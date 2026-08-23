--!strict
-- The reference every other weapon is measured against: speed 1x, and every animation
-- authored to `Weapons.swingBase`.

return {
	weight = "Medium",
	type = "Sword",
	speed = 1,
	damage = 18,

	idle = 121555066325081,
	walk = 131162423358667,
	swings = {
		98752333248597,
		122778194882345,
		109187943328490,
	},

	-- Seconds from the start of the animation to where its `Start` marker sits, read
	-- straight off the editor timeline. The parry tell fires `guard.parryWindow` before
	-- this.
	--
	-- Measured rather than guessed by code: a track played at weight 0 does not report
	-- markers, and there is no runtime way to ask an animation where its events are.
	-- One number per move beats three failed inference attempts.
	hitAt = 0.50,

	block = 121940421100599,
	parry = 121011560408838,

	-- Played on whoever GETS parried. A moveset with only `right` never rolls
	parried = {
		left = 92048474041706,
		right = 81404279835578,
	},

	heavy = {
		animation = 97463310555309,
		damage = 26,
		knockback = 26,
		-- A thrust is a line with thickness. `range` is the reach, so it stops being
		-- hostage to how long the blade mesh happens to be
		hitbox = {
			shape = "cast",
			size = Vector3.new(4, 4, 2),
			offset = Vector3.new(0, 0, -1),
			range = 9,
		},
	},

	-- No `chip` key means a block off this weapon costs no health at all
	aerial = {
		animation = 138038196043233,
		damage = 20,
		-- A dive hits whoever is in its path, so the box rides along per frame
		hitbox = {
			shape = "sweep",
			size = Vector3.new(7, 8, 7),
			offset = Vector3.new(0, -2, -2),
		},
		-- Held for dashTime, not applied once: a single impulse lets gravity bend it
		-- into a jump arc, which is the opposite of a glide
		dashSpeed = 30,
		-- Near-zero sink is what reads as gliding instead of falling
		dashFall = -8,
		dashTime = 0.35,
	},
}
