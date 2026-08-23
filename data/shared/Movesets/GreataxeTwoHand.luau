--!strict
-- Block, parry, crouch, heavy and aerial come from the `Greataxe` type layer; the
-- uppercut from `Heavy`. Only what this grip alone owns lives here.

return {
	weight = "Heavy",
	type = "Greataxe",
	-- Against the medium sword at 1x. Assumes M1, aerial and flourish are authored to
	-- `swingBase`; anything already made heavy gets slowed twice.
	speed = 0.83,
	damage = 20,

	idle = 77740771646689,
	walk = 79529144099802,
	swings = {
		111269660748188,
		126576927120908,
		86876023680893,
	},

	-- PLACEHOLDER: never measured. Read the seconds from the start of each swing to its
	-- `Start` marker on the editor timeline, at 1x, and put the real number here — the
	-- parry tell has nothing else to go on.
	hitAt = 0.5,

	-- Only the right side is authored, so nothing is ever rolled
	parried = { right = 124034155026056 },
}
