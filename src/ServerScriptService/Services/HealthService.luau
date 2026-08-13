--!strict
-- Health lives in a character attribute, not in Humanoid.Health.
--
-- Roblox's health kills by dismembering the rig, which is wrong for this game: a
-- character is never blown apart, it is finished. Owning the number also means armour,
-- resistances and execution states are ours to define instead of fought against.
--
-- The Humanoid is pinned far above anything reachable so falls, lava and the engine's
-- own damage can never end a character behind our back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Combat vitals live in Weapons alongside posture and stun, and are shared so the
-- HUD reads the same names instead of a second copy that can drift
local Config = require(ReplicatedStorage.Data.Weapons)
local Signal = require(ReplicatedStorage.Shared.Framework.Signal)

local HEALTH = Config.healthAttribute
local MAX_HEALTH = Config.maxHealthAttribute
local DEFEATED = Config.defeatedAttribute
local DEFAULT_MAX = Config.defaultMaxHealth

local ENGINE_POOL = 1e6

local HealthService = {}

-- Fired once per character when its health reaches zero
HealthService.Defeated = Signal.new()

local function humanoidOf(character: Model): Humanoid?
	return character:FindFirstChildOfClass("Humanoid")
end

function HealthService.setup(character: Model, maxHealth: number?)
	local humanoid = humanoidOf(character)
	if not humanoid then
		return
	end

	-- Take the engine out of the killing business entirely
	humanoid.MaxHealth = ENGINE_POOL
	humanoid.Health = ENGINE_POOL
	humanoid.BreakJointsOnDeath = false

	local max = maxHealth or DEFAULT_MAX
	character:SetAttribute(MAX_HEALTH, max)
	character:SetAttribute(HEALTH, max)
	character:SetAttribute(DEFEATED, false)
end

function HealthService.get(character: Model): number
	local value = character:GetAttribute(HEALTH)
	return if type(value) == "number" then value else 0
end

function HealthService.isDefeated(character: Model): boolean
	return character:GetAttribute(DEFEATED) == true
end

function HealthService.heal(character: Model, amount: number)
	if amount <= 0 or HealthService.isDefeated(character) then
		return
	end

	local max = character:GetAttribute(MAX_HEALTH)
	local ceiling = if type(max) == "number" then max else DEFAULT_MAX
	character:SetAttribute(HEALTH, math.min(HealthService.get(character) + amount, ceiling))
end

-- Returns true when this hit is the one that finished them, so callers can react
-- without racing the Defeated signal
function HealthService.damage(character: Model, amount: number): boolean
	if amount <= 0 or HealthService.isDefeated(character) then
		return false
	end

	local left = math.max(HealthService.get(character) - amount, 0)
	character:SetAttribute(HEALTH, left)

	if left > 0 then
		return false
	end

	character:SetAttribute(DEFEATED, true)

	-- The rig stays whole and simply stops answering input
	local humanoid = humanoidOf(character)
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
	end

	HealthService.Defeated:Fire(character)
	return true
end

return HealthService
