--!strict
-- Only the owner plays these; Animator replicates them to everyone else.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Data.Weapons)
local Net = require(ReplicatedStorage.Shared.Framework.Net)
local RaycastHitbox = require(ReplicatedStorage.RaycastHitbox)
local WeaponController = require(script.Parent.WeaponController)
local FxController = require(script.Parent.FxController)
local MovementController = require(script.Parent.MovementController)

local FADE = 0.1
local HEAVY_KEY = Enum.KeyCode.R
local GRIP_KEY = Enum.KeyCode.Y
local GUARD_KEY = Enum.KeyCode.F
local DASH_KEY = Enum.KeyCode.Q

-- Animation events authored on every attack animation
local START_MARKER = "Start"
local END_MARKER = "End"

-- Optional third event: where the blade lights up to say a parry would land. Authored,
-- not derived — the window is counted from the defender's F press, so the tell has to
-- come BEFORE the hitbox opens, and only the animation knows how much before.
-- No `Tell` in an animation means that attack simply cannot be read. That is a design
-- choice per move, not an error.
local TELL_MARKER = "Tell"

-- Read by Animate.client, which otherwise keeps filling the joints an attack skips
local ATTACK_LOCK = "AttackLock"

-- Above the Core that Animate.client plays
local LOCOMOTION_PRIORITY = Enum.AnimationPriority.Action

-- An attack is never overridden by anything. This is a competitive game: a swing that
-- can be visually diluted mid-frame is a swing the opponent cannot read reliably.
local SWING_PRIORITY = Enum.AnimationPriority.Action4

-- Reactions ride over a held block and never fight a swing, because anything that
-- triggers one has already cancelled the swing outright.
local REACTION_PRIORITY = Enum.AnimationPriority.Action3

-- Below reactions, deliberately. A held block is a sustained pose, so sharing the
-- attack's priority let it swallow both the ParryStart flourish and the parry impact —
-- the two animations that most need to be seen.
local BLOCK_PRIORITY = Enum.AnimationPriority.Action2

type Kind = "swing" | "flourish" | "heavy" | "aerial" | "parried" | "uppercut"

local player = Players.LocalPlayer

-- One Animation instance per id, reused across equips
local assets: { [string]: Animation } = {}

local humanoid: Humanoid? = nil
local animator: Animator? = nil

local idleTrack: AnimationTrack? = nil
local walkTrack: AnimationTrack? = nil

-- Class swings plus the universal flourish, in chain order
local chain: { AnimationTrack } = {}
local heavyTrack: AnimationTrack? = nil
local aerialTrack: AnimationTrack? = nil
local blockTrack: AnimationTrack? = nil
local parryTrack: AnimationTrack? = nil
local dashTracks: { [string]: AnimationTrack } = {}
local dashCancelTrack: AnimationTrack? = nil
local dashClip: AnimationTrack? = nil
local uppercutTrack: AnimationTrack? = nil

-- Universal locomotion, loaded per character: crouching is not a weapon stance
local crouchIdleTrack: AnimationTrack? = nil
local crouchWalkTrack: AnimationTrack? = nil
local uppercutReadyAt = 0
local parriedTracks: { [string]: AnimationTrack } = {}
local kindOf: { [AnimationTrack]: Kind } = {}

local guarding = false

-- F stays remembered while an attack runs, so the parry fires the instant the swing
-- ends instead of demanding a frame-perfect press right after it
local guardHeld = false

-- Forward declared: onAttackEnded has to reach it, and it is defined further down
local startGuard: () -> ()

local comboIndex = 0
local current: AnimationTrack? = nil
local activeKind: Kind? = nil
local queued = false

-- Debug only: an attack that ends without this is missing its Start marker
local openedHitbox = false

-- Set when we cut an attack ourselves. An interrupted swing legitimately never
-- reaches its Start marker, so warning about it would cry wolf every stagger.
local cancelled = false

-- Animations that carry a real `Tell` marker. Those never use the `hitAt` fallback,
-- because an authored event always beats a number in a config.
local hasTellMarker: { [string]: boolean } = {}
local tellToken = 0

-- Rebuilt only when the mounted model changes, not per attack
local hitbox: any = nil
local hitboxModel: Model? = nil

-- Shaped hitboxes: one hit per target per attack, cleared when the window opens
local shapeHits: { [Humanoid]: boolean } = {}
local sweepConnection: RBXScriptConnection? = nil
local sweepBox: BoxHandleAdornment? = nil

-- Built once per character and toggled, rather than instanced per dash
local dashForce: LinearVelocity? = nil
local dashToken = 0

-- Per-frame correction that keeps a juggled body at the shared hang height
local hoverConnection: RBXScriptConnection? = nil

-- When the last attack ended, not started: chaining must not read as idle time
local lastAttackEnd = 0

-- One gate per attack, never shared. Sharing is what made a heavy cool down the M1
-- and the endlag cool down the aerial.
local chainReadyAt = 0
local heavyReadyAt = 0
local aerialReadyAt = 0
local dashReadyAt = 0

-- While this is in the future the dash owns the character: no attack starts, and
-- dash cannot start during one either. The two are never simultaneous.
local dashUntil = 0

