--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Framework.Net)
local Config = require(ReplicatedStorage.Data.Weapons)

local HAND_TIMEOUT = 10

type Template = {
	model: Model,
	gripCFrame: CFrame,
}

local templates: { [number]: Template } = {}

local grips: { [Player]: Attachment } = {}
local mounted: { [Player]: Model } = {}
local watching: { [Player]: { RBXScriptConnection } } = {}

local WeaponController = {}

local function unmount(player: Player)
	local model = mounted[player]
	if model then
		mounted[player] = nil
		model:Destroy()
	end
end

local function mount(player: Player, id: number)
	unmount(player)

	local template = templates[id]
	local gripAttachment = grips[player]
	local character = player.Character
	if not template or not gripAttachment or not character then
		return
	end

	local model = template.model:Clone()
	local root = model.PrimaryPart

	-- Motor6D, not Weld: only a joint is animatable
	local joint = Instance.new("Motor6D")
	joint.Name = Config.rootName
	joint.Part0 = gripAttachment.Parent :: BasePart
	joint.Part1 = root
	joint.C0 = gripAttachment.CFrame
	joint.C1 = template.gripCFrame

	-- Parent before joining, or the assembly rebuilds twice
	model.Parent = character
	-- Joint lives on the weapon so one Destroy takes it too
	joint.Parent = root

	mounted[player] = model
end

local function refresh(player: Player)
	local id = player:GetAttribute(Config.attribute)
	if type(id) ~= "number" or id == Config.unarmed then
		unmount(player)
		return
	end
	mount(player, id)
end

local function onCharacterAdded(player: Player, character: Model)
	grips[player] = nil
	mounted[player] = nil

	-- Caching the grip keeps refresh() non-yielding
	local hand = character:WaitForChild(Config.rig.handPart, HAND_TIMEOUT) :: BasePart?
	if not hand then
		warn(`[WeaponController] {player.Name} has no {Config.rig.handPart}`)
		return
	end

	local gripAttachment = hand:WaitForChild(Config.rig.gripAttachment, HAND_TIMEOUT) :: Attachment?
	if not gripAttachment then
		warn(`[WeaponController] {player.Name} has no {Config.rig.gripAttachment}`)
		return
	end

	if player.Character ~= character then
		return
	end

	grips[player] = gripAttachment
	refresh(player)
end

local function watch(player: Player)
	watching[player] = {
		player:GetAttributeChangedSignal(Config.attribute):Connect(function()
			refresh(player)
		end),
		player.CharacterAdded:Connect(function(character: Model)
			onCharacterAdded(player, character)
		end),
		player.CharacterRemoving:Connect(function()
			grips[player] = nil
			mounted[player] = nil
		end),
	}

	local character = player.Character
	if character then
		task.spawn(onCharacterAdded, player, character)
	end
end

local function unwatch(player: Player)
	local connections = watching[player]
	if connections then
		watching[player] = nil
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	grips[player] = nil
	mounted[player] = nil
end

local function loadTemplates()
	local folder = ReplicatedStorage:WaitForChild(Config.folder)

	for id, entry in Config.byId do
		local name = entry.model
		local model = folder:FindFirstChild(name)
		if not model or not model:IsA("Model") then
			warn(`[WeaponController] missing weapon model "{name}"`)
			continue
		end

		local root = model.PrimaryPart
		if not root or root.Name ~= Config.rootName then
			warn(`[WeaponController] "{name}" needs PrimaryPart named {Config.rootName}`)
			continue
		end

		local gripAttachment = root:FindFirstChild(Config.rig.gripAttachment)
		if not gripAttachment or not gripAttachment:IsA("Attachment") then
			warn(`[WeaponController] "{name}" is missing {Config.rootName}.{Config.rig.gripAttachment}`)
			continue
		end

		-- Once per template, not per clone
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Massless = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			end
		end

		templates[id] = {
			model = model,
			gripCFrame = gripAttachment.CFrame,
		}
	end
end

function WeaponController.request(id: number)
	Net.FireServer("EquipWeapon", id)
end

function WeaponController.mountedFor(target: Player): Model?
	return mounted[target]
end

function WeaponController.Start()
	loadTemplates()

	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(unwatch)

	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return WeaponController
