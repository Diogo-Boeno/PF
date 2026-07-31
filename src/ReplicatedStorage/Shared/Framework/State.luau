local Signal = require(script.Parent.Signal)

local State = {}
local _data = {}
local _signals = {}

local function getSignal(key: string)
    if not _signals[key] then
        _signals[key] = Signal.new()
    end
    return _signals[key]
end

function State.Set(key: string, value: any)
    local old = _data[key]
    if old == value then return end
    _data[key] = value
    getSignal(key):Fire(value, old)
end

function State.Get(key: string): any
    return _data[key]
end

function State.Update(key: string, fn: (current: any) -> any)
    State.Set(key, fn(_data[key]))
end

function State.OnChange(key: string, callback: (new: any, old: any) -> ())
    return getSignal(key):Connect(callback)
end

function State.Observe(key: string, callback: (new: any, old: any) -> ())
    if _data[key] ~= nil then
        task.spawn(callback, _data[key], nil)
    end
    return getSignal(key):Connect(callback)
end

function State.Remove(key: string)
    local old = _data[key]
    _data[key] = nil
    if _signals[key] then
        _signals[key]:Fire(nil, old)
    end
end

return State
