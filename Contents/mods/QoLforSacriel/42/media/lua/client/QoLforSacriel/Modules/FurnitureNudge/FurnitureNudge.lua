local FurnitureNudge = {}

local installed = false

local function safeRequire(path, logger)
    local ok, mod = pcall(require, path)
    if not ok then
        if logger then
            logger.error("FurnitureNudge require failed: " .. tostring(path) .. " | " .. tostring(mod))
        end
        return nil
    end
    if mod == nil then
        if logger then
            logger.error("FurnitureNudge require returned nil: " .. tostring(path))
        end
        return nil
    end
    return mod
end

function FurnitureNudge.init(settings, logger)
    if installed then
        if logger then
            logger.debug("FurnitureNudge already installed")
        end
        return
    end

    local contextModule = safeRequire("QoLforSacriel/Modules/FurnitureNudge/FurnitureNudgeContext", logger)
    if contextModule and contextModule.install then
        contextModule.install(settings, logger)
    end

    installed = true
end

return FurnitureNudge