--!strict
-- Attributes, Origins and the Sanctuary curve. Data only.
-- Keys are English because code reads them; `label` is what the UI shows.

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
		Strength = { label = "Força", group = "Body" },
		Fortitude = { label = "Fortitude", group = "Body" },
		Swiftness = { label = "Ligeireza", group = "Body" },
		Insight = { label = "Perspicácia", group = "Mind" },
		Presence = { label = "Presença", group = "Mind" },
		Willpower = { label = "Vontade", group = "Mind" },
	},

	-- Each Origin adds three of its own. It never touches the universal six, which is
	-- what keeps one damage formula valid for every character.
	origins = {
		Crawlers = {
			label = "Rastejantes",
			attributes = {
				CarnalExpansion = { label = "Expansão Carnal" },
				PredatoryHunger = { label = "Fome Predatória" },
				SurvivalInstinct = { label = "Instinto de Sobrevivência" },
			},
		},
		Heralds = {
			label = "Arautos",
			attributes = {
				BlindFervor = { label = "Fervor Cego" },
				ChasteningPresence = { label = "Presença Castigadora" },
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
