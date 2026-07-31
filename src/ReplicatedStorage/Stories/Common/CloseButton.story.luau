local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local CloseButton = require(ReplicatedStorage.Shared.UI.Common.CloseButton)

return {
	vide = Vide,
	summary = "Ghost glyph — background only materializes on hover.",
	controls = {
		size = 24,
	},
	story = function(props)
		return CloseButton {
			parent = props.target,
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
			size = props.controls.size(),
			onClose = function()
				print("[Story] CloseButton activated")
			end,
		}
	end,
}
