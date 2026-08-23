--!strict
-- One moveset per file, discovered at require time. `Weapons.classes` IS this table.
--
-- Layers merge weight -> type -> moveset; the moveset's own keys win. A layer only earns
-- a place here once two movesets actually share it.

local Movesets = {
	-- Hitstun belongs to the weight, not the move: a heavy weapon buys a longer turn.
	-- Spamming M1 with one used to lose the trade because the victim recovered before
	-- the swing cycle came round again.
	weights = {
		Light = { hitstun = 0.6 },
		Medium = { hitstun = 0.9 },
		Heavy = {
			hitstun = 1.2,
			-- Ignores the weapon's swing speed by design: a slow weapon still uppercuts
			-- fast, and the damage scaling is what pays for it
			uppercut = { animation = 125721624070954 },
		},
	},

	types = {
		Greataxe = {
			block = 83891377944727,
			parry = 103985732950863,

			-- Crouching is posture, but a greataxe is too big to hold the universal pose
			crouch = {
				idle = 108592538476304,
				walk = 135450333455556,
			},

			-- The critical IS the heavy for this weapon; there is no separate move
			heavy = {
				animation = 103950024178748,
				-- PLACEHOLDER: copied from the sword, never tuned for a greataxe
				damage = 26,
				knockback = 26,
				hitbox = {
					shape = "cast",
					size = Vector3.new(4, 4, 2),
					offset = Vector3.new(0, 0, -1),
					range = 9,
				},
			},
			aerial = {
				animation = 81794080454334,
				-- PLACEHOLDER: copied from the sword, never tuned for a greataxe
				damage = 20,
				hitbox = {
					shape = "sweep",
					size = Vector3.new(7, 8, 7),
					offset = Vector3.new(0, -2, -2),
				},
				dashSpeed = 30,
				dashFall = -8,
				dashTime = 0.35,
			},
		},
	},

	classes = {} :: { [string]: any },
}

-- Every field holding an id. Normalizes a pasted number, flags a 0, catches a reupload.
local ANIMATION_FIELDS = {
	"idle",
	"walk",
	"swings",
	"block",
	"parry",
	"parried",
	"crouch.idle",
	"crouch.walk",
	"heavy.animation",
	"aerial.animation",
	"uppercut.animation",
}

-- Top level only. Deeper keys belong to the move that owns them.
local KNOWN_KEYS = {
	weight = true,
	type = true,
	speed = true,
	damage = true,
	hitAt = true,
	hitstun = true,
	chip = true,
	idle = true,
	walk = true,
	swings = true,
	block = true,
	parry = true,
	parried = true,
	crouch = true,
	heavy = true,
	aerial = true,
	uppercut = true,
}

-- CombatController indexes these unguarded: missing one crashes the equip.
local REQUIRED = { "idle", "walk", "swings" }

-- Studio gives a number, the engine wants a string. Accept both.
local function assetId(value: any): string?
	if type(value) == "number" then
		return `rbxassetid://{value}`
	end
	return if type(value) == "string" then value else nil
end

-- Walks a dotted path down to the table that holds the final key
local function fieldAt(source: any, path: string): (any, string?)
	local holder: any = source
	local key: string? = nil

	for part in string.gmatch(path, "[^.]+") do
		if key then
			holder = holder[key]
			if type(holder) ~= "table" then
				return nil, nil
			end
		end
		key = part
	end

	return holder, key
end

-- Calls `visit` for every animation id under `source`. A returned string replaces it.
local function visitAnimations(source: any, label: string, visit: (string, any) -> string?)
	for _, path in ANIMATION_FIELDS do
		local holder, key = fieldAt(source, path)
		local value = if holder and key then holder[key] else nil
		if value == nil then
			continue
		end

		if type(value) == "table" then
			for inner, entry in value do
				local where = if type(inner) == "number" then `{label}.{path}[{inner}]` else `{label}.{path}.{inner}`
				local replaced = visit(where, entry)
				if replaced then
					value[inner] = replaced
				end
			end
		else
			local target: any = holder
			local replaced = visit(`{label}.{path}`, value)
			if replaced then
				target[key] = replaced
			end
		end
	end
end

-- Where each id was first seen, so the second sighting can name both sides
local origin: { [string]: string } = {}

local function normalize(source: any, label: string)
	visitAnimations(source, label, function(where, value)
		local id = assetId(value)
		if not id then
			warn(`[Movesets] {where} is not an animation id`)
			return nil
		end

		-- Still normalized: a raw number would fail on AnimationId
		if id == "rbxassetid://0" then
			warn(`[Movesets] {where} has no animation id yet`)
			return id
		end

		local first = origin[id]
		if first then
			warn(`[Movesets] {where} reuses the id already on {first}`)
		else
			origin[id] = where
		end

		return id
	end)
end

-- Flattens a layer into the moveset, so every consumer reads one table
local function overlay(into: any, patch: any?)
	if not patch then
		return
	end

	for key, value in patch do
		if type(value) == "table" and type(into[key]) == "table" then
			local merged = table.clone(into[key])
			for inner, entry in value do
				merged[inner] = entry
			end
			into[key] = merged
		else
			into[key] = value
		end
	end
end

-- Layers first: a shared id is declared once, so auditing the merge instead would
-- report every weapon that inherits it as a duplicate of the others.
for name, layer in Movesets.weights do
	normalize(layer, `weights.{name}`)
end
for name, layer in Movesets.types do
	normalize(layer, `types.{name}`)
end

for _, module in script:GetChildren() do
	if not module:IsA("ModuleScript") then
		continue
	end

	local name = module.Name
	local moveset = require(module) :: any

	for key in moveset do
		if not KNOWN_KEYS[key] then
			warn(`[Movesets] {name} declares unknown key "{key}"`)
		end
	end

	-- No warn for a missing type layer: most weapons have one grip and share nothing.
	if moveset.weight and not Movesets.weights[moveset.weight] then
		warn(`[Movesets] {name} points at weight "{moveset.weight}", which has no layer`)
	end

	normalize(moveset, name)

	local resolved = {}
	overlay(resolved, Movesets.weights[moveset.weight])
	overlay(resolved, Movesets.types[moveset.type])
	overlay(resolved, moveset)

	for _, role in REQUIRED do
		if resolved[role] == nil then
			warn(`[Movesets] {name} is missing "{role}"`)
		end
	end

	Movesets.classes[name] = table.freeze(resolved)
end

export type Movesets = typeof(Movesets)

table.freeze(Movesets.weights)
table.freeze(Movesets.types)
table.freeze(Movesets.classes)

return table.freeze(Movesets)
