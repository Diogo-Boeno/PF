--!strict
-- Barrel for the UI kit: require(ReplicatedStorage.Shared.UI.Common) hands out
-- the whole set, while individual child requires keep working for one-offs.

local Theme = require(script.Theme)
local Button = require(script.Button)
local CloseButton = require(script.CloseButton)
local Window = require(script.Window)
local Checkbox = require(script.Checkbox)
local TextInput = require(script.TextInput)
local ModelViewport = require(script.ModelViewport)
local AutoScale = require(script.AutoScale)
local HitCircle = require(script.HitCircle)

export type Theme = Theme.Theme
export type ButtonProps = Button.ButtonProps
export type CloseButtonProps = CloseButton.CloseButtonProps
export type WindowProps = Window.WindowProps
export type CheckboxProps = Checkbox.CheckboxProps
export type TextInputProps = TextInput.TextInputProps
export type ModelViewportProps = ModelViewport.ModelViewportProps
export type HitCircleProps = HitCircle.HitCircleProps
export type HitResult = HitCircle.HitResult
export type Judgement = HitCircle.Judgement

return table.freeze({
	Theme = Theme,
	Button = Button,
	CloseButton = CloseButton,
	Window = Window,
	Checkbox = Checkbox,
	TextInput = TextInput,
	ModelViewport = ModelViewport,
	AutoScale = AutoScale,
	HitCircle = HitCircle,

	-- next pass: Slider, Dropdown, ProgressBar, Tooltip
})
