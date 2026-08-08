--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SmartBoneController = {}

function SmartBoneController.Start()
	-- SmartBone snapshots CollectionService:GetTagged() at require time but only connects
	-- its added/removed signals inside Start(). Requiring here keeps both in the same
	-- resumption so nothing tagged during boot falls into the gap between them.
	local SmartBone = require(ReplicatedStorage.SmartBone)

	SmartBone.Start()
end

return SmartBoneController
