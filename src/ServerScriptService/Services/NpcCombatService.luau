--!strict
-- Tag a rig with `CombatNpc` and it arms itself and swings at whoever comes close.
--
-- The weapon is built HERE, not on each client like a player's. That trades the
-- "weapon never crosses the network" rule for not having to generalise the whole
-- client mount path over non-Player holders. Fine for a handful of dummies; if NPCs
-- ever get numerous, move this to the client and drive it off a Model attribute.

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Data.Weapons)
local Tags = require(ReplicatedStorage.Shared.Framework.Tags)
local WeaponService = require(script.Parent.WeaponService)
local NpcBrain = require(script.Parent.NpcBrain)
local Brains = require(game:GetService("ServerStorage").Data.Brains)
local HealthService = require(script.Parent.HealthService)

local TAG = "CombatNpc"

-- Which catalogue entry a tagged rig arms itself with
local NPC_WEAPON = 1

local THINK_INTERVAL = 0.25
local ATTACK_RANGE = 10

-- Which brain a tagged rig uses. Absent falls back to `Brains.DEFAULT`.
local BRAIN_ATTRIBUTE = "Brain"

-- How close an incoming swing has to be before this rig bothers reading it. Wider than
-- ATTACK_RANGE so it starts guarding before the attacker is already on top of it.
local THREAT_RANGE = 13

-- Hitbox swept in front of the rig on the Start marker
local HIT_SIZE = Vector3.new(6, 6, 8)
local HIT_OFFSET = Vector3.new(0, 0, -4)

-- The move, not just the clip: telegraph, Fx and damage all key off which one it is
type Swing = {
	track: AnimationTrack,
	kind: string,
	damage: number,
}

type Npc = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	class: any,
	profile: any,
	-- Its own stream, so one rig's rolls never shift another's
	rng: Random,
	swings: { Swing },
	block: AnimationTrack?,
	parry: AnimationTrack?,
	index: number,
	nextAttack: number,
	-- False until every swing asset has actually arrived. See `swingsReady`.
	ready: boolean,
	-- Committed to answering a swing. Claimed up front so a second telegraph inside the
	-- same exchange does not re-roll a decision already being acted on.
	defendUntil: number,
	alive: boolean,
}

-- Every live rig, so one Telegraphed connection can reach all of them instead of one
-- connection per rig
local npcs: { [Model]: Npc } = {}

local NpcCombatService = {}

local function classFor(): any?
	local entry = Config.byId[NPC_WEAPON]
	if not entry then
		return nil
	end
	local name = entry.classes[Config.defaultGrip]
	return if name then Config.classes[name] else nil
end

local function armWeapon(npc: Npc): Model?
	local folder = ReplicatedStorage:FindFirstChild(Config.folder)
	local entry = Config.byId[NPC_WEAPON]
	local template = folder and entry and folder:FindFirstChild(entry.model)
	if not template or not template:IsA("Model") then
		warn(`[NpcCombatService] no weapon model for id {NPC_WEAPON}`)
		return nil
	end

	local hand = npc.model:FindFirstChild(Config.rig.handPart)
	local handGrip = hand and hand:FindFirstChild(Config.rig.gripAttachment)
	local root = template.PrimaryPart
	local weaponGrip = root and root:FindFirstChild(Config.rig.gripAttachment)
	if not handGrip or not handGrip:IsA("Attachment") then
		warn(`[NpcCombatService] {npc.model.Name} has no {Config.rig.handPart}.{Config.rig.gripAttachment}`)
		return nil
	end
	if not root or not weaponGrip or not weaponGrip:IsA("Attachment") then
		warn(`[NpcCombatService] "{entry.model}" is missing its grip attachment`)
		return nil
	end

	local weapon = template:Clone()
	local weaponRoot = weapon.PrimaryPart :: BasePart

	for _, part in weapon:GetDescendants() do
		if part:IsA("BasePart") then
			part.Massless = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end

	local joint = Instance.new("Motor6D")
	joint.Name = Config.rootName
	joint.Part0 = handGrip.Parent :: BasePart
	joint.Part1 = weaponRoot
	joint.C0 = handGrip.CFrame
	joint.C1 = weaponGrip.CFrame

	weapon.Parent = npc.model
	joint.Parent = weaponRoot

	return weapon
end

-- Follows the same DebugHitbox switch the rest of combat uses
local function trace(message: string)
	if Config.debugHitbox.enabled then
		print(`[Npc] {message}`)
	end
end

local function silencedUntil(npc: Npc): number
	local value = npc.model:GetAttribute(Config.stunUntilAttribute)
	return if type(value) == "number" then value else 0
end

