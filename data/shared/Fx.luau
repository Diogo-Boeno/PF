--!strict
-- Presentation only: which sound and which particle answer which combat event.
-- Nothing here decides damage, so retuning it can never desync anything.

local Fx = {
	soundFolder = "SFX",
	effectFolder = "VFX",

	-- Only the Attachment under the template Part is cloned, so the Part itself is
	-- just a Studio handle and never reaches the world. Lifetime comes from the
	-- slowest particle, not from a constant.
	--
	-- Emitters may override the burst size with an `EmitCount` attribute
	emitCount = 24,

	-- A list rolls one at random, which is what keeps repeated swings from
	-- turning into a metronome
	sound = {
		swing = { "Swing1", "Swing2" },
		flourish = { "FistSwing" },
		heavy = { "HeavySwing1" },
		aerial = { "swooshlong2" },

		hit = { "Hit1", "Hit2" },
		heavyHit = { "BigHit" },

		blocked = { "Clash1" },
		parry = { "Parry" },
		parried = { "Parried" },
		guardBreak = { "Guardbreak" },
	},

	effect = {
		parry = "ParryEffect",
	},
}

export type Fx = typeof(Fx)

table.freeze(Fx.sound)
table.freeze(Fx.effect)

return table.freeze(Fx)
