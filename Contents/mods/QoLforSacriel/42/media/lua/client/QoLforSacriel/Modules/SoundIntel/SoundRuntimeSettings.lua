local SoundRuntimeSettings = {}

local coreModOptions = require "QoLforSacriel/CoreModOptions"

local cached = nil
local initialized = false
local settingsRef = nil
local loggerRef = nil

function SoundRuntimeSettings.refresh(settings, logger, logRefresh)
    settingsRef = settings or settingsRef
    loggerRef = logger or loggerRef
    if not settingsRef then
        return nil
    end

    cached = {
        enabled = settingsRef.isEnabled() == true,
        soundDirectionEnabled = settingsRef.get("QoLforSacriel_UIFixes_EnableSoundDirection") == true,
        soundRadiusEnabled = settingsRef.get("QoLforSacriel_UIFixes_EnableNoiseRadius") == true,
        debugEnabled = settingsRef.get("QoLforSacriel_DebugLogs") == true,
    }

    if logRefresh == true and loggerRef and cached.debugEnabled then
        loggerRef.debug("Sound runtime gates refreshed from Mod Options")
    end
    return cached
end

function SoundRuntimeSettings.getCached(settings, logger)
    if cached == nil then
        return SoundRuntimeSettings.refresh(settings, logger)
    end
    return cached
end

function SoundRuntimeSettings.init(settings, logger)
    settingsRef = settings or settingsRef
    loggerRef = logger or loggerRef
    if not initialized then
        coreModOptions.addApplyListener(function()
            SoundRuntimeSettings.refresh(settingsRef, loggerRef, true)
        end)
        initialized = true
    end
    return SoundRuntimeSettings.refresh(settingsRef, loggerRef)
end

return SoundRuntimeSettings