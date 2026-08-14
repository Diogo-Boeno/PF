--!strict
-- Character sheet: stats on the left, hotbar slots on the right.
-- Read-only — spending happens at a Sanctuary, never from a menu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)

local Config = require(ReplicatedStorage.Data.Progression)
local Items = require(ReplicatedStorage.Data.Items)
local UI = require(ReplicatedStorage.Shared.UI.Common)
local useAttribute = require(ReplicatedStorage.Shared.UI.Common.useAttribute)

local Theme = UI.Theme
local create = Vide.create
local source = Vide.source
local indexes = Vide.indexes

-- Tab belongs to the inventory; the sheet moved off it
local SHEET_KEY = Enum.KeyCode.P

local player = Players.LocalPlayer

local SheetController = {}

local function Line(label: string, value: () -> string, order: number)
	return create "Frame" {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		LayoutOrder = order,

		create "TextLabel" {
			Size = UDim2.fromScale(0.65, 1),
			BackgroundTransparency = 1,
			Text = label,
			TextColor3 = Theme.color.textMuted,
			TextSize = Theme.textSize.sm,
			FontFace = Theme.font.body,
			TextXAlignment = Enum.TextXAlignment.Left,
		},

		create "TextLabel" {
			Position = UDim2.fromScale(0.65, 0),
			Size = UDim2.fromScale(0.35, 1),
			BackgroundTransparency = 1,
			Text = value,
			TextColor3 = Theme.color.textPrimary,
			TextSize = Theme.textSize.sm,
			FontFace = Theme.font.strong,
			TextXAlignment = Enum.TextXAlignment.Right,
		},
	}
end

local function Column(title: string, order: number, children: { any })
	return create "Frame" {
		Size = UDim2.new(0.5, -Theme.spacing.sm, 1, 0),
		BackgroundTransparency = 1,
		LayoutOrder = order,

		create "TextLabel" {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			Text = string.upper(title),
			TextColor3 = Theme.color.textFaint,
			TextSize = Theme.textSize.sm,
			FontFace = Theme.font.heading,
			TextXAlignment = Enum.TextXAlignment.Left,
		},

		create "Frame" {
			Position = UDim2.fromOffset(0, 28),
			Size = UDim2.new(1, 0, 1, -28),
			BackgroundTransparency = 1,

			create "UIListLayout" {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 2),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},

			table.unpack(children),
		},
	}
end

function SheetController.Start()
	local gui = player:WaitForChild("PlayerGui")

	Vide.root(function()
		local open = source(false)

		local lives = useAttribute(player, Config.livesAttribute, 0)
		local essence = useAttribute(player, Config.essenceAttribute, 0)
		local memories = useAttribute(player, Config.memoriesAttribute, 0)
		local level = useAttribute(player, Config.levelAttribute, 0)

		local stats: { any } = {
			Line("Nível", function()
				return `{level()} / {Config.maxLevel}`
			end, -4),
			Line("Vidas", function()
				return `{lives()} / {Config.startingLives}`
			end, -3),
			Line("Essência Bruta", function()
				return tostring(essence())
			end, -2),
			Line("Lembranças", function()
				return tostring(memories())
			end, -1),
		}

		local order = 0
		for key, spec in Config.universal do
			order += 1
			local value = useAttribute(player, Config.attributeAttribute .. key, 0)
			table.insert(
				stats,
				Line(spec.label, function()
					return tostring(value())
				end, order)
			)
		end

		-- The full inventory has its own screen; the sheet shows what is at hand
		local slots = source({})
		local function rebuildSlots()
			local list = {}
			for _, name in Items.slots do
				local id = player:GetAttribute(Items.slotAttribute .. name)
				local entry = if type(id) == "string" then Items.byId[id] else nil
				if entry then
					table.insert(list, { slot = name, label = entry.label })
				end
			end
			slots(list)
		end
		rebuildSlots()

		create "ScreenGui" {
			Name = "SheetUI",
			ResetOnSpawn = false,
			DisplayOrder = 15,
			Enabled = open,
			Parent = gui,

			UI.Window {
				title = "Ficha",
				size = UDim2.fromOffset(620, 400),
				onClose = function()
					open(false)
				end,
				children = {
					create "Frame" {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,

						create "UIListLayout" {
							FillDirection = Enum.FillDirection.Horizontal,
							Padding = UDim.new(0, Theme.spacing.md),
							SortOrder = Enum.SortOrder.LayoutOrder,
						},

						Column("Atributos", 1, stats),

						Column("Em mãos", 2, {
							indexes(slots, function(entry, index)
								return Line(`Slot {entry().slot}`, function()
									return entry().label
								end, index)
							end),
						}),
					},
				},
			},
		}

		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed or input.KeyCode ~= SHEET_KEY then
				return
			end
			rebuildSlots()
			open(not open())
		end)
	end)
end

return SheetController
