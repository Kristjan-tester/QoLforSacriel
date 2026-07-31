local ArmorMoodBase = {}

local installed = false
local lastUpdateByPlayer = {}
local lastDiscomfortByPlayer = {}

local function getWornItemAt(wornItems, index)
    if wornItems.getItemByIndex then
        local item = wornItems:getItemByIndex(index)
        if item then
            return item
        end

        -- Some builds expose 1-based getItemByIndex; try both before falling back.
        if index >= 0 then
            item = wornItems:getItemByIndex(index + 1)
            if item then
                return item
            end
        end
    end

    local entry = wornItems:get(index)
    if entry and entry.getItem then
        return entry:getItem()
    end

    if not entry and index >= 0 then
        entry = wornItems:get(index + 1)
        if entry and entry.getItem then
            return entry:getItem()
        end
    end

    return entry
end

local function isArmorItem(item)
    if not item then
        return false
    end

    local category = nil
    if item.getDisplayCategory then
        category = item:getDisplayCategory()
    end

    if category == nil and item.getScriptItem then
        local scriptItem = item:getScriptItem()
        if scriptItem and scriptItem.getDisplayCategory then
            category = scriptItem:getDisplayCategory()
        end
    end

    if not category then
        return false
    end

    local normalized = tostring(category):gsub("[^%a]", ""):lower()
    return normalized == "protectivegear"
end

local function isWearingArmor(playerObj)
    local wornItems = playerObj:getWornItems()
    if not wornItems then
        return false
    end

    for i = 0, wornItems:size() - 1 do
        local item = getWornItemAt(wornItems, i)
        if isArmorItem(item) then
            return true
        end
    end

    return false
end

local function clampToPositiveNumber(value, fallback)
    local n = tonumber(value)
    if not n or n ~= n then
        return fallback
    end
    if n <= 0 then
        return fallback
    end
    return n
end

local function clamp01(value, fallback)
    local n = tonumber(value)
    if not n then
        n = fallback
    end
    if n < 0 then return 0 end
    if n > 1 then return 1 end
    return n
end

local function isTrueSafe(value)
    return value == true
end

local function hasActionStateKeyword(playerObj)
    if not playerObj or not playerObj.getCurrentActionContextStateName then
        return false
    end

    local stateName = playerObj:getCurrentActionContextStateName()
    if not stateName then
        return false
    end

    local normalized = tostring(stateName):lower()
    return normalized:find("climb", 1, true) ~= nil
        or normalized:find("vault", 1, true) ~= nil
        or normalized:find("fence", 1, true) ~= nil
end

local function hasClimbOrVaultVariable(playerObj)
    if not playerObj or not playerObj.getVariableBoolean then
        return false
    end

    local vars = {
        "ClimbingFence",
        "ClimbFenceStarted",
        "ClimbFenceFinished",
        "ClimbWindowStarted",
        "ClimbWindowEnd",
        "ClimbWindowFinished",
        "VaultOverRun",
        "VaultOverSprint",
    }

    for i = 1, #vars do
        if isTrueSafe(playerObj:getVariableBoolean(vars[i])) then
            return true
        end
    end

    return false
end

local function isSuppressedTimedAction(playerObj)
    if not playerObj or not ISTimedActionQueue or not ISTimedActionQueue.getTimedActionQueue then
        return false
    end

    local queue = ISTimedActionQueue.getTimedActionQueue(playerObj)
    if not queue or not queue.queue or not queue.queue[1] then
        return false
    end

    local current = queue.queue[1]
    local actionType = current and current.Type
    if not actionType then
        return false
    end

    local actionTypeText = tostring(actionType)

    if actionTypeText == "ISChopTreeAction"
        or actionTypeText == "ISRemoveBush"
        or actionTypeText == "ISBuildAction"
        or actionTypeText == "ISMultiStageBuild"
        or actionTypeText == "ISDismantleAction"
    then
        return true
    end

    -- Covers ISCraftAction, ISHandcraftAction, ISCraftAnimAction, ISStartCraftProcessorAction, etc.
    return actionTypeText:lower():find("craft", 1, true) ~= nil
end

local function shouldSuspendArmorEffect(playerObj)
    if not playerObj then
        return false
    end

    if playerObj.isSprinting and playerObj:isSprinting() then
        return true
    end

    if playerObj.isRunning and playerObj:isRunning() then
        return true
    end

    if playerObj.isClimbing and playerObj:isClimbing() then
        return true
    end

    if hasClimbOrVaultVariable(playerObj) then
        return true
    end

    if hasActionStateKeyword(playerObj) then
        return true
    end

    if isSuppressedTimedAction(playerObj) then
        return true
    end

    return false
end

local function onPlayerUpdate(playerObj, settings, logger)
    if not playerObj or playerObj:isDead() then
        return
    end

    if settings.isEnabled("QoLforSacriel_EnableArmorMood") ~= true then
        return
    end

    local stats = playerObj:getStats()
    if not stats then
        return
    end

    local playerIndex = playerObj:getPlayerNum() or 0

    if not isWearingArmor(playerObj) then
        lastDiscomfortByPlayer[playerIndex] = stats:get(CharacterStat.DISCOMFORT)
        return
    end

    if shouldSuspendArmorEffect(playerObj) then
        -- While high-effort actions are active, do not apply armor discomfort mitigation.
        lastDiscomfortByPlayer[playerIndex] = stats:get(CharacterStat.DISCOMFORT)
        return
    end

    local worldHours = getGameTime():getWorldAgeHours()
    local cooldownSeconds = clampToPositiveNumber(settings.get("QoLforSacriel_ArmorMood_UpdateCooldownSeconds"), 2)
    local cooldownHours = cooldownSeconds / 3600
    local lastUpdate = lastUpdateByPlayer[playerIndex] or 0
    if worldHours - lastUpdate < cooldownHours then
        return
    end

    local currentDiscomfort = stats:get(CharacterStat.DISCOMFORT)
    local previousDiscomfort = lastDiscomfortByPlayer[playerIndex]

    if previousDiscomfort ~= nil and currentDiscomfort > previousDiscomfort then
        local reductionFactor = clamp01(settings.get("QoLforSacriel_ArmorMood_BaseReductionFactor"), 0.2)
        local gain = currentDiscomfort - previousDiscomfort
        local adjusted = previousDiscomfort + (gain * (1.0 - reductionFactor))
        adjusted = math.max(0.0, adjusted)

        if adjusted < currentDiscomfort then
            stats:set(CharacterStat.DISCOMFORT, adjusted)
            currentDiscomfort = adjusted
        end
    end

    lastDiscomfortByPlayer[playerIndex] = currentDiscomfort
    lastUpdateByPlayer[playerIndex] = worldHours
end

function ArmorMoodBase.init(settings, logger)
    if installed then
        logger.debug("ArmorMood.Base already installed")
        return
    end

    local wrapped = function(playerObj)
        local ok, err = pcall(function()
            onPlayerUpdate(playerObj, settings, logger)
        end)
        if not ok then
            logger.error("ArmorMood.Base update error: " .. tostring(err))
        end
    end

    Events.OnPlayerUpdate.Add(wrapped)
    installed = true
    logger.info("ArmorMood.Base installed")
end

return ArmorMoodBase
