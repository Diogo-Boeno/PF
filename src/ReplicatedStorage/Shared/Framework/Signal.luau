local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection.new(signal, fn)
    return setmetatable({
        _signal = signal,
        _fn = fn,
        Connected = true,
    }, Connection)
end

function Connection:Disconnect()
    if not self.Connected then return end
    self.Connected = false
    local index = table.find(self._signal._connections, self)
    if index then
        table.remove(self._signal._connections, index)
    end
end

function Signal.new()
    return setmetatable({
        _connections = {},
    }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
    local connection = Connection.new(self, fn)
    table.insert(self._connections, connection)
    return connection
end

function Signal:Once(fn: (...any) -> ())
    local connection
    connection = self:Connect(function(...)
        connection:Disconnect()
        fn(...)
    end)
    return connection
end

function Signal:Fire(...)
    for _, connection in self._connections do
        if connection.Connected then
            task.spawn(connection._fn, ...)
        end
    end
end

function Signal:Wait()
    local thread = coroutine.running()
    self:Once(function(...)
        task.spawn(thread, ...)
    end)
    return coroutine.yield()
end

function Signal:Destroy()
    for _, connection in self._connections do
        connection.Connected = false
    end
    self._connections = {}
end

return Signal
