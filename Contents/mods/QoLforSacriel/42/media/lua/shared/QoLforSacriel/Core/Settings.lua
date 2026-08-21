-- ff-assisted
local Settings = {}
local MOD_OPTIONS_ID = "QoLforSacriel.Modules"

local defaults = {
    QoLforSacriel_EnableMod = true,
    QoLforSacriel_DebugLogs = false,

    QoLforSacriel_EnableUIFixes = true,
    QoLforSacriel_UIFixes_EnableSkillFilter = true,
    QoLforSacriel_UIFixes_EnableExteriorVehicleHorn = true,
    QoLforSacriel_EnableForagingRefinement = true,
    QoLforSacriel_ForagingRefinement_EnableVisionTooltip = true,
    QoLforSacriel_ForagingRefinement_PinColorPreset = 1,
    QoLforSacriel_ForagingClothingPenaltyFix_Enabled = false,
    QoLforSacriel_EnableOrganizedInventory = true,
    QoLforSacriel_OrganizedInventory_ShowTooltipTags = true,
    QoLforSacriel_EnableDragDrop = true,
    QoLforSacriel_EnableRestSleep = true,
    QoLforSacriel_EnableEquipment = true,
    QoLforSacriel_EnableArmorMood = true,
    QoLforSacriel_EnableFurnitureNudge = true,
    QoLforSacriel_EnableLightSwitchToggle = true,
    QoLforSacriel_EnableNearbyDeviceOff = true,
    QoLforSacriel_EnableHeldBagClimb = true,
    QoLforSacriel_EnableVehicleEntryAssist = true,
    QoLforSacriel_EnableDrySelfDivisor = true,
    QoLforSacriel_DrySelf_WetnessPerUse = 12.5,

    QoLforSacriel_Equipment_EnablePresets = true,
    QoLforSacriel_Equipment_EnableMannequinMenu = true,

    QoLforSacriel_UIFixes_SkillFilterRecentMinutes = 60,
    QoLforSacriel_UIFixes_SkillFilterMinFullLevel = 2,
    QoLforSacriel_UIFixes_EnableWaterDepthHints = true,
    QoLforSacriel_UIFixes_EnableHeavyLoadHurtFeedback = true,
    QoLforSacriel_UIFixes_EnableFitnessNutritionIndicator = true,
    QoLforSacriel_UIFixes_ShowExactSleepStats = false,
    QoLforSacriel_UIFixes_EnableShowStats = true,
    QoLforSacriel_UIFixes_ShowBasicWeaponStats = false,
    QoLforSacriel_UIFixes_EnableCraftRecipeXp = true,
    QoLforSacriel_UIFixes_EnableCraftToolSubmenu = true,
    QoLforSacriel_UIFixes_EnableInventoryUpdate = true,
    QoLforSacriel_UIFixes_EnableGrabAllRotten = true,
    QoLforSacriel_UIFixes_EnableGrabAllStale = true,
    QoLforSacriel_UIFixes_EnableEatChainAll = true,
    QoLforSacriel_UIFixes_EnableEatUntilNotHungry = true,
    QoLforSacriel_UIFixes_EnableHeavyCraftDrop = true,
    QoLforSacriel_UIFixes_EnableWashAllBloodiestFirst = true,
    QoLforSacriel_UIFixes_EnableFishingNearbyLures = true,
    QoLforSacriel_UIFixes_EnableHeldItemPutInContainer = true,
    QoLforSacriel_UIFixes_EnableSoundDirection = false,
    QoLforSacriel_UIFixes_EnableNoiseRadius = false,
    QoLforSacriel_UIFixes_WaterDepthHints_OverlayRadius = 3,
    QoLforSacriel_UIFixes_WaterDepthHints_ShowLitersAboveForaging3 = true,
    QoLforSacriel_UIFixes_WaterDepthHints_ShallowMinWaterCount = 2,
    QoLforSacriel_UIFixes_WaterDepthHints_DeepMinWaterCount = 7,

    QoLforSacriel_SoundIntel_Enabled = true,
    QoLforSacriel_SoundIntel_UseAmbientCorrelation = true,
    QoLforSacriel_SoundIntel_ZMarkerEnabled = true,
    QoLforSacriel_SoundIntel_EnableInferredZombie = true,
    QoLforSacriel_SoundIntel_EnableInferredAnimal = true,
    QoLforSacriel_SoundIntel_ShowSourceLabel = true,
    QoLforSacriel_SoundIntel_ShowOutsideHearing = true,
    QoLforSacriel_SoundIntel_ArrowScalePercent = 100,
    QoLforSacriel_SoundIntel_ArrowScalePreset = 2,
    QoLforSacriel_SoundIntel_MaxTrackedCues = 32,
    QoLforSacriel_SoundIntel_CueDurationMs = 1400,
    QoLforSacriel_SoundRadius_Enabled = true,
    QoLforSacriel_SoundRadius_MaxActiveRings = 14,
    QoLforSacriel_SoundRadius_RingDurationMs = 1400,
    QoLforSacriel_SoundRadius_RingOpacityPercent = 25,
    QoLforSacriel_SoundRadius_RingCullingMarginPx = 128,
    QoLforSacriel_SoundRadius_ShowRadiusLabel = true,
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
    QoLforSacriel_Equipment_PresetName1 = "",
    QoLforSacriel_Equipment_PresetName2 = "",
    QoLforSacriel_Equipment_PresetName3 = "",
    QoLforSacriel_Equipment_PresetName4 = "",
    QoLforSacriel_Equipment_PresetName5 = "",
    QoLforSacriel_Equipment_PresetName6 = "",
    QoLforSacriel_Equipment_PresetName7 = "",
    QoLforSacriel_Equipment_PresetName8 = "",

    QoLforSacriel_FurnitureNudge_EnduranceScale = 0.25,
    QoLforSacriel_FurnitureNudge_EnduranceMin = 0.005,
    QoLforSacriel_FurnitureNudge_BlockOnFloorItems = false,
    QoLforSacriel_FurnitureNudge_BlockOnRugs = false,
    QoLforSacriel_FurnitureNudge_AllowMultiTile = true,
    QoLforSacriel_FurnitureNudge_IgnoreToolRequirements = true,

    QoLforSacriel_LightSwitchToggle_Hotkey = "F",
    QoLforSacriel_LightSwitchToggle_Range = 1,
    QoLforSacriel_LightSwitchToggle_RequireSameRoom = true,
    QoLforSacriel_NearbyDeviceOff_Hotkey = "G",
    QoLforSacriel_NearbyDeviceOff_Range = 3,

    QoLforSacriel_ArmorMood_BaseReductionFactor = 0.95,
    QoLforSacriel_ArmorMood_UpdateCooldownSeconds = 2,
}

