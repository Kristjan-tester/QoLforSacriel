local CoreModOptions = {}
local MOD_OPTIONS_ID = "QoLforSacriel.Modules"

local function registerBinding(bindingName, keyCode, shift, ctrl, alt)
    local core = getCore and getCore()
    if not core or not core.addKeyBinding then
        return
    end

    core:addKeyBinding(bindingName, keyCode, 0, shift == true, ctrl == true, alt == true)
end

local function syncPresetBindingFromOption(option, fallbackName, fallbackKey)
    if not option then
        registerBinding(fallbackName, fallbackKey, false, true, false)
        return
    end

    local bindingName = option.name or fallbackName
    local keyCode = tonumber(option.key) or fallbackKey
    local shift = option.shift == true
    local alt = option.alt == true

    local ctrl = option.ctrl
    if ctrl == nil then
        ctrl = true
    else
        ctrl = ctrl == true
    end

    registerBinding(bindingName, keyCode, shift, ctrl, alt)
end

local function syncPresetBindings(options)
    if not options or not options.getOption then
        return
    end

    syncPresetBindingFromOption(options:getOption("equipmentPresetHotkey1"), getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey1"), Keyboard.KEY_F1)
    syncPresetBindingFromOption(options:getOption("equipmentPresetHotkey2"), getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey2"), Keyboard.KEY_F2)
    syncPresetBindingFromOption(options:getOption("equipmentPresetHotkey3"), getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey3"), Keyboard.KEY_F3)
    syncPresetBindingFromOption(options:getOption("equipmentPresetHotkey4"), getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey4"), Keyboard.KEY_F4)
    syncPresetBindingFromOption(options:getOption("equipmentPresetHotkey5"), getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey5"), Keyboard.KEY_F5)
    syncPresetBindingFromOption(options:getOption("equipmentPresetHotkey6"), getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey6"), Keyboard.KEY_F6)
    syncPresetBindingFromOption(options:getOption("equipmentPresetHotkey7"), getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey7"), Keyboard.KEY_F7)
    syncPresetBindingFromOption(options:getOption("equipmentPresetHotkey8"), getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey8"), Keyboard.KEY_F8)
end

local function syncLightSwitchToggleBinding(options)
    if not options or not options.getOption then
        return
    end

    syncPresetBindingFromOption(options:getOption("lightSwitchToggleHotkey"), getText("UI_QoLforSacriel_Modules_LightSwitchToggleHotkey"), Keyboard.KEY_F)
end

function CoreModOptions.register(logger)
    if not PZAPI or not PZAPI.ModOptions or not PZAPI.ModOptions.create then
        if logger then
            logger.debug("Core ModOptions unavailable; using fallback settings")
        end
        return nil
    end

    local options = PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)
    if options then
        syncPresetBindings(options)
        syncLightSwitchToggleBinding(options)
        return options
    end

    options = PZAPI.ModOptions:create(MOD_OPTIONS_ID, "UI_QoLforSacriel_Modules_Title")

    options:addTitle("UI_QoLforSacriel_Modules_Title")
    options:addTickBox("enableMod", "UI_QoLforSacriel_Modules_EnableMod", true, "UI_QoLforSacriel_Modules_EnableMod_Tooltip")
    options:addTickBox("debugLogs", "UI_QoLforSacriel_Modules_DebugLogs", false, "UI_QoLforSacriel_Modules_DebugLogs_Tooltip")

    options:addSeparator()
    options:addTitle("UI_QoLforSacriel_Modules_UIFixesTitle")
    options:addTickBox("enableUIFixes", "UI_QoLforSacriel_Modules_EnableUIFixes", true, "UI_QoLforSacriel_Modules_EnableUIFixes_Tooltip")
    options:addTickBox("enableSkillFilter", "UI_QoLforSacriel_Modules_EnableSkillFilter", true, "UI_QoLforSacriel_Modules_EnableSkillFilter_Tooltip")
    options:addTickBox("skillFilterIncludePartialXP", "UI_QoLforSacriel_Modules_SkillFilterIncludePartialXP", true, "UI_QoLforSacriel_Modules_SkillFilterIncludePartialXP_Tooltip")
    options:addTickBox("enableWaterDepthHints", "UI_QoLforSacriel_Modules_EnableWaterDepthHints", true, "UI_QoLforSacriel_Modules_EnableWaterDepthHints_Tooltip")
    options:addTextEntry("waterDepthOverlayRadius", "UI_QoLforSacriel_Modules_WaterDepthOverlayRadius", "3", "UI_QoLforSacriel_Modules_WaterDepthOverlayRadius_Tooltip")
    options:addTickBox("enableSoundDirection", "UI_QoLforSacriel_Modules_EnableSoundDirection", true, "UI_QoLforSacriel_Modules_EnableSoundDirection_Tooltip")
    options:addDescription("UI_QoLforSacriel_Modules_SoundDirectionNote")

    options:addSeparator()
    options:addTitle("UI_QoLforSacriel_Modules_DragDropTitle")
    options:addTickBox("enableDragDrop", "UI_QoLforSacriel_Modules_EnableDragDrop", true, "UI_QoLforSacriel_Modules_EnableDragDrop_Tooltip")
    options:addTextEntry("dragDropFatigueStartMultiplier", "UI_QoLforSacriel_Modules_DragDropFatigueStartMultiplier", "0.35", "UI_QoLforSacriel_Modules_DragDropFatigueStartMultiplier_Tooltip")
    options:addTextEntry("dragDropFatigueMaxMultiplier", "UI_QoLforSacriel_Modules_DragDropFatigueMaxMultiplier", "1.00", "UI_QoLforSacriel_Modules_DragDropFatigueMaxMultiplier_Tooltip")
    options:addTextEntry("dragDropRampSeconds", "UI_QoLforSacriel_Modules_DragDropRampSeconds", "120", "UI_QoLforSacriel_Modules_DragDropRampSeconds_Tooltip")

    options:addSeparator()
    options:addTitle("UI_QoLforSacriel_Modules_RestSleepTitle")
    options:addTickBox("enableRestSleep", "UI_QoLforSacriel_Modules_EnableRestSleep", true, "UI_QoLforSacriel_Modules_EnableRestSleep_Tooltip")
    options:addTextEntry("restSleepSleepyThreshold", "UI_QoLforSacriel_Modules_RestSleepSleepyThreshold", "0.30", "UI_QoLforSacriel_Modules_RestSleepSleepyThreshold_Tooltip")
    options:addTickBox("restSleepInterruptOnMoveInput", "UI_QoLforSacriel_Modules_RestSleepInterruptOnMoveInput", true, "UI_QoLforSacriel_Modules_RestSleepInterruptOnMoveInput_Tooltip")
    options:addTickBox("restSleepInterruptOnPanic", "UI_QoLforSacriel_Modules_RestSleepInterruptOnPanic", true, "UI_QoLforSacriel_Modules_RestSleepInterruptOnPanic_Tooltip")
    options:addTextEntry("restSleepPanicInterruptLevel", "UI_QoLforSacriel_Modules_RestSleepPanicInterruptLevel", "50", "UI_QoLforSacriel_Modules_RestSleepPanicInterruptLevel_Tooltip")

    options:addSeparator()
    options:addTitle("UI_QoLforSacriel_Modules_EquipmentTitle")
    options:addTickBox("enableEquipment", "UI_QoLforSacriel_Modules_EnableEquipment", true, "UI_QoLforSacriel_Modules_EnableEquipment_Tooltip")
    options:addTickBox("equipmentEnablePresets", "UI_QoLforSacriel_Modules_EquipmentEnablePresets", true, "UI_QoLforSacriel_Modules_EquipmentEnablePresets_Tooltip")
    options:addTextEntry("equipmentPresetCount", "UI_QoLforSacriel_Modules_EquipmentPresetCount", "2", "UI_QoLforSacriel_Modules_EquipmentPresetCount_Tooltip")
    options:addTitle("UI_QoLforSacriel_Modules_EquipmentHotkeysTitle")
    options:addDescription("UI_QoLforSacriel_Modules_EquipmentHotkeysNote")
    local presetHotkey1Name = getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey1")
    local presetHotkey1 = options:addKeyBind("equipmentPresetHotkey1", presetHotkey1Name, Keyboard.KEY_F1, "UI_QoLforSacriel_Modules_EquipmentPresetHotkey_Tooltip")
    presetHotkey1.ctrl = true
    presetHotkey1.shift = false
    presetHotkey1.alt = false

    local presetHotkey2Name = getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey2")
    local presetHotkey2 = options:addKeyBind("equipmentPresetHotkey2", presetHotkey2Name, Keyboard.KEY_F2, "UI_QoLforSacriel_Modules_EquipmentPresetHotkey_Tooltip")
    presetHotkey2.ctrl = true
    presetHotkey2.shift = false
    presetHotkey2.alt = false

    local presetHotkey3Name = getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey3")
    local presetHotkey3 = options:addKeyBind("equipmentPresetHotkey3", presetHotkey3Name, Keyboard.KEY_F3, "UI_QoLforSacriel_Modules_EquipmentPresetHotkey_Tooltip")
    presetHotkey3.ctrl = true
    presetHotkey3.shift = false
    presetHotkey3.alt = false

    local presetHotkey4Name = getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey4")
    local presetHotkey4 = options:addKeyBind("equipmentPresetHotkey4", presetHotkey4Name, Keyboard.KEY_F4, "UI_QoLforSacriel_Modules_EquipmentPresetHotkey_Tooltip")
    presetHotkey4.ctrl = true
    presetHotkey4.shift = false
    presetHotkey4.alt = false

    local presetHotkey5Name = getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey5")
    local presetHotkey5 = options:addKeyBind("equipmentPresetHotkey5", presetHotkey5Name, Keyboard.KEY_F5, "UI_QoLforSacriel_Modules_EquipmentPresetHotkey_Tooltip")
    presetHotkey5.ctrl = true
    presetHotkey5.shift = false
    presetHotkey5.alt = false

    local presetHotkey6Name = getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey6")
    local presetHotkey6 = options:addKeyBind("equipmentPresetHotkey6", presetHotkey6Name, Keyboard.KEY_F6, "UI_QoLforSacriel_Modules_EquipmentPresetHotkey_Tooltip")
    presetHotkey6.ctrl = true
    presetHotkey6.shift = false
    presetHotkey6.alt = false

    local presetHotkey7Name = getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey7")
    local presetHotkey7 = options:addKeyBind("equipmentPresetHotkey7", presetHotkey7Name, Keyboard.KEY_F7, "UI_QoLforSacriel_Modules_EquipmentPresetHotkey_Tooltip")
    presetHotkey7.ctrl = true
    presetHotkey7.shift = false
    presetHotkey7.alt = false

    local presetHotkey8Name = getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey8")
    local presetHotkey8 = options:addKeyBind("equipmentPresetHotkey8", presetHotkey8Name, Keyboard.KEY_F8, "UI_QoLforSacriel_Modules_EquipmentPresetHotkey_Tooltip")
    presetHotkey8.ctrl = true
    presetHotkey8.shift = false
    presetHotkey8.alt = false

    options:addSeparator()
    options:addTitle("UI_QoLforSacriel_Modules_FurnitureNudgeTitle")
    options:addTickBox("enableFurnitureNudge", "UI_QoLforSacriel_Modules_EnableFurnitureNudge", true, "UI_QoLforSacriel_Modules_EnableFurnitureNudge_Tooltip")
    options:addTextEntry("furnitureNudgeEnduranceScale", "UI_QoLforSacriel_Modules_FurnitureNudgeEnduranceScale", "0.25", "UI_QoLforSacriel_Modules_FurnitureNudgeEnduranceScale_Tooltip")
    options:addTextEntry("furnitureNudgeEnduranceMin", "UI_QoLforSacriel_Modules_FurnitureNudgeEnduranceMin", "0.005", "UI_QoLforSacriel_Modules_FurnitureNudgeEnduranceMin_Tooltip")
    options:addTickBox("furnitureNudgeBlockOnFloorItems", "UI_QoLforSacriel_Modules_FurnitureNudgeBlockOnFloorItems", false, "UI_QoLforSacriel_Modules_FurnitureNudgeBlockOnFloorItems_Tooltip")
    options:addTickBox("furnitureNudgeBlockOnRugs", "UI_QoLforSacriel_Modules_FurnitureNudgeBlockOnRugs", false, "UI_QoLforSacriel_Modules_FurnitureNudgeBlockOnRugs_Tooltip")

    options:addSeparator()
    options:addTitle("UI_QoLforSacriel_Modules_LightSwitchToggleTitle")
    options:addTickBox("enableLightSwitchToggle", "UI_QoLforSacriel_Modules_EnableLightSwitchToggle", true, "UI_QoLforSacriel_Modules_EnableLightSwitchToggle_Tooltip")
    local lightSwitchToggleHotkeyName = getText("UI_QoLforSacriel_Modules_LightSwitchToggleHotkey")
    local lightSwitchToggleHotkey = options:addKeyBind("lightSwitchToggleHotkey", lightSwitchToggleHotkeyName, Keyboard.KEY_F, "UI_QoLforSacriel_Modules_LightSwitchToggleHotkey_Tooltip")
    lightSwitchToggleHotkey.ctrl = true
    lightSwitchToggleHotkey.shift = false
    lightSwitchToggleHotkey.alt = false
    options:addTextEntry("lightSwitchToggleRange", "UI_QoLforSacriel_Modules_LightSwitchToggleRange", "1", "UI_QoLforSacriel_Modules_LightSwitchToggleRange_Tooltip")
    options:addTickBox("lightSwitchToggleRequireSameRoom", "UI_QoLforSacriel_Modules_LightSwitchToggleRequireSameRoom", true, "UI_QoLforSacriel_Modules_LightSwitchToggleRequireSameRoom_Tooltip")

    options:addSeparator()
    options:addTitle("UI_QoLforSacriel_Modules_ArmorMoodTitle")
    options:addTickBox("enableArmorMood", "UI_QoLforSacriel_Modules_EnableArmorMood", true, "UI_QoLforSacriel_Modules_EnableArmorMood_Tooltip")
    options:addTextEntry("armorMoodBaseReductionFactor", "UI_QoLforSacriel_Modules_ArmorMoodBaseReductionFactor", "0.95", "UI_QoLforSacriel_Modules_ArmorMoodBaseReductionFactor_Tooltip")
    options:addTextEntry("armorMoodUpdateCooldownSeconds", "UI_QoLforSacriel_Modules_ArmorMoodUpdateCooldownSeconds", "2", "UI_QoLforSacriel_Modules_ArmorMoodUpdateCooldownSeconds_Tooltip")

    syncPresetBindings(options)
    syncLightSwitchToggleBinding(options)

    return options
end

return CoreModOptions
