--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Framework.Net)
local Signal = require(ReplicatedStorage.Shared.Framework.Signal)
local Config = require(ReplicatedStorage.Data.Weapons)
local HealthService = require(script.Parent.HealthService)

local Guard = Config.guard

local lastSwingFx: { [Player]: { [string]: number } } = {}

-- Weak keys so a dead target's entry goes away without a sweep
local WEAK_KEYS = { __mode = "k" }
local lastHit: { [Player]: { [Humanoid]: { [number]: number } } } = {}

-- Everything a body needs to defend itself, keyed by the CHARACTER rather than the
-- Player. Combat state belongs to the body — the same place HealthService already keeps
-- Health and Defeated — and that is what lets an NPC parry, block and dodge through the
-- one set of rules instead of a second implementation.
type Fighter = {
	-- nil means not holding guard at all
	guardStart: number?,
	parriedAt: number,
	whiffUntil: number,

	-- Earned by landing a parry. Valid with F already released, which is what turns one
	-- press into a chain instead of one refusal.
	parryFramesUntil: number,

	-- Guarding and being able to parry are different states. A hold that came too soon
	-- after the last one still blocks, it just is not armed.
	parryArmed: boolean,
	lastGuardPress: number,

	-- Dash invulnerability. Consumed by the first hit it turns away, never a duration
	-- that eats a whole flurry — that would beat any guard for free.
	dodgeUntil: number,
	lastDash: number,
	dashRefund: boolean,
	posture: number,
}

-- Weak keys: a character that leaves takes its record with it, no sweep and no
-- PlayerRemoving branch to forget
local fighters: { [Model]: Fighter } = setmetatable({}, WEAK_KEYS) :: any

local WeaponService = {}

-- Fired the moment a body commits to an attack, whoever owns it: (attacker, kind,
-- landsAt). `landsAt` is derived from the class here, never taken from the report, so a
-- client cannot lie its own swing into unreadable timing.
--
-- Everything that reacts to an incoming attack hangs off this — the outline, the parry
-- glow, and whatever decides an NPC should raise its guard.
WeaponService.Telegraphed = Signal.new()

-- Created on demand so no caller has to nil-check. The record is cheap and collectable.
local function fighterOf(character: Model): Fighter
	local found = fighters[character]
	if not found then
		found = {
			guardStart = nil,
			parriedAt = 0,
			whiffUntil = 0,
			parryFramesUntil = 0,
			parryArmed = false,
			lastGuardPress = -math.huge,
			dodgeUntil = 0,
			lastDash = -math.huge,
			dashRefund = false,
			posture = 0,
		}
		fighters[character] = found
	end
	return found
end

local function stunned(character: Model): boolean
	return character:GetAttribute(Config.stunAttribute) == true
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
-- `lockGuard` is what separates the two silences. Plain hitstun leaves the guard usable,
-- so a parry is still the way out; being parried takes even that, which is the turn the
-- attacker paid for.
function WeaponService.silence(character: Model?, duration: number, lockGuard: boolean?)
	if not character then
		return
	end

	local victim = Players:GetPlayerFromCharacter(character)
	if victim then
		Net.FireClient("Stagger", victim, duration, lockGuard)
	else
		character:SetAttribute(Config.stunUntilAttribute, os.clock() + duration)
	end
end

-- Cuts a body's current swing without stunning it: what a non-final hit of a multi-hit
-- attack costs. Same two routes as `silence`, and for the same reason — forgetting the
-- server-owned branch is silent, and the rig simply keeps swinging.
local function interrupt(character: Model?, drag: any)
	if not character then
		return
	end

	local victim = Players:GetPlayerFromCharacter(character)
	if victim then
		Net.FireClient("Interrupt", victim, if drag then drag.speed else nil, if drag then drag.duration else nil)
	else
		character:SetAttribute(Config.interruptAttribute, os.clock())
	end
end

-- How long a hit buys is a property of the weapon that landed it
local function hitstunOf(class: any?): number
	local value = class and class.hitstun
	return if type(value) == "number" then value else Config.hitstun
end

local function setPosture(character: Model, value: number)
	local clamped = math.clamp(value, 0, Guard.postureMax)
	fighterOf(character).posture = clamped

	-- Decay steps every frame. Replicating the raw float would be 60 writes a second
	-- per body for movement no UI can resolve; whole points are what a bar shows.
	local shown = math.floor(clamped)
	if character:GetAttribute(Config.postureAttribute) ~= shown then
		character:SetAttribute(Config.postureAttribute, shown)
	end
end