-- Cancelling refunds the dash, once. `fromRefund` marks the dash that spent it, and
-- that one earns nothing back — otherwise cancel-dash-cancel is free movement forever.
local refundAvailable = false
local fromRefund = false

-- The one lock that is meant to stop everything: being parried is a stagger
local staggerUntil = 0

-- Suspended by an uppercut. Being up here is not the same as jumping: the aerial is
-- off and the normal chain answers M1, so the window is a fight and not a dive.
local juggleUntil = 0

-- Captured on spawn so the juggle can restore it; WalkSpeed is borrowed, not owned
local baseWalkSpeed = 16

local connections: { RBXScriptConnection } = {}

local CombatController = {}

local function assetFor(id: string): Animation
	local asset = assets[id]
	if not asset then
		asset = Instance.new("Animation")
		asset.AnimationId = id
		assets[id] = asset
	end
	return asset
end

local function currentGrip(): string
	local grip = player:GetAttribute(Config.gripAttribute)
	return if type(grip) == "string" then grip else Config.defaultGrip
end

local function classFor(weaponId: number): any?
	local entry = Config.byId[weaponId]
	if not entry then
		return nil
	end

	local name = entry.classes[currentGrip()]
	if not name then
		return nil
	end

	local class = Config.classes[name]
	if not class then
		warn(`[CombatController] "{entry.model}" names unknown class "{name}"`)
	end
	return class
end

local function stunned(): boolean
	return player:GetAttribute(Config.stunAttribute) == true
end

local function rootPart(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local Debug = Config.debugHitbox

local function debugging(): boolean
	local override = workspace:GetAttribute(Debug.attribute)
	if type(override) == "boolean" then
		return override
	end
	return Debug.enabled
end

-- Adorned to Terrain, whose CFrame is identity, so this CFrame is world space
local function drawBox(cf: CFrame, size: Vector3, label: string, hits: number)
	if not debugging() then
		return
	end

	local box = Instance.new("BoxHandleAdornment")
	box.Name = "HitboxDebug"
	box.Adornee = workspace.Terrain
	box.CFrame = cf
	box.Size = size
	box.Color3 = Debug.color
	box.Transparency = Debug.transparency
	box.ZIndex = 0
	box.Parent = workspace.Terrain

	print(`[Hitbox] {label}: {hits} hit(s)`)
	task.delay(Debug.lifetime, function()
		box:Destroy()
	end)
end

local function setAttackLock(on: boolean)
	local character = player.Character
	if character then
		character:SetAttribute(ATTACK_LOCK, on)
	end
end

-- The library strips the metatable when it finally drops a hitbox (HitboxCaster:237),
-- so a stale reference is a plain table with no methods left. Clearing ours first
-- means a throw can never strand it, and the type check covers the already-stripped case.
local function releaseHitbox()
	local stale = hitbox
	hitbox = nil
	hitboxModel = nil

	if stale and type(stale.Destroy) == "function" then
		stale:Destroy()
	end
end

local function ensureHitbox(): any?
	local model = WeaponController.mountedFor(player)
	local character = player.Character
	if not model or not character then
		return nil
	end

	if model == hitboxModel and hitbox then
		return hitbox
	end
	releaseHitbox()

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local new = RaycastHitbox.new(model)
	new.RaycastParams = params
	-- One switch for rays and boxes, so nothing stays drawn after the flag is off
	new.Visualizer = debugging()
	new.DebugLog = debugging()
	new.OnHit:Connect(function(_part: BasePart, hit: Humanoid)
		Net.FireServer("WeaponHit", hit, activeKind)
		if debugging() then
			print(`[Hitbox] {activeKind}: hit {hit.Parent and hit.Parent.Name or "?"}`)
		end
	end)

	hitbox = new
	hitboxModel = model
	return new
end

-- The library gave dedup for free via HitStop; shaped hitboxes keep their own list
local function report(hit: Humanoid, kind: Kind): boolean
	if shapeHits[hit] then
		return false
	end
	shapeHits[hit] = true
	Net.FireServer("WeaponHit", hit, kind)
	return true
end

local function humanoidOf(part: BasePart): Humanoid?
	local parent = part.Parent
	return if parent then parent:FindFirstChildOfClass("Humanoid") else nil
end

local function overlapParams(character: Model): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	return params
end

local function queryBox(spec: any, kind: Kind): (CFrame?, number)
	local root, character = rootPart(), player.Character
	if not root or not character then
		return nil, 0
	end

	local origin = root.CFrame * CFrame.new(spec.offset)
	local hits = 0

	for _, part in workspace:GetPartBoundsInBox(origin, spec.size, overlapParams(character)) do
		local hit = humanoidOf(part)
		if hit and report(hit, kind) then
			hits += 1
		end
	end

	return origin, hits
end

local function pointHit(spec: any, kind: Kind)
	local origin, hits = queryBox(spec, kind)
	if origin then
		drawBox(origin, spec.size, kind, hits)
	end
end

-- Blockcast stops at the first thing it meets, which is what a thrust should do:
-- it impales one target and a wall still blocks it
local function castHit(spec: any, kind: Kind)
	local root, character = rootPart(), player.Character
	if not root or not character then
		return
	end

	local origin = root.CFrame * CFrame.new(spec.offset)
	local hits = 0

	-- A shapecast that starts already overlapping reports nothing, so point blank
	-- has to be answered by an overlap test before the cast is worth running
	for _, part in workspace:GetPartBoundsInBox(origin, spec.size, overlapParams(character)) do
		local hit = humanoidOf(part)
		if hit and report(hit, kind) then
			hits += 1
		end
	end

	if hits == 0 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }

		local result = workspace:Blockcast(origin, spec.size, origin.LookVector * spec.range, params)
		if result then
			local hit = humanoidOf(result.Instance)
			if hit and report(hit, kind) then
				hits = 1
			end
		end
	end

	-- Draw the volume actually swept, not the box at its start
	drawBox(origin * CFrame.new(0, 0, -spec.range / 2), spec.size + Vector3.new(0, 0, spec.range), kind, hits)
