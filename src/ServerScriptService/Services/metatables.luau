local State = {}
State.__index = State

local rawDataMap = setmetatable({}, {__mode = "k"})
local listenerMap = setmetatable({}, {__mode = "k"})

function State.new(initialData)
    local rawData = initialData or {}
    local listeners = {}

    local proxy = setmetatable({}, {
        __index = function(t, k)
            if type(k) == "string" and k:sub(1,1) == "_" then
                return nil
            end
            if State[k] ~= nil then
                return State[k]
            end
            return rawData[k]
        end,

        __newindex = function(t, k, v)
            if type(k) == "string" and k:sub(1,1) == "_" then
                error('tentou mudar prop privada')
            end
            rawData[k] = v
            local oldValue = t[k]
            print('Mudou')
            for _, listener in ipairs(listeners) do
                listener(k, oldValue, v)
            end
        end,

        __add = function(t1, t2)
            local combinedData = {}
            for k, v in pairs(rawDataMap[t1] or {}) do
                combinedData[k] = v
            end
            for k, v in pairs(rawDataMap[t2] or {}) do
                combinedData[k] = (combinedData[k] or 0)
            end

            return State.new(combinedData)
        end,

        __tostring = function(t)
            local result = "State {"
            local first = true
            for k, v in pairs(rawDataMap[t] or {}) do
                if type(k) == "string" and k:sub(1,1) ~= "_" then
                    if not first then result = result .. ", " end
                    result = result .. k .. " = " .. tostring(v)
                    first = false
                end
            end
            return result .. "}"
        end
    })



    return proxy
end
