--!strict
-- Decides, never acts. Every function is a pure read of a profile plus numbers the
-- caller already holds, so the body and the decision can be reasoned about apart.
--
-- Difficulty is timing, not permission: the brain returns WHEN to press, and the same
-- `parryWindow` that judges a player judges what that press turns into.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Data.Weapons)

local Guard = Config.guard

-- Aim for the middle of the parry window, so error either way still lands the guard up:
-- early reads as a block, late as a hit. Failing gracefully is the whole point.
local PARRY_LEAD = Guard.parryWindow / 2

-- Preferred lead for a block. Clamped in `commitAt` to whatever the incoming swing
-- actually leaves room for.
local BLOCK_LEAD = 0.35

-- How long a raised guard stays up. Past `parryWindow` on purpose: releasing inside it
-- would hand the rig free parry frames it never earned.
local GUARD_HOLD = 0.55

local NpcBrain = {}

-- nil means the telegraph went unnoticed, which is how awareness is paid for
function NpcBrain.chooseDefence(profile: any, rng: Random): string?
	if profile.answerTotal <= 0 or rng:NextNumber() > profile.awareness then
		return nil
	end

	local roll = rng:NextNumber() * profile.answerTotal
	for answer, weight in profile.answer do
		roll -= weight
		if roll <= 0 then
			return answer
		end
	end
	return nil
end

-- Clock time to commit, jittered. The caller drops it if it has already passed: a read
-- that arrives after the blade is no read at all.
function NpcBrain.commitAt(profile: any, defence: string, landsAt: number, now: number, rng: Random): number
	local windup = landsAt - now
	local jitter = profile.jitter
	local lead = PARRY_LEAD

	if defence == "dodge" then
		-- I-frames start on the press and are spent by the first hit, so they only have
		-- to be open when the blade arrives
		lead = Config.dash.iframes / 2
	elseif defence ~= "parry" then
		-- A block has two hard bounds, and a fixed lead honours neither. Late enough
		-- that the press has not happened before the swing began, early enough that the
		-- guard has settled PAST the parry window — otherwise a fighter with no parry in
		-- its answers would luck into one and stop being the archetype it is.
		--
		-- A fast weapon against a sloppy fighter can leave no room between the two. That
		-- is a real loss, not something to paper over, so the bounds cross and the
		-- midpoint takes the blame.
		local low = Guard.parryWindow + jitter
		local high = windup - jitter
		lead = if low <= high then math.clamp(BLOCK_LEAD, low, high) else (low + high) / 2
	end

	return landsAt - lead + rng:NextNumber(-jitter, jitter)
end

-- How long the rig is committed once it acts, so it stops re-deciding mid-answer but
-- frees up the moment the answer is spent
function NpcBrain.holdFor(defence: string): number
	return if defence == "dodge" then Config.dash.ground.time else GUARD_HOLD
end

function NpcBrain.shouldAttack(profile: any, rng: Random): boolean
	return rng:NextNumber() <= profile.aggression
end

return NpcBrain
