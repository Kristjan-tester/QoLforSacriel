require "TimedActions/ISInventoryTransferUtil"
require "TimedActions/ISWearClothing"

local EquipmentPresets = {}

local installed = false
local MAX_PRESET_COUNT = 8
local MOD_DATA_KEY = "QoLforSacriel_EquipmentPresets"
local MOD_DATA_TOGGLE_STATE_KEY = "QoLforSacriel_EquipmentPresetToggleState"
local HAND_MODE_PRIMARY = "primary"
local HAND_MODE_SECONDARY = "secondary"
local HAND_MODE_BOTH = "both"
local MAX_BODY_LOCATION_LENGTH = 64
local MAX_PRESET_NAME_LENGTH = 24
local HOTKEY_NONE_TOKEN = "NONE"
local MOD_OPTIONS_ID = "QoLforSacriel.Modules"
local GENERIC_PRESET_CONTEXT_CATEGORIES = {
    Food = true,
    Literature = true,
    Drainable = true,
    Key = true,
    Map = true,
    WeaponPart = true,
}

local HOTKEY_SETTING_PREFIX = "QoLforSacriel_Equipment_PresetHotkey"

local hotkeyCacheSignature = nil
local hotkeyCacheMap = {}
local hotkeyCachePresetCount = 0
local pendingHotkeyToggle = nil
local pendingHotkeyWaitLogged = false
local getConfiguredPresetCount
local getConfiguredHotkeyBinding
local getConfiguredBindingComboText

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

local function trimText(value)
    local text = tostring(value or "")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function truncateUtf8(text, maxCharacters)
    local characterCount = 0
    local byteIndex = 1
    local byteLength = #text

    while byteIndex <= byteLength and characterCount < maxCharacters do
        local firstByte = string.byte(text, byteIndex)
        local characterLength = 1

        if firstByte >= 0xF0 and firstByte <= 0xF7 then
            characterLength = 4
        elseif firstByte >= 0xE0 and firstByte <= 0xEF then
            characterLength = 3
        elseif firstByte >= 0xC0 and firstByte <= 0xDF then
            characterLength = 2
        end

        if byteIndex + characterLength - 1 > byteLength then
            break
        end

        byteIndex = byteIndex + characterLength
        characterCount = characterCount + 1
    end

    return string.sub(text, 1, byteIndex - 1)
end

local function getHotkeySettingName(index)
    return HOTKEY_SETTING_PREFIX .. tostring(index)
end

local function getHotkeyOptionId(index)
    return "equipmentPresetHotkey" .. tostring(index)
end

local function getPresetBindingName(index)
    if PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.getOptions then
        local options = PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)
        if options and options.getOption then
            local option = options:getOption(getHotkeyOptionId(index))
            if option and option.name and option.name ~= "" then
                return option.name
            end
        end
    end

    local key = "UI_QoLforSacriel_Modules_EquipmentPresetHotkey" .. tostring(index)
    return getTextOrNull(key) or ("Equipment Preset " .. tostring(index))
end

local function isModifierDown(functionName)
    local fn = _G[functionName]
    if type(fn) ~= "function" then
        return false
    end

    local ok, state = pcall(fn)
    if not ok then
        return false
    end
    return state == true
end

local function getHotkeyOption(index)
    if not PZAPI or not PZAPI.ModOptions or not PZAPI.ModOptions.getOptions then
        return nil
    end

    local options = PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)
    if not options or not options.getOption then
        return nil
    end

    return options:getOption(getHotkeyOptionId(index))
end

local function getExpectedModifierState(index)
    local option = getHotkeyOption(index)
    local source = option
    if option and type(option.element) == "table" then
        source = option.element
    end

    local ctrl = true
    local shift = false
    local alt = false

    if source then
        if source.ctrl ~= nil then
            ctrl = source.ctrl == true
        end
        if source.shift ~= nil then
            shift = source.shift == true
        end
        if source.alt ~= nil then
            alt = source.alt == true
        end
    end

    return ctrl, shift, alt
end

local function isModifierStateMatched(expectedCtrl, expectedShift, expectedAlt)
    local ctrlDown = isModifierDown("isCtrlKeyDown")
    local shiftDown = isModifierDown("isShiftKeyDown")
    local altDown = isModifierDown("isAltKeyDown")

    return ctrlDown == expectedCtrl
        and shiftDown == expectedShift
        and altDown == expectedAlt
end

local function areAnyModifierKeysDown()
    return isModifierDown("isCtrlKeyDown")
        or isModifierDown("isShiftKeyDown")
        or isModifierDown("isAltKeyDown")
end

local function getTimedActionQueueDepth(playerObj)
    if not playerObj or not ISTimedActionQueue or not ISTimedActionQueue.getTimedActionQueue then
        return -1
    end

    local queue = ISTimedActionQueue.getTimedActionQueue(playerObj)
    if not queue or not queue.queue then
        return -1
    end

    return #queue.queue
end

local function getDefaultHotkeyToken(index)
    return "F" .. tostring(index)
end

local function getDefaultHotkeyCode(index)
    return FKEY_TO_CODE[getDefaultHotkeyToken(index)]
end

local function normalizeHotkeyToken(value)
    local token = trimText(value)
    if token == "" then
        return nil
    end

    token = string.upper(token)
    token = token:gsub("%s+", "")
    if token:sub(1, 4) == "KEY_" then
        token = token:sub(5)
    end
    if token == "UNBOUND" then
        token = HOTKEY_NONE_TOKEN
    end
    return token
end

local function resolveKeyCodeFromToken(token)
    local normalized = normalizeHotkeyToken(token)
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

getConfiguredHotkeyBinding = function(settings, index)
    local value = settings.get(getHotkeySettingName(index))
    local defaultToken = getDefaultHotkeyToken(index)
    if value == nil then
        return getDefaultHotkeyCode(index), defaultToken
    end

    local numericValue = tonumber(value)
    if numericValue ~= nil then
        local keyCode = math.floor(numericValue)
        if keyCode > 0 then
            return keyCode, tostring(keyCode)
        end
        return nil, HOTKEY_NONE_TOKEN
    end

    local normalized = normalizeHotkeyToken(value)
    if not normalized then
        return getDefaultHotkeyCode(index), defaultToken
    end

    if normalized == "DEFAULT" then
        return getDefaultHotkeyCode(index), defaultToken
    end

    if normalized == HOTKEY_NONE_TOKEN then
        return nil, normalized
    end

    return resolveKeyCodeFromToken(normalized), normalized
end

