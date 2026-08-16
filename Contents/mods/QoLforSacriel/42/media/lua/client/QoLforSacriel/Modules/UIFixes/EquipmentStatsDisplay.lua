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
local originalCharacterProtectionRender = nil
local inventoryTooltipProviders = {}

function EquipmentStatsDisplay.registerInventoryTooltipProvider(provider)
    if type(provider) ~= "function" then
        return false
    end
    for _, existingProvider in ipairs(inventoryTooltipProviders) do
        if existingProvider == provider then
            return true
        end
    end
    table.insert(inventoryTooltipProviders, provider)
    return true
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
    if not settingsRef.isEnabled
        or settingsRef.isEnabled("QoLforSacriel_EnableUIFixes") ~= true
        or (
            settingsRef.get("QoLforSacriel_UIFixes_EnableShowStats") ~= true
            and settingsRef.get("QoLforSacriel_UIFixes_EnableCraftRecipeXp") ~= true
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

local function isShowStatsEnabled()
    if not isUiFixesEnabled() then
        return false
    end
    return settingsRef.get("QoLforSacriel_UIFixes_EnableShowStats") == true
end

local function isCraftRecipeXpEnabled()
    if not isUiFixesEnabled() then
        return false
    end
    return settingsRef.get("QoLforSacriel_UIFixes_EnableCraftRecipeXp") == true
end

local function isBasicWeaponStatsEnabled()
    if not isUiFixesEnabled() then
        return false
    end
    return settingsRef.get("QoLforSacriel_UIFixes_ShowBasicWeaponStats") == true
end

local function toNumberOrNil(value)
    local n = tonumber(value)
    if n == nil or n ~= n or n == math.huge or n == -math.huge then
        return nil
    end
    return n
end

local function formatCurrentMax(currentValue, maxValue)
    local current = toNumberOrNil(currentValue)
    local max = toNumberOrNil(maxValue)
    if current == nil or max == nil then
        return nil
    end
    current = math.max(0, math.floor(current))
    max = math.max(0, math.floor(max))
    if max <= 0 then
        return tostring(current)
    end
    if current > max then
        current = max
    end
    return tostring(current) .. "/" .. tostring(max)
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

local function getWornItemAt(wornItems, index)
    if not wornItems then
        return nil
    end

    local itemOk, item = safeCallMethod(wornItems, "getItemByIndex", index)
    if itemOk and item then
        return item
    end

    local entryOk, entry = safeCallMethod(wornItems, "get", index)
    if not entryOk or not entry then
        return nil
    end

    local wrappedItemOk, wrappedItem = safeCallMethod(entry, "getItem")
    if wrappedItemOk and wrappedItem then
        return wrappedItem
    end

    return entry
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

    return toNumberOrNil(value)
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

    if isBasicWeaponStatsEnabled() then
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

local function getLocalizedText(key, fallback)
    if type(getText) ~= "function" then
        return fallback
    end
    local ok, text = pcall(getText, key)
    if ok and text and text ~= "" then
        return text
    end
    return fallback
end

local function formatPercent(value, decimals)
    local numericValue = toNumberOrNil(value)
    if numericValue == nil then
        return nil
    end
    return formatFloat(numericValue * 100, decimals or 0) .. "%"
end

local function formatMultiplier(value)
    local numericValue = toNumberOrNil(value)
    if numericValue == nil then
        return nil
    end
    local multiplier = formatFloat(numericValue, 2)
    local delta = formatPercent(numericValue - 1, 0)
    if not multiplier or not delta then
        return nil
    end
    if numericValue > 1 then
        delta = "+" .. delta
    end
    return "x" .. multiplier .. " (" .. delta .. ")"
end

local function getWornEquipmentModifierRows(character)
    if not character then
        return {}
    end

    local rows = {}
    local runSpeed = 1
    local combatSpeed = 1
    local vision = 1
    local hearing = 1
    local discomfort = 0
    local stompPower = nil
    local wornItemsOk, wornItems = safeCallMethod(character, "getWornItems")
    local countOk, wornCount = safeCallMethod(wornItemsOk and wornItems or nil, "size")
    wornCount = countOk and math.max(0, math.floor(tonumber(wornCount) or 0)) or 0
    for index = 0, wornCount - 1 do
        local item = getWornItemAt(wornItems, index)
        local runModifier = getMethodNumberOrNil(item, "getRunSpeedModifier")
        if runModifier then
            runSpeed = runSpeed + (runModifier - 1)
        end

        local combatModifier = getMethodNumberOrNil(item, "getCombatSpeedModifier")
        if combatModifier then
            combatSpeed = combatSpeed + (combatModifier - 1)
        end

        local visionModifier = getMethodNumberOrNil(item, "getVisionModifier")
        if visionModifier and visionModifier > 0 then
            vision = vision * visionModifier
        end

        local hearingModifier = getMethodNumberOrNil(item, "getHearingModifier")
        if hearingModifier and hearingModifier > 0 then
            hearing = hearing * hearingModifier
        end

        local discomfortModifier = getMethodNumberOrNil(item, "getDiscomfortModifier")
        if discomfortModifier then
            discomfort = discomfort + discomfortModifier
        end
    end

    if ItemBodyLocation and ItemBodyLocation.SHOES then
        local shoesOk, shoes = safeCallMethod(character, "getWornItem", ItemBodyLocation.SHOES)
        if shoesOk and shoes then
            stompPower = getMethodNumberOrNil(shoes, "getStompPower")
        end
    end

    discomfort = math.max(0, discomfort)
    rows[#rows + 1] = {
        label = getLocalizedText("Tooltip_CombatSpeedModifier", "Combat Speed"),
        value = formatMultiplier(combatSpeed),
    }

    rows[#rows + 1] = {
        label = getLocalizedText("UI_QoLforSacriel_Protection_RunSpeedEquipment", "Run Speed (Equipment)"),
        value = formatMultiplier(runSpeed),
    }

    rows[#rows + 1] = {
        label = getLocalizedText("UI_QoLforSacriel_Protection_VisionImpairment", "Vision Impairment"),
        value = formatMultiplier(vision),
    }

    rows[#rows + 1] = {
        label = getLocalizedText("UI_QoLforSacriel_Protection_HearingImpairment", "Hearing Impairment"),
        value = formatMultiplier(hearing),
    }

    rows[#rows + 1] = {
        label = getLocalizedText("UI_QoLforSacriel_Protection_MaxWornDiscomfort", "Max worn Discomfort"),
        value = tostring(math.ceil(discomfort * 100)) .. "/100",
    }

    if not isBasicWeaponStatsEnabled() and stompPower then
        rows[#rows + 1] = {
            label = getLocalizedText("UI_QoLforSacriel_Protection_StompingPower", "Stomping Power"),
            value = tostring(math.floor(stompPower * 100 + 0.5)) .. "%",
        }
    end

    return rows, {
        wornCount = wornCount,
        combatSpeed = combatSpeed,
        runSpeed = runSpeed,
        vision = vision,
        hearing = hearing,
        discomfort = discomfort,
        stompPower = stompPower,
    }
end

local function addNumericAppendLine(lines, seen, key, label, value)
    if not key or seen[key] or not label or not value or value == "" then
        return
    end
    local normalized = string.lower(tostring(value))
    if normalized == "nan" or normalized == "inf" or normalized == "infinity" or normalized == "n/a" then
        return
    end
    seen[key] = true
    lines[#lines + 1] = {
        label = tostring(label),
        value = tostring(value),
    }
end

local function itemHasHideRemainingTag(item)
    if not ItemTag or not ItemTag.HIDE_REMAINING then
        return false
    end
    local ok, hasTag = safeCallMethod(item, "hasTag", ItemTag.HIDE_REMAINING)
    return ok and hasTag == true
end

local function itemHasTag(item, tagName)
    if not ItemTag or not ItemTag[tagName] then
        return false
    end
    local ok, hasTag = safeCallMethod(item, "hasTag", ItemTag[tagName])
    return ok and hasTag == true
end

local function isItemInstance(item, className)
    return instanceof and item and instanceof(item, className) == true
end

local function isLiteratureItem(item)
    local literatureOk, literature = safeCallItemMethod(item, "IsLiterature")
    return (literatureOk and literature == true) or isItemInstance(item, "Literature")
end

local function isShoesItem(item)
    if not ItemBodyLocation or not ItemBodyLocation.SHOES then
        return false
    end
    local bodyLocationOk, bodyLocation = safeCallItemMethod(item, "getBodyLocation")
    return bodyLocationOk and bodyLocation == ItemBodyLocation.SHOES
end

local function characterHasTrait(character, traitName)
    if not character or not CharacterTrait or not CharacterTrait[traitName] then
        return false
    end
    local ok, result = safeCallMethod(character, "hasTrait", CharacterTrait[traitName])
    return ok and result == true
end

local function canShowFoodNutrition(item, character)
    if characterHasTrait(character, "NUTRITIONIST") or characterHasTrait(character, "NUTRITIONIST2") then
        return true
    end
    local packagedOk, packaged = safeCallItemMethod(item, "isPackaged")
    if not packagedOk or packaged ~= true or characterHasTrait(character, "ILLITERATE") then
        return false
    end
    local modDataOk, modData = safeCallItemMethod(item, "getModData")
    local noLabel = false
    if modDataOk and modData and modData.rawget then
        local okNoLabel, value = pcall(modData.rawget, modData, "NoLabel")
        noLabel = okNoLabel and value ~= nil
    end
    if noLabel then
        return false
    end
    local darkOk, tooDark = safeCallMethod(character, "tooDarkToRead")
    return not (darkOk and tooDark == true)
end

local function addFoodAppendRows(lines, seen, item, character)
    local effects = {
        { "getHungerChange", "food-hunger", "Tooltip_food_Hunger", "Hunger", 100 },
        { "getThirstChange", "food-thirst", "Tooltip_food_Thirst", "Thirst", -200 },
        { "getEnduranceChange", "food-endurance", "Tooltip_food_Endurance", "Endurance", 100 },
        { "getStressChange", "food-stress", "Tooltip_food_Stress", "Stress", 100 },
        { "getBoredomChange", "food-boredom", "Tooltip_food_Boredom", "Boredom", 1 },
        { "getUnhappyChange", "food-unhappiness", "Tooltip_food_Unhappiness", "Unhappiness", 1 },
    }
    for index = 1, #effects do
        local spec = effects[index]
        local value = getMethodNumberOrNil(item, spec[1])
        if value and value ~= 0 then
            local formatted = formatFloat(value * spec[5], 0)
            if formatted and value * spec[5] > 0 then
                formatted = "+" .. formatted
            end
            addNumericAppendLine(lines, seen, spec[2], getLocalizedText(spec[3], spec[4]), formatted)
        end
    end

    local freezingTime = getMethodNumberOrNil(item, "getFreezingTime")
    if freezingTime and freezingTime > 0 and freezingTime < 100 then
        addNumericAppendLine(lines, seen, "food-freezing", getLocalizedText("IGUI_invpanel_FreezingTime", "Freezing"), formatFloat(freezingTime, 0) .. "%")
    end

    if canShowFoodNutrition(item, character) then
        local nutrition = {
            { "getCalories", "food-calories", "Tooltip_food_Calories", "Calories" },
            { "getCarbohydrates", "food-carbohydrates", "Tooltip_food_Carbs", "Carbohydrates" },
            { "getProteins", "food-proteins", "Tooltip_food_Prots", "Proteins" },
            { "getLipids", "food-lipids", "Tooltip_food_Fat", "Fat" },
        }
        for index = 1, #nutrition do
            local spec = nutrition[index]
            local value = getMethodNumberOrNil(item, spec[1])
            if value then
                addNumericAppendLine(lines, seen, spec[2], getLocalizedText(spec[3], spec[4]), formatFloat(value, 0))
            end
        end
    end
end

local function addClothingAppendRows(lines, seen, item)
    local cosmeticOk, cosmetic = safeCallItemMethod(item, "isCosmetic")
    local isCosmetic = cosmeticOk and cosmetic == true
    if not isCosmetic then
        local condition = getMethodNumberOrNil(item, "getCondition")
        local conditionMax = getMethodNumberOrNil(item, "getConditionMax")
        if condition and conditionMax and conditionMax > 0 then
            local ratio = formatCurrentMax(condition, conditionMax)
            local percentage = formatPercent(condition / conditionMax)
            if ratio and percentage then
                addNumericAppendLine(lines, seen, "clothing-condition", getLocalizedText("Tooltip_weapon_Condition", "Condition"), ratio .. " (" .. percentage .. ")")
            end
        end
        local resistanceRows = {
            { "getInsulation", "clothing-insulation", "Tooltip_item_Insulation", "Insulation", true },
            { "getWindresistance", "clothing-wind", "Tooltip_item_Windresist", "Wind Resistance", false },
            { "getWaterResistance", "clothing-water", "Tooltip_item_Waterresist", "Water Resistance", false },
        }
        for index = 1, #resistanceRows do
            local spec = resistanceRows[index]
            local value = getMethodNumberOrNil(item, spec[1])
            if value and (spec[5] or value > 0) then
                addNumericAppendLine(lines, seen, spec[2], getLocalizedText(spec[3], spec[4]), formatPercent(value))
            end
        end
    end

    local stateRows = {
        { "getBloodLevel", "clothing-blood", "Tooltip_clothing_bloody", "Blood", 0 },
        { "getDirtiness", "clothing-dirt", "Tooltip_clothing_dirty", "Dirt", 1 },
        { "getWetness", "clothing-wetness", "Tooltip_clothing_wet", "Wetness", 0 },
    }
    for index = 1, #stateRows do
        local spec = stateRows[index]
        local value = getMethodNumberOrNil(item, spec[1])
        if value and value >= spec[5] and value > 0 then
            addNumericAppendLine(lines, seen, spec[2], getLocalizedText(spec[3], spec[4]), formatFloat(value, 0) .. "%")
        end
    end

    local runSpeed = getMethodNumberOrNil(item, "getRunSpeedModifier")
    if runSpeed and runSpeed ~= 1 then
        addNumericAppendLine(lines, seen, "clothing-run-speed", getLocalizedText("Tooltip_RunSpeedModifier", "Run Speed"), formatMultiplier(runSpeed))
    end

    local combatSpeed = getMethodNumberOrNil(item, "getCombatSpeedModifier")
    if combatSpeed and combatSpeed ~= 1 then
        addNumericAppendLine(lines, seen, "clothing-combat-speed", getLocalizedText("Tooltip_CombatSpeedModifier", "Combat Speed"), formatMultiplier(combatSpeed))
    end

    if not isBasicWeaponStatsEnabled() and isShoesItem(item) then
        local stompPower = getMethodNumberOrNil(item, "getStompPower")
        if stompPower then
            addNumericAppendLine(lines, seen, "clothing-stomping-power", getLocalizedText("UI_QoLforSacriel_Protection_StompingPower", "Stomping Power"), formatPercent(stompPower))
        end
    end
end

local function addContainerAppendRows(lines, seen, item, character)
    local capacityOk, capacity = safeCallMethod(item, "getEffectiveCapacity", character)
    if capacityOk and toNumberOrNil(capacity) and toNumberOrNil(capacity) ~= 0 then
        addNumericAppendLine(lines, seen, "container-capacity", getLocalizedText("Tooltip_container_Capacity", "Capacity"), formatFloat(capacity, 0))
    end
    local reduction = getMethodNumberOrNil(item, "getWeightReduction")
    if reduction and reduction ~= 0 then
        addNumericAppendLine(lines, seen, "container-reduction", getLocalizedText("Tooltip_container_Weight_Reduction", "Weight Reduction"), formatFloat(reduction, 0) .. "%")
    end
    local maxItemSize = getMethodNumberOrNil(item, "getMaxItemSize")
    if maxItemSize and maxItemSize ~= 0 then
        addNumericAppendLine(lines, seen, "container-max-size", getLocalizedText("Tooltip_container_Max_Item_Size", "Max Item Size"), formatFloat(maxItemSize, 2))
    end
end

local function canShowLiteratureEffects(item, character)
    if not character then
        return false
    end

    local modDataOk, modData = safeCallItemMethod(item, "getModData")
    if not modDataOk or not modData then
        return false
    end

    local titleOk, title = pcall(function()
        return modData.literatureTitle
    end)
    if not titleOk then
        return false
    end
    if title == nil then
        return true
    end

    local readOk, read = safeCallMethod(character, "isLiteratureRead", title)
    return readOk and read ~= true
end

local function addLiteratureAppendRows(lines, seen, item, character)
    if canShowLiteratureEffects(item, character) then
        local effects = {
            { "getBoredomChange", "literature-boredom", "Tooltip_food_Boredom", "Boredom", 1 },
            { "getStressChange", "literature-stress", "Tooltip_literature_Stress_Reduction", "Stress", 100 },
            { "getUnhappyChange", "literature-unhappiness", "Tooltip_food_Unhappiness", "Unhappiness", 1 },
        }
        for index = 1, #effects do
            local spec = effects[index]
            local effect = getMethodNumberOrNil(item, spec[1])
            if effect and effect ~= 0 then
                addNumericAppendLine(lines, seen, spec[2], getLocalizedText(spec[3], spec[4]), formatFloat(effect * spec[5], 0))
            end
        end
    end

    local pages = getMethodNumberOrNil(item, "getNumberOfPages")
    if pages and pages ~= -1 then
        local value = tostring(math.max(0, math.floor(pages)))
        local fullTypeOk, fullType = safeCallItemMethod(item, "getFullType")
        if character and fullTypeOk and fullType then
            local readOk, readPages = safeCallMethod(character, "getAlreadyReadPages", fullType)
            if readOk then
                local ratio = formatCurrentMax(readPages or 0, pages)
                if ratio then
                    value = ratio
                end
            end
        end
        addNumericAppendLine(lines, seen, "literature-pages", getLocalizedText("Tooltip_literature_Number_of_Pages", "Pages"), value)
    end
end

local function collectNumericTooltipAppendLines(item, character)
    local lines = {}
    local seen = {}
    local isWeapon = isStrictWeaponItem(item)
    local isClothing = instanceof and instanceof(item, "Clothing") == true

    local remainingUses = getMethodNumberOrNil(item, "getCurrentUsesFloat")
    if isItemInstance(item, "DrainableComboItem") and remainingUses and not itemHasHideRemainingTag(item) and remainingUses >= 0 and remainingUses <= 1 then
        addNumericAppendLine(lines, seen, "remaining", getLocalizedText("IGUI_invpanel_Remaining", "Remaining"), formatPercent(remainingUses))
    end

    local fatigue = getMethodNumberOrNil(item, "getFatigueChange")
    if fatigue and fatigue ~= 0 then
        local formatted = formatPercent(fatigue)
        if formatted and fatigue > 0 then
            formatted = "+" .. formatted
        end
        addNumericAppendLine(lines, seen, "fatigue", getLocalizedText("Tooltip_item_Fatigue", "Fatigue"), formatted)
    end

    local wetOk, wet = safeCallItemMethod(item, "isWet")
    local wetCooldown = getMethodNumberOrNil(item, "getWetCooldown")
    if wetOk and wet == true and wetCooldown and wetCooldown >= 0 and wetCooldown <= 10000 then
        addNumericAppendLine(lines, seen, "wetness", getLocalizedText("Tooltip_Wetness", "Wetness"), formatPercent(wetCooldown / 10000))
    end

    local hasSharpnessOk, hasSharpness = safeCallItemMethod(item, "hasSharpness")
    local sharpness = getMethodNumberOrNil(item, "getSharpness")
    if not isWeapon and hasSharpnessOk and hasSharpness == true and sharpness and sharpness >= 0 and sharpness <= 1 then
        addNumericAppendLine(lines, seen, "sharpness", getLocalizedText("Tooltip_weapon_Sharpness", "Sharpness"), formatPercent(sharpness))
    end

    local condition = getMethodNumberOrNil(item, "getCondition")
    local conditionMax = getMethodNumberOrNil(item, "getConditionMax")
    local mechanicType = getMethodNumberOrNil(item, "getMechanicType")
    if not isWeapon and not isClothing and condition and conditionMax and conditionMax > 0 then
        local showCondition = (condition < conditionMax) or (mechanicType and mechanicType > 0) or itemHasTag(item, "SHOW_CONDITION")
        if showCondition then
            local ratio = formatCurrentMax(condition, conditionMax)
            local percentage = formatPercent(condition / conditionMax)
            if ratio and percentage then
                addNumericAppendLine(lines, seen, "condition", getLocalizedText("Tooltip_weapon_Condition", "Condition"), ratio .. " (" .. percentage .. ")")
            end
        end
    end

    local modifiers = {
        { "getVisionModifier", "vision", "Tooltip_item_VisionImpariment", "Vision" },
        { "getHearingModifier", "hearing", "Tooltip_item_HearingImpariment", "Hearing" },
    }
    for index = 1, #modifiers do
        local spec = modifiers[index]
        local value = getMethodNumberOrNil(item, spec[1])
        if value and value ~= 1 then
            addNumericAppendLine(lines, seen, spec[2], getLocalizedText(spec[3], spec[4]), formatMultiplier(value))
        end
    end

    local discomfort = getMethodNumberOrNil(item, "getDiscomfortModifier")
    if discomfort and discomfort ~= 0 then
        local formatted = formatPercent(discomfort)
        if formatted and discomfort > 0 then
            formatted = "+" .. formatted
        end
        addNumericAppendLine(lines, seen, "discomfort", getLocalizedText("Tooltip_item_Discomfort", "Discomfort"), formatted)
    end

    if isItemInstance(item, "Food") then
        addFoodAppendRows(lines, seen, item, character)
    elseif isItemInstance(item, "Clothing") then
        addClothingAppendRows(lines, seen, item)
    elseif isItemInstance(item, "InventoryContainer") then
        addContainerAppendRows(lines, seen, item, character)
    elseif isLiteratureItem(item) then
        addLiteratureAppendRows(lines, seen, item, character)
    end

    if isWeapon then
        local weaponLines = collectEquipmentStats(item)
        for index = 1, #weaponLines do
            local line = tostring(weaponLines[index])
            if not string.find(line, "N/A", 1, true) then
                local label, value = string.match(line, "^(.+):%s*(.+)$")
                if label and value then
                    lines[#lines + 1] = {
                        label = label,
                        value = value,
                    }
                end
            end
        end
    end

    return lines
end

local function collectInventoryTooltipAppendRows(item, character)
    local rows = {}
    if isShowStatsEnabled() then
        local statsLines = collectNumericTooltipAppendLines(item, character)
        if #statsLines > 0 then
            local sectionTitle = getLocalizedText("UI_QoLforSacriel_Modules_NumericTooltipAppendHeader", "ShowStats")
            if sectionTitle and sectionTitle ~= "" then
                table.insert(rows, { header = sectionTitle })
            end
            for _, line in ipairs(statsLines) do
                table.insert(rows, line)
            end
        end
    end

    for _, provider in ipairs(inventoryTooltipProviders) do
        local ok, providerRows = pcall(provider, item, character)
        if ok and type(providerRows) == "table" then
            for _, line in ipairs(providerRows) do
                if type(line) == "table" and line.label and line.value then
                    table.insert(rows, line)
                end
            end
        end
    end
    return rows
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

local function getCraftOutputStats(logic)
    local outputItem = resolvePrimaryOutputItemFromLogic(logic)
    if not outputItem then
        return nil
    end

    local playerOk, playerObj = safeCallMethod(logic, "getPlayer")
    local lines = collectNumericTooltipAppendLines(outputItem, playerOk and playerObj or nil)
    if #lines == 0 then
        return nil
    end

    local fullTypeOk, fullType = safeCallItemMethod(outputItem, "getFullType")
    return {
        title = getLocalizedText("UI_QoLforSacriel_Craft_OutputStats", "Output Stats"),
        rows = lines,
        signature = fullTypeOk and tostring(fullType) or tostring(outputItem),
    }
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

    local statsText = buildStatsDescription(item, { context = "crafting" })
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

local function appendStatsToObjectTooltip(tooltipUI, item, character, sourceTag)
    if not tooltipUI or not item then
        return false
    end

    local lines = collectNumericTooltipAppendLines(item, character)
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

    local padLeft = 5
    local padBottom = 5
    local padRight = 5
    local columnGap = 16
    local y = math.max(0, tooltipHeight - padBottom)
    local textManager = getTextManager and getTextManager() or nil

    for _, line in ipairs(lines) do
        local label = tostring(line.label)
        local value = tostring(line.value)
        if textManager and type(textManager.MeasureStringX) == "function" then
            local requiredWidth = padLeft + textManager:MeasureStringX(font, label) + columnGap + textManager:MeasureStringX(font, value) + padRight
            tooltipUI:adjustWidth(requiredWidth, "")
        else
            tooltipUI:adjustWidth(padLeft, label .. "  " .. value)
        end
        tooltipUI:DrawText(font, label, padLeft, y, 0.75, 0.95, 0.75, 1.0)
        tooltipUI:DrawTextRight(font, value, tooltipUI:getWidth() - padRight, y, 1.0, 1.0, 1.0, 1.0)
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

            if not isShowStatsEnabled() then
                return
            end

            local outputItem = resolveOutputItemFromCraftLogicItemSlot(itemSlot)
            local playerOk, playerObj = safeCallMethod(self, "getPlayer")
            appendStatsToObjectTooltip(tooltipUI, outputItem, playerOk and playerObj or nil, "ISWidgetCraftLogicInputControl.outputItems.drawTooltip")
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
        if not isShowStatsEnabled() then
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
            appendStatsToObjectTooltip(tooltipUI, outputItem, nil, "ISToolTipItemSlot.render")
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
        if self and self.owner and self.owner.Type == "ISEquippedItem" then
            return originalToolTipInvRender(self)
        end

        if not self or not self.item or not self.tooltip then
            return originalToolTipInvRender(self)
        end

        local characterOk, character = safeCallMethod(self.tooltip, "getCharacter")
        local rows = collectInventoryTooltipAppendRows(self.item, characterOk and character or nil)
        if #rows == 0 then
            return originalToolTipInvRender(self)
        end

        local font = UIFont[getCore():getOptionTooltipFont()]
        local lineSpacing = self.tooltip:getLineSpacing()
        local extraHeight = #rows * lineSpacing
        local padLeft = 5
        local padRight = 5
        local columnGap = 16
        local requiredWidth = 0
        local textManager = getTextManager and getTextManager() or nil
        if textManager and type(textManager.MeasureStringX) == "function" then
            for _, row in ipairs(rows) do
                if row.header then
                    requiredWidth = math.max(requiredWidth, padLeft + textManager:MeasureStringX(font, row.header) + padRight)
                else
                    local labelWidth = textManager:MeasureStringX(font, row.label)
                    local valueWidth = textManager:MeasureStringX(font, row.value)
                    requiredWidth = math.max(requiredWidth, padLeft + labelWidth + columnGap + valueWidth + padRight)
                end
            end
        end

        local originalSetHeight = ISToolTipInv.setHeight
        local originalSetWidth = ISToolTipInv.setWidth
        local originalDrawRectBorder = ISToolTipInv.drawRectBorder
        if type(originalSetHeight) ~= "function" or type(originalSetWidth) ~= "function" or type(originalDrawRectBorder) ~= "function" then
            return originalToolTipInvRender(self)
        end

        self.setWidth = function(instance, width, ...)
            local finalWidth = math.max(tonumber(width) or 0, requiredWidth)
            if instance.tooltip then
                instance.tooltip:setWidth(finalWidth)
            end
            return originalSetWidth(instance, finalWidth, ...)
        end

        self.setHeight = function(instance, height, ...)
            instance.keepOnScreen = false
            return originalSetHeight(instance, (tonumber(height) or 0) + extraHeight, ...)
        end

        self.drawRectBorder = function(instance, ...)
            if not instance or not instance.tooltip or type(instance.tooltip.DrawText) ~= "function" then
                return originalDrawRectBorder(instance, ...)
            end

            local y = instance.tooltip:getHeight()
            for _, row in ipairs(rows) do
                if row.header then
                    instance.tooltip:DrawText(font, row.header, padLeft, y, 0.75, 0.95, 0.75, 1.0)
                else
                    instance.tooltip:DrawText(font, row.label, padLeft, y, 0.75, 0.95, 0.75, 1.0)
                    instance.tooltip:DrawTextRight(font, row.value, instance.tooltip:getWidth() - padRight, y, 1.0, 1.0, 1.0, 1.0)
                end
                y = y + lineSpacing
            end
            return originalDrawRectBorder(instance, ...)
        end

        local ok, err = pcall(function()
            originalToolTipInvRender(self)
        end)

    self.setWidth = originalSetWidth
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

    local function measureTitleHeaderStatsPanel(stats, font)
        if not stats or not stats.rows or #stats.rows == 0 or not getTextManager then
            return nil
        end

        local textManager = getTextManager()
        if not textManager or not textManager.MeasureStringX or not textManager.getFontHeight then
            return nil
        end

        local columnGap = 16
        local width = textManager:MeasureStringX(font, stats.title)
        for _, row in ipairs(stats.rows) do
            local rowWidth = textManager:MeasureStringX(font, row.label) + columnGap + textManager:MeasureStringX(font, row.value)
            width = math.max(width, rowWidth)
        end

        return {
            title = stats.title,
            rows = stats.rows,
            width = width,
            height = textManager:getFontHeight(font) * (#stats.rows + 1),
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

        local stats = isShowStatsEnabled() and getCraftOutputStats(self.logic) or nil
        local statsSignature = recipeSignature .. "|" .. (stats and stats.signature or "<none>")
        if isShowStatsEnabled() and self.qolLastTitleStatsRecipeSignature ~= statsSignature then
            self.qolLastTitleStatsRecipeSignature = statsSignature
            self.qolLastTitleStats = stats

            if self.qolLastTitleStats then
                logDebug("titleHeader.output stats resolved for recipe='" .. recipeSignature .. "'")
            else
                logDebug("titleHeader.output stats unavailable for recipe='" .. recipeSignature .. "'")
            end
        end

        local statsModel = isShowStatsEnabled() and self.qolLastTitleStats or nil
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
        self.qolTitleHeaderStatsPanel = measureTitleHeaderStatsPanel(statsModel, font)
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
            local lineHeight = getTextManager():getFontHeight(font)
            local lineY = panelY
            if panel.rows then
                self:drawText(panel.title, panelX, lineY, 1, 1, 1, 1, font)
                lineY = lineY + lineHeight
                for _, row in ipairs(panel.rows) do
                    self:drawText(row.label, panelX, lineY, 1, 1, 1, 1, font)
                    self:drawTextRight(row.value, panelX + panel.width, lineY, 1, 1, 1, 1, font)
                    lineY = lineY + lineHeight
                end
            else
                for line in string.gmatch(panel.text .. "\n", "([^\n]*)\n") do
                    self:drawText(line, panelX, lineY, 1, 1, 1, 1, font)
                    lineY = lineY + lineHeight
                end
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
        if isShowStatsEnabled() then
            local stats = getCraftOutputStats(self.logic)
            if stats and stats.rows and #stats.rows > 0 then
                lines[#lines + 1] = stats.title
                for _, row in ipairs(stats.rows) do
                    lines[#lines + 1] = row.label .. ": " .. row.value
                end
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

local function patchCharacterProtection()
    pcall(require, "XpSystem/ISUI/ISCharacterProtection")
    if not ISCharacterProtection or not ISCharacterProtection.render then
        return false
    end

    if originalCharacterProtectionRender then
        return true
    end

    originalCharacterProtectionRender = ISCharacterProtection.render

    ISCharacterProtection.render = function(self)
        local previousFooterHeight = self and tonumber(self.qolProtectionFooterHeight) or 0
        if previousFooterHeight > 0 then
            self:setHeight(math.max(0, self:getHeight() - previousFooterHeight))
            self.qolProtectionFooterHeight = 0
        end

        originalCharacterProtectionRender(self)

        if not isShowStatsEnabled() or not self or not self.char then
            return
        end

        local rows, totals = getWornEquipmentModifierRows(self.char)
        local font = UIFont.Small
        local textManager = getTextManager and getTextManager() or nil
        if not textManager or type(textManager.MeasureStringX) ~= "function" or type(textManager.getFontHeight) ~= "function" then
            return
        end

        local padding = 6
        local bottomPadding = 8
        local columnGap = 16
        local lineHeight = textManager:getFontHeight(font)
        local title = getLocalizedText("UI_QoLforSacriel_Protection_TotalWornModifiers", "Total worn modifiers")
        local contentWidth = textManager:MeasureStringX(font, title)
        for _, row in ipairs(rows) do
            local rowWidth = textManager:MeasureStringX(font, row.label) + columnGap + textManager:MeasureStringX(font, row.value)
            contentWidth = math.max(contentWidth, rowWidth)
        end

        local bodyPartCount = 0
        if self.bparts then
            for _, enabled in pairs(self.bparts) do
                if enabled then
                    bodyPartCount = bodyPartCount + 1
                end
            end
        end
        local baseHeight = (padding + 5) + lineHeight + 6 + (bodyPartCount * lineHeight) + (padding + 5)
        local footerHeight = lineHeight * (#rows + 1) + (padding * 2) + bottomPadding
        local finalHeight = baseHeight + footerHeight
        self:setWidthAndParentWidth(math.max(self:getWidth(), contentWidth + (padding * 2)))
        self:setHeightAndParentHeight(finalHeight)
        self.qolProtectionFooterHeight = finalHeight - baseHeight

        local debugSignature = tostring(totals.wornCount)
            .. "|" .. tostring(totals.combatSpeed)
            .. "|" .. tostring(totals.runSpeed)
            .. "|" .. tostring(totals.vision)
            .. "|" .. tostring(totals.hearing)
            .. "|" .. tostring(totals.discomfort)
            .. "|" .. tostring(totals.stompPower)
        if self.qolProtectionFooterDebugSignature ~= debugSignature then
            self.qolProtectionFooterDebugSignature = debugSignature
            logDebug(
                "protection modifiers calculated: worn=" .. tostring(totals.wornCount)
                .. ", combat=" .. tostring(totals.combatSpeed)
                .. ", run=" .. tostring(totals.runSpeed)
                .. ", vision=" .. tostring(totals.vision)
                .. ", hearing=" .. tostring(totals.hearing)
                .. ", discomfort=" .. tostring(totals.discomfort)
                .. ", stomp=" .. tostring(totals.stompPower)
            )
        end

        local panelWidth = contentWidth + (padding * 2)
        local panelHeight = lineHeight * (#rows + 1) + (padding * 2)
        local panelX = math.max(0, (self:getWidth() - panelWidth) / 2)
        local y = baseHeight + padding
        local x = panelX + padding
        self:drawRect(panelX, y - padding, panelWidth, panelHeight, 0.32, 0.08, 0.08, 0.08)
        self:drawRectBorder(panelX, y - padding, panelWidth, panelHeight, 0.8, 0.75, 0.9, 0.75)
        self:drawText(title, x, y, 1, 1, 1, 1, font)
        y = y + lineHeight
        for _, row in ipairs(rows) do
            self:drawText(row.label, x, y, 1, 1, 1, 1, font)
            self:drawTextRight(row.value, x + contentWidth, y, 1, 1, 1, 1, font)
            y = y + lineHeight
        end
    end

    logDebug("character protection footer patch active")
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
        if isShowStatsEnabled()
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

        if not isShowStatsEnabled() then
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

        if not isShowStatsEnabled() then
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

        if not isShowStatsEnabled() then
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

        if not isShowStatsEnabled() then
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
    local protectionOk = patchCharacterProtection()
    return inventoryOk and craftOk and craftLogicOk and fallbackOk and invTooltipOk and titleHeaderOk and craftLogicTitleOk and protectionOk
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
