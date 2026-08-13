--!strict
-- Presentation only: which sound and which particle answer which combat event.
-- Nothing here decides damage, so retuning it can never desync anything.

local Fx = {
	soundFolder = "SFX",
	effectFolder = "VFX",

	-- Traces every step from event to emitter. Turn off once VFX behave.
	debug = true,

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

		-- Steel meeting steel: the sparks come off the defender's own edge, so they
		-- ride the DmgPoints of whatever weapon actually took the blow
		blocked = { name = "BlockSparks", on = "blade" },

		-- Parry tells, one per attack kind. Read by the OPPONENT, so they play on the
		-- attacker and everyone sees them: the game saying the input is live now.
		--
		-- The tell comes off whatever is about to hit you, which is why the flourish
		-- does not glow on a blade it is not swinging.
		-- `sustain` and not a burst: emitted particles are on their own the moment they
		-- exist, so a one-shot can never trail the blade. Keeping the emitter alive for
		-- the window means new particles keep being born wherever the tip is now.
		--
		-- `duration` should match guard.parryWindow: the glow IS the window.
		swingTell = { name = "SwordGlow", on = "tip", mode = "sustain", duration = 0.25 },
		heavyTell = { name = "SwordGlow", on = "tip", mode = "sustain", duration = 0.25 },
		aerialTell = { name = "SwordGlow", on = "tip", mode = "sustain", duration = 0.25 },
		flourishTell = { name = "SwordGlow", offset = Vector3.new(0, -2.5, -1) },

		-- heavy = { name = "WindBurst", offset = Vector3.new(0, -3, 0) },
	},

	-- Outline on whoever is winding up, fired when the animation STARTS — not when the
	-- hitbox opens. It is a telegraph: by the time the blade is live it has already
	-- stopped being information the opponent can act on.
	--
	-- White on purpose, Sekiro-style: the tell must read instantly and identically for
	-- every move, so it is never confused with elemental or status colour.
	highlight = {
		heavy = { color = Color3.fromRGB(255, 255, 255), duration = 0.35 },
		aerial = { color = Color3.fromRGB(255, 255, 255), duration = 0.35 },
	},
}

export type Fx = typeof(Fx)

table.freeze(Fx.sound)
table.freeze(Fx.effect)
table.freeze(Fx.highlight)

return table.freeze(Fx)
