local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local Checkbox = require(ReplicatedStorage.Shared.UI.Common.Checkbox)

return {
	vide = Vide,
	summary = "Controlled component — the story owns the checked state via the `checked` control.",
	controls = {
		label = "Enable feature",
		checked = false,
	},
	story = function(props)
		return Checkbox {
			parent = props.target,
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
			label = props.controls.label,
			value = props.controls.checked,
			onToggle = function(value: boolean)
				props.controls.checked(value)
			end,
		}
	end,
}