local MOD_OPTION_KEY_BY_SETTING = {
    QoLforSacriel_EnableMod = "enableMod",
    QoLforSacriel_DebugLogs = "debugLogs",
    QoLforSacriel_EnableUIFixes = "enableUIFixes",
    QoLforSacriel_UIFixes_EnableSkillFilter = "enableSkillFilter",
    QoLforSacriel_UIFixes_EnableExteriorVehicleHorn = "enableExteriorVehicleHorn",
    QoLforSacriel_EnableForagingRefinement = "enableForagingRefinement",
    QoLforSacriel_ForagingRefinement_EnableVisionTooltip = "enableForagingVisionTooltip",
    QoLforSacriel_ForagingRefinement_PinColorPreset = "foragingRefinementPinColorPreset",
    QoLforSacriel_ForagingClothingPenaltyFix_Enabled = "enableForagingClothingPenaltyFix",
    QoLforSacriel_EnableOrganizedInventory = "enableOrganizedInventory",
    QoLforSacriel_OrganizedInventory_ShowTooltipTags = "showOrganizedInventoryTooltipTags",
    QoLforSacriel_UIFixes_SkillFilterRecentMinutes = "skillFilterRecentMinutes",
    QoLforSacriel_UIFixes_SkillFilterMinFullLevel = "skillFilterMinFullLevel",
    QoLforSacriel_UIFixes_EnableWaterDepthHints = "enableWaterDepthHints",
    QoLforSacriel_UIFixes_EnableHeavyLoadHurtFeedback = "enableHeavyLoadHurtFeedback",
    QoLforSacriel_UIFixes_EnableFitnessNutritionIndicator = "enableFitnessNutritionIndicator",
    QoLforSacriel_UIFixes_ShowExactSleepStats = "showExactSleepStats",
    QoLforSacriel_UIFixes_EnableShowStats = "enableShowStats",
    QoLforSacriel_UIFixes_ShowBasicWeaponStats = "showBasicWeaponStats",
    QoLforSacriel_UIFixes_EnableCraftRecipeXp = "enableCraftRecipeXp",
    QoLforSacriel_UIFixes_EnableCraftToolSubmenu = "enableCraftToolSubmenu",
    QoLforSacriel_UIFixes_EnableInventoryUpdate = "enableInventoryUpdate",
    QoLforSacriel_UIFixes_EnableGrabAllRotten = "enableGrabAllRotten",
    QoLforSacriel_UIFixes_EnableGrabAllStale = "enableGrabAllStale",
    QoLforSacriel_UIFixes_EnableEatChainAll = "enableEatChainAll",
    QoLforSacriel_UIFixes_EnableEatUntilNotHungry = "enableEatUntilNotHungry",
    QoLforSacriel_UIFixes_EnableHeavyCraftDrop = "enableHeavyCraftDrop",
    QoLforSacriel_UIFixes_EnableWashAllBloodiestFirst = "enableWashAllBloodiestFirst",
    QoLforSacriel_UIFixes_EnableFishingNearbyLures = "enableFishingNearbyLures",
    QoLforSacriel_UIFixes_EnableHeldItemPutInContainer = "enableHeldItemPutInContainer",
    QoLforSacriel_UIFixes_WaterDepthHints_OverlayRadius = "waterDepthOverlayRadius",
    QoLforSacriel_UIFixes_WaterDepthHints_ShowLitersAboveForaging3 = "waterDepthShowLitersAboveForaging3",
    QoLforSacriel_UIFixes_WaterDepthHints_ShallowMinWaterCount = "waterDepthShallowMinWaterCount",
    QoLforSacriel_UIFixes_WaterDepthHints_DeepMinWaterCount = "waterDepthDeepMinWaterCount",
    QoLforSacriel_UIFixes_EnableSoundDirection = "enableSoundDirection",
    QoLforSacriel_UIFixes_EnableNoiseRadius = "enableNoiseRadius",
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
    QoLforSacriel_Equipment_EnableMannequinMenu = "equipmentEnableMannequinMenu",
    QoLforSacriel_Equipment_PresetCount = "equipmentPresetCount",
    QoLforSacriel_Equipment_PresetName1 = "equipmentPresetName1",
    QoLforSacriel_Equipment_PresetName2 = "equipmentPresetName2",
    QoLforSacriel_Equipment_PresetName3 = "equipmentPresetName3",
    QoLforSacriel_Equipment_PresetName4 = "equipmentPresetName4",
    QoLforSacriel_Equipment_PresetName5 = "equipmentPresetName5",
    QoLforSacriel_Equipment_PresetName6 = "equipmentPresetName6",
    QoLforSacriel_Equipment_PresetName7 = "equipmentPresetName7",
    QoLforSacriel_Equipment_PresetName8 = "equipmentPresetName8",
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
    QoLforSacriel_EnableNearbyDeviceOff = "enableNearbyDeviceOff",
    QoLforSacriel_NearbyDeviceOff_Hotkey = "nearbyDeviceOffHotkey",
    QoLforSacriel_NearbyDeviceOff_Range = "nearbyDeviceOffRange",
    QoLforSacriel_EnableHeldBagClimb = "enableHeldBagClimb",
    QoLforSacriel_EnableVehicleEntryAssist = "enableVehicleEntryAssist",
    QoLforSacriel_EnableDrySelfDivisor = "enableDrySelfDivisor",
    QoLforSacriel_DrySelf_WetnessPerUse = "drySelfWetnessPerUse",
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
