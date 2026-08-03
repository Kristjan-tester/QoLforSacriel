local Settings = {}
local MOD_OPTIONS_ID = "QoLforSacriel.Modules"

local defaults = {
    QoLforSacriel_EnableMod = true,
    QoLforSacriel_DebugLogs = false,

    QoLforSacriel_EnableUIFixes = true,
    QoLforSacriel_UIFixes_EnableSkillFilter = true,
    QoLforSacriel_EnableDragDrop = true,
    QoLforSacriel_EnableRestSleep = true,
    QoLforSacriel_EnableEquipment = true,
    QoLforSacriel_EnableArmorMood = true,
    QoLforSacriel_EnableFurnitureNudge = true,
    QoLforSacriel_EnableLightSwitchToggle = true,

    QoLforSacriel_Equipment_EnablePresets = true,

    QoLforSacriel_UIFixes_SkillFilterIncludePartialXP = true,
    QoLforSacriel_UIFixes_EnableWaterDepthHints = true,
    QoLforSacriel_UIFixes_EnableHeavyLoadHurtFeedback = true,
    QoLforSacriel_UIFixes_EnableExactEquipmentStats = true,
    QoLforSacriel_UIFixes_EnableCraftOutputItemTooltip = true,
    QoLforSacriel_UIFixes_ShowAllEquipmentTooltipStats = true,
    QoLforSacriel_UIFixes_EnableSoundDirection = true,
    QoLforSacriel_UIFixes_WaterDepthHints_OverlayRadius = 3,
    QoLforSacriel_UIFixes_WaterDepthHints_ShowLitersAboveForaging3 = true,
    QoLforSacriel_UIFixes_WaterDepthHints_ShallowMinWaterCount = 2,
    QoLforSacriel_UIFixes_WaterDepthHints_DeepMinWaterCount = 7,

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

    QoLforSacriel_DragDrop_FatigueStartMultiplier = 0.35,
    QoLforSacriel_DragDrop_FatigueMaxMultiplier = 1.00,
    QoLforSacriel_DragDrop_RampSeconds = 120,

    QoLforSacriel_RestSleep_SleepyThreshold = 0.30,
    QoLforSacriel_RestSleep_InterruptOnMoveInput = true,
    QoLforSacriel_RestSleep_InterruptOnPanic = true,
    QoLforSacriel_RestSleep_PanicInterruptLevel = 50,

    QoLforSacriel_Equipment_PresetCount = 2,

    QoLforSacriel_FurnitureNudge_EnduranceScale = 0.25,
    QoLforSacriel_FurnitureNudge_EnduranceMin = 0.005,
    QoLforSacriel_FurnitureNudge_BlockOnFloorItems = false,
    QoLforSacriel_FurnitureNudge_BlockOnRugs = false,
    QoLforSacriel_FurnitureNudge_AllowMultiTile = true,
    QoLforSacriel_FurnitureNudge_IgnoreToolRequirements = true,

    QoLforSacriel_LightSwitchToggle_Hotkey = "F",
    QoLforSacriel_LightSwitchToggle_Range = 1,
    QoLforSacriel_LightSwitchToggle_RequireSameRoom = true,

    QoLforSacriel_ArmorMood_BaseReductionFactor = 0.95,
    QoLforSacriel_ArmorMood_UpdateCooldownSeconds = 2,
}

