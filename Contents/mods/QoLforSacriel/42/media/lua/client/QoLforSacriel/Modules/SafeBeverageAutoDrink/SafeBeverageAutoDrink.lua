-- ff-assisted
local SafeBeverageAutoDrink = {}
local EquipmentStatsDisplay = require "QoLforSacriel/Modules/UIFixes/EquipmentStatsDisplay"

local installed = false
local settingsRef = nil
local autoDrinkHook = nil
local autoDrinkHookInstalled = false
local lastAutoDrinkLogMinute = nil
local MINIMUM_AMOUNT = 0.12
local THIRST_THRESHOLD = 0.1
local ITEM_MARKER_KEY = "QoLforSacriel_ExtendedAutoDrinkEnabled"
local SILENT_LOGGER = { debug = function() end }

local function isFeatureEnabled()
    return settingsRef
        and settingsRef.isEnabled
        and settingsRef.isEnabled("QoLforSacriel_EnableSafeBeverageAutoDrink") == true
end

local function finiteNumber(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end
    return number
end

local function callMethod(target, methodName, ...)
    if not target or not target[methodName] then
        return false, nil
    end
    return pcall(target[methodName], target, ...)
end

local function logAutoDrinkOncePerMinute(logger, message)
    local gameTime = getGameTime and getGameTime() or nil
    local worldHours = gameTime and gameTime.getWorldAgeHours and gameTime:getWorldAgeHours() or nil
    local worldMinute = finiteNumber(worldHours) and math.floor(worldHours * 60) or nil
    if worldMinute and lastAutoDrinkLogMinute == worldMinute then
        return
    end

    lastAutoDrinkLogMinute = worldMinute
    logger.debug(message)
end

local function hasCategory(fluid, categoryName)
    if not fluid or not fluid.isCategory or not FluidCategory or not FluidCategory[categoryName] then
        return false
    end
    local ok, result = pcall(fluid.isCategory, fluid, FluidCategory[categoryName])
    return ok and result == true
end

local function containerHasCategory(fluidContainer, categoryName)
    if not fluidContainer or not fluidContainer.isCategory or not FluidCategory or not FluidCategory[categoryName] then
        return false
    end
    local ok, result = pcall(fluidContainer.isCategory, fluidContainer, FluidCategory[categoryName])
    return ok and result == true
end

local function isDirectInventoryItem(playerObject, item)
    local inventory = playerObject and playerObject.getInventory and playerObject:getInventory() or nil
    local items = inventory and inventory.getItems and inventory:getItems() or nil
    if not items then
        return false
    end

    for index = 0, items:size() - 1 do
        if items:get(index) == item then
            return true
        end
    end
    return false
end

local function describeItem(item)
    local ok, fullType = callMethod(item, "getFullType")
    return ok and tostring(fullType) or "unknown-item"
end

local function describeFluid(fluid)
    local okName, name = callMethod(fluid, "getTranslatedName")
    if okName and name and tostring(name) ~= "" then
        return tostring(name)
    end

    local okType, fluidType = callMethod(fluid, "getFluidTypeString")
    return okType and tostring(fluidType) or "unknown-fluid"
end

local function describeFluidContainer(fluidContainer, primaryFluid)
    local okMixture, mixture = callMethod(fluidContainer, "isMixture")
    if okMixture and mixture == true and Fluid and Fluid.getAllFluids then
        local okFluids, fluids = pcall(Fluid.getAllFluids)
        local names = {}
        if okFluids and fluids then
            for index = 0, fluids:size() - 1 do
                local fluid = fluids:get(index)
                local okContains, contains = callMethod(fluidContainer, "contains", fluid)
                if okContains and contains == true then
                    names[#names + 1] = describeFluid(fluid)
                end
            end
        end
        if #names > 0 then
            return "mixed (" .. table.concat(names, ", ") .. ")"
        end
    end

    return describeFluid(primaryFluid)
end

local function isMarkedForExtendedAutoDrink(item)
    local ok, modData = callMethod(item, "getModData")
    return ok and modData and modData[ITEM_MARKER_KEY] == true
end

local function getExtendedAutoDrinkTooltipRows(item)
    if not isFeatureEnabled() or not isMarkedForExtendedAutoDrink(item) then
        return {}
    end

    return {
        {
            label = getText("UI_QoLforSacriel_ExtendedAutoDrink_TooltipLabel") or "Extended Auto-Drink",
            value = getText("UI_QoLforSacriel_ExtendedAutoDrink_TooltipEnabled") or "enabled",
        },
    }
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

local function collectFluidContainers(items)
    local candidates = {}
    for index = 1, #resolveActualItems(items) do
        local item = resolveActualItems(items)[index]
        if item and item.getFluidContainer and item:getFluidContainer() then
            table.insert(candidates, item)
        end
    end
    return candidates
end

local function setExtendedAutoDrinkEnabled(items, enabled, logger)
    if not isFeatureEnabled() then
        return
    end

    for index = 1, #items do
        local item = items[index]
        local ok, modData = callMethod(item, "getModData")
        if ok and modData then
            modData[ITEM_MARKER_KEY] = enabled and true or nil
            logger.debug(string.format(
                "Extended auto-drink %s: %s",
                enabled and "enabled" or "disabled", describeItem(item)
            ))
        end
    end
end

local function addContextMenuOption(context, items, logger)
    if not isFeatureEnabled() then
        return
    end

    local candidates = collectFluidContainers(items)
    if #candidates == 0 then
        return
    end

    local allEnabled = true
    for index = 1, #candidates do
        if not isMarkedForExtendedAutoDrink(candidates[index]) then
            allEnabled = false
            break
        end
    end

    local labelKey = allEnabled
        and "UI_QoLforSacriel_ExtendedAutoDrink_Disable"
        or "UI_QoLforSacriel_ExtendedAutoDrink_Enable"
    local fallback = allEnabled and "Disable Extended Auto-Drink" or "Enable Extended Auto-Drink"
    context:addOption(getText(labelKey) or fallback, candidates, function(selectedItems, enabled)
        setExtendedAutoDrinkEnabled(selectedItems, enabled, logger)
    end, not allEnabled)
end

local function isSafeBeverage(fluidContainer)
    local okAmount, amount = callMethod(fluidContainer, "getAmount")
    local okMixture, mixture = callMethod(fluidContainer, "isMixture")
    local okWaterOnly, waterOnly = callMethod(fluidContainer, "isWaterOnlySource")
    local okPoisonous, poisonous = callMethod(fluidContainer, "isPoisonous")
    local okPrimary, primaryFluid = callMethod(fluidContainer, "getPrimaryFluid")
    local okProperties, properties = callMethod(fluidContainer, "getProperties")
    local okThirst, thirstChange = callMethod(properties, "getThirstChange")
    local amountNumber = okAmount and finiteNumber(amount) or nil
    local thirstNumber = okThirst and finiteNumber(thirstChange) or nil

    if not okPrimary then
        return false
    end

    local allBeverages = false
    if okMixture and mixture == true then
        local okAllBeverages, result = callMethod(fluidContainer, "isAllCategory", FluidCategory and FluidCategory.Beverage or nil)
        allBeverages = okAllBeverages and result == true
    elseif okMixture and mixture == false then
        allBeverages = hasCategory(primaryFluid, "Beverage")
    end

    return amountNumber and amountNumber >= MINIMUM_AMOUNT
        and allBeverages
        and okWaterOnly and waterOnly == false
        and okPoisonous and poisonous == false
        and not containerHasCategory(fluidContainer, "Alcoholic")
        and thirstNumber and thirstNumber < 0,
        primaryFluid, amountNumber
end

local function findSafeBeverage(playerObject)
    local inventory = playerObject and playerObject.getInventory and playerObject:getInventory() or nil
    local items = inventory and inventory.getItems and inventory:getItems() or nil
    if not items then
        return nil, nil, nil, {
            directItems = 0,
            fluidContainers = 0,
            markedContainers = 0,
            safeBeverages = 0,
        }
    end

    local scan = {
        directItems = items:size(),
        fluidContainers = 0,
        markedContainers = 0,
        safeBeverages = 0,
    }
    local selectedItem = nil
    local selectedFluid = nil
    local selectedAmount = nil

    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local fluidContainer = item and item.getFluidContainer and item:getFluidContainer() or nil
        if fluidContainer then
            scan.fluidContainers = scan.fluidContainers + 1
        end
        if fluidContainer and isMarkedForExtendedAutoDrink(item) then
            scan.markedContainers = scan.markedContainers + 1
            local safe, primaryFluid, amount = isSafeBeverage(fluidContainer)
            if safe then
                scan.safeBeverages = scan.safeBeverages + 1
                if not selectedItem then
                    selectedItem = item
                    selectedFluid = primaryFluid
                    selectedAmount = amount
                end
            end
        end
    end

    return selectedItem, selectedFluid, selectedAmount, scan
end

local function drinkVanillaWater(playerObject, thirstNumber, logger)
    local inventory = playerObject and playerObject.getInventory and playerObject:getInventory() or nil
    local items = inventory and inventory.getItems and inventory:getItems() or nil
    local okSource, waterItem = callMethod(playerObject, "getWaterSource", items)
    local fluidContainer = waterItem and waterItem.getFluidContainer and waterItem:getFluidContainer() or nil
    local okAmount, availableAmount = callMethod(fluidContainer, "getAmount")
    local availableNumber = okAmount and finiteNumber(availableAmount) or nil
    if not okSource or not waterItem or not availableNumber or availableNumber <= 0 then
        logger.debug("Safe beverage fallback found no vanilla water source")
        return false
    end

    local amountToDrink = math.min(availableNumber, thirstNumber * 2)
    local percentage = amountToDrink / availableNumber
    if amountToDrink <= 0 or percentage <= 0 or percentage > 1 then
        logger.debug("Safe beverage fallback rejected invalid vanilla water amount")
        return false
    end

    local ok, consumed = pcall(playerObject.DrinkFluid, playerObject, waterItem, percentage, false)
    logger.debug(string.format(
        "Safe beverage fallback to vanilla water: %s | amount=%.3f | percentage=%.3f | consumed=%s",
        describeItem(waterItem), amountToDrink, percentage, tostring(ok and consumed == true)
    ))
    return ok and consumed == true
end

local function drinkVanillaWaterForCurrentThirst(playerObject, logger)
    local stats = playerObject and playerObject.getStats and playerObject:getStats() or nil
    local okThirst, thirst = callMethod(stats, "get", CharacterStat and CharacterStat.THIRST or nil)
    local thirstNumber = okThirst and finiteNumber(thirst) or nil
    if not thirstNumber or thirstNumber <= THIRST_THRESHOLD then
        logger.debug("Safe beverage fallback could not determine a drinkable thirst amount")
        return false
    end

    return drinkVanillaWater(playerObject, thirstNumber, logger)
end

local function onAutoDrink(playerObject, settings, logger)
    if not isFeatureEnabled()
        or type(getSpecificPlayer) ~= "function"
        or playerObject ~= getSpecificPlayer(0)
    then
        return false
    end

    local stats = playerObject.getStats and playerObject:getStats() or nil
    local okThirst, thirst = callMethod(stats, "get", CharacterStat and CharacterStat.THIRST or nil)
    local thirstNumber = okThirst and finiteNumber(thirst) or nil
    if not thirstNumber or thirstNumber <= THIRST_THRESHOLD then
        return false
    end

    local item, primaryFluid, amount, scan = findSafeBeverage(playerObject)

    if not item or not isDirectInventoryItem(playerObject, item) then
        local consumed = drinkVanillaWater(playerObject, thirstNumber, SILENT_LOGGER)
        logAutoDrinkOncePerMinute(logger, string.format(
            "Safe beverage auto-drink: thirst=%.3f | marked=%d | safe=%d | result=vanilla-water-fallback:%s",
            thirstNumber, scan.markedContainers, scan.safeBeverages, tostring(consumed)
        ))
        return consumed
    end

    local amountToDrink = math.min(amount, thirstNumber * 2)
    local percentage = amountToDrink / amount
    if amountToDrink <= 0 or percentage <= 0 or percentage > 1 then
        local consumed = drinkVanillaWater(playerObject, thirstNumber, SILENT_LOGGER)
        logAutoDrinkOncePerMinute(logger, string.format(
            "Safe beverage auto-drink: thirst=%.3f | item=%s | result=invalid-safe-amount; vanilla-water-fallback:%s",
            thirstNumber, describeItem(item), tostring(consumed)
        ))
        return consumed
    end

    local fluidContainer = item:getFluidContainer()
    local ok, consumed = pcall(playerObject.DrinkFluid, playerObject, item, percentage, false)
    if ok and consumed == true then
        local okRemaining, remaining = callMethod(fluidContainer, "getAmount")
        logAutoDrinkOncePerMinute(logger, string.format(
            "Safe beverage auto-drink: thirst=%.3f | item=%s | fluid=%s | drank=%.3f | remaining=%s",
            thirstNumber, describeItem(item), describeFluidContainer(fluidContainer, primaryFluid), amountToDrink,
            okRemaining and finiteNumber(remaining) and string.format("%.3f", remaining) or "unknown"
        ))
        return true
    end

    local fallbackConsumed = drinkVanillaWater(playerObject, thirstNumber, SILENT_LOGGER)
    logAutoDrinkOncePerMinute(logger, string.format(
        "Safe beverage auto-drink: thirst=%.3f | item=%s | result=safe-drink-failed; vanilla-water-fallback:%s",
        thirstNumber, describeItem(item), tostring(fallbackConsumed)
    ))
    return fallbackConsumed
end

local function updateAutoDrinkHook(logger)
    if not autoDrinkHook or not Hook or not Hook.AutoDrink then
        return
    end

    if isFeatureEnabled() and not autoDrinkHookInstalled and Hook.AutoDrink.Add then
        Hook.AutoDrink.Add(autoDrinkHook)
        autoDrinkHookInstalled = true
        logger.info("SafeBeverageAutoDrink.AutoDrink hook enabled")
    elseif not isFeatureEnabled() and autoDrinkHookInstalled and Hook.AutoDrink.Remove then
        Hook.AutoDrink.Remove(autoDrinkHook)
        autoDrinkHookInstalled = false
        logger.info("SafeBeverageAutoDrink.AutoDrink hook disabled; vanilla auto-drink restored")
    end
end

function SafeBeverageAutoDrink.init(settings, logger)
    if installed then
        logger.debug("SafeBeverageAutoDrink.Base already installed")
        return
    end
    settingsRef = settings
    if not Hook or not Hook.AutoDrink or not Hook.AutoDrink.Add then
        logger.error("SafeBeverageAutoDrink.Base unavailable: Hook.AutoDrink binding is missing")
        return
    end

    if EquipmentStatsDisplay and EquipmentStatsDisplay.registerInventoryTooltipProvider then
        EquipmentStatsDisplay.registerInventoryTooltipProvider(getExtendedAutoDrinkTooltipRows)
    else
        logger.error("SafeBeverageAutoDrink.Base unavailable: inventory tooltip provider is missing")
        return
    end

    autoDrinkHook = function(playerObject)
        local ok, handled = pcall(onAutoDrink, playerObject, settings, logger)
        if not ok then
            logger.error("Safe beverage auto-drink failed: " .. tostring(handled))
            return drinkVanillaWaterForCurrentThirst(playerObject, logger)
        end
        return handled == true
    end
    updateAutoDrinkHook(logger)
    Events.OnTick.Add(function()
        updateAutoDrinkHook(logger)
    end)
    Events.OnFillInventoryObjectContextMenu.Add(function(_, context, items)
        local ok, errorMessage = pcall(addContextMenuOption, context, items, logger)
        if not ok then
            logger.error("Safe beverage auto-drink context error: " .. tostring(errorMessage))
        end
    end)
    installed = true
    logger.info("SafeBeverageAutoDrink.Base installed")
end

return SafeBeverageAutoDrink