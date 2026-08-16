--!strict
-- Rarity is the border colour of a slot, and nothing else. Quality (stars) and enchant
-- are separate axes that never colour anything — they become badges later.

export type Rarity = {
	Border: Color3,
	Order: number,
	Label: string,
}

local FALLBACK = "Common"

-- Kept off the module table so sorting can iterate it without tripping over `get`
local entries: { [string]: Rarity } = {
	-- Lifted to read against the beige cell: the first pass sat too close to it in value
	Common = { Border = Color3.fromHex("#B0A695"), Order = 1, Label = "Common" },
	Uncommon = { Border = Color3.fromHex("#8FC14A"), Order = 2, Label = "Uncommon" },
	Rare = { Border = Color3.fromHex("#E0645C"), Order = 3, Label = "Rare" },
	Legendary = { Border = Color3.fromHex("#4FC2D4"), Order = 4, Label = "Legendary" },
	Mythical = { Border = Color3.fromHex("#9B7BE8"), Order = 5, Label = "Mythical" },
	Unique = { Border = Color3.fromHex("#E86BB0"), Order = 6, Label = "Unique" },
}

for _, entry in entries do
	table.freeze(entry)
end

local ItemRarity = {
	entries = table.freeze(entries),
}

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
