local InventoryUpdate = {}

local installed = false
local settingsRef = nil
local loggerRef = nil

local activeEatChains = {}
local queueEatChainRefreshAction = nil
local getEatStatusDebugText = nil

local function logDebug(message)
    if not loggerRef or not loggerRef.debug then
        return
    end
    if not settingsRef or not settingsRef.get or settingsRef.get("QoLforSacriel_DebugLogs") ~= true then
        return
    end
    if not settingsRef.isEnabled
        or settingsRef.isEnabled("QoLforSacriel_EnableUIFixes") ~= true
        or settingsRef.get("QoLforSacriel_UIFixes_EnableInventoryUpdate") ~= true
    then
        return
    end
    loggerRef.debug("UIFixes.InventoryUpdate: " .. tostring(message))
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

local function isUiFixesEnabled()
    return settingsRef
        and settingsRef.isEnabled
        and settingsRef.isEnabled("QoLforSacriel_EnableUIFixes") == true
end

local function isInventoryUpdateEnabled()
    if not isUiFixesEnabled() then
        return false
    end
    return settingsRef and settingsRef.get and settingsRef.get("QoLforSacriel_UIFixes_EnableInventoryUpdate") == true
end

local function isFeatureEnabled(settingName)
    if not isInventoryUpdateEnabled() then
        return false
    end
    return settingsRef and settingsRef.get and settingsRef.get(settingName) == true
end

local function getActualItems(items)
    if not ISInventoryPane or type(ISInventoryPane.getActualItems) ~= "function" then
        return {}
    end

    local ok, actual = pcall(ISInventoryPane.getActualItems, items)
    if not ok or type(actual) ~= "table" then
        return {}
    end

    return actual
end

local function isFoodItem(item)
    return item ~= nil and item.getCategory and item:getCategory() == "Food"
end

local function getItemDebugLabel(item)
    if not item or not item.getFullType then
        return "?"
    end

    local ok, fullType = pcall(function()
        return item:getFullType()
    end)
    if ok and fullType and fullType ~= "" then
        return tostring(fullType)
    end
    return "?"
end

local function isRottenFood(item)
    if not isFoodItem(item) or not item.isRotten then
        return false
    end
    local ok, value = pcall(function()
        return item:isRotten()
    end)
    return ok and value == true
end

local function getNumericItemAge(item)
    if not item or not item.getAge then
        return nil
    end
    local ok, value = pcall(function()
        return item:getAge()
    end)
    if not ok then
        return nil
    end
    return tonumber(value)
end

local function getNumericOffAge(item)
    if not item or not item.getOffAge then
        return nil
    end
    local ok, value = pcall(function()
        return item:getOffAge()
    end)
    if not ok then
        return nil
    end
    return tonumber(value)
end

local function getNumericOffAgeMax(item)
    if not item or not item.getOffAgeMax then
        return nil
    end
    local ok, value = pcall(function()
        return item:getOffAgeMax()
    end)
    if not ok then
        return nil
    end
    return tonumber(value)
end

local function isStaleFood(item)
    if not isFoodItem(item) then
        return false
    end

    if item.isStale then
        local okStale, stale = pcall(function()
            return item:isStale()
        end)
        if okStale and stale == true then
            return not isRottenFood(item)
        end
    end

    local age = getNumericItemAge(item)
    local offAge = getNumericOffAge(item)
    local offAgeMax = getNumericOffAgeMax(item)

    if not age or not offAge or not offAgeMax then
        return false
    end

    if offAgeMax >= 1000000000 then
        return false
    end

    return age >= offAge and age < offAgeMax and not isRottenFood(item)
end

local function getSourceContainerFromSelection(actualItems, playerObj)
    if not actualItems or #actualItems == 0 or not playerObj then
        return nil
    end

    for i = 1, #actualItems do
        local item = actualItems[i]
        if item and item.getContainer then
            local okContainer, container = pcall(function()
                return item:getContainer()
            end)
            if okContainer and container and container ~= playerObj:getInventory() then
                return container
            end
        end
    end

    return nil
end

