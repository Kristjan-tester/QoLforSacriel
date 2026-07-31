local EquipmentPresets = {}

local installed = false
local MAX_PRESET_COUNT = 8
local MOD_DATA_KEY = "QoLforSacriel_EquipmentPresets"

local function getConfiguredPresetCount(settings)
    local count = tonumber(settings.get("QoLforSacriel_Equipment_PresetCount")) or 3
    return math.max(1, math.min(MAX_PRESET_COUNT, math.floor(count)))
end

local function getPresetMenuLabel()
    return getTextOrNull("UI_QoLforSacriel_EquipmentPresets") or "Equipment Presets"
end

local function getAssignPresetLabel(index)
    local key = "UI_QoLforSacriel_EquipmentAssignPreset" .. tostring(index)
    return getTextOrNull(key) or ("Add to Preset " .. tostring(index))
end

local function getTogglePresetLabel(index)
    local key = "UI_QoLforSacriel_EquipmentTogglePreset" .. tostring(index)
    return getTextOrNull(key) or ("Toggle Preset " .. tostring(index) .. " (Ctrl+F" .. tostring(index) .. ")")
end

local function getClearPresetLabel(index)
    local key = "UI_QoLforSacriel_EquipmentClearPreset" .. tostring(index)
    return getTextOrNull(key) or ("Clear Preset " .. tostring(index))
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

local function containsValue(list, value)
    for i = 1, #list do
        if list[i] == value then
            return true
        end
    end
    return false
end

local function addTypeToPreset(playerObj, presetIndex, fullType)
    local store = getPresetStore(playerObj)
    local preset = store[presetIndex]
    if not containsValue(preset, fullType) then
        table.insert(preset, fullType)
    end
end

local function clearPreset(playerObj, presetIndex)
    local store = getPresetStore(playerObj)
    store[presetIndex] = {}
end

local function collectSelectedTypes(items)
    local selectedTypes = {}
    local seen = {}

    for i = 1, #items do
        local item = items[i]
        if item and item.getFullType then
            local fullType = item:getFullType()
            if fullType and not seen[fullType] then
                table.insert(selectedTypes, fullType)
                seen[fullType] = true
            end
        end
    end

    return selectedTypes
end

local function addSelectionToPreset(playerObj, presetIndex, selectedTypes)
    for i = 1, #selectedTypes do
        addTypeToPreset(playerObj, presetIndex, selectedTypes[i])
    end
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
        table.insert(presetNames, getDisplayNameForType(preset[i]))
    end

    local selectedNames = {}
    local alreadyInPreset = {}
    local willAdd = {}

    for i = 1, #selectedTypes do
        local fullType = selectedTypes[i]
        local name = getDisplayNameForType(fullType)
        table.insert(selectedNames, name)

        if containsValue(preset, fullType) then
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
    for i = 1, wornItems:size() do
        local entry = wornItems:get(i - 1)
        local item = entry and entry:getItem() or nil
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

local function isTypeEquipped(playerObj, fullType)
    return findWornItemByType(playerObj, fullType) ~= nil
end

local function queueEquipByType(playerObj, fullType)
    local item = playerObj:getInventory():getFirstTypeRecurse(fullType)
    if not item then
        return false
    end

    if playerObj:isEquipped(item) then
        return true
    end

    local playerNum = playerObj:getPlayerNum()
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

    forEachPresetItem(playerObj, presetIndex, function(fullType)
        hasAny = true
        if not isTypeEquipped(playerObj, fullType) then
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
        local fullType = preset[i]
        local ok = false
        if unequip then
            ok = queueUnequipByType(playerObj, fullType)
        else
            ok = queueEquipByType(playerObj, fullType)
        end
        if ok then
            changed = changed + 1
        end
    end

    logger.debug("Equipment preset " .. tostring(presetIndex) .. " toggled; mode=" .. (unequip and "unequip" or "equip") .. ", actions=" .. tostring(changed))
end

local function onInventoryContext(playerIndex, context, items, settings, logger)
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

    local selectedTypes = collectSelectedTypes(actualItems)
    if #selectedTypes == 0 then
        return
    end

    local menuOption = context:addOption(getPresetMenuLabel())
    local subMenu = context:getNew(context)
    context:addSubMenu(menuOption, subMenu)

    local presetCount = getConfiguredPresetCount(settings)

    for i = 1, presetCount do
        local addOption = subMenu:addOption(getAssignPresetLabel(i), playerObj, function(p, presetIndex, types)
            addSelectionToPreset(p, presetIndex, types)
        end, i, selectedTypes)
        attachOptionTooltip(addOption, buildAssignPresetTooltip(playerObj, i, selectedTypes))

        subMenu:addOption(getTogglePresetLabel(i), playerObj, function(p, presetIndex)
            togglePreset(p, presetIndex, logger)
        end, i)

        subMenu:addOption(getClearPresetLabel(i), playerObj, function(p, presetIndex)
            clearPreset(p, presetIndex)
        end, i)
    end
end

local function getPresetIndexFromKey(key)
    if key == Keyboard.KEY_F1 then return 1 end
    if key == Keyboard.KEY_F2 then return 2 end
    if key == Keyboard.KEY_F3 then return 3 end
    if key == Keyboard.KEY_F4 then return 4 end
    if key == Keyboard.KEY_F5 then return 5 end
    if key == Keyboard.KEY_F6 then return 6 end
    if key == Keyboard.KEY_F7 then return 7 end
    if key == Keyboard.KEY_F8 then return 8 end
    return nil
end

local function onKeyPressed(key, settings, logger)
    if settings.get("QoLforSacriel_Equipment_EnablePresets") ~= true then
        return
    end

    if not isCtrlKeyDown() then
        return
    end

    local presetIndex = getPresetIndexFromKey(key)
    if not presetIndex then
        return
    end

    if presetIndex > getConfiguredPresetCount(settings) then
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

    Events.OnKeyPressed.Add(function(key)
        local ok, err = pcall(function()
            onKeyPressed(key, settings, logger)
        end)
        if not ok then
            logger.error("Equipment.Presets key error: " .. tostring(err))
        end
    end)

    installed = true
    logger.info("Equipment.Presets installed")
end

return EquipmentPresets
