local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local Button = require(ReplicatedStorage.Shared.UI.Common.Button)

return {
	vide = Vide,
	summary = "Idle/hover/press/disabled states driven by one derived precedence.",
	controls = {
		text = "Click me",
		disabled = false,
	},
	story = function(props)
		return Button {
			parent = props.target,
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
			text = props.controls.text,
			disabled = props.controls.disabled,
			onClick = function()
				print("[Story] Button clicked")
			end,
		}
	end,
}
