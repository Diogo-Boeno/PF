local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local TextInput = require(ReplicatedStorage.Shared.UI.Common.TextInput)

return {
	vide = Vide,
	summary = "Focus ring on focus, accent-dim hint on hover; onSubmit fires on Enter.",
	controls = {
		placeholder = "Search...",
		initialText = "",
	},
	story = function(props)
		return TextInput {
			parent = props.target,
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
			placeholder = props.controls.placeholder(),
			initialText = props.controls.initialText(),
			onChanged = function(value: string)
				print("[Story] TextInput changed:", value)
			end,
			onSubmit = function(value: string)
				print("[Story] TextInput submitted:", value)
			end,
		}
	end,
}
