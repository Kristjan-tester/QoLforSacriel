local SoundSettingsProvider = {}
local MOD_OPTIONS_ID = "QoLforSacriel.SoundIntel"
local cached = nil

local DEFAULTS = {
    QoLforSacriel_SoundIntel_Enabled = false,
    QoLforSacriel_SoundIntel_UseAmbientCorrelation = true,
    QoLforSacriel_SoundIntel_ZMarkerEnabled = true,
    QoLforSacriel_SoundIntel_EnableInferredZombie = true,
    QoLforSacriel_SoundIntel_EnableInferredAnimal = true,
    QoLforSacriel_SoundIntel_ShowSourceLabel = true,
    QoLforSacriel_SoundIntel_ShowOutsideHearing = false,
    QoLforSacriel_SoundIntel_ArrowScalePercent = 100,
    QoLforSacriel_SoundIntel_ArrowScalePreset = 2,
    QoLforSacriel_SoundIntel_MaxTrackedCues = 24,
    QoLforSacriel_SoundIntel_CueDurationMs = 1400,
    QoLforSacriel_SoundIntel_Category_PlayerLocal = true,
    QoLforSacriel_SoundIntel_Category_Zombie = true,
    QoLforSacriel_SoundIntel_Category_Combat = true,
    QoLforSacriel_SoundIntel_Category_Environment = true,
    QoLforSacriel_SoundIntel_Category_Vehicle = true,
    QoLforSacriel_SoundIntel_Category_AlarmAndSignal = true,
    QoLforSacriel_SoundIntel_Category_Meta = true,
    QoLforSacriel_SoundIntel_Category_Unknown = true,
    QoLforSacriel_SoundIntel_Category_Inferred = true,
}

local MOD_OPTION_KEY_BY_SETTING = {
    QoLforSacriel_SoundIntel_Enabled = "enabled",
    QoLforSacriel_SoundIntel_UseAmbientCorrelation = "useAmbientCorrelation",
    QoLforSacriel_SoundIntel_ZMarkerEnabled = "zMarkerEnabled",
    QoLforSacriel_SoundIntel_EnableInferredZombie = "enableInferredZombie",
    QoLforSacriel_SoundIntel_EnableInferredAnimal = "enableInferredAnimal",
    QoLforSacriel_SoundIntel_ShowSourceLabel = "showSourceLabel",
    QoLforSacriel_SoundIntel_ShowOutsideHearing = "showOutsideHearing",
    QoLforSacriel_SoundIntel_ArrowScalePercent = "arrowScalePercent",
    QoLforSacriel_SoundIntel_ArrowScalePreset = "arrowScalePreset",
    QoLforSacriel_SoundIntel_MaxTrackedCues = "maxTrackedCues",
    QoLforSacriel_SoundIntel_CueDurationMs = "cueDurationMs",
    QoLforSacriel_SoundIntel_Category_PlayerLocal = "catPlayerLocal",
    QoLforSacriel_SoundIntel_Category_Zombie = "catZombie",
    QoLforSacriel_SoundIntel_Category_Combat = "catCombat",
    QoLforSacriel_SoundIntel_Category_Environment = "catEnvironment",
    QoLforSacriel_SoundIntel_Category_Vehicle = "catVehicle",
    QoLforSacriel_SoundIntel_Category_AlarmAndSignal = "catAlarmAndSignal",
    QoLforSacriel_SoundIntel_Category_Meta = "catMeta",
    QoLforSacriel_SoundIntel_Category_Unknown = "catUnknown",
    QoLforSacriel_SoundIntel_Category_Inferred = "catInferred",
}

local function clampInt(v, lo, hi)
    local n = tonumber(v)
    if not n then
        return lo
    end
    n = math.floor(n)
    if n < lo then
        return lo
    end
    if n > hi then
        return hi
    end
    return n
end

local function clampArrowScalePercent(v)
    return clampInt(v, 60, 180)
end

local function presetToPercent(v)
    local preset = clampInt(v, 1, 3)
    if preset <= 1 then
        return 85
    end
    if preset >= 3 then
        return 120
    end
    return 100