local function breakGuard(character: Model)
	setPosture(character, 0)
	fighterOf(character).guardStart = nil
	character:SetAttribute(Config.stunAttribute, true)

	-- Also down the silence path, which is the only one a server-owned rig reads. A
	-- guard-broken NPC that kept swinging is exactly the failure `silence` exists for.
	WeaponService.silence(character, Guard.stunTime)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	broadcastFx("guardBreak", if humanoid then humanoid.RootPart else nil, character)

	task.delay(Guard.stunTime, function()
		if character.Parent then
			character:SetAttribute(Config.stunAttribute, false)
		end
	end)
end

local function addPosture(character: Model, amount: number)
	local value = fighterOf(character).posture + amount
	if value >= Guard.postureMax then
		breakGuard(character)
		return
	end
	setPosture(character, value)
end

local function lockParry(character: Model)
	local expiry = os.clock() + Guard.parryWhiff
	fighterOf(character).whiffUntil = expiry
	character:SetAttribute(Config.parryLockAttribute, true)

	task.delay(Guard.parryWhiff, function()
		-- A later whiff pushed the expiry out; that timer owns the unlock
		if character.Parent and fighterOf(character).whiffUntil == expiry then
			character:SetAttribute(Config.parryLockAttribute, false)
		end
	end)
end

-- A hold that never met an attack inside the window costs the parry, not the block.
--
-- Takes a character, not a Player: this is the whole guard rule set, and an NPC brain
-- calls it directly rather than growing a second copy that drifts.
function WeaponService.setGuard(character: Model?, holding: boolean)
	if not character then
		return
	end

	local fighter = fighterOf(character)

	if not holding then
		local held = fighter.guardStart
		fighter.guardStart = nil

		-- Released while still inside the parry window — never once it has settled into
		-- a block. The frames carry the read past the release, so tapping F on a swing
		-- you saw coming is enough, and the defender may attack straight after.
		--
		-- Locked out earns nothing: without this, alternating taps produced near
		-- continuous frames and the whiff penalty never caught up.
		local now = os.clock()
		if held and fighter.parryArmed and now - held <= Guard.parryWindow and now >= fighter.whiffUntil then
			fighter.parryFramesUntil = now + Guard.parryFrames
		end
		return
	end

	if fighter.guardStart or stunned(character) then
		return
	end

	local now = os.clock()
	fighter.guardStart = now

	-- Mashing does not re-open the window. The hold still blocks; it just cannot parry.
	local armed = now - fighter.lastGuardPress >= Guard.parryRearm
	fighter.lastGuardPress = now
	fighter.parryArmed = armed

	-- Already locked out, or not armed: a plain block, and nothing to schedule
	if not armed or now < fighter.whiffUntil then
		return
	end

	task.delay(Guard.parryWindow, function()
		-- Releasing early does not forgive it: pressing F is what commits the parry
		if fighter.parriedAt < now then
			lockParry(character)
		end
	end)
end

-- The client owns when a dash starts, so it says so. Nothing here trusts the timing
-- beyond a cooldown: at worst a cheat buys itself the same window a legit dash gets.
--
-- Character-keyed for the same reason as `setGuard`: an NPC dodge has to buy the same
-- i-frames a player's does, under the same cooldown.
function WeaponService.reportDash(character: Model?, cancelled: boolean?)
	if not character then
		return
	end

	local fighter = fighterOf(character)
	local now = os.clock()
	local spec = Config.dash

	if cancelled == true then
		-- Cancelling spends the dash for a longer read. It does not stack with the
		-- window already running; the later deadline simply wins.
		fighter.dodgeUntil = math.max(fighter.dodgeUntil, now + spec.cancelIframes)

		-- Mirrors the client's refund. Only one is ever outstanding, so this cannot
		-- become an unlimited pass through the cooldown.
		fighter.dashRefund = true
		return
	end

	-- Held to the same cooldown the client obeys, so spamming the remote cannot buy
	-- more invulnerability than dashing legitimately would. A refund is the one
	-- sanctioned way past it.
	if fighter.dashRefund then
		fighter.dashRefund = false
	elseif now - fighter.lastDash < spec.cooldown then
		return
	end

	fighter.lastDash = now
	fighter.dodgeUntil = now + spec.iframes
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
local function onSwungReport(player: Player, event: any, ordinal: any, rate: any)
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

	-- Each stab of a flurry is its own event to the throttle. Sharing one key, the same
	-- 0.15s that keeps a spammer quiet would swallow two thirds of a three-hit critical.
	local key = if type(ordinal) == "number" then `{event}{ordinal}` else event

	local now = os.clock()
	if now - (seen[key] or 0) < Config.swingFxCooldown then
		return
	end
	seen[key] = now

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	-- Cosmetic, so the client owns it for its own weapon — but bounded, because an
	-- unbounded PlaybackSpeed is a noise weapon pointed at everyone else
	local range = Config.swingFxPitch
	local pitch = if type(rate) == "number" then math.clamp(rate, range.Min, range.Max) else 1

	for _, other in Players:GetPlayers() do
		if other ~= player then
			Net.FireClient("Fx", other, event, root.Position, character, pitch)
		end
	end
