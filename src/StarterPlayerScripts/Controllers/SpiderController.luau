--!strict
-- Drives the procedural gait of every spider rig on screen, locally.
--
-- Nothing is replicated: the gait is derived from HumanoidRootPart position and
-- velocity, which already replicate, so each client simulates every rig it can
-- see. Legs may differ by a frame between clients — invisible in practice, and
-- it costs zero bandwidth and never lags behind the body.
--
-- Discovery is CharacterAdded rather than a CollectionService tag: the spider is
-- the StarterCharacter, so every character is a rig by definition. A tag would
-- add a manual Studio step that fails silently the moment it is forgotten.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SpiderGait = require(ReplicatedStorage.Shared.Modules.SpiderGait)

local STEP_NAME = "SpiderGait"

-- Rigs beyond this are a few pixels tall; their legs are not worth a raycast.
local MAX_SIM_DISTANCE = 300

-- Flip to true and read the output when the gait looks wrong; tuning blind is
-- how you end up chasing a rig assembly problem in the maths.
local DEBUG = false
local DEBUG_INTERVAL = 1

local rigs: { [Model]: SpiderGait.Rig } = {}
local pending: { [Model]: boolean } = {}
local connections: { RBXScriptConnection } = {}
local sinceDebug = 0

local SpiderController = {}

local function detach(model: Model)
	pending[model] = nil
	local rig = rigs[model]
	if rig then
		rigs[model] = nil
		SpiderGait.destroy(rig)
	end
end

local function attach(model: Model)
	if rigs[model] or pending[model] then
		return
	end
	pending[model] = true

	-- create yields on WaitForChild, so it cannot run inline
	task.spawn(function()
		local rig = SpiderGait.create(model)
		-- detach can run while we are yielding; pending is the cancel token
		local cancelled = not pending[model]
		pending[model] = nil

		if not rig then
			warn(`[SpiderController] create failed for {model:GetFullName()}`)
			return
		end
		if cancelled or not model.Parent then
			SpiderGait.destroy(rig)
			return
		end

		rigs[model] = rig
	end)
end

local function watch(player: Player)
	table.insert(connections, player.CharacterAdded:Connect(attach))
	table.insert(connections, player.CharacterRemoving:Connect(detach))
	-- the local player is usually already spawned by the time controllers load
	if player.Character then
		attach(player.Character)
	end
end

local function onRenderStep(dt: number)
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else nil

	for _, rig in rigs do
		if not eye or (rig.root.Position - eye).Magnitude < MAX_SIM_DISTANCE then
			SpiderGait.step(rig, dt)
		end
	end

	if not DEBUG then
		return
	end
	sinceDebug += dt
	if sinceDebug < DEBUG_INTERVAL then
		return
	end
	sinceDebug = 0
	for _, rig in rigs do
		SpiderGait.diagnose(rig)
	end
end

function SpiderController.Init()
	table.insert(connections, Players.PlayerAdded:Connect(watch))
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

function SpiderController.Start()
	-- Body motion writes Motor6D.C0 after the Animator has posed the rig, so this
	-- must sit at or after RenderPriority.Character.
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Character.Value + 1, onRenderStep)
end

function SpiderController.Stop()
	RunService:UnbindFromRenderStep(STEP_NAME)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for model in rigs do
		detach(model)
	end
end

return SpiderController
