-- ff-assisted
require "TimedActions/ISPickUpGroundCoverItem"
require "TimedActions/ISEquipWeaponAction"

local GroundCoverRemovalMenu = {}

local installed = false
local settingsRef = nil
local loggerRef = nil

local ITEM_TYPE_BY_CUSTOM_NAME = {
    FlatStone = "Base.FlatStone",
    Log = "Base.Log",
    TreeBranch2 = "Base.TreeBranch2",
    LargeStone = "Base.LargeStone",
    LargeStoneTwigs = "Base.LargeStone",
}

local ITEM_TYPE_BY_SPRITE_NAME = {
    d_generic_1_23 = "Base.FlatStone",
}

local GroundCoverPickupEquipAction = ISPickUpGroundCoverItem:derive("QoLforSacriel_GroundCoverPickupEquipAction")

local function getTextOrFallback(key, fallback)
    if getTextOrNull then
        local translated = getTextOrNull(key)
        if translated and translated ~= "" then
            return translated
        end
    end
    return fallback
end

local function logDebug(message)
    if settingsRef
        and settingsRef.get
        and settingsRef.get("QoLforSacriel_DebugLogs") == true
        and loggerRef
        and loggerRef.debug
    then
        loggerRef.debug("UIFixes.GroundCoverRemovalMenu: " .. tostring(message))
    end
end

local function isEnabled()
    return settingsRef
        and settingsRef.isEnabled
        and settingsRef.isEnabled("QoLforSacriel_EnableUIFixes") == true
        and settingsRef.isEnabled("QoLforSacriel_UIFixes_EnableGroundCoverRemovalMenu") == true
end

local function describeObject(object)
    local sprite = object and object.getSprite and object:getSprite() or nil
    local spriteName = sprite and sprite.getName and sprite:getName() or "none"
    local properties = sprite and sprite.getProperties and sprite:getProperties() or nil
    local customName = properties and properties:has("CustomName") and properties:get("CustomName") or "none"
    return "customName=" .. tostring(customName) .. " | sprite=" .. tostring(spriteName)
end

local function resolveItemType(object)
    if not object or not object.getSprite then
        return nil
    end

    local sprite = object:getSprite()
    local spriteName = sprite and sprite:getName() or nil
    if spriteName and ITEM_TYPE_BY_SPRITE_NAME[spriteName] then
        return ITEM_TYPE_BY_SPRITE_NAME[spriteName]
    end
    local properties = sprite and sprite:getProperties() or nil
    if not properties or not properties:has("CustomName") then
        return nil
    end

    return ITEM_TYPE_BY_CUSTOM_NAME[properties:get("CustomName")]
end

local function canFitInInventory(playerObj, itemType)
    if not playerObj or not itemType then
        return false
    end

    local inventory = playerObj:getInventory()
    local item = instanceItem(itemType)
    return inventory and item and inventory:hasRoomFor(playerObj, item) == true
end

function GroundCoverPickupEquipAction:complete()
    local itemType = resolveItemType(self.object)
    local inventory = self.character and self.character:getInventory() or nil
    local square = self.object and self.object:getSquare() or nil
    if not itemType
        or not inventory
        or not square
        or not square:getObjects():contains(self.object)
    then
        logDebug("equip pickup refused because the ground cover is no longer available")
        return false
    end

    local item = instanceItem(itemType)
    if not item or not inventory:hasRoomFor(self.character, item) then
        logDebug("equip pickup refused because inventory capacity changed for " .. tostring(itemType))
        return false
    end

    inventory:AddItem(item)
    sendAddItemToContainer(inventory, item)
    square:transmitRemoveItemFromSquare(self.object)

    local equipAction = ISEquipWeaponAction:new(self.character, item, 50, true, false, false)
    if ISTimedActionQueue and ISTimedActionQueue.add and equipAction then
        ISTimedActionQueue.add(equipAction)
        logDebug("equip pickup completed and equip action queued for " .. tostring(itemType) .. " id=" .. tostring(item:getID()))
    else
        logDebug("equip pickup completed but equip queue was unavailable for " .. tostring(itemType))
    end

    return true
end

function GroundCoverPickupEquipAction:new(character, square, object)
    return ISPickUpGroundCoverItem.new(self, character, square, object)
end

local function queueInventoryPickup(worldobjects, playerIndex, object)
    if ISWorldObjectContextMenu and ISWorldObjectContextMenu.onPickupGroundCoverItem then
        ISWorldObjectContextMenu.onPickupGroundCoverItem(worldobjects, playerIndex, object)
        logDebug("queued inventory pickup for " .. tostring(resolveItemType(object)))
    end
end

local function queueEquipPickup(playerIndex, object)
    local playerObj = getSpecificPlayer(playerIndex)
    if not playerObj or not object or not object:getSquare() then
        return
    end

    local itemType = resolveItemType(object)
    if not canFitInInventory(playerObj, itemType) then
        logDebug("equip pickup refused due to inventory capacity for " .. tostring(itemType))
        return
    end

    if luautils.walkAdj(playerObj, object:getSquare()) then
        ISTimedActionQueue.add(GroundCoverPickupEquipAction:new(playerObj, object:getSquare(), object))
        logDebug("queued equip pickup for " .. tostring(itemType))
    end
