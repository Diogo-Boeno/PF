local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Loader = require(ReplicatedStorage.Shared.Framework.Loader)
local Controllers = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Controllers")

Loader.LoadDescendants(Controllers)
Loader.Start()
