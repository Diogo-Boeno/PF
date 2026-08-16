--!strict
-- Rarity is the fill colour of a slot, and nothing else. Quality (stars) and enchant are
-- separate axes that never colour anything — they become badges later.
--
-- It used to be the border. A 2px outline is too little area to read across a grid, so
-- the whole grid looked monochrome.

-- The border is the fill darkened, not a colour of its own: storing both let them drift
-- apart, and one number keeps every rarity on the same relationship.
export type Rarity = {
	Fill: Color3,
	Order: number,
	Label: string,
}

local FALLBACK = "Common"

local BORDER_FACTOR = 0.755

-- Kept off the module table so sorting can iterate it without tripping over `get`
local entries: { [string]: Rarity } = {
	-- Lifted to read against the beige cell: the first pass sat too close to it in value
	Common = { Fill = Color3.fromHex("#A49E94"), Order = 1, Label = "Common" },
	Uncommon = { Fill = Color3.fromHex("#8FAA8D"), Order = 2, Label = "Uncommon" },
	Rare = { Fill = Color3.fromHex("#AA928D"), Order = 3, Label = "Rare" },
	Legendary = { Fill = Color3.fromHex("#8DA5AA"), Order = 4, Label = "Legendary" },
	Mythical = { Fill = Color3.fromHex("#9E8EA9"), Order = 5, Label = "Mythical" },
	Unique = { Fill = Color3.fromHex("#AA8DA1"), Order = 6, Label = "Unique" },
}

for _, entry in entries do
	table.freeze(entry)
end

local ItemRarity = {
	entries = table.freeze(entries),
	-- Bottom stop of the slot gradient. Exported ahead of the gradient itself so the
	-- number lives with the palette rather than being typed into the UI later.
	GRADIENT_BOTTOM = 0.84,
}

function ItemRarity.borderOf(fill: Color3): Color3
	return Color3.new(fill.R * BORDER_FACTOR, fill.G * BORDER_FACTOR, fill.B * BORDER_FACTOR)
end

-- Never nil: an unknown rarity is a data mistake, and a slot with no border would hide it
function ItemRarity.get(name: string?): Rarity
	local entry = if type(name) == "string" then entries[name] else nil
	if entry then
		return entry
	end

	warn(`[ItemRarity] no colour for "{tostring(name)}" in this table, using {FALLBACK}`)
	return entries[FALLBACK]
end

return table.freeze(ItemRarity)
