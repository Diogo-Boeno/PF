local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local StatBar = require(ReplicatedStorage.Shared.UI.Common.StatBar)
local Theme = require(ReplicatedStorage.Shared.UI.Common.Theme)

local read = Vide.read

return {
	vide = Vide,
	summary = "Controlled bar: drag health to watch the fill spring and flip to low colour.",
	controls = {
		health = 100,
		maxHealth = 100,
		segments = 10,
		showLabel = true,
	},
	story = function(props)
		-- UI Labs hands controls over as sources, so they are already Reactive<T>
		local controls = props.controls

		return Vide.create "Frame" {
			Parent = props.target,
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.color.background,
			BorderSizePixel = 0,

			Vide.create "UIListLayout" {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, Theme.spacing.md),
			},

			StatBar {
				value = controls.health,
				max = controls.maxHealth,
				lowColor = Theme.vitals.healthLow,
				segments = read(controls.segments),
				layoutOrder = 1,
				label = function()
					if not read(controls.showLabel) then
						return ""
					end
					return `{math.floor(read(controls.health))} / {read(controls.maxHealth)}`
				end,
			},

			StatBar {
				value = controls.health,
				max = controls.maxHealth,
				color = Theme.vitals.posture,
				size = UDim2.fromOffset(360, 10),
				layoutOrder = 2,
			},
		}
	end,
}
