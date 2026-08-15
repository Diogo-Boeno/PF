--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Framework.Net)
local Config = require(ReplicatedStorage.Data.Weapons)
local HealthService = require(script.Parent.HealthService)

local Guard = Config.guard

local lastSwingFx: { [Player]: { [string]: number } } = {}

-- Weak keys so a dead target's entry goes away without a sweep
local WEAK_KEYS = { __mode = "k" }
local lastHit: { [Player]: { [Humanoid]: number } } = {}

-- nil means not holding guard at all
local guardStart: { [Player]: number } = {}
local parriedAt: { [Player]: number } = {}
local whiffUntil: { [Player]: number } = {}

-- Earned by landing a parry. Valid with F already released, which is what turns one
-- press into a chain instead of one refusal.
local parryFramesUntil: { [Player]: number } = {}

-- Guarding and being able to parry are different states. A hold that came too soon
-- after the last one still blocks, it just is not armed.
local parryArmed: { [Player]: boolean } = {}
local lastGuardPress: { [Player]: number } = {}

-- Dash invulnerability. Consumed by the first hit it turns away, never a duration
-- that eats a whole flurry — that would beat any guard for free.
local dodgeUntil: { [Player]: number } = {}
local lastDash: { [Player]: number } = {}
local dashRefund: { [Player]: boolean } = {}
local posture: { [Player]: number } = {}

local WeaponService = {}

local function stunned(player: Player): boolean
	return player:GetAttribute(Config.stunAttribute) == true
end

-- Damage never touches Humanoid.Health: the engine's version kills by tearing the rig
-- apart, and health is ours to own. HealthService takes the character, not the humanoid.
local function hurt(target: Humanoid, amount: number)
	local character = target.Parent
	if character and character:IsA("Model") then
		HealthService.damage(character, amount)
	end
end

-- Presentation is decided where the outcome is decided, so no client has to guess
-- whether its own swing landed, was blocked or got parried.
--
-- `subject` is whoever the outcome happened TO — the defender. Effects declared with
-- `on = "blade"` need it to find the weapon the sparks come off.
local function broadcastFx(event: string, at: BasePart?, subject: Model?)
	if at then
		Net.FireAllClients("Fx", event, at.Position, subject)
	end
end

-- Silences a body for `duration`, by whatever route actually reaches it: a player's
-- client through the remote, a server-owned rig through an attribute it polls.
--
-- One function because this choice has to be made everywhere something staggers, and
-- forgetting the second branch is silent — the NPC simply keeps swinging.
local function silence(character: Model?, duration: number)
	if not character then
		return
	end

	local victim = Players:GetPlayerFromCharacter(character)
	if victim then
		Net.FireClient("Stagger", victim, duration)
	else
		character:SetAttribute(Config.stunUntilAttribute, os.clock() + duration)
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
	broadcastFx("guardBreak", if humanoid then humanoid.RootPart else nil, character)

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
		local held = guardStart[player]
		guardStart[player] = nil

		-- Released while still inside the parry window — never once it has settled into
		-- a block. The frames carry the read past the release, so tapping F on a swing
		-- you saw coming is enough, and the defender may attack straight after.
		--
		-- Locked out earns nothing: without this, alternating taps produced near
		-- continuous frames and the whiff penalty never caught up.
		local now = os.clock()
		if held and parryArmed[player] and now - held <= Guard.parryWindow and now >= (whiffUntil[player] or 0) then
			parryFramesUntil[player] = now + Guard.parryFrames
		end
		return
	end

	if guardStart[player] or stunned(player) then
		return
	end

	local now = os.clock()
	guardStart[player] = now

	-- Mashing does not re-open the window. The hold still blocks; it just cannot parry.
	local armed = now - (lastGuardPress[player] or -math.huge) >= Guard.parryRearm
	lastGuardPress[player] = now
	parryArmed[player] = armed

	-- Already locked out, or not armed: a plain block, and nothing to schedule
	if not armed or now < (whiffUntil[player] or 0) then
		return
	end

	task.delay(Guard.parryWindow, function()
		-- Releasing early does not forgive it: pressing F is what commits the parry
		if (parriedAt[player] or 0) < now then
			lockParry(player)
		end
	end)
end

-- The client owns when a dash starts, so it says so. Nothing here trusts the timing
-- beyond a cooldown: at worst a cheat buys itself the same window a legit dash gets.
local function onDashReport(player: Player, cancelled: any)
	local now = os.clock()
	local spec = Config.dash

	if cancelled == true then
		-- Cancelling spends the dash for a longer read. It does not stack with the
		-- window already running; the later deadline simply wins.
		dodgeUntil[player] = math.max(dodgeUntil[player] or 0, now + spec.cancelIframes)

		-- Mirrors the client's refund. Only one is ever outstanding, so this cannot
		-- become an unlimited pass through the cooldown.
		dashRefund[player] = true
		return
	end

	-- Held to the same cooldown the client obeys, so spamming the remote cannot buy
	-- more invulnerability than dashing legitimately would. A refund is the one
	-- sanctioned way past it.
	if dashRefund[player] then
		dashRefund[player] = nil
	elseif now - (lastDash[player] or -math.huge) < spec.cooldown then
		return
	end

	lastDash[player] = now
	dodgeUntil[player] = now + spec.iframes
