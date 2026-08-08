--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Framework.Net)
local Config = require(ReplicatedStorage.Data.Weapons)

local lastRequest: { [Player]: number } = {}

local WeaponService = {}

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

	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return WeaponService
