local EquipmentPresets = {}

local installed = false
local MAX_PRESET_COUNT = 8
local MOD_DATA_KEY = "QoLforSacriel_EquipmentPresets"
local HAND_MODE_PRIMARY = "primary"
local HAND_MODE_SECONDARY = "secondary"
local HAND_MODE_BOTH = "both"
local HOTKEY_NONE_TOKEN = "NONE"
local MOD_OPTIONS_ID = "QoLforSacriel.Modules"

local HOTKEY_SETTING_PREFIX = "QoLforSacriel_Equipment_PresetHotkey"

local hotkeyCacheSignature = nil
local hotkeyCacheMap = {}
local hotkeyCachePresetCount = 0
local getConfiguredPresetCount
local getConfiguredHotkeyBinding

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

local function isKeyAndModifiersMatched(index, key, settings)
    local keyCode = getConfiguredHotkeyBinding(settings, index)
    if not keyCode or key ~= keyCode then
        return false
    end

    local expectedCtrl, expectedShift, expectedAlt = getExpectedModifierState(index)
    local ctrlDown = isModifierDown("isCtrlKeyDown")
    local shiftDown = isModifierDown("isShiftKeyDown")
    local altDown = isModifierDown("isAltKeyDown")

    return ctrlDown == expectedCtrl
        and shiftDown == expectedShift
        and altDown == expectedAlt
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
    if value == nil then
        local defaultToken = getDefaultHotkeyToken(index)
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
        local defaultToken = getDefaultHotkeyToken(index)
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
    hotkeyCachePresetCount = presetCount

    for i = 1, presetCount do
        local keyCode, token = getConfiguredHotkeyBinding(settings, i)
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

local function createPresetEntry(fullType, handMode)
    if not handMode then
        return fullType
    end

    return {
        fullType = fullType,
        handMode = handMode,
    }
end

getConfiguredPresetCount = function(settings)
    local count = tonumber(settings.get("QoLforSacriel_Equipment_PresetCount")) or 3
    return math.max(1, math.min(MAX_PRESET_COUNT, math.floor(count)))
end

local function getPresetMenuLabel()
    return getTextOrNull("UI_QoLforSacriel_EquipmentPresets") or "Equipment Presets"
end

local function getPresetEntryLabel(index)
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

        if incomingMode and incomingMode ~= existingMode then
            preset[existingIndex] = createPresetEntry(fullType, incomingMode)
        elseif type(preset[existingIndex]) ~= "table" and incomingMode then
            preset[existingIndex] = createPresetEntry(fullType, incomingMode)
        end
        return
    end

    table.insert(preset, entry)
end

local function clearPreset(playerObj, presetIndex)
    local store = getPresetStore(playerObj)
    store[presetIndex] = {}
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

local function collectSelectedEntries(items, playerObj)
    local selectedEntries = {}
    local seen = {}

    for i = 1, #items do
        local item = items[i]
        if item and item.getFullType then
            local fullType = item:getFullType()
            if fullType then
                local handMode = detectCurrentHandMode(playerObj, item)
                if not seen[fullType] then
                    table.insert(selectedEntries, createPresetEntry(fullType, handMode))
                    seen[fullType] = {
                        index = #selectedEntries,
                        handMode = handMode,
                    }
                elseif handMode and not seen[fullType].handMode then
                    selectedEntries[seen[fullType].index] = createPresetEntry(fullType, handMode)
                    seen[fullType].handMode = handMode
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

local function isWeaponCategoryItem(item)
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
            table.insert(selectedEntries, createPresetEntry(fullType, handMode))
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

local function isPresetEntryEquipped(playerObj, entry)
    local fullType = getEntryFullType(entry)
    if not fullType then
        return false
    end

    local handMode = getEntryHandMode(entry)
    if handMode then
        return isHandModeSatisfied(playerObj, fullType, handMode)
    end
    return isTypeEquipped(playerObj, fullType)
end

