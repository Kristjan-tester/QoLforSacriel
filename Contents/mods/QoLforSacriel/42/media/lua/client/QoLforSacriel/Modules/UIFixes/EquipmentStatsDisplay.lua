local EquipmentStatsDisplay = {}

local installed = false
local inventoryPatched = false
local craftPatched = false
local fallbackPatched = false
local inventoryTooltipPatched = false
local retryHookInstalled = false
local retryTickCounter = 0
local RETRY_TICK_INTERVAL = 120

local settingsRef = nil
local loggerRef = nil

local originalDrawItemDetails = nil
local originalWidgetOutputUpdateScriptValues = nil
local originalWidgetInputUpdateScriptValues = nil
local originalWidgetOutputUpdateValues = nil
local originalWidgetInputUpdateValues = nil
local originalCraftLogicInputControlCreateDynamicChildren = nil
local originalToolTipItemSlotRender = nil
local originalToolTipInvRender = nil
local originalWidgetTitleHeaderUpdateLabels = nil

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
    loggerRef.debug("UIFixes.EquipmentStatsDisplay: " .. tostring(message))
end

local function isUiFixesEnabled()
    return settingsRef
        and settingsRef.isEnabled
        and settingsRef.isEnabled("QoLforSacriel_EnableUIFixes") == true
end

local function isExactStatsEnabled()
    if not isUiFixesEnabled() then
        return false
    end
    return settingsRef.get("QoLforSacriel_UIFixes_EnableExactEquipmentStats") == true
end

local function isCraftOutputTooltipEnabled()
    if not isUiFixesEnabled() then
        return false
    end
    return settingsRef.get("QoLforSacriel_UIFixes_EnableCraftOutputItemTooltip") == true
end

local function isShowAllEquipmentStatsEnabled()
    if not isUiFixesEnabled() then
        return false
    end
    return settingsRef.get("QoLforSacriel_UIFixes_ShowAllEquipmentTooltipStats") == true
end

local function formatCurrentMax(currentValue, maxValue)
    local current = math.max(0, math.floor(tonumber(currentValue) or 0))
    local max = math.max(0, math.floor(tonumber(maxValue) or 0))
    if max <= 0 then
        return tostring(current)
    end
    if current > max then
        current = max
    end
    return tostring(current) .. "/" .. tostring(max)
end

local function toNumberOrNil(value)
    local n = tonumber(value)
    if n == nil then
        return nil
    end
    return n
end

local function formatFloat(value, decimals)
    local n = toNumberOrNil(value)
    if n == nil then
        return nil
    end
    return string.format("%0." .. tostring(decimals) .. "f", n)
end

local function safeCallItemMethod(item, methodName)
    if not item or type(methodName) ~= "string" then
        return false, nil
    end

    local okLookup, method = pcall(function()
        return item[methodName]
    end)
    if not okLookup then
        return false, nil
    end
    if type(method) ~= "function" then
        return false, nil
    end

    local ok, value = pcall(method, item)
    if not ok then
        return false, nil
    end

    return true, value
end

local function safeCallMethod(target, methodName, ...)
    if not target or type(methodName) ~= "string" then
        return false, nil
    end

    local okLookup, method = pcall(function()
        return target[methodName]
    end)
    if not okLookup then
        return false, nil
    end
    if type(method) ~= "function" then
        return false, nil
    end

    local ok, value = pcall(method, target, ...)
    if not ok then
        return false, nil
    end

    return true, value
end

local function safeGetMethod(target, methodName)
    if not target or type(methodName) ~= "string" then
        return false, nil
    end

    local okLookup, method = pcall(function()
        return target[methodName]
    end)
    if not okLookup or type(method) ~= "function" then
        return false, nil
    end

    return true, method
end

local function normalizeDisplayCategory(value)
    if value == nil then
        return nil
    end
    return tostring(value):gsub("[^%a]", ""):lower()
end

local function getItemDisplayCategory(item)
    if not item then
        return nil
    end

    local okCategory, displayCategory = safeCallItemMethod(item, "getDisplayCategory")
    if okCategory and displayCategory ~= nil then
        return displayCategory
    end

    local okScriptItem, scriptItem = safeCallItemMethod(item, "getScriptItem")
    if okScriptItem and scriptItem and type(scriptItem.getDisplayCategory) == "function" then
        local okScriptCategory, scriptDisplayCategory = pcall(scriptItem.getDisplayCategory, scriptItem)
        if okScriptCategory then
            return scriptDisplayCategory
        end
    end

    return nil
end

local function isStrictWeaponItem(item)
    if not item then
        return false
    end

    if instanceof and instanceof(item, "HandWeapon") then
        return true
    end

    local category = normalizeDisplayCategory(getItemDisplayCategory(item))
    if category == "weapon" then
        return true
    end
    if category and #category >= 6 and category:sub(-6) == "weapon" then
        return true
    end

    -- Some crafted weapons do not expose stable weapon category/type, but do expose weapon stats.
    local okMinDamage, minDamage = safeCallItemMethod(item, "getMinDamage")
    local okMaxDamage, maxDamage = safeCallItemMethod(item, "getMaxDamage")
    if okMinDamage and okMaxDamage and tonumber(minDamage) and tonumber(maxDamage) then
        local minValue = tonumber(minDamage) or 0
        local maxValue = tonumber(maxDamage) or 0
        if minValue > 0 or maxValue > 0 then
            return true
        end
    end

    return false