end

local function stopSweep()
	if sweepConnection then
		sweepConnection:Disconnect()
		sweepConnection = nil
	end
	if sweepBox then
		sweepBox:Destroy()
		sweepBox = nil
	end
end

local function startSweep(spec: any, kind: Kind)
	stopSweep()

	if debugging() then
		local box = Instance.new("BoxHandleAdornment")
		box.Name = "HitboxDebug"
		box.Adornee = workspace.Terrain
		box.Size = spec.size
		box.Color3 = Debug.color
		box.Transparency = Debug.transparency
		box.ZIndex = 0
		box.Parent = workspace.Terrain
		sweepBox = box
	end

	-- One adornment tracked across the window instead of one per frame
	sweepConnection = RunService.Heartbeat:Connect(function()
		local origin, hits = queryBox(spec, kind)
		if not origin then
			return
		end
		if sweepBox then
			sweepBox.CFrame = origin
		end
		if hits > 0 and debugging() then
			print(`[Hitbox] {kind}: {hits} hit(s)`)
		end
	end)
end

local function stopHitbox()
	stopSweep()
	-- Same stripped-metatable case as releaseHitbox: a dropped hitbox keeps no methods
	if hitbox and type(hitbox.HitStop) == "function" then
		hitbox:HitStop()
	end
end

local function stopHover()
	if hoverConnection then
		hoverConnection:Disconnect()
		hoverConnection = nil
	end
end

local function stopDash()
	if dashForce then
		dashForce.Enabled = false
	end
	stopHover()
	-- Invalidates any delayed stop still pending for an older dash
	dashToken += 1
end

-- A Humanoid rewrites its own horizontal velocity every step, so a one-shot write to
-- AssemblyLinearVelocity is gone by the next frame. Held force is the only thing that
-- moves a character against its own controller.
local function applyImpulse(direction: Vector3, speed: number, vertical: number?, duration: number)
	local force, root = dashForce, rootPart()
	if not force or not root then
		return
	end

	local y = if vertical then vertical else root.AssemblyLinearVelocity.Y
	force.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	force.VectorVelocity = Vector3.new(direction.X * speed, y, direction.Z * speed)
	force.Enabled = true

	dashToken += 1
	local token = dashToken
	task.delay(duration, function()
		if dashToken == token then
			stopDash()
		end
	end)
end

local function startDash(aerial: any)
	local root = rootPart()
	if root then
		applyImpulse(root.CFrame.LookVector, aerial.dashSpeed, aerial.dashFall, aerial.dashTime)
	end
end

-- Class sets the shape, the weapon scales it. Resolved once per attack, so the
-- sweep's per-frame loop reads a table that is already final.
local function scaled(spec: any?, reach: number): any?
	if not spec or reach == 1 then
		return spec
	end
	return {
		shape = spec.shape,
		size = spec.size * reach,
		offset = spec.offset * reach,
		range = if spec.range then spec.range * reach else nil,
	}
end

-- No `hitbox` key means the attack cuts with the blade, same rule as everywhere else
local function hitboxSpecFor(kind: Kind): any?
	-- Both are body attacks, so no weapon lengthens them
	if kind == "flourish" then
		return Config.flourish.hitbox
	end
	if kind == "uppercut" then
		return Config.uppercut.hitbox
	end

	local id = player:GetAttribute(Config.attribute)
	if type(id) ~= "number" then
		return nil
	end

	local entry = Config.byId[id]
	local class = classFor(id)
	if not entry or not class then
		return nil
	end

	local reach = if type(entry.reach) == "number" then entry.reach else 1

	if kind == "heavy" then
		return scaled(if class.heavy then class.heavy.hitbox else nil, reach)
	end
	if kind == "aerial" then
		return scaled(if class.aerial then class.aerial.hitbox else nil, reach)
	end
	return nil
end

-- Played locally first so the swinger never hears its own attack late; the server
-- echoes it to everyone else
local function announceSwing(kind: Kind)
	if kind == "parried" then
		return
	end

	local root = rootPart()
	if root then
		FxController.play(kind, root.Position, player.Character)
	end
	Net.FireServer("Swung", kind)