local function queueEquipByType(playerObj, fullType, handMode)
    local item = playerObj:getInventory():getFirstTypeRecurse(fullType)
    if not item then
        return false
    end

    local playerNum = playerObj:getPlayerNum()
    if handMode == HAND_MODE_BOTH then
        if isHandModeSatisfied(playerObj, fullType, handMode) then
            return true
        end
        ISInventoryPaneContextMenu.equipWeapon(item, false, true, playerNum)
        return true
    elseif handMode == HAND_MODE_SECONDARY then
        if isHandModeSatisfied(playerObj, fullType, handMode) then
            return true
        end
        ISInventoryPaneContextMenu.equipWeapon(item, false, false, playerNum)
        return true
    elseif handMode == HAND_MODE_PRIMARY then
        if isHandModeSatisfied(playerObj, fullType, handMode) then
            return true
        end
        ISInventoryPaneContextMenu.equipWeapon(item, true, false, playerNum)
        return true
    end

    if playerObj:isEquipped(item) then
        return true
    end

    if item:hasTag(ItemTag.WEARABLE) or item:getCategory() == "Clothing" then
        ISInventoryPaneContextMenu.wearItem(item, playerNum)
        return true
    end

    ISInventoryPaneContextMenu.equipWeapon(item, true, false, playerNum)
    return true
end

local function queueUnequipByType(playerObj, fullType)
    local equipped = findWornItemByType(playerObj, fullType)
    if not equipped then
        return false
    end

    ISInventoryPaneContextMenu.unequipItem(equipped, playerObj:getPlayerNum())
    return true
end

local function shouldUnequipPreset(playerObj, presetIndex)
    local hasAny = false
    local allEquipped = true

    forEachPresetItem(playerObj, presetIndex, function(entry)
        hasAny = true
        if not isPresetEntryEquipped(playerObj, entry) then
            allEquipped = false
        end
    end)

    if not hasAny then
        return false
    end
    return allEquipped
end

local function togglePreset(playerObj, presetIndex, logger)
    local store = getPresetStore(playerObj)
    local preset = store[presetIndex]
    if #preset == 0 then
        logger.debug("Equipment preset " .. tostring(presetIndex) .. " is empty")
        return
    end

    local unequip = shouldUnequipPreset(playerObj, presetIndex)
    local changed = 0

    for i = 1, #preset do
        local entry = preset[i]
        local fullType = getEntryFullType(entry)
        if fullType and fullType ~= "" then
            local handMode = getEntryHandMode(entry)
            local ok = false
            if unequip then
                ok = queueUnequipByType(playerObj, fullType)
            else
                ok = queueEquipByType(playerObj, fullType, handMode)
            end
            if ok then
                changed = changed + 1
            end
        end
    end

    logger.debug("Equipment preset " .. tostring(presetIndex) .. " toggled; mode=" .. (unequip and "unequip" or "equip") .. ", actions=" .. tostring(changed))
end

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
    if #selectedEntries == 0 then
        return
    end

    local menuOption = context:addOption(getPresetMenuLabel())
    local subMenu = context:getNew(context)
    context:addSubMenu(menuOption, subMenu)

    local presetCount = getConfiguredPresetCount(settings)

    for i = 1, presetCount do
        local presetOption = subMenu:addOption(getPresetEntryLabel(i))
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

local function getPresetIndexFromKey(key, settings, logger)
    refreshHotkeyCache(settings, logger)

    local core = getCore and getCore()
    if core and core.isKey then
        for i = 1, hotkeyCachePresetCount do
            if core:isKey(getPresetBindingName(i), key) then
                return i, hotkeyCachePresetCount
            end
        end
    end

    for i = 1, hotkeyCachePresetCount do
        if isKeyAndModifiersMatched(i, key, settings) then
            return i, hotkeyCachePresetCount
        end
    end

    return hotkeyCacheMap[key], hotkeyCachePresetCount
end

local function onKeyStartPressed(key, settings, logger)
    if settings.isEnabled("QoLforSacriel_EnableEquipment") ~= true then
        return
    end
    if settings.get("QoLforSacriel_Equipment_EnablePresets") ~= true then
        return
    end

    local presetIndex, presetCount = getPresetIndexFromKey(key, settings, logger)
    if not presetIndex then
        return
    end

    if presetIndex > presetCount then
        return
    end

    local playerObj = getSpecificPlayer(0)
    if not playerObj or playerObj:isDead() then
        return
    end

    togglePreset(playerObj, presetIndex, logger)
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

    Events.OnKeyStartPressed.Add(function(key)
        local ok, err = pcall(function()
            onKeyStartPressed(key, settings, logger)
        end)
        if not ok then
            logger.error("Equipment.Presets key error: " .. tostring(err))
        end
    end)

    installed = true
    logger.info("Equipment.Presets installed")
end

return EquipmentPresets
