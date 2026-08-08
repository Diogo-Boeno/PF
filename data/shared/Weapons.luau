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

	byId = {
		"Sword",
	},

	-- Every accepted equip replicates to every client
	requestCooldown = 0.25,
}

export type Weapons = typeof(Weapons)

table.freeze(Weapons.rig)
table.freeze(Weapons.byId)

return table.freeze(Weapons)