local function collectFoodCandidatesFromContainer(container, mode)
    local results = {}
    if not container or not container.getItems then
        return results
    end

    local items = container:getItems()
    if not items or not items.size then
        return results
    end

    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            if mode == "rotten" and isRottenFood(item) then
                results[#results + 1] = item
            elseif mode == "stale" and isStaleFood(item) then
                results[#results + 1] = item
            end
        end
    end

    return results
end

local function queueTransferToPlayer(playerObj, playerIndex, items)
    if not playerObj or not items or #items == 0 then
        return
    end
    if not ISInventoryPaneContextMenu or type(ISInventoryPaneContextMenu.transferItemToPlayer) ~= "function" then
        return
    end

    local dontWalk = false
    for i = 1, #items do
        local item = items[i]
        if item and item.getContainer and item:getContainer() then
            if not dontWalk and luautils and luautils.walkToContainer then
                if not luautils.walkToContainer(item:getContainer(), playerIndex) then
                    return
                end
                dontWalk = true
            end

            ISInventoryPaneContextMenu.transferItemToPlayer(item, playerIndex, dontWalk)
        end
    end
end

local function onGrabFoodFromContainer(target, mode, playerIndex)
    local playerObj = getSpecificPlayer(playerIndex)
    if not playerObj or not target or not target.container then
        return
    end

    local candidates = collectFoodCandidatesFromContainer(target.container, mode)
    if #candidates == 0 then
        return
    end

    queueTransferToPlayer(playerObj, playerIndex, candidates)
end

local function findEatSubMenu(context)
    if not context or not context.options then
        return nil
    end

    for _, option in ipairs(context.options) do
        if option and option.subOption and context.getSubMenu then
            local subMenu = context:getSubMenu(option.subOption)
            if subMenu and subMenu.options then
                for _, child in ipairs(subMenu.options) do
                    if child and child.onSelect == ISInventoryPaneContextMenu.onEatItems then
                        return subMenu
                    end
                end
            end
        end
    end

    return nil
end

local function hasOpeningRecipe(item)
    if not item or not item.getOpeningRecipe then
        return false
    end
    local ok, value = pcall(function()
        return item:getOpeningRecipe()
    end)
    return ok and value ~= nil and value ~= ""
end

local function isChainEligibleFood(item)
    if not isFoodItem(item) then
        return false
    end

    if hasOpeningRecipe(item) then
        return true
    end

    if item.getHungChange then
        local ok, hungChange = pcall(function()
            return item:getHungChange()
        end)
        if ok and tonumber(hungChange) and tonumber(hungChange) < 0 then
            return true
        end
    end

    return false
end

local function buildEatCandidatesFromSelection(items)
    local actualItems = getActualItems(items)
    local result = {}
    for i = 1, #actualItems do
        local item = actualItems[i]
        if isChainEligibleFood(item) then
            result[#result + 1] = item
        end
    end
    return result
end

local function resolveOpeningRecipe(item, playerObj)
    if not item or not playerObj or not item.getOpeningRecipe then
        return nil
    end

    local openingRecipeName = item:getOpeningRecipe()
    if not openingRecipeName or openingRecipeName == "" then
        return nil
    end

    if not getScriptManager then
        return nil
    end

    local scriptRecipe = getScriptManager():getCraftRecipe(openingRecipeName)
    if not scriptRecipe then
        return nil
    end

    if not ISInventoryPaneContextMenu
        or type(ISInventoryPaneContextMenu.getContainers) ~= "function"
        or not HandcraftLogic
        or not HandcraftLogic.new
    then
        return nil
    end

    local containers = ISInventoryPaneContextMenu.getContainers(playerObj)
    if not containers then
        return nil
    end

    local logic = HandcraftLogic.new(playerObj, nil, nil)
    logic:setContainers(containers)
    logic:setRecipeFromContextClick(scriptRecipe, item)
    if logic:canPerformCurrentRecipe() then
        return scriptRecipe
    end

    return nil
end

local function hasAnyTimedActionInProgress(playerObj)
    if not playerObj or not ISTimedActionQueue or not ISTimedActionQueue.getTimedActionQueue then
        return false
    end

    local queue = ISTimedActionQueue.getTimedActionQueue(playerObj)
    if not queue or not queue.queue then
        return false
    end

    local rawQueue = queue.queue
    if rawQueue[1] ~= nil or rawQueue[0] ~= nil then
        return true
    end

    if rawQueue.size and type(rawQueue.size) == "function" then
        local ok, size = pcall(function()
            return rawQueue:size()
        end)
        if ok and tonumber(size) and tonumber(size) > 0 then
            return true
        end
    end

    return #rawQueue > 0
end

local function getTimedActionQueueLength(playerObj)
    if not playerObj or not ISTimedActionQueue or not ISTimedActionQueue.getTimedActionQueue then
        return 0
    end

    local queue = ISTimedActionQueue.getTimedActionQueue(playerObj)
    if not queue or not queue.queue then
        return 0
    end

    local rawQueue = queue.queue
    if rawQueue.size and type(rawQueue.size) == "function" then
        local ok, size = pcall(function()
            return rawQueue:size()
        end)
        if ok and tonumber(size) then
            return tonumber(size)
        end
    end

    local count = #rawQueue
    if count > 0 then
        return count
    end

    local zeroIndexedCount = 0
    while rawQueue[zeroIndexedCount] ~= nil do
        zeroIndexedCount = zeroIndexedCount + 1
    end

    return zeroIndexedCount
end

local function canAccessContainerWithoutWalking(playerObj, container)
    if not playerObj or not container then
        return false
    end

    if container.isInCharacterInventory and container:isInCharacterInventory(playerObj) then
        return true
    end

    local parent = container.getParent and container:getParent() or nil
    if parent and instanceof and instanceof(parent, "BaseVehicle") then
        if playerObj:getVehicle() == parent then
            return true
        end

        local part = container.getVehiclePart and container:getVehiclePart() or nil
        return part
            and part.getVehicle
            and part.getIndex
            and part:getVehicle():canAccessContainer(part:getIndex(), playerObj) == true
    end

    local sourceSquare = nil
    if parent and parent.getSquare then
        sourceSquare = parent:getSquare()
    elseif container.getSourceGrid then
        sourceSquare = container:getSourceGrid()
    end

    local currentSquare = playerObj:getCurrentSquare()
    if not sourceSquare or not currentSquare or not AdjacentFreeTileFinder or not AdjacentFreeTileFinder.Find then
        return false
    end

    return AdjacentFreeTileFinder.Find(sourceSquare, playerObj) == currentSquare
end

local function tryQueueEatItem(playerObj, item, playerIndex, chain)
    if not playerObj or not item or not item.getContainer or not item:getContainer() then
        logDebug("eat chain queue check failed: item missing or no container")
        return false
    end
    if not ISEatFoodAction or not ISEatFoodAction.new or not ISTimedActionQueue or not ISTimedActionQueue.add then
        logDebug("eat chain queue check failed: vanilla eat action unavailable")
        return false
    end

    local action = ISEatFoodAction:new(playerObj, item, 1)

    action.perform = function(self)
        local refreshAction = nil
        if activeEatChains[playerIndex] == chain and queueEatChainRefreshAction then
            refreshAction = queueEatChainRefreshAction(playerObj, playerIndex, chain, self)
        end
        ISEatFoodAction.perform(self)
        if activeEatChains[playerIndex] == chain and chain.pendingAction == self then
            if refreshAction then
                chain.pendingAction = refreshAction
                logDebug("eat chain action completed: queued hunger refresh, " .. getEatStatusDebugText(playerObj))
            else
                chain.pendingAction = nil
                chain.lastActionCompleted = true
                logDebug("eat chain action completed: refresh queue failed, " .. getEatStatusDebugText(playerObj))
            end
        end
    end

    action.stop = function(self)
        ISEatFoodAction.stop(self)
        if activeEatChains[playerIndex] == chain and chain.pendingAction == self then
            chain.pendingAction = nil
            chain.cancelled = true
            logDebug("eat chain cancelled: queued eat action stopped")
        end
    end

    local sourceContainer = item:getContainer()
    local playerInventory = playerObj:getInventory()
    local beforeCount = getTimedActionQueueLength(playerObj)
    local afterCount = beforeCount

    if sourceContainer ~= playerInventory then
        if not ISInventoryTransferUtil or not ISInventoryTransferUtil.newInventoryTransferAction or not ISTimedActionQueue.addAfter then
            logDebug("eat chain queue check failed: vanilla transfer action unavailable")
            return false
        end

        if chain.canWalkToFirstItem then
            if luautils and luautils.walkToContainer and not luautils.walkToContainer(sourceContainer, playerIndex) then
                logDebug("eat chain queue check failed: cannot reach first item container, item='" .. getItemDebugLabel(item) .. "'")
                return false
            end
        elseif not canAccessContainerWithoutWalking(playerObj, sourceContainer) then
            chain.cancelled = true
            logDebug("eat chain stopped: source container out of reach, item='" .. getItemDebugLabel(item) .. "'")
            return false
        end

        local transferBeforeCount = getTimedActionQueueLength(playerObj)
        local transferAction = ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item, sourceContainer, playerInventory)
        if not transferAction then
            logDebug("eat chain queue check failed: could not create transfer action, item='" .. getItemDebugLabel(item) .. "'")
            return false
        end

        ISTimedActionQueue.add(transferAction)
        local transferAfterCount = getTimedActionQueueLength(playerObj)
        if transferAfterCount <= transferBeforeCount then
            logDebug("eat chain queue check failed: transfer was not queued, item='" .. getItemDebugLabel(item) .. "'")
            return false
        end

        local queuedQueue = ISTimedActionQueue.addAfter(transferAction, action)
        if not queuedQueue then
            logDebug("eat chain queue check failed: could not queue eat after transfer, item='" .. getItemDebugLabel(item) .. "'")
            return false
        end

        afterCount = getTimedActionQueueLength(playerObj)
        logDebug(
            "eat chain queued transfer: item='" .. getItemDebugLabel(item)
            .. "', before=" .. tostring(beforeCount)
            .. ", after=" .. tostring(afterCount)
        )
    else
        ISTimedActionQueue.add(action)
        afterCount = getTimedActionQueueLength(playerObj)
    end

    if afterCount <= beforeCount then
        return false
    end

    chain.pendingAction = action
    chain.lastActionCompleted = false
    chain.canWalkToFirstItem = false
    logDebug(
        "eat queue attempt: item='" .. getItemDebugLabel(item)
        .. "', before=" .. tostring(beforeCount)
        .. ", after=" .. tostring(afterCount)
    )

    return afterCount > beforeCount
end

local function isHungry(playerObj)
    if not playerObj then
        return false
    end

    local moodles = playerObj:getMoodles()
    if moodles and MoodleType then
        local moodleKey = MoodleType.HUNGRY or MoodleType.HUNGER
        if moodleKey then
            local okMoodle, moodleLevel = pcall(function()
                return moodles:getMoodleLevel(moodleKey)
            end)
            if okMoodle and tonumber(moodleLevel) then
                return tonumber(moodleLevel) > 0
            end
        end
    end

    local stats = playerObj:getStats()
    if stats and stats.get then
        local okStat, hungerValue = pcall(function()
            return stats:get(CharacterStat.HUNGER)
        end)
        if okStat and tonumber(hungerValue) then
            return tonumber(hungerValue) > 0.01
        end
    end

    return true
end

local function getFoodEatenLevel(playerObj)
    if not playerObj or not MoodleType or not MoodleType.FOOD_EATEN then
        return nil
    end

    local moodles = playerObj:getMoodles()
    if not moodles then
        return nil
    end

    local ok, level = pcall(function()
        return moodles:getMoodleLevel(MoodleType.FOOD_EATEN)
    end)
    if ok and tonumber(level) then
        return tonumber(level)
    end
    return nil
end

local function getHungerValue(playerObj)
    if not playerObj or not CharacterStat then
        return nil
    end

    local stats = playerObj:getStats()
    if not stats or not stats.get then
        return nil
    end

    local ok, hungerValue = pcall(function()
        return stats:get(CharacterStat.HUNGER)
    end)
    if ok and tonumber(hungerValue) then
        return tonumber(hungerValue)
    end
    return nil
end

getEatStatusDebugText = function(playerObj)
    return "hunger=" .. tostring(getHungerValue(playerObj))
        .. ", foodEaten=" .. tostring(getFoodEatenLevel(playerObj))
end

local function canContinueEating(playerObj)
    local foodEatenLevel = getFoodEatenLevel(playerObj)
    return foodEatenLevel == nil or foodEatenLevel < 3
end

local function clearEatChain(playerIndex)
    logDebug("clearing eat chain for player=" .. tostring(playerIndex))
    activeEatChains[playerIndex] = nil
end

local function runEatChainStep(playerObj, chain)
    local playerIndex = playerObj:getPlayerNum()
    if not chain or not chain.items then
        clearEatChain(playerIndex)
        return
    end

    if chain.mode == "until-not-hungry" and not isHungry(playerObj) then
        logDebug("eat chain stopped: hunger cleared, " .. getEatStatusDebugText(playerObj))
        clearEatChain(playerIndex)
        return
    end

    if not canContinueEating(playerObj) then
        logDebug("eat chain stopped: too full to eat, " .. getEatStatusDebugText(playerObj))
        clearEatChain(playerIndex)
        return
    end

    while chain.nextIndex <= #chain.items do
        local item = chain.items[chain.nextIndex]
        if tryQueueEatItem(playerObj, item, playerIndex, chain) then
            logDebug(
                "eat chain queued item index=" .. tostring(chain.nextIndex)
                .. "/" .. tostring(#chain.items)
                .. ", mode=" .. tostring(chain.mode)
                .. ", " .. getEatStatusDebugText(playerObj)
            )
            chain.nextIndex = chain.nextIndex + 1
            return
        end

        if chain.cancelled then
            clearEatChain(playerIndex)
            return
        end

        logDebug("eat chain skipped item index=" .. tostring(chain.nextIndex) .. " (not queueable)")
        chain.nextIndex = chain.nextIndex + 1
    end

    clearEatChain(playerIndex)
end

queueEatChainRefreshAction = function(playerObj, playerIndex, chain, previousAction)
    if not ISBaseTimedAction or not ISTimedActionQueue or not ISTimedActionQueue.addAfter then
        return nil
    end

    local refreshAction = ISBaseTimedAction:new(playerObj)
    refreshAction.Type = "QoLforSacrielEatChainRefreshAction"
    refreshAction.playerIndex = playerIndex
    refreshAction.chain = chain
    refreshAction.maxTime = 1
    refreshAction.stopOnWalk = false
    refreshAction.stopOnRun = true
    refreshAction.stopOnAim = false

    function refreshAction:isValid()
        return activeEatChains[self.playerIndex] == self.chain
    end

    function refreshAction:perform()
        ISBaseTimedAction.perform(self)
        if activeEatChains[self.playerIndex] == self.chain and self.chain.pendingAction == self then
            self.chain.pendingAction = nil
            runEatChainStep(self.character, self.chain)
        end
    end

    function refreshAction:stop()
        ISBaseTimedAction.stop(self)
        if activeEatChains[self.playerIndex] == self.chain and self.chain.pendingAction == self then
            self.chain.pendingAction = nil
            self.chain.cancelled = true
            logDebug("eat chain cancelled: hunger refresh action stopped")
        end
    end

    local queue = ISTimedActionQueue.addAfter(previousAction, refreshAction)
    if not queue then
        return nil
    end
    return refreshAction
end

local function startEatChain(playerObj, items, mode)
    if not playerObj or not items or #items == 0 then
        return
    end

    local playerIndex = playerObj:getPlayerNum()
    activeEatChains[playerIndex] = {
        mode = mode,
        items = items,
        nextIndex = 1,
        pendingAction = nil,
        lastActionCompleted = false,
        cancelled = false,
        canWalkToFirstItem = true,
    }

    logDebug(
        "starting eat chain: player=" .. tostring(playerIndex)
        .. ", mode=" .. tostring(mode)
        .. ", candidates=" .. tostring(#items)
        .. ", " .. getEatStatusDebugText(playerObj)
    )

    if not hasAnyTimedActionInProgress(playerObj) then
        runEatChainStep(playerObj, activeEatChains[playerIndex])
    end
end

local function onEatAllChainSelected(items, playerIndex)
    local playerObj = getSpecificPlayer(playerIndex)
    if not playerObj then
        return
    end

    local candidates = buildEatCandidatesFromSelection(items)
    if #candidates == 0 then
        logDebug("eat-all chain selected but found no candidates")
        return
    end

    startEatChain(playerObj, candidates, "all")
end

local function onEatUntilNotHungrySelected(items, playerIndex)
    local playerObj = getSpecificPlayer(playerIndex)
    if not playerObj then
        return
    end

    local candidates = buildEatCandidatesFromSelection(items)
    if #candidates == 0 then
        logDebug("eat-until-not-hungry selected but found no candidates")
        return
    end

    startEatChain(playerObj, candidates, "until-not-hungry")
end

local function onTick()
    if not isInventoryUpdateEnabled() then
        for playerIndex, _ in pairs(activeEatChains) do
            activeEatChains[playerIndex] = nil
        end
        return
    end

    for playerIndex, chain in pairs(activeEatChains) do
        local playerObj = getSpecificPlayer(playerIndex)
        if not playerObj or playerObj:isDead() then
            logDebug("eat chain removed: player missing or dead")
            activeEatChains[playerIndex] = nil
        elseif chain.cancelled then
            clearEatChain(playerIndex)
        elseif chain.pendingAction then
            -- The exact queued action owns progression through its perform/stop callbacks.
        elseif chain.lastActionCompleted then
            chain.lastActionCompleted = false
            if hasAnyTimedActionInProgress(playerObj) then
                logDebug("eat chain cancelled: another action was queued after eating")
                clearEatChain(playerIndex)
            else
                runEatChainStep(playerObj, chain)
            end
        else
            if not hasAnyTimedActionInProgress(playerObj) then
                runEatChainStep(playerObj, chain)
            end
        end
    end
end

local function addGrabFoodOptions(playerIndex, context, items)
    local playerObj = getSpecificPlayer(playerIndex)
    if not playerObj then
        return
    end

    local actualItems = getActualItems(items)
    local sourceContainer = getSourceContainerFromSelection(actualItems, playerObj)
    if not sourceContainer then
        return
    end

    if isFeatureEnabled("QoLforSacriel_UIFixes_EnableGrabAllRotten") then
        local rottenCandidates = collectFoodCandidatesFromContainer(sourceContainer, "rotten")
        if #rottenCandidates > 0 then
            local label = getTextOrFallback("UI_QoLforSacriel_InventoryUpdate_GrabAllRotten", "Grab All Rotten")
            context:addOption(label, { container = sourceContainer }, onGrabFoodFromContainer, "rotten", playerIndex)
        end
    end

    if isFeatureEnabled("QoLforSacriel_UIFixes_EnableGrabAllStale") then
        local staleCandidates = collectFoodCandidatesFromContainer(sourceContainer, "stale")
        if #staleCandidates > 0 then
            local label = getTextOrFallback("UI_QoLforSacriel_InventoryUpdate_GrabAllStale", "Grab All Stale")
            context:addOption(label, { container = sourceContainer }, onGrabFoodFromContainer, "stale", playerIndex)
        end
    end
end

local function addEatChainOptions(playerIndex, context, items)
    local eatSubMenu = findEatSubMenu(context)
    if not eatSubMenu then
        return
    end

    local candidates = buildEatCandidatesFromSelection(items)
    if #candidates <= 1 then
        return
    end

    if isFeatureEnabled("QoLforSacriel_UIFixes_EnableEatChainAll") then
        local label = getTextOrFallback("UI_QoLforSacriel_InventoryUpdate_EatAllChain", "Eat All (Chain)")
        if not eatSubMenu:getOptionFromName(label) then
            eatSubMenu:addOption(label, items, onEatAllChainSelected, playerIndex)
        end
    end

    if isFeatureEnabled("QoLforSacriel_UIFixes_EnableEatUntilNotHungry") then
        local label = getTextOrFallback("UI_QoLforSacriel_InventoryUpdate_EatUntilNotHungry", "Eat Until Not Hungry")
        if not eatSubMenu:getOptionFromName(label) then
            eatSubMenu:addOption(label, items, onEatUntilNotHungrySelected, playerIndex)
        end
    end
end

local function onFillInventoryObjectContextMenu(playerIndex, context, items)
    if not isInventoryUpdateEnabled() then
        return
    end

    addGrabFoodOptions(playerIndex, context, items)
    addEatChainOptions(playerIndex, context, items)
end

function InventoryUpdate.init(settings, logger)
    if installed then
        if logger and logger.debug then
            logger.debug("UIFixes.InventoryUpdate already installed")
        end
        return
    end

    settingsRef = settings
    loggerRef = logger

    Events.OnFillInventoryObjectContextMenu.Add(function(playerIndex, context, items)
        local ok, err = pcall(function()
            onFillInventoryObjectContextMenu(playerIndex, context, items)
        end)
        if not ok and loggerRef and loggerRef.error then
            loggerRef.error("UIFixes.InventoryUpdate context error: " .. tostring(err))
        end
    end)

    Events.OnTick.Add(function()
        local ok, err = pcall(onTick)
        if not ok and loggerRef and loggerRef.error then
            loggerRef.error("UIFixes.InventoryUpdate tick error: " .. tostring(err))
        end
    end)

    installed = true
    if logger and logger.info then
        logger.info("UIFixes.InventoryUpdate installed")
    end
end

return InventoryUpdate
