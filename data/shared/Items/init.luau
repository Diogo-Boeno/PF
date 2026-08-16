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
	-- Model name under ReplicatedStorage.Items. A weapon takes its own from the weapon
	-- catalog instead; an item with neither simply never shows in the hand.
	model: string?,
}

local Items = {
	-- Prefix + hotbar button name: Slot1..Slot9, Slot0. Holds an item id, not a weapon id.
	slotAttribute = "Slot",

	-- Keyboard row order, matching the hotbar button names
	slots = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },

	-- Where non-weapon models live, in ReplicatedStorage. Weapons keep their own folder
	-- because the weapon catalog, not the item catalog, names them.
	folder = "Items",

	-- Item id in hand. Carrying is not wielding: the model is mounted off this, while
	-- the combat class waits for `Weapons.attribute`, which the first M1 writes.
	heldAttribute = "Held",

	-- Framework/State key. The hotbar shows its empty slots only while the bag is open.
	openState = "InventoryOpen",

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
