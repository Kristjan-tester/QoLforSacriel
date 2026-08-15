-- ff-assisted
local CoreModOptions = {}
local MOD_OPTIONS_ID = "QoLforSacriel.Modules"
local HOTKEY_NONE_TOKEN = "NONE"
local applyListeners = {}

local FKEY_TO_CODE = {
    F1 = Keyboard.KEY_F1,
    F2 = Keyboard.KEY_F2,
    F3 = Keyboard.KEY_F3,
    F4 = Keyboard.KEY_F4,
    F5 = Keyboard.KEY_F5,
    F6 = Keyboard.KEY_F6,
    F7 = Keyboard.KEY_F7,
    F8 = Keyboard.KEY_F8,
    F9 = Keyboard.KEY_F9,
    F10 = Keyboard.KEY_F10,
    F11 = Keyboard.KEY_F11,
    F12 = Keyboard.KEY_F12,
}

local ALPHA_TO_CODE = {
    A = Keyboard.KEY_A, B = Keyboard.KEY_B, C = Keyboard.KEY_C, D = Keyboard.KEY_D,
    E = Keyboard.KEY_E, F = Keyboard.KEY_F, G = Keyboard.KEY_G, H = Keyboard.KEY_H,
    I = Keyboard.KEY_I, J = Keyboard.KEY_J, K = Keyboard.KEY_K, L = Keyboard.KEY_L,
    M = Keyboard.KEY_M, N = Keyboard.KEY_N, O = Keyboard.KEY_O, P = Keyboard.KEY_P,
    Q = Keyboard.KEY_Q, R = Keyboard.KEY_R, S = Keyboard.KEY_S, T = Keyboard.KEY_T,
    U = Keyboard.KEY_U, V = Keyboard.KEY_V, W = Keyboard.KEY_W, X = Keyboard.KEY_X,
    Y = Keyboard.KEY_Y, Z = Keyboard.KEY_Z,
}

local DIGIT_TO_CODE = {
    ["0"] = Keyboard.KEY_0,
    ["1"] = Keyboard.KEY_1,
    ["2"] = Keyboard.KEY_2,
    ["3"] = Keyboard.KEY_3,
    ["4"] = Keyboard.KEY_4,
    ["5"] = Keyboard.KEY_5,
    ["6"] = Keyboard.KEY_6,
    ["7"] = Keyboard.KEY_7,
    ["8"] = Keyboard.KEY_8,
    ["9"] = Keyboard.KEY_9,
}

local NUMPAD_TO_CODE = {
    NUMPAD0 = Keyboard.KEY_NUMPAD0,
    NUMPAD1 = Keyboard.KEY_NUMPAD1,
    NUMPAD2 = Keyboard.KEY_NUMPAD2,
    NUMPAD3 = Keyboard.KEY_NUMPAD3,
    NUMPAD4 = Keyboard.KEY_NUMPAD4,
    NUMPAD5 = Keyboard.KEY_NUMPAD5,
    NUMPAD6 = Keyboard.KEY_NUMPAD6,
    NUMPAD7 = Keyboard.KEY_NUMPAD7,
    NUMPAD8 = Keyboard.KEY_NUMPAD8,
    NUMPAD9 = Keyboard.KEY_NUMPAD9,
}

local EXTRA_TOKEN_TO_CODE = {
    MINUS = Keyboard.KEY_MINUS,
    EQUALS = Keyboard.KEY_EQUALS,
    COMMA = Keyboard.KEY_COMMA,
    PERIOD = Keyboard.KEY_PERIOD,
    SLASH = Keyboard.KEY_SLASH,
    SEMICOLON = Keyboard.KEY_SEMICOLON,
    APOSTROPHE = Keyboard.KEY_APOSTROPHE,
    LBRACKET = Keyboard.KEY_LBRACKET,
    RBRACKET = Keyboard.KEY_RBRACKET,
    BACKSLASH = Keyboard.KEY_BACKSLASH,
    GRAVE = Keyboard.KEY_GRAVE,
    SPACE = Keyboard.KEY_SPACE,
    TAB = Keyboard.KEY_TAB,
}

