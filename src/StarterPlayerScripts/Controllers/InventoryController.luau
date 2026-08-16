--!strict
-- Drives the hand-built Inventory. The ScreenGui already holds every category, so
-- this only fills them: it clones a cell per carried item and never builds hierarchy.
--
-- The UI decides which categories exist — the Container's children are the list, not
-- anything written here.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Framework.Net)
local State = require(ReplicatedStorage.Shared.Framework.State)
local Items = require(ReplicatedStorage.Data.Items)
local ItemRarity = require(ReplicatedStorage.Shared.UI.ItemRarity)

local TOGGLE_KEY = Enum.KeyCode.Tab
local TOGGLE_ACTION = "InventoryToggle"

local GUI_NAME = "Inventory"
local STATS_NAME = "Stats"
local HOTBAR_NAME = "HotbarUI"
local HOLDER_NAME = "Holder"
local BACKGROUND_NAME = "Background"
local CONTAINER_NAME = "Container"
local CELLS_NAME = "Frame"
local CATEGORY_NAME = "Category"
local QUANTITY_NAME = "Quantity"
local LABEL_NAME = "ContentName"
local STROKE_NAME = "Stroke"

local COMPONENTS_NAME = "Components"
local TEMPLATE_NAME = "CellButton"

local DRAG_GUI_NAME = "InventoryDragUI"
local DRAG_ORDER = 50

-- Pixels of travel that turn a press into a drag instead of a click
local DRAG_THRESHOLD = 6
local FIND_TIMEOUT = 10

type Category = {
	holder: Instance,
	quantity: TextLabel?,
	count: number,
}

local player = Players.LocalPlayer

local playerGui: PlayerGui
local inventory: ScreenGui?
local stats: Instance?
local hotbarHolder: Instance?
local template: GuiButton?
local dragGui: ScreenGui?

local categories: { [string]: Category } = {}
local owned: { [string]: number } = {}
local open = false

-- `slot` is the hotbar slot the drag came out of, nil when it came from the grid.
-- It is what tells a drop apart: back to the bag, or onto the bar.
local pending: { id: string, source: GuiButton, origin: Vector2, slot: string? }? = nil
local drag: { id: string, ghost: GuiObject, slot: string? }? = nil

local InventoryController = {}

local function mouse(): Vector2
	return UserInputService:GetMouseLocation()
end

-- GetMouseLocation carries the top-bar inset; AbsolutePosition space does not
local function slotAt(position: Vector2): string?
	local holder = hotbarHolder
	if not holder then
		return nil
	end

	local inset = GuiService:GetGuiInset()
	local point = position - Vector2.new(inset.X, inset.Y)

	for _, object in playerGui:GetGuiObjectsAtPosition(point.X, point.Y) do
		if object.Parent == holder and object:IsA("ImageButton") then
			return object.Name
		end
	end
	return nil
end

local function cancelDrag()
	pending = nil

	local current = drag
	if current then
		drag = nil
		current.ghost:Destroy()
	end
end

-- True while the cursor is over the open panel, which is what "back to the bag" means
local function overInventory(position: Vector2): boolean
	local panel = inventory
	if not panel or not open then
		return false
	end

	local inset = GuiService:GetGuiInset()
	local point = position - Vector2.new(inset.X, inset.Y)

	for _, object in playerGui:GetGuiObjectsAtPosition(point.X, point.Y) do
		if object:IsDescendantOf(panel) then
			return true
		end
	end
	return false
end

local function startDrag(waiting: { id: string, source: GuiButton, origin: Vector2, slot: string? })
	local parent = dragGui
	if not parent then
		return
	end

	local source = waiting.source
	local ghost = source:Clone() :: GuiObject
	ghost.Name = "Ghost"
	ghost.Active = false
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.Size = UDim2.fromOffset(source.AbsoluteSize.X, source.AbsoluteSize.Y)
	ghost.Position = UDim2.fromOffset(mouse().X, mouse().Y)
	ghost.ZIndex = DRAG_ORDER
	ghost.Parent = parent

	drag = { id = waiting.id, ghost = ghost, slot = waiting.slot }
end

