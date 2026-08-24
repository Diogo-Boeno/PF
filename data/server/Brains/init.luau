--!strict
-- One brain per file, discovered at require time. A rig picks one with the `Brain`
-- attribute; anything unnamed falls back to `DEFAULT`.
--
-- Server-only on purpose: how well a boss reads you is not something a client needs.
--
-- Difficulty here is never a special rule. An NPC presses guard through the same
-- `setGuard` a player's F does and is judged by the same `parryWindow` — so a worse
-- fighter is only one that notices less often and presses less accurately.

local Brains = {
	DEFAULT = "Brute",

	-- Everything a brain may leave out. A file writes only what differs from this.
	defaults = {
		-- Chance of noticing a telegraph at all. A miss simply eats the hit.
		awareness = 0.6,

		-- How it answers what it noticed, as weights. A missing key means it cannot do
		-- that at all — the same rule a missing move follows everywhere else here.
		answer = { block = 1 },

		-- Seconds of error either side of the intended press. `guard.parryWindow` is
		-- 0.16s, so jitter near that turns intended parries into ordinary blocks and
		-- then into nothing — which is how a worse fighter should fail.
		jitter = 0.06,

		-- Chance of swinging when the cooldown is up and something is in range. Below 1
		-- so the rig stops reading as a metronome.
		aggression = 0.7,
		attackCooldown = 1.6,
	},

	byId = {} :: { [string]: any },
}

local function overlay(into: any, patch: any)
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

local KNOWN_KEYS = {
	awareness = true,
	answer = true,
	jitter = true,
	aggression = true,
	attackCooldown = true,
}

local ANSWERS = {
	parry = true,
	block = true,
	dodge = true,
}

for _, module in script:GetChildren() do
	if not module:IsA("ModuleScript") then
		continue
	end

	local name = module.Name
	local brain = require(module) :: any

	for key in brain do
		if not KNOWN_KEYS[key] then
			warn(`[Brains] {name} declares unknown key "{key}"`)
		end
	end

	local resolved = {}
	overlay(resolved, Brains.defaults)
	overlay(resolved, brain)

	local total = 0
	for answer, weight in resolved.answer do
		if not ANSWERS[answer] then
			warn(`[Brains] {name} answers with "{answer}", which is not a defence`)
			continue
		end
		total += weight
	end

	if total <= 0 then
		warn(`[Brains] {name} has no usable defence and will never guard`)
	end
	resolved.answerTotal = total
	resolved.id = name

	Brains.byId[name] = table.freeze(resolved)
end

if not Brains.byId[Brains.DEFAULT] then
	warn(`[Brains] the default brain "{Brains.DEFAULT}" has no file`)
end

export type Brains = typeof(Brains)

table.freeze(Brains.defaults)
table.freeze(Brains.byId)

return table.freeze(Brains)
