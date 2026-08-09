--!strict
-- Everything visual and audible for combat lands here. Nothing in this file is
-- authoritative — it only ever plays what the server already decided.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Data.Fx)
local Net = require(ReplicatedStorage.Shared.Framework.Net)

local FIND_TIMEOUT = 10

local sounds: Folder? = nil
local effects: Folder? = nil

local FxController = {}

local function pick(list: { string }): string?
	if #list == 0 then
		return nil
	end
	return list[math.random(#list)]
end

-- Attachment rather than a Part: a positional sound needs a point in the world,
-- not a body, and this spawns no physics for the engine to solve
local function playSound(name: string, position: Vector3)
	local folder = sounds
	local template = folder and folder:FindFirstChild(name)
	if not template or not template:IsA("Sound") then
		warn(`[FxController] no sound "{name}"`)
		return
	end

	local anchor = Instance.new("Attachment")
	anchor.Name = "FxSound"
	anchor.WorldPosition = position
	anchor.Parent = workspace.Terrain

	local sound = template:Clone()
	sound.Parent = anchor
	sound:Play()

	Debris:AddItem(anchor, sound.TimeLength > 0 and sound.TimeLength + 0.5 or 5)
end

-- Only the Attachment is cloned. The template's Part exists to hold it in Studio and
-- would otherwise show up in the world as a floating block.
local function playEffect(name: string, cframe: CFrame)
	local folder = effects
	local template = folder and folder:FindFirstChild(name)
	local source = template and template:FindFirstChildOfClass("Attachment")
	if not source then
		warn(`[FxController] no effect "{name}" with an Attachment`)
		return
	end

	local anchor = source:Clone()
	anchor.Name = "FxBurst"
	anchor.Parent = workspace.Terrain
	anchor.WorldCFrame = cframe

	local longest = 0
	for _, emitter in anchor:GetDescendants() do
		if emitter:IsA("ParticleEmitter") then
			-- Emit is the burst. Leaving Enabled on streams particles the whole time
			-- the anchor lives, which is what made it look like it was blinking.
			emitter.Enabled = false
			local count = emitter:GetAttribute("EmitCount")
			emitter:Emit(if type(count) == "number" then count else Config.emitCount)
			longest = math.max(longest, emitter.Lifetime.Max)
		end
	end

	-- Live exactly as long as the slowest particle, not a fixed guess
	Debris:AddItem(anchor, longest + 0.1)
end

-- `event` keys into both tables, so one name carries sound and particle together
function FxController.play(event: string, position: Vector3)
	local list = Config.sound[event]
	if list then
		local name = pick(list)
		if name then
			playSound(name, position)
		end
	end

	local effect = Config.effect[event]
	if effect then
		playEffect(effect, CFrame.new(position))
	end
end

function FxController.Start()
	sounds = ReplicatedStorage:WaitForChild(Config.soundFolder, FIND_TIMEOUT) :: Folder?
	effects = ReplicatedStorage:WaitForChild(Config.effectFolder, FIND_TIMEOUT) :: Folder?

	if not sounds then
		warn(`[FxController] ReplicatedStorage has no {Config.soundFolder}`)
	end
	if not effects then
		warn(`[FxController] ReplicatedStorage has no {Config.effectFolder}`)
	end

	-- Last, because Net.On yields on WaitForChild
	Net.On("Fx", function(event: string, position: Vector3)
		FxController.play(event, position)
	end)
end

return FxController
