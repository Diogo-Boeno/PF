--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Data.Weapons)
local WeaponController = require(script.Parent.WeaponController)

local UI_NAME = "HotbarUI"
local HOLDER_NAME = "Holder"
local LABEL_NAME = "ContentName"
local FIND_TIMEOUT = 10

-- Button names follow the keyboard row, not the grid order
local SLOT_KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.One] = "1",
	[Enum.KeyCode.Two] = "2",
	[Enum.KeyCode.Three] = "3",
	[Enum.KeyCode.Four] = "4",
	[Enum.KeyCode.Five] = "5",
	[Enum.KeyCode.Six] = "6",
	[Enum.KeyCode.Seven] = "7",
	[Enum.KeyCode.Eight] = "8",
	[Enum.KeyCode.Nine] = "9",
	[Enum.KeyCode.Zero] = "0",
}

local player = Players.LocalPlayer

local labels: { [string]: TextLabel } = {}

local HotbarController = {}

local function attributeFor(slot: string): string
	return Config.slotAttribute .. slot
end

-- "0" closes the keyboard row, so it sorts past 9
local function layoutOrderFor(slot: string): number
	local n = tonumber(slot)
	if not n then
		return 0
	end
	return if n == 0 then 10 else n
end

local function contentOf(slot: string): string
	local id = player:GetAttribute(attributeFor(slot))
	if type(id) ~= "number" then
		return ""
	end
	local entry = Config.byId[id]
	return if entry then entry.model else ""
end

local function paint(slot: string)
	local label = labels[slot]
	if label then
		label.Text = contentOf(slot)
	end
end

local function activate(slot: string)
	local id = player:GetAttribute(attributeFor(slot))
	if type(id) ~= "number" or not Config.byId[id] then
		return
	end

	-- Hitting the equipped slot again puts it away
	local equipped = player:GetAttribute(Config.attribute)
	WeaponController.request(if equipped == id then Config.unarmed else id)
end

function HotbarController.Start()
	-- Bounded: a missing hand-built UI should say so, not hang the controller forever
	local gui = player:WaitForChild("PlayerGui"):WaitForChild(UI_NAME, FIND_TIMEOUT)
	if not gui then
		warn(`[HotbarController] PlayerGui has no {UI_NAME}`)
		return
	end

	local holder = gui:WaitForChild(HOLDER_NAME, FIND_TIMEOUT)
	if not holder then
		warn(`[HotbarController] {UI_NAME} has no {HOLDER_NAME}`)
		return
	end

	-- Tied LayoutOrder falls back to child order, which differs once replicated
	local layout = holder:FindFirstChildOfClass("UIGridLayout")
	if layout then
		layout.SortOrder = Enum.SortOrder.LayoutOrder
	end

	-- The UI owns how many slots exist; CellNum is untouched serial
	for _, button in holder:GetChildren() do
		if not button:IsA("ImageButton") then
			continue
		end

		local label = button:FindFirstChild(LABEL_NAME)
		if not label or not label:IsA("TextLabel") then
			warn(`[HotbarController] slot "{button.Name}" has no {LABEL_NAME}`)
			continue
		end

		local slot = button.Name
		labels[slot] = label
		button.LayoutOrder = layoutOrderFor(slot)
		paint(slot)

		player:GetAttributeChangedSignal(attributeFor(slot)):Connect(function()
			paint(slot)
		end)

		button.Activated:Connect(function()
			activate(slot)
		end)
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end

		local slot = SLOT_KEYS[input.KeyCode]
		if slot then
			activate(slot)
		end
	end)
end

return HotbarController
