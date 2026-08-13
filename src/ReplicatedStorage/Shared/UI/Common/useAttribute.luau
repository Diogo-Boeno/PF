--!strict
-- Bridges a replicated attribute into a Vide source. Progression replicates through
-- Player attributes, so every screen that shows it needs this.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Vide = require(Packages.vide)

local source = Vide.source
local cleanup = Vide.cleanup

local function useAttribute<T>(instance: Instance, name: string, default: T): () -> T
	local value = source((instance:GetAttribute(name) :: any) or default)

	local connection = instance:GetAttributeChangedSignal(name):Connect(function()
		value((instance:GetAttribute(name) :: any) or default)
	end)
	cleanup(connection)

	return value
end

return useAttribute
