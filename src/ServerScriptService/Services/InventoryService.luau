--!strict
-- Owns what a lineage carries and which hotbar slot holds what. Both live in the
-- profile, so they survive a rejoin.
--
-- Possession and the hotbar are separate on purpose: the client may ask to slot or
-- equip anything, and every request is checked against what the profile actually has.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Framework.Net)
local Items = require(ReplicatedStorage.Data.Items)
local Weapons = require(ReplicatedStorage.Data.Weapons)
local DataService = require(script.Parent.DataService)
local WeaponService = require(script.Parent.WeaponService)

-- Test grant, delete once the world hands out items
local STARTER_ITEM = "greataxe"

local REQUEST_COOLDOWN = 0.15

local lastRequest: { [Player]: number } = {}

local InventoryService = {}

local function owns(lineage: any, id: string): boolean
	return (lineage.Inventory[id] or 0) > 0
end

-- At most one weapon is ever slotted, which is what makes "replace the current one"
-- a single lookup instead of a scan with ties
local function weaponSlot(lineage: any): string?
	for slot, id in lineage.Equipment do
		local entry = Items.byId[id]
		if entry and entry.weapon then
			return slot
		end
	end
	return nil
end

-- Slots replicate as attributes like everything else; the carried items do not fit
-- one, so they go over a remote the client also asks for on its own Start
local function slotOf(lineage: any, id: string): string?
	for slot, slotted in lineage.Equipment do
		if slotted == id then
			return slot
		end
	end
	return nil
end

local function firstFreeSlot(lineage: any): string?
	for _, slot in Items.slots do
		if not lineage.Equipment[slot] then
			return slot
		end
	end
	return nil
end

local function publish(player: Player)
	local lineage = DataService.lineage(player)

	for _, slot in Items.slots do
		local id = if lineage then lineage.Equipment[slot] else nil
		player:SetAttribute(Items.slotAttribute .. slot, id)
	end

	Net.FireClient("InventorySync", player, if lineage then lineage.Inventory else {})
end

function InventoryService.grant(player: Player, id: string, amount: number?): boolean
	local lineage = DataService.lineage(player)
	if not lineage or not Items.byId[id] then
		return false
	end

	lineage.Inventory[id] = (lineage.Inventory[id] or 0) + (amount or 1)
	publish(player)
	return true
end

function InventoryService.remove(player: Player, id: string, amount: number?): boolean
	local lineage = DataService.lineage(player)
	if not lineage or not owns(lineage, id) then
		return false
	end

	local left = lineage.Inventory[id] - (amount or 1)
	lineage.Inventory[id] = if left > 0 then left else nil

	-- A slot pointing at something no longer carried would still equip it
	if not lineage.Inventory[id] then
		for slot, slotted in lineage.Equipment do
			if slotted == id then
				lineage.Equipment[slot] = nil
			end
		end
	end

	publish(player)
	return true
end

-- Puts the item in hand. Passing nil puts it away. Equipping never touches the hotbar:
-- what is held and what is slotted are different things, and reserving a slot here is
-- what made one sword read as two.
function InventoryService.equip(player: Player, id: string?): boolean
	local lineage = DataService.lineage(player)
	if not lineage then
		return false
	end

	if id == nil then
		lineage.Held = ""
		player:SetAttribute(Items.heldAttribute, nil)
		WeaponService.equip(player, Weapons.unarmed)
		return true
	end

	local entry = Items.byId[id]
	if not entry or not owns(lineage, id) then
		return false
	end

	-- Minimum attribute requirements are checked here once items declare them

	-- Only carried, never wielded: it hangs in the hand as a plain object so it can be
	-- dropped. Drawing it is the first M1, which is what writes the weapon attribute.
	lineage.Held = id
	player:SetAttribute(Items.heldAttribute, id)
	WeaponService.equip(player, Weapons.unarmed)
	return true
end

function InventoryService.setSlot(player: Player, slot: string, id: string?): boolean
	local lineage = DataService.lineage(player)
	if not lineage or not table.find(Items.slots, slot) then
		return false
	end

	if id == nil then
		lineage.Equipment[slot] = nil
		publish(player)
		return true
	end

	local entry = Items.byId[id]
	if not entry or not owns(lineage, id) then
		return false
	end

	-- A weapon occupies one slot at a time, so dragging one moves it rather than copies
	if entry.weapon then
		local previous = weaponSlot(lineage)
		if previous then
			lineage.Equipment[previous] = nil
		end
	end

	lineage.Equipment[slot] = id

	-- Remembered so using the item again sends it back here instead of anywhere free
	if type(lineage.LastSlot) ~= "table" then
		lineage.LastSlot = {}
	end
	lineage.LastSlot[id] = slot

	publish(player)
	return true
end

-- Using what is in hand is what earns it a place on the bar. Until then it is just
-- held, which is why equipping alone never takes a slot.
function InventoryService.commitHeld(player: Player): boolean
	local lineage = DataService.lineage(player)
	if not lineage then
		return false
	end

	local id = lineage.Held
	local entry = if type(id) == "string" then Items.byId[id] else nil
	if not entry then
		return false
	end

	-- Drawing is what turns a carried object into a weapon. Idempotent, so the per-attack
	-- report that follows costs nothing.
	if entry.weapon then
		WeaponService.equip(player, entry.weapon)
	end

	if slotOf(lineage, id) then
		return false
	end

	local remembered = if type(lineage.LastSlot) == "table" then lineage.LastSlot[id] else nil
	local slot = if type(remembered) == "string" and table.find(Items.slots, remembered)
		then remembered
		else firstFreeSlot(lineage)

	if not slot then
		return false
	end

	return InventoryService.setSlot(player, slot, id)
end

local function throttled(player: Player): boolean
	local now = os.clock()
	if now - (lastRequest[player] or 0) < REQUEST_COOLDOWN then
		return true
	end
	lastRequest[player] = now
	return false
end

local function onEquipRequest(player: Player, id: any)
	if id ~= nil and type(id) ~= "string" then
		return
	end
	if throttled(player) then
		return
	end
	InventoryService.equip(player, id)
end

local function onSlotRequest(player: Player, slot: any, id: any)
	if type(slot) ~= "string" or (id ~= nil and type(id) ~= "string") then
		return
	end
	if throttled(player) then
		return
	end
	InventoryService.setSlot(player, slot, id)
end

-- A body only exists once a lineage does, so spawning is when there is something to
-- grant to and something to publish
local function onSpawn(player: Player)
	local lineage = DataService.lineage(player)
	if not lineage then
		return
	end

	if not lineage.Inventory[STARTER_ITEM] then
		InventoryService.grant(player, STARTER_ITEM)
	end

	-- What was in hand comes back with the body; the attribute does not survive a rejoin
	local held = lineage.Held
	if type(held) == "string" and held ~= "" then
		InventoryService.equip(player, held)
	end

	publish(player)
end

function InventoryService.Start()
	Net.On("EquipItem", onEquipRequest)
	Net.On("SetSlot", onSlotRequest)
	Net.On("InventoryRequest", publish)
	-- Not throttled: it fires per attack and no-ops once the item is already slotted
	Net.On("UseHeld", InventoryService.commitHeld)
	Net.Register("InventorySync")

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			onSpawn(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return InventoryService