local function isDragInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- Any item goes to the hand, not just a weapon. The server checks possession.
local function equip(id: string)
	if Items.byId[id] then
		Net.FireServer("EquipItem", id)
	end
end

local function buildCell(category: Category, entry: Items.Entry)
	local source = template
	if not source then
		return
	end

	local cell = source:Clone()
	cell.Name = entry.id

	local label = cell:FindFirstChild(LABEL_NAME, true)
	if label and label:IsA("TextLabel") then
		label.Text = entry.label
	end

	-- Rarity owns both fill and border. Category is communicated by which section the
	-- cell sits in, so painting it here would say it twice.
	local rarity = ItemRarity.get(entry.rarity)
	cell.BackgroundColor3 = rarity.Fill

	local stroke = cell:FindFirstChild(STROKE_NAME)
	if stroke and stroke:IsA("ImageLabel") then
		stroke.ImageColor3 = ItemRarity.borderOf(rarity.Fill)
	end

	-- Activated is not used: a press that turns into a drag must not also equip
	cell.InputBegan:Connect(function(input: InputObject)
		if isDragInput(input) then
			pending = { id = entry.id, source = cell, origin = mouse() }
		end
	end)

	cell.Parent = category.holder
	category.count += 1
end

local function slottedIds(): { [string]: boolean }
	local set = {}
	for _, slot in Items.slots do
		local id = player:GetAttribute(Items.slotAttribute .. slot)
		if type(id) == "string" then
			set[id] = true
		end
	end
	return set
end

local function rebuild()
	-- An item on the hotbar is out of the bag. Listing it in both reads as a duplicate.
	local slotted = slottedIds()

	for _, category in categories do
		for _, child in category.holder:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
		category.count = 0
	end

	for id, amount in owned do
		local entry = Items.byId[id]
		if not entry or amount <= 0 or slotted[id] then
			continue
		end

		local category = categories[entry.category]
		if category then
			buildCell(category, entry)
		end
	end

	for _, category in categories do
		if category.quantity then
			category.quantity.Text = tostring(category.count)
		end
	end
end

-- Stats is a hand-built container; whether it is the ScreenGui or holds several is
-- the UI's call, so both shapes answer here
local function setStatsVisible(visible: boolean)
	local folder = stats
	if not folder then
		return
	end

	if folder:IsA("ScreenGui") then
		folder.Enabled = visible
		return
	end

	for _, child in folder:GetChildren() do
		if child:IsA("ScreenGui") then
			child.Enabled = visible
		end
	end
end

local function setOpen(value: boolean)
	local gui = inventory
	if not gui then
		return
	end

	open = value
	gui.Enabled = value
	setStatsVisible(not value)

	-- The hotbar reveals its empty slots off this, so they only exist as drop targets
	State.Set(Items.openState, value)

	if not value then
		cancelDrag()
	end
end

