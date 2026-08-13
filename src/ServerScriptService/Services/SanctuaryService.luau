--!strict
-- Buying attributes. Progression is physical: the server checks you are actually
-- standing at a Sanctuary, because "go there" is the mechanic — a client that could
-- buy from anywhere would turn the whole Pilgrimage into a pause menu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Framework.Net)
local Tags = require(ReplicatedStorage.Shared.Framework.Tags)
local DataService = require(script.Parent.DataService)

local TAG = "Sanctuary"
local RANGE = 24
local REQUEST_COOLDOWN = 0.2

local sanctuaries: { [BasePart]: boolean } = {}
local lastRequest: { [Player]: number } = {}

local SanctuaryService = {}

local function nearAny(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end

	for part in sanctuaries do
		if part.Parent and (part.Position - root.Position).Magnitude <= RANGE then
			return true
		end
	end
	return false
end

local function onBuyRequest(player: Player, name: any)
	local now = os.clock()
	if now - (lastRequest[player] or 0) < REQUEST_COOLDOWN then
		return
	end
	lastRequest[player] = now

	if type(name) ~= "string" then
		return
	end

	if not nearAny(player) then
		Net.FireClient("BuyResult", player, false, "distance")
		return
	end

	local ok, reason = DataService.buyAttribute(player, name)
	Net.FireClient("BuyResult", player, ok, reason)
end

function SanctuaryService.Start()
	Tags.bind(TAG, function(instance)
		if not instance:IsA("BasePart") then
			warn(`[SanctuaryService] {instance.Name} is tagged {TAG} but is not a BasePart`)
			return nil
		end

		sanctuaries[instance] = true
		return function()
			sanctuaries[instance] = nil
		end
	end)

	Net.On("BuyAttribute", onBuyRequest)
	Net.Register("BuyResult")

	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return SanctuaryService
