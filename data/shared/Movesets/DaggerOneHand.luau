--!strict
-- First Light weapon. Fast and short: `weights.Light` already gives it the 0.6s hitstun,
-- which is the trade — it swings more often and buys less turn per hit.

return {
	weight = "Light",
	type = "Dagger",
	-- Against the medium sword at 1x. Assumes every swing is authored to `swingBase`
	-- (0.40s), so the real swing lands at 0.40 / 1.2 = 0.33s.
	speed = 1.2,
	damage = 11.5,

	idle = 136718615839340,
	walk = 91593490212905,
	swings = {
		89127833737863,
		88994585577832,
		72233542291529,
	},

	-- PLACEHOLDER: never measured. Read the seconds from the start of each swing to its
	-- `Start` marker on the editor timeline, at 1x. The parry tell has nothing else to
	-- go on, and it has to stay well above `guard.parryWindow`.
	hitAt = 0.5,

	block = 78178221203791,
	parry = 126781897365999,

	-- Only the right side is authored, so nothing is ever rolled
	parried = { right = 123580789862094 },

	-- The critical is three stabs off one repeated `Hit` marker, and only the last of
	-- them buys a turn. The first two cut the victim's swing without locking them, so
	-- parrying out of the flurry stays the answer.
	heavy = {
		animation = 91658591853822,
		-- Per stab, in order. Absent means a single hit worth `damage`, like every other
		-- weapon. The whole flurry totals one M1: this is pressure, not damage.
		hits = { 3.83, 3.83, 3.83 },

		-- What a non-final stab costs instead of hitstun. The victim keeps the guard and
		-- the turn; they just cannot walk out of the rest.
		-- PLACEHOLDER: tune against the real marker spacing in the editor.
		drag = { speed = 10, duration = 0.45 },

		-- No `knockback` on purpose: a shove would push the victim out of the next stab
		hitbox = {
			shape = "point",
			size = Vector3.new(5, 5, 7),
			offset = Vector3.new(0, 0, -4),
		},
	},

	aerial = {
		animation = 127227507203194,
		-- PLACEHOLDER: copied from the sword, never tuned for a dagger
		damage = 20,
		hitbox = {
			shape = "sweep",
			size = Vector3.new(7, 8, 7),
			offset = Vector3.new(0, -2, -2),
		},
		dashSpeed = 30,
		dashFall = -8,
		dashTime = 0.35,
	},
}
