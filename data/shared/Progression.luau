--!strict
-- Attributes, Origins and the Sanctuary curve. Data only.
-- `label` is what the UI shows; the key is what code reads.

local Progression = {
	-- A lineage gets three. Losing the last one ends it and banks Memories.
	startingLives = 3,

	-- Character level, separate from points inside one attribute
	maxLevel = 30,
	veilTrialLevel = 20,

	-- False until the profile is in memory. Without it every screen would read the
	-- empty defaults for a frame and flash the creation UI at returning players.
	loadedAttribute = "ProfileLoaded",

	attributeAttribute = "Attr_",
	essenceAttribute = "RawEssence",
	livesAttribute = "Lives",
	memoriesAttribute = "Memories",
	levelAttribute = "Level",

	-- The six everyone has, in two groups
	universal = {
		Strength = { label = "Strength", group = "Body" },
		Fortitude = { label = "Fortitude", group = "Body" },
		Swiftness = { label = "Swiftness", group = "Body" },
		Insight = { label = "Insight", group = "Mind" },
		Presence = { label = "Presence", group = "Mind" },
		Willpower = { label = "Willpower", group = "Mind" },
	},

	-- Each Origin adds three of its own. It never touches the universal six, which is
	-- what keeps one damage formula valid for every character.
	origins = {
		Crawlers = {
			label = "Crawlers",
			attributes = {
				CarnalExpansion = { label = "Carnal Expansion" },
				PredatoryHunger = { label = "Predatory Hunger" },
				SurvivalInstinct = { label = "Survival Instinct" },
			},
		},
		Heralds = {
			label = "Heralds",
			attributes = {
				BlindFervor = { label = "Blind Fervor" },
				ChasteningPresence = { label = "Chastening Presence" },
				-- Was "Convicção", which only restated Willpower plus Presence. Litany
				-- is the recited prayer that keeps a Herald intact against Resonance:
				-- it slows how fast the Echo learns them.
				Litany = { label = "Litania" },
			},
		},
	},

	weaponProficiency = { "Light", "Medium", "Heavy" },

	-- Sanctuary curve. Cost of the NEXT point is the tier the point lands in.
	essencePerPoint = 100,
	tiers = {
		{ ceiling = 15, cost = 1 },
		{ ceiling = 30, cost = 2 },
		{ ceiling = 40, cost = 4 },
	},

	-- Ceilings that a Rite has to open. Reaching one is not enough.
	riteAt = { 15, 30 },

	-- Share of the lineage's spent Essence that comes back as Memories when it ends.
	-- Not everything, or death costs nothing; not nothing, or it costs everything.
	memoryRefund = 0.15,
}

export type Progression = typeof(Progression)

table.freeze(Progression.universal)
table.freeze(Progression.origins)
table.freeze(Progression.weaponProficiency)
table.freeze(Progression.tiers)
table.freeze(Progression.riteAt)

return table.freeze(Progression)
