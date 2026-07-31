local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local HitCircle = require(ReplicatedStorage.Shared.UI.Common.HitCircle)

return {
	vide = Vide,
	summary = "osu!-style hit target: click when the amber ring meets the circle. Loops so you can feel the timing.",
	controls = {
		approachTime = 1.2,
		label = "S",
		autoReset = true,
	},
	story = function(props)
		return HitCircle {
			parent = props.target,
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
			approachTime = props.controls.approachTime,
			label = props.controls.label,
			autoReset = props.controls.autoReset,
			onJudge = function(result)
				print(`[HitCircle] {result.judgement} ({string.format("%+.0f", result.errorMs)}ms)`)
			end,
		}
	end,
}
