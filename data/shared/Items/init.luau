--!strict
-- Item catalog. One module per category, discovered at require time: a single flat
-- file stops being editable long before the game has all its items.
--
-- `id` and `category` are stamped here, so a category module never repeats itself.

export type Entry = {
	id: string,
	label: string,
	category: string,
	-- Index into Weapons.byId. Absent means the item cannot be equipped.
	weapon: number?,
}

local Items = {
	-- Prefix + hotbar button name: Slot1..Slot9, Slot0. Holds an item id, not a weapon id.
	slotAttribute = "Slot",

	-- Keyboard row order, matching the hotbar button names
	slots = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },

	byId = {} :: { [string]: Entry },
	byCategory = {} :: { [string]: { [string]: Entry } },
}

for _, module in script:GetChildren() do
	if not module:IsA("ModuleScript") then
		continue
	end

	local category = module.Name
	local set: { [string]: any } = {}

	for id, entry in require(module) :: { [string]: any } do
		if Items.byId[id] then
			warn(`[Items] duplicate id "{id}" in {category}`)
			continue
		end

		entry.id = id
		entry.category = category
		table.freeze(entry)

		Items.byId[id] = entry
		set[id] = entry
	end

	Items.byCategory[category] = table.freeze(set)
end

export type Items = typeof(Items)

table.freeze(Items.slots)
table.freeze(Items.byId)
table.freeze(Items.byCategory)

return table.freeze(Items)
