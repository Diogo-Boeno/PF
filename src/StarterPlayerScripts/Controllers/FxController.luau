--!strict
-- Everything visual and audible for combat lands here. Nothing in this file is
-- authoritative — it only ever plays what the server already decided.

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Data.Fx)
local Net = require(ReplicatedStorage.Shared.Framework.Net)

local FIND_TIMEOUT = 10

-- Same attachment name RaycastHitbox already looks for, so blade VFX needs no new
-- rig setup: any weapon that can hit can also spark
local BLADE_POINT = "DmgPoint"

local sounds: Folder? = nil
local effects: Folder? = nil

local FxController = {}

local function trace(message: string)
	if Config.debug then
		print(`[Fx] {message}`)
	end
end

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

-- Clones the EMITTERS into the host attachment, never the attachment itself: an
-- Attachment cannot parent another Attachment.
--
-- Two modes, because impacts and states are not the same thing:
--   burst   — one Emit, particles fly free. Right for a hit: it happened, it is over.
--   sustain — Enabled for `duration`, emitting the whole time. Right for a tell: the
--             particles trail the blade because new ones keep being born at it. A
--             burst can never "follow" anything, since emitted particles are on their
--             own the instant they exist.
local function emitFrom(source: Attachment, host: Attachment, spec: any)
	local sustain = spec.mode == "sustain"
	local duration = spec.duration or 0.3
	local made = 0

	for _, template in source:GetChildren() do
		if not template:IsA("ParticleEmitter") then
			continue
		end
		made += 1

		local emitter = template:Clone()
		emitter.Name = "FxBurst"
		emitter.Enabled = sustain
		emitter.Parent = host

		if sustain then
			task.delay(duration, function()
				if emitter.Parent then
					emitter.Enabled = false
				end
			end)
			Debris:AddItem(emitter, duration + emitter.Lifetime.Max + 0.1)
		else
			local count = emitter:GetAttribute("EmitCount")
			emitter:Emit(if type(count) == "number" then count else Config.emitCount)
			Debris:AddItem(emitter, emitter.Lifetime.Max + 0.1)
		end
	end

	trace(`    emitFrom -> {made} emitter(s), sustain={sustain}, into {host:GetFullName()}`)
end

local function bladePoints(subject: Model): { Attachment }
	local points = {}
	for _, point in subject:GetDescendants() do
		if point:IsA("Attachment") and point.Name == BLADE_POINT then
			table.insert(points, point)
		end
	end
	return points
end

-- The tip is the DmgPoint furthest from the weapon's own root, which is geometry and
-- not pose: it stays the tip whatever the swing is doing at that instant.
local function tipOf(points: { Attachment }): Attachment?
	local best: Attachment? = nil
	local bestDistance = -1

	for _, point in points do
		local weapon = point:FindFirstAncestorWhichIsA("Model")
		local root = weapon and weapon.PrimaryPart
		if root then
			local distance = (point.WorldPosition - root.Position).Magnitude
			if distance > bestDistance then
				best = point
				bestDistance = distance
			end
		end
	end

	return best
end

-- Sparks belong to the blade, not to a point in the world: emitting from the weapon's
-- own DmgPoints means they follow the swing and land wherever the edge actually is.
local function playOnBlade(name: string, subject: Model, tipOnly: boolean, spec: any)
	local folder = effects
	local template = folder and folder:FindFirstChild(name)
	local source = template and template:FindFirstChildOfClass("Attachment")
	trace(`  playOnBlade "{name}" template={template ~= nil} attachment={source ~= nil}`)

	if not source then
		warn(`[FxController] no effect "{name}" with an Attachment`)
		return
	end

	local points = bladePoints(subject)
	trace(`  tipOnly={tipOnly} points={#points} on {subject.Name}`)

	if #points == 0 then
		warn(`[FxController] "{subject.Name}" has no {BLADE_POINT} to emit "{name}" from`)
		return
	end

	if tipOnly then
		local tip = tipOf(points)
		trace(`  tip = {if tip then tip:GetFullName() else "NONE (no weapon PrimaryPart?)"}`)
		if tip then
			emitFrom(source, tip, spec)
		end
		return
	end

	for _, point in points do
		emitFrom(source, point, spec)
	end
