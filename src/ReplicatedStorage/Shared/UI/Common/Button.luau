--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local Theme = require(script.Parent.Theme)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local read = Vide.read

type Reactive<T> = T | () -> T
type InteractionState = "idle" | "hover" | "press" | "disabled"

export type ButtonProps = {
	text: Reactive<string>,
	onClick: () -> (),
	disabled: Reactive<boolean>?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	parent: Instance?,
}

local function Button(props: ButtonProps)
	local hovering = source(false)
	local pressing = source(false)
	local disabled = props.disabled

	local function isDisabled(): boolean
		return if disabled == nil then false else read(disabled)
	end

	-- one derived state so every visual property agrees on precedence
	-- (disabled > press > hover)
	local state = derive(function(): InteractionState
		return if isDisabled() then "disabled" elseif pressing() then "press" elseif hovering() then "hover" else "idle"
	end)

	return create "TextButton" {
		Name = "Button",
		Size = props.size or UDim2.fromOffset(160, 36),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = function()
			local s = state()
			return if s == "press"
				then Theme.color.surfacePressed
				elseif s == "hover" then Theme.color.surfaceHover
				elseif s == "disabled" then Theme.color.surface
				else Theme.color.surfaceRaised
		end,
		Text = props.text,
		TextColor3 = function()
			return if state() == "disabled" then Theme.color.textFaint else Theme.color.textPrimary
		end,
		TextSize = Theme.textSize.md,
		FontFace = Theme.font.strong,
		Parent = props.parent,

		Activated = function()
			if isDisabled() then
				return
			end
			props.onClick()
		end,
		MouseEnter = function()
			hovering(true)
		end,
		MouseLeave = function()
			hovering(false)
			-- MouseButton1Up never fires here if the press is released outside the button
			pressing(false)
		end,
		MouseButton1Down = function()
			pressing(true)
		end,
		MouseButton1Up = function()
			pressing(false)
		end,

		create "UICorner" { CornerRadius = Theme.radius.sm },
		create "UIStroke" {
			Thickness = Theme.strokeThickness,
			-- accent shows up only through interaction, never at rest
			Color = function()
				local s = state()
				return if s == "press"
					then Theme.color.accent
					elseif s == "hover" then Theme.color.accentDim
					elseif s == "disabled" then Theme.color.strokeSoft
					else Theme.color.stroke
			end,
		},
	}
end

return Button
