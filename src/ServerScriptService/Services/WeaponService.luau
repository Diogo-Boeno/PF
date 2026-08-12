--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Framework.Net)
local Config = require(ReplicatedStorage.Data.Weapons)

local Guard = Config.guard

-- Test grant, delete once inventory exists
local STARTER_SLOT = "1"
local STARTER_WEAPON = 1

local lastRequest: { [Player]: number } = {}
local lastSwingFx: { [Player]: number } = {}

-- Weak keys so a dead target's entry goes away without a sweep
local WEAK_KEYS = { __mode = "k" }
local lastHit: { [Player]: { [Humanoid]: number } } = {}

-- nil means not holding guard at all
local guardStart: { [Player]: number } = {}
local parriedAt: { [Player]: number } = {}
local whiffUntil: { [Player]: number } = {}
local posture: { [Player]: number } = {}

local WeaponService = {}

local function stunned(player: Player): boolean
	return player:GetAttribute(Config.stunAttribute) == true
end

-- Presentation is decided where the outcome is decided, so no client has to guess
-- whether its own swing landed, was blocked or got parried
local function broadcastFx(event: string, at: BasePart?)
	if at then
		Net.FireAllClients("Fx", event, at.Position)
	end
end

local function setPosture(player: Player, value: number)
	local clamped = math.clamp(value, 0, Guard.postureMax)
	posture[player] = clamped

	-- Decay steps every frame. Replicating the raw float would be 60 writes a second
	-- per player for movement no UI can resolve; whole points are what a bar shows.
	local shown = math.floor(clamped)
	if player:GetAttribute(Config.postureAttribute) ~= shown then
		player:SetAttribute(Config.postureAttribute, shown)
	end
end

local function breakGuard(player: Player)
	setPosture(player, 0)
	guardStart[player] = nil
	player:SetAttribute(Config.stunAttribute, true)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	broadcastFx("guardBreak", if humanoid then humanoid.RootPart else nil)

	task.delay(Guard.stunTime, function()
		if player.Parent then
			player:SetAttribute(Config.stunAttribute, false)
		end
	end)
end

local function addPosture(player: Player, amount: number)
	local value = (posture[player] or 0) + amount
	if value >= Guard.postureMax then
		breakGuard(player)
		return
	end
	setPosture(player, value)
end

local function lockParry(player: Player)
	local expiry = os.clock() + Guard.parryWhiff
	whiffUntil[player] = expiry
	player:SetAttribute(Config.parryLockAttribute, true)

	task.delay(Guard.parryWhiff, function()
		-- A later whiff pushed the expiry out; that timer owns the unlock
		if player.Parent and whiffUntil[player] == expiry then
			player:SetAttribute(Config.parryLockAttribute, false)
		end
	end)
end

-- A hold that never met an attack inside the window costs the parry, not the block
local function onGuardRequest(player: Player, holding: any)
	if holding ~= true then
		guardStart[player] = nil
		return
	end

	if guardStart[player] or stunned(player) then
		return
	end

	local now = os.clock()
	guardStart[player] = now

	-- Already locked out, so this hold is a plain block and must not re-arm anything
	if now < (whiffUntil[player] or 0) then
		return
	end

	task.delay(Guard.parryWindow, function()
		-- Releasing early does not forgive it: pressing F is what commits the parry
		if (parriedAt[player] or 0) < now then
			lockParry(player)
		end
	end)
end

-- Right is the only side every class carries, so it is the fallback
local function parriedSide(class: any): string?
	local set = class.parried
	if not set then
		return nil
	end
	if set.left and set.right then
		return if math.random() < 0.5 then "left" else "right"
	end
	return if set.left then "left" else "right"
end

local function grantStarter(player: Player)
	player:SetAttribute(Config.slotAttribute .. STARTER_SLOT, STARTER_WEAPON)
end