end

local function startHitbox(kind: Kind)
	openedHitbox = true
	table.clear(shapeHits)
	announceSwing(kind)

	local spec = hitboxSpecFor(kind)
	if not spec then
		local active = ensureHitbox()
		if active then
			activeKind = kind
			active:HitStart()
		end
		return
	end

	if spec.shape == "point" then
		pointHit(spec, kind)
	elseif spec.shape == "cast" then
		castHit(spec, kind)
	elseif spec.shape == "sweep" then
		startSweep(spec, kind)
	else
		warn(`[Hitbox] {kind} declares unknown shape "{spec.shape}"`)
	end
end

local function clearTracks()
	-- Drop the queue first: Stop() below fires Stopped on every track
	queued = false
	current = nil
	activeKind = nil
	chainReadyAt = 0
	heavyReadyAt = 0
	aerialReadyAt = 0
	staggerUntil = 0
	dashUntil = 0
	stopDash()
	setAttackLock(false)
	releaseHitbox()

	local idle, walk = idleTrack, walkTrack
	idleTrack = nil
	walkTrack = nil

	if idle then
		idle:Stop(FADE)
		idle:Destroy()
	end
	if walk then
		walk:Stop(FADE)
		walk:Destroy()
	end

	guarding = false
	for track in kindOf do
		track:Stop(FADE)
		track:Destroy()
	end
	if blockTrack then
		blockTrack:Stop(FADE)
		blockTrack:Destroy()
	end
	if parryTrack then
		parryTrack:Stop(FADE)
		parryTrack:Destroy()
	end

	table.clear(kindOf)
	table.clear(chain)
	table.clear(parriedTracks)
	heavyTrack = nil
	aerialTrack = nil
	blockTrack = nil
	parryTrack = nil

	comboIndex = 0
end

local function crouching(): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute(Config.crouch.attribute) == true
end

local function stopLocomotion()
	for _, track in { idleTrack, walkTrack, crouchIdleTrack, crouchWalkTrack } do
		if track and track.IsPlaying then
			track:Stop(FADE)
		end
	end
end

local function updateLocomotion()
	local living = humanoid
	if not living then
		return
	end

	-- Crouch animations are universal and replace the class pair outright, because
	-- sneaking is a posture and not a way of holding a weapon
	local low = crouching()
	local idle = if low then crouchIdleTrack else idleTrack
	local walk = if low then crouchWalkTrack else walkTrack

	-- Silence the unused pair FIRST, and unconditionally. Unarmed there is no class
	-- pair at all, and bailing out before this left the crouch loop running with no
	-- way to stand back up until a weapon was equipped.
	for _, other in { idleTrack, walkTrack, crouchIdleTrack, crouchWalkTrack } do
		if other and other ~= idle and other ~= walk and other.IsPlaying then
			other:Stop(FADE)
		end
	end

	-- Unarmed and standing: nothing of ours should play, and Animate.client takes over
	if not idle or not walk then
		return
	end

	-- An attack owns the whole pose. Left running underneath, locomotion fills in
	-- every joint the attack does not animate, so the result stops matching the editor
	if current then
		return
	end

	-- MoveDirection is input, not physics: no residual drift to threshold against
	local moving = living.MoveDirection.Magnitude > 0
	local wanted = if moving then walk else idle
	local other = if moving then idle else walk

	if other.IsPlaying then
		other:Stop(FADE)
	end
	if not wanted.IsPlaying then
		wanted:Play(FADE)
	end
end

-- Per kind, because the tell has to come off whatever is actually going to hit you:
-- a blade for a swing, a foot for the flourish
local function fireTell(kind: Kind)
	local root, character = rootPart(), player.Character
	if not root or not character then
		return
	end

	local event = kind .. "Tell"
	FxController.play(event, root.Position, character)
	Net.FireServer("Swung", event)
end

-- Schedules the tell for animations with no authored `Tell` marker.
--
-- Timing comes from the class's `hitAt`, which is read off the editor. A run-time
-- measurement was tried and abandoned: markers do not fire on a weight-0 track, and
-- learning from the first real swing left that swing untelegraphed.
local function scheduleTell(track: AnimationTrack)
	local animation = track.Animation
	local id = if animation then animation.AnimationId else ""
	if id == "" or hasTellMarker[id] then
		return
	end

	local weaponId = player:GetAttribute(Config.attribute)
	local class = if type(weaponId) == "number" then classFor(weaponId) else nil
	local hitAt = class and class.hitAt
	if type(hitAt) ~= "number" then
		return
	end

	local lead = hitAt - Config.guard.parryWindow
	if lead <= 0 then
		return
	end

	local kind = kindOf[track]
	if not kind then
		return
	end

	tellToken += 1
	local token = tellToken
	task.delay(lead, function()
		if tellToken == token and current == track then
			fireTell(kind)
		end
	end)
end

