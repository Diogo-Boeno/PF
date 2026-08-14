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
local Items = require(ReplicatedStorage.Data.Items)

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

local pending: { id: string, cell: GuiButton, origin: Vector2 }? = nil
local drag: { id: string, ghost: GuiObject }? = nil

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

local function startDrag(id: string, cell: GuiButton)
	local parent = dragGui
	if not parent then
		return
	end

	local ghost = cell:Clone() :: GuiObject
	ghost.Name = "Ghost"
	ghost.Active = false
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.Size = UDim2.fromOffset(cell.AbsoluteSize.X, cell.AbsoluteSize.Y)
	ghost.Position = UDim2.fromOffset(mouse().X, mouse().Y)
	ghost.ZIndex = DRAG_ORDER
	ghost.Parent = parent

	drag = { id = id, ghost = ghost }
end

local function equip(id: string)
	local entry = Items.byId[id]
	-- Nothing else is equippable yet; a material cell simply does not answer
	if entry and entry.weapon then
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

	-- Activated is not used: a press that turns into a drag must not also equip
	cell.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			pending = { id = entry.id, cell = cell, origin = mouse() }
		end
	end)

	cell.Parent = category.holder
	category.count += 1
end

local function rebuild()
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
		if not entry or amount <= 0 then
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
		startDrag(waiting.id, waiting.cell)
	end
end

local function onInputEnded(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local current = drag
	local waiting = pending

	if current then
		local slot = slotAt(mouse())
		cancelDrag()
		if slot then
			Net.FireServer("SetSlot", slot, current.id)
		end
		return
	end

	cancelDrag()
	if waiting then
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
