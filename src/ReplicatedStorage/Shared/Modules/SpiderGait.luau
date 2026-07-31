--!strict
-- Procedural four-legged gait. Drives a rig's IK targets from raycasts against
-- the world and floats the body over the mean foot height, so the legs react to
-- terrain instead of replaying a canned animation.
--
-- Purely cosmetic: nothing here touches the HumanoidRootPart, so physics,
-- collision and replication are untouched. Body motion is written to the root
-- Motor6D's C0 — not Transform, which the Animator rewrites every frame.
--
--   local rig = SpiderGait.create(character)   -- yields; call from task.spawn
--   RunService:BindToRenderStep(name, Enum.RenderPriority.Character.Value + 1, function(dt)
--       SpiderGait.step(rig, dt)
--   end)
--
-- One rule holds the whole thing together: feet are a function of the physics
-- root only, and the body is a function of the feet only along the up axis.
-- Feeding the rendered body position back into the raycasts, or letting the body
-- chase the feet horizontally, collapses the rig onto itself.
--
-- Expected hierarchy (names are load-bearing):
--
--   Model
--   ├── HumanoidRootPart, Torso, Humanoid
--   ├── Targets/<leg>          rig's own IK goal; only read, never moved
--   ├── RaycastParts/<leg>     rest marker; sampled once to define the leg's stance
--   └── Humanoid/<leg>_IKControl

local Workspace = game:GetService("Workspace")

local SpiderGait = {}

local LEG_NAMES = { "FrontLeft", "FrontRight", "RearLeft", "RearRight" }

-- Diagonal pairs. A leg may only lift while the opposite pair is fully planted,
-- which is what keeps the rig statically stable instead of belly-flopping.
local LEG_GROUP: { [string]: number } = {
	FrontLeft = 1,
	RearRight = 1,
	FrontRight = 2,
	RearLeft = 2,
}

-- Step trigger as a fraction of the rig's own stance radius, not a fixed number
-- of studs: a threshold that ignores the rig's scale either never fires or fires
-- so often that the swing never completes, which reads as twitching in place.
local STEP_RATIO = 0.8
local MIN_STEP_DISTANCE = 0.4 -- floor for rigs whose markers sit near the centre
local STEP_TIME = 0.14 -- seconds a step takes end to end
local STEP_PREDICT = 0.25 -- seconds of body velocity baked into the landing spot

-- Arc height scales with the length of the step being taken. A fixed height
-- makes short corrective steps look like the rig is stamping, and long strides
-- look like it is skating.
local STEP_HEIGHT_RATIO = 0.45
local MIN_STEP_HEIGHT = 0.25
local MAX_STEP_HEIGHT = 2.5

local RAY_UP = 3 -- ray starts this far above the stance point
local RAY_DOWN = 8 -- and reaches this far below it
local MAX_LIFT = 4 -- clamp on body rise/fall, for when a leg loses the ground
local BODY_SMOOTH = 12 -- exponential smoothing rate for the body; higher is snappier
local CALIBRATE_TIME = 2 -- seconds for the rest height to converge; slow on purpose
local CHILD_TIMEOUT = 5 -- a replicating character can lag behind its own spawn

export type Leg = {
	name: string,
	group: number,
	target: BasePart, -- our own part in Workspace, never the rig's
	rigTarget: BasePart, -- the rig's original, restored on destroy
	restOffset: Vector3, -- stance position in root space, frozen at create
	control: IKControl,
	planted: Vector3, -- world position the foot is resting at
	normal: Vector3, -- surface normal under that foot
	groundOffset: number, -- last sampled ground height relative to stance, along up
	grounded: boolean, -- false when the last probe found nothing below
	from: Vector3, -- step origin
	to: Vector3, -- step destination
	height: number, -- arc height of the step in progress
	alpha: number, -- step progress; >= 1 means planted
}

export type Rig = {
	model: Model,
	root: BasePart,
	torso: BasePart,
	humanoid: Humanoid,
	joint: Motor6D?, -- nil disables body motion but keeps the legs working
	legs: { Leg },
	rayParams: RaycastParams,
	restDrop: number, -- how far below the root the ground sits at rest, along up
	stepDistance: number, -- derived from the stance radius at create
	probe: number, -- round-robin index of the leg being re-sampled this frame
	baseC0: CFrame, -- the joint's untouched rest C0, restored on destroy
	pose: CFrame, -- smoothed body C0
	primed: boolean, -- first step snaps instead of easing in from the rest pose
	hijacked: number, -- frames where something rewrote our C0; see diagnose
}

-- Returns the CFrame rotation that takes vector `u` onto vector `v`.
-- Credit: @EgoMoose (Roblox)
local function getRotationBetween(u: Vector3, v: Vector3): CFrame
	local dot = u:Dot(v)
	if dot > 0.99999 then
		return CFrame.identity
	elseif dot < -0.99999 then
		return CFrame.fromAxisAngle(Vector3.xAxis, math.pi)
	end
	return CFrame.fromAxisAngle(u:Cross(v), math.acos(dot))
