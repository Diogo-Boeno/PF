--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Framework.Net)
local Config = require(ReplicatedStorage.Data.Weapons)

-- Test grant, delete once inventory exists
local STARTER_SLOT = "1"
local STARTER_WEAPON = 1

local lastRequest: { [Player]: number } = {}

local WeaponService = {}

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

function WeaponService.Start()
	Net.On("EquipWeapon", onEquipRequest)

	Players.PlayerAdded:Connect(grantStarter)
	for _, player in Players:GetPlayers() do
		grantStarter(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return WeaponService