end

-- Right is the only side every class carries, so it is the fallback
local function parriedSide(class: any?): string?
	local set = class and class.parried
	if not set then
		return nil
	end
	if set.left and set.right then
		return if math.random() < 0.5 then "left" else "right"
	end
	return if set.left then "left" else "right"
end

-- No client reaches this directly: InventoryService checks the player actually carries
-- the weapon before asking. An id outside the catalog reads as unarmed.
function WeaponService.equip(player: Player, requestedId: any)
	local id = Config.unarmed
	if type(requestedId) == "number" and Config.byId[requestedId] ~= nil then
		id = requestedId
	end

	if player:GetAttribute(Config.attribute) == id then
		return
	end

	-- A weapon with no class for the grip in force would equip into nothing, so the grip
	-- follows the weapon. Written first, so the client resolves the class only once.
	local entry = Config.byId[id]
	if entry then
		local grip = player:GetAttribute(Config.gripAttribute)
		if type(grip) ~= "string" then
			grip = Config.defaultGrip
		end

		if not entry.classes[grip] then
			for available in entry.classes do
				player:SetAttribute(Config.gripAttribute, available)
				break
			end
		end
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

	-- Per event, not per player: the Tell fires just before the swing's own Start, and
	-- a shared cooldown would silently drop whichever came second
	local seen = lastSwingFx[player]
	if not seen then
		seen = {}
		lastSwingFx[player] = seen
	end

	local now = os.clock()
	if now - (seen[event] or 0) < Config.swingFxCooldown then
		return
	end
	seen[event] = now

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

-- Telegraph is the windup tell. Same closed set and same rate limit as Swung, because
-- it is the other Fx a client is allowed to ask for.
local function onTelegraphReport(player: Player, event: any)
	if type(event) ~= "string" or Config.swingFx[event] ~= true then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	for _, other in Players:GetPlayers() do
		if other ~= player then
			Net.FireClient("Telegraph", other, event, character)
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
	if kind == "uppercut" then
		return Config.uppercut.damage
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
	local defender = if target.Parent and target.Parent:IsA("Model") then target.Parent else nil
	local victim = Players:GetPlayerFromCharacter(target.Parent)
	local now = os.clock()

	if not victim then
		hurt(target, damage)
		broadcastFx("hit", target.RootPart, defender)
		silence(defender, Config.hitstun)
		return "hit"
	end

	-- I-frames answer before anything else and are spent on contact. One dash turns
	-- away one blow; the rest of the flurry lands.
	if now < (dodgeUntil[victim] or 0) then
		dodgeUntil[victim] = 0
		broadcastFx("dodge", target.RootPart, defender)
		return "dodged"
	end

	local held = guardStart[victim]

	-- Two ways to parry, and the second is the point of this system:
	--   window — pressed F recently enough, the deliberate read
	--   frames — earned by the previous parry, and valid with F already released
	-- Chaining is what lets one well-timed press turn away a flurry.
	local inWindow = held ~= nil
		and parryArmed[victim] == true
		and now - held <= Guard.parryWindow
		and now >= (whiffUntil[victim] or 0)
	local inFrames = now < (parryFramesUntil[victim] or 0)

	if not inWindow and not inFrames then
		if not held then
			hurt(target, damage)
			broadcastFx("hit", target.RootPart, defender)

			-- Only a clean hit staggers. Blocking or parrying is the reward for
			-- defending, so neither may cost the defender their turn.
			silence(defender, Config.hitstun)
			return "hit"
		end

		-- Guarding but past the window: an ordinary block
		addPosture(victim, damage * Guard.postureFactor)
		broadcastFx("blocked", target.RootPart, defender)
		if class and class.chip then
			target:TakeDamage(damage * class.chip)
		end
		return "blocked"
	end

	do
		parriedAt[victim] = now

		-- Every parry pays for the next one
		parryFramesUntil[victim] = now + Guard.parryFrames

		addPosture(victim, -Guard.parryRelief)
		broadcastFx("parry", target.RootPart, defender)

		-- The impact animation belongs to whoever caught the blow, and it is their own
		-- weapon absorbing it — so the side comes from the DEFENDER's class, not the
		-- attacker's. The attacker just loses their turn.
		local defenderSide = parriedSide(classFor(victim))
		if defenderSide then
			Net.FireClient("ParryImpact", victim, defenderSide)
		end

		if attacker then
			addPosture(attacker, Guard.parryPosture)
			Net.FireClient("Stagger", attacker, Guard.parriedLock)
		end

		if Config.debugHitbox.enabled then
			local how = if inWindow then "window" else "frames"
			print(`[Parry] {victim.Name} parried {if attacker then attacker.Name else "an NPC"} ({how})`)
		end
		return "parried"
	end
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

