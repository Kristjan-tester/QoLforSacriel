-- ff-assisted
local HeldItemContainerMenu = {}

local installed = false
local patched = false
local settingsRef = nil
local loggerRef = nil
local originalCreateMenu = nil

local function logDebug(message)
    if settingsRef
        and settingsRef.get
        and settingsRef.get("QoLforSacriel_DebugLogs") == true
        and loggerRef
        and loggerRef.debug
    then
        loggerRef.debug("UIFixes.HeldItemContainerMenu: " .. tostring(message))
    end
end

local function isEnabled()
    return settingsRef
        and settingsRef.isEnabled
        and settingsRef.isEnabled("QoLforSacriel_EnableUIFixes") == true
        and settingsRef.get
        and settingsRef.get("QoLforSacriel_UIFixes_EnableHeldItemPutInContainer") == true
end

local function getTextOrFallback(key, fallback)
    if getTextOrNull then
        local translated = getTextOrNull(key)
        if translated and translated ~= "" then
            return translated
        end
    end
    return fallback
end

local function getSelectedItem(items)
    if type(items) ~= "table" or not items[1] then
        return nil
    end
    local selected = items[1]
    if instanceof(selected, "InventoryItem") then
        return selected
    end
    return selected.items and selected.items[1] or nil
end

local function isHeldByPlayer(playerObj, item)
    return playerObj
        and item
        and (playerObj:getPrimaryHandItem() == item or playerObj:getSecondaryHandItem() == item)
end

local function getVehicleContainerLabel(container)
    local parent = container and container.getParent and container:getParent() or nil
    if not parent
        or not instanceof(parent, "BaseVehicle")
        or not parent.getPartCount
        or not parent.getPartByIndex
    then
        return nil
    end

    for index = 0, parent:getPartCount() - 1 do
        local vehiclePart = parent:getPartByIndex(index)
        if vehiclePart and vehiclePart:getItemContainer() == container then
            return getText("IGUI_VehiclePart" .. container:getType())
        end
    end
    return nil
end

local function getContainerLabel(container)
    local vehicleLabel = getVehicleContainerLabel(container)
    if vehicleLabel then
        return vehicleLabel
    end
    local containingItem = container and container.getContainingItem and container:getContainingItem() or nil
    if containingItem and containingItem.getName then
        local itemName = containingItem:getName()
        if itemName and itemName ~= "" then
            return itemName
        end
    end
    if container and container.getType then
        local containerType = container:getType()
        if containerType and containerType ~= "" then
            return tostring(containerType)
        end
    end
    local parent = container and container.getParent and container:getParent() or nil
    return parent and parent.getName and parent:getName() or "?"
end

local function isFloorContainer(container)
    return container
        and container.getType
        and string.lower(tostring(container:getType())) == "floor"
end

local function canOfferDestination(item, sourceContainer, destinationContainer)
    if not item or not sourceContainer or not destinationContainer or sourceContainer == destinationContainer then
        return false
    end
    if destinationContainer.getContainingItem and destinationContainer:getContainingItem() == item then
        return false
    end
    if destinationContainer.isInside and destinationContainer:isInside(item) then
        return false
    end
    return destinationContainer.isItemAllowed and destinationContainer:isItemAllowed(item)
end

local function queueTransfer(playerIndex, item, destinationContainer)
    local playerObj = getSpecificPlayer(playerIndex)
    local sourceContainer = item and item.getContainer and item:getContainer() or nil
    if not playerObj
        or not isHeldByPlayer(playerObj, item)
        or not canOfferDestination(item, sourceContainer, destinationContainer)
        or not ISInventoryTransferUtil
        or not ISInventoryTransferUtil.newInventoryTransferAction
        or not ISTimedActionQueue
        or not ISTimedActionQueue.add
    then
        return
    end

    local action = ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item, sourceContainer, destinationContainer)
    if action then
        ISTimedActionQueue.add(action)
    end
end

local function addPutInContainerMenu(context, playerIndex, items)
    if not isEnabled() or not context or not context.addOption then
        return
    end

    local playerObj = getSpecificPlayer(playerIndex)
    local item = getSelectedItem(items)
    if not isHeldByPlayer(playerObj, item) then
        return
    end

    local sourceContainer = item:getContainer()
    local containers = ISInventoryPaneContextMenu.getContainers(playerObj)
    if not sourceContainer or not containers then
        return
    end

    local destinations = {}
    local seen = {}
    for index = 0, containers:size() - 1 do
        local container = containers:get(index)
        if container
            and not isFloorContainer(container)
            and not seen[container]
            and canOfferDestination(item, sourceContainer, container)
        then
            seen[container] = true
            destinations[#destinations + 1] = container
        end
    end
    if #destinations == 0 then
        return
    end

    local label = getTextOrFallback("UI_QoLforSacriel_HeldItemPutInContainer", "Put in Container")
    if context:getOptionFromName(label) then
        return
    end

    local rootOption = context:addOption(label)
    local subMenu = context:getNew(context)
    context:addSubMenu(rootOption, subMenu)
    local labelCounts = {}
    for _, container in ipairs(destinations) do
        local baseLabel = getContainerLabel(container)
        labelCounts[baseLabel] = (labelCounts[baseLabel] or 0) + 1
        local destinationLabel = baseLabel
        if labelCounts[baseLabel] > 1 then
            destinationLabel = baseLabel .. " (" .. tostring(labelCounts[baseLabel]) .. ")"
        end
        subMenu:addOption(destinationLabel, playerIndex, queueTransfer, item, container)
    end
    logDebug("added " .. tostring(#destinations) .. " held-item destinations")
end

local function patchInventoryMenu()
    if patched then
        return true
    end

    pcall(require, "ISUI/ISInventoryPaneContextMenu")
    pcall(require, "TimedActions/ISInventoryTransferUtil")
    if not ISInventoryPaneContextMenu
        or type(ISInventoryPaneContextMenu.createMenu) ~= "function"
        or type(ISInventoryPaneContextMenu.getContainers) ~= "function"
    then
        return false
    end

    originalCreateMenu = ISInventoryPaneContextMenu.createMenu
    ISInventoryPaneContextMenu.createMenu = function(playerIndex, isInPlayerInventory, items, x, y, origin)
        local context = originalCreateMenu(playerIndex, isInPlayerInventory, items, x, y, origin)
        if context then
            addPutInContainerMenu(context, playerIndex, items)
        end
        return context
    end

    patched = true
    if loggerRef and loggerRef.info then
        loggerRef.info("UIFixes.HeldItemContainerMenu patched inventory menu")
    end
    return true
end

function HeldItemContainerMenu.init(settings, logger)
    if installed then
        return
    end

    settingsRef = settings
    loggerRef = logger
    if not patchInventoryMenu() and Events and Events.OnGameStart then
        Events.OnGameStart.Add(patchInventoryMenu)
    end
    installed = true
end

return HeldItemContainerMenu