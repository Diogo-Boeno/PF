--!strict
-- Sanctuary panel. Opens by proximity, never by a key — standing there is the
-- mechanic, so the UI follows the world instead of the other way around.

local CollectionService = game:GetService("CollectionService")
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

local TAG = "Sanctuary"

-- Slightly under the server's 24, so the panel never offers what it would refuse
local RANGE = 22
local POLL = 0.25

local REASONS = {
	distance = "Too far from a Sanctuary",
	essence = "Not enough Essence",
	rite = "A Rite is required to pass this point",
	maxed = "This attribute is at its limit",
	unknown = "Unknown attribute",
}

local player = Players.LocalPlayer

local SanctuaryController = {}

local function costFor(current: number): number?
	for _, tier in Config.tiers do
		if current < tier.ceiling then
			return Config.essencePerPoint * tier.cost
		end
	end
	return nil
end

local function AttributeRow(key: string, label: string, order: number)
	local value = useAttribute(player, Config.attributeAttribute .. key, 0)

	return create "Frame" {
		Name = key,
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		LayoutOrder = order,

		create "TextLabel" {
			Size = UDim2.new(0.45, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = label,
			TextColor3 = Theme.color.textPrimary,
			TextSize = Theme.textSize.sm,
			FontFace = Theme.font.body,
			TextXAlignment = Enum.TextXAlignment.Left,
		},

		create "TextLabel" {
			Position = UDim2.fromScale(0.45, 0),
			Size = UDim2.new(0.2, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = function()
				local cost = costFor(value())
				return if cost then `{value()}  ·  {cost}` else `{value()}  ·  máx`
			end,
			TextColor3 = Theme.color.textMuted,
			TextSize = Theme.textSize.sm,
			FontFace = Theme.font.body,
			TextXAlignment = Enum.TextXAlignment.Left,
		},

		UI.Button {
			text = "Refine",
			anchorPoint = Vector2.new(1, 0.5),
			position = UDim2.new(1, 0, 0.5, 0),
			size = UDim2.fromOffset(90, 26),
			disabled = function()
				return costFor(value()) == nil
			end,
			onClick = function()
				Net.FireServer("BuyAttribute", key)
			end,
		},
	}
end

function SanctuaryController.Start()
	local gui = player:WaitForChild("PlayerGui")

	Vide.root(function()
		local near = source(false)
		local feedback = source("")
		local rows = source({})

		local function rebuild()
			local list = {}
			for key, spec in Config.universal do
				table.insert(list, { key = key, label = spec.label })
			end

			-- Origin attributes only appear for the Origin that has them
			for _, origin in Config.origins do
				for key, spec in origin.attributes do
					if player:GetAttribute(Config.attributeAttribute .. key) ~= nil then
						table.insert(list, { key = key, label = spec.label })
					end
				end
			end

			table.sort(list, function(a, b)
				return a.label < b.label
			end)
			rows(list)
		end

		rebuild()

		local essence = useAttribute(player, Config.essenceAttribute, 0)
		local memories = useAttribute(player, Config.memoriesAttribute, 0)

		create "ScreenGui" {
			Name = "SanctuaryUI",
			ResetOnSpawn = false,
			DisplayOrder = 10,
			Enabled = near,
			Parent = gui,

			UI.Window {
				title = "Sanctuary",
				size = UDim2.fromOffset(460, 380),
				position = UDim2.fromScale(0.5, 0.5),
				children = {
					create "Frame" {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,

						create "UIListLayout" {
							FillDirection = Enum.FillDirection.Vertical,
							Padding = UDim.new(0, Theme.spacing.xs),
							SortOrder = Enum.SortOrder.LayoutOrder,
						},

						create "TextLabel" {
							Size = UDim2.new(1, 0, 0, 24),
							BackgroundTransparency = 1,
							LayoutOrder = -2,
							Text = function()
								return `Essence {essence()}    ·    Memories {memories()}`
							end,
							TextColor3 = Theme.color.textPrimary,
							TextSize = Theme.textSize.md,
							FontFace = Theme.font.strong,
							TextXAlignment = Enum.TextXAlignment.Left,
						},

						create "TextLabel" {
							Size = UDim2.new(1, 0, 0, 18),
							BackgroundTransparency = 1,
							LayoutOrder = -1,
							Text = feedback,
							TextColor3 = Theme.color.danger,
							TextSize = Theme.textSize.sm,
							FontFace = Theme.font.body,
							TextXAlignment = Enum.TextXAlignment.Left,
						},

						indexes(rows, function(row, index)
							return AttributeRow(row().key, row().label, index)
						end),
					},
				},
			},
		}

		Net.On("BuyResult", function(ok: boolean, reason: string)
			feedback(if ok then "" else REASONS[reason] or reason)
			rebuild()
		end)

		-- Polled rather than per-frame: presence changes at walking speed
		task.spawn(function()
			while true do
				task.wait(POLL)

				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local found = false

				if root then
					for _, part in CollectionService:GetTagged(TAG) do
						if part:IsA("BasePart") and (part.Position - root.Position).Magnitude <= RANGE then
							found = true
							break
						end
					end
				end

				if found ~= near() then
					near(found)
					if not found then
						feedback("")
					end
				end
			end
		end)
	end)
end

return SanctuaryController
