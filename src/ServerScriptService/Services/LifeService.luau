--!strict
-- Spawning and dying. The player only exists in the world while a lineage does,
-- so `Lineage == nil` is the whole gate for the character-creation screen — there
-- is no second flag that could disagree with it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Framework.Net)
local DataService = require(script.Parent.DataService)
local HealthService = require(script.Parent.HealthService)

local RESPAWN_DELAY = 3

local LifeService = {}

local function spawnIfAlive(player: Player)
	if DataService.lineage(player) then
		player:LoadCharacter()
	end
end

local function onDefeated(character: Model)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local remaining = DataService.loseLife(player)
	if remaining <= 0 then
		-- Lineage is gone; the client sees Lives hit 0 and asks for a new character
		Net.FireClient("LineageEnded", player)
		return
	end

	-- The body stays whole on the ground until it is replaced
	task.delay(RESPAWN_DELAY, function()
		if player.Parent == Players then
			spawnIfAlive(player)
		end
	end)
end

-- Humanoid.Died is never used: HealthService owns defeat, and the engine's health is
-- pinned so high it can never fire on its own
local function watchCharacter(character: Model)
	if not character:WaitForChild("Humanoid", 10) then
		return
	end
	HealthService.setup(character)
end

local function onCreateRequest(player: Player, origin: any)
	if type(origin) ~= "string" then
		return
	end
	if DataService.startLineage(player, origin) then
		spawnIfAlive(player)
	end
end

function LifeService.Start()
	-- The server decides when a body exists, not the engine
	Players.CharacterAutoLoads = false

	Net.On("CreateLineage", onCreateRequest)
	Net.Register("LineageEnded")

	HealthService.Defeated:Connect(onDefeated)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(watchCharacter)

		-- DataService loads the profile in its own thread; wait for it rather than
		-- racing it, or the first spawn silently never happens
		task.spawn(function()
			local waited = 0
			while player.Parent == Players and not DataService.get(player) and waited < 20 do
				waited += task.wait(0.2)
			end

			if player.Parent ~= Players then
				return
			end

			-- No lineage means no body: the client sees Lives at 0 and shows creation
			spawnIfAlive(player)
		end)
	end)
end

return LifeService
