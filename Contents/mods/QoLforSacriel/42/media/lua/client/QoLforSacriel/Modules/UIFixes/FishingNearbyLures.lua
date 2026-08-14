-- ff-assisted
local FishingNearbyLures = {}

local installed = false
local patched = false
local settingsRef = nil
local loggerRef = nil
local originalAddFishRodOptions = nil

local function logDebug(message)
    if settingsRef
        and settingsRef.get
        and settingsRef.get("QoLforSacriel_DebugLogs") == true
        and loggerRef
        and loggerRef.debug
    then
        loggerRef.debug("UIFixes.FishingNearbyLures: " .. tostring(message))
    end
end

local function isEnabled()
    return settingsRef
        and settingsRef.isEnabled
        and settingsRef.isEnabled("QoLforSacriel_EnableUIFixes") == true
        and settingsRef.get
        and settingsRef.get("QoLforSacriel_UIFixes_EnableFishingNearbyLures") == true
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
    if not container then
        return getTextOrFallback("UI_QoLforSacriel_FishingNearbyLures_UnknownContainer", "Nearby container")
    end

    local vehicleLabel = getVehicleContainerLabel(container)
    if vehicleLabel then
        return vehicleLabel
    end
    local containingItem = container.getContainingItem and container:getContainingItem() or nil
    if containingItem and containingItem.getName then
        local itemName = containingItem:getName()
        if itemName and itemName ~= "" then
            return itemName
        end
    end
    if container.getType then
        local containerType = container:getType()
        if containerType and containerType ~= "" then
            return tostring(containerType)
        end
    end
    local parent = container.getParent and container:getParent() or nil
    if parent and parent.getName then
        local name = parent:getName()
        if name and name ~= "" then
            return name
        end
    end
    return getTextOrFallback("UI_QoLforSacriel_FishingNearbyLures_UnknownContainer", "Nearby container")
end

local function isEligibleLure(item)
    return item
        and item.getFullType
        and Fishing
        and Fishing.IsLure
        and Fishing.IsLure(item:getFullType())
        and (not instanceof(item, "Food") or not item:isCooked())
end

local function collectLures(container)
    local lures = {}
    if not container or not container.getAllEvalRecurse then
        return lures
    end

    local items = container:getAllEvalRecurse(function(item)
        return isEligibleLure(item)
    end, ArrayList.new())
    if not items then
        return lures
    end

    for index = 0, items:size() - 1 do
        lures[#lures + 1] = items:get(index)
    end
    return lures
end

local function addNearbyLure(playerIndex, fishingRod, lure)
    local playerObj = getSpecificPlayer(playerIndex)
    if not playerObj
        or not fishingRod
        or fishingRod:isBroken()
        or fishingRod:getModData().fishing_Lure ~= nil
        or not lure
        or not lure.getContainer
        or not lure:getContainer()
        or not isEligibleLure(lure)
    then
        return
    end

    ISInventoryPaneContextMenu.addLure(playerIndex, fishingRod, lure)
end

local function addNearbyLuresToMenu(fishingRod, context, playerIndex, optionStartIndex)
    if not isEnabled() or not fishingRod or fishingRod:getModData().fishing_Lure ~= nil then
        return
    end

    local rodOption = nil
    for index = optionStartIndex + 1, #context.options do
        local option = context.options[index]
        if option and option.name == fishingRod:getDisplayName() and option.subOption then
            rodOption = option
        end
    end
    if not rodOption then
        return
    end

    local rodMenu = context:getSubMenu(rodOption.subOption)
    local addBaitOption = rodMenu and rodMenu:getOptionFromName(getText("ContextMenu_Add_Bait")) or nil
    local baitMenu = addBaitOption and rodMenu:getSubMenu(addBaitOption.subOption) or nil
    if not rodMenu then
        return
    end

    local playerObj = getSpecificPlayer(playerIndex)
    local playerInventory = playerObj and playerObj:getInventory() or nil
    local containers = playerObj and ISInventoryPaneContextMenu.getContainers(playerObj) or nil
    if not playerInventory or not containers then
        return
    end

    local candidates = {}
    for index = 0, containers:size() - 1 do
        local container = containers:get(index)
        if container and container ~= playerInventory then
            local lures = collectLures(container)
            if #lures > 0 then
                candidates[#candidates + 1] = { container = container, lures = lures }
            end
        end
    end
    if #candidates == 0 then
        return
    end

    if not baitMenu then
        addBaitOption = rodMenu:addOption(getText("ContextMenu_Add_Bait"))
        addBaitOption.iconTexture = getTexture("Item_Worm")
        baitMenu = rodMenu:getNew(rodMenu)
        rodMenu:addSubMenu(addBaitOption, baitMenu)
    end
    if baitMenu:getOptionFromName(getTextOrFallback("UI_QoLforSacriel_FishingNearbyLures", "Nearby Containers")) then
        return
    end

    local nearbyOption = baitMenu:addOption(getTextOrFallback("UI_QoLforSacriel_FishingNearbyLures", "Nearby Containers"))
    local nearbyMenu = baitMenu:getNew(baitMenu)
    baitMenu:addSubMenu(nearbyOption, nearbyMenu)

    for _, candidate in ipairs(candidates) do
        local containerOption = nearbyMenu:addOption(getContainerLabel(candidate.container))
        local containerMenu = nearbyMenu:getNew(nearbyMenu)
        nearbyMenu:addSubMenu(containerOption, containerMenu)
        for _, lure in ipairs(candidate.lures) do
            local lureOption = containerMenu:addOption(lure:getName(), playerIndex, addNearbyLure, fishingRod, lure)
            lureOption.itemForTexture = lure
        end
    end

    logDebug("added nearby lure entries for " .. tostring(#candidates) .. " container(s)")
end

local function patchFishingMenu()
    if patched then
        return true
    end

    pcall(require, "ISUI/ISInventoryPaneContextMenu")
    if not ISInventoryPaneContextMenu
        or type(ISInventoryPaneContextMenu.addFishRodOptions) ~= "function"
        or type(ISInventoryPaneContextMenu.getContainers) ~= "function"
        or type(ISInventoryPaneContextMenu.addLure) ~= "function"
    then
        return false
    end

    originalAddFishRodOptions = ISInventoryPaneContextMenu.addFishRodOptions
    ISInventoryPaneContextMenu.addFishRodOptions = function(fishingRod, haveLure, context, playerIndex)
        local optionStartIndex = #context.options
        originalAddFishRodOptions(fishingRod, haveLure, context, playerIndex)
        addNearbyLuresToMenu(fishingRod, context, playerIndex, optionStartIndex)
    end

    patched = true
    if loggerRef and loggerRef.info then
        loggerRef.info("UIFixes.FishingNearbyLures patched fishing rod menu")
    end
    return true
end

function FishingNearbyLures.init(settings, logger)
    if installed then
        return
    end

    settingsRef = settings
    loggerRef = logger
    if not patchFishingMenu() and Events and Events.OnGameStart then
        Events.OnGameStart.Add(patchFishingMenu)
    end
    installed = true
end

return FishingNearbyLures