--!strict
-- Character creation. Shown whenever there is no lineage, which the server signals
-- by leaving Lives at 0 — the same value that means "you spent your last life".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)

local Config = require(ReplicatedStorage.Data.Progression)
local Net = require(ReplicatedStorage.Shared.Framework.Net)
local UI = require(ReplicatedStorage.Shared.UI.Common)
local useAttribute = require(ReplicatedStorage.Shared.UI.Common.useAttribute)

local Theme = UI.Theme
local create = Vide.create
local source = Vide.source
local indexes = Vide.indexes

local player = Players.LocalPlayer

local CreationController = {}

local function OriginCard(key: string, origin: any, onPick: (string) -> ())
	local names = {}
	for _, spec in origin.attributes do
		table.insert(names, spec.label)
	end
	table.sort(names)

	return create "Frame" {
		Name = key,
		Size = UDim2.new(0.5, -Theme.spacing.sm, 1, 0),
		BackgroundColor3 = Theme.color.surfaceRaised,
		BorderSizePixel = 0,

		create "UICorner" { CornerRadius = Theme.radius.sm },
		create "UIStroke" {
			Color = Theme.color.stroke,
			Thickness = Theme.strokeThickness,
		},
		create "UIPadding" {
			PaddingTop = UDim.new(0, Theme.spacing.md),
			PaddingBottom = UDim.new(0, Theme.spacing.md),
			PaddingLeft = UDim.new(0, Theme.spacing.md),
			PaddingRight = UDim.new(0, Theme.spacing.md),
		},

		create "TextLabel" {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			Text = string.upper(origin.label),
			TextColor3 = Theme.color.textPrimary,
			TextSize = Theme.textSize.lg,
			FontFace = Theme.font.heading,
			TextXAlignment = Enum.TextXAlignment.Left,
		},

		create "TextLabel" {
			Position = UDim2.fromOffset(0, 32),
			Size = UDim2.new(1, 0, 1, -76),
			BackgroundTransparency = 1,
			Text = table.concat(names, "\n"),
			TextColor3 = Theme.color.textMuted,
			TextSize = Theme.textSize.sm,
			FontFace = Theme.font.body,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		},

		UI.Button {
			text = "Choose",
			anchorPoint = Vector2.new(0.5, 1),
			position = UDim2.fromScale(0.5, 1),
			size = UDim2.new(1, 0, 0, 32),
			onClick = function()
				onPick(key)
			end,
		},
	}
end

function CreationController.Start()
	local gui = player:WaitForChild("PlayerGui")

	Vide.root(function()
		local loaded = useAttribute(player, Config.loadedAttribute, false)
		local lives = useAttribute(player, Config.livesAttribute, 0)
		local pending = source(false)

		-- Never before the profile lands, or a returning player sees this flash
		local function needsCharacter(): boolean
			return loaded() and lives() <= 0 and not pending()
		end

		local origins = source({})
		local list = {}
		for key, origin in Config.origins do
			table.insert(list, { key = key, origin = origin })
		end
		table.sort(list, function(a, b)
			return a.key < b.key
		end)
		origins(list)

		local function pick(key: string)
			pending(true)
			Net.FireServer("CreateLineage", key)
			-- Released if the server refuses, so a rejected pick is retryable
			task.delay(2, function()
				pending(false)
			end)
		end

		create "ScreenGui" {
			Name = "CreationUI",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			DisplayOrder = 20,
			Enabled = needsCharacter,
			Parent = gui,

			create "Frame" {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Theme.color.background,
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
			},

			UI.Window {
				title = "New Pilgrimage",
				size = UDim2.fromOffset(560, 320),
				children = {
					create "Frame" {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,

						create "UIListLayout" {
							FillDirection = Enum.FillDirection.Horizontal,
							HorizontalAlignment = Enum.HorizontalAlignment.Center,
							Padding = UDim.new(0, Theme.spacing.md),
							SortOrder = Enum.SortOrder.LayoutOrder,
						},

						indexes(origins, function(entry)
							return OriginCard(entry().key, entry().origin, pick)
						end),
					},
				},
			},
		}
	end)
end

return CreationController