-- Stops whatever is mid-swing. A think-loop check only gates STARTING an attack, so
-- without this a swing thrown a frame before the uppercut still lands from mid-air.
local function cancelSwings(npc: Npc)
	for _, swing in npc.swings do
		if swing.track.IsPlaying then
			swing.track:Stop(0.1)
		end
	end
end

-- The server owns this rig, so it knows where it is looking. No blade raycast needed.
local function strike(npc: Npc, kind: string, damage: number)
	-- Second gate: the marker can fire from an animation that was already running
	if os.clock() < silencedUntil(npc) then
		return
	end

	-- No client of its own to play this locally, so the swing is heard from the server
	WeaponService.announceSwing(npc.model, kind)

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { npc.model }

	local origin = npc.root.CFrame * CFrame.new(HIT_OFFSET)
	local seen: { [Humanoid]: boolean } = {}

	for _, part in workspace:GetPartBoundsInBox(origin, HIT_SIZE, params) do
		local parent = part.Parent
		local hit = parent and parent:FindFirstChildOfClass("Humanoid")
		local hurtable = parent and parent:IsA("Model") and not HealthService.isDefeated(parent)
		if hit and hurtable and hit ~= npc.humanoid and not seen[hit] then
			seen[hit] = true

			-- The rig owns this swing, so it eats posture for being parried the same
			-- way a player does — and `silence` inside resolveHit already takes the
			-- turn, through the attribute this rig polls.
			WeaponService.resolveHit(hit, damage, npc.class, npc.model)
		end
	end
end

-- Kicks the fetch instead of waiting for the first Play to do it. Spawned because it
-- yields, and pcall'd because a failure here must not stop the rig existing.
local function preload(npc: Npc, assets: { Animation })
	task.spawn(function()
		local ok, err = pcall(ContentProvider.PreloadAsync, ContentProvider, assets)
		if not ok then
			warn(`[NpcCombatService] preload failed for {npc.model.Name}: {err}`)
			return
		end

		-- Grace for Length to populate off the loaded asset, then anything still at zero
		-- is a bad id rather than a slow download. Without this the rig just never swings
		-- and says nothing about why.
		task.wait(1)
		for index, swing in npc.swings do
			if swing.track.Length <= 0 then
				warn(`[NpcCombatService] {npc.model.Name} swing {index} never loaded; it will not attack`)
			end
		end
	end)
end

local function loadSwings(npc: Npc)
	local animator = npc.humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		warn(`[NpcCombatService] {npc.model.Name} has no Animator`)
		return
	end

	local ids = table.clone(npc.class.swings)
	table.insert(ids, Config.flourish.animation)

	local assets = {}

	for _, id in ids do
		local asset = Instance.new("Animation")
		asset.AnimationId = id
		table.insert(assets, asset)

		local track = animator:LoadAnimation(asset)
		track.Priority = Enum.AnimationPriority.Action2
		track.Looped = false

		-- The chain closes on the universal kick, exactly as a player's does
		local flourish = id == Config.flourish.animation
		local kind = if flourish then "flourish" else "swing"
		local damage = if flourish then Config.flourish.damage else npc.class.damage

		track:GetMarkerReachedSignal("Start"):Connect(function()
			strike(npc, kind, damage)
		end)

		table.insert(npc.swings, { track = track, kind = kind, damage = damage })
	end

	preload(npc, assets)
end

-- An unloaded track reports Length 0 and plays through in a single frame, firing its
-- Start marker at once. The damage then lands before the telegraph that is supposed to
-- warn about it — the rig hits out of nothing and nobody can read it. So it does not get
-- to swing until the assets are actually here.
local function swingsReady(npc: Npc): boolean
	if npc.ready then
		return true
	end

	for _, swing in npc.swings do
		if swing.track.Length <= 0 then
			return false
		end
	end

	npc.ready = #npc.swings > 0
	if npc.ready then
		trace(`{npc.model.Name} animations ready`)
	end
	return npc.ready
end

-- Block and parry come off the same class the swings do, so the rig defends with the
-- weapon it is actually holding. Above its swings in priority: raising a guard is the
-- rig giving up on the attack, not layering over it.
local function loadGuard(npc: Npc)
	local animator = npc.humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	local function load(id: any, looped: boolean, into: { Animation }): AnimationTrack?
		if type(id) ~= "string" then
			return nil
		end

		local asset = Instance.new("Animation")
		asset.AnimationId = id
		table.insert(into, asset)

		local track = animator:LoadAnimation(asset)
		track.Priority = Enum.AnimationPriority.Action3
		track.Looped = looped
		return track
	end

	local assets = {}
	npc.block = load(npc.class.block, true, assets)
	npc.parry = load(npc.class.parry, false, assets)

	-- Same reason as the swings: an unloaded guard pose is an invisible block
	preload(npc, assets)
end