end

local function optionTargetsObject(option, object)
    if not option then
        return false
    end

    if option.onSelect == ISWorldObjectContextMenu.onPickupGroundCoverItem then
        if option.target == object then
            return true
        end
        for index = 1, 10 do
            if option["param" .. tostring(index)] == object then
                return true
            end
        end
    end

    return option.param1 == ISWorldObjectContextMenu.onPickupGroundCoverItem
        and option.param5 == object
end

local function removalOptionMatchesItem(option, itemType)
    local item = itemType and instanceItem(itemType) or nil
    local displayName = item and item.getDisplayName and item:getDisplayName() or nil
    local optionName = option and option.name or nil
    if not displayName or not optionName or option.subOption then
        return false
    end

    return string.find(string.lower(tostring(optionName)), string.lower(tostring(displayName)), 1, true) ~= nil
        and string.find(string.lower(tostring(optionName)), "remove", 1, true) ~= nil
end

local function findPickupOption(menu, object, itemType, path)
    if not menu or not menu.options then
        return nil, nil
    end

    for _, option in ipairs(menu.options) do
        if optionTargetsObject(option, object) or removalOptionMatchesItem(option, itemType) then
            return menu, option
        end
        if option.subOption and menu.getSubMenu then
            local childMenu = menu:getSubMenu(option.subOption)
            local childPath = path .. " > " .. tostring(option.name)
            local owner, childOption = findPickupOption(childMenu, object, itemType, childPath)
            if owner and childOption then
                return owner, childOption
            end
        end
    end

    return nil, nil
end

local function addDisabledEquipOption(subMenu)
    local option = subMenu:addOption(getTextOrFallback("UI_QoLforSacriel_GroundCoverRemoval_EquipPrimary", "Equip in primary"))
    option.notAvailable = true
    option.toolTip = ISToolTip:new()
    option.toolTip:initialise()
    option.toolTip:setVisible(false)
    option.toolTip.description = getTextOrFallback("UI_QoLforSacriel_GroundCoverRemoval_InventoryFull", "No room in inventory.")
end

local function replacePickupOption(context, option, worldobjects, playerIndex, object, itemType)
    option.onSelect = nil
    option.target = nil
    for index = 1, 10 do
        option["param" .. tostring(index)] = nil
    end

    local subMenu = context:getNew(context)
    context:addSubMenu(option, subMenu)
    subMenu:addGetUpOption(getTextOrFallback("UI_QoLforSacriel_GroundCoverRemoval_PutInInventory", "Put in inventory"), worldobjects, queueInventoryPickup, playerIndex, object)

    local playerObj = getSpecificPlayer(playerIndex)
    if canFitInInventory(playerObj, itemType) then
        subMenu:addGetUpOption(getTextOrFallback("UI_QoLforSacriel_GroundCoverRemoval_EquipPrimary", "Equip in primary"), playerIndex, queueEquipPickup, object)
    else
        addDisabledEquipOption(subMenu)
    end

    logDebug("replaced pickup menu option for " .. tostring(itemType))
end

local function installMenuHook()
    Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldobjects, test)
        if not isEnabled() or not context or not worldobjects then
            return
        end

        local selected = {}
        for _, object in ipairs(worldobjects) do
            local itemType = resolveItemType(object)
            if itemType then
                logDebug("ground-cover target accepted: " .. tostring(itemType) .. " | " .. describeObject(object))
                selected[#selected + 1] = { object = object, itemType = itemType }
            else
                logDebug("ground-cover target ignored: " .. describeObject(object))
            end
        end
        if #selected == 0 then
            logDebug("world menu had no supported ground-cover targets")
            return
        end
        if test then
            logDebug("world menu test detected " .. tostring(#selected) .. " supported ground-cover target(s)")
            return true
        end

        logDebug(string.format(
            "world menu detected: objects=%d | options=%d | supportedTargets=%d",
            #worldobjects, #context.options, #selected
        ))

        for _, candidate in ipairs(selected) do
            local ownerMenu, option = findPickupOption(context, candidate.object, candidate.itemType, "root")
            if ownerMenu and option then
                replacePickupOption(ownerMenu, option, worldobjects, playerIndex, candidate.object, candidate.itemType)
                logDebug("replaced pickup menu option for " .. tostring(candidate.itemType) .. " in nested menu")
            else
                logDebug("ground-cover target had no matching vanilla pickup option: " .. tostring(candidate.itemType) .. " | " .. describeObject(candidate.object))
            end
        end
    end)
end

function GroundCoverRemovalMenu.init(settings, logger)
    if installed then
        return
    end

    settingsRef = settings
    loggerRef = logger
    installMenuHook()
    installed = true
end

return GroundCoverRemovalMenu