--!strict

local Weapons = {
	attribute = "Weapon",
	unarmed = 0,
	folder = "Weapons",

	-- Prefix + button name: Slot1..Slot9, Slot0
	slotAttribute = "Slot",

	-- Animation poses key off part name; shared swings need one
	rootName = "Handle",

	-- Same attachment name on both sides: palm and weapon root
	rig = {
		handPart = "RightPalm",
		gripAttachment = "GripAttachment",
	},

	-- How the weapon is held. Swaps the animation class, nothing else today.
	-- Absent attribute reads as `defaultGrip`, so joining costs no replication.
	gripAttribute = "Grip",
	defaultGrip = "OneHand",
	otherGrip = {
		OneHand = "TwoHand",
		TwoHand = "OneHand",
	},

	-- Draws every hitbox: the library's rays and the box queries alike. The Workspace
	-- attribute `DebugHitbox` overrides this at runtime, so toggling needs no rebuild.
	debugHitbox = {
		enabled = true,
		attribute = "DebugHitbox",
		lifetime = 0.6,
		-- Orange so a box never reads as one of the library's red rays
		color = Color3.fromRGB(255, 120, 40),
		transparency = 0.65,
	},

	-- Universal: every weapon closes its chain with the same kick
	flourish = {
		animation = "rbxassetid://85666929481197",
		damage = 8,
		knockback = 70,
		-- A kick is contact in an instant: one query, no sweep
		hitbox = {
			shape = "point",
			size = Vector3.new(6, 6, 7),
			offset = Vector3.new(0, 0, -5),
		},
	},

	-- A class owns only what it can do; a missing key IS the availability rule
	classes = {
		OneHandMedium = {
			damage = 12,
			idle = "rbxassetid://121555066325081",
			walk = "rbxassetid://131162423358667",
			swings = {
				"rbxassetid://98752333248597",
				"rbxassetid://122778194882345",
				"rbxassetid://109187943328490",
			},
			heavy = {
				animation = "rbxassetid://97463310555309",
				damage = 26,
				-- A thrust is a line with thickness. `range` is the reach, so it stops
				-- being hostage to how long the blade mesh happens to be
				hitbox = {
					shape = "cast",
					size = Vector3.new(4, 4, 2),
					offset = Vector3.new(0, 0, -1),
					range = 9,
				},
			},
			block = "rbxassetid://121940421100599",
			parry = "rbxassetid://121011560408838",
			-- Played on whoever GETS parried. A class with only `right` never rolls
			parried = {
				left = "rbxassetid://92048474041706",
				right = "rbxassetid://81404279835578",
			},
			-- No `chip` key means a block off this weapon costs no health at all
			aerial = {
				animation = "rbxassetid://138038196043233",
				damage = 20,
				-- A dive hits whoever is in its path, so the box rides along per frame
				hitbox = {
					shape = "sweep",
					size = Vector3.new(7, 8, 7),
					offset = Vector3.new(0, -2, -2),
				},
				-- Held for dashTime, not applied once: a single impulse lets gravity
				-- bend it into a jump arc, which is the opposite of a glide
				dashSpeed = 30,
				-- Near-zero sink is what reads as gliding instead of falling
				dashFall = -8,
				dashTime = 0.35,
			},
		},
	},

	-- One class per grip. A grip the weapon has no class for cannot be switched to,
	-- which is what keeps TwoHand off until its animations exist.
	--
	-- `reach` scales this weapon's heavy and aerial hitboxes against the class
	-- baseline, so a katana outranges a shortsword without either leaving the class.
	-- Absent means 1. It does not touch the flourish, which is a kick.
	byId = {
		{ model = "Sword", classes = { OneHand = "OneHandMedium" } },
	},

	-- Tail of a swing that accepts the next click; earlier clicks are dropped
	comboBuffer = 0.25,

	-- Idle this long after a swing ends and the combo restarts at 1
	comboReset = 0.8,

	-- Locked out after the flourish, so closing the chain costs something
	endlag = 0.5,

	-- Wider than endlag; the aerial repeats only after it clears
	aerialCooldown = 1.2,

	-- Blocks R alone, counted from when the heavy ends. Other attacks stay free
	heavyCooldown = 1.5,

	-- Every accepted equip replicates to every client
	requestCooldown = 0.25,

	-- Sanity bound on a reported hit, not gameplay reach. Wide enough to absorb lag
	maxHitDistance = 18,

	-- Per attacker/target pair, so multi-target still lands but spam does not
	hitCooldown = 0.35,

	postureAttribute = "Posture",
	stunAttribute = "Stunned",
	parryLockAttribute = "ParryLocked",

	guard = {
		-- Window after pressing F where an incoming hit is parried outright.
		-- Past it the same hold is an ordinary block.
		parryWindow = 0.25,
		-- Pressing F with nothing to parry locks the parry out. Block stays free,
		-- which is what makes panic-mashing F cost something.
		parryWhiff = 1.5,
		postureMax = 100,
		-- Per second, always draining
		postureDecay = 14,
		-- Posture a blocked hit adds, as a share of the damage it would have dealt
		postureFactor = 1.4,
		-- Posture the attacker eats for being parried
		parryPosture = 30,
		-- Posture the defender sheds for landing one
		parryRelief = 20,
		-- Full posture: stunned, wide open, posture reset
		stunTime = 2,
		-- Attacker lockout after being parried
		parriedLock = 1.2,
	},
}

export type Weapons = typeof(Weapons)

table.freeze(Weapons.rig)
table.freeze(Weapons.debugHitbox)
table.freeze(Weapons.otherGrip)
table.freeze(Weapons.flourish)
table.freeze(Weapons.guard)
table.freeze(Weapons.classes)
table.freeze(Weapons.byId)

return table.freeze(Weapons)