local MOD_OPTION_KEY_BY_SETTING = {
    QoLforSacriel_EnableMod = "enableMod",
    QoLforSacriel_DebugLogs = "debugLogs",
    QoLforSacriel_EnableUIFixes = "enableUIFixes",
    QoLforSacriel_UIFixes_EnableSkillFilter = "enableSkillFilter",
    QoLforSacriel_UIFixes_SkillFilterIncludePartialXP = "skillFilterIncludePartialXP",
    QoLforSacriel_UIFixes_EnableWaterDepthHints = "enableWaterDepthHints",
    QoLforSacriel_UIFixes_EnableHeavyLoadHurtFeedback = "enableHeavyLoadHurtFeedback",
    QoLforSacriel_UIFixes_EnableExactEquipmentStats = "enableExactEquipmentStats",
    QoLforSacriel_UIFixes_EnableCraftOutputItemTooltip = "enableCraftOutputItemTooltip",
    QoLforSacriel_UIFixes_ShowAllEquipmentTooltipStats = "showAllEquipmentTooltipStats",
    QoLforSacriel_UIFixes_WaterDepthHints_OverlayRadius = "waterDepthOverlayRadius",
    QoLforSacriel_UIFixes_WaterDepthHints_ShowLitersAboveForaging3 = "waterDepthShowLitersAboveForaging3",
    QoLforSacriel_UIFixes_WaterDepthHints_ShallowMinWaterCount = "waterDepthShallowMinWaterCount",
    QoLforSacriel_UIFixes_WaterDepthHints_DeepMinWaterCount = "waterDepthDeepMinWaterCount",
    QoLforSacriel_UIFixes_EnableSoundDirection = "enableSoundDirection",
    QoLforSacriel_EnableDragDrop = "enableDragDrop",
    QoLforSacriel_DragDrop_FatigueStartMultiplier = "dragDropFatigueStartMultiplier",
    QoLforSacriel_DragDrop_FatigueMaxMultiplier = "dragDropFatigueMaxMultiplier",
    QoLforSacriel_DragDrop_RampSeconds = "dragDropRampSeconds",
    QoLforSacriel_EnableRestSleep = "enableRestSleep",
    QoLforSacriel_RestSleep_SleepyThreshold = "restSleepSleepyThreshold",
    QoLforSacriel_RestSleep_InterruptOnMoveInput = "restSleepInterruptOnMoveInput",
    QoLforSacriel_RestSleep_InterruptOnPanic = "restSleepInterruptOnPanic",
    QoLforSacriel_RestSleep_PanicInterruptLevel = "restSleepPanicInterruptLevel",
    QoLforSacriel_EnableEquipment = "enableEquipment",
    QoLforSacriel_Equipment_EnablePresets = "equipmentEnablePresets",
    QoLforSacriel_Equipment_PresetCount = "equipmentPresetCount",
    QoLforSacriel_Equipment_PresetHotkey1 = "equipmentPresetHotkey1",
    QoLforSacriel_Equipment_PresetHotkey2 = "equipmentPresetHotkey2",
    QoLforSacriel_Equipment_PresetHotkey3 = "equipmentPresetHotkey3",
    QoLforSacriel_Equipment_PresetHotkey4 = "equipmentPresetHotkey4",
    QoLforSacriel_Equipment_PresetHotkey5 = "equipmentPresetHotkey5",
    QoLforSacriel_Equipment_PresetHotkey6 = "equipmentPresetHotkey6",
    QoLforSacriel_Equipment_PresetHotkey7 = "equipmentPresetHotkey7",
    QoLforSacriel_Equipment_PresetHotkey8 = "equipmentPresetHotkey8",
    QoLforSacriel_EnableFurnitureNudge = "enableFurnitureNudge",
    QoLforSacriel_FurnitureNudge_EnduranceScale = "furnitureNudgeEnduranceScale",
    QoLforSacriel_FurnitureNudge_EnduranceMin = "furnitureNudgeEnduranceMin",
    QoLforSacriel_FurnitureNudge_BlockOnFloorItems = "furnitureNudgeBlockOnFloorItems",
    QoLforSacriel_FurnitureNudge_BlockOnRugs = "furnitureNudgeBlockOnRugs",
    QoLforSacriel_FurnitureNudge_AllowMultiTile = "furnitureNudgeAllowMultiTile",
    QoLforSacriel_FurnitureNudge_IgnoreToolRequirements = "furnitureNudgeIgnoreToolRequirements",
    QoLforSacriel_EnableLightSwitchToggle = "enableLightSwitchToggle",
    QoLforSacriel_LightSwitchToggle_Hotkey = "lightSwitchToggleHotkey",
    QoLforSacriel_LightSwitchToggle_Range = "lightSwitchToggleRange",
    QoLforSacriel_LightSwitchToggle_RequireSameRoom = "lightSwitchToggleRequireSameRoom",
    QoLforSacriel_EnableArmorMood = "enableArmorMood",
    QoLforSacriel_ArmorMood_BaseReductionFactor = "armorMoodBaseReductionFactor",
    QoLforSacriel_ArmorMood_UpdateCooldownSeconds = "armorMoodUpdateCooldownSeconds",
}

local function getModOptionValue(name)
    if not PZAPI or not PZAPI.ModOptions or not PZAPI.ModOptions.getOptions then
        return nil
    end

    local options = PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)
    if not options or not options.getOption then
        return nil
    end

    local optionId = MOD_OPTION_KEY_BY_SETTING[name]
    if not optionId then
        return nil
    end

    local option = options:getOption(optionId)
    if not option or not option.getValue then
        return nil
    end

    local ok, value = pcall(function()
        return option:getValue()
    end)
    if not ok then
        return nil
    end

    return value
end

function Settings.get(name)
    local modOptionValue = getModOptionValue(name)
    if modOptionValue ~= nil then
        return modOptionValue
    end

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