end

local function toStatStringOrNA(value, decimals)
    if value == nil then
        return "N/A"
    end

    local numericValue = tonumber(value)
    if numericValue ~= nil then
        if decimals ~= nil then
            return string.format("%0." .. tostring(decimals) .. "f", numericValue)
        end
        if numericValue == math.floor(numericValue) then
            return tostring(math.floor(numericValue))
        end
        return tostring(numericValue)
    end

    local asText = tostring(value)
    if asText == "" then
        return "N/A"
    end
    return asText
end

local function getMethodValueOrNA(item, methodName, decimals)
    local ok, value = safeCallItemMethod(item, methodName)
    if not ok then
        return "N/A"
    end
    return toStatStringOrNA(value, decimals)
end

local function collectEquipmentStats(item, options)
    if not item then
        return {}
    end

    if not isStrictWeaponItem(item) then
        return {}
    end

    local omitIdentityStats = options and options.omitIdentityStats == true
    local forceFullStats = options and options.forceFullStats == true

    local lines = {}

    if not omitIdentityStats then
        local okCondition, conditionValue = safeCallItemMethod(item, "getCondition")
        local okConditionMax, conditionMax = safeCallItemMethod(item, "getConditionMax")
        local conditionText = "N/A"
        if okCondition and okConditionMax and toNumberOrNil(conditionMax) and conditionMax > 0 then
            conditionText = formatCurrentMax(conditionValue, conditionMax)
        elseif okCondition and conditionValue ~= nil then
            conditionText = toStatStringOrNA(conditionValue)
        end
        table.insert(lines, (getTextOrNull("IGUI_invpanel_Condition") or "Condition") .. ": " .. conditionText)
    end

    local okMinDamage, minDamage = safeCallItemMethod(item, "getMinDamage")
    local okMaxDamage, maxDamage = safeCallItemMethod(item, "getMaxDamage")
    local damageText = "N/A"
    if okMinDamage and okMaxDamage and minDamage ~= nil and maxDamage ~= nil then
        local minText = formatFloat(minDamage, 2)
        local maxText = formatFloat(maxDamage, 2)
        if minText and maxText then
            damageText = minText .. "-" .. maxText
        end
    end
    table.insert(lines, "Damage: " .. damageText)

    if not forceFullStats and not isShowAllEquipmentStatsEnabled() then
        return lines
    end

    table.insert(lines, "Door Damage: " .. getMethodValueOrNA(item, "getDoorDamage"))
    table.insert(lines, "Tree Damage: " .. getMethodValueOrNA(item, "getTreeDamage"))
    table.insert(lines, "Minimum Range: " .. getMethodValueOrNA(item, "getMinRange", 2))
    table.insert(lines, "Maximum Range: " .. getMethodValueOrNA(item, "getMaxRange", 2))
    table.insert(lines, "Attack Speed: " .. getMethodValueOrNA(item, "getBaseSpeed", 2))
    table.insert(lines, "Critical Hit Chance: " .. getMethodValueOrNA(item, "getCriticalChance", 2))
    table.insert(lines, "Critical Hit Multiplier: " .. getMethodValueOrNA(item, "getCriticalDamageMultiplier", 2))

    local knockbackValue = getMethodValueOrNA(item, "getPushBackMod", 2)
    if knockbackValue == "N/A" then
        knockbackValue = getMethodValueOrNA(item, "getKnockdownMod", 2)
    end
    table.insert(lines, "Knockback: " .. knockbackValue)

    if not omitIdentityStats then
        local okSharpness, sharpness = safeCallItemMethod(item, "getSharpness")
        if okSharpness and sharpness ~= nil then
            local sharpnessText = formatFloat(sharpness, 2)
            if sharpnessText then
                table.insert(lines, "Sharpness: " .. sharpnessText)
            else
                table.insert(lines, "Sharpness: N/A")
            end
        else
            table.insert(lines, "Sharpness: N/A")
        end
    end

    return lines
end

local function buildStatsDescription(item, options)
    local lines = collectEquipmentStats(item, options)
    if #lines == 0 then
        return nil
    end
    return table.concat(lines, " <BR> ")
end

local function createInventoryItemByFullName(fullName)
    if not fullName or fullName == "" then
        return nil
    end
    if not InventoryItemFactory or not InventoryItemFactory.CreateItem then
        return nil
    end

    local ok, result = pcall(function()
        return InventoryItemFactory.CreateItem(fullName)
    end)
    if not ok or not result then
        return nil
    end

    return result
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

local function getRecipeDisplayName(recipe)
    if not recipe then
        return "<none>"
    end

    local okTranslated, translatedName = safeCallMethod(recipe, "getTranslationName")
    if okTranslated and translatedName and translatedName ~= "" then
        return tostring(translatedName)
    end

    local okName, internalName = safeCallMethod(recipe, "getName")
    if okName and internalName and internalName ~= "" then
        return tostring(internalName)
    end

    return "<unknown>"
end