local function play(track: AnimationTrack)
	local previous = current

	-- Reassigned before stopping, so the old track's Stopped sees it is no longer
	-- current and bails out instead of clearing state the new one just set
	current = track
	if previous and previous ~= track then
		previous:Stop(FADE)
	end

	openedHitbox = false
	cancelled = false
	stopLocomotion()
	setAttackLock(true)
	track:Play(FADE)

	-- Telegraph on the first frame of the windup, not when the blade goes live: a tell
	-- that arrives with the hitbox is not a tell
	local kind = kindOf[track]
	local character = player.Character
	if kind and character then
		FxController.highlight(kind, character)
		Net.FireServer("Telegraph", kind)
	end

	scheduleTell(track)
end

local function playNext()
	if #chain == 0 then
		return
	end

	if os.clock() - lastAttackEnd > Config.comboReset then
		comboIndex = 0
	end

	comboIndex = comboIndex % #chain + 1
	play(chain[comboIndex])
end

local function onAttackEnded(track: AnimationTrack)
	-- A teardown Stop fires this for tracks that were never the active one
	if current ~= track then
		return
	end

	current = nil
	activeKind = nil
	lastAttackEnd = os.clock()

	local kind = kindOf[track]

	-- The likeliest reason a hitbox "does not work" is the marker never being authored.
	-- A cancelled attack is not that, and warning about it would drown the real case.
	if debugging() and not openedHitbox and not cancelled and kind ~= "parried" then
		warn(`[Hitbox] {kind} ended without ever opening — no "{START_MARKER}" marker?`)
	end
	cancelled = false

	if kind == "flourish" then
		chainReadyAt = lastAttackEnd + Config.endlag
	elseif kind == "aerial" then
		aerialReadyAt = lastAttackEnd + Config.aerialCooldown
	elseif kind == "heavy" then
		heavyReadyAt = lastAttackEnd + Config.heavyCooldown
	elseif kind == "uppercut" then
		uppercutReadyAt = lastAttackEnd + Config.uppercut.cooldown
	elseif kind == "parried" then
		comboIndex = 0
	elseif queued then
		queued = false
		playNext()
		return
	end

	queued = false
	setAttackLock(false)
	updateLocomotion()

	-- Held through the swing: the parry window opens now, not on a new press
	if guardHeld then
		startGuard()
	end
end

local function buildTrack(target: Animator, id: string, kind: Kind): AnimationTrack
	local track = target:LoadAnimation(assetFor(id))
	track.Priority = SWING_PRIORITY
	track.Looped = false
	kindOf[track] = kind

	-- Logs which markers an animation actually fires. A marker that was authored but
	-- never published simply never arrives, and without this it is indistinguishable
	-- from broken code downstream.
	local function reached(marker: string)
		if debugging() then
			print(`[Marker] {kind}: {marker}`)
		end
	end

	local animationId = if track.Animation then track.Animation.AnimationId else ""

	-- The animation owns the active window; code never guesses it
	track:GetMarkerReachedSignal(START_MARKER):Connect(function()
		reached(START_MARKER)
		startHitbox(kind)
	end)
	track:GetMarkerReachedSignal(END_MARKER):Connect(function()
		reached(END_MARKER)
		stopHitbox()
	end)

	-- Fired on the attacker's own blade and echoed to everyone: the defender is the
	-- one who has to see it
	track:GetMarkerReachedSignal(TELL_MARKER):Connect(function()
		reached(TELL_MARKER)
		hasTellMarker[animationId] = true
		fireTell(kind)
	end)

	-- A cut attack never reaches its End marker
	track.Stopped:Connect(stopHitbox)
	track.Stopped:Connect(function()
		onAttackEnded(track)
	end)

	return track
end

local function loadTracks(weaponId: number)
	local target = animator
	local class = classFor(weaponId)
	if not target or not class then
		return
	end

	local idle = target:LoadAnimation(assetFor(class.idle))
	idle.Priority = LOCOMOTION_PRIORITY
	idle.Looped = true

	local walk = target:LoadAnimation(assetFor(class.walk))
	walk.Priority = LOCOMOTION_PRIORITY
	walk.Looped = true

	for _, id in class.swings do
		table.insert(chain, buildTrack(target, id, "swing"))
	end
	-- Flourish is the chain's last link for every weapon, not a class animation
	table.insert(chain, buildTrack(target, Config.flourish.animation, "flourish"))

	-- Universal like the flourish, but off the chain: it answers to crouch, not to M1 order
	uppercutTrack = buildTrack(target, Config.uppercut.animation, "uppercut")

	if class.heavy then
		heavyTrack = buildTrack(target, class.heavy.animation, "heavy")
	end
	if class.aerial then
		aerialTrack = buildTrack(target, class.aerial.animation, "aerial")
	end

	-- Guard tracks carry no hitbox markers, so they skip buildTrack entirely
	if class.block then
		local block = target:LoadAnimation(assetFor(class.block))
		block.Priority = BLOCK_PRIORITY
		block.Looped = true
		blockTrack = block
	end
	if class.parry then
		local parry = target:LoadAnimation(assetFor(class.parry))
		parry.Priority = REACTION_PRIORITY
		parry.Looped = false

		-- It can outlive the hold, so it is the one that releases the pose
		parry.Stopped:Connect(function()
			if guarding or current then
				return
			end
			setAttackLock(false)
			updateLocomotion()
		end)

		parryTrack = parry
	end
	if class.parried then
		for side, id in class.parried do
			local track = buildTrack(target, id, "parried")
			track.Priority = REACTION_PRIORITY
			parriedTracks[side] = track
		end
	end

	idleTrack = idle
	walkTrack = walk
	updateLocomotion()
