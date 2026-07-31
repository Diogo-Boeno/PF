--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)
local Theme = require(script.Parent.Theme)

local create = Vide.create
local source = Vide.source
local effect = Vide.effect
local cleanup = Vide.cleanup
local changed = Vide.changed
local read = Vide.read

type Reactive<T> = T | () -> T

export type ModelViewportProps = {
	model: Reactive<Model?>,
	-- orbit angles in degrees; supply sources to spin the model reactively
	yaw: Reactive<number>?,
	pitch: Reactive<number>?,
	-- distance multiplier over the exact fit; >1 leaves breathing room
	padding: number?,
	fieldOfView: number?,
	background: boolean?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	parent: Instance?,
}

-- Positions the camera so the model's bounding sphere fits the frame at ANY
-- aspect ratio. Roblox camera FOV is vertical, so the horizontal half-angle
-- must be derived from the ratio; fitting against the tighter of the two axes
-- guarantees the model never crops whether the frame is wide, tall, or square.
local function frameModel(model: Model, camera: Camera, aspect: number, yaw: number, pitch: number, padding: number)
	if aspect <= 0 then
		return
	end

	local boxCFrame, boxSize = model:GetBoundingBox()
	-- circumscribing sphere: rotation-invariant, so orbiting never clips corners
	local radius = boxSize.Magnitude / 2
	if radius <= 0 then
		return
	end

	local halfV = math.rad(camera.FieldOfView) / 2
	local halfH = math.atan(aspect * math.tan(halfV))
	local halfMin = math.min(halfV, halfH)

	local distance = (radius / math.sin(halfMin)) * padding

	local orbit = CFrame.fromEulerAnglesYXZ(math.rad(pitch), math.rad(yaw), 0)
	local eye = boxCFrame.Position + orbit * Vector3.new(0, 0, distance)
	camera.CFrame = CFrame.lookAt(eye, boxCFrame.Position)
end

local function ModelViewport(props: ModelViewportProps)
	local aspect = source(1)
	local padding = props.padding or 1.12

	local camera = create "Camera" {
		FieldOfView = props.fieldOfView or 55,
	}

	local viewport = create "ViewportFrame" {
		Name = "ModelViewport",
		Size = props.size or UDim2.fromOffset(180, 180),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = Theme.color.surfacePressed,
		-- transparent by default; only draw the recessed backdrop when asked
		BackgroundTransparency = if props.background == true then 0 else 1,
		BorderSizePixel = 0,
		CurrentCamera = camera,
		-- neutral gray light keeps monochrome models readable without color cast
		Ambient = Color3.fromRGB(150, 150, 150),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
		Parent = props.parent,

		camera,

		-- fires once on mount then on every resize, so the fit re-solves whenever
		-- the frame's proportions change (this is the whole point of the component)
		changed("AbsoluteSize", function(sz: Vector2)
			aspect(if sz.Y > 0 then sz.X / sz.Y else 1)
		end),

		create "UICorner" { CornerRadius = Theme.radius.md },
		create "UIStroke" {
			Color = Theme.color.stroke,
			Thickness = Theme.strokeThickness,
			Transparency = 1,
		},
	}

	-- clone lifecycle lives in upvalues (not effect-scoped cleanup) because the
	-- framing effect re-runs on yaw/pitch/aspect too — we only want to rebuild
	-- the clone when the source model actually changes.
	local lastTemplate: Model? = nil
	local clone: Model? = nil

	effect(function()
		local template = read(props.model)
		local a = aspect()
		local yaw = if props.yaw ~= nil then read(props.yaw) else 0
		local pitch = if props.pitch ~= nil then read(props.pitch) else 0

		if template ~= lastTemplate then
			if clone then
				clone:Destroy()
				clone = nil
			end
			lastTemplate = template
			if template then
				-- clone so a model living in Assets/ is never reparented out of it
				local fresh = template:Clone()
				fresh.Parent = viewport
				clone = fresh
			end
		end

		if clone then
			frameModel(clone, camera, a, yaw, pitch, padding)
		end
	end)

	cleanup(function()
		if clone then
			clone:Destroy()
		end
	end)

	return viewport
end

return ModelViewport
