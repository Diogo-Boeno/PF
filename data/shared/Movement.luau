--!strict
-- Tuning for MovementController. Data only — no logic, no instances. Feel lives here
-- so tweaking it never means reading the controller. Frozen so a stray write can't
-- silently retune movement at runtime.

local Movement = {
	-- WalkSpeed while sprinting. There is no walk value on purpose: the humanoid
	-- spawns with StarterPlayer's speed and the controller restores that, which keeps
	-- one source of truth for walking.
	sprintSpeed = 20,

	-- Below this the sprint cycle reads as sliding in place rather than running.
	sprintMinSpeed = 1,

	-- Impact speed that earns the heavy landing animation, as v = sqrt(2*g*h).
	-- Measured in Studio at default gravity (196.2): a plain jump on flat ground lands
	-- at 0, a 3-stud step-off at ~34, a 5.5-stud drop at ~47, an 8-stud drop at ~56.
	-- 60 was too high to ever fire in normal play; 45 catches a real drop and still
	-- ignores jumping in place.
	hardLandingSpeed = 35,

	animation = {
		sprint = "rbxassetid://113853542577722",
		land = "rbxassetid://83965390015351",
	},
}

export type Movement = typeof(Movement)

table.freeze(Movement.animation)

return table.freeze(Movement)