local function normalizeBindingToken(value)
    local token = tostring(value or "")
    token = token:gsub("^%s+", "")
    token = token:gsub("%s+$", "")
    if token == "" then
        return nil
    end

    token = string.upper(token):gsub("%s+", "")
    if token:sub(1, 4) == "KEY_" then
        token = token:sub(5)
    end
    if token == "UNBOUND" then
        token = HOTKEY_NONE_TOKEN
    end
    return token
end

local function resolveKeyCodeFromToken(token)
    local normalized = normalizeBindingToken(token)
    if not normalized or normalized == HOTKEY_NONE_TOKEN then
        return nil
    end

    local keyCode = FKEY_TO_CODE[normalized]
    if keyCode then
        return keyCode
    end

    keyCode = ALPHA_TO_CODE[normalized]
    if keyCode then
        return keyCode
    end

    keyCode = DIGIT_TO_CODE[normalized]
    if keyCode then
        return keyCode
    end

    keyCode = NUMPAD_TO_CODE[normalized]
    if keyCode then
        return keyCode
    end

    return EXTRA_TOKEN_TO_CODE[normalized]
end

local function registerBinding(bindingName, keyCode, shift, ctrl, alt)
    local core = getCore and getCore()
    if not core or not core.addKeyBinding then
        return
    end

    core:addKeyBinding(bindingName, keyCode, 0, shift == true, ctrl == true, alt == true)
end

local function getKeybindStateSource(option)
    if option and type(option.element) == "table" then
        return option.element
    end
    return option
end

local function readModifierFlag(option, state, key)
    local value = nil
    if state then
        value = state[key]
    end
    if value == nil and option then
        value = option[key]
    end
    return value == true
end

local function writeResolvedBindingState(option, keyCode, shift, ctrl, alt)
    if not option then
        return
    end

    option.key = keyCode
    option.shift = shift
    option.ctrl = ctrl
    option.alt = alt

    if type(option.element) == "table" then
        option.element.keyCode = keyCode
        option.element.shift = shift
        option.element.ctrl = ctrl
        option.element.alt = alt
    end
end

local function syncPresetBindingFromOption(optionId, option, fallbackName, fallbackKey, logger)
    if not option then
        if logger and logger.debug then
            logger.debug("Keybind sync [" .. tostring(optionId) .. "]: option missing; fallback binding name='" .. tostring(fallbackName) .. "', key=" .. tostring(fallbackKey) .. ", shift=false, ctrl=true, alt=false")
        end
        registerBinding(fallbackName, fallbackKey, false, true, false)
        return
    end

    local bindingName = option.name or fallbackName
    local keyCode = fallbackKey
    local useDefaultModifiers = false
    local state = getKeybindStateSource(option)
    local keyToken = state and state.keyCode or option.key
    local normalizedToken = normalizeBindingToken(keyToken)
    local numericKey = tonumber(keyToken)

    if numericKey ~= nil then
        keyCode = math.floor(numericKey)
        if keyCode <= 0 then
            keyCode = 0
        end
    else
        if normalizedToken == nil then
            keyCode = fallbackKey
            useDefaultModifiers = true
        elseif normalizedToken == HOTKEY_NONE_TOKEN then
            keyCode = 0
        elseif normalizedToken == "DEFAULT" then
            keyCode = fallbackKey
            useDefaultModifiers = true
        else
            local resolvedCode = resolveKeyCodeFromToken(normalizedToken)
            if resolvedCode then
                keyCode = resolvedCode
            else
                keyCode = 0
                if logger and logger.debug then
                    logger.debug("ModOptions keybind token unresolved for '" .. tostring(bindingName) .. "': " .. tostring(normalizedToken) .. " (treated as unbound)")
                end
            end
        end
    end

    local shift = readModifierFlag(option, state, "shift")
    local alt = readModifierFlag(option, state, "alt")
    local ctrl = readModifierFlag(option, state, "ctrl")

    if keyCode <= 0 then
        keyToken = 0
        ctrl = false
        shift = false
        alt = false
    elseif useDefaultModifiers then
        ctrl = true
        shift = false
        alt = false
    end

    writeResolvedBindingState(option, keyCode, shift, ctrl, alt)

    if logger and logger.debug then
        logger.debug(
            "Keybind sync [" .. tostring(optionId) .. "]"
            .. ": name='" .. tostring(bindingName) .. "'"
            .. ", rawKey=" .. tostring(keyToken)
            .. ", normalized=" .. tostring(normalizedToken)
            .. ", rawShift=" .. tostring(state and state.shift or option.shift)
            .. ", rawCtrl=" .. tostring(state and state.ctrl or option.ctrl)
            .. ", rawAlt=" .. tostring(state and state.alt or option.alt)
            .. ", resolvedKey=" .. tostring(keyCode)
            .. ", resolvedShift=" .. tostring(shift)
            .. ", resolvedCtrl=" .. tostring(ctrl)
            .. ", resolvedAlt=" .. tostring(alt)
            .. ", defaultMods=" .. tostring(useDefaultModifiers)
        )
    end

    registerBinding(bindingName, keyCode, shift, ctrl, alt)
