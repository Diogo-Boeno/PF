--!strict
-- Tag-driven behavior binding over CollectionService. Register a handler for a
-- tag once and it runs for every instance carrying that tag — the ones already
-- present and every one tagged later — then cleans up when the tag is removed or
-- the instance is destroyed. Keeps world objects declarative: tag a part in
-- Studio, bind the tag in code, never hunt instances by hand.
--
-- A handler is either a function or a small module of functions:
--
--   Tags.bind("Prompt", function(instance)
--       local conn = instance.Triggered:Connect(onTrigger)
--       return function() conn:Disconnect() end   -- optional cleanup
--   end)
--
--   Tags.bind("Prompt", {
--       added = function(instance) ... return cleanup end,
--       removed = function(instance) ... end,       -- optional
--   })
--
-- `added` may return a cleanup function that runs when the instance loses the
-- tag or is destroyed. Multiple handlers can bind the same tag independently.

local CollectionService = game:GetService("CollectionService")

-- returned by `added`; runs on tag-removed / instance-destroyed
export type Cleanup = () -> ()

export type Handler = ((instance: Instance) -> Cleanup?) | {
	added: (instance: Instance) -> Cleanup?,
	removed: ((instance: Instance) -> ())?,
}

local Tags = {}

-- marks an instance as bound but with no cleanup, so we never call `added` twice
local NOOP: Cleanup = function() end

-- Binds `handler` to `tag`. Returns an unbind function that detaches from every
-- currently-tagged instance and stops reacting to future ones.
function Tags.bind(tag: string, handler: Handler): () -> ()
	local added: (instance: Instance) -> Cleanup?
	local removed: ((instance: Instance) -> ())? = nil
	if type(handler) == "function" then
		added = handler
	else
		added = handler.added
		removed = handler.removed
	end

	local cleanups: { [Instance]: Cleanup } = {}

	local function apply(instance: Instance)
		-- GetTagged + the added signal can both surface the same instance; guard it
		if cleanups[instance] then
			return
		end
		cleanups[instance] = added(instance) or NOOP
	end

	local function unapply(instance: Instance)
		local cleanup = cleanups[instance]
		if not cleanup then
			return
		end
		cleanups[instance] = nil
		cleanup()
		if removed then
			removed(instance)
		end
	end

	for _, instance in CollectionService:GetTagged(tag) do
		apply(instance)
	end
	local addedConn = CollectionService:GetInstanceAddedSignal(tag):Connect(apply)
	-- fires on both tag removal and instance destruction, so it is the only teardown hook needed
	local removedConn = CollectionService:GetInstanceRemovedSignal(tag):Connect(unapply)

	return function()
		addedConn:Disconnect()
		removedConn:Disconnect()
		-- snapshot keys: unapply mutates `cleanups` as it goes
		local bound = {}
		for instance in cleanups do
			table.insert(bound, instance)
		end
		for _, instance in bound do
			unapply(instance)
		end
	end
end

return Tags
