-- Author: Roox4



--[[

Example Usage:
////////////////////////////////////////////////////////////////

local ProceduralModule = require(/moduleLocation/.ProceduralModule)

local runService = game:GetService("RunService")

local enemy = script.Parent
local root = enemy:FindFirstChild("HumanoidRootPart")
local hum = enemy:FindFirstChild("Humanoid")
local alignOrientation = root:FindFirstChild("AlignOrientation")

local target = workspace:FindFirstChild("Target")

--// IkTargets
local ikTargets = enemy:FindFirstChild("IkTargets")
local leftFront_IkTarget = ikTargets:FindFirstChild("LeftFront_IkTarget")
local leftBack_IkTarget = ikTargets:FindFirstChild("LeftBack_IkTarget")
local rightFront_IkTarget = ikTargets:FindFirstChild("RightFront_IkTarget")
local rightBack_IkTarget = ikTargets:FindFirstChild("RightBack_IkTarget")

--// Raycast parts
local raycastParts = enemy:FindFirstChild("RaycastParts")
local leftFront_RaycastPart = raycastParts:FindFirstChild("LeftFront_RaycastPart")
local leftBack_RaycastPart = raycastParts:FindFirstChild("LeftBack_RaycastPart")
local rightFront_RaycastPart = raycastParts:FindFirstChild("RightFront_RaycastPart")
local rightBack_RaycastPart = raycastParts:FindFirstChild("RightBack_RaycastPart")

--// IKControls
local leftFront_IKControl = hum:FindFirstChild("LeftFront_IKControl")
local leftBack_IKControl = hum:FindFirstChild("LeftBack_IKControl")
local rightFront_IKControl = hum:FindFirstChild("RightFront_IKControl")
local rightBack_IKControl = hum:FindFirstChild("RightBack_IKControl")

leftFront_IKControl.Pole = root.LeftFront_Pole
leftBack_IKControl.Pole = root.LeftBack_Pole
rightFront_IKControl.Pole = root.RightFront_Pole
rightBack_IKControl.Pole = root.RightBack_Pole

--// RaycastParams
local rayCastParams = RaycastParams.new()
rayCastParams.FilterDescendantsInstances = {enemy}
rayCastParams.FilterType = Enum.RaycastFilterType.Exclude

for _,v: BasePart in ikTargets:GetChildren() do
	v.Transparency = 1
end

for _,v: BasePart in raycastParts:GetChildren() do
	v.Transparency = 1
end

coroutine.wrap(function()
	while task.wait(0.25) do
		hum:MoveTo(target.Position)
	end
end)()

runService.Heartbeat:Connect(function()
	local rayCast = workspace:Raycast(root.Position, -1000 * root.CFrame.UpVector, rayCastParams)

	if rayCast then
		local rotateToFloorCFrame = ProceduralModule:getRotationBetween(root.CFrame.UpVector, rayCast.Normal)
		local floorOrientedCFrame = rotateToFloorCFrame * CFrame.new(root.Position)

		local dz = (root.Position.Z - target.Position.Z)
		local dx = (root.Position.X - target.Position.X)
		local horizontalAngle = math.atan2(dx, dz)

		alignOrientation.CFrame = floorOrientedCFrame.Rotation * CFrame.fromOrientation(0, horizontalAngle, 0)
	end
end)

while true do
	ProceduralModule:IkLegStep(leftFront_IkTarget, leftFront_RaycastPart, enemy.PrimaryPart, 2, 2, 1, 0.05, rayCastParams)
	ProceduralModule:IkLegStep(rightBack_IkTarget, rightBack_RaycastPart, enemy.PrimaryPart, 2, 2, 1, 0.05, rayCastParams)
	task.wait(0.1)
	ProceduralModule:IkLegStep(rightFront_IkTarget, rightFront_RaycastPart, enemy.PrimaryPart, 2, 2, 1, 0.05, rayCastParams)
	ProceduralModule:IkLegStep(leftBack_IkTarget, leftBack_RaycastPart, enemy.PrimaryPart, 2, 2, 1, 0.05, rayCastParams)
	task.wait(0.1)
end
////////////////////////////////////////////////////////////////

--]]



local ProceduralModule = {}


--// Returns a CFrame rotation between two vectors
--// Credit: @EgoMoose (Roblox)
function ProceduralModule:getRotationBetween(u, v)
	local randomAxis = Vector3.new(1, 0, 0)

	local dot = u:Dot(v)
	if (dot > 0.99999) then
		return CFrame.new()

	elseif (dot < -0.99999) then
		return CFrame.fromAxisAngle(randomAxis, math.pi)
	end

	return CFrame.fromAxisAngle(u:Cross(v), math.acos(dot))
end



--[[

Parameters:

ikTarget ->			A reference to the IK target of a leg
ikRayPart ->		A reference to the raycast part of a leg
root ->				The root part of a model
stepDistance ->		A number that specifies a distance a model has to travel before this function executes
stepForward -> 		A number that specifies a length of a step
stepHeight -> 		A number that specifies a maximum height the leg reaches when stepping
stepWait -> 		A number that specifies a how long the step takes (should be a small value like 0.05)
rayCastParams -> 	A reference to the RaycastParams

--]]


--// Calculates the position of a leg
function ProceduralModule:IkLegStep(ikTarget: BasePart, ikRayPart: BasePart, root: BasePart, stepDistance: number, stepForward: number, stepHeight: number, stepWait: number, rayCastParams: RaycastParams)
	stepWait = stepWait or 0.05
	stepForward = stepForward or 0
	stepHeight = stepHeight or 2

	local rayCast = workspace:Raycast(ikRayPart.Position, Vector3.new(0, -1000, 0), rayCastParams)

	if rayCast then
		if not ikTarget:GetAttribute("PreviousPos") then
			ikTarget:SetAttribute("PreviousPos", Vector3.new(0, 0, 0))
		end

		local previousFootPos = ikTarget:GetAttribute("PreviousPos")

		local defaultFootPos = rayCast.Position
		local diff = (defaultFootPos - previousFootPos).Magnitude

		--// Do a step
		if diff > stepDistance then
			local finalFootPos = rayCast.Position + root.CFrame.LookVector * stepForward
			local middleFootPos = ((finalFootPos - previousFootPos) * 0.5 + previousFootPos) + Vector3.new(0, stepHeight, 0)

			coroutine.wrap(function()
				ikTarget.Position = middleFootPos
				task.wait(stepWait)
				ikTarget.Position = finalFootPos

				ikTarget:SetAttribute("PreviousPos", ikTarget.Position)
			end)()
		end
	end
end

return ProceduralModule
