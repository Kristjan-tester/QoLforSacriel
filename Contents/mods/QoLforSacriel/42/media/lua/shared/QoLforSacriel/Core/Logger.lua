local Logger = {}

Logger.prefix = "[QoLforSacriel]"

local cachedSettings = nil

local function toStringSafe(v)
    if v == nil then
        return "nil"
    end
    return tostring(v)
end

function Logger._emit(level, msg)
    print(Logger.prefix .. "[" .. level .. "] " .. toStringSafe(msg))
end

function Logger.info(msg)
    Logger._emit("INFO", msg)
end

function Logger.warn(msg)
    Logger._emit("WARN", msg)
end

function Logger.error(msg)
    Logger._emit("ERROR", msg)
end

local function isDebugEnabled()
    if not cachedSettings then
        local ok, mod = pcall(require, "QoLforSacriel/Core/Settings")
        if ok then
            cachedSettings = mod
        end
    end

    if cachedSettings and cachedSettings.get then
        return cachedSettings.get("QoLforSacriel_DebugLogs") == true
    end

    return false
end

function Logger.debug(msg)
    if isDebugEnabled() then
        Logger._emit("DEBUG", msg)
    end
end

return Logger