local function onEquipRequest(player: Player, requestedId: any)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < Config.requestCooldown then
		return
	end
	lastRequest[player] = now

	local id = Config.unarmed
	if type(requestedId) == "number" and Config.byId[requestedId] ~= nil then
		id = requestedId
	end

	if player:GetAttribute(Config.attribute) == id then
		return
	end
	player:SetAttribute(Config.attribute, id)
end

local function classFor(player: Player): any?
	local weaponId = player:GetAttribute(Config.attribute)
	if type(weaponId) ~= "number" then
		return nil
	end

	local entry = Config.byId[weaponId]
	if not entry then
		return nil
	end

	local grip = player:GetAttribute(Config.gripAttribute)
	if type(grip) ~= "string" then
		grip = Config.defaultGrip
	end

	local name = entry.classes[grip]
	return if name then Config.classes[name] else nil
end

-- The swinger already played this locally, so it is echoed to everyone else only.
-- Rate limited because it is the one Fx a client gets to ask for.
local function onSwungReport(player: Player, event: any)
	if type(event) ~= "string" or Config.swingFx[event] ~= true then
		return
	end

	local now = os.clock()
	if now - (lastSwingFx[player] or 0) < Config.swingFxCooldown then
		return
	end
	lastSwingFx[player] = now

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	for _, other in Players:GetPlayers() do
		if other ~= player then
			Net.FireClient("Fx", other, event, root.Position, character)
		end
	end
end

-- A grip the equipped weapon has no class for is not a grip the player can hold
local function onGripRequest(player: Player, requested: any)
	if type(requested) ~= "string" or Config.otherGrip[requested] == nil then
		return
	end

	local weaponId = player:GetAttribute(Config.attribute)
	local entry = if type(weaponId) == "number" then Config.byId[weaponId] else nil
	if not entry or not entry.classes[requested] then
		return
	end

	player:SetAttribute(Config.gripAttribute, requested)
end

-- Damage lives with whoever owns the move: the flourish is universal, the rest
-- belong to the class. A kind the class does not declare is a forged report.
local function damageFor(class: any, kind: any): number?
	if kind == "swing" then
		return class.damage
	end
	if kind == "flourish" then
		return Config.flourish.damage
	end
	if kind == "heavy" then
		return if class.heavy then class.heavy.damage else nil
	end
	if kind == "aerial" then
		return if class.aerial then class.aerial.damage else nil
	end
	return nil
end

-- Guard resolution, split out because an NPC swing has to go through the exact same
-- parry and block rules a player swing does. `attacker` is nil when nobody owns the
-- swing, which is why an NPC neither gains posture from parrying nor eats it.
function WeaponService.resolveHit(target: Humanoid, damage: number, class: any, attacker: Player?): string
	local victim = Players:GetPlayerFromCharacter(target.Parent)
	local held = if victim then guardStart[victim] else nil
	if not victim or not held then
		target:TakeDamage(damage)
		broadcastFx("hit", target.RootPart)
		return "hit"
	end

	local now = os.clock()

	-- Inside the window and not locked out: the hit is refused outright
	if now - held <= Guard.parryWindow and now >= (whiffUntil[victim] or 0) then
		parriedAt[victim] = now
		addPosture(victim, -Guard.parryRelief)
		broadcastFx("parry", target.RootPart)

		if attacker then
			addPosture(attacker, Guard.parryPosture)
			local side = parriedSide(class)
			if side then
				Net.FireClient("Parried", attacker, side)
			end
		end
		return "parried"
	end

	-- Otherwise an ordinary block: posture always, health only on chip
	addPosture(victim, damage * Guard.postureFactor)
	broadcastFx("blocked", target.RootPart)
	if class and class.chip then
		target:TakeDamage(damage * class.chip)
	end
	return "blocked"
end