local function getLogicRecipeSignature(logic)
    if not logic then
        return "<none>"
    end

    local okRecipe, recipe = safeCallMethod(logic, "getRecipe")
    if not okRecipe or not recipe then
        return "<none>"
    end

    return getRecipeDisplayName(recipe)
end

local function instantiateCraftingItemPrototype(prototype)
    if not prototype then
        return nil
    end

    local okInstance, instance = safeCallMethod(prototype, "InstanceItem", nil, true)
    if okInstance and instance then
        return instance
    end

    local okInstanceFallback, fallbackInstance = safeCallMethod(prototype, "InstanceItem", nil)
    if okInstanceFallback and fallbackInstance then
        return fallbackInstance
    end

    return nil
end

local function tryResolveOutputCandidateItem(candidate)
    if not candidate then
        return nil
    end

    local candidatePrototype = instantiateCraftingItemPrototype(candidate)
    if candidatePrototype then
        return candidatePrototype
    end

    local okCandidateScriptItem, candidateScriptItem = safeCallItemMethod(candidate, "getScriptItem")
    if okCandidateScriptItem and candidateScriptItem then
        local scriptPrototype = instantiateCraftingItemPrototype(candidateScriptItem)
        if scriptPrototype then
            return scriptPrototype
        end
    end

    local fullName = nil
    local okFullType, resolvedFullType = safeCallMethod(candidate, "getFullType")
    if okFullType and resolvedFullType and resolvedFullType ~= "" then
        fullName = tostring(resolvedFullType)
    end

    local okFullName, resolvedFullName = safeCallMethod(candidate, "getFullName")
    if (not fullName or fullName == "") and okFullName and resolvedFullName and resolvedFullName ~= "" then
        fullName = tostring(resolvedFullName)
    end

    if (not fullName or fullName == "") then
        local okModule, moduleName = safeCallMethod(candidate, "getModuleName")
        local okName, itemName = safeCallMethod(candidate, "getName")
        if okModule and okName and moduleName and itemName and moduleName ~= "" and itemName ~= "" then
            fullName = tostring(moduleName) .. "." .. tostring(itemName)
        end
    end

    local reconstructed = createInventoryItemByFullName(fullName)
    if reconstructed then
        return reconstructed
    end

    return candidateScriptItem or candidate
end

local function describePossibleItemFromIoScript(ioScript, methodName)
    if not ioScript then
        return "?"
    end

    local okList, objectList = safeCallMethod(ioScript, methodName)
    if not okList or not objectList or getListSize(objectList) <= 0 then
        return "?"
    end

    local first = getListValue(objectList, 0)
    if not first then
        return "?"
    end

    local okDisplay, displayName = safeCallMethod(first, "getDisplayName")
    if okDisplay and displayName and displayName ~= "" then
        return tostring(displayName)
    end

    local okFullType, fullType = safeCallMethod(first, "getFullType")
    if okFullType and fullType and fullType ~= "" then
        return tostring(fullType)
    end

    return "?"
end

local function describeIoScript(ioScript, ioType, index)
    if not ioScript then
        return "#" .. tostring(index + 1) .. " ?"
    end

    local descriptor = "?"
    local okType, resourceType = safeCallMethod(ioScript, "getResourceType")
    if okType and resourceType == ResourceType.Item then
        local amountText = nil
        local okIntAmount, intAmount = safeCallMethod(ioScript, "getIntAmount")
        if okIntAmount and tonumber(intAmount) then
            amountText = tostring(math.max(0, math.floor(tonumber(intAmount))))
        else
            local okAmount, amount = safeCallMethod(ioScript, "getAmount")
            if okAmount and tonumber(amount) then
                amountText = tostring(tonumber(amount))
            end
        end

        local itemName = "?"
        if ioType == "input" then
            itemName = describePossibleItemFromIoScript(ioScript, "getPossibleInputItems")
        else
            itemName = describePossibleItemFromIoScript(ioScript, "getPossibleResultItems")
        end

        descriptor = "Item"
        if amountText then
            descriptor = descriptor .. " x" .. amountText
        end
        descriptor = descriptor .. " " .. itemName
    elseif okType and resourceType == ResourceType.Fluid then
        local okAmount, amount = safeCallMethod(ioScript, "getAmount")
        local amountText = (okAmount and tonumber(amount)) and tostring(round(tonumber(amount), 2)) .. "L" or "?"
        descriptor = "Fluid " .. amountText
    elseif okType and resourceType == ResourceType.Energy then
        local okAmount, amount = safeCallMethod(ioScript, "getAmount")
        local amountText = (okAmount and tonumber(amount)) and tostring(round(tonumber(amount), 2)) or "?"
        descriptor = "Energy " .. amountText
    end

    return "#" .. tostring(index + 1) .. " " .. descriptor
end

