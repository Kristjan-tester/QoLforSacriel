local ModuleRegistry = {}

ModuleRegistry._entries = {}

function ModuleRegistry.register(id, enabledSetting, initFn)
    table.insert(ModuleRegistry._entries, {
        id = id,
        enabledSetting = enabledSetting,
        initFn = initFn,
    })
end

function ModuleRegistry.initAll(settings, logger)
    for i = 1, #ModuleRegistry._entries do
        local entry = ModuleRegistry._entries[i]
        local ok, err = pcall(function()
            entry.initFn(settings, logger)
        end)
        if ok then
            logger.info("Module ready: " .. tostring(entry.id))
        else
            logger.error("Module failed: " .. tostring(entry.id) .. " | " .. tostring(err))
        end
    end
end

return ModuleRegistry