-- Server-owned bodies get launched here, mirroring the client's two phases. Without
-- this an NPC just stands there while the attacker rises, and the juggle has nobody
-- in it.
local function launchHere(root: BasePart, heading: Vector3, hangY: number, spec: any, humanoid: Humanoid?)
	-- Same reason as the client path: a Humanoid that believes it is standing will
	-- drag the body back down against the force
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	local anchor = Instance.new("Attachment")
	anchor.Name = "Launch"
	anchor.Parent = root

	local force = Instance.new("LinearVelocity")
	force.Attachment0 = anchor
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.MaxForce = math.huge
	force.VectorVelocity = Vector3.new(heading.X * spec.carrySpeed, spec.riseSpeed, heading.Z * spec.carrySpeed)
	force.Parent = anchor

	-- Carry belongs to the launch, not the hang. Line mode along Y holds the height
	-- while leaving the horizontal axes free, so a juggled body can still drift.
	task.delay(spec.riseTime, function()
		if not force.Parent then
			return
		end
		force.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
		force.LineDirection = Vector3.yAxis

		-- Chases the shared height, exactly as the client path does, so an NPC ends up
		-- level with whoever launched it instead of wherever its own rise stopped
		local hover: RBXScriptConnection? = nil
		hover = RunService.Heartbeat:Connect(function()
			if not force.Parent or not root.Parent then
				if hover then
					hover:Disconnect()
				end
				return
			end
			local gap = hangY - root.Position.Y
			force.LineVelocity = math.clamp(gap * spec.hangGain, -spec.hangCorrection, spec.hangCorrection)
		end)

		task.delay(spec.hangTime, function()
			if hover then
				hover:Disconnect()
			end
		end)
	end)

	Debris:AddItem(anchor, spec.riseTime + spec.hangTime)
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
	if typeof(target) ~= "Instance" or not target:IsA("Humanoid") then
		return
	end

	-- Humanoid.Health is pinned high and means nothing now; defeat is our attribute
	local targetCharacter = target.Parent
	if not targetCharacter or not targetCharacter:IsA("Model") or HealthService.isDefeated(targetCharacter) then
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
	if not attacker or attacker == target or HealthService.isDefeated(character) then
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
	-- The uppercut lifts BOTH of them: the reward is a shared window in the air, not
	-- distance. Sent to each client because each owns its own character's physics.
	if kind == "uppercut" then
		local spec = Config.uppercut

		-- One heading for both, taken from the attacker: they leave the ground as a
		-- pair and stay a pair for the whole hang
		local heading = attackerRoot.CFrame.LookVector * Vector3.new(1, 0, 1)
		heading = if heading.Magnitude > 0 then heading.Unit else Vector3.zero

		-- One height for both, measured off the contact instead of off each body. Each
		-- side rises on its own machine, so without a shared mark they settle at
		-- different altitudes and the follow-up swing has nothing to reach.
		local hangY = (attackerRoot.Position.Y + targetRoot.Position.Y) / 2 + spec.riseHeight

		-- Whoever owns the body applies the force: the victim's client if it has one,
		-- this server if it does not
		local victim = Players:GetPlayerFromCharacter(target.Parent)
		if victim then
			Net.FireClient("Launch", victim, heading, hangY)
		else
			launchHere(targetRoot, heading, hangY, spec, target)
		end

		-- Longer than the hitstun resolveHit already applied. On the client `max()`
		-- keeps the longer of the two; on an NPC the later deadline simply wins.
		silence(targetCharacter, spec.victimStun)

		Net.FireClient("Launch", player, heading, hangY)
		return
	end

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
	Net.On("WeaponHit", onHitReport)
	Net.On("SetGrip", onGripRequest)
	Net.On("SetGuard", onGuardRequest)
	Net.On("Dash", onDashReport)
	Net.On("Swung", onSwungReport)
	Net.On("Telegraph", onTelegraphReport)

	-- Server->client only, so nothing else would ever create them
	Net.Register("Knockback")
	Net.Register("Launch")
	Net.Register("ParryImpact")
	Net.Register("Stagger")
	Net.Register("Fx")

	Players.PlayerRemoving:Connect(function(player)
		lastSwingFx[player] = nil
		lastHit[player] = nil
		guardStart[player] = nil
		parriedAt[player] = nil
		whiffUntil[player] = nil
		parryFramesUntil[player] = nil
		parryArmed[player] = nil
		lastGuardPress[player] = nil
		dodgeUntil[player] = nil
		lastDash[player] = nil
		dashRefund[player] = nil
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
