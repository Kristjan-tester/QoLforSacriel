local RestUntilSleepy = {}

local installed = false
local activeByPlayer = {}
local PAIN_INTERRUPT_LEVEL = 1

local function getLabel()
    local translated = getTextOrNull("UI_QoLforSacriel_RestUntilSleepy")
    if translated and translated ~= "" then
        return translated
    end
    return "Rest Until Sleepy"
end

local function shouldOffer(playerObj)
    if not playerObj then
        return false
    end
    if playerObj:isDead() or playerObj:getVehicle() then
        return false
    end
    if playerObj:isAsleep() then
        return false
    end
    return true
end

local function invokeOption(option)
    if not option or type(option.onSelect) ~= "function" then
        return false
    end

    option.onSelect(
        option.target,
        option.param1,
        option.param2,
        option.param3,
        option.param4,
        option.param5,
        option.param6,
        option.param7,
        option.param8,
        option.param9,
        option.param10
    )
    return true
end

local function getActionFunction(option)
    if not option then
        return nil
    end
    if option.onSelect == ISContextMenu.onGetUpAndThen then
        return option.param1
    end
    return option.onSelect
end

local function resolveRelevantActionOption(menu)
    if not menu or not menu.options then
        return nil
    end

    local fallbackSleep = nil
    for _, option in ipairs(menu.options) do
        local actionFn = getActionFunction(option)
        if actionFn == ISWorldObjectContextMenu.onRest then
            return option
        end
        if actionFn == ISWorldObjectContextMenu.onSleep and fallbackSleep == nil then
            fallbackSleep = option
        end
    end

    return fallbackSleep
end

local function stopRest(playerObj, state, logger, reason)
    if not playerObj then
        return
    end

    playerObj:StopAllActionQueue()
    if playerObj:isSitOnGround() or playerObj:isSittingOnFurniture() then
        playerObj:setVariable("forceGetUp", true)
    end

    if setGameSpeed then
        pcall(function()
            setGameSpeed(1)
        end)
    end

    if state and state.debugEnabled then
        local currentFatigue = playerObj:getStats():get(CharacterStat.FATIGUE)
        logger.debug("RestUntilSleepy stop: " .. tostring(reason) .. " | fatigue " .. tostring(state.startFatigue) .. " -> " .. tostring(currentFatigue))
    end
end

local function onSelect(playerObj, actionOption, settings, logger)
    if not shouldOffer(playerObj) then
        return
    end

    if not invokeOption(actionOption) then
        logger.warn("RestUntilSleepy could not run mapped rest/sleep action")
        return
    end

    local idx = playerObj:getPlayerNum() or 0
    local threshold = tonumber(settings.get("QoLforSacriel_RestSleep_SleepyThreshold")) or 0.3
    threshold = math.max(0.0, math.min(1.0, threshold))

    local actionFn = getActionFunction(actionOption)
    if actionFn ~= ISWorldObjectContextMenu.onRest then
        return
    end

    activeByPlayer[idx] = {
        threshold = threshold,
        debugEnabled = settings.get("QoLforSacriel_DebugLogs") == true,
        startFatigue = playerObj:getStats():get(CharacterStat.FATIGUE),
        startTs = getTimestamp(),
        startedRest = false,
    }
end

local function onFillWorldObjectContextMenu(playerIndex, context, worldobjects, test, settings, logger)
    if test then
        return
    end

    local playerObj = getSpecificPlayer(playerIndex)
    if not shouldOffer(playerObj) then
        return
    end

    for _, topOption in ipairs(context.options) do
        if topOption.subOption then
            local subMenu = context:getSubMenu(topOption.subOption)
            local actionOption = resolveRelevantActionOption(subMenu)
            if actionOption and not subMenu:getOptionFromName(getLabel()) then
                subMenu:addOption(getLabel(), playerObj, function(p, mappedOption)
                    onSelect(p, mappedOption, settings, logger)
                end, actionOption)
            end
        end
    end
end

local function shouldInterruptOnThreat(playerObj)
    local stats = playerObj:getStats()
    if not stats then
        return false
    end

    if stats.getNumVeryCloseZombies and stats:getNumVeryCloseZombies() > 0 then
        return true
    end
    return false
end

local function getPanicValue(playerObj)
    local stats = playerObj:getStats()
    if stats and stats.getPanic then
        return stats:getPanic()
    end

    local moodles = playerObj:getMoodles()
    if moodles then
        local moodleLevel = moodles:getMoodleLevel(MoodleType.PANIC)
        return math.max(0, moodleLevel) * 25
    end

    return 0
end

local function onPlayerUpdate(playerObj, settings, logger)
    if not playerObj then
        return
    end

    local idx = playerObj:getPlayerNum() or 0
    local state = activeByPlayer[idx]
    if not state then
        return
    end

    local fatigue = playerObj:getStats():get(CharacterStat.FATIGUE)

    if not state.startedRest then
        local isResting = playerObj.isResting and playerObj:isResting()
        if playerObj:isSitOnGround() or playerObj:isSittingOnFurniture() or isResting then
            state.startedRest = true
        elseif getTimestamp() - (state.startTs or 0) > 15 then
            activeByPlayer[idx] = nil
            return
        end
    end

    if not state.startedRest then
        return
    end

    if fatigue >= state.threshold then
        stopRest(playerObj, state, logger, "threshold")
        activeByPlayer[idx] = nil
        return
    end

    if settings.get("QoLforSacriel_RestSleep_InterruptOnMoveInput") == true then
        if playerObj:isPlayerMoving() or playerObj:pressedMovement(false) then
            stopRest(playerObj, state, logger, "movement")
            activeByPlayer[idx] = nil
            return
        end
    end

    if settings.get("QoLforSacriel_RestSleep_InterruptOnPanic") == true then
        local panicThreshold = tonumber(settings.get("QoLforSacriel_RestSleep_PanicInterruptLevel")) or 50
        panicThreshold = math.max(0, math.min(100, panicThreshold))
        local panicValue = getPanicValue(playerObj)
        if panicValue >= panicThreshold then
            stopRest(playerObj, state, logger, "panic")
            activeByPlayer[idx] = nil
            return
        end
    end

    local painLevel = playerObj:getMoodles():getMoodleLevel(MoodleType.Pain)
    if painLevel >= PAIN_INTERRUPT_LEVEL then
        stopRest(playerObj, state, logger, "pain")
        activeByPlayer[idx] = nil
        return
    end

    if shouldInterruptOnThreat(playerObj) then
        stopRest(playerObj, state, logger, "threat")
        activeByPlayer[idx] = nil
        return
    end

    local isResting = playerObj.isResting and playerObj:isResting()
    if not playerObj:isSitOnGround() and not playerObj:isSittingOnFurniture() and not isResting then
        stopRest(playerObj, state, logger, "finished")
        activeByPlayer[idx] = nil
    end
end

function RestUntilSleepy.init(settings, logger)
    if installed then
        logger.debug("RestSleep.RestUntilSleepy already installed")
        return
    end

    Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldobjects, test)
        local ok, err = pcall(function()
            onFillWorldObjectContextMenu(playerIndex, context, worldobjects, test, settings, logger)
        end)
        if not ok then
            logger.error("RestUntilSleepy context error: " .. tostring(err))
        end
    end)

    Events.OnPlayerUpdate.Add(function(playerObj)
        local ok, err = pcall(function()
            onPlayerUpdate(playerObj, settings, logger)
        end)
        if not ok then
            logger.error("RestUntilSleepy update error: " .. tostring(err))
        end
    end)

    installed = true
    logger.info("RestSleep.RestUntilSleepy installed")
end

return RestUntilSleepy