end

local function refresh()
	clearTracks()

	local id = player:GetAttribute(Config.attribute)
	if type(id) == "number" and id ~= Config.unarmed then
		loadTracks(id)
	end
end

local function airborne(): boolean
	local living = humanoid
	return living ~= nil and living.FloorMaterial == Enum.Material.Air
end

local function playAerial()
	local track = aerialTrack
	local id = player:GetAttribute(Config.attribute)
	if not track or type(id) ~= "number" then
		return
	end

	local class = classFor(id)
	if class and class.aerial then
		startDash(class.aerial)
	end
	comboIndex = 0
	play(track)
end

-- Crouched, both mouse buttons answer with the uppercut. Deliberate stance beats
-- chain order, and asking for it with either hand beats remembering which one.
local function uppercut(): boolean
	local now = os.clock()
	if guarding or stunned() or now < staggerUntil or now < dashUntil then
		return false
	end
	if not crouching() or not uppercutTrack or current or now < uppercutReadyAt then
		return false
	end

	play(uppercutTrack)

	-- The move rises out of the crouch, so the stance follows the animation rather
	-- than leaving a crouched pose fighting a standing swing
	MovementController.uncrouch()

	-- Lunge on the swing, not on the hit: it is what lets the blow reach at all
	local root = rootPart()
	if root then
		local spec = Config.uppercut
		applyImpulse(root.CFrame.LookVector, spec.lungeSpeed, nil, spec.lungeTime)
	end
	return true
end

local function swing()
	local now = os.clock()
	if guarding or stunned() or now < staggerUntil or now < dashUntil then
		return
	end

	if uppercut() then
		return
	end

	-- The aerial outranks M1 while it is off cooldown, and takes no buffering. Once it
	-- is spent the chain answers in the air too: the alternative is M1 doing nothing
	-- mid-air, which reads as the input being dropped.
	--
	-- Never during a juggle: up there the normal chain applies, because the uppercut
	-- bought a window to combo in, not a platform to dive from.
	if now >= juggleUntil and airborne() and aerialTrack and not current and now >= aerialReadyAt then
		playAerial()
		return
	end

	if now < chainReadyAt then
		return
	end

	local active = current
	if not active then
		playNext()
		return
	end

	-- An attack is never cut; only its tail buffers the next one
	if kindOf[active] == "swing" and active.Length - active.TimePosition <= Config.comboBuffer then
		queued = true
	end
end

local function heavy()
	local track = heavyTrack
	local now = os.clock()
	if not track or current or guarding or stunned() or now < staggerUntil or now < heavyReadyAt or now < dashUntil then
		return
	end

	comboIndex = 0
	play(track)
end

local function dash()
	local now = os.clock()
	local living = humanoid
	-- `current` blocks it: dashing out of a swing would make every attack safe
	if not living or current or guarding or stunned() or now < staggerUntil or now < dashReadyAt then
		return
	end

	local root = rootPart()
	if not root then
		return
	end

	-- Steering wins over facing: a dash is a movement option, and reading MoveDirection
	-- is what lets you dash sideways or back without turning the character first.
	--
	-- With no input at all it goes BACKWARD. A standing dash is a disengage — nobody
	-- taps it to walk into the thing in front of them.
	local steer = living.MoveDirection
	local direction = if steer.Magnitude > 0 then steer.Unit else -root.CFrame.LookVector

	-- A dash bought with a refund cannot buy another; a fresh one arms the refund
	refundAvailable = not fromRefund
	fromRefund = false

	-- Same key, different move: a ground burst versus an airborne glide
	local spec = if airborne() then Config.dash.air else Config.dash.ground
	dashReadyAt = now + Config.dash.cooldown
	dashUntil = now + spec.time
	applyImpulse(direction, spec.speed, spec.lift, spec.time)

	-- Clip chosen in the character's own space, so it matches where the body goes
	local local_ = root.CFrame:VectorToObjectSpace(direction)
	local name
	if math.abs(local_.Z) >= math.abs(local_.X) then
		name = if local_.Z < 0 then "forward" else "backward"
	else
		name = if local_.X > 0 then "right" else "left"
	end

	dashClip = dashTracks[name]
	if dashClip then
		dashClip:Play(FADE)
	end

	FxController.play("dash", root.Position, player.Character)
	Net.FireServer("Swung", "dash")
	Net.FireServer("Dash", false)
end

-- M2 mid-dash: kill the movement and the clip on the spot, and buy a longer read for
-- the one hit the i-frames still owe. Spending the dash is the price of the extension.
local function cancelDash(): boolean
	if os.clock() >= dashUntil then
		return false
	end

	stopDash()
	dashUntil = 0

	if dashClip then
		dashClip:Stop(FADE)
		dashClip = nil
	end
	if dashCancelTrack then
		dashCancelTrack:Play(FADE)
	end

	-- One refund per chain. The dash it pays for is marked so cancelling THAT one
	-- gives nothing back, which is what stops cancel-dash-cancel from being free.
	if refundAvailable then
		refundAvailable = false
		fromRefund = true
		dashReadyAt = 0
	end

	Net.FireServer("Dash", true)
	return true
