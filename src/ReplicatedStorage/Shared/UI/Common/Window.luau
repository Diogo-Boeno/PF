--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- components normally never touch services (docs/ui/COMPONENTS.md), but a drag
-- must keep tracking the pointer after it leaves the header, so global input
-- is the only reliable source of movement
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local Theme = require(script.Parent.Theme)
local CloseButton = require(script.Parent.CloseButton)
local AutoScale = require(script.Parent.AutoScale)

local create = Vide.create
local source = Vide.source
local cleanup = Vide.cleanup
local read = Vide.read

type Reactive<T> = T | () -> T

export type WindowProps = {
	title: Reactive<string>,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	onClose: (() -> ())?,
	parent: Instance?,
	children: { Instance }?,
}

local HEADER_HEIGHT = 36

-- signature detail of the design language: thin L-brackets floating just
-- outside each corner, like crop marks on a technical drawing
local BRACKET_ARM = 12
local BRACKET_GAP = 5

local function bracket(cx: number, cy: number): Frame
	return create "Frame" {
		Name = "Bracket",
		AnchorPoint = Vector2.new(cx, cy),
		Position = UDim2.new(
			cx,
			if cx == 0 then -BRACKET_GAP else BRACKET_GAP,
			cy,
			if cy == 0 then -BRACKET_GAP else BRACKET_GAP
		),
		Size = UDim2.fromOffset(BRACKET_ARM, BRACKET_ARM),
		BackgroundTransparency = 1,

		create "Frame" {
			AnchorPoint = Vector2.new(0, cy),
			Position = UDim2.fromScale(0, cy),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Theme.color.stroke,
			BorderSizePixel = 0,
		},
		create "Frame" {
			AnchorPoint = Vector2.new(cx, 0),
			Position = UDim2.fromScale(cx, 0),
			Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = Theme.color.stroke,
			BorderSizePixel = 0,
		},
	}
end

local function Window(props: WindowProps)
	local position = source(props.position or UDim2.fromScale(0.5, 0.5))
	local onClose = props.onClose
	local size = props.size or UDim2.fromOffset(380, 280)
	-- pixel-designed windows normalize against the screen baseline; scale-designed
	-- ones are already responsive and must not shrink twice
	local pixelDesigned = size.X.Scale == 0 and size.Y.Scale == 0

	local dragConns: { RBXScriptConnection } = {}

	local function stopDrag()
		for _, conn in dragConns do
			conn:Disconnect()
		end
		table.clear(dragConns)
	end

	-- registered here (inside the reactive scope) because a window destroyed
	-- mid-drag would otherwise leak the global InputChanged connection
	cleanup(stopDrag)

	local function beginDrag(input: InputObject)
		stopDrag()

		local pointerStart = input.Position
		local positionStart = position()

		table.insert(
			dragConns,
			UserInputService.InputChanged:Connect(function(moved: InputObject)
				if
					moved.UserInputType ~= Enum.UserInputType.MouseMovement
					and moved.UserInputType ~= Enum.UserInputType.Touch
				then
					return
				end
				local delta = moved.Position - pointerStart
				-- offset-only math keeps whatever scale positioning the window was given
				position(
					UDim2.new(
						positionStart.X.Scale,
						positionStart.X.Offset + delta.X,
						positionStart.Y.Scale,
						positionStart.Y.Offset + delta.Y
					)
				)
			end)
		)

		table.insert(
			dragConns,
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					stopDrag()
				end
			end)
		)
	end

	return create "Frame" {
		Name = "Window",
		Size = size,
		Position = position,
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.color.surface,
		BorderSizePixel = 0,
		-- sink clicks so the window never leaks input to what's behind it
		Active = true,
		Parent = props.parent,

		if pixelDesigned then create "UIScale" { Scale = AutoScale.factor() } else nil,

		create "UICorner" { CornerRadius = Theme.radius.md },
		create "UIStroke" {
			Color = Theme.color.stroke,
			Thickness = Theme.strokeThickness,
		},

		create "Frame" {
			Name = "Header",
			Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
			BackgroundTransparency = 1,
			Active = true,

			InputBegan = function(input: InputObject)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					beginDrag(input)
				end
			end,

			create "TextLabel" {
				Name = "Title",
				Position = UDim2.fromOffset(Theme.spacing.md, 0),
				Size = UDim2.new(1, -(Theme.spacing.md + HEADER_HEIGHT), 1, 0),
				BackgroundTransparency = 1,
				-- forced uppercase keeps every window title consistent with the design language
				Text = function()
					return string.upper(read(props.title))
				end,
				TextColor3 = Theme.color.textPrimary,
				TextSize = Theme.textSize.sm,
				FontFace = Theme.font.heading,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			},

			if onClose
				then CloseButton {
					onClose = onClose,
					anchorPoint = Vector2.new(1, 0.5),
					position = UDim2.new(1, -Theme.spacing.sm, 0.5, 0),
				}
				else nil,
		},

		create "Frame" {
			Name = "Divider",
			Position = UDim2.fromOffset(0, HEADER_HEIGHT),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Theme.color.strokeSoft,
			BorderSizePixel = 0,
		},

		create "Frame" {
			Name = "Content",
			Position = UDim2.fromOffset(0, HEADER_HEIGHT + 1),
			Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + 1)),
			BackgroundTransparency = 1,
			-- content must never escape the window frame
			ClipsDescendants = true,

			create "UIPadding" {
				PaddingTop = UDim.new(0, Theme.spacing.md),
				PaddingBottom = UDim.new(0, Theme.spacing.md),
				PaddingLeft = UDim.new(0, Theme.spacing.md),
				PaddingRight = UDim.new(0, Theme.spacing.md),
			},

			props.children,
		},

		bracket(0, 0),
		bracket(1, 0),
		bracket(0, 1),
		bracket(1, 1),
	}
end

return Window
