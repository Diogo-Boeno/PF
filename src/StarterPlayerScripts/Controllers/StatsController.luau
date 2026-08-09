--!strict
-- Drives the hand-built bars under PlayerGui.Stats, each a ScreenGui holding a
-- Shadow and a Fill as siblings. The UI owns its own look; this writes Fill.Size only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Data.Weapons)

local FOLDER_NAME = "Stats"
local FILL_NAME = "Fill"
local FIND_TIMEOUT = 10

local DRAIN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

type Bar = {
	fill: Frame,
	-- Size as authored in Studio, which is what "full" means
	full: UDim2,
	tween: Tween?,
}

local player = Players.LocalPlayer

local bars: { [string]: Bar } = {}
local humanoid: Humanoid? = nil
local connections: { RBXScriptConnection } = {}

local StatsController = {}

-- Fills anchor at (0, 0.5), so scaling X alone drains them from the right
local function setFraction(name: string, fraction: number, animate: boolean)
	local bar = bars[name]
	if not bar then
		return
	end

	local ratio = math.clamp(fraction, 0, 1)
	local full = bar.full
	local goal = UDim2.new(full.X.Scale * ratio, full.X.Offset * ratio, full.Y.Scale, full.Y.Offset)

	if bar.tween then
		bar.tween:Cancel()
		bar.tween = nil
	end

	if not animate then
		bar.fill.Size = goal
		return
	end

	local tween = TweenService:Create(bar.fill, DRAIN, { Size = goal })
	bar.tween = tween
	tween:Play()
end

local function refreshHealth()
	local living = humanoid
	if not living then
		return
	end
	local max = living.MaxHealth
	setFraction("Health", if max > 0 then living.Health / max else 0, true)
end

local function refreshPosture()
	local value = player:GetAttribute(Config.postureAttribute)
	local max = Config.guard.postureMax
	-- Already arrives as a smooth ramp from the server's decay, so tweening it
	-- would only add lag behind a value that is not jumping in the first place
	setFraction("Posture", if type(value) == "number" and max > 0 then value / max else 0, false)
end

local function teardownCharacter()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	humanoid = nil
end

local function setupCharacter(character: Model)
	teardownCharacter()

	local newHumanoid = character:WaitForChild("Humanoid") :: Humanoid
	if player.Character ~= character then
		return
	end
	humanoid = newHumanoid

	table.insert(connections, newHumanoid.HealthChanged:Connect(refreshHealth))
	table.insert(connections, newHumanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refreshHealth))

	refreshHealth()
end

-- Every ScreenGui in the folder registers itself, so a bar with no data source yet
-- still gets picked up the day something feeds it
local function collectBars()
	local gui = player:WaitForChild("PlayerGui")
	local folder = gui:WaitForChild(FOLDER_NAME, FIND_TIMEOUT)
	if not folder then
		warn(`[StatsController] PlayerGui has no {FOLDER_NAME}`)
		return
	end

	for _, screen in folder:GetChildren() do
		if not screen:IsA("ScreenGui") then
			continue
		end

		local fill = screen:FindFirstChild(FILL_NAME)
		if fill and fill:IsA("Frame") then
			bars[screen.Name] = { fill = fill, full = fill.Size }
		else
			warn(`[StatsController] {screen.Name} has no {FILL_NAME}`)
		end
	end
end

function StatsController.Start()
	collectBars()

	player:GetAttributeChangedSignal(Config.postureAttribute):Connect(refreshPosture)
	refreshPosture()

	player.CharacterAdded:Connect(setupCharacter)
	player.CharacterRemoving:Connect(teardownCharacter)

	local character = player.Character
	if character then
		task.spawn(setupCharacter, character)
	end
end

return StatsController
