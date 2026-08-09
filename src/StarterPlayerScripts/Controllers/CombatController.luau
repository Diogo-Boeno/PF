--!strict
-- Only the owner plays these; Animator replicates them to everyone else.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Data.Weapons)
local Net = require(ReplicatedStorage.Shared.Framework.Net)
local RaycastHitbox = require(ReplicatedStorage.RaycastHitbox)
local WeaponController = require(script.Parent.WeaponController)

local FADE = 0.1
local HEAVY_KEY = Enum.KeyCode.R
local GRIP_KEY = Enum.KeyCode.Y
local GUARD_KEY = Enum.KeyCode.F

-- Animation events authored on every attack animation
local START_MARKER = "Start"
local END_MARKER = "End"

-- Above the Core that Animate.client plays; attacks above those
local LOCOMOTION_PRIORITY = Enum.AnimationPriority.Action
local SWING_PRIORITY = Enum.AnimationPriority.Action2
-- Over a held block, which is Action2 and never coexists with an attack
local REACTION_PRIORITY = Enum.AnimationPriority.Action3

type Kind = "swing" | "flourish" | "heavy" | "aerial" | "parried"

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
local parriedTracks: { [string]: AnimationTrack } = {}
local kindOf: { [AnimationTrack]: Kind } = {}

local guarding = false

local comboIndex = 0
local current: AnimationTrack? = nil
local activeKind: Kind? = nil
local queued = false

-- Rebuilt only when the mounted model changes, not per attack
local hitbox: any = nil
local hitboxModel: Model? = nil

-- Built once per character and toggled, rather than instanced per dash
local dashForce: LinearVelocity? = nil
local dashToken = 0

-- When the last attack ended, not started: chaining must not read as idle time
local lastAttackEnd = 0
local lockedUntil = 0
local heavyReadyAt = 0

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

local function releaseHitbox()
	if hitbox then
		hitbox:Destroy()
		hitbox = nil
	end
	hitboxModel = nil
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
	new.Visualizer = true
	new.DebugLog = true
	new.OnHit:Connect(function(_part: BasePart, hit: Humanoid)
		Net.FireServer("WeaponHit", hit, activeKind)
	end)

	hitbox = new
	hitboxModel = model
	return new
end

local function stopHitbox()
	if hitbox then
		hitbox:HitStop()
	end
end

-- One box query on the impact frame. The leg is short and a kick has no arc to
-- interpolate, so raycasting it would pay per-frame cost for nothing.
local function kickBox()
	local root = rootPart()
	local character = player.Character
	if not root or not character then
		return
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local origin = root.CFrame * CFrame.new(0, 0, -Config.flourish.reach)
	local seen: { [Humanoid]: boolean } = {}

	for _, part in workspace:GetPartBoundsInBox(origin, Config.flourish.size, params) do
		local parent = part.Parent
		local hit = parent and parent:FindFirstChildOfClass("Humanoid")
		if hit and not seen[hit] then
			seen[hit] = true
			Net.FireServer("WeaponHit", hit, "flourish")
		end
	end
end

local function stopDash()
	if dashForce then
		dashForce.Enabled = false
	end
	-- Invalidates any delayed stop still pending for an older dash
	dashToken += 1
end

local function startDash(aerial: any)
	local force, root = dashForce, rootPart()
	if not force or not root then
		return
	end

	local look = root.CFrame.LookVector
	force.VectorVelocity = Vector3.new(look.X * aerial.dashSpeed, aerial.dashFall, look.Z * aerial.dashSpeed)
	force.Enabled = true

	dashToken += 1
	local token = dashToken
	task.delay(aerial.dashTime, function()
		if dashToken == token then
			stopDash()
		end
	end)
end

local function startHitbox(kind: Kind)
	if kind == "flourish" then
		kickBox()
		return
	end

	local active = ensureHitbox()
	if active then
		activeKind = kind
		active:HitStart()
	end
end

local function clearTracks()
	-- Drop the queue first: Stop() below fires Stopped on every track
	queued = false
	current = nil
	activeKind = nil
	lockedUntil = 0
	heavyReadyAt = 0
	stopDash()
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

