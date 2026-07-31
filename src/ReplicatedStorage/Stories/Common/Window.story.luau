local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local UI = ReplicatedStorage.Shared.UI.Common
local Theme = require(UI.Theme)
local Window = require(UI.Window)
local Button = require(UI.Button)
local Checkbox = require(UI.Checkbox)

local create = Vide.create
local source = Vide.source

return {
	vide = Vide,
	summary = "Draggable frame with corner brackets; content composes Button + Checkbox to show real usage.",
	controls = {
		title = "Settings",
	},
	story = function(props)
		local remember = source(false)

		return Window {
			parent = props.target,
			title = props.controls.title,
			onClose = function()
				print("[Story] Window closed")
			end,
			children = {
				create "TextLabel" {
					Position = UDim2.fromOffset(0, 0),
					Size = UDim2.new(1, 0, 0, 20),
					BackgroundTransparency = 1,
					Text = "Discard unsaved changes?",
					TextColor3 = Theme.color.textPrimary,
					TextSize = Theme.textSize.md,
					FontFace = Theme.font.body,
					TextXAlignment = Enum.TextXAlignment.Left,
				},

				Checkbox {
					position = UDim2.fromOffset(0, 32),
					label = "Remember my choice",
					value = remember,
					onToggle = function(value: boolean)
						remember(value)
					end,
				},

				Button {
					position = UDim2.fromOffset(0, 68),
					text = "Confirm",
					onClick = function()
						print("[Story] Confirm clicked, remember =", remember())
					end,
				},
			},
		}
	end,
}
