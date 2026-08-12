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

	-- Name of the VFX template, or a table when the burst needs to sit somewhere other
	-- than the character's centre. `offset` is in the subject's local space, so
	-- { 0, -3, 0 } puts it at the feet and stays correct whichever way they face.
	effect = {
		parry = "ParryEffect",
		-- heavy = { name = "WindBurst", offset = Vector3.new(0, -3, 0) },
	},

	-- Outline drawn on whoever performs the attack, for reads at a glance. An event
	-- with no entry gets no outline, same rule as everything else here.
	highlight = {
		heavy = {
			color = Color3.fromRGB(255, 170, 60),
			duration = 0.45,
		},
	},
}

export type Fx = typeof(Fx)

table.freeze(Fx.sound)
table.freeze(Fx.effect)
table.freeze(Fx.highlight)

return table.freeze(Fx)