end

-- Telegraph is the windup tell. Same closed set and same rate limit as Swung, because
-- it is the other Fx a client is allowed to ask for.
-- The one place an attack becomes public knowledge. A player reports its own windup; an
-- NPC's is raised by the server. Both land here, so neither is readable by rules the
-- other does not obey.
function WeaponService.telegraph(character: Model?, kind: any, class: any)
	if not character or type(kind) ~= "string" or Config.swingFx[kind] ~= true then
		return
	end

	local windup = if class then Config.windupOf(class, kind) else nil
	WeaponService.Telegraphed:Fire(character, kind, if windup then os.clock() + windup else nil)

	local attacker = Players:GetPlayerFromCharacter(character)
	for _, other in Players:GetPlayers() do
		-- The attacker already drew its own outline locally
		if other ~= attacker then
			Net.FireClient("Telegraph", other, kind, character)
		end
	end

	-- A player's client fires its own tell, which honours an authored `Tell` marker. A
	-- server-owned rig has no client, so the `hitAt` fallback is scheduled here —
	-- without it an NPC swing carries no parry window for anyone to read.
	if not attacker and windup then
		task.delay(math.max(windup - Guard.parryWindow, 0), function()
			if not character.Parent then
				return
			end
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			broadcastFx(kind .. "Tell", if humanoid then humanoid.RootPart else nil, character)
		end)
	end

	if Config.debugHitbox.enabled then
		local when = if windup then string.format("%.2fs", windup) else "unknown (no hitAt)"
		print(`[Telegraph] {character.Name} {kind}, lands in {when}`)
	end
end

-- The server-owned mirror of the client's own announce: a rig has no client to play its
-- swing locally, so the sound comes from here.
function WeaponService.announceSwing(character: Model, kind: string)
	if Config.swingFx[kind] ~= true then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	broadcastFx(kind, if humanoid then humanoid.RootPart else nil, character)
end

local function onTelegraphReport(player: Player, event: any)
	WeaponService.telegraph(player.Character, event, classFor(player))
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
local function damageFor(class: any, kind: any, ordinal: any): number?
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
		if not class.heavy then
			return nil
		end
		-- A multi-hit critical prices each stab separately; the ordinal has to name one
		local hits = class.heavy.hits
		if hits then
			return if type(ordinal) == "number" then hits[ordinal] else nil
		end
		return class.heavy.damage
	end
	if kind == "aerial" then
		return if class.aerial then class.aerial.damage else nil
	end
	return nil
end