local function describeIoScripts(recipe, ioType)
    if not recipe then
        return "[]"
    end

    local methodName = ioType == "input" and "getInputs" or "getOutputs"
    local okIo, ioList = safeCallMethod(recipe, methodName)
    if not okIo or not ioList then
        return "[]"
    end

    local count = getListSize(ioList)
    if count <= 0 then
        return "[]"
    end

    local parts = {}
    local cap = math.min(count, 5)
    for i = 0, cap - 1 do
        local script = getListValue(ioList, i)
        parts[#parts + 1] = describeIoScript(script, ioType, i)
    end

    if count > cap then
        parts[#parts + 1] = "+" .. tostring(count - cap) .. " more"
    end

    return "[" .. table.concat(parts, "; ") .. "]"
end

local function resolvePrimaryOutputItemFromLogic(logic)
    local okResolve, resolvedItem = pcall(function()
        if not logic then
            return nil
        end

        local okRecipe, recipe = safeCallMethod(logic, "getRecipe")
        if not okRecipe or not recipe then
            return nil
        end

        local okOutputs, outputs = safeCallMethod(recipe, "getOutputs")
        if not okOutputs or not outputs or getListSize(outputs) <= 0 then
            return nil
        end

        local firstOutputScript = getListValue(outputs, 0)
        if not firstOutputScript then
            return nil
        end

        local okType, resourceType = safeCallMethod(firstOutputScript, "getResourceType")
        if not okType or resourceType ~= ResourceType.Item then
            return nil
        end

        local okMapper, outputMapper = safeCallMethod(firstOutputScript, "getOutputMapper")
        if okMapper and outputMapper then
            local okGetOutputItem, outputMapperMethod = safeGetMethod(outputMapper, "getOutputItem")
            local okRecipeData, recipeData = safeCallMethod(logic, "getRecipeData")
            if okGetOutputItem and outputMapperMethod and okRecipeData and recipeData then
                local okMapped, mappedItem = pcall(outputMapperMethod, outputMapper, recipeData, true)
                if okMapped then
                    local fromMapped = tryResolveOutputCandidateItem(mappedItem)
                    if fromMapped then
                        return fromMapped
                    end
                end
            end
        end

        local okResults, resultItems = safeCallMethod(firstOutputScript, "getPossibleResultItems")
        if okResults and resultItems and getListSize(resultItems) > 0 then
            local count = getListSize(resultItems)
            local cap = math.min(count, 3)
            for i = 0, cap - 1 do
                local candidate = getListValue(resultItems, i)
                local fromResult = tryResolveOutputCandidateItem(candidate)
                if fromResult then
                    return fromResult
                end
            end
        end

        return nil
    end)

    if not okResolve then
        logDebug("titleHeader.output resolver failed safely")
        return nil
    end

    return resolvedItem
end

local function buildTitleHeaderOutputStatsLine(logic)
    local outputItem = resolvePrimaryOutputItemFromLogic(logic)
    if not outputItem then
        return nil
    end

    local lines = collectEquipmentStats(outputItem, { omitIdentityStats = true, forceFullStats = true })
    if #lines == 0 then
        return nil
    end

    local compactLines = {}
    compactLines[#compactLines + 1] = "Output Weapon Stats:"

    for i = 1, #lines do
        compactLines[#compactLines + 1] = tostring(lines[i])
    end

    return table.concat(compactLines, "\n")
end

local function emitCraftRecipeSelectionDebug(titleHeader)
    if not titleHeader or not titleHeader.logic then
        return
    end

    local okRecipe, recipe = safeCallMethod(titleHeader.logic, "getRecipe")
    if not okRecipe then
        return
    end

    local recipeName = getRecipeDisplayName(recipe)
    local inputsDesc = describeIoScripts(recipe, "input")
    local outputsDesc = describeIoScripts(recipe, "output")
    local signature = recipeName .. "|" .. inputsDesc .. "|" .. outputsDesc

    if titleHeader.qolLastRecipeDebugSignature == signature then
        return
    end

    titleHeader.qolLastRecipeDebugSignature = signature
    logDebug("craft selected recipe='" .. recipeName .. "' expectedInputs=" .. inputsDesc .. " expectedOutputs=" .. outputsDesc)
end

local function coerceToInventoryItem(candidate)
    if not candidate then
        return nil
    end

    local fullName = nil
    local okFullType, resolvedFullType = safeCallMethod(candidate, "getFullType")
    if okFullType and resolvedFullType and resolvedFullType ~= "" then
        fullName = resolvedFullType
    end

    local okFullName, resolvedFullName = safeCallMethod(candidate, "getFullName")
    if (not fullName or fullName == "") and okFullName and resolvedFullName and resolvedFullName ~= "" then
        fullName = resolvedFullName
    end

    if (not fullName or fullName == "") then
        local okModule, moduleName = safeCallMethod(candidate, "getModuleName")
        local okName, itemName = safeCallMethod(candidate, "getName")
        if okModule and okName and moduleName and itemName and moduleName ~= "" and itemName ~= "" then
            fullName = tostring(moduleName) .. "." .. tostring(itemName)
        end
    end

    return createInventoryItemByFullName(fullName)
end

local function isOutputBoxWidget(widget)
    if not widget or not widget.parent then
        return false
    end
    return widget.parent.Type == "ISWidgetIngredientsOutputs"
end

local function isItemOutputScript(script)
    if not script or not script.getResourceType then
        return false
    end
    local okType, resourceType = pcall(function()
        return script:getResourceType()
    end)
    return okType and resourceType == ResourceType.Item
end

local function getExistingMouseOverText(icon, fallback)
    if icon and type(icon.mouseovertext) == "string" and icon.mouseovertext ~= "" then
        return icon.mouseovertext
    end
    return fallback
end

local function appendStatsToTooltipText(baseText, statsText)
    if not statsText or statsText == "" then
        return baseText
    end

    local prefix = tostring(baseText or "")
    if prefix == "" then
        return statsText
    end

    if string.find(prefix, statsText, 1, true) then
        return prefix
    end

    return prefix .. " <BR> " .. statsText
end

local function applyTooltipAppendFromScriptTable(widget, scriptTable, item, sourceTag)
    if not item or not scriptTable or not scriptTable.icon then
        return false
    end

    local statsText = buildStatsDescription(item, { forceFullStats = true })
    if not statsText then
        logDebug(sourceTag .. " no equipment stats for current item")
        return false
    end

    local baseText = getExistingMouseOverText(scriptTable.icon, scriptTable.iconText)
    local mergedText = appendStatsToTooltipText(baseText, statsText)
    if mergedText and scriptTable.icon.setMouseOverText then
        scriptTable.icon:setMouseOverText(mergedText)
        logDebug(sourceTag .. " appended tooltip stats for " .. tostring(scriptTable.inputFullName or scriptTable.iconText or "unknown"))
        return true
    end

    logDebug(sourceTag .. " unable to append: icon missing setMouseOverText")
    return false
end

local function resolveOutputItemFromWidgetOutput(widget)
    if not widget or not widget.outputScript then
        return nil
    end

    if not isItemOutputScript(widget.outputScript) then
        return nil
    end

    if widget.logic and widget.logic.isManualSelectInputs and widget.logic:isManualSelectInputs() then
        local okMapper, outputMapper = pcall(function()
            return widget.outputScript:getOutputMapper()
        end)
        local okGetOutputItem, outputMapperMethod = false, nil
        if okMapper and outputMapper then
            okGetOutputItem, outputMapperMethod = safeGetMethod(outputMapper, "getOutputItem")
        end
        local okRecipeData, recipeData = safeCallMethod(widget.logic, "getRecipeData")
        if okMapper and outputMapper and okGetOutputItem and outputMapperMethod and okRecipeData and recipeData then
            local okItem, mappedItem = pcall(outputMapperMethod, outputMapper, recipeData, true)
            local invItem = coerceToInventoryItem(okItem and mappedItem or nil)
            if invItem then
                return invItem
            end
        end
    end

    local outputObjects = nil
    if widget.primary and widget.primary.outputObjects then
        outputObjects = widget.primary.outputObjects
    elseif widget.outputScript.getPossibleResultItems then
        local okOutputs, outputs = pcall(function()
            return widget.outputScript:getPossibleResultItems()
        end)
        if okOutputs then
            outputObjects = outputs
        end
    end

    if outputObjects and outputObjects.size and outputObjects:size() > 0 then
        local okCandidate, candidate = pcall(function()
            return outputObjects:get(0)
        end)
        if okCandidate then
            return coerceToInventoryItem(candidate)
        end
    end

    if widget.primary and widget.primary.inputFullName then
        return createInventoryItemByFullName(widget.primary.inputFullName)
    end

    return nil
end

local function resolveOutputItemFromWidgetInput(widget)
    if not widget or widget.displayAsOutput ~= true then
        return nil
    end

    if widget.primary and widget.primary.inputItem then
        local asInventory = coerceToInventoryItem(widget.primary.inputItem)
        if asInventory then
            return asInventory
        end
    end

    if widget.createScript and isItemOutputScript(widget.createScript) and widget.createScript.getPossibleResultItems then
        local okOutputs, outputs = pcall(function()
            return widget.createScript:getPossibleResultItems()
        end)
        if okOutputs and outputs and outputs.size and outputs:size() > 0 then
            local okCandidate, candidate = pcall(function()
                return outputs:get(0)
            end)
            if okCandidate then
                local asInventory = coerceToInventoryItem(candidate)
                if asInventory then
                    return asInventory
                end
            end
        end
    end

    if widget.primary and widget.primary.inputFullName then
        return createInventoryItemByFullName(widget.primary.inputFullName)
    end

    return nil
end

local function resolveOutputItemFromCraftLogicItemSlot(itemSlot)
    if not itemSlot then
        return nil
    end

    if itemSlot.storedItem then
        local fromStored = coerceToInventoryItem(itemSlot.storedItem)
        if fromStored then
            return fromStored
        end
    end

    if itemSlot.storedScriptItem then
        local fromScript = coerceToInventoryItem(itemSlot.storedScriptItem)
        if fromScript then
            return fromScript
        end

        local scriptItem = itemSlot.storedScriptItem
        local fullName = nil

        if type(scriptItem.getFullName) == "function" then
            local okFullName, resolvedFullName = pcall(scriptItem.getFullName, scriptItem)
            if okFullName and resolvedFullName and resolvedFullName ~= "" then
                fullName = resolvedFullName
            end
        end

        if (not fullName or fullName == "") and type(scriptItem.getModuleName) == "function" and type(scriptItem.getName) == "function" then
            local okModule, moduleName = pcall(scriptItem.getModuleName, scriptItem)
            local okName, itemName = pcall(scriptItem.getName, scriptItem)
            if okModule and okName and moduleName and itemName and moduleName ~= "" and itemName ~= "" then
                fullName = tostring(moduleName) .. "." .. tostring(itemName)
            end
        end

        local fromScriptName = createInventoryItemByFullName(fullName)
        if fromScriptName then
            return fromScriptName
        end
    end

    return nil
end

local function isCraftLogicOutputSlot(itemSlot)
    if not itemSlot then
        return false
    end

    local node = itemSlot
    local depth = 0
    while node and depth < 10 do
        if node.isOutput == true then
            return true
        end
        node = node.parent
        depth = depth + 1
    end

    return false
end

local function appendStatsToObjectTooltip(tooltipUI, item, sourceTag)
    if not tooltipUI or not item then
        return false
    end

    local lines = collectEquipmentStats(item, { forceFullStats = true })
    if #lines == 0 then
        logDebug(sourceTag .. " no equipment stats for current item")
        return false
    end

    local font = nil
    local okFont, resolvedFont = pcall(function()
        return tooltipUI:getFont()
    end)
    if okFont then
        font = resolvedFont
    end

    local lineSpacing = 14
    local okLineSpacing, resolvedLineSpacing = pcall(function()
        return tooltipUI:getLineSpacing()
    end)
    if okLineSpacing and tonumber(resolvedLineSpacing) then
        lineSpacing = tonumber(resolvedLineSpacing)
    end

    local tooltipHeight = 0
    local okHeight, resolvedHeight = pcall(function()
        return tooltipUI:getHeight()
    end)
    if okHeight and tonumber(resolvedHeight) then
        tooltipHeight = tonumber(resolvedHeight)
    end

    local padLeft = tonumber(tooltipUI.padLeft) or 0
    local padBottom = tonumber(tooltipUI.padBottom) or 0
    local y = math.max(0, tooltipHeight - padBottom)

    for _, line in ipairs(lines) do
        tooltipUI:DrawText(font, tostring(line), padLeft, y, 0.75, 0.95, 0.75, 1.0)
        tooltipUI:adjustWidth(padLeft, tostring(line))
        y = y + lineSpacing
    end

    tooltipUI:setHeight(y + padBottom)
    logDebug(sourceTag .. " appended ObjectTooltip stats")
    return true
end

local function patchCraftLogicPreviewTooltip()
    pcall(require, "Entity/ISUI/Components/Crafting/ISWidgetCraftLogicInputControl")
    if not ISWidgetCraftLogicInputControl or not ISWidgetCraftLogicInputControl.createDynamicChildren then
        return false
    end

    if originalCraftLogicInputControlCreateDynamicChildren then
        return true
    end

    originalCraftLogicInputControlCreateDynamicChildren = ISWidgetCraftLogicInputControl.createDynamicChildren

    ISWidgetCraftLogicInputControl.createDynamicChildren = function(self)
        originalCraftLogicInputControlCreateDynamicChildren(self)

        if not self or not self.outputItems then
            return
        end
        if self.outputItems.qolEquipmentStatsTooltipPatched then
            return
        end

        local originalDrawTooltip = self.outputItems.drawTooltip
        self.outputItems.drawTooltip = function(itemSlot, tooltipUI)
            if originalDrawTooltip then
                originalDrawTooltip(itemSlot, tooltipUI)
            end

            if not isCraftOutputTooltipEnabled() then
                return
            end

            local outputItem = resolveOutputItemFromCraftLogicItemSlot(itemSlot)
            appendStatsToObjectTooltip(tooltipUI, outputItem, "ISWidgetCraftLogicInputControl.outputItems.drawTooltip")
        end

        self.outputItems.qolEquipmentStatsTooltipPatched = true
        logDebug("craft logic preview tooltip patch active")
    end

    return true
end

local function patchCraftTooltipRenderFallback()
    if fallbackPatched then
        return true
    end

    pcall(require, "Entity/ISUI/Components/Crafting/ISToolTipItemSlot")
    if not ISToolTipItemSlot or not ISToolTipItemSlot.render then
        return false
    end

    originalToolTipItemSlotRender = ISToolTipItemSlot.render

    ISToolTipItemSlot.render = function(self)
        if not isCraftOutputTooltipEnabled() then
            return originalToolTipItemSlotRender(self)
        end

        local itemSlot = self and self.itemSlot or nil
        if not isCraftLogicOutputSlot(itemSlot) then
            return originalToolTipItemSlotRender(self)
        end

        local originalDrawTooltip = itemSlot and itemSlot.drawTooltip or nil
        if not originalDrawTooltip then
            return originalToolTipItemSlotRender(self)
        end

        itemSlot.drawTooltip = function(slot, tooltipUI)
            originalDrawTooltip(slot, tooltipUI)
            local outputItem = resolveOutputItemFromCraftLogicItemSlot(slot)
            appendStatsToObjectTooltip(tooltipUI, outputItem, "ISToolTipItemSlot.render")
        end

        local ok, err = pcall(function()
            originalToolTipItemSlotRender(self)
        end)

        itemSlot.drawTooltip = originalDrawTooltip

        if not ok then
            logDebug("fallback render hook error: " .. tostring(err))
            return
        end
    end

    fallbackPatched = true
    if loggerRef and loggerRef.info then
        loggerRef.info("UIFixes.EquipmentStatsDisplay fallback tooltip render patch active")
    end
    return true
end

local function patchInventoryTooltipRenderFallback()
    if inventoryTooltipPatched then
        return true
    end

    pcall(require, "ISUI/ISToolTipInv")
    if not ISToolTipInv or not ISToolTipInv.render then
        return false
    end

    originalToolTipInvRender = ISToolTipInv.render

    ISToolTipInv.render = function(self)
        if not isExactStatsEnabled() and not isCraftOutputTooltipEnabled() then
            return originalToolTipInvRender(self)
        end

        if not self or not self.item or not self.tooltip then
            return originalToolTipInvRender(self)
        end

        local lines = collectEquipmentStats(self.item)
        if #lines == 0 then
            return originalToolTipInvRender(self)
        end

        local font = UIFont[getCore():getOptionTooltipFont()]
        local lineSpacing = self.tooltip:getLineSpacing()
        local baseHeight = self.tooltip:getHeight()
        local newHeight = baseHeight + (#lines * lineSpacing)

        local originalSetHeight = ISToolTipInv.setHeight
        local originalDrawRectBorder = ISToolTipInv.drawRectBorder

        self.setHeight = function(instance, _, ...)
            instance.keepOnScreen = false
            return originalSetHeight(instance, newHeight, ...)
        end

        self.drawRectBorder = function(instance, ...)
            local y = baseHeight
            local padLeft = 5
            for _, line in ipairs(lines) do
                instance.tooltip:DrawText(font, tostring(line), padLeft, y, 0.75, 0.95, 0.75, 1.0)
                y = y + lineSpacing
            end
            return originalDrawRectBorder(instance, ...)
        end

        local ok, err = pcall(function()
            originalToolTipInvRender(self)
        end)

        self.setHeight = originalSetHeight
        self.drawRectBorder = originalDrawRectBorder

        if not ok then
            logDebug("ISToolTipInv fallback render hook error: " .. tostring(err))
            return originalToolTipInvRender(self)
        end
    end

    inventoryTooltipPatched = true
    if loggerRef and loggerRef.info then
        loggerRef.info("UIFixes.EquipmentStatsDisplay inventory tooltip render patch active")
    end
    return true
end

local function patchCraftTitleHeaderInfo()
    pcall(require, "Entity/ISUI/Controls/ISWidgetTitleHeader")
    if not ISWidgetTitleHeader or not ISWidgetTitleHeader.updateLabels then
        return false
    end

    if originalWidgetTitleHeaderUpdateLabels then
        return true
    end

    originalWidgetTitleHeaderUpdateLabels = ISWidgetTitleHeader.updateLabels

    ISWidgetTitleHeader.updateLabels = function(self)
        originalWidgetTitleHeaderUpdateLabels(self)

        if not isCraftOutputTooltipEnabled() then
            return
        end

        emitCraftRecipeSelectionDebug(self)

        if not self.titleLabel then
            return
        end

        local baseTitle = self.titleLabel.origTitleStr or self.titleLabel.name or self.title or ""
        local recipeSignature = getLogicRecipeSignature(self.logic)

        if self.qolLastTitleStatsRecipeSignature ~= recipeSignature then
            self.qolLastTitleStatsRecipeSignature = recipeSignature
            self.qolLastTitleStatsLine = buildTitleHeaderOutputStatsLine(self.logic)

            if self.qolLastTitleStatsLine and self.qolLastTitleStatsLine ~= "" then
                logDebug("titleHeader.output stats resolved for recipe='" .. recipeSignature .. "'")
            else
                logDebug("titleHeader.output stats unavailable for recipe='" .. recipeSignature .. "'")
            end
        end

        local statsLine = self.qolLastTitleStatsLine
        if statsLine and statsLine ~= "" then
            self.titleLabel:setName(tostring(baseTitle) .. "\n" .. tostring(statsLine))
        else
            self.titleLabel:setName(tostring(baseTitle))
        end
        self.titleLabel:setHeightToName(0)
    end

    logDebug("craft title header patch active")
    return true
end

local function patchInventoryPane()
    if inventoryPatched then
        return true
    end

    local okRequire = pcall(require, "ISUI/ISInventoryPane")
    if not okRequire then
        return false
    end

    if not ISInventoryPane or not ISInventoryPane.drawItemDetails then
        return false
    end

    originalDrawItemDetails = ISInventoryPane.drawItemDetails

    ISInventoryPane.drawItemDetails = function(self, item, y, xoff, yoff, red)
        if isExactStatsEnabled()
            and item
            and instanceof
            and instanceof(item, "HandWeapon")
        then
            local okCurrent, currentValue = pcall(function()
                return item:getCondition()
            end)
            local okMax, maxValue = pcall(function()
                return item:getConditionMax()
            end)

            if okCurrent and okMax and maxValue and maxValue > 0 then
                local headerHeight = self.headerHgt or 0
                local top = headerHeight + y * self.itemHgt + yoff
                local fgText = { r = 0.6, g = 0.8, b = 0.5, a = 0.6 }
                if red then
                    fgText = { r = 0.0, g = 0.0, b = 0.5, a = 0.7 }
                end

                local label = (getTextOrNull("IGUI_invpanel_Condition") or "Condition") .. ": " .. formatCurrentMax(currentValue, maxValue)
                self:drawText(label, 40 + 30 + xoff, top + (self.itemHgt - self.fontHgt) / 2, fgText.a, fgText.r, fgText.g, fgText.b, self.font)
                return
            end
        end

        return originalDrawItemDetails(self, item, y, xoff, yoff, red)
    end

    inventoryPatched = true
    logDebug("inventory draw patch active")
    return true
end

local function patchCraftWidgets()
    if craftPatched then
        return true
    end

    pcall(require, "Entity/ISUI/CraftRecipe/ISWidgetIngredientsOutputs")
    pcall(require, "Entity/ISUI/CraftRecipe/ISWidgetOutput")
    pcall(require, "Entity/ISUI/CraftRecipe/ISWidgetInput")

    if not ISWidgetOutput or not ISWidgetInput then
        return false
    end

    originalWidgetOutputUpdateScriptValues = ISWidgetOutput.updateScriptValues
    originalWidgetInputUpdateScriptValues = ISWidgetInput.updateScriptValues
    originalWidgetOutputUpdateValues = ISWidgetOutput.updateValues
    originalWidgetInputUpdateValues = ISWidgetInput.updateValues

    ISWidgetOutput.updateScriptValues = function(self, scriptTable)
        originalWidgetOutputUpdateScriptValues(self, scriptTable)

        if not isCraftOutputTooltipEnabled() then
            return
        end
        if scriptTable ~= self.primary then
            return
        end
        if not isOutputBoxWidget(self) then
            return
        end

        local item = resolveOutputItemFromWidgetOutput(self)
        applyTooltipAppendFromScriptTable(self, scriptTable, item, "ISWidgetOutput.updateScriptValues")
    end

    ISWidgetInput.updateScriptValues = function(self, scriptTable)
        originalWidgetInputUpdateScriptValues(self, scriptTable)

        if not isCraftOutputTooltipEnabled() then
            return
        end
        if self.displayAsOutput ~= true then
            return
        end
        if scriptTable ~= self.primary then
            return
        end
        if not isOutputBoxWidget(self) then
            return
        end

        local item = resolveOutputItemFromWidgetInput(self)
        applyTooltipAppendFromScriptTable(self, scriptTable, item, "ISWidgetInput.updateScriptValues")
    end

    ISWidgetOutput.updateValues = function(self)
        originalWidgetOutputUpdateValues(self)

        if not isCraftOutputTooltipEnabled() then
            return
        end
        if not isOutputBoxWidget(self) then
            return
        end
        if not self.primary then
            return
        end

        local item = resolveOutputItemFromWidgetOutput(self)
        applyTooltipAppendFromScriptTable(self, self.primary, item, "ISWidgetOutput.updateValues")
    end

    ISWidgetInput.updateValues = function(self)
        originalWidgetInputUpdateValues(self)

        if not isCraftOutputTooltipEnabled() then
            return
        end
        if self.displayAsOutput ~= true then
            return
        end
        if not isOutputBoxWidget(self) then
            return
        end
        if not self.primary then
            return
        end

        local item = resolveOutputItemFromWidgetInput(self)
        applyTooltipAppendFromScriptTable(self, self.primary, item, "ISWidgetInput.updateValues")
    end

    craftPatched = true
    logDebug("craft output tooltip append patch active")
    return true
end

local function tryPatchAll()
    local inventoryOk = patchInventoryPane()
    local craftOk = patchCraftWidgets()
    local craftLogicOk = patchCraftLogicPreviewTooltip()
    local fallbackOk = patchCraftTooltipRenderFallback()
    local invTooltipOk = patchInventoryTooltipRenderFallback()
    local titleHeaderOk = patchCraftTitleHeaderInfo()
    return inventoryOk and craftOk and craftLogicOk and fallbackOk and invTooltipOk and titleHeaderOk
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
            loggerRef.info("UIFixes.EquipmentStatsDisplay delayed patching completed")
        end
    end
end

function EquipmentStatsDisplay.init(settings, logger)
    settingsRef = settings
    loggerRef = logger

    print("[QoLforSacriel][INFO] EquipmentStatsDisplay init reached")

    if installed then
        if logger and logger.debug then
            logger.debug("UIFixes.EquipmentStatsDisplay already installed")
        end
        return
    end

    local allPatched = tryPatchAll()
    print("[QoLforSacriel][INFO] EquipmentStatsDisplay patch result=" .. tostring(allPatched))

    if (not allPatched) and Events and Events.OnTick and (not retryHookInstalled) then
        Events.OnTick.Add(onRetryTick)
        retryHookInstalled = true
        if logger and logger.info then
            logger.info("UIFixes.EquipmentStatsDisplay waiting for UI class load; retry hook installed")
        end
    end

    installed = true
    if logger and logger.info then
        logger.info("UIFixes.EquipmentStatsDisplay installed")
    end
end

return EquipmentStatsDisplay
