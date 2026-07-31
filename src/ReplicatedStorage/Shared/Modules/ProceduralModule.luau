-- Author: Roox4

local ProceduralModule = {}

--// Returns a CFrame rotation between two vectors
--// Credit: @EgoMoose (Roblox)
function ProceduralModule:getRotationBetween(u, v)
	local randomAxis = Vector3.new(1, 0, 0)

	local dot = u:Dot(v)
	if dot > 0.99999 then
		return CFrame.new()
	elseif dot < -0.99999 then
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
function ProceduralModule:IkLegStep(
	ikTarget: BasePart,
	ikRayPart: BasePart,
	root: BasePart,
	stepDistance: number,
	stepForward: number,
	stepHeight: number,
	stepWait: number,
	rayCastParams: RaycastParams
)
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
			local middleFootPos = ((finalFootPos - previousFootPos) * 0.5 + previousFootPos)
				+ Vector3.new(0, stepHeight, 0)

			task.spawn(function()
				ikTarget.Position = middleFootPos
				task.wait(stepWait)
				ikTarget.Position = finalFootPos

				ikTarget:SetAttribute("PreviousPos", ikTarget.Position)
			end)
		end
	end
end

return ProceduralModule