-- Guard resolution. Both sides are characters, so a player and an NPC run the exact
-- same parry, block and dodge rules — there is no second implementation to drift.
-- `attacker` is nil only when nobody owns the swing.
--
-- `chain` present means more hits of this attack are still coming, and it carries the
-- drag they apply. Only the last hit of a flurry buys a turn — from a clean hit OR from
-- a parry — so an early one interrupts instead of stunning and never locks the attacker.
function WeaponService.resolveHit(target: Humanoid, damage: number, class: any, attacker: Model?, chain: any?): string
	local parent = target.Parent
	local defender = if parent and parent:IsA("Model") then parent else nil
	if not defender then
		return "hit"
	end

	local fighter = fighterOf(defender)
	local now = os.clock()

	-- I-frames answer before anything else and are spent on contact. One dash turns
	-- away one blow; the rest of the flurry lands.
	if now < fighter.dodgeUntil then
		fighter.dodgeUntil = 0
		broadcastFx("dodge", target.RootPart, defender)
		return "dodged"
	end

	local held = fighter.guardStart

	-- Two ways to parry, and the second is the point of this system:
	--   window — pressed F recently enough, the deliberate read
	--   frames — earned by the previous parry, and valid with F already released
	-- Chaining is what lets one well-timed press turn away a flurry.
	local inWindow = held ~= nil
		and fighter.parryArmed
		and now - held <= Guard.parryWindow
		and now >= fighter.whiffUntil
	local inFrames = now < fighter.parryFramesUntil

	if not inWindow and not inFrames then
		if not held then
			hurt(target, damage)
			broadcastFx("hit", target.RootPart, defender)

			-- Only a clean hit staggers. Blocking or parrying is the reward for
			-- defending, so neither may cost the defender their turn.
			if chain then
				interrupt(defender, chain.drag)
			else
				WeaponService.silence(defender, hitstunOf(class))
			end
			return "hit"
		end

		-- Guarding but past the window: an ordinary block
		addPosture(defender, damage * Guard.postureFactor)
		broadcastFx("blocked", target.RootPart, defender)
		if Config.debugHitbox.enabled then
			print(`[Block] {defender.Name} blocked {if attacker then attacker.Name else "nobody"}`)
		end
		if class and class.chip then
			target:TakeDamage(damage * class.chip)
		end
		return "blocked"
	end

	fighter.parriedAt = now

	-- Every parry pays for the next one
	fighter.parryFramesUntil = now + Guard.parryFrames

	addPosture(defender, -Guard.parryRelief)
	broadcastFx("parry", target.RootPart, defender)

	-- The impact animation belongs to whoever caught the blow, and it is their own
	-- weapon absorbing it — so the side comes from the DEFENDER's class, not the
	-- attacker's. The attacker just loses their turn.
	--
	-- Player-only: it is a client remote, and a server-owned rig has no client. An NPC
	-- playing its own parry animation is the execution piece, not this one.
	local victim = Players:GetPlayerFromCharacter(defender)
	if victim then
		local defenderSide = parriedSide(classFor(victim))
		if defenderSide then
			Net.FireClient("ParryImpact", victim, defenderSide)
		end
	end

	if attacker then
		-- Posture lands on every parried stab: turning away a whole flurry should
		-- move the bar three times. Only the turn itself waits for the last one.
		addPosture(attacker, Guard.parryPosture)
		if not chain then
			-- Guard locked too: being parried costs the turn outright, unlike hitstun
			WeaponService.silence(attacker, Guard.parriedLock, true)
		end
	end

	if Config.debugHitbox.enabled then
		local how = if inWindow then "window" else "frames"
		print(`[Parry] {defender.Name} parried {if attacker then attacker.Name else "nobody"} ({how})`)
	end
	return "parried"
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
local function onHitReport(player: Player, target: any, kind: any, ordinal: any)
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

	local damage = damageFor(class, kind, ordinal)
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

	-- Keyed by ordinal as well as target: the three stabs of a flurry all land inside
	-- one cooldown window, while repeating the same stab stays barred
	local slot = seen[target]
	if not slot then
		slot = {}
		seen[target] = slot
	end

	local key = if type(ordinal) == "number" then ordinal else 0
	local now = os.clock()
	if now - (slot[key] or 0) < Config.hitCooldown then
		return
	end
	slot[key] = now

	-- More stabs still to come, so this one interrupts instead of buying the turn
	local hits = if kind == "heavy" and class.heavy then class.heavy.hits else nil
	local chain = if hits and type(ordinal) == "number" and ordinal < #hits then { drag = class.heavy.drag } else nil

	if WeaponService.resolveHit(target, damage, class, character, chain) ~= "hit" then
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
		WeaponService.silence(targetCharacter, spec.victimStun)

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
	-- Thin adapters: the rules live in the character-keyed functions, and an NPC brain
	-- calls those same ones
	Net.On("SetGuard", function(player: Player, holding: any)
		WeaponService.setGuard(player.Character, holding == true)
	end)
	Net.On("Dash", function(player: Player, cancelled: any)
		WeaponService.reportDash(player.Character, cancelled == true)
	end)
	Net.On("Swung", onSwungReport)
	Net.On("Telegraph", onTelegraphReport)

	-- Server->client only, so nothing else would ever create them
	Net.Register("Knockback")
	Net.Register("Launch")
	Net.Register("ParryImpact")
	Net.Register("Stagger")
	Net.Register("Interrupt")
	Net.Register("Fx")

	-- Only the report rate limits are keyed by Player now. Combat state lives on the
	-- character and leaves with it, which is what the weak keys are for.
	Players.PlayerRemoving:Connect(function(player)
		lastSwingFx[player] = nil
		lastHit[player] = nil
	end)

	-- Posture always drains, for every body that has any. Stepped rather than computed
	-- on read so the replicated attribute stays honest for whatever UI reads it later.
	RunService.Heartbeat:Connect(function(delta: number)
		for character, fighter in fighters do
			if fighter.posture > 0 then
				setPosture(character, fighter.posture - Guard.postureDecay * delta)
			end
		end
	end)
end

return WeaponService