end

-- Only the Attachment is cloned. The template's Part exists to hold it in Studio and
-- would otherwise show up in the world as a floating block.
local function playEffect(name: string, cframe: CFrame)
	local folder = effects
	local template = folder and folder:FindFirstChild(name)
	local source = template and template:FindFirstChildOfClass("Attachment")
	trace(`  playEffect "{name}" template={template ~= nil} attachment={source ~= nil}`)

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
			emitter.Enabled = false
			local count = emitter:GetAttribute("EmitCount")
			emitter:Emit(if type(count) == "number" then count else Config.emitCount)
			longest = math.max(longest, emitter.Lifetime.Max)
		end
	end

	-- Live exactly as long as the slowest particle, not a fixed guess
	Debris:AddItem(anchor, longest + 0.1)
end

-- Public and separate from play(): the telegraph fires when the animation starts, the
-- sound and particles when the hitbox opens. Bundling them would put the tell too late
-- to be information the opponent can act on.
function FxController.highlight(event: string, subject: Model)
	local spec = Config.highlight[event]
	if not spec then
		return
	end

	-- Replaced rather than stacked, so repeated casts do not pile outlines up
	local existing = subject:FindFirstChild("FxHighlight")
	if existing then
		existing:Destroy()
	end

	local outline = Instance.new("Highlight")
	outline.Name = "FxHighlight"
	outline.FillTransparency = 1
	outline.OutlineColor = spec.color
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Adornee = subject
	outline.Parent = subject

	Debris:AddItem(outline, spec.duration)
end

-- `event` keys into every table, so one name carries sound, particle and outline.
-- `subject` is the character it happened to, when there is one.
function FxController.play(event: string, position: Vector3, subject: Model?)
	trace(
		`play "{event}" subject={if subject then subject.Name else "nil"}`
			.. ` sound={Config.sound[event] ~= nil} effect={Config.effect[event] ~= nil}`
			.. ` folderReady={effects ~= nil}`
	)

	local list = Config.sound[event]
	if list then
		local name = pick(list)
		if name then
			playSound(name, position)
		end
	end

	local effect = Config.effect[event]
	if effect then
		local spec = if type(effect) == "table" then effect else { name = effect }

		-- `blade` rides every DmgPoint, `tip` only the furthest one — the burst follows
		-- the edge instead of sitting where the character happened to be
		if (spec.on == "blade" or spec.on == "tip") and subject then
			playOnBlade(spec.name, subject, spec.on == "tip", spec)
		else
			local at = CFrame.new(position)

			-- Local-space offset needs the subject's orientation to mean anything
			if spec.offset then
				local pivot = if subject then subject:GetPivot() else at
				at = (pivot - pivot.Position + position) * CFrame.new(spec.offset)
			end
			playEffect(spec.name, at)
		end
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

	-- A particle texture loads on first use and the burst that triggers the load draws
	-- nothing — the first combo comes out invisible while every one after it works.
	--
	-- Content strings, not the instances: PreloadAsync does not resolve a
	-- ParticleEmitter's Texture from the folder, so handing it the folder does nothing.
	task.spawn(function()
		local assets: { string } = {}

		if effects then
			for _, item in effects:GetDescendants() do
				if item:IsA("ParticleEmitter") and item.Texture ~= "" then
					table.insert(assets, item.Texture)
				end
			end
		end

		if sounds then
			for _, item in sounds:GetDescendants() do
				if item:IsA("Sound") and item.SoundId ~= "" then
					table.insert(assets, item.SoundId)
				end
			end
		end

		trace(`preloading {#assets} asset(s)`)
		if #assets > 0 then
			local ok, err = pcall(ContentProvider.PreloadAsync, ContentProvider, assets)
			trace(`preload done ok={ok} {if ok then "" else tostring(err)}`)
		end
	end)

	-- Last, because Net.On yields on WaitForChild
	Net.On("Fx", function(event: string, position: Vector3, subject: Model?)
		FxController.play(event, position, subject)
	end)

	Net.On("Telegraph", function(event: string, subject: Model?)
		if subject then
			FxController.highlight(event, subject)
		end
	end)
end

return FxController