local function buildHotkeySignature(settings, presetCount)
    local parts = { tostring(presetCount) }

    for i = 1, MAX_PRESET_COUNT do
        local keyCode = getConfiguredHotkeyBinding(settings, i)
        parts[#parts + 1] = tostring(keyCode or 0)
    end
    return table.concat(parts, "|")
end

local function refreshHotkeyCache(settings, logger)
    local presetCount = getConfiguredPresetCount(settings)
    local signature = buildHotkeySignature(settings, presetCount)
    if signature == hotkeyCacheSignature then
        return
    end

    hotkeyCacheSignature = signature
    hotkeyCacheMap = {}
    hotkeyCachePresetCount = MAX_PRESET_COUNT
    local hotkeySummary = {}

    -- Keep all preset hotkeys active even when fewer slots are shown in the context menu.
    for i = 1, MAX_PRESET_COUNT do
        local keyCode, token = getConfiguredHotkeyBinding(settings, i)
        hotkeySummary[#hotkeySummary + 1] = "P" .. tostring(i) .. "=" .. getConfiguredBindingComboText(settings, i)
        if keyCode then
            if not hotkeyCacheMap[keyCode] then
                hotkeyCacheMap[keyCode] = i
            elseif logger and logger.debug then
                logger.debug("Equipment preset duplicate hotkey token '" .. tostring(token) .. "' for presets " .. tostring(hotkeyCacheMap[keyCode]) .. " and " .. tostring(i) .. "; keeping lower index")
            end
        else
            if token ~= HOTKEY_NONE_TOKEN and logger and logger.debug then
                logger.debug("Equipment preset invalid hotkey token for preset " .. tostring(i) .. ": " .. tostring(token))
            end
        end
    end

    if logger and logger.debug then
        logger.debug("Equipment preset keybind map refreshed: " .. table.concat(hotkeySummary, "; "))
    end
end

local function getConfiguredBindingText(settings, index)
    local keyCode = getConfiguredHotkeyBinding(settings, index)
    if not keyCode then
        return getTextOrNull("UI_QoLforSacriel_EquipmentHotkeyUnbound") or "Unbound"
    end

    local keyName = tostring(keyCode)
    if type(getKeyName) == "function" then
        local ok, resolvedName = pcall(getKeyName, keyCode)
        if ok and resolvedName and tostring(resolvedName) ~= "" then
            keyName = tostring(resolvedName)
        end
    end
    return keyName
end

getConfiguredBindingComboText = function(settings, index)
    local keyCode = getConfiguredHotkeyBinding(settings, index)
    if not keyCode then
        return getTextOrNull("UI_QoLforSacriel_EquipmentHotkeyUnbound") or "Unbound"
    end

    local parts = {}
    local ctrl, shift, alt = getExpectedModifierState(index)
    if ctrl then
        parts[#parts + 1] = "Ctrl"
    end
    if shift then
        parts[#parts + 1] = "Shift"
    end
    if alt then
        parts[#parts + 1] = "Alt"
    end
    parts[#parts + 1] = getConfiguredBindingText(settings, index)

    return table.concat(parts, "+")
end

local function getPressedComboText(key)
    local parts = {}
    if isModifierDown("isCtrlKeyDown") then
        parts[#parts + 1] = "Ctrl"
    end
    if isModifierDown("isShiftKeyDown") then
        parts[#parts + 1] = "Shift"
    end
    if isModifierDown("isAltKeyDown") then
        parts[#parts + 1] = "Alt"
    end

    local keyName = tostring(key)
    if type(getKeyName) == "function" then
        local ok, resolvedName = pcall(getKeyName, key)
        if ok and resolvedName and tostring(resolvedName) ~= "" then
            keyName = tostring(resolvedName)
        end
    end
    parts[#parts + 1] = keyName

    return table.concat(parts, "+")
end

local function getEntryFullType(entry)
    if type(entry) == "table" then
        return entry.fullType
    end
    return entry
end

local function getEntryHandMode(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local mode = entry.handMode
    if mode == HAND_MODE_PRIMARY or mode == HAND_MODE_SECONDARY or mode == HAND_MODE_BOTH then
        return mode
    end
    return nil
end

local function normalizeBodyLocation(bodyLocation)
    if not bodyLocation then
        return nil
    end

    local value = tostring(bodyLocation)
    if value == "" then
        return nil
    end

    if #value > MAX_BODY_LOCATION_LENGTH then
        return nil
    end

    if value:find("[^%w_%-:]", 1, false) then
        return nil
    end

    return value
end

local function getEntryBodyLocation(entry)
    if type(entry) ~= "table" then
        return nil
    end
    return normalizeBodyLocation(entry.bodyLocation)
end

local function createPresetEntry(fullType, handMode, bodyLocation)
    local normalizedBodyLocation = normalizeBodyLocation(bodyLocation)
    if not handMode and not normalizedBodyLocation then
        return fullType
    end

    local out = {
        fullType = fullType,
        handMode = handMode,
    }

    if normalizedBodyLocation then
        out.bodyLocation = normalizedBodyLocation
    end

    return out
end

getConfiguredPresetCount = function(settings)
    local count = tonumber(settings.get("QoLforSacriel_Equipment_PresetCount")) or 2
    return math.max(1, math.min(MAX_PRESET_COUNT, math.floor(count)))
end

local function getPresetMenuLabel()
    return getTextOrNull("UI_QoLforSacriel_EquipmentPresets") or "Equipment Presets"
end

local function getPresetEntryLabel(index, settings)
    local configuredName = settings and settings.get and settings.get("QoLforSacriel_Equipment_PresetName" .. tostring(index))
    configuredName = truncateUtf8(trimText(configuredName), MAX_PRESET_NAME_LENGTH)
    if configuredName ~= "" then
        return configuredName
    end

    local key = "UI_QoLforSacriel_EquipmentPresetEntry" .. tostring(index)
    return getTextOrNull(key) or ("Preset " .. tostring(index))
end

local function getAssignPresetLabel(index)
    local key = "UI_QoLforSacriel_EquipmentAssignPreset" .. tostring(index)
    return getTextOrNull(key) or ("Add to Preset " .. tostring(index))
end

local function getAddToThisPresetLabel()
    return getTextOrNull("UI_QoLforSacriel_EquipmentAddToThisPreset") or "Add to this preset"
end

local function getTogglePresetLabel(index)
    local key = "UI_QoLforSacriel_EquipmentTogglePreset" .. tostring(index)
    return getTextOrNull(key) or ("Toggle Preset " .. tostring(index) .. " (Ctrl+F" .. tostring(index) .. ")")
end

local function getTogglePresetShortLabel()
    return getTextOrNull("UI_QoLforSacriel_EquipmentTogglePresetShort") or "Toggle preset"
end

local function getTogglePresetTooltip(index, settings)
    local key = "UI_QoLforSacriel_EquipmentTogglePresetTooltip"
    local text = getTextOrNull(key)
    local hotkeyText = getConfiguredBindingText(settings, index)
    if text then
        return text .. " <LINE> Hotkey: " .. hotkeyText
    end
    return "Toggles this preset between equip and unequip mode. <LINE> Hotkey: " .. hotkeyText
end

local function getClearPresetLabel(index)
    local key = "UI_QoLforSacriel_EquipmentClearPreset" .. tostring(index)
    return getTextOrNull(key) or ("Clear Preset " .. tostring(index))
end

local function getClearPresetShortLabel()
    return getTextOrNull("UI_QoLforSacriel_EquipmentClearPresetShort") or "Clear preset"
end

local function getAddAllCurrentProtectiveLabel()
    return getTextOrNull("UI_QoLforSacriel_EquipmentAddAllCurrentProtective") or "add all current"
end

local function getAddAllCurrentProtectiveTooltip()
    return getTextOrNull("UI_QoLforSacriel_EquipmentAddAllCurrentProtective_Tooltip")
    or "adds currently worn protective gear and equipped weapon-category items to this preset, clearing anything that was here before"
end

local function getMannequinUnavailableTooltip(reason)
    local key = "UI_QoLforSacriel_EquipmentMannequinUnavailable_" .. tostring(reason)
    return getTextOrNull(key) or "Action unavailable in current context."
end

local function getStoreProtectiveArmorLabel()
    return getTextOrNull("UI_QoLforSacriel_EquipmentStoreProtectiveArmor") or "Store Protective Armor"
end

local function getWearProtectiveArmorLabel()
    return getTextOrNull("UI_QoLforSacriel_EquipmentWearProtectiveArmor") or "Wear Protective Armor"
end

local function getAddPresetToMannequinLabel()
    return getTextOrNull("UI_QoLforSacriel_EquipmentAddPresetToMannequin") or "Add preset to mannequin"
end

local function resolveActualItems(items)
    if ISInventoryPane and ISInventoryPane.getActualItems then
        local actual = ISInventoryPane.getActualItems(items)
        if actual then
            return actual
        end
    end
    return items or {}
end

local function getPresetStore(playerObj)
    local modData = playerObj:getModData()
    if not modData[MOD_DATA_KEY] then
        modData[MOD_DATA_KEY] = {}
    end

    local store = modData[MOD_DATA_KEY]
    for i = 1, MAX_PRESET_COUNT do
        if not store[i] then
            store[i] = {}
        end
    end

    return store
end

local function getToggleStateStore(playerObj)
    local modData = playerObj:getModData()
    if type(modData[MOD_DATA_TOGGLE_STATE_KEY]) ~= "table" then
        modData[MOD_DATA_TOGGLE_STATE_KEY] = {}
    end

    local store = modData[MOD_DATA_TOGGLE_STATE_KEY]
    for i = 1, MAX_PRESET_COUNT do
        if store[i] == nil then
            store[i] = false
        end
    end

    return store
end

local function setPresetMarkedEquipped(playerObj, presetIndex, marked)
    local store = getToggleStateStore(playerObj)
    store[presetIndex] = marked == true
end

local function isPresetMarkedEquipped(playerObj, presetIndex)
    local store = getToggleStateStore(playerObj)
    return store[presetIndex] == true
end

local function containsType(list, fullType)
    for i = 1, #list do
        if getEntryFullType(list[i]) == fullType then
            return true
        end
    end
    return false
end

local function getEntryIndexByType(list, fullType)
    for i = 1, #list do
        if getEntryFullType(list[i]) == fullType then
            return i
        end
    end
    return nil
end

local function upsertPresetEntry(playerObj, presetIndex, entry)
    local fullType = getEntryFullType(entry)
    if not fullType then
        return
    end

    local store = getPresetStore(playerObj)
    local preset = store[presetIndex]
    local existingIndex = getEntryIndexByType(preset, fullType)
    if existingIndex then
        local existingMode = getEntryHandMode(preset[existingIndex])
        local incomingMode = getEntryHandMode(entry)
        local existingBodyLocation = getEntryBodyLocation(preset[existingIndex])
        local incomingBodyLocation = getEntryBodyLocation(entry)

        local modeChanged = incomingMode and incomingMode ~= existingMode
        local bodyLocationChanged = incomingBodyLocation and incomingBodyLocation ~= existingBodyLocation
        local tableUpgradeNeeded = type(preset[existingIndex]) ~= "table" and (incomingMode or incomingBodyLocation)

        if modeChanged or bodyLocationChanged or tableUpgradeNeeded then
            preset[existingIndex] = createPresetEntry(fullType, incomingMode or existingMode, incomingBodyLocation or existingBodyLocation)
        end
        return
    end

    table.insert(preset, entry)
end

local function clearPreset(playerObj, presetIndex)
    local store = getPresetStore(playerObj)
    store[presetIndex] = {}
    setPresetMarkedEquipped(playerObj, presetIndex, false)
end

local function detectCurrentHandMode(playerObj, item)
    if not playerObj or not item then
        return nil
    end

    local primary = playerObj:getPrimaryHandItem()
    local secondary = playerObj:getSecondaryHandItem()
    if primary and secondary and primary == item and secondary == item then
        return HAND_MODE_BOTH
    end
    if secondary and secondary == item then
        return HAND_MODE_SECONDARY
    end
    if primary and primary == item then
        return HAND_MODE_PRIMARY
    end
    return nil
end

local function detectCurrentBodyLocation(playerObj, item)
    if not playerObj or not item then
        return nil
    end

    local wornItems = playerObj:getWornItems()
    if not wornItems then
        return nil
    end

    if wornItems.getLocation then
        local location = normalizeBodyLocation(wornItems:getLocation(item))
        if location then
            return location
        end
    end

    for i = 0, wornItems:size() - 1 do
        local worn = wornItems:get(i)
        if worn and worn.getItem and worn:getItem() == item and worn.getLocation then
            return normalizeBodyLocation(worn:getLocation())
        end

        if wornItems.getItemByIndex and wornItems:getItemByIndex(i) == item then
            if item.getBodyLocation then
                local bodyLocation = normalizeBodyLocation(item:getBodyLocation())
                if bodyLocation then
                    return bodyLocation
                end
            end
            if item.canBeEquipped then
                return normalizeBodyLocation(item:canBeEquipped())
            end
        end
    end

    return nil
end

local isWeaponCategoryItem

local function isWearableItem(item)
    if not item then
        return false
    end

    if item.getBodyLocation then
        local okBody, bodyLocation = pcall(item.getBodyLocation, item)
        if okBody and bodyLocation and tostring(bodyLocation) ~= "" then
            return true
        end
    end

    if item.canBeEquipped then
        local okEquippable, bodyLocation = pcall(item.canBeEquipped, item)
        if okEquippable and bodyLocation and tostring(bodyLocation) ~= "" then
            return true
        end
    end

    if item.isClothing then
        local okClothing, clothing = pcall(item.isClothing, item)
        if okClothing and clothing == true then
            return true
        end
    end

    if item.getCategory then
        local okCategory, category = pcall(item.getCategory, item)
        if okCategory and category == "Clothing" then
            return true
        end
    end

    if item.hasTag then
        local okTag, hasWearableTag = pcall(item.hasTag, item, "Wearable")
        if okTag and hasWearableTag == true then
            return true
        end
    end

    return false
end

local function getItemCategory(item)
    if not item or not item.getCategory then
        return nil
    end

    local ok, category = pcall(item.getCategory, item)
    if ok then
        return category
    end

    return nil
end

local function isPresetContextItem(item)
    if not item or not item.getFullType then
        return false
    end

    local category = getItemCategory(item)
    if category == nil then
        return false
    end
    if GENERIC_PRESET_CONTEXT_CATEGORIES[category] then
        return false
    end
    if category == "Weapon" then
        return true
    end

    return isWeaponCategoryItem(item) or isWearableItem(item)
end

local function collectSelectedEntries(items, playerObj)
    local selectedEntries = {}
    local seen = {}

    for i = 1, #items do
        local item = items[i]
        if isPresetContextItem(item) then
            local fullType = item:getFullType()
            if fullType and fullType ~= "" then
                local handMode = detectCurrentHandMode(playerObj, item)
                local bodyLocation = detectCurrentBodyLocation(playerObj, item)
                if not seen[fullType] then
                    table.insert(selectedEntries, createPresetEntry(fullType, handMode, bodyLocation))
                    seen[fullType] = {
                        index = #selectedEntries,
                        handMode = handMode,
                        bodyLocation = bodyLocation,
                    }
                elseif (handMode and not seen[fullType].handMode) or (bodyLocation and not seen[fullType].bodyLocation) then
                    local resolvedHandMode = handMode or seen[fullType].handMode
                    local resolvedBodyLocation = bodyLocation or seen[fullType].bodyLocation
                    selectedEntries[seen[fullType].index] = createPresetEntry(fullType, resolvedHandMode, resolvedBodyLocation)
                    seen[fullType].handMode = resolvedHandMode
                    seen[fullType].bodyLocation = resolvedBodyLocation
                end
            end
        end
    end

    return selectedEntries
end

local function addSelectionToPreset(playerObj, presetIndex, selectedEntries)
    for i = 1, #selectedEntries do
        upsertPresetEntry(playerObj, presetIndex, selectedEntries[i])
    end
end

local function closeContextMenu(context)
    if not context then
        return
    end

    if context.hideAndChildren then
        context:hideAndChildren()
        return
    end

    if context.setVisible then
        context:setVisible(false)
        return
    end

    if context.setHide then
        context:setHide(true)
    end
end

local function getItemDisplayCategory(item)
    if not item then
        return nil
    end

    local category = nil
    if item.getDisplayCategory then
        local okCategory, displayCategory = pcall(function()
            return item:getDisplayCategory()
        end)
        if okCategory then
            category = displayCategory
        end
    end

    if category == nil and item.getScriptItem then
        local scriptItem = item:getScriptItem()
        if scriptItem and scriptItem.getDisplayCategory then
            local okScriptCategory, scriptDisplayCategory = pcall(function()
                return scriptItem:getDisplayCategory()
            end)
            if okScriptCategory then
                category = scriptDisplayCategory
            end
        end
    end

    return category
end

local function isProtectiveGearItem(item)
    local category = getItemDisplayCategory(item)

    if not category then
        return false
    end

    local normalized = tostring(category):gsub("[^%a]", ""):lower()
    return normalized == "protectivegear"
end

isWeaponCategoryItem = function(item)
    local category = getItemDisplayCategory(item)
    if not category then
        return false
    end

    local normalized = tostring(category):gsub("[^%a]", ""):lower()
    if normalized == "weapon" then
        return true
    end
    if #normalized >= 6 and normalized:sub(-6) == "weapon" then
        return true
    end
    return false
end

local function getWornItemAt(wornItems, index)
    if not wornItems then
        return nil
    end

    if wornItems.getItemByIndex then
        local item = wornItems:getItemByIndex(index)
        if item then
            return item
        end

        -- Some builds expose 1-based getItemByIndex; try both before falling back.
        if index >= 0 then
            item = wornItems:getItemByIndex(index + 1)
            if item then
                return item
            end
        end
    end

    local entry = wornItems:get(index)
    if entry and entry.getItem then
        return entry:getItem()
    end

    if not entry and index >= 0 then
        entry = wornItems:get(index + 1)
        if entry and entry.getItem then
            return entry:getItem()
        end
    end

    return entry
end

local function collectCurrentProtectiveAndWeaponEntries(playerObj)
    local selectedEntries = {}
    local seen = {}

    local function addItemIfEligible(item)
        if not item or not item.getFullType then
            return
        end

        local fullType = item:getFullType()
        if not fullType or fullType == "" or seen[fullType] then
            return
        end

        if isProtectiveGearItem(item) or isWeaponCategoryItem(item) then
            local handMode = detectCurrentHandMode(playerObj, item)
            local bodyLocation = detectCurrentBodyLocation(playerObj, item)
            table.insert(selectedEntries, createPresetEntry(fullType, handMode, bodyLocation))
            seen[fullType] = true
        end
    end

    local wornItems = playerObj:getWornItems()
    if not wornItems then
        return selectedEntries
    end

    for i = 0, wornItems:size() - 1 do
        addItemIfEligible(getWornItemAt(wornItems, i))
    end

    addItemIfEligible(playerObj:getPrimaryHandItem())
    addItemIfEligible(playerObj:getSecondaryHandItem())

    return selectedEntries
end

local function replacePresetWithCurrentProtective(playerObj, presetIndex)
    clearPreset(playerObj, presetIndex)
    addSelectionToPreset(playerObj, presetIndex, collectCurrentProtectiveAndWeaponEntries(playerObj))
    setPresetMarkedEquipped(playerObj, presetIndex, false)
end

local function getDisplayNameForType(fullType)
    if not fullType or fullType == "" then
        return ""
    end

    local scriptItem = nil
    if ScriptManager and ScriptManager.instance and ScriptManager.instance.FindItem then
        scriptItem = ScriptManager.instance:FindItem(fullType)
    elseif getScriptManager then
        local mgr = getScriptManager()
        if mgr and mgr.FindItem then
            scriptItem = mgr:FindItem(fullType)
        end
    end

    if scriptItem and scriptItem.getDisplayName then
        local okName, name = pcall(function()
            return scriptItem:getDisplayName()
        end)
        if okName and name and name ~= "" then
            return name
        end
    end

    if InventoryItemFactory and InventoryItemFactory.CreateItem then
        local okItem, item = pcall(function()
            return InventoryItemFactory.CreateItem(fullType)
        end)
        if okItem and item and item.getDisplayName then
            local okDisplay, displayName = pcall(function()
                return item:getDisplayName()
            end)
            if okDisplay and displayName and displayName ~= "" then
                return displayName
            end
        end
    end

    return fullType
end

local function buildAssignPresetTooltip(playerObj, presetIndex, selectedTypes)
    local store = getPresetStore(playerObj)
    local preset = store[presetIndex]

    local presetNames = {}
    for i = 1, #preset do
        table.insert(presetNames, getDisplayNameForType(getEntryFullType(preset[i])))
    end

    local selectedNames = {}
    local alreadyInPreset = {}
    local willAdd = {}

    for i = 1, #selectedTypes do
        local fullType = getEntryFullType(selectedTypes[i])
        local name = getDisplayNameForType(fullType)
        table.insert(selectedNames, name)

        if containsType(preset, fullType) then
            table.insert(alreadyInPreset, name)
        else
            table.insert(willAdd, name)
        end
    end

    local description = ""
    if #presetNames > 0 then
        description = description .. "Preset contains: " .. table.concat(presetNames, ", ")
    else
        description = description .. "Preset contains: empty"
    end

    description = description .. " <LINE> Selected: " .. table.concat(selectedNames, ", ")

    if #willAdd > 0 then
        description = description .. " <LINE> Will add: " .. table.concat(willAdd, ", ")
    else
        description = description .. " <LINE> Will add: none"
    end

    if #alreadyInPreset > 0 then
        description = description .. " <LINE> Already in preset: " .. table.concat(alreadyInPreset, ", ")
    end

    return description
end

local function attachOptionTooltip(option, description)
    if not option or not description or description == "" then
        return
    end

    local tooltip = ISInventoryPaneContextMenu.addToolTip()
    tooltip.description = description
    tooltip.maxLineWidth = 512
    option.toolTip = tooltip
end

local function forEachPresetItem(playerObj, presetIndex, fn)
    local store = getPresetStore(playerObj)
    local preset = store[presetIndex]
    for i = 1, #preset do
        fn(preset[i])
    end
end

local function findWornItemByType(playerObj, fullType)
    local wornItems = playerObj:getWornItems()
    for i = 0, wornItems:size() - 1 do
        local item = getWornItemAt(wornItems, i)
        if item and item:getFullType() == fullType then
            return item
        end
    end

    local primary = playerObj:getPrimaryHandItem()
    if primary and primary:getFullType() == fullType then
        return primary
    end

    local secondary = playerObj:getSecondaryHandItem()
    if secondary and secondary:getFullType() == fullType then
        return secondary
    end

    return nil
end

local function isHandModeSatisfied(playerObj, fullType, handMode)
    local primary = playerObj:getPrimaryHandItem()
    local secondary = playerObj:getSecondaryHandItem()
    local primaryType = primary and primary:getFullType() or nil
    local secondaryType = secondary and secondary:getFullType() or nil

    if handMode == HAND_MODE_PRIMARY then
        return primaryType == fullType
    end
    if handMode == HAND_MODE_SECONDARY then
        return secondaryType == fullType
    end
    if handMode == HAND_MODE_BOTH then
        return primaryType == fullType and secondaryType == fullType
    end
    return false
end

local function isTypeEquipped(playerObj, fullType)
    return findWornItemByType(playerObj, fullType) ~= nil
end

local function findWornItemByTypeAndLocation(playerObj, fullType, bodyLocation)
    local normalizedBodyLocation = normalizeBodyLocation(bodyLocation)
    if not normalizedBodyLocation then
        return nil
    end

    local wornItems = playerObj:getWornItems()
    if not wornItems then
        return nil
    end

    for i = 0, wornItems:size() - 1 do
        local worn = wornItems:get(i)
        if worn and worn.getItem and worn.getLocation then
            local location = normalizeBodyLocation(worn:getLocation())
            local item = worn:getItem()
            if location == normalizedBodyLocation and item and item.getFullType and item:getFullType() == fullType then
                return item
            end
        end
    end

    return nil
end

local function getPlayerWornItemAtLocation(playerObj, bodyLocation)
    local normalizedBodyLocation = normalizeBodyLocation(bodyLocation)
    if not playerObj or not normalizedBodyLocation then
        return nil
    end

    if ItemBodyLocation and ItemBodyLocation.get and ResourceLocation and ResourceLocation.of then
        local itemBodyLocation = ItemBodyLocation.get(ResourceLocation.of(normalizedBodyLocation))
        if itemBodyLocation then
            return playerObj:getWornItem(itemBodyLocation)
        end
    end

    return playerObj:getWornItem(normalizedBodyLocation)
end

local function isBodyLocationSatisfied(playerObj, fullType, bodyLocation)
    return findWornItemByTypeAndLocation(playerObj, fullType, bodyLocation) ~= nil
end

local function getItemByTypeForBodyLocation(playerObj, fullType, bodyLocation)
    local normalizedBodyLocation = normalizeBodyLocation(bodyLocation)
    if not normalizedBodyLocation then
        return playerObj:getInventory():getFirstTypeRecurse(fullType)
    end

    local bestFallback = nil
    local inventory = playerObj:getInventory()
    if not inventory then
        return nil
    end

    local items = inventory:getAllEvalRecurse(function(it)
        return it and it.getFullType and it:getFullType() == fullType
    end)

    if not items then
        return nil
    end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and not playerObj:isEquipped(item) then
            local itemBodyLocation = normalizeBodyLocation(item.getBodyLocation and item:getBodyLocation() or nil)
            local itemEquippedLocation = normalizeBodyLocation(item.canBeEquipped and item:canBeEquipped() or nil)
            if itemBodyLocation == normalizedBodyLocation or itemEquippedLocation == normalizedBodyLocation then
                return item
            end
            if not bestFallback then
                bestFallback = item
            end
        end
    end

    if bestFallback then
        return bestFallback
    end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            return item
        end
    end

    return nil
end

local function getItemBodyLocation(item)
    if not item then
        return nil
    end

    if item.IsClothing and item:IsClothing() and item.getBodyLocation then
        return normalizeBodyLocation(item:getBodyLocation())
    end

    if item.canBeEquipped then
        return normalizeBodyLocation(item:canBeEquipped())
    end

    return nil
end

local function resolveExtraTypeForBodyLocation(item, bodyLocation)
    local normalizedBodyLocation = normalizeBodyLocation(bodyLocation)
    if not item or not normalizedBodyLocation then
        return nil
    end

    if getItemBodyLocation(item) == normalizedBodyLocation then
        return nil
    end

    if not item.getClothingItemExtra or not item.getModule then
        return nil
    end

    local extraList = item:getClothingItemExtra()
    if not extraList then
        return nil
    end

    for i = 0, extraList:size() - 1 do
        local extraType = moduleDotType(item:getModule(), extraList:get(i))
        local extraItem = ISInventoryPaneContextMenu.getItemInstance and ISInventoryPaneContextMenu.getItemInstance(extraType) or nil
        if extraItem and getItemBodyLocation(extraItem) == normalizedBodyLocation then
            return extraType
        end
    end

    return nil
end

local function isPresetEntryEquipped(playerObj, entry)
    local fullType = getEntryFullType(entry)
    if not fullType then
        return false
    end

    local handMode = getEntryHandMode(entry)
    if handMode then
        return isHandModeSatisfied(playerObj, fullType, handMode)
    end

    local bodyLocation = getEntryBodyLocation(entry)
    if bodyLocation then
        return isBodyLocationSatisfied(playerObj, fullType, bodyLocation)
    end

    return isTypeEquipped(playerObj, fullType)
end

local function findInventoryItemByType(playerObj, fullType)
    if not playerObj or not fullType or fullType == "" then
        return nil
    end

    local inventory = playerObj:getInventory()
    if not inventory then
        return nil
    end

    local item = inventory:getFirstTypeRecurse(fullType)
    if item then
        return item
    end

    local shortType = fullType:match("[^%.]+$")
    if shortType and shortType ~= "" and shortType ~= fullType then
        item = inventory:getFirstTypeRecurse(shortType)
        if item and item.getFullType and item:getFullType() == fullType then
            return item
        end
    end

    return nil
end

local function isMannequinCompatibleItem(item, bodyLocation)
    local normalizedBodyLocation = normalizeBodyLocation(bodyLocation)
    if not item or not normalizedBodyLocation or getItemBodyLocation(item) ~= normalizedBodyLocation then
        return false
    end

    if item.IsClothing and item:IsClothing() then
        return true
    end

    return item.getCategory and item:getCategory() == "Container"
end

local function isProtectiveClothingItem(item)
    return item and item.IsClothing and item:IsClothing() and isProtectiveGearItem(item)
end

local function getMannequinEntryBodyLocation(playerObj, entry)
    local savedBodyLocation = getEntryBodyLocation(entry)
    if savedBodyLocation then
        return savedBodyLocation
    end

    local fullType = getEntryFullType(entry)
    local item = findInventoryItemByType(playerObj, fullType)
    return getItemBodyLocation(item)
end

local function logMannequinDebug(logger, message)
    if logger and logger.debug then
        logger.debug("Equipment preset mannequin: " .. message)
    end
end

local function isMannequinCompatibleEntry(playerObj, entry)
    return getEntryFullType(entry) ~= nil and getEntryFullType(entry) ~= "" and getMannequinEntryBodyLocation(playerObj, entry) ~= nil
end

local function findUnequippedItemForMannequin(playerObj, fullType, bodyLocation)
    if not playerObj or not fullType or not bodyLocation then
        return nil
    end

    local inventory = playerObj:getInventory()
    if not inventory then
        return nil
    end

    local items = inventory:getAllEvalRecurse(function(item)
        return item and item.getFullType and item:getFullType() == fullType
    end)
    if not items then
        return nil
    end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and not playerObj:isEquipped(item) and isMannequinCompatibleItem(item, bodyLocation) then
            return item
        end
    end

    return nil
end

local function findPresetItemForMannequin(playerObj, fullType, bodyLocation)
    local item = findUnequippedItemForMannequin(playerObj, fullType, bodyLocation)
    if item then
        return item
    end

    item = findWornItemByTypeAndLocation(playerObj, fullType, bodyLocation)
    if item and isMannequinCompatibleItem(item, bodyLocation) then
        return item
    end

    return nil
end

local function findMannequinWornItemByTypeAndLocation(mannequin, fullType, bodyLocation)
    local normalizedBodyLocation = normalizeBodyLocation(bodyLocation)
    if not mannequin or not normalizedBodyLocation or not mannequin.getWornItems then
        return nil
    end

    local wornItems = mannequin:getWornItems()
    if not wornItems then
        return nil
    end

    for i = 0, wornItems:size() - 1 do
        local worn = wornItems:get(i)
        local item = worn and worn.getItem and worn:getItem() or nil
        local location = worn and worn.getLocation and normalizeBodyLocation(worn:getLocation()) or nil
        if location == normalizedBodyLocation and item and item.getFullType and item:getFullType() == fullType then
            return item
        end
    end

    return nil
end

local function isUsableMannequin(object)
    return type(instanceof) == "function" and instanceof(object, "IsoMannequin")
        and object.getContainer and object:getContainer()
        and object.getSquare and object:getSquare()
end

local function resolveMannequinOnSquare(square)
    local objects = square and square.getObjects and square:getObjects() or nil
    if not objects then
        return nil
    end

    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if isUsableMannequin(object) then
            return object
        end
    end

    return nil
end

local function resolveMannequin(worldobjects)
    if not worldobjects then
        return nil
    end

    for _, worldObject in ipairs(worldobjects) do
        if isUsableMannequin(worldObject) then
            return worldObject
        end

        local square = worldObject and worldObject.getSquare and worldObject:getSquare() or nil
        local mannequin = resolveMannequinOnSquare(square)
        if mannequin then
            return mannequin
        end
    end

    local clickedObject = worldobjects[1]
    local clickedSquare = clickedObject and clickedObject.getSquare and clickedObject:getSquare() or nil
    local cell = getCell and getCell() or nil
    if clickedSquare and cell and cell.getGridSquare then
        local diagonalSquare = cell:getGridSquare(clickedSquare:getX() + 1, clickedSquare:getY() - 1, clickedSquare:getZ())
        local mannequin = resolveMannequinOnSquare(diagonalSquare)
        if mannequin then
            return mannequin
        end
    end

    return nil
end

local function canUseMannequinTransfers(playerObj, mannequin)
    if not playerObj or playerObj:isDead() or playerObj:getVehicle() then
        return false
    end
    if isGamePaused and isGamePaused() then
        return false
    end
    if not mannequin or not mannequin.getContainer or not mannequin:getContainer() or not mannequin.getSquare or not mannequin:getSquare() then
        return false
    end
    return ISTimedActionQueue and ISInventoryTransferUtil and ISInventoryTransferUtil.newInventoryTransferAction and ISWearClothing
end

local function walkToMannequin(playerObj, mannequin)
    return luautils and luautils.walkAdj and luautils.walkAdj(playerObj, mannequin:getSquare()) == true
end

local function getMannequinWornItems(mannequin, predicate)
    local items = {}
    local wornItems = mannequin and mannequin.getWornItems and mannequin:getWornItems() or nil
    if not wornItems then
        return items
    end

    for index = 0, wornItems:size() - 1 do
        local item = getWornItemAt(wornItems, index)
        if item and (not predicate or predicate(item)) then
            items[#items + 1] = item
        end
    end

    return items
end

local function queueProtectiveArmorToMannequin(playerObj, mannequin, logger)
    if not canUseMannequinTransfers(playerObj, mannequin) or not walkToMannequin(playerObj, mannequin) then
        logMannequinDebug(logger, "store protective rejected: interaction unavailable")
        return
    end

    local stored = 0
    local wornItems = playerObj:getWornItems()
    for index = 0, wornItems:size() - 1 do
        local item = getWornItemAt(wornItems, index)
        if isProtectiveClothingItem(item) and item:getContainer() then
            ISInventoryPaneContextMenu.unequipItem(item, playerObj:getPlayerNum())
            ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item, item:getContainer(), mannequin:getContainer()))
            stored = stored + 1
            logMannequinDebug(logger, "store protective queued: type=" .. tostring(item:getFullType()))
        end
    end

    logMannequinDebug(logger, "store protective complete: queued=" .. tostring(stored))
end

local function queueProtectiveArmorFromMannequin(playerObj, mannequin, logger)
    if not canUseMannequinTransfers(playerObj, mannequin) or not walkToMannequin(playerObj, mannequin) then
        logMannequinDebug(logger, "wear protective rejected: interaction unavailable")
        return
    end

    local wornItems = getMannequinWornItems(mannequin, isProtectiveClothingItem)
    for index = 1, #wornItems do
        local item = wornItems[index]
        ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
        ISTimedActionQueue.add(ISWearClothing:new(playerObj, item, 50))
        logMannequinDebug(logger, "wear protective queued: type=" .. tostring(item:getFullType()))
    end

    logMannequinDebug(logger, "wear protective complete: queued=" .. tostring(#wornItems))
end

local function queuePresetToMannequin(playerObj, mannequin, presetIndex, logger)
    local canTransfer = canUseMannequinTransfers(playerObj, mannequin)
    local walkedToMannequin = canTransfer and walkToMannequin(playerObj, mannequin)
    if not canTransfer or not walkedToMannequin then
        logMannequinDebug(logger, "put rejected: canTransfer=" .. tostring(canTransfer) .. ", adjacent=" .. tostring(walkedToMannequin))
        return
    end

    local preset = getPresetStore(playerObj)[presetIndex]
    local transferred = 0
    local skipped = 0
    for i = 1, #preset do
        local entry = preset[i]
        local fullType = getEntryFullType(entry)
        local bodyLocation = getMannequinEntryBodyLocation(playerObj, entry)
        local item = isMannequinCompatibleEntry(playerObj, entry) and findPresetItemForMannequin(playerObj, fullType, bodyLocation) or nil
        local sourceContainer = item and item:getContainer() or nil
        if item and sourceContainer then
            if playerObj:isEquipped(item) then
                ISInventoryPaneContextMenu.unequipItem(item, playerObj:getPlayerNum())
            end
            ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item, sourceContainer, mannequin:getContainer()))
            transferred = transferred + 1
            logMannequinDebug(logger, "put queued: type=" .. tostring(fullType) .. ", location=" .. tostring(bodyLocation) .. ", source=" .. tostring(sourceContainer:getType()))
        else
            skipped = skipped + 1
            logMannequinDebug(logger, "put skipped: type=" .. tostring(fullType) .. ", savedLocation=" .. tostring(getEntryBodyLocation(entry)) .. ", resolvedLocation=" .. tostring(bodyLocation) .. ", compatible=" .. tostring(isMannequinCompatibleEntry(playerObj, entry)) .. ", sourceItem=" .. tostring(item ~= nil))
        end
    end

    if logger and logger.debug then
        logger.debug("Equipment preset mannequin put: preset=" .. tostring(presetIndex) .. ", transferred=" .. tostring(transferred) .. ", skipped=" .. tostring(skipped))
    end
end

local function getMannequinPresetAvailability(playerObj, presetIndex, logger)
    local preset = getPresetStore(playerObj)[presetIndex]
    local hasCompatible = false
    local hasPlayerItem = false

    for i = 1, #preset do
        local entry = preset[i]
        local fullType = getEntryFullType(entry)
        local savedBodyLocation = getEntryBodyLocation(entry)
        local bodyLocation = getMannequinEntryBodyLocation(playerObj, entry)
        local compatible = isMannequinCompatibleEntry(playerObj, entry)
        if compatible then
            hasCompatible = true
            local playerItem = findPresetItemForMannequin(playerObj, fullType, bodyLocation)
            hasPlayerItem = hasPlayerItem or playerItem ~= nil
            logMannequinDebug(logger, "availability: preset=" .. tostring(presetIndex) .. ", type=" .. tostring(fullType) .. ", savedLocation=" .. tostring(savedBodyLocation) .. ", resolvedLocation=" .. tostring(bodyLocation) .. ", playerItem=" .. tostring(playerItem ~= nil))
        else
            logMannequinDebug(logger, "availability skipped: preset=" .. tostring(presetIndex) .. ", type=" .. tostring(fullType) .. ", savedLocation=" .. tostring(savedBodyLocation) .. ", resolvedLocation=" .. tostring(bodyLocation))
        end
    end

    logMannequinDebug(logger, "availability summary: preset=" .. tostring(presetIndex) .. ", compatible=" .. tostring(hasCompatible) .. ", playerItem=" .. tostring(hasPlayerItem))
    return hasCompatible, hasPlayerItem
end

local function queueEquipByType(playerObj, fullType, handMode, bodyLocation, logger)
    local item = findInventoryItemByType(playerObj, fullType)
    if not item then
        if logger and logger.debug then
            logger.debug("Equipment preset equip miss: item not found for type=" .. tostring(fullType))
        end
        return false
    end

    local playerNum = playerObj:getPlayerNum()
    local queueBefore = getTimedActionQueueDepth(playerObj)
    if handMode == HAND_MODE_BOTH then
        if isHandModeSatisfied(playerObj, fullType, handMode) then
            return true
        end
        ISInventoryPaneContextMenu.equipWeapon(item, false, true, playerNum)
        if logger and logger.debug then
            logger.debug("Equipment preset equip queued: type=" .. tostring(fullType) .. ", handMode=" .. tostring(handMode) .. ", action=equipWeaponBoth, queueBefore=" .. tostring(queueBefore) .. ", queueAfter=" .. tostring(getTimedActionQueueDepth(playerObj)))
        end
        return true
    elseif handMode == HAND_MODE_SECONDARY then
        if isHandModeSatisfied(playerObj, fullType, handMode) then
            return true
        end
        ISInventoryPaneContextMenu.equipWeapon(item, false, false, playerNum)
        if logger and logger.debug then
            logger.debug("Equipment preset equip queued: type=" .. tostring(fullType) .. ", handMode=" .. tostring(handMode) .. ", action=equipWeaponSecondary, queueBefore=" .. tostring(queueBefore) .. ", queueAfter=" .. tostring(getTimedActionQueueDepth(playerObj)))
        end
        return true
    elseif handMode == HAND_MODE_PRIMARY then
        if isHandModeSatisfied(playerObj, fullType, handMode) then
            return true
        end
        ISInventoryPaneContextMenu.equipWeapon(item, true, false, playerNum)
        if logger and logger.debug then
            logger.debug("Equipment preset equip queued: type=" .. tostring(fullType) .. ", handMode=" .. tostring(handMode) .. ", action=equipWeaponPrimary, queueBefore=" .. tostring(queueBefore) .. ", queueAfter=" .. tostring(getTimedActionQueueDepth(playerObj)))
        end
        return true
    end

    local normalizedBodyLocation = normalizeBodyLocation(bodyLocation)
    if normalizedBodyLocation then
        if isBodyLocationSatisfied(playerObj, fullType, normalizedBodyLocation) then
            return true
        end

        local occupying = getPlayerWornItemAtLocation(playerObj, normalizedBodyLocation)
        if occupying and occupying ~= item then
            ISInventoryPaneContextMenu.unequipItem(occupying, playerNum)
        end

        local extraType = resolveExtraTypeForBodyLocation(item, normalizedBodyLocation)
        if extraType and ISInventoryPaneContextMenu.onClothingItemExtra then
            ISInventoryPaneContextMenu.onClothingItemExtra(item, extraType, playerObj)
            return true
        end

        ISInventoryPaneContextMenu.wearItem(item, playerNum)
        return true
    end

    if playerObj:isEquipped(item) then
        return true
    end

    if isWearableItem(item) then
        ISInventoryPaneContextMenu.wearItem(item, playerNum)
        if logger and logger.debug then
            logger.debug("Equipment preset equip queued: type=" .. tostring(fullType) .. ", handMode=nil, action=wearItem, queueBefore=" .. tostring(queueBefore) .. ", queueAfter=" .. tostring(getTimedActionQueueDepth(playerObj)))
        end
        return true
    end

    ISInventoryPaneContextMenu.equipWeapon(item, true, false, playerNum)
    if logger and logger.debug then
        logger.debug("Equipment preset equip queued: type=" .. tostring(fullType) .. ", handMode=nil, action=equipWeaponPrimaryFallback, queueBefore=" .. tostring(queueBefore) .. ", queueAfter=" .. tostring(getTimedActionQueueDepth(playerObj)))
    end
    return true
end

local function queueUnequipByType(playerObj, fullType, logger)
    local equipped = findWornItemByType(playerObj, fullType)
    if not equipped then
        return false
    end

    local queueBefore = getTimedActionQueueDepth(playerObj)
    ISInventoryPaneContextMenu.unequipItem(equipped, playerObj:getPlayerNum())
    if logger and logger.debug then
        logger.debug("Equipment preset unequip queued: type=" .. tostring(fullType) .. ", queueBefore=" .. tostring(queueBefore) .. ", queueAfter=" .. tostring(getTimedActionQueueDepth(playerObj)))
    end
    return true
end

local function evaluatePresetState(playerObj, presetIndex)
    local hasAny = false
    local total = 0
    local equipped = 0
    local allEquipped = true

    forEachPresetItem(playerObj, presetIndex, function(entry)
        hasAny = true
        total = total + 1
        if not isPresetEntryEquipped(playerObj, entry) then
            allEquipped = false
        else
            equipped = equipped + 1
        end
    end)

    return {
        hasAny = hasAny,
        total = total,
        equipped = equipped,
        allEquipped = allEquipped,
    }
end

local function shouldUnequipPreset(playerObj, presetIndex)
    local state = evaluatePresetState(playerObj, presetIndex)

    if not state.hasAny then
        return false
    end
    return state.allEquipped
end

local function togglePreset(playerObj, presetIndex, logger)
    local store = getPresetStore(playerObj)
    local preset = store[presetIndex]
    if #preset == 0 then
        logger.debug("Equipment preset " .. tostring(presetIndex) .. " is empty")
        return
    end

    local state = evaluatePresetState(playerObj, presetIndex)
    local unequip = state.hasAny and (state.allEquipped or isPresetMarkedEquipped(playerObj, presetIndex))
    if logger and logger.debug then
        logger.debug("Equipment preset " .. tostring(presetIndex) .. " state: total=" .. tostring(state.total) .. ", equipped=" .. tostring(state.equipped) .. ", allEquipped=" .. tostring(state.allEquipped) .. ", mode=" .. (unequip and "unequip" or "equip"))
    end
    local changed = 0
    local missingOnEquip = 0

    for i = 1, #preset do
        local entry = preset[i]
        local fullType = getEntryFullType(entry)
        if fullType and fullType ~= "" then
            local handMode = getEntryHandMode(entry)
            local bodyLocation = getEntryBodyLocation(entry)
            local ok = false
            if unequip then
                ok = queueUnequipByType(playerObj, fullType, logger)
            else
                ok = queueEquipByType(playerObj, fullType, handMode, bodyLocation, logger)
            end
            if ok then
                changed = changed + 1
            elseif not unequip then
                missingOnEquip = missingOnEquip + 1
                logger.debug("Equipment preset " .. tostring(presetIndex) .. " equip miss: type=" .. tostring(fullType) .. ", handMode=" .. tostring(handMode))
            end
        end
    end

    if unequip then
        setPresetMarkedEquipped(playerObj, presetIndex, false)
    elseif missingOnEquip > 0 then
        -- Missing inventory items should still let the next toggle act as unequip.
        setPresetMarkedEquipped(playerObj, presetIndex, true)
    else
        setPresetMarkedEquipped(playerObj, presetIndex, false)
    end

    logger.debug("Equipment preset " .. tostring(presetIndex) .. " toggled; mode=" .. (unequip and "unequip" or "equip") .. ", actions=" .. tostring(changed))
end

local onMannequinContext

local function onInventoryContext(playerIndex, context, items, settings, logger)
    if settings.isEnabled("QoLforSacriel_EnableEquipment") ~= true then
        return
    end
    if settings.get("QoLforSacriel_Equipment_EnablePresets") ~= true then
        return
    end

    local playerObj = getSpecificPlayer(playerIndex)
    if not playerObj or not context then
        return
    end

    local actualItems = resolveActualItems(items)
    if #actualItems == 0 then
        return
    end

    local selectedEntries = collectSelectedEntries(actualItems, playerObj)
    if settings.get("QoLforSacriel_DebugLogs") == true and logger and logger.debug then
        logger.debug("Equipment preset inventory classification: selected=" .. tostring(#actualItems) .. ", eligible=" .. tostring(#selectedEntries))
    end
    if #selectedEntries == 0 then
        return
    end

    local menuOption = context:addOption(getPresetMenuLabel())
    local subMenu = context:getNew(context)
    context:addSubMenu(menuOption, subMenu)

    local presetCount = getConfiguredPresetCount(settings)

    for i = 1, presetCount do
        local presetOption = subMenu:addOption(getPresetEntryLabel(i, settings))
        local presetSubMenu = context:getNew(context)
        context:addSubMenu(presetOption, presetSubMenu)

        local addOption = presetSubMenu:addOption(getAddToThisPresetLabel(), playerObj, function(p, presetIndex, entries)
            addSelectionToPreset(p, presetIndex, entries)
            closeContextMenu(context)
        end, i, selectedEntries)
        attachOptionTooltip(addOption, buildAssignPresetTooltip(playerObj, i, selectedEntries))

        local toggleOption = presetSubMenu:addOption(getTogglePresetShortLabel(), playerObj, function(p, presetIndex)
            togglePreset(p, presetIndex, logger)
            closeContextMenu(context)
        end, i)
        attachOptionTooltip(toggleOption, getTogglePresetTooltip(i, settings))

        local addAllCurrentOption = presetSubMenu:addOption(getAddAllCurrentProtectiveLabel(), playerObj, function(p, presetIndex)
            replacePresetWithCurrentProtective(p, presetIndex)
            closeContextMenu(context)
        end, i)
        attachOptionTooltip(addAllCurrentOption, getAddAllCurrentProtectiveTooltip())

        presetSubMenu:addOption(getClearPresetShortLabel(), playerObj, function(p, presetIndex)
            clearPreset(p, presetIndex)
            closeContextMenu(context)
        end, i)
    end
end

onMannequinContext = function(playerObj, context, mannequin, settings, logger, source)
    local canTransfer = canUseMannequinTransfers(playerObj, mannequin)
    local mannequinHasProtectiveArmor = #getMannequinWornItems(mannequin, isProtectiveClothingItem) > 0
    if settings.get("QoLforSacriel_DebugLogs") == true then
        logMannequinDebug(logger, "menu opened: source=" .. tostring(source) .. ", canTransfer=" .. tostring(canTransfer) .. ", dead=" .. tostring(playerObj:isDead()) .. ", vehicle=" .. tostring(playerObj:getVehicle() ~= nil) .. ", mannequinHasProtectiveArmor=" .. tostring(mannequinHasProtectiveArmor))
    end

    local armorLabel = mannequinHasProtectiveArmor and getWearProtectiveArmorLabel() or getStoreProtectiveArmorLabel()
    local armorOption = context:addOption(armorLabel, playerObj, function(player, target, hasProtectiveArmor)
        if hasProtectiveArmor then
            queueProtectiveArmorFromMannequin(player, target, logger)
        else
            queueProtectiveArmorToMannequin(player, target, logger)
        end
        closeContextMenu(context)
    end, mannequin, mannequinHasProtectiveArmor)
    if not canTransfer then
        armorOption.notAvailable = true
        attachOptionTooltip(armorOption, getMannequinUnavailableTooltip("interaction"))
    end

    local menuOption = context:addOption(getPresetMenuLabel())
    local subMenu = context:getNew(context)
    context:addSubMenu(menuOption, subMenu)

    for i = 1, getConfiguredPresetCount(settings) do
        local presetOption = subMenu:addOption(getPresetEntryLabel(i, settings))
        local presetSubMenu = context:getNew(context)
        context:addSubMenu(presetOption, presetSubMenu)
        local hasCompatible, hasPlayerItem = getMannequinPresetAvailability(playerObj, i, settings.get("QoLforSacriel_DebugLogs") == true and logger or nil)

        local putOption = presetSubMenu:addOption(getAddPresetToMannequinLabel(), playerObj, function(player, target, presetIndex)
            queuePresetToMannequin(player, target, presetIndex, logger)
            closeContextMenu(context)
        end, mannequin, i)
        if not canTransfer or not hasCompatible or not hasPlayerItem then
            putOption.notAvailable = true
            attachOptionTooltip(putOption, getMannequinUnavailableTooltip(not canTransfer and "interaction" or (not hasCompatible and "compatible" or "playerItem")))
        end
    end
end

local function onWorldObjectContext(playerIndex, context, worldobjects, test, settings, logger)
    if test or settings.isEnabled("QoLforSacriel_EnableEquipment") ~= true
        or settings.get("QoLforSacriel_Equipment_EnablePresets") ~= true
        or settings.get("QoLforSacriel_Equipment_EnableMannequinMenu") ~= true
    then
        return
    end

    local playerObj = getSpecificPlayer(playerIndex)
    local mannequin = resolveMannequin(worldobjects)
    if not playerObj or not mannequin then
        if settings.get("QoLforSacriel_DebugLogs") == true then
            logMannequinDebug(logger, "menu skipped: player=" .. tostring(playerObj ~= nil) .. ", mannequin=" .. tostring(mannequin ~= nil) .. ", worldObjects=" .. tostring(worldobjects and #worldobjects or 0))
        end
        return
    end

    onMannequinContext(playerObj, context, mannequin, settings, logger, "world")
end

local function getPresetIndexFromKey(key, settings, logger)
    refreshHotkeyCache(settings, logger)

    local core = getCore and getCore()
    if not core or not core.isKey then
        return nil, hotkeyCachePresetCount
    end

    for i = 1, hotkeyCachePresetCount do
        local ok, matched = pcall(core.isKey, core, getPresetBindingName(i), key)
        if ok and matched == true then
            local expectedCtrl, expectedShift, expectedAlt = getExpectedModifierState(i)
            if isModifierStateMatched(expectedCtrl, expectedShift, expectedAlt) then
                return i, hotkeyCachePresetCount
            end
        end
    end

    return nil, hotkeyCachePresetCount
end

local function onKeyStartPressed(key, settings, logger)
    if settings.isEnabled("QoLforSacriel_EnableEquipment") ~= true then
        return
    end
    if settings.get("QoLforSacriel_Equipment_EnablePresets") ~= true then
        return
    end

    local presetIndex = getPresetIndexFromKey(key, settings, logger)
    if not presetIndex then
        return
    end

    if logger and logger.debug then
        logger.debug("Equipment preset toggle detected: pressed=" .. getPressedComboText(key) .. ", preset=" .. tostring(presetIndex) .. ", configured=" .. getConfiguredBindingComboText(settings, presetIndex))
    end

    local expectedCtrl, expectedShift, expectedAlt = getExpectedModifierState(presetIndex)

    pendingHotkeyToggle = {
        presetIndex = presetIndex,
        waitModifierRelease = (expectedCtrl or expectedShift or expectedAlt) == true,
    }
    pendingHotkeyWaitLogged = false
end

local function onTick(settings, logger)
    local pending = pendingHotkeyToggle
    if not pending then
        return
    end

    if settings.isEnabled("QoLforSacriel_EnableEquipment") ~= true
        or settings.get("QoLforSacriel_Equipment_EnablePresets") ~= true
    then
        pendingHotkeyToggle = nil
        pendingHotkeyWaitLogged = false
        return
    end

    pendingHotkeyToggle = nil

    local playerObj = getSpecificPlayer(0)
    if not playerObj or playerObj:isDead() then
        return
    end

    if pending.waitModifierRelease and areAnyModifierKeysDown() then
        if not pendingHotkeyWaitLogged and logger and logger.debug then
            logger.debug("Equipment preset hotkey pending until modifiers are released: preset=" .. tostring(pending.presetIndex))
            pendingHotkeyWaitLogged = true
        end
        pendingHotkeyToggle = pending
        return
    end

    pendingHotkeyWaitLogged = false

    togglePreset(playerObj, pending.presetIndex, logger)
end

function EquipmentPresets.init(settings, logger)
    if installed then
        logger.debug("Equipment.Presets already installed")
        return
    end

    Events.OnFillInventoryObjectContextMenu.Add(function(playerIndex, context, items)
        local ok, err = pcall(function()
            onInventoryContext(playerIndex, context, items, settings, logger)
        end)
        if not ok then
            logger.error("Equipment.Presets context error: " .. tostring(err))
        end
    end)

    Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldobjects, test)
        local ok, err = pcall(function()
            onWorldObjectContext(playerIndex, context, worldobjects, test, settings, logger)
        end)
        if not ok then
            logger.error("Equipment.Presets mannequin context error: " .. tostring(err))
        end
    end)

    Events.OnKeyStartPressed.Add(function(key)
        local ok, err = pcall(function()
            onKeyStartPressed(key, settings, logger)
        end)
        if not ok then
            logger.error("Equipment.Presets key error: " .. tostring(err))
        end
    end)

    Events.OnTick.Add(function()
        local ok, err = pcall(function()
            onTick(settings, logger)
        end)
        if not ok then
            logger.error("Equipment.Presets tick error: " .. tostring(err))
        end
    end)

    installed = true
    logger.info("Equipment.Presets installed")
end

return EquipmentPresets