-- Hops the rig clear of the blow. The i-frames are what actually save it; this is so a
-- dodge reads as a dodge instead of as tanking the hit standing still.
local function dodgeAway(npc: Npc, from: Vector3)
	local spec = Config.dash.ground
	local away = (npc.root.Position - from) * Vector3.new(1, 0, 1)
	local direction = if away.Magnitude > 0 then away.Unit else -npc.root.CFrame.LookVector

	local anchor = Instance.new("Attachment")
	anchor.Name = "Dodge"
	anchor.Parent = npc.root

	local force = Instance.new("LinearVelocity")
	force.Attachment0 = anchor
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.MaxForce = math.huge
	force.VectorVelocity = Vector3.new(direction.X * spec.speed, spec.lift, direction.Z * spec.speed)
	force.Parent = anchor

	-- Destroying the attachment takes the constraint with it
	Debris:AddItem(anchor, spec.time)
end

local function performDefence(npc: Npc, defence: string, from: Vector3)
	if not npc.alive or HealthService.isDefeated(npc.model) then
		trace(`{npc.model.Name} could not {defence}: alive={npc.alive} defeated={HealthService.isDefeated(npc.model)}`)
		return
	end
	-- Hitstun takes the turn, not the read: guarding and parrying stay open, exactly as
	-- they do for a player. Dodging does not — a stunned player cannot dash either.
	if defence == "dodge" and os.clock() < silencedUntil(npc) then
		trace(`{npc.model.Name} too stunned to dodge`)
		return
	end

	trace(`{npc.model.Name} {defence}s now`)

	if defence == "dodge" then
		WeaponService.reportDash(npc.model, false)
		dodgeAway(npc, from)
		return
	end

	-- Committing to the guard drops the swing: a rig cannot do both, exactly as a
	-- player cannot
	cancelSwings(npc)
	WeaponService.setGuard(npc.model, true)

	local track = if defence == "parry" then npc.parry else npc.block
	if track then
		track:Play(0.1)
	end

	task.delay(NpcBrain.holdFor(defence), function()
		WeaponService.setGuard(npc.model, false)
		if track and track.IsPlaying then
			track:Stop(0.15)
		end
	end)
end

-- One incoming swing, one decision. The press is scheduled rather than polled because
-- `parryWindow` is 0.16s and the think loop runs at 0.25s — a tick would miss it.
local function react(npc: Npc, attackerRoot: BasePart, landsAt: number)
	local now = os.clock()
	if now < npc.defendUntil then
		trace(`{npc.model.Name} already committed, {string.format("%.2f", npc.defendUntil - now)}s left`)
		return
	end
	local defence = NpcBrain.chooseDefence(npc.profile, npc.rng)
	if not defence then
		trace(`{npc.model.Name} ({npc.profile.id}) did not read it`)
		return
	end

	local at = NpcBrain.commitAt(npc.profile, defence, landsAt, now, npc.rng)
	if at <= now then
		trace(`{npc.model.Name} read it {string.format("%.2f", now - at)}s too late for {defence}`)
		return
	end

	trace(`{npc.model.Name} will {defence} in {string.format("%.2f", at - now)}s`)

	-- Claimed from the press, not from the impact: the answer is spent when the guard
	-- drops, and reserving past that is time spent ignoring swings for no reason.
	npc.defendUntil = at + NpcBrain.holdFor(defence)

	local from = attackerRoot.Position
	task.delay(at - now, function()
		performDefence(npc, defence, from)
	end)
end

local function nearestPlayer(npc: Npc): BasePart?
	local best: BasePart? = nil
	local bestDistance = ATTACK_RANGE

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = humanoid and humanoid.RootPart
		if root and character and not HealthService.isDefeated(character) then
			-- Crouching shortens the range you register at, which is what makes it a
			-- tradeoff instead of a free slow walk
			local reach = bestDistance
			if character:GetAttribute(Config.crouch.attribute) == true then
				reach *= Config.crouch.stealth
			end

			local distance = (root.Position - npc.root.Position).Magnitude
			if distance < reach then
				best = root
				bestDistance = distance
			end
		end
	end

	return best
end

local function attack(npc: Npc)
	if #npc.swings == 0 then
		return
	end
	npc.index = npc.index % #npc.swings + 1

	local swing = npc.swings[npc.index]
	-- Announced BEFORE the clip, not at the Start marker: a tell that arrives with the
	-- blade is not a tell, and this is the only thing that makes the rig readable
	WeaponService.telegraph(npc.model, swing.kind, npc.class)
	swing.track:Play(0.1)
end

