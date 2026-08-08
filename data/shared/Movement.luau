--!strict

local Movement = {
	sprintSpeed = 20,
	sprintMinSpeed = 1,
	hardLandingSpeed = 35,

	animation = {
		sprint = "rbxassetid://113853542577722",
		land = "rbxassetid://83965390015351",
	},
}

export type Movement = typeof(Movement)

table.freeze(Movement.animation)

return table.freeze(Movement)
