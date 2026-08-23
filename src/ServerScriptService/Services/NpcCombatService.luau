--!strict
-- Tag a rig with `CombatNpc` and it arms itself and swings at whoever comes close.
--
-- The weapon is built HERE, not on each client like a player's. That trades the
-- "weapon never crosses the network" rule for not having to generalise the whole
-- client mount path over non-Player holders. Fine for a handful of dummies; if NPCs
-- ever get numerous, move this to the client and drive it off a Model attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Data.Weapons)
local Tags = require(ReplicatedStorage.Shared.Framework.Tags)
local WeaponService = require(script.Parent.WeaponService)
local HealthService = require(script.Parent.HealthService)

local TAG = "CombatNpc"

-- Which catalogue entry a tagged rig arms itself with
local NPC_WEAPON = 1

local THINK_INTERVAL = 0.25
local ATTACK_RANGE = 10
local ATTACK_COOLDOWN = 1.6

-- Hitbox swept in front of the rig on the Start marker
local HIT_SIZE = Vector3.new(6, 6, 8)
local HIT_OFFSET = Vector3.new(0, 0, -4)

type Npc = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	class: any,
	swings: { AnimationTrack },
	index: number,
	nextAttack: number,
	lockedUntil: number,
	alive: boolean,
}

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

local function silencedUntil(npc: Npc): number
	local value = npc.model:GetAttribute(Config.stunUntilAttribute)
	return if type(value) == "number" then value else 0
end

-- Stops whatever is mid-swing. A think-loop check only gates STARTING an attack, so
-- without this a swing thrown a frame before the uppercut still lands from mid-air.
local function cancelSwings(npc: Npc)
	for _, track in npc.swings do
		if track.IsPlaying then
			track:Stop(0.1)
		end
	end
end

-- The server owns this rig, so it knows where it is looking. No blade raycast needed.
local function strike(npc: Npc, damage: number)
	-- Second gate: the marker can fire from an animation that was already running
	if os.clock() < silencedUntil(npc) then
		return
	end

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

			-- `nil` attacker: nobody owns this swing, so no posture changes hands.
			-- Getting parried still costs the turn, exactly as it costs a player theirs.
			if WeaponService.resolveHit(hit, damage, npc.class, nil) == "parried" then
				npc.lockedUntil = os.clock() + Config.guard.parriedLock
			end
		end
	end
end

local function loadSwings(npc: Npc)
	local animator = npc.humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		warn(`[NpcCombatService] {npc.model.Name} has no Animator`)
		return
	end

	local ids = table.clone(npc.class.swings)
	table.insert(ids, Config.flourish.animation)

	for _, id in ids do
		local asset = Instance.new("Animation")
		asset.AnimationId = id

		local track = animator:LoadAnimation(asset)
		track.Priority = Enum.AnimationPriority.Action2
		track.Looped = false

		local damage = if id == Config.flourish.animation then Config.flourish.damage else npc.class.damage
		track:GetMarkerReachedSignal("Start"):Connect(function()
			strike(npc, damage)
		end)

		table.insert(npc.swings, track)
	end
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
	npc.swings[npc.index]:Play(0.1)
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

			-- Being parried costs the NPC its turn, same as it costs a player theirs
			if now >= npc.nextAttack and now >= npc.lockedUntil then
				npc.nextAttack = now + ATTACK_COOLDOWN
				attack(npc)
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

	local npc: Npc = {
		model = model,
		humanoid = humanoid,
		root = root,
		class = class,
		swings = {},
		index = 0,
		nextAttack = 0,
		lockedUntil = 0,
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
		silencer:Disconnect()
		interrupter:Disconnect()
	end
end

function NpcCombatService.Start()
	Tags.bind(TAG, bind)
end

return NpcCombatService