local function onInputChanged(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local current = drag
	if current then
		local at = mouse()
		current.ghost.Position = UDim2.fromOffset(at.X, at.Y)
		return
	end

	local waiting = pending
	if waiting and (mouse() - waiting.origin).Magnitude >= DRAG_THRESHOLD then
		startDrag(waiting)
	end
end

local function onInputEnded(input: InputObject)
	if not isDragInput(input) then
		return
	end

	local current = drag
	local waiting = pending

	if current then
		local at = mouse()
		local target = slotAt(at)
		cancelDrag()

		if target and target ~= current.slot then
			Net.FireServer("SetSlot", target, current.id)
		elseif current.slot and not target and overInventory(at) then
			-- Dropped back in the bag: clearing the slot is what returns it to the grid
			Net.FireServer("SetSlot", current.slot)
		end
		return
	end

	cancelDrag()

	-- A click on a hotbar button is the hotbar's own toggle, not ours
	if waiting and not waiting.slot then
		equip(waiting.id)
	end
end

local function collectCategories()
	local gui = inventory
	if not gui then
		return
	end

	local background = gui:WaitForChild(BACKGROUND_NAME, FIND_TIMEOUT)
	local container = background and background:WaitForChild(CONTAINER_NAME, FIND_TIMEOUT)
	if not container then
		warn(`[InventoryController] {GUI_NAME} has no {BACKGROUND_NAME}.{CONTAINER_NAME}`)
		return
	end

	for _, frame in container:GetChildren() do
		if not frame:IsA("GuiObject") then
			continue
		end

		local holder = frame:FindFirstChild(CELLS_NAME)
		if not holder then
			warn(`[InventoryController] category "{frame.Name}" has no {CELLS_NAME}`)
			continue
		end

		local header = frame:FindFirstChild(CATEGORY_NAME)
		local quantity = header and header:FindFirstChild(QUANTITY_NAME)

		categories[frame.Name] = {
			holder = holder,
			quantity = if quantity and quantity:IsA("TextLabel") then quantity else nil,
			count = 0,
		}

		if not Items.byCategory[frame.Name] then
			warn(`[InventoryController] category "{frame.Name}" has no module in Data.Items`)
		end
	end
end

function InventoryController.Start()
	playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	local gui = playerGui:WaitForChild(GUI_NAME, FIND_TIMEOUT)
	if not gui or not gui:IsA("ScreenGui") then
		warn(`[InventoryController] PlayerGui has no {GUI_NAME}`)
		return
	end
	inventory = gui

	local components = ReplicatedStorage:WaitForChild(COMPONENTS_NAME, FIND_TIMEOUT)
	local source = components and components:FindFirstChild(TEMPLATE_NAME)
	if not source or not source:IsA("GuiButton") then
		warn(`[InventoryController] {COMPONENTS_NAME} has no {TEMPLATE_NAME}`)
		return
	end
	template = source

	stats = playerGui:FindFirstChild(STATS_NAME)
	local hotbar = playerGui:FindFirstChild(HOTBAR_NAME)
	hotbarHolder = hotbar and hotbar:FindFirstChild(HOLDER_NAME)

	-- Dragging a slot out is the only way back to the bag; clicking it stays the
	-- hotbar's equip toggle
	if hotbarHolder then
		for _, button in hotbarHolder:GetChildren() do
			if not button:IsA("ImageButton") then
				continue
			end

			button.InputBegan:Connect(function(input: InputObject)
				if not isDragInput(input) then
					return
				end

				local id = player:GetAttribute(Items.slotAttribute .. button.Name)
				if type(id) == "string" then
					pending = { id = id, source = button, origin = mouse(), slot = button.Name }
				end
			end)
		end
	end

	dragGui = Instance.new("ScreenGui")
	local overlay = dragGui :: ScreenGui
	overlay.Name = DRAG_GUI_NAME
	overlay.ResetOnSpawn = false
	-- The ghost follows the raw mouse, so it must live in the same uninset space
	overlay.IgnoreGuiInset = true
	overlay.DisplayOrder = DRAG_ORDER
	overlay.Parent = playerGui

	collectCategories()

	-- Forced rather than trusted: the panel is authored open in Studio
	setOpen(false)

	-- Backpack because ours replaces it. PlayerList because Tab is ITS hotkey, held by
	-- CoreGui above every binding a game can make — there is no way to rebind it.
	local ok = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	if not ok then
		warn("[InventoryController] could not disable the default CoreGui")
	end

	Net.On("InventorySync", function(inventoryTable: any)
		owned = if type(inventoryTable) == "table" then inventoryTable else {}
		rebuild()
	end)

	-- Slotting an item takes it out of the grid, so the grid follows the slots
	for _, slot in Items.slots do
		player:GetAttributeChangedSignal(Items.slotAttribute .. slot):Connect(rebuild)
	end

	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.InputEnded:Connect(onInputEnded)

	-- CoreGui claims Tab, so UserInputService only ever sees it as gameProcessed.
	-- ContextActionService binds above that layer and sinks it.
	ContextActionService:BindAction(TOGGLE_ACTION, function(_, state: Enum.UserInputState)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end

		-- Tab inside a field belongs to the field
		if UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end

		setOpen(not open)
		return Enum.ContextActionResult.Sink
	end, false, TOGGLE_KEY)

	Net.FireServer("InventoryRequest")
end

return InventoryController
