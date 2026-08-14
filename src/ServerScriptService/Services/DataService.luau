--!strict
-- Owns the profile. Everything that has to survive a rejoin passes through here.
--
-- Two lifetimes live in one profile:
--   Memories  — the account. Never wiped.
--   Lineage   — the current character. Wiped when its last life is spent.
--
-- That split is the whole death design: losing a lineage costs the build, not the
-- account, so a run can hurt without making the player start from nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Data.Progression)
-- Wally puts it under Packages; it still only ever runs on the server
local ProfileStore = require(ReplicatedStorage.Packages.profilestore)

local STORE_NAME = "PlayerStore"

-- Bump only for changes old saves cannot survive, and add a migration for it
local SCHEMA_VERSION = 1

local function newLineage(): any
	return {
		Origin = "",
		Lives = Config.startingLives,
		Level = 1,
		RawEssence = 0,
		SpentEssence = 0,
		Attributes = {},
		-- Ceilings already opened by a Rite. Reaching 15 is not the same as passing it.
		Rites = {},
		Proficiency = {},
		Echoes = {},
		Stigmas = {},
		Oath = "",
		Vow = "",
		Inventory = {},
		Equipment = {},
		-- What is in hand right now. Separate from Equipment: holding is not slotting.
		Held = "",
		-- id → last slot it occupied, so using it again sends it back where it was
		LastSlot = {},
		QuestProgress = {},
		Discoveries = {},
	}
end

local TEMPLATE = {
	Schema = SCHEMA_VERSION,
	Memories = 0,
	Unlocks = {},
	-- nil until the player creates one, which is what the creation flow keys off
	Lineage = nil :: any,
}

local store = ProfileStore.New(STORE_NAME, TEMPLATE)
local profiles: { [Player]: any } = {}

local DataService = {}

-- Runs before Reconcile so a migration never fights a freshly filled default
local function migrate(data: any)
	if data.Schema == SCHEMA_VERSION then
		return
	end
	-- No migrations yet: version 1 is the first shipped schema
	data.Schema = SCHEMA_VERSION
end

-- Player attributes are the replication channel everywhere else in this project,
-- so progression uses the same one instead of inventing a second
local function publish(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end

	local data = profile.Data
	player:SetAttribute(Config.loadedAttribute, true)
	player:SetAttribute(Config.memoriesAttribute, data.Memories)

	local lineage = data.Lineage
	if not lineage then
		player:SetAttribute(Config.livesAttribute, 0)
		player:SetAttribute(Config.essenceAttribute, 0)
		player:SetAttribute(Config.levelAttribute, 0)
		return
	end

	player:SetAttribute(Config.livesAttribute, lineage.Lives)
	player:SetAttribute(Config.essenceAttribute, lineage.RawEssence)
	player:SetAttribute(Config.levelAttribute, lineage.Level)

	for name in Config.universal do
		player:SetAttribute(Config.attributeAttribute .. name, lineage.Attributes[name] or 0)
	end

	local origin = Config.origins[lineage.Origin]
	if origin then
		for name in origin.attributes do
			player:SetAttribute(Config.attributeAttribute .. name, lineage.Attributes[name] or 0)
		end
	end
end

function DataService.get(player: Player): any?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

function DataService.lineage(player: Player): any?
	local data = DataService.get(player)
	return if data then data.Lineage else nil
end

function DataService.startLineage(player: Player, origin: string): boolean
	local data = DataService.get(player)
	if not data or data.Lineage or not Config.origins[origin] then
		return false
	end

	local lineage = newLineage()
	lineage.Origin = origin
	data.Lineage = lineage
	publish(player)
	return true
end

function DataService.addEssence(player: Player, amount: number)
	local lineage = DataService.lineage(player)
	if not lineage or amount <= 0 then
		return
	end
	lineage.RawEssence += amount
	publish(player)
end

-- Cost of the point that takes an attribute from `current` to `current + 1`
function DataService.costOf(current: number): number?
	for _, tier in Config.tiers do
		if current < tier.ceiling then
			return Config.essencePerPoint * tier.cost
		end
	end
	return nil
end

function DataService.knowsAttribute(player: Player, name: string): boolean
	if Config.universal[name] then
		return true
	end
	local lineage = DataService.lineage(player)
	local origin = lineage and Config.origins[lineage.Origin]
	return origin ~= nil and origin.attributes[name] ~= nil
end

-- Buying is refused rather than queued: a blocked ceiling is the design, and the
-- caller needs to know which of the two reasons stopped it.
function DataService.buyAttribute(player: Player, name: string): (boolean, string)
	local lineage = DataService.lineage(player)
	if not lineage or not DataService.knowsAttribute(player, name) then
		return false, "unknown"
	end

	local current = lineage.Attributes[name] or 0
	local cost = DataService.costOf(current)
	if not cost then
		return false, "maxed"
	end

	if table.find(Config.riteAt, current) and not table.find(lineage.Rites, current) then
		return false, "rite"
	end

	if lineage.RawEssence < cost then
		return false, "essence"
	end

	lineage.RawEssence -= cost
	lineage.SpentEssence += cost
	lineage.Attributes[name] = current + 1
	publish(player)
	return true, "ok"
end

function DataService.completeRite(player: Player, ceiling: number): boolean
	local lineage = DataService.lineage(player)
	if not lineage or not table.find(Config.riteAt, ceiling) then
		return false
	end
	if table.find(lineage.Rites, ceiling) then
		return false
	end
	table.insert(lineage.Rites, ceiling)
	return true
end

-- Ends the lineage and banks part of what it spent. The account keeps Memories;
-- everything else about that character is gone.
local function endLineage(player: Player)
	local data = DataService.get(player)
	local lineage = data and data.Lineage
	if not data or not lineage then
		return
	end

	data.Memories += math.floor(lineage.SpentEssence * Config.memoryRefund)
	data.Lineage = nil
	publish(player)
end

function DataService.loseLife(player: Player): number
	local lineage = DataService.lineage(player)
	if not lineage then
		return 0
	end

	lineage.Lives -= 1
	if lineage.Lives <= 0 then
		endLineage(player)
		return 0
	end

	publish(player)
	return lineage.Lives
end

function DataService.grantLife(player: Player): boolean
	local lineage = DataService.lineage(player)
	if not lineage or lineage.Lives >= Config.startingLives then
		return false
	end
	lineage.Lives += 1
	publish(player)
	return true
end

local function onPlayerAdded(player: Player)
	local profile

	while player.Parent == Players and ProfileStore.IsClosing == false do
		profile = store:StartSessionAsync(`{player.UserId}`, {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})
		if profile ~= nil then
			break
		end
	end

	if profile == nil then
		player:Kick("Could not load your data. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	migrate(profile.Data)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Session ended — please rejoin.")
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	profiles[player] = profile
	publish(player)
end

function DataService.Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if profile then
			profile:EndSession()
		end
	end)
end

return DataService
