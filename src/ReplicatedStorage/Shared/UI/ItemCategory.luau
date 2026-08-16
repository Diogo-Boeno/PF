--!strict
-- Category is the fill colour of a slot. Rarity owns the border; the two never overlap.
--
-- The cell is a flat beige with no image, so these sit at its luminance: a dark palette
-- reads as near-black there whatever it is applied to.

export type Category = {
	Background: Color3,
	Label: string,
}

local FALLBACK = "Material"

-- Kept off the module table so listing categories can iterate it without hitting `get`
local entries: { [string]: Category } = {
	Material = { Background = Color3.fromHex("#D6C7A4"), Label = "Material" },
	Schematic = { Background = Color3.fromHex("#B9C6CE"), Label = "Schematic" },
	Training = { Background = Color3.fromHex("#D8BCA4"), Label = "Training" },
	Equipment = { Background = Color3.fromHex("#D9B8B4"), Label = "Equipment" },
}

for _, entry in entries do
	table.freeze(entry)
end

local ItemCategory = {
	entries = table.freeze(entries),
}

-- Never nil: an unknown category is a data mistake, and an uncoloured slot would hide it.
-- The catalogue names its categories after the module file, which is plural, so a
-- trailing "s" is dropped before the lookup — Materials and Material are one category.
function ItemCategory.get(name: string?): Category
	local entry = if type(name) == "string" then entries[name] or entries[name:gsub("s$", "")] else nil
	if entry then
		return entry
	end

	-- Says "no colour for" and not "unknown": the category exists, this table has no
	-- entry for it, and the two read very differently at 2am
	warn(`[ItemCategory] no colour for "{tostring(name)}" in this table, using {FALLBACK}`)
	return entries[FALLBACK]
end

return table.freeze(ItemCategory)
