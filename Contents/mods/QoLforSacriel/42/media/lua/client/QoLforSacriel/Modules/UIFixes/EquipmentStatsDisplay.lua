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
local originalCraftLogicInputControlCalculateLayout = nil
local originalToolTipItemSlotRender = nil
local originalToolTipInvRender = nil
local originalWidgetTitleHeaderUpdateLabels = nil
local originalWidgetTitleHeaderRender = nil
local originalWidgetTitleHeaderCalculateLayout = nil
local originalWidgetCraftLogicTitleCreateChildren = nil

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
    if not settingsRef.isEnabled
        or settingsRef.isEnabled("QoLforSacriel_EnableUIFixes") ~= true
        or (
            settingsRef.get("QoLforSacriel_UIFixes_EnableExactEquipmentStats") ~= true
            and settingsRef.get("QoLforSacriel_UIFixes_EnableCraftOutputItemTooltip") ~= true
            and settingsRef.get("QoLforSacriel_UIFixes_EnableCraftRecipeXp") ~= true
            and settingsRef.get("QoLforSacriel_UIFixes_ShowAllEquipmentTooltipStats") ~= true
        )
    then
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

local function isCraftRecipeXpEnabled()
    if not isUiFixesEnabled() then
        return false
    end
    return settingsRef.get("QoLforSacriel_UIFixes_EnableCraftRecipeXp") == true
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

local function isFirearmItem(item)
    if not item or not isStrictWeaponItem(item) then
        return false
    end

    local okRanged, ranged = safeCallItemMethod(item, "isRanged")
    if okRanged and ranged == true then
        return true
    end

    local okMaxAmmo, maxAmmo = safeCallItemMethod(item, "getMaxAmmo")
    if okMaxAmmo and tonumber(maxAmmo) and tonumber(maxAmmo) > 0 then
        return true
    end

    return false
end

local function getMethodNumberOrNil(item, methodName)
    local ok, value = safeCallItemMethod(item, methodName)
    if not ok then
        return nil
    end

    return tonumber(value)
end

local function isExplosiveItem(item)
    if not item then
        return false
    end

    local category = normalizeDisplayCategory(getItemDisplayCategory(item))
    if category == "explosive" or category == "explosives" then
        return true
    end

    local okIsExplosive, explosiveFlag = safeCallItemMethod(item, "isExplosive")
    if okIsExplosive and explosiveFlag == true then
        return true
    end

    local explosiveSignals = {
        "getExplosionPower",
        "getExplosionRange",
        "getExplosionTimer",
        "getTriggerExplosionTimer",
        "getSensorRange",
        "getFireRange",
        "getSmokeRange",
    }

    for i = 1, #explosiveSignals do
        local n = getMethodNumberOrNil(item, explosiveSignals[i])
        if n and n > 0 then
            return true
        end
    end

    return false
end

