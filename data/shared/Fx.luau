--!strict
-- Presentation only: which sound and which particle answer which combat event.
-- Nothing here decides damage, so retuning it can never desync anything.

local Fx = {
	soundFolder = "SFX",
	effectFolder = "VFX",

	-- The template Part is cloned, so it must stay Anchored and non-colliding
	effectLifetime = 2,
	-- Emitters may override with an `EmitCount` attribute
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

		blocked = { "DampenedHit" },
		parry = { "Clash1", "Clash2", "Clash3" },
		parried = { "Parried" },
		guardBreak = { "BlastHit" },
	},

	effect = {
		parry = "ParryEffect",
	},
}

export type Fx = typeof(Fx)

table.freeze(Fx.sound)
table.freeze(Fx.effect)

return table.freeze(Fx)
