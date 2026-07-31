local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Loader = require(ReplicatedStorage.Shared.Framework.Loader)

Loader.LoadDescendants(ServerScriptService.Services)
Loader.Start()
