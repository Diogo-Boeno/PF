-- Procedural gait driven by ProceduralModule (Roox4).
-- Poles are already set on the IKControls in the rig, so nothing here touches them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProceduralModule = require(ReplicatedStorage.Shared.Modules.ProceduralModule)

local character = script.Parent
local root = character:WaitForChild("HumanoidRootPart") :: BasePart
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local targets = character:WaitForChild("Targets")
local raycastParts = character:WaitForChild("RaycastParts")
local alignOrientation = root:WaitForChild("AlignOrientation") :: AlignOrientation

-- Measured from the rig: the IK chain reaches 2.08 studs with the hip 0.5 above
-- the ground, leaving about 2.0 studs of horizontal travel. Stride and trigger
-- distance are fractions of that and cannot grow past it.
local STEP_DISTANCE = 1.6
local STEP_FORWARD = 1.6
local STEP_HEIGHT = 0.5

-- Cycle timing is solved from speed instead of fixed, which is what lets this
-- rig keep up at WalkSpeed 16: stride is capped by leg length, so the only way
-- to cover more ground per second is to cycle faster.
--
-- MIN_PHASE is a readability floor, not a physical one. Below roughly 60ms the
-- two diagonal pairs land close enough together that the eye reads them as one
-- event, and the gait stops looking like a gait. Clamping there trades a little
-- foot slip for an alternation you can actually see.
local MIN_PHASE = 0.07
local MAX_PHASE = 0.18

-- Portion of a phase the foot spends in the air.
local SWING_RATIO = 0.5

-- Below this the body counts as standing still and the legs settle into a
-- fixed idle pose instead of holding wherever the last stride left them.
local IDLE_SPEED = 0.5

-- Settling uses a small trigger distance so a foot only a little off its rest
-- spot still corrects, and no forward throw so it lands straight underneath.
local SETTLE_DISTANCE = 0.15
local SETTLE_WAIT = 0.06

-- Fast cycles need a short smoothing window, otherwise consecutive steps blur
-- together and the feet read as floating.
local IK_SMOOTH_TIME = 0.03

local rayCastParams = RaycastParams.new()
rayCastParams.FilterDescendantsInstances = { character }
rayCastParams.FilterType = Enum.RaycastFilterType.Exclude

for _, v in ipairs(targets:GetChildren()) do
	if v:IsA("BasePart") then
		v.Transparency = 1
	end
end

for _, v in ipairs(raycastParts:GetChildren()) do
	if v:IsA("BasePart") then
		v.Transparency = 1
	end
end

for _, ik in ipairs(humanoid:GetChildren()) do
	if ik:IsA("IKControl") then
		ik.SmoothTime = IK_SMOOTH_TIME
	end
end

-- Body tilt is driven here, so the Humanoid has to stop competing for it.
humanoid.AutoRotate = false

if not alignOrientation.Attachment0 then
	local attachment = Instance.new("Attachment")
	attachment.Name = "AlignAttachment"
	attachment.Parent = root
	alignOrientation.Attachment0 = attachment
end

alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
alignOrientation.RigidityEnabled = false
alignOrientation.Responsiveness = 50

-- Resolved once at boot: a folder replicates before its children do, so looking
-- a leg up mid-cycle can hand back nil on the first frames after spawning.
local LEG_NAMES = { "FrontLeft", "FrontRight", "RearLeft", "RearRight" }
local OFFBEAT_LEGS = { "FrontRight", "RearLeft" }

local legs: { [string]: { target: BasePart, rayPart: BasePart } } = {}

for _, name in LEG_NAMES do
	local target = targets:WaitForChild(name) :: BasePart
	legs[name] = {
		target = target,
		rayPart = raycastParts:WaitForChild(name) :: BasePart,
	}
	target:SetAttribute("PreviousPos", target.Position)
end

-- Every leg drifts from the body at the same rate, so left alone all four cross
-- the trigger distance on the same frame and the alternation collapses into one
-- shared movement. Nudging one diagonal pair's reference point puts it half a
-- stride out of phase -- the foot itself does not move, only the point the
-- module measures against.
local function desync()
	for _, name in OFFBEAT_LEGS do
		local target = legs[name].target
		local previous = target:GetAttribute("PreviousPos") :: Vector3
		target:SetAttribute("PreviousPos", previous - root.CFrame.LookVector * (STEP_FORWARD * 0.5))
	end
end

local function step(name: string, stepDistance: number, stepForward: number, stepWait: number)
	local leg = legs[name]

	ProceduralModule:IkLegStep(
		leg.target,
		leg.rayPart,
		root,
		stepDistance,
		stepForward,
		STEP_HEIGHT,
		stepWait,
		rayCastParams
	)
end

local function stride(phase: number)
	local swing = phase * SWING_RATIO

	step("FrontLeft", STEP_DISTANCE, STEP_FORWARD, swing)
	step("RearRight", STEP_DISTANCE, STEP_FORWARD, swing)
	task.wait(phase)

	step("FrontRight", STEP_DISTANCE, STEP_FORWARD, swing)
	step("RearLeft", STEP_DISTANCE, STEP_FORWARD, swing)
	task.wait(phase)
end

-- Runs once when the body stops: pulls every foot back under its raycast part,
-- so idle is always the same pose rather than wherever the last stride ended.
local function settle()
	step("FrontLeft", SETTLE_DISTANCE, 0, SETTLE_WAIT)
	step("RearRight", SETTLE_DISTANCE, 0, SETTLE_WAIT)
	task.wait(SETTLE_WAIT * 2)

	step("FrontRight", SETTLE_DISTANCE, 0, SETTLE_WAIT)
	step("RearLeft", SETTLE_DISTANCE, 0, SETTLE_WAIT)
	task.wait(SETTLE_WAIT * 2)
end

local function horizontalSpeed(): number
	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

-- Heading is remembered so the body holds its last facing when standing still,
-- instead of snapping to whatever a zero move vector resolves to.
local heading = 0

RunService.Heartbeat:Connect(function()
	local moveDirection = humanoid.MoveDirection
	if moveDirection.Magnitude > 0.01 then
		heading = math.atan2(-moveDirection.X, -moveDirection.Z)
	end

	local rayCast = workspace:Raycast(root.Position, Vector3.new(0, -1000, 0), rayCastParams)
	local floorRotation = CFrame.identity

	if rayCast then
		-- Measured against world up, not the body's current up: feeding the
		-- current tilt back into the calculation makes it drift.
		floorRotation = ProceduralModule:getRotationBetween(Vector3.yAxis, rayCast.Normal)
	end

	alignOrientation.CFrame = floorRotation * CFrame.fromOrientation(0, heading, 0)
end)

local moving = false

while true do
	local speed = horizontalSpeed()

	if speed > IDLE_SPEED then
		if not moving then
			moving = true
			-- Settling put both pairs back in sync, so the offbeat has to be
			-- re-established every time the body starts moving again.
			desync()
		end

		stride(math.clamp(STEP_FORWARD / (2 * speed), MIN_PHASE, MAX_PHASE))
	else
		if moving then
			moving = false
			settle()
		end

		task.wait(MAX_PHASE)
	end
end
