--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local Theme = require(script.Parent.Theme)

local create = Vide.create
local source = Vide.source

export type CloseButtonProps = {
	onClose: () -> (),
	size: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	parent: Instance?,
}

local function CloseButton(props: CloseButtonProps)
	local hovering = source(false)
	local pressing = source(false)
	local size = props.size or 24

	return create "TextButton" {
		Name = "CloseButton",
		Size = UDim2.fromOffset(size, size),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		AutoButtonColor = false,
		BackgroundColor3 = Theme.color.surfaceHover,
		-- background only materializes on hover; at rest the glyph stands alone
		BackgroundTransparency = function()
			return if hovering() then 0 else 1
		end,
		-- plain "X" over a unicode glyph: guaranteed present in every font family
		Text = "X",
		TextSize = Theme.textSize.sm,
		FontFace = Theme.font.heading,
		TextColor3 = function()
			return if pressing()
				then Theme.color.accent
				elseif hovering() then Theme.color.textPrimary
				else Theme.color.textMuted
		end,
		Parent = props.parent,

		Activated = function()
			props.onClose()
		end,
		MouseEnter = function()
			hovering(true)
		end,
		MouseLeave = function()
			hovering(false)
			pressing(false)
		end,
		MouseButton1Down = function()
			pressing(true)
		end,
		MouseButton1Up = function()
			pressing(false)
		end,

		create "UICorner" { CornerRadius = Theme.radius.sm },
	}
end

return CloseButton