end

-- The Motor6D that carries the whole visual body. Standard rigs name it
-- RootJoint, but match on the parts so a renamed joint still works.
local function findRootJoint(model: Model, root: BasePart, torso: BasePart): Motor6D?
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Part0 == root and descendant.Part1 == torso then
			return descendant
		end
	end
	return nil
end

-- Our own IK goal, living in Workspace and owned by this client alone.
--
-- The rig's Targets folder is left untouched on purpose: anchoring a part that
-- shares an assembly with the HumanoidRootPart freezes the whole character, and
-- an unanchored one just falls. A detached part sidesteps both. CanQuery is off
-- so the leg raycasts never hit our own markers.
local function makeTarget(name: string, position: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = name .. "_GaitTarget"
	part.Size = Vector3.one * 0.2
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Position = position
	part.Parent = Workspace
	return part
end

-- Resolves the rig hierarchy and drops the feet onto the ground.
-- Yields: waits on children, since a character can replicate before its parts do.
function SpiderGait.create(model: Model): Rig?
	local root = model:WaitForChild("HumanoidRootPart", CHILD_TIMEOUT) :: BasePart?
	local torso = model:WaitForChild("Torso", CHILD_TIMEOUT) :: BasePart?
	local humanoid = model:WaitForChild("Humanoid", CHILD_TIMEOUT) :: Humanoid?
	local targets = model:WaitForChild("Targets", CHILD_TIMEOUT)
	local restParts = model:WaitForChild("RaycastParts", CHILD_TIMEOUT)

	if not root or not torso or not humanoid or not targets or not restParts then
		warn(`[SpiderGait] {model:GetFullName()}: missing HumanoidRootPart/Torso/Humanoid/Targets/RaycastParts`)
		return nil
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { model }
	rayParams.RespectCanCollide = true

	local joint = findRootJoint(model, root, torso)
	if not joint then
		warn(`[SpiderGait] {model:GetFullName()}: no Motor6D linking HumanoidRootPart to Torso; body motion disabled`)
	end

	local rig: Rig = {
		model = model,
		root = root,
		torso = torso,
		humanoid = humanoid,
		joint = joint,
		legs = {},
		rayParams = rayParams,
		-- replaced below by a measurement; this is only the fallback
		restDrop = -(humanoid.HipHeight + root.Size.Y * 0.5),
		stepDistance = MIN_STEP_DISTANCE,
		probe = 0,
		baseC0 = if joint then joint.C0 else CFrame.identity,
		pose = if joint then joint.C0 else CFrame.identity,
		primed = false,
		hijacked = 0,
	}

	local rootCF = root.CFrame
	local up = rootCF.UpVector
	local groundedLegs = 0
	local dropSum = 0

	for _, name in LEG_NAMES do
		local rigTarget = targets:FindFirstChild(name) :: BasePart?
		local rest = restParts:FindFirstChild(name) :: BasePart?
		local control = humanoid:FindFirstChild(name .. "_IKControl") :: IKControl?

		if not rigTarget or not rest or not control then
			warn(`[SpiderGait] {model:GetFullName()}: leg "{name}" is incomplete`)
			return nil
		end

		rest.Transparency = 1
		rest.CanCollide = false

		local leg: Leg = {
			name = name,
			group = LEG_GROUP[name],
			target = makeTarget(name, rest.Position),
			rigTarget = rigTarget,
			restOffset = rootCF:PointToObjectSpace(rest.Position),
			control = control,
			planted = rest.Position,
			normal = up,
			groundOffset = 0,
			grounded = false,
			from = rest.Position,
			to = rest.Position,
			height = MIN_STEP_HEIGHT,
			alpha = 1,
		}

		local hit = Workspace:Raycast(rest.Position + up * RAY_UP, -up * (RAY_UP + RAY_DOWN), rayParams)
		if hit then
			leg.planted = hit.Position
			leg.normal = hit.Normal
			leg.from = hit.Position
			leg.to = hit.Position
			leg.groundOffset = (hit.Position - rest.Position):Dot(up)
			leg.grounded = true
			groundedLegs += 1
			dropSum += (hit.Position - root.Position):Dot(up)
		end
		leg.target.Position = leg.planted

		control.Target = leg.target
		-- Optional: without a pole the solver is free to fold the knee inward
		control.Pole = root:FindFirstChild(name .. "_Pole")
		control.Enabled = true

		table.insert(rig.legs, leg)
	end

	-- Measure the rest height off the rig standing there, rather than trusting
	-- HipHeight: custom rigs routinely report ~0 while the root floats well clear
	-- of the ground, and the error goes straight into the body offset.
	if groundedLegs > 0 then
		rig.restDrop = dropSum / groundedLegs
	end

	local radiusSum = 0
	for _, leg in rig.legs do
		radiusSum += Vector2.new(leg.restOffset.X, leg.restOffset.Z).Magnitude
	end
	rig.stepDistance = math.max(radiusSum / #rig.legs * STEP_RATIO, MIN_STEP_DISTANCE)

	return rig
end

-- Advances one frame. Cheap enough to run for every visible rig.
function SpiderGait.step(rig: Rig, dt: number)
	local root = rig.root
	if not root.Parent then
		return
	end

	local rootCF = root.CFrame
	local up = rootCF.UpVector
	local velocity = root.AssemblyLinearVelocity
	local legs = rig.legs
	local count = #legs

	-- Re-probe one leg per frame. The ground under a foot changes far slower
	-- than the frame rate, so raycasting all four every frame costs 4x for no
	-- visible gain. Between probes the last hit rides along with the stance,
	-- which tracks flat and gently sloped ground closely.
	rig.probe = rig.probe % count + 1
	local probed = legs[rig.probe]
	local probeStance = rootCF * probed.restOffset
	local probeHit = Workspace:Raycast(probeStance + up * RAY_UP, -up * (RAY_UP + RAY_DOWN), rig.rayParams)
	if probeHit then
		probed.groundOffset = (probeHit.Position - probeStance):Dot(up)
		probed.normal = probeHit.Normal
		probed.grounded = true
	else
		probed.grounded = false
	end

	-- Scalars rather than tables: this runs per rig per frame
	local footSum = Vector3.zero
	local normalSum = Vector3.zero
	local airborne1, airborne2 = false, false
	local gap1, gap2 = 0, 0

	for _, leg in legs do
		if leg.alpha < 1 then
			leg.alpha = math.min(leg.alpha + dt / STEP_TIME, 1)
			local t = leg.alpha
			local eased = t * t * (3 - 2 * t) -- smoothstep: eases both ends of the swing
			leg.target.Position = leg.from:Lerp(leg.to, eased) + up * math.sin(t * math.pi) * leg.height

			if leg.alpha >= 1 then
				leg.planted = leg.to
			elseif leg.group == 1 then
				airborne1 = true
			else
				airborne2 = true
			end
		else
			leg.target.Position = leg.planted

			if leg.grounded then
				local ground = rootCF * leg.restOffset + up * leg.groundOffset
				local gap = (ground - leg.planted).Magnitude
				if leg.group == 1 then
					gap1 = math.max(gap1, gap)
				else
					gap2 = math.max(gap2, gap)
				end
			end
		end

		footSum += leg.planted
		normalSum += leg.normal
	end

	-- One diagonal swings at a time, and it is the pair that has fallen furthest
	-- behind — never simply the first one in the list. Letting list order decide
	-- starves the other pair: the leading group re-triggers the instant it lands
	-- and the trailing legs drag indefinitely.
	if not airborne1 and not airborne2 then
		local leading = if gap1 >= gap2 then 1 else 2
		if math.max(gap1, gap2) > rig.stepDistance then
			for _, leg in legs do
				if leg.group == leading and leg.grounded then
					local ground = rootCF * leg.restOffset + up * leg.groundOffset
					leg.from = leg.planted
					-- Land ahead of where the ground is now, so the cadence keeps
					-- up with the body instead of chasing it
					leg.to = ground + velocity * STEP_PREDICT
					leg.height =
						math.clamp((leg.to - leg.from).Magnitude * STEP_HEIGHT_RATIO, MIN_STEP_HEIGHT, MAX_STEP_HEIGHT)
					leg.alpha = 0
				end
			end
		end
	end

	local joint = rig.joint
	if not joint then
		return
	end

	local footMean = footSum / count
	-- Averaging four normals reads slopes and steps that a single centre ray misses
	local normal = if normalSum.Magnitude > 1e-4 then normalSum.Unit else up

	-- Vertical only. The body must never chase the feet horizontally: planted
	-- feet trail behind a walking rig, so following their centroid drags the
	-- torso backwards onto them.
	local drop = (footMean - root.Position):Dot(up)

	-- Self-calibrating rest height. Measuring once at spawn samples whatever pose
	-- the rig happened to be in mid-drop and bakes that error in forever; a slow
	-- average settles on the real standing height and keeps lift centred on zero.
	rig.restDrop += (drop - rig.restDrop) * math.min(dt / CALIBRATE_TIME, 1)
	local lift = math.clamp(drop - rig.restDrop, -MAX_LIFT, MAX_LIFT)

	-- getRotationBetween works in world space; conjugate it into the root's frame
	local rotation = rootCF.Rotation
	local localTilt = rotation:Inverse() * getRotationBetween(up, normal) * rotation

	-- Motor6D: Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse().
	-- We write C0 rather than Transform because the Animator owns Transform and
	-- rewrites it every frame — anything we put there is gone before it renders.
	-- Pre-multiplying the rest C0 applies our offset in the root's frame, so zero
	-- lift and zero tilt reproduce the rig's untouched rest pose exactly.
	local desired = CFrame.new(0, lift, 0) * localTilt * rig.baseC0

	if rig.primed and not joint.C0:FuzzyEq(rig.pose, 1e-3) then
		rig.hijacked += 1
	end

	local blend = if rig.primed then 1 - math.exp(-BODY_SMOOTH * dt) else 1
	rig.primed = true
	rig.pose = rig.pose:Lerp(desired, blend)
	joint.C0 = rig.pose
end

local function fmtVector(v: Vector3): string
	return string.format("%.2f,%.2f,%.2f", v.X, v.Y, v.Z)
end

-- Dumps every number the gait runs on. Read it in this order:
--   stanceRadius  how far the feet sit from the centre; stepDistance derives
--                 from it, and everything about cadence follows from that.
--   stepGap       what the step gate compares against stepDistance.
--   ray           NO HIT means the leg never updates and drags behind forever.
--   hijacked      nonzero means something rewrites Motor6D.C0 after us.
--   state         Freefall while standing still means the Humanoid cannot find
--                 the ground, which shakes the body and poisons every other number.
function SpiderGait.diagnose(rig: Rig)
	local root = rig.root
	local rootCF = root.CFrame
	local up = rootCF.UpVector
	local lines = {
		`[SpiderGait] {rig.model.Name} speed={string.format("%.2f", root.AssemblyLinearVelocity.Magnitude)} `
			.. `hijacked={rig.hijacked} joint={if rig.joint then rig.joint.Name else "NONE"} `
			.. `rootAnchored={root.Anchored} state={rig.humanoid:GetState().Name} `
			.. `hipHeight={string.format("%.2f", rig.humanoid.HipHeight)}`,
	}

	local footSum = Vector3.zero
	local radiusSum = 0

	for _, leg in rig.legs do
		local ground = rootCF * leg.restOffset + up * leg.groundOffset

		table.insert(
			lines,
			`  {leg.name} g{leg.group} alpha={string.format("%.2f", leg.alpha)}`
				.. ` stanceLocal=({fmtVector(leg.restOffset)})`
				.. ` plantedLocal=({fmtVector(rootCF:PointToObjectSpace(leg.planted))})`
				-- the value the step gate actually compares against rig.stepDistance
				.. ` stepGap={string.format("%.2f", (ground - leg.planted).Magnitude)}`
				.. ` stepLen={string.format("%.2f", (leg.to - leg.from).Magnitude)}`
				.. ` arc={string.format("%.2f", leg.height)}`
				.. ` ray={if leg.grounded then "ok" else "NO HIT"}`
				.. ` ikOn={leg.control.Enabled} ikTarget={if leg.control.Target == leg.target then "ok" else "WRONG"}`
		)

		footSum += leg.planted
		radiusSum += Vector2.new(leg.restOffset.X, leg.restOffset.Z).Magnitude
	end

	local count = #rig.legs
	local footMean = footSum / count
	local drop = (footMean - root.Position):Dot(up)

	-- How far the feet are spread apart. If this collapses toward zero the rig is
	-- standing on a single point, whatever the maths downstream says.
	local spread = 0
	for _, leg in rig.legs do
		spread += (leg.planted - footMean).Magnitude
	end

	table.insert(
		lines,
		`  body drop={string.format("%.2f", drop)} restDrop={string.format("%.2f", rig.restDrop)}`
			.. ` lift={string.format("%.2f", math.clamp(drop - rig.restDrop, -MAX_LIFT, MAX_LIFT))}`
			.. ` stepDistance={string.format("%.2f", rig.stepDistance)}`
			-- horizontal distance from the root, which is what drives stepDistance
			.. ` stanceRadius={string.format("%.2f", radiusSum / count)}`
			.. ` footSpread={string.format("%.2f", spread / count)}`
			-- poseOffset is what we ask the body to do; torsoLocal is what the
			-- engine actually rendered. They must track each other.
			.. ` poseOffset={fmtVector((rig.baseC0:Inverse() * rig.pose).Position)}`
			.. ` torsoLocal=({fmtVector(rootCF:PointToObjectSpace(rig.torso.Position))})`
	)

	print(table.concat(lines, "\n"))
end

function SpiderGait.destroy(rig: Rig)
	for _, leg in rig.legs do
		leg.control.Enabled = false
		leg.control.Target = leg.rigTarget
		leg.target:Destroy()
	end
	if rig.joint then
		rig.joint.C0 = rig.baseC0
	end
end

return SpiderGait
