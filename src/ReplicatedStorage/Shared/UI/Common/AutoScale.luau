--!strict
-- Screen-size normalization for pixel-designed UI. `factor()` returns a reactive
-- scale that maps the current viewport against a 1920x1080 design baseline, so a
-- window authored in offset pixels keeps its intended proportions on any screen.
-- Must be called inside a reactive scope (it registers a cleanup).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)

local source = Vide.source
local cleanup = Vide.cleanup

-- 720p baseline means the factor is >= 1 on virtually every screen — the UI
-- only ever grows from its authored pixel size, never shrinks below it
local BASE_WIDTH = 1280
local BASE_HEIGHT = 720
local MIN_SCALE = 0.9
local MAX_SCALE = 1.6

local AutoScale = {}

local function compute(): number
	local camera = Workspace.CurrentCamera
	if not camera then
		return 1
	end
	local viewport = camera.ViewportSize
	if viewport.X <= 1 or viewport.Y <= 1 then
		return 1
	end
	return math.clamp(math.min(viewport.X / BASE_WIDTH, viewport.Y / BASE_HEIGHT), MIN_SCALE, MAX_SCALE)
end

function AutoScale.factor(): () -> number
	local factor = source(compute())
	local camera = Workspace.CurrentCamera
	if camera then
		cleanup(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			factor(compute())
		end))
	end
	return factor
end

return AutoScale
