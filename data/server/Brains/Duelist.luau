--!strict
-- The smart one. Its jitter is below half the parry window, so every parry it ATTEMPTS
-- lands — what limits it is `awareness` and the weights below, not precision. Raise
-- jitter past 0.08 if you want failed parries to be the throttle instead.

return {
	awareness = 0.9,
	answer = { parry = 6, block = 3, dodge = 2 },
	jitter = 0.035,
	aggression = 0.6,
	attackCooldown = 1.2,
}
