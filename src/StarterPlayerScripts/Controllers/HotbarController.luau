--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Framework.Net)
local State = require(ReplicatedStorage.Shared.Framework.State)
local Items = require(ReplicatedStorage.Data.Items)
local ItemRarity = require(ReplicatedStorage.Shared.UI.ItemRarity)
local ItemCategory = require(ReplicatedStorage.Shared.UI.ItemCategory)

local UI_NAME = "HotbarUI"
local HOLDER_NAME = "Holder"
local STROKE_NAME = "Stroke"
local LABEL_NAME = "ContentName"

local COMPONENTS_NAME = "Components"
local EMPTY_TEMPLATE = "SimpleFrameredWindow"
local EMPTY_NAME = "Empty"

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

type Slot = {
	button: ImageButton,
	stroke: GuiObject?,
	label: TextLabel,
	empty: GuiObject?,
	-- As authored, so a filled slot goes back to the look the UI defined
	image: number,
	background: number,
}

local player = Players.LocalPlayer

local slots: { [string]: Slot } = {}
local emptyTemplate: GuiObject? = nil
local bagOpen = false

local HotbarController = {}

local function attributeFor(slot: string): string
	return Items.slotAttribute .. slot
end

-- "0" closes the keyboard row, so it sorts past 9
local function layoutOrderFor(slot: string): number
	local n = tonumber(slot)
	if not n then
		return 0
	end
	return if n == 0 then 10 else n
end

local function entryOf(slot: string): Items.Entry?
	local id = player:GetAttribute(attributeFor(slot))
	return if type(id) == "string" then Items.byId[id] else nil
end

local function paint(name: string)
	local slot = slots[name]
	if not slot then
		return
	end

	local entry = entryOf(name)
	local filled = entry ~= nil
	slot.label.Text = if entry then entry.label else ""

	-- Hidden, not transparent: UIGridLayout skips invisible children, and that closing
	-- of the gap is what packs the filled slots together and centres them. The key is
	-- the button's name, so slot 8 answers to 8 wherever it lands on screen.
	slot.button.Visible = filled or bagOpen

	-- The placeholder is the whole look of an empty slot, so the button's own chrome
	-- gets out of the way and comes back exactly as authored
	slot.button.ImageTransparency = if filled then slot.image else 1
	slot.button.BackgroundTransparency = if filled then slot.background else 1

	if slot.stroke then
		slot.stroke.Visible = filled
	end

	-- Category fills, rarity outlines — same rule the inventory cell follows
	if entry then
		slot.button.BackgroundColor3 = ItemCategory.get(entry.category).Background
		if slot.stroke and slot.stroke:IsA("ImageLabel") then
			slot.stroke.ImageColor3 = ItemRarity.get(entry.rarity).Border
		end
	end

	-- An empty slot is only worth showing while there is something to drop into it
	if slot.empty then
		slot.empty.Visible = not filled and bagOpen
	end
end

local function repaint()
	for name in slots do
		paint(name)
	end
end

local function activate(name: string)
	local entry = entryOf(name)
	if not entry then
		return
	end

	-- Toggles on what is IN HAND, not on the equipped weapon: `Weapon` is memory now and
	-- survives putting the thing away, so comparing against it never flipped back.
	local held = player:GetAttribute(Items.heldAttribute)
	Net.FireServer("EquipItem", if held == entry.id then nil else entry.id)
end

local function makeEmpty(button: ImageButton): GuiObject?
	local template = emptyTemplate
	if not template then
		return nil
	end

	local frame = template:Clone() :: GuiObject
	frame.Name = EMPTY_NAME
	frame.AnchorPoint = Vector2.zero
	frame.Position = UDim2.fromScale(0, 0)
	frame.Size = UDim2.fromScale(1, 1)
	-- Never a drop blocker: the button under it is what the drag looks for
	frame.Active = false
	frame.Visible = false
	frame.Parent = button
	return frame
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

	-- Authored disabled in Studio to keep the editor clean; in game it is always up
	if gui:IsA("ScreenGui") then
		gui.Enabled = true
	end

	local components = ReplicatedStorage:WaitForChild(COMPONENTS_NAME, FIND_TIMEOUT)
	local source = components and components:FindFirstChild(EMPTY_TEMPLATE)
	if source and source:IsA("GuiObject") then
		emptyTemplate = source
	else
		warn(`[HotbarController] {COMPONENTS_NAME} has no {EMPTY_TEMPLATE}; empty slots stay blank`)
	end

	-- Tied LayoutOrder falls back to child order, which differs once replicated
	local layout = holder:FindFirstChildOfClass("UIGridLayout")
	if layout then
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		-- Empty slots drop out of the row, so what is left has to re-centre
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end

	-- The UI owns how many slots exist; CellNum is untouched serial
	for _, button in holder:GetChildren() do
		if not button:IsA("ImageButton") then
			continue
		end

		-- Recursive: the label lives under Stroke now, and has moved once already
		local label = button:FindFirstChild(LABEL_NAME, true)
		if not label or not label:IsA("TextLabel") then
			warn(`[HotbarController] slot "{button.Name}" has no {LABEL_NAME}`)
			continue
		end

		local stroke = button:FindFirstChild(STROKE_NAME)
		local name = button.Name

		slots[name] = {
			button = button,
			stroke = if stroke and stroke:IsA("GuiObject") then stroke else nil,
			label = label,
			empty = makeEmpty(button),
			image = button.ImageTransparency,
			background = button.BackgroundTransparency,
		}

		button.LayoutOrder = layoutOrderFor(name)
		paint(name)

		player:GetAttributeChangedSignal(attributeFor(name)):Connect(function()
			paint(name)
		end)

		button.Activated:Connect(function()
			activate(name)
		end)
	end

	State.Observe(Items.openState, function(value: any)
		bagOpen = value == true
		repaint()
	end)

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