end

local function syncPresetBindings(options, logger)
    if not options or not options.getOption then
        return
    end

    syncPresetBindingFromOption("equipmentPresetHotkey1", options:getOption("equipmentPresetHotkey1"), getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey1"), Keyboard.KEY_F1, logger)
    syncPresetBindingFromOption("equipmentPresetHotkey2", options:getOption("equipmentPresetHotkey2"), getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey2"), Keyboard.KEY_F2, logger)
    syncPresetBindingFromOption("equipmentPresetHotkey3", options:getOption("equipmentPresetHotkey3"), getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey3"), Keyboard.KEY_F3, logger)
    syncPresetBindingFromOption("equipmentPresetHotkey4", options:getOption("equipmentPresetHotkey4"), getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey4"), Keyboard.KEY_F4, logger)
    syncPresetBindingFromOption("equipmentPresetHotkey5", options:getOption("equipmentPresetHotkey5"), getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey5"), Keyboard.KEY_F5, logger)
    syncPresetBindingFromOption("equipmentPresetHotkey6", options:getOption("equipmentPresetHotkey6"), getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey6"), Keyboard.KEY_F6, logger)
    syncPresetBindingFromOption("equipmentPresetHotkey7", options:getOption("equipmentPresetHotkey7"), getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey7"), Keyboard.KEY_F7, logger)
    syncPresetBindingFromOption("equipmentPresetHotkey8", options:getOption("equipmentPresetHotkey8"), getText("UI_QoLforSacriel_Modules_EquipmentPresetHotkey8"), Keyboard.KEY_F8, logger)
end

local function syncLightSwitchToggleBinding(options, logger)
    if not options or not options.getOption then
        return
    end

    syncPresetBindingFromOption("lightSwitchToggleHotkey", options:getOption("lightSwitchToggleHotkey"), getText("UI_QoLforSacriel_Modules_LightSwitchToggleHotkey"), Keyboard.KEY_F, logger)
end

local function syncNearbyDeviceOffBinding(options, logger)
    if not options or not options.getOption then
        return
    end

    syncPresetBindingFromOption("nearbyDeviceOffHotkey", options:getOption("nearbyDeviceOffHotkey"), getText("UI_QoLforSacriel_Modules_NearbyDeviceOffHotkey"), Keyboard.KEY_G, logger)
end

local function syncAllBindings(options, logger)
    syncPresetBindings(options, logger)
    syncLightSwitchToggleBinding(options, logger)
    syncNearbyDeviceOffBinding(options, logger)
end

local function notifyApplyListeners()
    for index = 1, #applyListeners do
        applyListeners[index]()
    end
end

local function attachApplySync(options, logger)
    if not options or options._qolApplySyncAttached == true then
        return
    end

    local previousApply = options.apply
    options.apply = function(self)
        if previousApply then
            previousApply(self)
        end
        syncAllBindings(self, logger)
        notifyApplyListeners()
    end

    options._qolApplySyncAttached = true
end

function CoreModOptions.addApplyListener(listener)
    if type(listener) == "function" then
        table.insert(applyListeners, listener)
    end
end

function CoreModOptions.syncKeybinds(logger)
    if not PZAPI or not PZAPI.ModOptions or not PZAPI.ModOptions.getOptions then
        return nil
    end

    local options = PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)
    if not options then
        return nil
    end

    attachApplySync(options, logger)
    syncAllBindings(options, logger)
    return options
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
        attachApplySync(options, logger)
        syncAllBindings(options, logger)
        return options
    end

    options = PZAPI.ModOptions:create(MOD_OPTIONS_ID, "UI_QoLforSacriel_Modules_Title")

    options:addTitle("UI_QoLforSacriel_Modules_Title")
    options:addTickBox("enableMod", "UI_QoLforSacriel_Modules_EnableMod", true, "UI_QoLforSacriel_Modules_EnableMod_Tooltip")
    options:addTickBox("debugLogs", "UI_QoLforSacriel_Modules_DebugLogs", false, "UI_QoLforSacriel_Modules_DebugLogs_Tooltip")
    options:addTickBox("enableSoundDirection", "UI_QoLforSacriel_Modules_EnableSoundDirection", true, "UI_QoLforSacriel_Modules_EnableSoundDirection_Tooltip")
    options:addDescription("UI_QoLforSacriel_Modules_SoundDirectionNote")
    options:addTickBox("enableNoiseRadius", "UI_QoLforSacriel_Modules_EnableNoiseRadius", true, "UI_QoLforSacriel_Modules_EnableNoiseRadius_Tooltip")
    options:addDescription("UI_QoLforSacriel_Modules_NoiseRadiusNote")

    options:addSeparator()
    options:addTitle("UI_QoLforSacriel_Modules_UIFixesTitle")
    options:addTickBox("enableUIFixes", "UI_QoLforSacriel_Modules_EnableUIFixes", true, "UI_QoLforSacriel_Modules_EnableUIFixes_Tooltip")
    options:addTickBox("enableSkillFilter", "UI_QoLforSacriel_Modules_EnableSkillFilter", true, "UI_QoLforSacriel_Modules_EnableSkillFilter_Tooltip")
    options:addTickBox("enableExteriorVehicleHorn", "UI_QoLforSacriel_Modules_EnableExteriorVehicleHorn", true, "UI_QoLforSacriel_Modules_EnableExteriorVehicleHorn_Tooltip")
    options:addTextEntry("skillFilterRecentMinutes", "UI_QoLforSacriel_Modules_SkillFilterRecentMinutes", "60", "UI_QoLforSacriel_Modules_SkillFilterRecentMinutes_Tooltip")
    options:addTextEntry("skillFilterMinFullLevel", "UI_QoLforSacriel_Modules_SkillFilterMinFullLevel", "1", "UI_QoLforSacriel_Modules_SkillFilterMinFullLevel_Tooltip")
    options:addTickBox("enableHeavyLoadHurtFeedback", "UI_QoLforSacriel_Modules_EnableHeavyLoadHurtFeedback", true, "UI_QoLforSacriel_Modules_EnableHeavyLoadHurtFeedback_Tooltip")
    options:addTickBox("enableFitnessNutritionIndicator", "UI_QoLforSacriel_Modules_EnableFitnessNutritionIndicator", true, "UI_QoLforSacriel_Modules_EnableFitnessNutritionIndicator_Tooltip")
    options:addTickBox("enableShowStats", "UI_QoLforSacriel_Modules_EnableShowStats", true, "UI_QoLforSacriel_Modules_EnableShowStats_Tooltip")
    options:addTickBox("showBasicWeaponStats", "UI_QoLforSacriel_Modules_ShowBasicWeaponStats", false, "UI_QoLforSacriel_Modules_ShowBasicWeaponStats_Tooltip")
    options:addTickBox("enableCraftRecipeXp", "UI_QoLforSacriel_Modules_EnableCraftRecipeXp", true, "UI_QoLforSacriel_Modules_EnableCraftRecipeXp_Tooltip")
    options:addTickBox("enableCraftToolSubmenu", "UI_QoLforSacriel_Modules_EnableCraftToolSubmenu", true, "UI_QoLforSacriel_Modules_EnableCraftToolSubmenu_Tooltip")
    options:addTickBox("enableInventoryUpdate", "UI_QoLforSacriel_Modules_EnableInventoryUpdate", true, "UI_QoLforSacriel_Modules_EnableInventoryUpdate_Tooltip")
    options:addTickBox("enableGrabAllRotten", "UI_QoLforSacriel_Modules_EnableGrabAllRotten", true, "UI_QoLforSacriel_Modules_EnableGrabAllRotten_Tooltip")
    options:addTickBox("enableGrabAllStale", "UI_QoLforSacriel_Modules_EnableGrabAllStale", true, "UI_QoLforSacriel_Modules_EnableGrabAllStale_Tooltip")
    options:addTickBox("enableEatChainAll", "UI_QoLforSacriel_Modules_EnableEatChainAll", true, "UI_QoLforSacriel_Modules_EnableEatChainAll_Tooltip")
    options:addTickBox("enableEatUntilNotHungry", "UI_QoLforSacriel_Modules_EnableEatUntilNotHungry", true, "UI_QoLforSacriel_Modules_EnableEatUntilNotHungry_Tooltip")
    options:addTickBox("enableHeavyCraftDrop", "UI_QoLforSacriel_Modules_EnableHeavyCraftDrop", false, "UI_QoLforSacriel_Modules_EnableHeavyCraftDrop_Tooltip")
    options:addTickBox("enableWashAllBloodiestFirst", "UI_QoLforSacriel_Modules_EnableWashAllBloodiestFirst", true, "UI_QoLforSacriel_Modules_EnableWashAllBloodiestFirst_Tooltip")
    options:addTickBox("enableFishingNearbyLures", "UI_QoLforSacriel_Modules_EnableFishingNearbyLures", true, "UI_QoLforSacriel_Modules_EnableFishingNearbyLures_Tooltip")
    options:addTickBox("enableHeldItemPutInContainer", "UI_QoLforSacriel_Modules_EnableHeldItemPutInContainer", true, "UI_QoLforSacriel_Modules_EnableHeldItemPutInContainer_Tooltip")
    options:addTickBox("enableWaterDepthHints", "UI_QoLforSacriel_Modules_EnableWaterDepthHints", true, "UI_QoLforSacriel_Modules_EnableWaterDepthHints_Tooltip")
    options:addTickBox("waterDepthShowLitersAboveForaging3", "UI_QoLforSacriel_Modules_WaterDepthShowLitersAboveForaging3", true, "UI_QoLforSacriel_Modules_WaterDepthShowLitersAboveForaging3_Tooltip")
    
    local waterDepthOverlayRadiusOption = options:addComboBox("waterDepthOverlayRadius", "UI_QoLforSacriel_Modules_WaterDepthOverlayRadius", "UI_QoLforSacriel_Modules_WaterDepthOverlayRadius_Tooltip")
    for i = 1, 6 do
        waterDepthOverlayRadiusOption:addItem("UI_QoLforSacriel_Modules_WaterDepthOverlayRadius_" .. tostring(i), i == 3)
    end

    local getWaterDepthOverlayRadiusOptionValue = waterDepthOverlayRadiusOption.getValue
    waterDepthOverlayRadiusOption.getValue = function(self)
        -- Backwards compatibility: migrate legacy text-entry saves into combo index.
        local legacyValue = tonumber(self.value)
        if legacyValue and self.selected == 3 and legacyValue >= 1 and legacyValue <= #self.values then
            self.selected = legacyValue
            if self.element ~= nil then
                self.element.selected = legacyValue
            end
            self.value = nil
        end
        return getWaterDepthOverlayRadiusOptionValue(self)
    end

    options:addTextEntry("waterDepthShallowMinWaterCount", "UI_QoLforSacriel_Modules_WaterDepthShallowMinWaterCount", "2", "UI_QoLforSacriel_Modules_WaterDepthShallowMinWaterCount_Tooltip")
    options:addTextEntry("waterDepthDeepMinWaterCount", "UI_QoLforSacriel_Modules_WaterDepthDeepMinWaterCount", "7", "UI_QoLforSacriel_Modules_WaterDepthDeepMinWaterCount_Tooltip")

    options:addSeparator()
    options:addTitle("UI_QoLforSacriel_Modules_ForagingRefinementTitle")
    options:addTickBox("enableForagingRefinement", "UI_QoLforSacriel_Modules_EnableForagingRefinement", true, "UI_QoLforSacriel_Modules_EnableForagingRefinement_Tooltip")

    options:addSeparator()
    options:addTitle("UI_QoLforSacriel_Modules_InteractionTitle")

    options:addSeparator()
    options:addTitle("UI_QoLforSacriel_Modules_EquipmentTitle")
    options:addTickBox("enableEquipment", "UI_QoLforSacriel_Modules_EnableEquipment", true, "UI_QoLforSacriel_Modules_EnableEquipment_Tooltip")
    options:addTickBox("equipmentEnablePresets", "UI_QoLforSacriel_Modules_EquipmentEnablePresets", true, "UI_QoLforSacriel_Modules_EquipmentEnablePresets_Tooltip")
    local equipmentPresetCountOption = options:addComboBox("equipmentPresetCount", "UI_QoLforSacriel_Modules_EquipmentPresetCount", "UI_QoLforSacriel_Modules_EquipmentPresetCount_Tooltip")
    for i = 1, 8 do
        equipmentPresetCountOption:addItem("UI_QoLforSacriel_Modules_EquipmentPresetCount_" .. tostring(i), i == 2)
    end

    local getPresetCountOptionValue = equipmentPresetCountOption.getValue
    equipmentPresetCountOption.getValue = function(self)
        -- Backwards compatibility: migrate legacy text-entry saves into combo index.
        local legacyValue = tonumber(self.value)
        if legacyValue and self.selected == 2 and legacyValue >= 1 and legacyValue <= #self.values then
            self.selected = legacyValue
            if self.element ~= nil then
                self.element.selected = legacyValue
            end
            self.value = nil
        end
        return getPresetCountOptionValue(self)
    end

    options:addTitle("UI_QoLforSacriel_Modules_EquipmentPresetNamesTitle")
    options:addDescription("UI_QoLforSacriel_Modules_EquipmentPresetNamesNote")
    options:addTextEntry("equipmentPresetName1", "UI_QoLforSacriel_Modules_EquipmentPresetName1", "", "UI_QoLforSacriel_Modules_EquipmentPresetName_Tooltip")
    options:addTextEntry("equipmentPresetName2", "UI_QoLforSacriel_Modules_EquipmentPresetName2", "", "UI_QoLforSacriel_Modules_EquipmentPresetName_Tooltip")
    options:addTextEntry("equipmentPresetName3", "UI_QoLforSacriel_Modules_EquipmentPresetName3", "", "UI_QoLforSacriel_Modules_EquipmentPresetName_Tooltip")
    options:addTextEntry("equipmentPresetName4", "UI_QoLforSacriel_Modules_EquipmentPresetName4", "", "UI_QoLforSacriel_Modules_EquipmentPresetName_Tooltip")
    options:addTextEntry("equipmentPresetName5", "UI_QoLforSacriel_Modules_EquipmentPresetName5", "", "UI_QoLforSacriel_Modules_EquipmentPresetName_Tooltip")
    options:addTextEntry("equipmentPresetName6", "UI_QoLforSacriel_Modules_EquipmentPresetName6", "", "UI_QoLforSacriel_Modules_EquipmentPresetName_Tooltip")
    options:addTextEntry("equipmentPresetName7", "UI_QoLforSacriel_Modules_EquipmentPresetName7", "", "UI_QoLforSacriel_Modules_EquipmentPresetName_Tooltip")
    options:addTextEntry("equipmentPresetName8", "UI_QoLforSacriel_Modules_EquipmentPresetName8", "", "UI_QoLforSacriel_Modules_EquipmentPresetName_Tooltip")

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
    options:addTickBox("furnitureNudgeAllowMultiTile", "UI_QoLforSacriel_Modules_FurnitureNudgeAllowMultiTile", false, "UI_QoLforSacriel_Modules_FurnitureNudgeAllowMultiTile_Tooltip")
    options:addTickBox("furnitureNudgeIgnoreToolRequirements", "UI_QoLforSacriel_Modules_FurnitureNudgeIgnoreToolRequirements", false, "UI_QoLforSacriel_Modules_FurnitureNudgeIgnoreToolRequirements_Tooltip")

    options:addSeparator()
    options:addTitle("UI_QoLforSacriel_Modules_LightSwitchToggleTitle")
    options:addTickBox("enableLightSwitchToggle", "UI_QoLforSacriel_Modules_EnableLightSwitchToggle", true, "UI_QoLforSacriel_Modules_EnableLightSwitchToggle_Tooltip")
    local lightSwitchToggleHotkeyName = getText("UI_QoLforSacriel_Modules_LightSwitchToggleHotkey")
    local lightSwitchToggleHotkey = options:addKeyBind("lightSwitchToggleHotkey", lightSwitchToggleHotkeyName, Keyboard.KEY_F, "UI_QoLforSacriel_Modules_LightSwitchToggleHotkey_Tooltip")
    lightSwitchToggleHotkey.ctrl = true
    lightSwitchToggleHotkey.shift = false
    lightSwitchToggleHotkey.alt = false
    local lightSwitchToggleRangeOption = options:addComboBox("lightSwitchToggleRange", "UI_QoLforSacriel_Modules_LightSwitchToggleRange", "UI_QoLforSacriel_Modules_LightSwitchToggleRange_Tooltip")
    for i = 1, 3 do
        lightSwitchToggleRangeOption:addItem("UI_QoLforSacriel_Modules_LightSwitchToggleRange_" .. tostring(i), i == 1)
    end

    local getLightSwitchToggleRangeOptionValue = lightSwitchToggleRangeOption.getValue
    lightSwitchToggleRangeOption.getValue = function(self)
        -- Backwards compatibility: migrate legacy text-entry saves into combo index.
        local legacyValue = tonumber(self.value)
        if legacyValue and self.selected == 1 and legacyValue >= 1 and legacyValue <= #self.values then
            self.selected = legacyValue
            if self.element ~= nil then
                self.element.selected = legacyValue
            end
            self.value = nil
        end
        return getLightSwitchToggleRangeOptionValue(self)
    end

    options:addTickBox("lightSwitchToggleRequireSameRoom", "UI_QoLforSacriel_Modules_LightSwitchToggleRequireSameRoom", true, "UI_QoLforSacriel_Modules_LightSwitchToggleRequireSameRoom_Tooltip")

    options:addSeparator()
    options:addTitle("UI_QoLforSacriel_Modules_NearbyDeviceOffTitle")
    options:addTickBox("enableNearbyDeviceOff", "UI_QoLforSacriel_Modules_EnableNearbyDeviceOff", true, "UI_QoLforSacriel_Modules_EnableNearbyDeviceOff_Tooltip")
    local nearbyDeviceOffHotkeyName = getText("UI_QoLforSacriel_Modules_NearbyDeviceOffHotkey")
    local nearbyDeviceOffHotkey = options:addKeyBind("nearbyDeviceOffHotkey", nearbyDeviceOffHotkeyName, Keyboard.KEY_G, "UI_QoLforSacriel_Modules_NearbyDeviceOffHotkey_Tooltip")
    nearbyDeviceOffHotkey.ctrl = true
    nearbyDeviceOffHotkey.shift = false
    nearbyDeviceOffHotkey.alt = false
    local nearbyDeviceOffRangeOption = options:addComboBox("nearbyDeviceOffRange", "UI_QoLforSacriel_Modules_NearbyDeviceOffRange", "UI_QoLforSacriel_Modules_NearbyDeviceOffRange_Tooltip")
    for i = 1, 3 do
        nearbyDeviceOffRangeOption:addItem("UI_QoLforSacriel_Modules_NearbyDeviceOffRange_" .. tostring(i), i == 3)
    end

    options:addSeparator()
    options:addTitle("UI_QoLforSacriel_Modules_HeldBagClimbTitle")
    options:addTickBox("enableHeldBagClimb", "UI_QoLforSacriel_Modules_EnableHeldBagClimb", true, "UI_QoLforSacriel_Modules_EnableHeldBagClimb_Tooltip")

    options:addSeparator()
    options:addTitle("UI_QoLforSacriel_Modules_VehicleEntryAssistTitle")
    options:addTickBox("enableVehicleEntryAssist", "UI_QoLforSacriel_Modules_EnableVehicleEntryAssist", true, "UI_QoLforSacriel_Modules_EnableVehicleEntryAssist_Tooltip")

    options:addSeparator()
    options:addTitle("UI_QoLforSacriel_Modules_CharacterSystemsTitle")
    options:addTitle("UI_QoLforSacriel_Modules_DrySelfTitle")
    options:addTickBox("enableDrySelfDivisor", "UI_QoLforSacriel_Modules_EnableDrySelfDivisor", true, "UI_QoLforSacriel_Modules_EnableDrySelfDivisor_Tooltip")
    options:addTextEntry("drySelfWetnessPerUse", "UI_QoLforSacriel_Modules_DrySelfWetnessPerUse", "6.25", "UI_QoLforSacriel_Modules_DrySelfWetnessPerUse_Tooltip")
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
    options:addTitle("UI_QoLforSacriel_Modules_ArmorMoodTitle")
    options:addTickBox("enableArmorMood", "UI_QoLforSacriel_Modules_EnableArmorMood", true, "UI_QoLforSacriel_Modules_EnableArmorMood_Tooltip")
    options:addTextEntry("armorMoodBaseReductionFactor", "UI_QoLforSacriel_Modules_ArmorMoodBaseReductionFactor", "0.95", "UI_QoLforSacriel_Modules_ArmorMoodBaseReductionFactor_Tooltip")
    options:addTextEntry("armorMoodUpdateCooldownSeconds", "UI_QoLforSacriel_Modules_ArmorMoodUpdateCooldownSeconds", "2", "UI_QoLforSacriel_Modules_ArmorMoodUpdateCooldownSeconds_Tooltip")

    attachApplySync(options, logger)
    syncAllBindings(options, logger)

    return options
end

return CoreModOptions
