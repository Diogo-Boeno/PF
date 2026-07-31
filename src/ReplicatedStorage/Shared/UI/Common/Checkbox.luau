--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local Theme = require(script.Parent.Theme)

local create = Vide.create
local source = Vide.source

type Reactive<T> = T | () -> T

export type CheckboxProps = {
	-- controlled component: the caller owns the state, usually a Vide source
	value: () -> boolean,
	onToggle: (boolean) -> (),
	label: Reactive<string>?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	parent: Instance?,
}

local BOX_SIZE = 18

local function Checkbox(props: CheckboxProps)
	local hovering = source(false)
	local label = props.label

	-- the whole row (box + label) is one hitbox so the label is clickable too
	return create "TextButton" {
		Name = "Checkbox",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(BOX_SIZE, BOX_SIZE),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		Parent = props.parent,

		Activated = function()
			props.onToggle(not props.value())
		end,
		MouseEnter = function()
			hovering(true)
		end,
		MouseLeave = function()
			hovering(false)
		end,

		create "UIListLayout" {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, Theme.spacing.sm),
		},

		create "Frame" {
			Name = "Box",
			Size = UDim2.fromOffset(BOX_SIZE, BOX_SIZE),
			BackgroundColor3 = Theme.color.surfaceRaised,
			BorderSizePixel = 0,

			create "UICorner" { CornerRadius = Theme.radius.sm },
			create "UIStroke" {
				Thickness = Theme.strokeThickness,
				Color = function()
					return if props.value()
						then Theme.color.accent
						elseif hovering() then Theme.color.accentDim
						else Theme.color.stroke
				end,
			},

			-- inner square instead of a checkmark glyph: crisper at small
			-- sizes and immune to font fallback surprises
			create "Frame" {
				Name = "Fill",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(8, 8),
				BackgroundColor3 = Theme.color.accent,
				BorderSizePixel = 0,
				BackgroundTransparency = function()
					return if props.value() then 0 else 1
				end,

				create "UICorner" { CornerRadius = UDim.new(0, 2) },
			},
		},

		if label
			then create "TextLabel" {
				Name = "Label",
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, BOX_SIZE),
				Text = label,
				TextSize = Theme.textSize.md,
				FontFace = Theme.font.body,
				TextColor3 = function()
					return if hovering() then Theme.color.textPrimary else Theme.color.textMuted
				end,
				TextXAlignment = Enum.TextXAlignment.Left,
			}
			else nil,
	}
end

return Checkbox