end

local function getModOptionValue(settingKey)
    if not PZAPI or not PZAPI.ModOptions or not PZAPI.ModOptions.getOptions then
        return nil
    end

    local options = PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)
    if not options or not options.getOption then
        return nil
    end

    local optionId = MOD_OPTION_KEY_BY_SETTING[settingKey]
    if not optionId then
        return nil
    end

    local opt = options:getOption(optionId)
    if not opt or not opt.getValue then
        return nil
    end

    local ok, value = pcall(function()
        return opt:getValue()
    end)
    if not ok then
        return nil
    end

    return value
end

local function resolveValue(settings, settingKey)
    local modOptionValue = getModOptionValue(settingKey)
    if modOptionValue ~= nil then
        return modOptionValue
    end

    local sandboxOrDefault = settings and settings.get and settings.get(settingKey)
    if sandboxOrDefault ~= nil then
        return sandboxOrDefault
    end

    return DEFAULTS[settingKey]
end

local function resolveSettings(settings)
    local out = {}

    out.enabled = resolveValue(settings, "QoLforSacriel_SoundIntel_Enabled") == true
    out.useAmbientCorrelation = resolveValue(settings, "QoLforSacriel_SoundIntel_UseAmbientCorrelation") == true
    out.zMarkerEnabled = resolveValue(settings, "QoLforSacriel_SoundIntel_ZMarkerEnabled") == true
    out.enableInferredZombie = resolveValue(settings, "QoLforSacriel_SoundIntel_EnableInferredZombie") == true
    out.enableInferredAnimal = resolveValue(settings, "QoLforSacriel_SoundIntel_EnableInferredAnimal") == true
    out.showSourceLabel = resolveValue(settings, "QoLforSacriel_SoundIntel_ShowSourceLabel") == true
    out.showOutsideHearing = resolveValue(settings, "QoLforSacriel_SoundIntel_ShowOutsideHearing") == true
    local scalePercent = resolveValue(settings, "QoLforSacriel_SoundIntel_ArrowScalePercent")
    if scalePercent == nil then
        scalePercent = presetToPercent(resolveValue(settings, "QoLforSacriel_SoundIntel_ArrowScalePreset"))
    end
    out.arrowScalePercent = clampArrowScalePercent(scalePercent)
    out.maxTrackedCues = clampInt(resolveValue(settings, "QoLforSacriel_SoundIntel_MaxTrackedCues"), 4, 128)
    out.cueDurationMs = clampInt(resolveValue(settings, "QoLforSacriel_SoundIntel_CueDurationMs"), 300, 5000)
    out.categoryPlayerLocal = resolveValue(settings, "QoLforSacriel_SoundIntel_Category_PlayerLocal") == true
    out.categoryZombie = resolveValue(settings, "QoLforSacriel_SoundIntel_Category_Zombie") == true
    out.categoryCombat = resolveValue(settings, "QoLforSacriel_SoundIntel_Category_Combat") == true
    out.categoryEnvironment = resolveValue(settings, "QoLforSacriel_SoundIntel_Category_Environment") == true
    out.categoryVehicle = resolveValue(settings, "QoLforSacriel_SoundIntel_Category_Vehicle") == true
    out.categoryAlarmAndSignal = resolveValue(settings, "QoLforSacriel_SoundIntel_Category_AlarmAndSignal") == true
    out.categoryMeta = resolveValue(settings, "QoLforSacriel_SoundIntel_Category_Meta") == true
    out.categoryUnknown = resolveValue(settings, "QoLforSacriel_SoundIntel_Category_Unknown") == true
    out.categoryInferred = resolveValue(settings, "QoLforSacriel_SoundIntel_Category_Inferred") == true

    return out
end

function SoundSettingsProvider.refresh(settings)
    cached = resolveSettings(settings)
    return cached
end

function SoundSettingsProvider.getCached(settings)
    if cached == nil then
        return SoundSettingsProvider.refresh(settings)
    end
    return cached
end

function SoundSettingsProvider.get(settings)
    return SoundSettingsProvider.getCached(settings)
end

return SoundSettingsProvider
