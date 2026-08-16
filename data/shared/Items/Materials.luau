--!strict
-- `model` names a child of ReplicatedStorage.Items, found recursively — the folder
-- layout there is free. No GripAttachment means the item never goes to the hand.

return {
	gem = { label = "Gem", model = "Gem", rarity = "Uncommon" },
	diamond = { label = "Diamond", model = "Diamond", rarity = "Rare" },

	coalOre = { label = "Coal Ore", model = "CoalOre", rarity = "Common" },
	ironOre = { label = "Iron Ore", model = "IronOre", rarity = "Common" },
	goldOre = { label = "Gold Ore", model = "GoldOre", rarity = "Uncommon" },
	platinumOre = { label = "Platinum Ore", model = "PlatinumOre", rarity = "Rare" },

	ironIngot = { label = "Iron Ingot", model = "IronIngot", rarity = "Common" },
	goldIngot = { label = "Gold Ingot", model = "GoldIngot", rarity = "Uncommon" },
	platinumIngot = { label = "Platinum Ingot", model = "PlatinumIngot", rarity = "Rare" },

	stick = { label = "Stick", model = "Stick", rarity = "Common" },
	rock = { label = "Rock", model = "Rock", rarity = "Common" },
	cloth = { label = "Cloth", model = "Cloth", rarity = "Common" },
}
