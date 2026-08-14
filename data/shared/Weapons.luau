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
		knockback = 34,
		-- A kick is contact in an instant: one query, no sweep
		hitbox = {
			shape = "point",
			size = Vector3.new(6, 6, 7),
			offset = Vector3.new(0, 0, -5),
		},
	},

	-- Universal, like the flourish. Locomotion animations, so they override whatever
	-- the equipped class would otherwise play.
	crouch = {
		attribute = "Crouching",
		idle = "rbxassetid://74565750413787",
		walk = "rbxassetid://99824326303518",
		speed = 8,
		-- Multiplies how far an NPC notices you from. Groundwork for backstabs.
		stealth = 0.45,
	},

	-- Crouched M1. Landing it lifts BOTH fighters, which is the point: it buys a
	-- shared window in the air rather than just launching the victim away.
	uppercut = {
		animation = "rbxassetid://95795987512728",
		damage = 14,
		riseSpeed = 38,
		riseTime = 0.25,
		hangTime = 1.75,

		-- Where the hang settles, above the CONTACT point rather than above each body.
		-- Holding wherever the rise happened to end left the two at different altitudes
		-- — latency, starting velocity and ground level all differ — and a follow-up
		-- swing from above or below the target is the whole complaint.
		riseHeight = 9,
		-- Per second, per stud of error. High enough to close the gap inside the hang,
		-- low enough that it reads as floating rather than snapping.
		hangGain = 6,
		-- Ceiling on that correction, so a body that starts far off drifts up instead
		-- of rocketing to the mark
		hangCorrection = 24,

		-- Forward nudge on the swing itself, before contact: closes the gap so a
		-- crouched attacker can actually reach. Attacker only — nothing was hit yet.
		lungeSpeed = 26,
		lungeTime = 0.18,

		-- Carried into the launch by BOTH, so they travel together instead of the
		-- victim hanging where they stood while the attacker sails past
		carrySpeed = 16,

		-- WalkSpeed while suspended. Not zero: being frozen mid-air reads as a freeze
		-- bug, and a little drift lets both fighters position inside the window.
		airSpeed = 6,

		-- The victim's silence up there. Longer than `hitstun` on purpose: the point of
		-- landing an uppercut is buying a turn, and plain hitstun is short enough that
		-- the victim can answer with M1 and erase the whole reward.
		victimStun = 1.1,
		cooldown = 2,
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

			-- Seconds from the start of the animation to where its `Start` marker sits,
			-- read straight off the editor timeline. The parry tell fires
			-- `guard.parryWindow` before this.
			--
			-- Measured rather than guessed by code: a track played at weight 0 does not
			-- report markers, and there is no runtime way to ask an animation where its
			-- events are. One number per move beats three failed inference attempts.
			hitAt = 0.50,
			heavy = {
				animation = "rbxassetid://97463310555309",
				damage = 26,
				knockback = 26,
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

	-- How long the shove is held. A Humanoid overrides its own velocity every step,
	-- so a shove has to be a sustained force or it never happens at all.
	knockbackTime = 0.18,

	-- Enough to unstick from the ground so friction stops eating the shove, and no
	-- more: higher reads as a launch, which is not what a hit is.
	knockbackLift = 10,

	-- Taking a real hit cancels whatever you were swinging and locks attacks. Without
	-- it, trading M1 forever is the optimal play and nothing punishes getting hit.
	hitstun = 0.45,

	-- Dash goes where you are steering, falling back to facing when standing still.
	-- `animation` empty until one is authored; the movement works without it.
	--
	-- Ground and air are different moves: on the ground it is a short burst that
	-- closes or breaks spacing, in the air it is a glide that buys distance and hang
	-- time. Same key, different physics.
	dash = {
		cooldown = 1,
		ground = { speed = 42, lift = 4, time = 0.2 },
		air = { speed = 32, lift = 12, time = 0.32 },

		-- Picked from the dash direction in the character's own space, so the clip
		-- matches where the body actually goes
		clips = {
			forward = "rbxassetid://75477975155159",
			backward = "rbxassetid://110233560124664",
			right = "rbxassetid://136054039921519",
			left = "rbxassetid://124452693988963",
		},
		cancel = "rbxassetid://81330636825906",

		-- Invulnerable while dashing, but for exactly ONE hit: dodging consumes it.
		-- A dash that ate a whole flurry would be strictly better than any guard.
		iframes = 0.2,

		-- Cancelling with M2 spends the dash to buy a longer read, mirroring how a
		-- parry buys its frames. Still one hit.
		cancelIframes = 0.22,
	},

	-- Every accepted equip replicates to every client
	requestCooldown = 0.25,

	-- The only Fx a client may ask for, so the set is closed and rate limited
	swingFx = {
		swing = true,
		flourish = true,
		heavy = true,
		aerial = true,
		dash = true,
		uppercut = true,
		swingTell = true,
		heavyTell = true,
		aerialTell = true,
		flourishTell = true,
	},
	swingFxCooldown = 0.15,

	-- Sanity bound on a reported hit, not gameplay reach. Wide enough to absorb lag
	maxHitDistance = 18,

	-- Per attacker/target pair, so multi-target still lands but spam does not
	hitCooldown = 0.35,

	postureAttribute = "Posture",
	stunAttribute = "Stunned",

	-- On the character, as a deadline. Players are silenced through the `Stagger`
	-- remote; a server-owned NPC has no client to send that to, so it reads this.
	stunUntilAttribute = "StunnedUntil",
	parryLockAttribute = "ParryLocked",

	-- On the character, not the Player: NPCs carry these too, and they die with the rig
	healthAttribute = "Health",
	maxHealthAttribute = "MaxHealth",
	defeatedAttribute = "Defeated",
	defaultMaxHealth = 100,

	guard = {
		-- Window after pressing F where an incoming hit is parried outright.
		-- Past it the same hold is an ordinary block.
		--
		-- Short on purpose: it has to be narrower than a swing's windup, or pressing F
		-- the moment you SEE the animation start already covers the impact and the read
		-- costs nothing. Keep it well under `hitAt`.
		parryWindow = 0.16,
		-- Pressing F with nothing to parry locks the parry out. Block stays free,
		-- which is what makes panic-mashing F cost something.
		parryWhiff = 1.5,

		-- Granted BY a successful parry, and valid even after F is released. Landing
		-- one buys the next: a single well-timed press can turn away a whole flurry,
		-- and a lone attack no longer demands frame-perfect release.
		parryFrames = 0.12,

		-- Minimum gap between armed parry windows. Pressing F again sooner still
		-- blocks, it just does not parry — otherwise mashing beats reading, since
		-- every press would re-open a fresh window.
		parryRearm = 0.7,
		postureMax = 100,
		-- Per second, always draining
		postureDecay = 1,
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
table.freeze(Weapons.crouch)
table.freeze(Weapons.uppercut)
table.freeze(Weapons.dash.ground)
table.freeze(Weapons.dash.air)
table.freeze(Weapons.dash.clips)
table.freeze(Weapons.dash)
table.freeze(Weapons.debugHitbox)
table.freeze(Weapons.swingFx)
table.freeze(Weapons.otherGrip)
table.freeze(Weapons.flourish)
table.freeze(Weapons.guard)
table.freeze(Weapons.classes)
table.freeze(Weapons.byId)

return table.freeze(Weapons)