end

-- Server rejects a grip the weapon has no class for, so nothing is checked here
local function toggleGrip()
	if current then
		return
	end
	Net.FireServer("SetGrip", Config.otherGrip[currentGrip()])
end

startGuard = function()
	local block = blockTrack
	-- Attack cooldowns do not gate the guard; only a stagger does. `current` does:
	-- the hold is remembered and retried when the attack ends.
	if guarding or current or not block or stunned() or os.clock() < staggerUntil then
		return
	end

	guarding = true
	stopLocomotion()
	-- A held block owns the pose for the same reason an attack does
	setAttackLock(true)

	-- Block loops underneath from the first frame; the parry flourish rides over it
	-- and expires on its own, so no timer decides when the hold becomes a block
	block:Play(FADE)

	-- Locked out means this hold is only a block, and it must read as one
	if parryTrack and player:GetAttribute(Config.parryLockAttribute) ~= true then
		parryTrack:Play(FADE)
	end

	Net.FireServer("SetGuard", true)
end

local function stopGuard()
	if not guarding then
		return
	end
	guarding = false

	if blockTrack and blockTrack.IsPlaying then
		blockTrack:Stop(FADE)
	end

	Net.FireServer("SetGuard", false)

	-- ParryStart is a flourish, not a hold: releasing F ends the guard but the
	-- animation plays out. Its own Stopped hands the pose back.
	if parryTrack and parryTrack.IsPlaying then
		return
	end

	-- An attack may have interrupted the hold and still owns the lock
	if not current then
		setAttackLock(false)
	end
	updateLocomotion()
end

-- Taking a hit interrupts. Stopping the track fires onAttackEnded, which clears
-- `current` and shuts the hitbox, so a cancelled swing cannot still connect.
local function onStagger(duration: any)
	if type(duration) ~= "number" then
		return
	end

	staggerUntil = math.max(staggerUntil, os.clock() + duration)
	queued = false

	local active = current
	if active then
		cancelled = true
		active:Stop(FADE)
	end
	stopGuard()
end

-- Played on the one who CAUGHT the blow: their own blade absorbing it. The guard is
-- not dropped and `current` is untouched, so this rides over the held block and the
-- hold survives it — being rewarded for a parry must not cost the stance.
local function onParryImpact(side: any)
	local track = if type(side) == "string" then parriedTracks[side] else nil
	if not track then
		warn(`[CombatController] no parry impact animation for side "{tostring(side)}"`)
		return
	end
	track:Play(FADE)
end

-- Holds height with the constraint in Line mode along Y, which leaves X and Z to the
-- Humanoid. A Vector constraint pins all three axes and the player cannot budge.
--
-- `targetY` is chased every frame rather than held wherever the rise ended. Both bodies
-- rise on their own machine, and latency, starting velocity and ground level all differ
-- — freezing in place strands them at different altitudes, which is precisely what makes
-- the follow-up swing pass over or under the target.
local function holdHeight(duration: number, targetY: number?)
	local force, root = dashForce, rootPart()
	if not force or not root then
		return
	end

	force.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	force.LineDirection = Vector3.yAxis
	force.LineVelocity = 0
	force.Enabled = true

	dashToken += 1
	local token = dashToken

	stopHover()
	if targetY then
		local spec = Config.uppercut
		hoverConnection = RunService.Heartbeat:Connect(function()
			if dashToken ~= token or not root.Parent then
				stopHover()
				return
			end
			local gap = targetY - root.Position.Y
			force.LineVelocity = math.clamp(gap * spec.hangGain, -spec.hangCorrection, spec.hangCorrection)
		end)
	end

	task.delay(duration, function()
		if dashToken == token then
			stopDash()
		end
	end)
end

-- Rise, then hover. Two phases because a single impulse would arc straight back down,
-- and the hang is the whole point: it is a window both fighters get to use.
--
-- Only the heading and the hang height cross the wire, and both are the server's call:
-- one so the pair travels together instead of the victim hanging where they stood, the
-- other so they arrive level with each other. Every timing is the same Config on both
-- sides — sending those too would only invite the two ends to disagree.
local function applyLaunch(direction: any, hangY: any)
	if typeof(direction) ~= "Vector3" or type(hangY) ~= "number" then
		return
	end

	local spec = Config.uppercut

	-- The Humanoid tries to snap back to the ground it thinks it is standing on.
	-- Forcing Freefall is what stops it fighting the launch and yanking the body down.
	local living = humanoid
	if living then
		living:ChangeState(Enum.HumanoidStateType.Freefall)
		living.WalkSpeed = spec.airSpeed
	end

	juggleUntil = os.clock() + spec.riseTime + spec.hangTime
	applyImpulse(direction, spec.carrySpeed, spec.riseSpeed, spec.riseTime)

	task.delay(spec.riseTime, function()
		-- The carry belongs to the launch, not the hang
		holdHeight(spec.hangTime, hangY)
	end)

	task.delay(spec.riseTime + spec.hangTime, function()
		local ended = humanoid
		if ended then
			ended.WalkSpeed = baseWalkSpeed
		end
	end)
