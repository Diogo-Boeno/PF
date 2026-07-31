--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local Theme = require(script.Parent.Theme)

local create = Vide.create
local source = Vide.source
local changed = Vide.changed

export type TextInputProps = {
	placeholder: string?,
	initialText: string?,
	onChanged: ((string) -> ())?,
	onSubmit: ((string) -> ())?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	parent: Instance?,
}

local function TextInput(props: TextInputProps)
	local focused = source(false)
	local hovering = source(false)
	-- mirror of the instance's Text so onSubmit can read it without holding a ref
	local text = source(props.initialText or "")

	return create "TextBox" {
		Name = "TextInput",
		Size = props.size or UDim2.fromOffset(220, 34),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = Theme.color.surfaceRaised,
		BorderSizePixel = 0,
		ClipsDescendants = true,

		Text = props.initialText or "",
		PlaceholderText = props.placeholder or "",
		PlaceholderColor3 = Theme.color.textFaint,
		TextColor3 = Theme.color.textPrimary,
		TextSize = Theme.textSize.md,
		FontFace = Theme.font.body,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Parent = props.parent,

		Focused = function()
			focused(true)
		end,
		FocusLost = function(enterPressed: boolean)
			focused(false)
			if enterPressed and props.onSubmit then
				props.onSubmit(text())
			end
		end,
		MouseEnter = function()
			hovering(true)
		end,
		MouseLeave = function()
			hovering(false)
		end,

		changed("Text", function(value: string)
			-- changed() replays the current value on mount; only report real edits
			if value == text() then
				return
			end
			text(value)
			if props.onChanged then
				props.onChanged(value)
			end
		end),

		create "UICorner" { CornerRadius = Theme.radius.sm },
		create "UIStroke" {
			Thickness = Theme.strokeThickness,
			-- the focus ring is the accent's job; hover only hints at it
			Color = function()
				return if focused()
					then Theme.color.accent
					elseif hovering() then Theme.color.accentDim
					else Theme.color.strokeSoft
			end,
		},
		create "UIPadding" {
			PaddingLeft = UDim.new(0, Theme.spacing.sm),
			PaddingRight = UDim.new(0, Theme.spacing.sm),
		},
	}
end

return TextInput
