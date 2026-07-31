local Logger = {}

Logger.prefix = "[QoLforSacriel]"

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

function Logger.debug(msg)
    local vars = SandboxVars
    if vars and vars.QoLforSacriel_DebugLogs == true then
        Logger._emit("DEBUG", msg)
    end
end

return Logger
