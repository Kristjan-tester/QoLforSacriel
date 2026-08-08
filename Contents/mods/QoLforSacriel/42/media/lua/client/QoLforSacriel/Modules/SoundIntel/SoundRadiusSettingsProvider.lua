local SoundRadiusSettingsProvider = {}
local MOD_OPTIONS_ID = "QoLforSacriel.SoundRadius"

local DEFAULTS = {
    QoLforSacriel_SoundRadius_Enabled = false,
    QoLforSacriel_SoundRadius_MaxActiveRings = 6,
    QoLforSacriel_SoundRadius_RingDurationMs = 1400,
    QoLforSacriel_SoundRadius_RingOpacityPercent = 25,
    QoLforSacriel_SoundRadius_RingCullingMarginPx = 128,
    QoLforSacriel_SoundRadius_ShowRadiusLabel = true,
}

local OPTION_KEYS = {
    QoLforSacriel_SoundRadius_Enabled = "enabled",
    QoLforSacriel_SoundRadius_MaxActiveRings = "maxActiveRings",
    QoLforSacriel_SoundRadius_RingDurationMs = "ringDurationMs",
    QoLforSacriel_SoundRadius_RingOpacityPercent = "ringOpacityPercent",
    QoLforSacriel_SoundRadius_RingCullingMarginPx = "ringCullingMarginPx",
    QoLforSacriel_SoundRadius_ShowRadiusLabel = "showRadiusLabel",
}

local function clamp(value, low, high)
    local number = math.floor(tonumber(value) or low)
    return math.max(low, math.min(high, number))
end

local function resolve(settings, setting)
    local optionId = OPTION_KEYS[setting]
    local options = PZAPI and PZAPI.ModOptions and PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)
    local option = options and options:getOption(optionId)
    if option and option.getValue then
        local ok, value = pcall(function() return option:getValue() end)
        if ok and value ~= nil then return value end
    end
    return settings.get(setting) ~= nil and settings.get(setting) or DEFAULTS[setting]
end

function SoundRadiusSettingsProvider.get(settings)
    local enabled = resolve(settings, "QoLforSacriel_SoundRadius_Enabled") == true
    return {
        enabled = enabled,
        playerWorldSoundRingsEnabled = enabled,
        maxActiveRings = clamp(resolve(settings, "QoLforSacriel_SoundRadius_MaxActiveRings"), 1, 24),
        ringDurationMs = clamp(resolve(settings, "QoLforSacriel_SoundRadius_RingDurationMs"), 300, 5000),
        playerWorldSoundRingOpacityPercent = clamp(resolve(settings, "QoLforSacriel_SoundRadius_RingOpacityPercent"), 5, 80),
        playerWorldSoundRingCullingMarginPx = clamp(resolve(settings, "QoLforSacriel_SoundRadius_RingCullingMarginPx"), 0, 1024),
        showPlayerWorldSoundRadiusLabel = resolve(settings, "QoLforSacriel_SoundRadius_ShowRadiusLabel") == true,
    }
end

return SoundRadiusSettingsProvider