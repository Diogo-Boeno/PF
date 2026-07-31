local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local Theme = require(ReplicatedStorage.Shared.UI.Common.Theme)
local ModelViewport = require(ReplicatedStorage.Shared.UI.Common.ModelViewport)

-- self-contained placeholder so the story never depends on an asset existing
-- elsewhere in the game; any real Model works the same way through `model`.
local function buildDemoModel(): Model
	local model = Instance.new("Model")
	model.Name = "DemoModel"

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Anchored = true
	base.CanCollide = false
	base.Size = Vector3.new(3, 3, 3)
	base.Color = Theme.color.surfaceRaised
	base.Material = Enum.Material.SmoothPlastic
	base.Parent = model

	local accent = Instance.new("Part")
	accent.Name = "Accent"
	accent.Shape = Enum.PartType.Ball
	accent.Anchored = true
	accent.CanCollide = false
	accent.Size = Vector3.new(1.4, 1.4, 1.4)
	accent.Color = Theme.color.accent
	accent.Material = Enum.Material.Neon
	accent.CFrame = base.CFrame * CFrame.new(0, 2.2, 0)
	accent.Parent = model

	model.PrimaryPart = base
	return model
end

local demoModel = buildDemoModel()

return {
	vide = Vide,
	summary = "Orbit camera auto-fits any model to the frame; drag yaw/pitch to see it live.",
	controls = {
		yaw = 25,
		pitch = -15,
		padding = 1.12,
		fieldOfView = 55,
		background = true,
	},
	story = function(props)
		return ModelViewport {
			parent = props.target,
			size = UDim2.fromOffset(240, 240),
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
			model = demoModel,
			-- reactive props: orbiting updates live as the controls change
			yaw = props.controls.yaw,
			pitch = props.controls.pitch,
			padding = props.controls.padding(),
			fieldOfView = props.controls.fieldOfView(),
			background = props.controls.background(),
		}
	end,
}