end

local function applyKnockback(direction: Vector3, speed: number)
	-- Lift on purpose: flat against the ground, friction and the Humanoid controller
	-- both eat the shove and a grounded target barely budges
	applyImpulse(direction, speed, Config.knockbackLift, Config.knockbackTime)

	if debugging() then
		print(`[Knockback] applied {speed}`)
	end
end

local function teardownCharacter()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)

	stopDash()
	dashReadyAt = 0
	dashClip = nil
	refundAvailable = false
	fromRefund = false

	for _, track in dashTracks do
		track:Stop(FADE)
		track:Destroy()
	end
	table.clear(dashTracks)

	if dashCancelTrack then
		dashCancelTrack:Stop(FADE)
		dashCancelTrack:Destroy()
		dashCancelTrack = nil
	end
	if dashForce then
		-- Destroy the attachment, not the force: the force is its child
		local attachment = dashForce.Parent
		dashForce = nil
		if attachment then
			attachment:Destroy()
		end
	end

	clearTracks()
	humanoid = nil
	animator = nil
end

local function buildDashForce(root: BasePart): LinearVelocity
	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatDash"
	attachment.Parent = root

	local force = Instance.new("LinearVelocity")
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.MaxForce = math.huge
	force.VectorVelocity = Vector3.zero
	force.Enabled = false
	force.Parent = attachment

	return force
end

local function setupCharacter(character: Model)
	teardownCharacter()

	local newHumanoid = character:WaitForChild("Humanoid") :: Humanoid
	local newAnimator = newHumanoid:WaitForChild("Animator") :: Animator
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart

	if player.Character ~= character then
		return
	end

	humanoid = newHumanoid
	animator = newAnimator
	dashForce = buildDashForce(root)
	baseWalkSpeed = newHumanoid.WalkSpeed
	juggleUntil = 0

	-- Loaded per character, not per weapon: dashing, crouching and the uppercut all
	-- work unarmed
	for name, id in Config.dash.clips do
		local track = newAnimator:LoadAnimation(assetFor(id))
		track.Priority = REACTION_PRIORITY
		track.Looped = false
		dashTracks[name] = track
	end

	local cancel = newAnimator:LoadAnimation(assetFor(Config.dash.cancel))
	cancel.Priority = REACTION_PRIORITY
	cancel.Looped = false
	dashCancelTrack = cancel

	local crouchIdle = newAnimator:LoadAnimation(assetFor(Config.crouch.idle))
	crouchIdle.Priority = LOCOMOTION_PRIORITY
	crouchIdle.Looped = true
	crouchIdleTrack = crouchIdle

	local crouchWalk = newAnimator:LoadAnimation(assetFor(Config.crouch.walk))
	crouchWalk.Priority = LOCOMOTION_PRIORITY
	crouchWalk.Looped = true
	crouchWalkTrack = crouchWalk

	table.insert(connections, character:GetAttributeChangedSignal(Config.crouch.attribute):Connect(updateLocomotion))

	table.insert(connections, newHumanoid:GetPropertyChangedSignal("MoveDirection"):Connect(updateLocomotion))

	-- Landing ends the glide, so a low aerial does not skate along the floor
	table.insert(
		connections,
		newHumanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
			if newHumanoid.FloorMaterial ~= Enum.Material.Air then
				stopDash()
			end
		end)
	)

	refresh()
end

function CombatController.Start()
	player:GetAttributeChangedSignal(Config.attribute):Connect(refresh)
	-- Grip picks the animation class, so it rebuilds the same way a weapon swap does
	player:GetAttributeChangedSignal(Config.gripAttribute):Connect(refresh)

	player.CharacterAdded:Connect(setupCharacter)
	player.CharacterRemoving:Connect(teardownCharacter)

	local character = player.Character
	if character then
		task.spawn(setupCharacter, character)
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			swing()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			-- A live dash owns the button; crouched with none, it is the uppercut
			if not cancelDash() then
				uppercut()
			end
		elseif input.KeyCode == HEAVY_KEY then
			heavy()
		elseif input.KeyCode == GRIP_KEY then
			toggleGrip()
		elseif input.KeyCode == GUARD_KEY then
			guardHeld = true
			startGuard()
		elseif input.KeyCode == DASH_KEY then
			dash()
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == GUARD_KEY then
			guardHeld = false
			stopGuard()
		end
	end)

	-- A guard break drops the hold; the server already stopped honouring it
	player:GetAttributeChangedSignal(Config.stunAttribute):Connect(function()
		if stunned() then
			stopGuard()
		end
	end)

	-- Last: Net.On yields on WaitForChild, and input must be live before that
	Net.On("Knockback", applyKnockback)
	Net.On("Launch", applyLaunch)
	Net.On("ParryImpact", onParryImpact)
	Net.On("Stagger", onStagger)
end

return CombatController
