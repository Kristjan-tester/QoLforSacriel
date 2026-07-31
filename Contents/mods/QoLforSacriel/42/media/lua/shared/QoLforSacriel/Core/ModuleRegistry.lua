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
        local enabled = settings.isEnabled(entry.enabledSetting)

        if enabled then
            local ok, err = pcall(function()
                entry.initFn(settings, logger)
            end)
            if ok then
                logger.info("Module enabled: " .. tostring(entry.id))
            else
                logger.error("Module failed: " .. tostring(entry.id) .. " | " .. tostring(err))
            end
        else
            logger.debug("Module disabled by setting: " .. tostring(entry.id))
        end
    end
end

return ModuleRegistry