local function buildExplosiveEffectLabel(item)
    local effects = {}

    local explosionRange = getMethodNumberOrNil(item, "getExplosionRange")
    if explosionRange and explosionRange > 0 then
        effects[#effects + 1] = "Explosion"
    end

    local fireRange = getMethodNumberOrNil(item, "getFireRange")
    if fireRange and fireRange > 0 then
        effects[#effects + 1] = "Fire"
    end

    local smokeRange = getMethodNumberOrNil(item, "getSmokeRange")
    if smokeRange and smokeRange > 0 then
        effects[#effects + 1] = "Smoke"
    end

    if #effects == 0 then
        return nil
    end

    return table.concat(effects, ", ")
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

    local isWeapon = isStrictWeaponItem(item)
    local isExplosive = isExplosiveItem(item)

    if not isWeapon and not isExplosive then
        return {}
    end

    local omitIdentityStats = options and options.omitIdentityStats == true
    local forceFullStats = options and options.forceFullStats == true
    local context = options and options.context or nil

    local lines = {}

    if not omitIdentityStats and isWeapon then
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

    if isExplosive and damageText == "N/A" then
        local explosionPower = getMethodNumberOrNil(item, "getExplosionPower")
        if explosionPower and explosionPower > 0 then
            damageText = toStatStringOrNA(explosionPower)
        else
            local extraDamage = getMethodNumberOrNil(item, "getExtraDamage")
            if extraDamage and extraDamage > 0 then
                damageText = toStatStringOrNA(extraDamage, 2)
            end
        end
    end

    if not isExplosive then
        table.insert(lines, "Damage: " .. damageText)
    end

    if not forceFullStats and not isShowAllEquipmentStatsEnabled() then
        return lines
    end

    if isFirearmItem(item) then
        lines = {}
        table.insert(lines, "Damage: " .. damageText)
        table.insert(lines, "Ammo: " .. getMethodValueOrNA(item, "getCurrentAmmoCount"))
        table.insert(lines, "Magazine Capacity: " .. getMethodValueOrNA(item, "getMaxAmmo"))
        table.insert(lines, "Minimum Range: " .. getMethodValueOrNA(item, "getMinRange", 2))
        table.insert(lines, "Maximum Range: " .. getMethodValueOrNA(item, "getMaxRange", 2))
        table.insert(lines, "Accuracy: " .. getMethodValueOrNA(item, "getHitChance"))
        table.insert(lines, "Accuracy bonus (Aiming): " .. getMethodValueOrNA(item, "getAimingPerkHitChanceModifier", 2))
        table.insert(lines, "Crit Hit Chance: " .. getMethodValueOrNA(item, "getCriticalChance", 2))
        table.insert(lines, "Crit Hit bonus (Aiming): " .. getMethodValueOrNA(item, "getAimingPerkCritModifier"))
        table.insert(lines, "Noise Radius: " .. getMethodValueOrNA(item, "getSoundRadius"))

        local firearmKnockbackValue = getMethodValueOrNA(item, "getPushBackMod", 2)
        if firearmKnockbackValue == "N/A" then
            firearmKnockbackValue = getMethodValueOrNA(item, "getKnockdownMod", 2)
        end
        table.insert(lines, "Knockback: " .. firearmKnockbackValue)

        return lines
    end

    if isExplosive then
        table.insert(lines, "Maximum Range: " .. getMethodValueOrNA(item, "getMaxRange", 2))
        table.insert(lines, "Noise Radius: " .. getMethodValueOrNA(item, "getSoundRadius"))

        local effectLabel = buildExplosiveEffectLabel(item)
        if effectLabel then
            table.insert(lines, "Effect: " .. effectLabel)
        end

        local effectPower = getMethodNumberOrNil(item, "getExplosionPower")
        if (not effectPower or effectPower <= 0) then
            effectPower = getMethodNumberOrNil(item, "getExtraDamage")
        end
        if effectPower and effectPower > 0 then
            table.insert(lines, "Effect Power: " .. toStatStringOrNA(effectPower, 2))
        end

        local effectRange = getMethodNumberOrNil(item, "getExplosionRange")
        if (not effectRange or effectRange <= 0) then
            local fireRange = getMethodNumberOrNil(item, "getFireRange")
            local smokeRange = getMethodNumberOrNil(item, "getSmokeRange")
            effectRange = math.max(fireRange or 0, smokeRange or 0)
        end
        if effectRange and effectRange > 0 then
            table.insert(lines, "Effect Range: " .. toStatStringOrNA(effectRange, 2))
        end

        local timerValue = getMethodNumberOrNil(item, "getExplosionTimer")
        if (not timerValue or timerValue <= 0) then
            timerValue = getMethodNumberOrNil(item, "getTriggerExplosionTimer")
        end
        if timerValue and timerValue > 0 then
            table.insert(lines, "Timer: " .. toStatStringOrNA(timerValue))
        end

        local sensorRange = getMethodNumberOrNil(item, "getSensorRange")
        if sensorRange and sensorRange > 0 then
            table.insert(lines, "Sensor Range: " .. toStatStringOrNA(sensorRange, 2))
        end

        return lines
    end

    table.insert(lines, "Door Damage: " .. getMethodValueOrNA(item, "getDoorDamage"))
    table.insert(lines, "Tree Damage: " .. getMethodValueOrNA(item, "getTreeDamage"))
    table.insert(lines, "Minimum Range: " .. getMethodValueOrNA(item, "getMinRange", 2))
    table.insert(lines, "Maximum Range: " .. getMethodValueOrNA(item, "getMaxRange", 2))
    table.insert(lines, "Attack Speed: " .. getMethodValueOrNA(item, "getBaseSpeed", 2))
    table.insert(lines, "Crit Hit Chance: " .. getMethodValueOrNA(item, "getCriticalChance", 2))
    table.insert(lines, "Crit Hit Multiplier: " .. getMethodValueOrNA(item, "getCriticalDamageMultiplier", 2))

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

    local lines = collectEquipmentStats(outputItem, { omitIdentityStats = true, forceFullStats = true, context = "crafting" })
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

local function getSandboxXpMultiplier(perk)
    if not SandboxOptions or not SandboxOptions.instance or not perk or not perk.getType then
        return 1
    end

    local okMultiplier, multiplier = pcall(function()
        local config = SandboxOptions.instance.multipliersConfig
        if config and config.xpMultiplierGlobalToggle and config.xpMultiplierGlobalToggle:getValue() then
            return config.xpMultiplierGlobal:getValue()
        end

        local optionName = "MultiplierConfig." .. tostring(perk:getType())
        local option = SandboxOptions.instance:getOptionByName(optionName)
        return option:asConfigOption():getValueAsString()
    end)

    return okMultiplier and tonumber(multiplier) or 1
end

local function getCraftRecipeXpMultiplier(playerObj, perk)
    if not playerObj or not perk or not perk.getType then
        return 1
    end

    local perkType = perk:getType()
    local isSprinting = PerkFactory and PerkFactory.Perks and perkType == PerkFactory.Perks.Sprinting
    local isFitness = PerkFactory and PerkFactory.Perks and perkType == PerkFactory.Perks.Fitness
    local isStrength = PerkFactory and PerkFactory.Perks and perkType == PerkFactory.Perks.Strength
    local excludesSpeedReduction = isSprinting or isFitness or isStrength
    local excludesSpeedIncrease = isFitness or isStrength
    local multiplier = excludesSpeedReduction and 1 or 0.25
    local playerXp = playerObj.getXp and playerObj:getXp() or nil
    if playerXp and playerXp.getPerkBoost then
        local okBoost, boost = pcall(function()
            return playerXp:getPerkBoost(perkType)
        end)
        if okBoost and tonumber(boost) then
            if tonumber(boost) == 1 and isSprinting then
                multiplier = 1.25
            elseif tonumber(boost) == 1 then
                multiplier = 1
            elseif tonumber(boost) == 2 and not excludesSpeedIncrease then
                multiplier = 1.33
            elseif tonumber(boost) >= 3 and not excludesSpeedIncrease then
                multiplier = 1.66
            end
        end
    end

    if CharacterTrait and playerObj.hasTrait then
        if CharacterTrait.FAST_LEARNER and not excludesSpeedIncrease and playerObj:hasTrait(CharacterTrait.FAST_LEARNER) then
            multiplier = multiplier * 1.3
        end
        if CharacterTrait.SLOW_LEARNER and not excludesSpeedReduction and playerObj:hasTrait(CharacterTrait.SLOW_LEARNER) then
            multiplier = multiplier * 0.7
        end
        if CharacterTrait.PACIFIST
            and playerObj:hasTrait(CharacterTrait.PACIFIST)
            and PerkFactory
            and PerkFactory.Perks
            and (
                perkType == PerkFactory.Perks.SmallBlade
                or perkType == PerkFactory.Perks.LongBlade
                or perkType == PerkFactory.Perks.SmallBlunt
                or perkType == PerkFactory.Perks.Spear
                or perkType == PerkFactory.Perks.Blunt
                or perkType == PerkFactory.Perks.Axe
                or perkType == PerkFactory.Perks.Aiming
            )
        then
            multiplier = multiplier * 0.75
        end
        if CharacterTrait.CRAFTY
            and playerObj:hasTrait(CharacterTrait.CRAFTY)
            and PerkFactory
            and PerkFactory.Perks
            and perk.getParent
            and perk:getParent() == PerkFactory.Perks.Crafting
        then
            multiplier = multiplier * 1.3
        end
    end

    if playerXp and playerXp.getMultiplier then
        local okTemporary, temporaryMultiplier = pcall(function()
            return playerXp:getMultiplier(perkType)
        end)
        if okTemporary and tonumber(temporaryMultiplier) and tonumber(temporaryMultiplier) > 1 then
            multiplier = multiplier * tonumber(temporaryMultiplier)
        end
    end

    return multiplier * getSandboxXpMultiplier(perk)
end

local function getCraftRecipeAwardAmount(playerObj, perk, baseAmount)
    local awardedAmount = baseAmount
    local perkType = perk and perk.getType and perk:getType() or nil
    local nutrition = playerObj and playerObj.getNutrition and playerObj:getNutrition() or nil
    if PerkFactory and PerkFactory.Perks and perkType == PerkFactory.Perks.Fitness and nutrition and nutrition.canAddFitnessXp then
        local okFitness, canAddFitnessXp = pcall(function()
            return nutrition:canAddFitnessXp()
        end)
        if okFitness and not canAddFitnessXp then
            return 0
        end
    end
    if PerkFactory and PerkFactory.Perks and perkType == PerkFactory.Perks.Strength and nutrition and nutrition.getProteins then
        local okProtein, proteins = pcall(function()
            return nutrition:getProteins()
        end)
        if okProtein and tonumber(proteins) then
            if tonumber(proteins) > 50 and tonumber(proteins) < 300 then
                awardedAmount = awardedAmount * 1.5
            elseif tonumber(proteins) < -300 then
                awardedAmount = awardedAmount * 0.7
            end
        end
    end

    awardedAmount = awardedAmount * getCraftRecipeXpMultiplier(playerObj, perk)
    local playerXp = playerObj and playerObj.getXp and playerObj:getXp() or nil
    if not playerXp or not playerXp.getXP or not perk.getTotalXpForLevel then
        return awardedAmount
    end

    local okCap, cappedAmount = pcall(function()
        local currentXp = playerXp:getXP(perk:getType())
        local maxXp = perk:getTotalXpForLevel(10)
        return math.max(0, math.min(awardedAmount, maxXp - currentXp))
    end)

    return okCap and cappedAmount or awardedAmount
end

local function formatCraftRecipeXpAmount(amount)
    local rounded = math.floor((amount * 10) + 0.5) / 10
    return string.format("%.1f", rounded)
end

local function buildCraftRecipeXpLine(recipe, playerObj)
    if not recipe or not playerObj then
        return nil
    end

    local okCount, awardCount = pcall(function()
        return recipe:getXPAwardCount()
    end)
    if not okCount or not tonumber(awardCount) or tonumber(awardCount) <= 0 then
        return nil
    end

    local lines = { getTextOrNull("UI_QoLforSacriel_CraftRecipe_XpGained") or "XP Gained" }
    for index = 0, tonumber(awardCount) - 1 do
        local okAward, award = pcall(function()
            return recipe:getXPAward(index)
        end)
        if okAward and award then
            local okPerk, perk = pcall(function()
                return award:getPerk()
            end)
            local okAmount, amount = pcall(function()
                return award:getAmount()
            end)
            if okPerk and perk and okAmount and tonumber(amount) then
                local perkName = perk:getName()
                if perkName and perkName ~= "" then
                    local awardedAmount = getCraftRecipeAwardAmount(playerObj, perk, tonumber(amount))
                    lines[#lines + 1] = tostring(perkName) .. ": " .. formatCraftRecipeXpAmount(awardedAmount) .. " XP"
                end
            end
        end
    end

    return #lines > 1 and table.concat(lines, "\n") or nil
end

local function logCraftRecipeXpState(widget, recipe, xpLine)
    if not widget then
        return
    end

    local recipeName = getRecipeDisplayName(recipe)
    local debugSignature = tostring(recipeName) .. "|" .. tostring(xpLine or "")
    if widget.qolCraftRecipeXpDebugSignature == debugSignature then
        return
    end
    widget.qolCraftRecipeXpDebugSignature = debugSignature

    if not isCraftRecipeXpEnabled() then
        logDebug("craft XP skipped: recipe='" .. tostring(recipeName) .. "', option disabled")
        return
    end

    if not recipe then
        logDebug("craft XP unavailable: selected recipe was nil")
        return
    end

    local okCount, awardCount = pcall(function()
        return recipe:getXPAwardCount()
    end)
    if not okCount or not tonumber(awardCount) then
        logDebug("craft XP unavailable: getXPAwardCount failed for recipe='" .. tostring(recipeName) .. "'")
        return
    end

    logDebug(
        "craft XP read: recipe='" .. tostring(recipeName)
        .. "', awards=" .. tostring(awardCount)
        .. ", outputBox=" .. tostring(widget.outputItems ~= nil)
        .. ", displayLine=" .. tostring(xpLine ~= nil and xpLine ~= "")
    )

    for index = 0, tonumber(awardCount) - 1 do
        local okAward, award = pcall(function()
            return recipe:getXPAward(index)
        end)
        if not okAward or not award then
            logDebug("craft XP award invalid: recipe='" .. tostring(recipeName) .. "', index=" .. tostring(index))
        else
            local okPerk, perk = pcall(function()
                return award:getPerk()
            end)
            local okAmount, amount = pcall(function()
                return award:getAmount()
            end)
            local perkName = okPerk and perk and perk:getName() or "?"
            logDebug(
                "craft XP award: recipe='" .. tostring(recipeName)
                .. "', index=" .. tostring(index)
                .. ", perk='" .. tostring(perkName)
                .. "', amount=" .. tostring(okAmount and amount or "?")
            )
        end
    end
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

    local statsText = buildStatsDescription(item, { forceFullStats = true, context = "crafting" })
    if not statsText then
        return false
    end

    local baseText = getExistingMouseOverText(scriptTable.icon, scriptTable.iconText)
    local mergedText = appendStatsToTooltipText(baseText, statsText)
    if mergedText and scriptTable.icon.setMouseOverText then
        scriptTable.icon:setMouseOverText(mergedText)
        return true
    end

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

    local lines = collectEquipmentStats(item, { forceFullStats = true, context = "crafting" })
    if #lines == 0 then
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

        local xpLine = nil
        if isCraftRecipeXpEnabled() then
            xpLine = buildCraftRecipeXpLine(self.recipe)
        end

        logCraftRecipeXpState(self, self.recipe, xpLine)

        if xpLine and xpLine ~= "" and self.outputItems then
            self.qolCraftRecipeXpLabel = ISXuiSkin.build(
                self.xuiSkin,
                "S_NeedsAStyle",
                ISLabel,
                0,
                0,
                -1,
                xpLine,
                1,
                1,
                1,
                1,
                UIFont.Small,
                true
            )
            self.qolCraftRecipeXpLabel:initialise()
            self.qolCraftRecipeXpLabel:instantiate()
            self.qolCraftRecipeXpLabel:setHeightToName(0)
            self:addChild(self.qolCraftRecipeXpLabel)
            logDebug("craft XP output label added: recipe='" .. tostring(getRecipeDisplayName(self.recipe)) .. "'")
        elseif isCraftRecipeXpEnabled() and xpLine and xpLine ~= "" then
            logDebug("craft XP output label skipped: output box missing for recipe='" .. tostring(getRecipeDisplayName(self.recipe)) .. "'")
        end

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

    originalCraftLogicInputControlCalculateLayout = ISWidgetCraftLogicInputControl.calculateLayout

    ISWidgetCraftLogicInputControl.calculateLayout = function(self, preferredWidth, preferredHeight)
        local xpLabel = self.qolCraftRecipeXpLabel
        if not xpLabel or not self.outputItems then
            return originalCraftLogicInputControlCalculateLayout(self, preferredWidth, preferredHeight)
        end

        xpLabel:setWidthToName(0)
        xpLabel:setHeightToName(0)

        local labelHeight = xpLabel:getHeight()
        local labelSpacing = self.elementSpacing or 0
        local footerHeight = labelHeight + labelSpacing
        local availableHeight = math.max(0, (preferredHeight or 0) - footerHeight)

        originalCraftLogicInputControlCalculateLayout(self, preferredWidth, availableHeight)

        xpLabel:setX(self.outputItems:getX() + (self.outputItems:getWidth() - xpLabel:getWidth()) / 2)
        xpLabel:setY(self.outputItems:getY() + self.outputItems:getHeight() + labelSpacing)
        self:setHeight(self:getHeight() + footerHeight)

        if not self.qolCraftRecipeXpLayoutLogged then
            self.qolCraftRecipeXpLayoutLogged = true
            logDebug(
                "craft XP output label layout: x=" .. tostring(xpLabel:getX())
                .. ", y=" .. tostring(xpLabel:getY())
                .. ", width=" .. tostring(xpLabel:getWidth())
                .. ", height=" .. tostring(xpLabel:getHeight())
            )
        end
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

        if self.owner and self.owner.Type == "ISEquippedItem" then
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
        if type(originalSetHeight) ~= "function" or type(originalDrawRectBorder) ~= "function" then
            return originalToolTipInvRender(self)
        end

        self.setHeight = function(instance, _, ...)
            instance.keepOnScreen = false
            return originalSetHeight(instance, newHeight, ...)
        end

        self.drawRectBorder = function(instance, ...)
            if not instance or not instance.tooltip or type(instance.tooltip.DrawText) ~= "function" then
                return originalDrawRectBorder(instance, ...)
            end

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

    local function measureTitleHeaderPanel(text, font)
        if not text or text == "" or not getTextManager then
            return nil
        end

        local textManager = getTextManager()
        if not textManager or not textManager.MeasureStringX or not textManager.MeasureStringY then
            return nil
        end

        local width = 0
        for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
            width = math.max(width, textManager:MeasureStringX(font, line))
        end

        return {
            text = text,
            width = width,
            height = textManager:MeasureStringY(font, text),
        }
    end

    ISWidgetTitleHeader.updateLabels = function(self)
        originalWidgetTitleHeaderUpdateLabels(self)

        emitCraftRecipeSelectionDebug(self)

        if not self.titleLabel then
            return
        end

        local baseTitle = self.titleLabel.origTitleStr or self.titleLabel.name or self.title or ""
        local recipeSignature = getLogicRecipeSignature(self.logic)
        local okRecipe, recipe = safeCallMethod(self.logic, "getRecipe")
        local okPlayer, playerObj = safeCallMethod(self.logic, "getPlayer")
        local xpLine = nil
        if okRecipe and okPlayer and isCraftRecipeXpEnabled() then
            xpLine = buildCraftRecipeXpLine(recipe, playerObj)
        end
        logCraftRecipeXpState(self, okRecipe and recipe or nil, xpLine)

        if isCraftOutputTooltipEnabled() and self.qolLastTitleStatsRecipeSignature ~= recipeSignature then
            self.qolLastTitleStatsRecipeSignature = recipeSignature
            self.qolLastTitleStatsLine = buildTitleHeaderOutputStatsLine(self.logic)

            if self.qolLastTitleStatsLine and self.qolLastTitleStatsLine ~= "" then
                logDebug("titleHeader.output stats resolved for recipe='" .. recipeSignature .. "'")
            else
                logDebug("titleHeader.output stats unavailable for recipe='" .. recipeSignature .. "'")
            end
        end

        local statsLine = self.qolLastTitleStatsLine
        local statsText = isCraftOutputTooltipEnabled() and statsLine or nil
        local xpText = xpLine and xpLine ~= "" and xpLine or nil
        if xpText then
            if self.qolLastXpTitleHeaderSignature ~= recipeSignature then
                self.qolLastXpTitleHeaderSignature = recipeSignature
                logDebug("craft XP title header added: recipe='" .. tostring(getRecipeDisplayName(recipe)) .. "'")
            end
        end

        self.titleLabel:setName(tostring(baseTitle))
        self.titleLabel:setHeightToName(0)
        local font = self.titleLabel.font or UIFont.Small
        self.qolTitleHeaderStatsPanel = measureTitleHeaderPanel(statsText, font)
        self.qolTitleHeaderXpPanel = measureTitleHeaderPanel(xpText, font)
        self.qolTitleHeaderHasPanels = self.qolTitleHeaderStatsPanel ~= nil or self.qolTitleHeaderXpPanel ~= nil
        if self.qolTitleHeaderHasPanels then
            local panelHeight = 0
            if self.qolTitleHeaderStatsPanel then
                panelHeight = math.max(panelHeight, self.qolTitleHeaderStatsPanel.height)
            end
            if self.qolTitleHeaderXpPanel then
                panelHeight = math.max(panelHeight, self.qolTitleHeaderXpPanel.height)
            end
            self.qolTitleHeaderPanelReservedHeight = panelHeight + 11
        else
            self.qolTitleHeaderPanelReservedHeight = 0
        end
    end

    originalWidgetTitleHeaderCalculateLayout = ISWidgetTitleHeader.calculateLayout

    ISWidgetTitleHeader.calculateLayout = function(self, preferredWidth, preferredHeight)
        originalWidgetTitleHeaderCalculateLayout(self, preferredWidth, preferredHeight)

        if not self.qolTitleHeaderHasPanels or not self.titleLabel then
            return
        end

        local statsPanel = self.qolTitleHeaderStatsPanel
        local xpPanel = self.qolTitleHeaderXpPanel
        local gap = statsPanel and xpPanel and 10 or 0
        local panelsWidth = 0
        if statsPanel then
            panelsWidth = panelsWidth + statsPanel.width + 8
        end
        if xpPanel then
            panelsWidth = panelsWidth + xpPanel.width + 8
        end
        panelsWidth = panelsWidth + gap

        local requiredWidth = self:getWidth() - self.titleLabel:getWidth() + panelsWidth
        if requiredWidth > self:getWidth() then
            originalWidgetTitleHeaderCalculateLayout(self, requiredWidth, preferredHeight)
        end

        local contentHeight = self:getHeight()
        self.qolTitleHeaderPanelY = contentHeight + 5
        self:setHeight(contentHeight + (self.qolTitleHeaderPanelReservedHeight or 0))
    end

    originalWidgetTitleHeaderRender = ISWidgetTitleHeader.render

    ISWidgetTitleHeader.render = function(self)
        originalWidgetTitleHeaderRender(self)

        if not self.qolTitleHeaderHasPanels then
            return
        end

        local padding = 4
        local font = self.titleLabel and self.titleLabel.font or UIFont.Small
    local panelY = self.qolTitleHeaderPanelY or 0
        local panelX = self.titleLabel:getX() + 4
        local function drawPanel(panel)
            if not panel then
                return
            end
            local x = panelX - padding
            local y = panelY - padding
            local width = panel.width + (padding * 2)
            local height = panel.height + (padding * 2)
            self:drawRect(x, y, width, height, 0.32, 0.08, 0.08, 0.08)
            self:drawRectBorder(x, y, width, height, 0.8, 0.75, 0.9, 0.75)
            local lineY = panelY
            for line in string.gmatch(panel.text .. "\n", "([^\n]*)\n") do
                self:drawText(line, panelX, lineY, 1, 1, 1, 1, font)
                lineY = lineY + getTextManager():getFontHeight(font)
            end
            panelX = panelX + width + 6
        end

        drawPanel(self.qolTitleHeaderStatsPanel)
        drawPanel(self.qolTitleHeaderXpPanel)
    end

    logDebug("craft title header patch active")
    return true
end

local function patchCraftLogicTitle()
    pcall(require, "Entity/ISUI/Components/Crafting/ISWidgetCraftLogicTitle")
    if not ISWidgetCraftLogicTitle or not ISWidgetCraftLogicTitle.createChildren then
        return false
    end

    if originalWidgetCraftLogicTitleCreateChildren then
        return true
    end

    originalWidgetCraftLogicTitleCreateChildren = ISWidgetCraftLogicTitle.createChildren

    ISWidgetCraftLogicTitle.createChildren = function(self)
        originalWidgetCraftLogicTitleCreateChildren(self)

        if not self.titleLabel then
            return
        end

        local baseTitle = self.titleLabel.origTitleStr or self.titleLabel.name or self.title or ""
        local lines = {}
        if isCraftOutputTooltipEnabled() then
            local statsLine = buildTitleHeaderOutputStatsLine(self.logic)
            if statsLine and statsLine ~= "" then
                lines[#lines + 1] = statsLine
            end
        end

        if #lines > 0 then
            self.titleLabel:setName(tostring(baseTitle) .. "\n" .. table.concat(lines, "\n"))
        else
            self.titleLabel:setName(tostring(baseTitle))
        end
        self.titleLabel:setHeightToName(0)
    end

    logDebug("craft recipe title info patch active")
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
    local craftLogicTitleOk = patchCraftLogicTitle()
    return inventoryOk and craftOk and craftLogicOk and fallbackOk and invTooltipOk and titleHeaderOk and craftLogicTitleOk
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
