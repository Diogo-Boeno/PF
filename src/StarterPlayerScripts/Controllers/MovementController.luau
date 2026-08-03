--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Data.Movement)

local SPRINT_KEY = Enum.KeyCode.LeftShift

local GROUNDED_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Landed] = true,
}

local SPRINT_ASSET = Instance.new("Animation")
SPRINT_ASSET.AnimationId = Config.animation.sprint

local LAND_ASSET = Instance.new("Animation")
LAND_ASSET.AnimationId = Config.animation.land

local player = Players.LocalPlayer

local sprintHeld = false

local humanoid: Humanoid? = nil
local sprintTrack: AnimationTrack? = nil
local landTrack: AnimationTrack? = nil
local connections: { RBXScriptConnection } = {}
local baseWalkSpeed = 0
local runSpeed = 0
local grounded = false
local fallStartY: number? = nil

local MovementController = {}

local function applyWalkSpeed()
	local current = humanoid
	if current then
		current.WalkSpeed = if sprintHeld then Config.sprintSpeed else baseWalkSpeed
	end
end

local function evaluateSprint()
	local track = sprintTrack
	if not track then
		return
	end

	local shouldPlay = sprintHeld and grounded and runSpeed > Config.sprintMinSpeed
	if shouldPlay == track.IsPlaying then
		return
	end

	if shouldPlay then
		track:Play()
	else
		track:Stop()
	end
end

local function onLanded(landedY: number)
	local startY = fallStartY
	fallStartY = nil

	local track = landTrack
	if not startY or not track then
		return
	end

	local drop = math.max(startY - landedY, 0)
	if math.sqrt(2 * workspace.Gravity * drop) > Config.hardLandingSpeed then
		track:Play()
	end
end

local function teardownCharacter()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)

	humanoid = nil
	sprintTrack = nil
	landTrack = nil
	runSpeed = 0
	grounded = false
	fallStartY = nil
end

local function setupCharacter(character: Model)
	teardownCharacter()

	local newHumanoid = character:WaitForChild("Humanoid") :: Humanoid
	local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	local animator = newHumanoid:WaitForChild("Animator") :: Animator

	local newSprintTrack = animator:LoadAnimation(SPRINT_ASSET)
	newSprintTrack.Looped = true

	local newLandTrack = animator:LoadAnimation(LAND_ASSET)

	humanoid = newHumanoid
	sprintTrack = newSprintTrack
	landTrack = newLandTrack

	baseWalkSpeed = newHumanoid.WalkSpeed
	grounded = true

	applyWalkSpeed()

	table.insert(
		connections,
		newHumanoid.Running:Connect(function(speed: number)
			runSpeed = speed
			evaluateSprint()
		end)
	)

	table.insert(
		connections,
		newHumanoid.StateChanged:Connect(function(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
			grounded = GROUNDED_STATES[new] == true

			if new == Enum.HumanoidStateType.Freefall then
				fallStartY = rootPart.Position.Y
			elseif new == Enum.HumanoidStateType.Landed then
				onLanded(rootPart.Position.Y)
			end

			evaluateSprint()
		end)
	)
end

function MovementController.Start()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or input.KeyCode ~= SPRINT_KEY then
			return
		end
		sprintHeld = true
		applyWalkSpeed()
		evaluateSprint()
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode ~= SPRINT_KEY then
			return
		end
		sprintHeld = false
		applyWalkSpeed()
		evaluateSprint()
	end)

	player.CharacterAdded:Connect(setupCharacter)
	player.CharacterRemoving:Connect(teardownCharacter)

	local character = player.Character
	if character then
		setupCharacter(character)
	end
end

return MovementController
