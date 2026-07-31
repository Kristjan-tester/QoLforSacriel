local Settings = {}

local defaults = {
    QoLforSacriel_EnableMod = true,
    QoLforSacriel_DebugLogs = false,

    QoLforSacriel_EnableUIFixes = true,
    QoLforSacriel_EnableDragDrop = true,
    QoLforSacriel_EnableRestSleep = true,
    QoLforSacriel_EnableEquipment = true,
    QoLforSacriel_EnableArmorMood = true,

    QoLforSacriel_Equipment_EnablePresets = true,

    QoLforSacriel_UIFixes_SkillFilterIncludePartialXP = true,
    QoLforSacriel_UIFixes_EnableWaterDepthHints = true,
    QoLforSacriel_UIFixes_WaterDepthHints_OverlayRadius = 3,
    QoLforSacriel_UIFixes_WaterDepthHints_ShallowMinWaterCount = 2,
    QoLforSacriel_UIFixes_WaterDepthHints_MediumMinWaterCount = 4,
    QoLforSacriel_UIFixes_WaterDepthHints_DeepMinWaterCount = 7,

    QoLforSacriel_DragDrop_FatigueStartMultiplier = 0.35,
    QoLforSacriel_DragDrop_FatigueMaxMultiplier = 1.00,
    QoLforSacriel_DragDrop_RampSeconds = 90,

    QoLforSacriel_RestSleep_SleepyThreshold = 0.30,
    QoLforSacriel_RestSleep_InterruptOnMoveInput = true,
    QoLforSacriel_RestSleep_InterruptOnPanic = true,
    QoLforSacriel_RestSleep_PanicInterruptLevel = 50,

    QoLforSacriel_Equipment_PresetCount = 3,

    QoLforSacriel_ArmorMood_BaseReductionFactor = 0.60,
    QoLforSacriel_ArmorMood_UpdateCooldownSeconds = 2,
}

function Settings.get(name)
    local vars = SandboxVars
    if vars ~= nil and vars[name] ~= nil then
        return vars[name]
    end
    return defaults[name]
end

function Settings.getAll()
    return defaults
end

function Settings.isEnabled(key)
    if Settings.get("QoLforSacriel_EnableMod") ~= true then
        return false
    end
    if key == nil then
        return true
    end
    return Settings.get(key) == true
end

return Settings
