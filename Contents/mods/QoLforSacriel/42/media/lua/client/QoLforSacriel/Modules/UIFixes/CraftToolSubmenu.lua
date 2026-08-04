local CraftToolSubmenu = {}

local installed = false
local patched = false
local retryHookInstalled = false
local retryTickCounter = 0
local RETRY_TICK_INTERVAL = 120

local settingsRef = nil
local loggerRef = nil

local originalAddNewCraftingDynamicalContextMenu = nil

local ITEM_COLOR_SUFFIXES = {
    "black", "white", "red", "blue", "green", "yellow", "orange", "purple", "pink",
    "brown", "grey", "gray", "beige", "tan", "khaki", "olive", "navy", "cyan", "magenta",
    "light", "dark",
    "denim", "lightblue", "darkblue", "lightgreen", "darkgreen", "lightgrey", "darkgrey",
}

local function getCraftTooltipApi()
    if type(CraftTooltip) == "table" then
        return CraftTooltip
    end
    if type(ISRecipeTooltip) == "table" then
        return ISRecipeTooltip
    end
    return nil
end

local function safeReleaseCraftTooltips()
    local tooltipApi = getCraftTooltipApi()
    if tooltipApi and type(tooltipApi.releaseAll) == "function" then
        tooltipApi.releaseAll()
    end
end

local function logDebug(message)
    if not loggerRef or not loggerRef.debug then
        return
    end
    if not settingsRef or not settingsRef.get then
        return
    end
    if settingsRef.get("QoLforSacriel_DebugLogs") ~= true then
        return
    end
    loggerRef.debug("UIFixes.CraftToolSubmenu: " .. tostring(message))
end

local function isUiFixesEnabled()
    return settingsRef
        and settingsRef.isEnabled
        and settingsRef.isEnabled("QoLforSacriel_EnableUIFixes") == true
end

local function isCraftToolSubmenuEnabled()
    if not isUiFixesEnabled() then
        return false
    end
    return settingsRef.get("QoLforSacriel_UIFixes_EnableCraftToolSubmenu") == true
end

local function getMaxToolSlots()
    return 1
end

local function safeCallMethod(target, methodName, ...)
    if not target or type(methodName) ~= "string" then
        return false, nil
    end

    local okLookup, method = pcall(function()
        return target[methodName]
    end)
    if not okLookup or type(method) ~= "function" then
        return false, nil
    end

    local ok, value = pcall(method, target, ...)
    if not ok then
        return false, nil
    end

    return true, value
end

local function getListSize(list)
    if not list or type(list.size) ~= "function" then
        return 0
    end
    local okSize, size = pcall(list.size, list)
    if not okSize then
        return 0
    end
    return tonumber(size) or 0
end

local function getListValue(list, index)
    if not list or type(list.get) ~= "function" then
        return nil
    end
    local okGet, value = pcall(list.get, list, index)
    if not okGet then
        return nil
    end
    return value
end

local function isToolInputScript(inputScript)
    if not inputScript then
        return false
    end

    local okType, resourceType = safeCallMethod(inputScript, "getResourceType")
    if not okType or resourceType ~= ResourceType.Item then
        return false
    end

    local okLeft, isToolLeft = safeCallMethod(inputScript, "hasFlag", InputFlag.ToolLeft)
    local okRight, isToolRight = safeCallMethod(inputScript, "hasFlag", InputFlag.ToolRight)
    local okTool, isTool = safeCallMethod(inputScript, "isTool")
    return (okTool and isTool == true) or (okLeft and isToolLeft == true) or (okRight and isToolRight == true)
end

local function isItemResourceInputScript(inputScript)
    if not inputScript then
        return false
    end

    local okType, resourceType = safeCallMethod(inputScript, "getResourceType")
    return okType and resourceType == ResourceType.Item
end

local function isKeepItemInputScript(inputScript)
    if not inputScript then
        return false
    end

    local okType, resourceType = safeCallMethod(inputScript, "getResourceType")
    if not okType or resourceType ~= ResourceType.Item then
        return false
    end

    local okKeep, isKeep = safeCallMethod(inputScript, "isKeep")
    return okKeep and isKeep == true
end