local function think(npc: Npc)
	while npc.alive and npc.model.Parent do
		task.wait(THINK_INTERVAL)

		if HealthService.isDefeated(npc.model) then
			break
		end

		local targetRoot = nearestPlayer(npc)
		if targetRoot then
			-- Face the target: the hitbox is cast straight ahead.
			--
			-- Writing CFrame on a loose assembly ZEROES its velocity, so this has to
			-- put it back. Without that, this loop quietly cancelled every knockback
			-- and launch on the next tick and the body snapped back down.
			local position = npc.root.Position
			local look = (targetRoot.Position - position) * Vector3.new(1, 0, 1)
			if look.Magnitude > 0 then
				local velocity = npc.root.AssemblyLinearVelocity
				npc.root.CFrame = CFrame.lookAt(position, position + look.Unit)
				npc.root.AssemblyLinearVelocity = velocity
			end

			local now = os.clock()

			-- Set by whoever staggered this rig. Players get the same silence through
			-- the Stagger remote; a server-owned body reads it off the character.
			if now < silencedUntil(npc) then
				cancelSwings(npc)
				continue
			end

			-- Guarding and swinging are exclusive. The cooldown advances even on a
			-- failed aggression roll, so a shy rig waits instead of rerolling every tick.
			if now >= npc.nextAttack and now >= npc.defendUntil and swingsReady(npc) then
				npc.nextAttack = now + npc.profile.attackCooldown
				if NpcBrain.shouldAttack(npc.profile, npc.rng) then
					attack(npc)
				end
			end
		end
	end
end

local function bind(model: Instance)
	if not model:IsA("Model") then
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	local class = classFor()
	if not humanoid or not root or not class then
		warn(`[NpcCombatService] {model.Name} needs a Humanoid with a RootPart`)
		return nil
	end

	local named = model:GetAttribute(BRAIN_ATTRIBUTE)
	local profile = if type(named) == "string" then Brains.byId[named] else nil
	if named ~= nil and not profile then
		warn(`[NpcCombatService] {model.Name} names unknown brain "{tostring(named)}"`)
	end

	profile = profile or Brains.byId[Brains.DEFAULT]
	if not profile then
		warn(`[NpcCombatService] {model.Name} has no brain and no default to fall back on`)
		return nil
	end

	local npc: Npc = {
		model = model,
		humanoid = humanoid,
		root = root,
		class = class,
		profile = profile,
		rng = Random.new(),
		swings = {},
		block = nil,
		parry = nil,
		index = 0,
		ready = false,
		nextAttack = 0,
		defendUntil = 0,
		alive = true,
	}

	-- Pin simulation to the server. Roblox hands ownership of a loose assembly to the
	-- nearest client, and then a server-applied force is fought by that client's own
	-- simulation — the body snaps back to where the client thought it was. Every
	-- knockback and launch on this rig depends on the server owning it.
	if not npc.root.Anchored then
		pcall(function()
			npc.root:SetNetworkOwner(nil)
		end)
	end

	HealthService.setup(model)
	armWeapon(npc)
	loadSwings(npc)
	loadGuard(npc)
	npcs[model] = npc
	trace(`{model.Name} bound, brain {profile.id}, block={npc.block ~= nil} parry={npc.parry ~= nil}`)
	task.spawn(think, npc)

	-- Cancel the moment the stun lands, not on the next think tick: a quarter second
	-- is long enough for an already-running swing to connect from mid-air
	local silencer = model:GetAttributeChangedSignal(Config.stunUntilAttribute):Connect(function()
		if os.clock() < silencedUntil(npc) then
			cancelSwings(npc)
		end
	end)

	-- A non-final hit of a multi-hit attack cuts the swing and nothing else: the rig is
	-- not stunned, so `think` may start the next attack straight away. On the signal
	-- rather than in the loop because stabs land faster than THINK_INTERVAL.
	local interrupter = model:GetAttributeChangedSignal(Config.interruptAttribute):Connect(function()
		cancelSwings(npc)
	end)

	return function()
		npc.alive = false
		npcs[model] = nil
		silencer:Disconnect()
		interrupter:Disconnect()
	end
end

function NpcCombatService.Start()
	Tags.bind(TAG, bind)

	-- One connection for every rig. The signal already names the attacker, so each rig
	-- only decides whether that swing is close enough to be its problem.
	WeaponService.Telegraphed:Connect(function(attacker: Model, _kind: string, landsAt: number?)
		-- No `hitAt` on that moveset means nothing to time a press against
		if not landsAt then
			return
		end

		local root = attacker:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return
		end

		local considered, reached = 0, 0
		for model, npc in npcs do
			considered += 1
			local mine = model ~= attacker and npc.alive
			if mine and (npc.root.Position - root.Position).Magnitude <= THREAT_RANGE then
				reached += 1
				react(npc, root, landsAt)
			end
		end

		if considered == 0 or reached == 0 then
			trace(`telegraph from {attacker.Name}: {considered} rig(s) known, {reached} in range`)
		end
	end)
end

return NpcCombatService
