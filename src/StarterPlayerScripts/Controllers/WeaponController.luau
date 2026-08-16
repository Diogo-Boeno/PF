--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Data.Weapons)
local Items = require(ReplicatedStorage.Data.Items)

local HAND_TIMEOUT = 10

-- A one-piece item is its own root. Wrapping a mesh in a Model just to satisfy the
-- weapon contract would be ceremony, so a BasePart template is accepted as-is.
type Template = {
	instance: Instance,
	gripCFrame: CFrame,
}

-- Keyed by item id, not weapon id: what goes in the hand is an item, and a weapon is
-- only one kind of item
local templates: { [string]: Template } = {}

local grips: { [Player]: Attachment } = {}
local mounted: { [Player]: Instance } = {}
local watching: { [Player]: { RBXScriptConnection } } = {}

local WeaponController = {}

local function unmount(player: Player)
	local model = mounted[player]
	if model then
		mounted[player] = nil
		model:Destroy()
	end
end

local function mount(player: Player, id: string)
	unmount(player)

	local template = templates[id]
	local gripAttachment = grips[player]
	local character = player.Character
	if not template or not gripAttachment or not character then
		return
	end

	local clone = template.instance:Clone()
	local root = if clone:IsA("Model") then clone.PrimaryPart else clone :: BasePart
	if not root then
		clone:Destroy()
		return
	end

	-- Motor6D, not Weld: only a joint is animatable
	local joint = Instance.new("Motor6D")
	joint.Name = Config.rootName
	joint.Part0 = gripAttachment.Parent :: BasePart
	joint.Part1 = root
	joint.C0 = gripAttachment.CFrame
	joint.C1 = template.gripCFrame

	-- Parent before joining, or the assembly rebuilds twice
	clone.Parent = character
	-- Joint lives on the item so one Destroy takes it too
	joint.Parent = root

	mounted[player] = clone
end

-- Mounted off what is HELD, not off what is wielded: carrying an item shows it in the
-- hand, and only the first M1 promotes it to a weapon. The model is the same either way.
local function refresh(player: Player)
	local held = player:GetAttribute(Items.heldAttribute)
	if type(held) ~= "string" or not templates[held] then
		unmount(player)
		return
	end
	mount(player, held)
end

local function onCharacterAdded(player: Player, character: Model)
	grips[player] = nil
	mounted[player] = nil

	-- Caching the grip keeps refresh() non-yielding
	local hand = character:WaitForChild(Config.rig.handPart, HAND_TIMEOUT) :: BasePart?
	if not hand then
		warn(`[WeaponController] {player.Name} has no {Config.rig.handPart}`)
		return
	end

	local gripAttachment = hand:WaitForChild(Config.rig.gripAttachment, HAND_TIMEOUT) :: Attachment?
	if not gripAttachment then
		warn(`[WeaponController] {player.Name} has no {Config.rig.gripAttachment}`)
		return
	end

	if player.Character ~= character then
		return
	end

	grips[player] = gripAttachment
	refresh(player)
end

local function watch(player: Player)
	watching[player] = {
		player:GetAttributeChangedSignal(Items.heldAttribute):Connect(function()
			refresh(player)
		end),
		player.CharacterAdded:Connect(function(character: Model)
			onCharacterAdded(player, character)
		end),
		player.CharacterRemoving:Connect(function()
			grips[player] = nil
			mounted[player] = nil
		end),
	}

	local character = player.Character
	if character then
		task.spawn(onCharacterAdded, player, character)
	end
end

local function unwatch(player: Player)
	local connections = watching[player]
	if connections then
		watching[player] = nil
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	grips[player] = nil
	mounted[player] = nil
end

-- Weapons are named by the weapon catalog and live in their own folder; everything else
-- names its own model. An item with neither is simply never held, and says nothing.
local function templateNameFor(entry: Items.Entry): (string?, Instance?)
	if entry.weapon then
		local weapon = Config.byId[entry.weapon]
		return (if weapon then weapon.model else nil), ReplicatedStorage:FindFirstChild(Config.folder)
	end
	return entry.model, ReplicatedStorage:FindFirstChild(Items.folder)
end

local function loadTemplates()
	ReplicatedStorage:WaitForChild(Config.folder)

	-- Collected into one line at the end: twenty separate warns is noise, one sorted
	-- list is a checklist of what still has to be posed by hand
	local pivoted: { string } = {}

	for id, entry in Items.byId do
		local name, folder = templateNameFor(entry)
		if not name then
			continue
		end

		-- Recursive: the folder is organised into subfolders by hand, and that layout is
		-- the author's to change without breaking the lookup
		local instance = folder and folder:FindFirstChild(name, true)
		if not instance then
			warn(`[WeaponController] missing model "{name}" for item "{id}"`)
			continue
		end

		local root = if instance:IsA("Model") then instance.PrimaryPart else instance :: BasePart
		if not root or not root:IsA("BasePart") then
			warn(`[WeaponController] "{name}" is a Model with no PrimaryPart`)
			continue
		end

		-- Animation stores pose by part name, and the shared swings animate `Handle`. A
		-- weapon rooted on anything else mounts fine and then never moves.
		if entry.weapon and root.Name ~= Config.rootName then
			warn(
				`[WeaponController] "{name}" root is "{root.Name}", not {Config.rootName} — swings will not animate it`
			)
		end

		-- A weapon aligns two GripAttachments so the pose is authored, not guessed. A
		-- plain item has none and is held by its pivot, which inherits the grip's own
		-- orientation — authored for a blade, so it needs `holdOffset` to stand upright.
		-- Recursive: a Model may carry the grip on any of its parts, not just the one that
		-- happens to be the PrimaryPart
		local gripAttachment = instance:FindFirstChild(Config.rig.gripAttachment, true)
		local gripCFrame = Items.holdOffset

		if gripAttachment and gripAttachment:IsA("Attachment") then
			-- Converted into the root's space, because C1 only means anything relative to
			-- Part1. On a weapon, whose grip sits on the root, this is the same CFrame.
			gripCFrame = root.CFrame:ToObjectSpace(gripAttachment.WorldCFrame)
		else
			table.insert(pivoted, id)
		end

		-- Once per template, not per clone
		for _, part in instance:GetDescendants() do
			if part:IsA("BasePart") then
				part.Massless = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false

				-- Only the root carries the Motor6D, so the rest has to ride along or a
				-- two-piece item leaves its other half on the floor. Welding the template
				-- means the clone comes out already whole.
				if part ~= root then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = root
					weld.Part1 = part
					weld.Parent = root
				end
			end
		end
		if instance:IsA("BasePart") then
			instance.Massless = true
			instance.CanCollide = false
			instance.CanQuery = false
			instance.CanTouch = false
		end

		templates[id] = {
			instance = instance,
			gripCFrame = gripCFrame,
		}
	end

	if #pivoted > 0 then
		table.sort(pivoted)
		warn(`[WeaponController] no {Config.rig.gripAttachment}, held by pivot: {table.concat(pivoted, ", ")}`)
	end
end

function WeaponController.mountedFor(target: Player): Model?
	return mounted[target]
end

function WeaponController.Start()
	loadTemplates()

	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(unwatch)

	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return WeaponController
