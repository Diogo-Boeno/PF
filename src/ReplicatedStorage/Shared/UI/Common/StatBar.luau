--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local Theme = require(script.Parent.Theme)

local create = Vide.create
local read = Vide.read
local spring = Vide.spring

type Reactive<T> = T | () -> T

export type StatBarProps = {
	value: Reactive<number>,
	max: Reactive<number>?,

	color: Reactive<Color3>?,
	-- Swapped in at or below `lowAt`. Omit to keep one colour the whole way down
	lowColor: Reactive<Color3>?,
	lowAt: number?,

	-- Notches drawn over the fill, purely to make small changes legible
	segments: number?,
	label: Reactive<string>?,

	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	parent: Instance?,
}

local DEFAULT_SIZE = UDim2.fromOffset(360, 26)
local DEFAULT_LOW_AT = 0.3

-- Slow enough to read as drain, fast enough not to lie about current health
local FILL_PERIOD = 0.25
local FILL_DAMPING = 1

local function StatBar(props: StatBarProps)
	local function fraction(): number
		local maximum = if props.max == nil then 1 else read(props.max)
		if maximum <= 0 then
			return 0
		end
		return math.clamp(read(props.value) / maximum, 0, 1)
	end

	local function fillColor(): Color3
		local base = if props.color then read(props.color) else Theme.vitals.health
		local low = props.lowColor
		if low and fraction() <= (props.lowAt or DEFAULT_LOW_AT) then
			return read(low)
		end
		return base
	end

	local children: { any } = {
		create "UICorner" {
			CornerRadius = Theme.radius.sm,
		},

		create "UIStroke" {
			Color = Theme.color.stroke,
			Thickness = Theme.strokeThickness,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		},

		-- No corner of its own: the parent clips, so a nearly empty bar keeps a
		-- square inner edge instead of collapsing into a lozenge
		create "Frame" {
			Name = "Fill",
			BackgroundColor3 = spring(fillColor, FILL_PERIOD, FILL_DAMPING),
			BorderSizePixel = 0,
			Size = spring(function()
				return UDim2.fromScale(fraction(), 1)
			end, FILL_PERIOD, FILL_DAMPING),
		},
	}

	-- Static: the count never changes, so these need no reactive scope
	local segments = props.segments or 0
	for index = 1, segments - 1 do
		table.insert(
			children,
			create "Frame" {
				Name = "Notch",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(index / segments, 0),
				Size = UDim2.new(0, Theme.strokeThickness, 1, 0),
				BackgroundColor3 = Theme.color.background,
				BorderSizePixel = 0,
				ZIndex = 2,
			}
		)
	end

	if props.label then
		table.insert(
			children,
			create "TextLabel" {
				Name = "Label",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = props.label,
				FontFace = Theme.font.strong,
				TextSize = Theme.textSize.sm,
				TextColor3 = Theme.color.textPrimary,
				ZIndex = 3,
			}
		)
	end

	return create "Frame" {
		Name = "StatBar",
		Size = props.size or DEFAULT_SIZE,
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = Theme.vitals.track,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = props.parent,

		table.unpack(children),
	}
end

return StatBar