local function getCandidateInputScripts(recipe)
    local candidateInputs = {}
    local okInputs, inputs = safeCallMethod(recipe, "getInputs")
    if not okInputs or not inputs then
        return candidateInputs
    end

    local count = getListSize(inputs)
    for i = 0, count - 1 do
        local inputScript = getListValue(inputs, i)
        if isItemResourceInputScript(inputScript) then
            candidateInputs[#candidateInputs + 1] = inputScript
        end
    end

    return candidateInputs
end

local function createRecipeLogic(playerObj, containers, recipe, selectedItem)
    local logic = HandcraftLogic.new(playerObj, nil, nil)
    logic:setContainers(containers)
    logic:setRecipeFromContextClick(recipe, selectedItem)
    return logic
end

local function getAllItemsFromContainers(containers)
    local items = ArrayList.new()
    local okItems, result = pcall(function()
        return CraftRecipeManager.getAllItemsFromContainers(containers, items)
    end)
    if okItems and result then
        return result
    end
    return items
end

local function getItemKey(item)
    if not item then
        return nil
    end

    local okFullType, fullType = safeCallMethod(item, "getFullType")
    if okFullType and fullType and fullType ~= "" then
        return tostring(fullType)
    end

    local okName, name = safeCallMethod(item, "getName")
    if okName and name and name ~= "" then
        return tostring(name)
    end

    return tostring(item)
end

local function getItemDisplayName(item)
    if not item then
        return "?"
    end

    local okDisplayName, displayName = safeCallMethod(item, "getDisplayName")
    if okDisplayName and displayName and displayName ~= "" then
        return tostring(displayName)
    end

    local okName, name = safeCallMethod(item, "getName")
    if okName and name and name ~= "" then
        return tostring(name)
    end

    return tostring(item)
end

local function getItemFullType(item)
    if not item then
        return nil
    end

    local okFullType, fullType = safeCallMethod(item, "getFullType")
    if okFullType and fullType and fullType ~= "" then
        return tostring(fullType)
    end

    return nil
end

local function normalizeItemFamilyKeyFromFullType(fullType)
    if not fullType or fullType == "" then
        return nil
    end

    local asText = tostring(fullType)
    local modulePart, itemPart = asText:match("^([^%.]+)%.(.+)$")
    if not modulePart or not itemPart then
        modulePart = ""
        itemPart = asText
    end

    local normalizedItem = string.lower(itemPart)
    local changed = true
    while changed do
        changed = false
        for i = 1, #ITEM_COLOR_SUFFIXES do
            local suffix = ITEM_COLOR_SUFFIXES[i]
            if normalizedItem:match("_" .. suffix .. "$") then
                normalizedItem = normalizedItem:sub(1, #normalizedItem - #suffix - 1)
                changed = true
                break
            end

            if normalizedItem:match(suffix .. "$") and #normalizedItem > (#suffix + 2) then
                normalizedItem = normalizedItem:sub(1, #normalizedItem - #suffix)
                changed = true
                break
            end
        end
    end

    normalizedItem = normalizedItem:gsub("[_%-]+$", "")
    return string.lower(modulePart) .. "." .. normalizedItem
end

local function getItemFamilyKey(item)
    local fullType = getItemFullType(item)
    if not fullType then
        return nil
    end
    return normalizeItemFamilyKeyFromFullType(fullType)
end

local function isInputScriptValidForItem(recipe, inputScript, item, playerObj)
    if not recipe or not inputScript or not item then
        return false
    end
    if type(CraftRecipeManager) ~= "table" or type(CraftRecipeManager.getAllValidInputScriptsForItem) ~= "function" then
        return false
    end

    local okScripts, validScripts = pcall(CraftRecipeManager.getAllValidInputScriptsForItem, recipe, item, playerObj)
    if not okScripts or not validScripts then
        return false
    end

    for i = 0, getListSize(validScripts) - 1 do
        if getListValue(validScripts, i) == inputScript then
            return true
        end
    end

    return false
end

local function collectToolCandidatesForScript(recipeData, recipe, inputScript, allItems, playerObj)
    local candidates = {}

    for i = 0, getListSize(allItems) - 1 do
        local item = getListValue(allItems, i)
        local matched = false
        if item and recipeData and recipeData.canOfferInputItem then
            matched = recipeData:canOfferInputItem(inputScript, item, false) == true
        end

        if (not matched) and item then
            matched = isInputScriptValidForItem(recipe, inputScript, item, playerObj)
        end

        if matched then
            candidates[#candidates + 1] = item
        end
    end

    return candidates
end

local function isSameItem(itemA, itemB)
    if not itemA or not itemB then
        return false
    end
    if itemA == itemB then
        return true
    end

    local okA, idA = safeCallMethod(itemA, "getID")
    local okB, idB = safeCallMethod(itemB, "getID")
    if okA and okB and idA ~= nil and idB ~= nil then
        return tonumber(idA) == tonumber(idB)
    end

    return false
end

local function hasSelectedItemCandidate(candidates, selectedItem)
    if not selectedItem then
        return false
    end

    for i = 1, #candidates do
        if isSameItem(candidates[i], selectedItem) then
            return true
        end
    end

    return false
end

local function isToolItemForRecipe(recipe, item, playerObj)
    if type(CraftRecipeManager) ~= "table" or type(CraftRecipeManager.isItemToolForRecipe) ~= "function" then
        return false
    end

    local ok1, result1 = pcall(CraftRecipeManager.isItemToolForRecipe, recipe, item, playerObj)
    if ok1 and result1 == true then
        return true
    end

    local ok2, result2 = pcall(CraftRecipeManager.isItemToolForRecipe, recipe, item, nil)
    if ok2 and result2 == true then
        return true
    end

    return false
end

local function filterToolItemsForRecipe(recipe, candidates, playerObj)
    local toolItems = {}

    for i = 1, #candidates do
        local item = candidates[i]
        if item and isToolItemForRecipe(recipe, item, playerObj) then
            toolItems[#toolItems + 1] = item
        end
    end

    return toolItems
end

local function buildToolSelectionBaseLabel(selection)
    local names = {}
    for i = 1, #selection do
        names[#names + 1] = getItemDisplayName(selection[i].item)
    end
    return table.concat(names, " + ")
end

local function getItemConditionText(item)
    if not item then
        return nil
    end

    local okCondition, condition = safeCallMethod(item, "getCondition")
    local okMax, conditionMax = safeCallMethod(item, "getConditionMax")
    if not okCondition or not okMax then
        return nil
    end

    condition = tonumber(condition)
    conditionMax = tonumber(conditionMax)
    if not condition or not conditionMax or conditionMax <= 0 then
        return nil
    end

    local percent = math.floor((condition / conditionMax) * 100 + 0.5)
    return tostring(condition) .. "/" .. tostring(conditionMax) .. " (" .. tostring(percent) .. "%)"
end

local function buildToolSelectionTooltipLabel(selection)
    local parts = {}

    for i = 1, #selection do
        local item = selection[i].item
        local part = getItemDisplayName(item)
        local conditionText = getItemConditionText(item)
        if conditionText then
            part = part .. " [" .. conditionText .. "]"
        end
        parts[#parts + 1] = part
    end

    return table.concat(parts, " + ")
end

local function buildToolSelectionTooltipDescription(selectedItem, toolSelection)
    local parts = {}
    parts[#parts + 1] = "Selected tool: " .. buildToolSelectionTooltipLabel(toolSelection)

    if toolSelection and #toolSelection > 0 then
        local tool = toolSelection[1] and toolSelection[1].item or nil
        local okSharpness, sharpness = false, nil
        if tool then
            okSharpness, sharpness = safeCallMethod(tool, "getSharpness")
        end
        if okSharpness and sharpness ~= nil then
            local numericSharpness = tonumber(sharpness)
            local sharpnessText = numericSharpness and tostring(math.floor(numericSharpness * 100 + 0.5) / 100) or tostring(sharpness)
            parts[#parts + 1] = "Sharpness: " .. sharpnessText
        end
    end

    return table.concat(parts, " <LINE> ")
end

local function getFirstSelectionTexture(toolSelection)
    if not toolSelection or #toolSelection == 0 then
        return nil
    end

    local first = toolSelection[1]
    if not first or not first.item then
        return nil
    end

    local item = first.item
    local okTexture, texture = safeCallMethod(item, "getTexture")
    if okTexture and texture then
        return texture
    end

    local okTex, tex = safeCallMethod(item, "getTex")
    if okTex and tex then
        return tex
    end

    return nil
end

local function buildSelectionLabels(selections)
    local baseLabels = {}
    local countsByBaseLabel = {}
    local seenByBaseLabel = {}

    for i = 1, #selections do
        local baseLabel = buildToolSelectionBaseLabel(selections[i])
        baseLabels[i] = baseLabel
        countsByBaseLabel[baseLabel] = (countsByBaseLabel[baseLabel] or 0) + 1
    end

    local labels = {}
    for i = 1, #selections do
        local baseLabel = baseLabels[i]
        if (countsByBaseLabel[baseLabel] or 0) > 1 then
            local ordinal = (seenByBaseLabel[baseLabel] or 0) + 1
            seenByBaseLabel[baseLabel] = ordinal
            labels[i] = baseLabel .. " [" .. tostring(ordinal) .. "]"
        else
            labels[i] = baseLabel
        end
    end

    return labels
end

local function buildToolSelections(variableToolInputScripts, candidateMap, fixedSelection)
    local selections = {}
    local current = {}
    local usedItems = {}

    if fixedSelection then
        for i = 1, #fixedSelection do
            usedItems[fixedSelection[i].item] = true
        end
    end

    local function visit(index)
        if index > #variableToolInputScripts then
            local copy = {}
            local cursor = 1
            if fixedSelection then
                for i = 1, #fixedSelection do
                    copy[cursor] = fixedSelection[i]
                    cursor = cursor + 1
                end
            end
            for i = 1, #current do
                copy[cursor] = current[i]
                cursor = cursor + 1
            end
            selections[#selections + 1] = copy
            return
        end

        local inputScript = variableToolInputScripts[index]
        local candidates = candidateMap[inputScript] or {}
        for i = 1, #candidates do
            local item = candidates[i]
            if not usedItems[item] then
                usedItems[item] = true
                current[#current + 1] = { inputScript = inputScript, item = item }
                visit(index + 1)
                current[#current] = nil
                usedItems[item] = nil
            end
        end
    end

    visit(1)
    return selections
end

local function applyToolSelectionToLogic(logic, toolSelection)
    if not logic or not toolSelection then
        return false
    end

    local recipeData = logic:getRecipeData()
    if not recipeData then
        return false
    end

    for i = 1, #toolSelection do
        local inputScript = toolSelection[i].inputScript
        local inputScriptData = recipeData:getDataForInputScript(inputScript)
        if inputScriptData then
            while inputScriptData:getLastInputItem() do
                inputScriptData:removeInputItem(inputScriptData:getLastInputItem())
            end
        end
    end

    local appliedAny = false
    for i = 1, #toolSelection do
        local success = recipeData:offerInputItem(toolSelection[i].inputScript, toolSelection[i].item, false)
        if success then
            appliedAny = true
        else
            logDebug("failed to apply chosen tool '" .. getItemDisplayName(toolSelection[i].item) .. "'")
            return false
        end
    end

    return appliedAny
end

local function decorateOption(option, recipeTexture, selectedItem)
    if not option or not recipeTexture then
        return
    end

    option.iconTexture = recipeTexture
    if selectedItem and selectedItem.getColor and selectedItem:getColor() then
        option.color = {}
        option.color.b = selectedItem:getColorBlue()
        option.color.r = selectedItem:getColorRed()
        option.color.g = selectedItem:getColorGreen()
    end
end

local function attachRecipeTooltip(option, playerObj, recipe, logic, recipeTexture, toolSelection)
    local tooltipApi = getCraftTooltipApi()
    if not tooltipApi or type(tooltipApi.addToolTip) ~= "function" then
        return
    end

    local tooltip = tooltipApi.addToolTip()
    if not tooltip then
        return
    end

    tooltip.character = playerObj
    tooltip.recipe = recipe
    tooltip.logic = logic
    local tooltipName = recipe:getTranslationName()
    if toolSelection and #toolSelection > 0 then
        tooltipName = tooltipName .. " - " .. buildToolSelectionTooltipLabel(toolSelection)
    end
    tooltip:setName(tooltipName)
    if recipeTexture then
        tooltip:setTextureDirectly(recipeTexture)
    end
    option.toolTip = tooltip
end

local function attachChildSelectionTooltip(option, recipe, selectedItem, toolSelection)
    if not option or not recipe or not toolSelection then
        return
    end

    local tooltip = nil
    if ISInventoryPaneContextMenu and type(ISInventoryPaneContextMenu.addToolTip) == "function" then
        tooltip = ISInventoryPaneContextMenu.addToolTip()
    else
        tooltip = ISToolTip:new()
    end

    if not tooltip then
        return
    end

    tooltip:setName(recipe:getTranslationName())
    tooltip.description = buildToolSelectionTooltipDescription(selectedItem, toolSelection)

    local selectionTexture = getFirstSelectionTexture(toolSelection)
    if selectionTexture and tooltip.setTextureDirectly then
        tooltip:setTextureDirectly(selectionTexture)
    end

    option.toolTip = tooltip
end

local getMatchingItemCountByFamilyKey

local function getMatchingSelectedItemCount(containers, selectedItem)
    if not containers or not selectedItem then
        return 0
    end

    local selectedFamilyKey = getItemFamilyKey(selectedItem)
    if not selectedFamilyKey then
        return 1
    end

    return getMatchingItemCountByFamilyKey(containers, selectedFamilyKey)
end

getMatchingItemCountByFamilyKey = function(containers, familyKey)
    if not containers then
        return 0
    end

    if not familyKey or familyKey == "" then
        return 1
    end

    local allItems = getAllItemsFromContainers(containers)
    if not allItems then
        return 1
    end

    local count = 0
    for i = 0, getListSize(allItems) - 1 do
        local item = getListValue(allItems, i)
        local itemFamilyKey = getItemFamilyKey(item)
        if itemFamilyKey ~= nil and itemFamilyKey == familyKey then
            count = count + 1
        end
    end

    return count
end

local function getCraftAmountLabel(mode)
    if mode == "all" then
        return "All"
    end
    return "One"
end

local function closeContextMenu(menu)
    if not menu then
        return
    end

    if menu.hideAndChildren then
        menu:hideAndChildren()
        return
    end

    if menu.setVisible then
        menu:setVisible(false)
        return
    end

    if menu.setHide then
        menu:setHide(true)
    end
end

local function getValidInputScriptForItem(recipe, item, playerObj)
    if not recipe or not item then
        return nil
    end
    if type(CraftRecipeManager) ~= "table" or type(CraftRecipeManager.getValidInputScriptForItem) ~= "function" then
        return nil
    end

    local okScript, inputScript = pcall(CraftRecipeManager.getValidInputScriptForItem, recipe, item, playerObj)
    if not okScript then
        return nil
    end
    return inputScript
end

local function itemMatchesAllQueueState(playerObj, state, item)
    if not state or not item then
        return false
    end

    local itemFamilyKey = getItemFamilyKey(item)
    if not itemFamilyKey or not state.familyKey or itemFamilyKey ~= state.familyKey then
        return false
    end

    if state.selectedInputScript then
        local inputScript = getValidInputScriptForItem(state.recipe, item, playerObj)
        return inputScript ~= nil and inputScript == state.selectedInputScript
    end

    return true
end

local function getMatchingItemCountForAllState(playerObj, state, containers)
    if not state or not containers then
        return 0
    end

    local allItems = getAllItemsFromContainers(containers)
    if not allItems then
        return 0
    end

    local count = 0
    for i = 0, getListSize(allItems) - 1 do
        local item = getListValue(allItems, i)
        if itemMatchesAllQueueState(playerObj, state, item) then
            count = count + 1
        end
    end

    return count
end

local function findNextMatchingItemForFamily(playerObj, familyKey)
    if not playerObj or not familyKey or familyKey == "" then
        return nil
    end

    local inventory = playerObj:getInventory()
    if not inventory then
        return nil
    end

    local okItems, items = pcall(function()
        return inventory:getAllEvalRecurse(function(it)
            if not it then
                return false
            end
            return getItemFamilyKey(it) == familyKey
        end)
    end)
    if not okItems or not items or getListSize(items) <= 0 then
        return nil
    end

    return getListValue(items, 0)
end

local function findNextMatchingItemForAllState(playerObj, state, containers)
    if not state or not containers then
        return nil
    end

    local allItems = getAllItemsFromContainers(containers)
    if not allItems then
        return nil
    end

    for i = 0, getListSize(allItems) - 1 do
        local item = getListValue(allItems, i)
        if itemMatchesAllQueueState(playerObj, state, item) then
            return item
        end
    end

    return nil
end

local function appendDeferredReturnItems(state, items)
    if not state or not items then
        return
    end

    if not state.deferredReturnItems then
        state.deferredReturnItems = {}
    end

    for i = 1, #items do
        state.deferredReturnItems[#state.deferredReturnItems + 1] = items[i]
    end
end

local function flushDeferredReturnItems(state)
    if not state or not state.deferredReturnItems or #state.deferredReturnItems == 0 then
        return
    end

    local playerObj = getSpecificPlayer(state.player)
    if not playerObj then
        state.deferredReturnItems = {}
        return
    end

    ISCraftingUI.ReturnItemsToOriginalContainer(playerObj, state.deferredReturnItems)
    state.deferredReturnItems = {}
end

local function performSingleCraftWithToolSelection(selectedItem, recipe, player, eatPercentage, toolSelection, onCompleteFunc, onCompleteTarget, allState)
    local playerObj = getSpecificPlayer(player)
    local containers = ISInventoryPaneContextMenu.getContainers(playerObj)
    local logic = HandcraftLogic.new(playerObj, nil, nil)
    logic:setIsoObject(logic:findCraftSurface(playerObj, 2))
    logic:setContainers(containers)
    logic:setRecipeFromContextClick(recipe, selectedItem)

    if not applyToolSelectionToLogic(logic, toolSelection) then
        return false
    end

    if logic:canPerformCurrentRecipe() then
        local items = logic:getRecipeData():getAllInputItems()
        local itemsToReturn = logic:getRecipeData():getAllPutBackInputItems()

        if logic:isUsingRecipeAtHandBenefit() then
            local recipeAtHandItem = logic:getUsingRecipeAtHandItem()
            if recipeAtHandItem then
                items:add(recipeAtHandItem)
                itemsToReturn:add(recipeAtHandItem)
            end
        end

        local returnToContainer = {}
        if not recipe:isCanBeDoneFromFloor() then
            local itemsWereMoved = false
            for i = 1, items:size() do
                local item = items:get(i - 1)
                if item:getContainer() ~= playerObj:getInventory() then
                    ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
                    if itemsToReturn:contains(item) then
                        table.insert(returnToContainer, item)
                    end
                    itemsWereMoved = true
                end
            end
            if itemsWereMoved then
                logic:setRecipeFromContextClick(recipe, selectedItem)
                if not applyToolSelectionToLogic(logic, toolSelection) then
                    return false
                end
            end
        end

        local action = ISEntityUI.HandcraftStart(playerObj, logic, false, true, eatPercentage)
        if action then
            if onCompleteFunc then
                local payload = onCompleteTarget
                if not payload then
                    payload = {}
                end
                payload.logic = logic
                action:setOnComplete(onCompleteFunc, payload)
            else
                action:setOnComplete(ISInventoryPaneContextMenu.OnNewCraftComplete, logic)
            end
            logic:startCraftAction(action)

            if allState then
                appendDeferredReturnItems(allState, returnToContainer)
            else
                ISCraftingUI.ReturnItemsToOriginalContainer(playerObj, returnToContainer)
            end
            return true
        end

        if allState then
            appendDeferredReturnItems(allState, returnToContainer)
        else
            ISCraftingUI.ReturnItemsToOriginalContainer(playerObj, returnToContainer)
        end
    end

    return false
end

local function onCraftWithToolSelectionAllContinue(payload)
    if not payload or not payload.state then
        return
    end

    local state = payload.state
    local playerObj = getSpecificPlayer(state.player)
    local containers = ISInventoryPaneContextMenu.getContainers(playerObj)
    if payload.logic then
        ISInventoryPaneContextMenu.OnNewCraftComplete(payload.logic)
    end

    local currentCount = getMatchingItemCountForAllState(playerObj, state, containers)
    if currentCount >= state.lastObservedCount then
        logDebug(
            "all craft queue stopped: no progress detected (likely interrupted), family='"
            .. tostring(state.familyKey)
            .. "', previousCount=" .. tostring(state.lastObservedCount)
            .. ", currentCount=" .. tostring(currentCount)
        )
        flushDeferredReturnItems(state)
        return
    end

    state.lastObservedCount = currentCount
    if currentCount <= 0 then
        logDebug("all craft queue complete")
        flushDeferredReturnItems(state)
        return
    end

    local nextItem = findNextMatchingItemForAllState(playerObj, state, containers)
    if not nextItem then
        logDebug("all craft queue stopped: no next matching item for family='" .. tostring(state.familyKey) .. "'")
        flushDeferredReturnItems(state)
        return
    end

    logDebug("all craft queue continue: remaining=" .. tostring(currentCount) .. ", next='" .. tostring(getItemDisplayName(nextItem)) .. "'")

    local queued = performSingleCraftWithToolSelection(
        nextItem,
        state.recipe,
        state.player,
        state.eatPercentage,
        state.toolSelection,
        onCraftWithToolSelectionAllContinue,
        { state = state },
        state
    )

    if not queued then
        logDebug("all craft queue stopped: failed to queue next craft action")
        flushDeferredReturnItems(state)
    end
end

local function onCraftWithToolSelection(selectedItem, recipe, player, all, eatPercentage, toolSelection, contextMenu)
    local playerObj = getSpecificPlayer(player)
    local containers = ISInventoryPaneContextMenu.getContainers(playerObj)
    closeContextMenu(contextMenu)

    if all then
        local familyKey = getItemFamilyKey(selectedItem)
        local selectedInputScript = getValidInputScriptForItem(recipe, selectedItem, playerObj)
        local sameFamilyCount = getMatchingSelectedItemCount(containers, selectedItem)
        local recipeAwareCount = sameFamilyCount

        if selectedInputScript then
            local countState = {
                recipe = recipe,
                familyKey = familyKey,
                selectedInputScript = selectedInputScript,
            }
            recipeAwareCount = getMatchingItemCountForAllState(playerObj, countState, containers)
        end

        logDebug(
            "all craft requested: selected='" .. tostring(getItemDisplayName(selectedItem))
            .. "', family='" .. tostring(familyKey)
            .. "', sameFamilyCount=" .. tostring(sameFamilyCount)
            .. ", recipeAwareCount=" .. tostring(recipeAwareCount)
        )

        if recipeAwareCount <= 1 then
            performSingleCraftWithToolSelection(selectedItem, recipe, player, eatPercentage, toolSelection)
            return
        end

        local state = {
            recipe = recipe,
            player = player,
            eatPercentage = eatPercentage,
            toolSelection = toolSelection,
            familyKey = familyKey,
            selectedInputScript = selectedInputScript,
            lastObservedCount = recipeAwareCount,
            deferredReturnItems = {},
        }

        local queued = performSingleCraftWithToolSelection(
            selectedItem,
            recipe,
            player,
            eatPercentage,
            toolSelection,
            onCraftWithToolSelectionAllContinue,
            { state = state },
            state
        )

        if not queued then
            logDebug("all craft queue start failed")
            flushDeferredReturnItems(state)
        else
            logDebug("all craft queue started: planned crafts=" .. tostring(recipeAwareCount))
        end
        return
    end

    performSingleCraftWithToolSelection(selectedItem, recipe, player, eatPercentage, toolSelection)
end

local function shouldUseSubmenuForRecipe(recipe, selectedItem, playerObj, containers)
    local recipeName = "<unknown>"
    local okRecipeName, resolvedRecipeName = safeCallMethod(recipe, "getTranslationName")
    if okRecipeName and resolvedRecipeName and resolvedRecipeName ~= "" then
        recipeName = tostring(resolvedRecipeName)
    end

    local candidateInputScripts = getCandidateInputScripts(recipe)
    if #candidateInputScripts == 0 then
        logDebug("recipe '" .. recipeName .. "' has no item input scripts")
        return false, nil
    end

    local logic = createRecipeLogic(playerObj, containers, recipe, selectedItem)
    local recipeData = logic:getRecipeData()
    if not recipeData then
        return false, nil
    end

    local allItems = getAllItemsFromContainers(containers)
    local candidateMap = {}
    local fixedSelection = {}
    local variableToolInputScripts = {}

    for i = 1, #candidateInputScripts do
        local inputScript = candidateInputScripts[i]
        local candidates = collectToolCandidatesForScript(recipeData, recipe, inputScript, allItems, playerObj)
        if #candidates == 0 then
            logDebug("recipe '" .. recipeName .. "' input slot " .. tostring(i) .. " has no candidates")
        else
            local explicitTool = isToolInputScript(inputScript)
            local selectedItemCandidate = hasSelectedItemCandidate(candidates, selectedItem)
            local toolItems = filterToolItemsForRecipe(recipe, candidates, playerObj)
            local inferredByRecipe = #toolItems > 0
            local choiceBearingKeepInput = (not explicitTool)
                and (not inferredByRecipe)
                and isKeepItemInputScript(inputScript)
                and #candidates > 1
                and (not selectedItemCandidate)
            local toolLike = explicitTool or inferredByRecipe or choiceBearingKeepInput

            if not toolLike then
                logDebug(
                    "recipe '" .. recipeName .. "' skipping non-tool input slot " .. tostring(i)
                    .. " (selectedItemCandidate=" .. tostring(selectedItemCandidate)
                    .. ", keep=" .. tostring(isKeepItemInputScript(inputScript))
                    .. ", candidates=" .. tostring(#candidates) .. ")"
                )
            else
                local effectiveCandidates = candidates
                if inferredByRecipe then
                    effectiveCandidates = toolItems
                end

                if #effectiveCandidates == 0 then
                    logDebug("recipe '" .. recipeName .. "' tool-like slot " .. tostring(i) .. " has no effective candidates")
                else
                    candidateMap[inputScript] = effectiveCandidates
                    if #effectiveCandidates == 1 then
                        fixedSelection[#fixedSelection + 1] = { inputScript = inputScript, item = effectiveCandidates[1] }
                    else
                        variableToolInputScripts[#variableToolInputScripts + 1] = inputScript
                    end
                end
            end
        end
    end

    local effectiveToolSlotCount = #variableToolInputScripts
    if effectiveToolSlotCount == 0 or effectiveToolSlotCount > getMaxToolSlots() then
        logDebug(
            "recipe '" .. recipeName .. "' skipped: effectiveToolSlotCount=" .. tostring(effectiveToolSlotCount)
            .. ", maxToolSlots=" .. tostring(getMaxToolSlots())
        )
        return false, nil
    end

    local selections = buildToolSelections(variableToolInputScripts, candidateMap, fixedSelection)
    if #selections <= 1 then
        logDebug("recipe '" .. recipeName .. "' skipped: selection count=" .. tostring(#selections))
        return false, nil
    end

    logDebug(
        "recipe '" .. recipeName .. "' submenu enabled: variableSlots=" .. tostring(effectiveToolSlotCount)
        .. ", selections=" .. tostring(#selections)
    )

    return true, {
        logic = logic,
        selections = selections,
        selectionLabels = buildSelectionLabels(selections),
    }
end

local function patchInventoryPaneContextMenu()
    if patched then
        return true
    end

    pcall(require, "ISUI/ISInventoryPaneContextMenu")
    if not ISInventoryPaneContextMenu or not ISInventoryPaneContextMenu.addNewCraftingDynamicalContextMenu then
        return false
    end

    originalAddNewCraftingDynamicalContextMenu = ISInventoryPaneContextMenu.addNewCraftingDynamicalContextMenu

    ISInventoryPaneContextMenu.addNewCraftingDynamicalContextMenu = function(selectedItem, context, recipeList, player, containerList)
        if not isCraftToolSubmenuEnabled() then
            return originalAddNewCraftingDynamicalContextMenu(selectedItem, context, recipeList, player, containerList)
        end

        safeReleaseCraftTooltips()
        local rootContext = context
        local playerObj = getSpecificPlayer(player)
        local containers = ISInventoryPaneContextMenu.getContainers(playerObj)
        local matchingSelectedItemCount = getMatchingSelectedItemCount(containers, selectedItem)
        if recipeList:size() > 1 then
            local option = context:addOption(selectedItem:getDisplayName())
            option.iconTexture = selectedItem:getIcon():splitIcon()
            local subMenu = context:getNew(context)
            context:addSubMenu(option, subMenu)
            context = subMenu
        end

        for i = 0, recipeList:size() - 1 do
            local recipe = recipeList:get(i)
            local logic = createRecipeLogic(playerObj, containers, recipe, selectedItem)
            local recipeName = getText(recipe:getTranslationName())
            local recipeTexture = logic:getResultTexture() or selectedItem:getTexture() or nil
            if selectedItem and not recipeTexture then
                recipeTexture = selectedItem:getTexture()
            end

            local useSubmenu, submenuData = shouldUseSubmenuForRecipe(recipe, selectedItem, playerObj, containers)
            if useSubmenu then
                local parentOption = context:addOption(recipeName, nil)
                decorateOption(parentOption, recipeTexture, selectedItem)

                local toolMenu = context:getNew(context)
                context:addSubMenu(parentOption, toolMenu)

                for selectionIndex = 1, #submenuData.selections do
                    local toolSelection = submenuData.selections[selectionIndex]
                    local selectionLabel = submenuData.selectionLabels[selectionIndex] or buildToolSelectionBaseLabel(toolSelection)
                    local toolTexture = getFirstSelectionTexture(toolSelection) or recipeTexture
                    if matchingSelectedItemCount > 1 then
                        local childOption = toolMenu:addOption(selectionLabel, nil)
                        decorateOption(childOption, toolTexture, nil)

                        local amountMenu = context:getNew(context)
                        context:addSubMenu(childOption, amountMenu)

                        local oneOption = amountMenu:addOption(getCraftAmountLabel("one"), selectedItem, onCraftWithToolSelection, recipe, player, false, nil, toolSelection, rootContext)
                        decorateOption(oneOption, toolTexture, nil)
                        attachChildSelectionTooltip(oneOption, recipe, selectedItem, toolSelection)

                        local allOption = amountMenu:addOption(getCraftAmountLabel("all"), selectedItem, onCraftWithToolSelection, recipe, player, true, nil, toolSelection, rootContext)
                        decorateOption(allOption, toolTexture, nil)
                        attachChildSelectionTooltip(allOption, recipe, selectedItem, toolSelection)
                    else
                        local childOption = toolMenu:addOption(selectionLabel, selectedItem, onCraftWithToolSelection, recipe, player, false, nil, toolSelection, rootContext)
                        decorateOption(childOption, toolTexture, nil)
                        attachChildSelectionTooltip(childOption, recipe, selectedItem, toolSelection)
                    end
                end
            else
                local option = context:addOption(recipeName, selectedItem, ISInventoryPaneContextMenu.OnNewCraft, recipe, player, false)
                decorateOption(option, recipeTexture, selectedItem)
                attachRecipeTooltip(option, playerObj, recipe, logic, recipeTexture)
            end
        end
    end

    patched = true
    if loggerRef and loggerRef.info then
        loggerRef.info("UIFixes.CraftToolSubmenu patched inventory craft menu")
    end
    return true
end

local function tryPatchAll()
    return patchInventoryPaneContextMenu()
end

local function onRetryTick()
    retryTickCounter = retryTickCounter + 1
    if retryTickCounter % RETRY_TICK_INTERVAL ~= 0 then
        return
    end

    if tryPatchAll() then
        if retryHookInstalled and Events and Events.OnTick then
            Events.OnTick.Remove(onRetryTick)
            retryHookInstalled = false
        end
        if loggerRef and loggerRef.info then
            loggerRef.info("UIFixes.CraftToolSubmenu delayed patching completed")
        end
    end
end

function CraftToolSubmenu.init(settings, logger)
    settingsRef = settings
    loggerRef = logger

    if installed then
        if logger and logger.debug then
            logger.debug("UIFixes.CraftToolSubmenu already installed")
        end
        return
    end

    local patchedNow = tryPatchAll()
    if (not patchedNow) and Events and Events.OnTick and (not retryHookInstalled) then
        Events.OnTick.Add(onRetryTick)
        retryHookInstalled = true
        if logger and logger.info then
            logger.info("UIFixes.CraftToolSubmenu waiting for UI class load; retry hook installed")
        end
    end

    installed = true
    if logger and logger.info then
        logger.info("UIFixes.CraftToolSubmenu installed")
    end
end

return CraftToolSubmenu