-- Non-player targets are owned by the server, so the shove is applied right here.
-- Same sustained force as the client path: a one-shot velocity write loses to the
-- Humanoid controller on the very next step.
local function shoveHere(root: BasePart, direction: Vector3, speed: number)
	local anchor = Instance.new("Attachment")
	anchor.Name = "Knockback"
	anchor.Parent = root

	local force = Instance.new("LinearVelocity")
	force.Attachment0 = anchor
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.MaxForce = math.huge
	force.VectorVelocity = Vector3.new(direction.X * speed, Config.knockbackLift, direction.Z * speed)
	force.Parent = anchor

	-- Destroying the attachment takes the constraint with it
	Debris:AddItem(anchor, Config.knockbackTime)
end

-- Same rule as damage: a move with no `knockback` key simply does not shove
local function knockbackFor(class: any, kind: any): number?
	if kind == "flourish" then
		return Config.flourish.knockback
	end
	if kind == "heavy" then
		return if class.heavy then class.heavy.knockback else nil
	end
	if kind == "aerial" then
		return if class.aerial then class.aerial.knockback else nil
	end
	return nil
end

-- The client detects; the server decides. Nothing here trusts the report itself,
-- only that the attacker could plausibly have made it.
local function onHitReport(player: Player, target: any, kind: any)
	if typeof(target) ~= "Instance" or not target:IsA("Humanoid") or target.Health <= 0 then
		return
	end

	local class = classFor(player)
	if not class then
		return
	end

	local damage = damageFor(class, kind)
	if not damage then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local attacker = character:FindFirstChildOfClass("Humanoid")
	if not attacker or attacker == target or attacker.Health <= 0 then
		return
	end

	local attackerRoot = attacker.RootPart
	local targetRoot = target.RootPart
	if not attackerRoot or not targetRoot then
		return
	end

	if (attackerRoot.Position - targetRoot.Position).Magnitude > Config.maxHitDistance then
		return
	end

	local seen = lastHit[player]
	if not seen then
		seen = setmetatable({}, WEAK_KEYS) :: any
		lastHit[player] = seen
	end

	local now = os.clock()
	if now - (seen[target] or 0) < Config.hitCooldown then
		return
	end
	seen[target] = now

	if WeaponService.resolveHit(target, damage, class, player) ~= "hit" then
		return
	end

	-- The target's client owns that character's physics, so a server-side shove
	-- would just be overwritten by its next simulation step
	local push = knockbackFor(class, kind)
	if not push then
		return
	end

	local direction = (targetRoot.Position - attackerRoot.Position) * Vector3.new(1, 0, 1)
	if direction.Magnitude == 0 then
		return
	end

	local victim = Players:GetPlayerFromCharacter(target.Parent)
	if victim then
		Net.FireClient("Knockback", victim, direction.Unit, push)
	else
		shoveHere(targetRoot, direction.Unit, push)
	end

	if Config.debugHitbox.enabled then
		print(`[Knockback] {kind} -> {target.Parent and target.Parent.Name}, force {push}, player {victim ~= nil}`)
	end
end

function WeaponService.Start()
	Net.On("EquipWeapon", onEquipRequest)
	Net.On("WeaponHit", onHitReport)
	Net.On("SetGrip", onGripRequest)
	Net.On("SetGuard", onGuardRequest)
	Net.On("Swung", onSwungReport)

	-- Server->client only, so nothing else would ever create them
	Net.Register("Knockback")
	Net.Register("Parried")
	Net.Register("Fx")

	Players.PlayerAdded:Connect(grantStarter)
	for _, player in Players:GetPlayers() do
		grantStarter(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		lastSwingFx[player] = nil
		lastHit[player] = nil
		guardStart[player] = nil
		parriedAt[player] = nil
		whiffUntil[player] = nil
		posture[player] = nil
	end)

	-- Posture always drains. Stepped rather than computed on read so the replicated
	-- attribute stays honest for whatever UI reads it later.
	RunService.Heartbeat:Connect(function(delta: number)
		for player, value in posture do
			if value > 0 then
				setPosture(player, value - Guard.postureDecay * delta)
			end
		end
	end)
end

return WeaponService