local function stopLocomotion()
	local idle, walk = idleTrack, walkTrack
	if idle and idle.IsPlaying then
		idle:Stop(FADE)
	end
	if walk and walk.IsPlaying then
		walk:Stop(FADE)
	end
end

local function updateLocomotion()
	local idle, walk, living = idleTrack, walkTrack, humanoid
	if not idle or not walk or not living then
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

local function play(track: AnimationTrack)
	current = track
	stopLocomotion()
	track:Play(FADE)
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
	if kind == "flourish" then
		lockedUntil = lastAttackEnd + Config.endlag
	elseif kind == "aerial" then
		lockedUntil = lastAttackEnd + Config.aerialCooldown
	elseif kind == "heavy" then
		heavyReadyAt = lastAttackEnd + Config.heavyCooldown
	elseif kind == "parried" then
		comboIndex = 0
	elseif queued then
		queued = false
		playNext()
		return
	end

	queued = false
	updateLocomotion()
end

local function buildTrack(target: Animator, id: string, kind: Kind): AnimationTrack
	local track = target:LoadAnimation(assetFor(id))
	track.Priority = SWING_PRIORITY
	track.Looped = false
	kindOf[track] = kind

	-- The animation owns the active window; code never guesses it
	track:GetMarkerReachedSignal(START_MARKER):Connect(function()
		startHitbox(kind)
	end)
	track:GetMarkerReachedSignal(END_MARKER):Connect(stopHitbox)

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

	if class.heavy then
		heavyTrack = buildTrack(target, class.heavy.animation, "heavy")
	end
	if class.aerial then
		aerialTrack = buildTrack(target, class.aerial.animation, "aerial")
	end

	-- Guard tracks carry no hitbox markers, so they skip buildTrack entirely
	if class.block then
		local block = target:LoadAnimation(assetFor(class.block))
		block.Priority = SWING_PRIORITY
		block.Looped = true
		blockTrack = block
	end
	if class.parry then
		local parry = target:LoadAnimation(assetFor(class.parry))
		parry.Priority = REACTION_PRIORITY
		parry.Looped = false
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

local function swing()
	if guarding or stunned() or os.clock() < lockedUntil then
		return
	end

	if airborne() then
		-- The aerial replaces M1 outright and takes no buffering
		if not current and aerialTrack then
			playAerial()
		end
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
	if not track or current or guarding or stunned() or now < lockedUntil or now < heavyReadyAt then
		return
	end

	comboIndex = 0
	play(track)
end

-- Server rejects a grip the weapon has no class for, so nothing is checked here
local function toggleGrip()
	if current then
		return
	end
	Net.FireServer("SetGrip", Config.otherGrip[currentGrip()])
end

local function startGuard()
	local block = blockTrack
	if guarding or current or not block or stunned() or os.clock() < lockedUntil then
		return
	end

	guarding = true
	stopLocomotion()

	-- Block loops underneath from the first frame; the parry flourish rides over it
	-- and expires on its own, so no timer decides when the hold becomes a block
	block:Play(FADE)
	if parryTrack then
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
	if parryTrack and parryTrack.IsPlaying then
		parryTrack:Stop(FADE)
	end

	Net.FireServer("SetGuard", false)
	updateLocomotion()
end

local function onParried(side: any)
	stopGuard()

	local track = if type(side) == "string" then parriedTracks[side] else nil
	if track then
		play(track)
	end
	lockedUntil = os.clock() + Config.guard.parriedLock
end

local function applyKnockback(direction: Vector3, force: number)
	local root = rootPart()
	if not root then
		return
	end

	local vertical = root.AssemblyLinearVelocity.Y
	root.AssemblyLinearVelocity = Vector3.new(direction.X * force, vertical, direction.Z * force)
end

local function teardownCharacter()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)

	stopDash()
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
		elseif input.KeyCode == HEAVY_KEY then
			heavy()
		elseif input.KeyCode == GRIP_KEY then
			toggleGrip()
		elseif input.KeyCode == GUARD_KEY then
			startGuard()
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == GUARD_KEY then
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
	Net.On("Parried", onParried)
end

return CombatController
