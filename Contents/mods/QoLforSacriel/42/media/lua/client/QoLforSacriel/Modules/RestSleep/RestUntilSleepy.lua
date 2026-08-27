-- ff-assisted
local RestUntilSleepy = {}

local installed = false
local activeByPlayer = {}
local PAIN_INTERRUPT_LEVEL = 1
local REST_SPEED_MULTIPLIER = 20
local NORMAL_SPEED_MULTIPLIER = 1
local REST_SPEED_SETTLE_SECONDS = 0.35
local RECENT_SLEEP_COOLDOWN_HOURS = 1
local NEARBY_BED_RADIUS = 3

local function applyGameSpeed(multiplier)
    local targetMultiplier = tonumber(multiplier) or NORMAL_SPEED_MULTIPLIER
    if targetMultiplier < 1 then
        targetMultiplier = 1
    end

    local targetMode = 1
    if targetMultiplier >= 40 then
        targetMode = 4
    elseif targetMultiplier >= 20 then
        targetMode = 3
    elseif targetMultiplier >= 5 then
        targetMode = 2
    end

    local controls = nil
    if UIManager then
        if UIManager.getSpeedControls then
            local okControls, speedControls = pcall(function()
                return UIManager.getSpeedControls()
            end)
            if okControls then
                controls = speedControls
            end
        end
        if not controls and UIManager.speedControls then
            controls = UIManager.speedControls
        end
    end

    if controls and controls.SetCurrentGameSpeed then
        pcall(function()
            controls:SetCurrentGameSpeed(targetMode)
        end)
    end

    local gameTime = getGameTime and getGameTime()
    if gameTime and gameTime.setMultiplier then
        pcall(function()
            gameTime:setMultiplier(targetMultiplier)
        end)
    elseif setGameSpeed then
        pcall(function()
            setGameSpeed(targetMultiplier)
        end)
    end
end

local function getSafeMoodleLevel(playerObj, moodleType, fallback)
    if not playerObj or not moodleType then
        return fallback or 0
    end

    local moodles = playerObj:getMoodles()
    if not moodles then
        return fallback or 0
    end

    local ok, level = pcall(function()
        return moodles:getMoodleLevel(moodleType)
    end)

    if not ok then
        return fallback or 0
    end

    local numeric = tonumber(level)
    if not numeric then
        return fallback or 0
    end

    return numeric
end

local function getLabel()
    local translated = getTextOrNull("UI_QoLforSacriel_RestUntilSleepy")
    if translated and translated ~= "" then
        return translated
    end
    return "Rest Until Sleepy"
end

local function getTextSafe(key, fallback)
    local translated = getTextOrNull(key)
    return translated and translated ~= "" and translated or fallback
end

local function getSleepyThreshold(settings)
    local threshold = tonumber(settings.get("QoLforSacriel_RestSleep_SleepyThreshold")) or 0.3
    return math.max(0.0, math.min(1.0, threshold))
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

    for _, option in ipairs(menu.options) do
        local actionFn = getActionFunction(option)
        if actionFn == ISWorldObjectContextMenu.onRest then
            return option
        end
    end

    return nil
end

local function hasRelevantActionOption(menu)
    if not menu or not menu.options then
        return false
    end

    for _, option in ipairs(menu.options) do
        local actionFn = getActionFunction(option)
        if actionFn == ISWorldObjectContextMenu.onRest or actionFn == ISWorldObjectContextMenu.onSleep then
            return true
        end
    end

    return false
end

local function isCurrentlyResting(playerObj)
    if not playerObj then
        return false
    end

    local isResting = playerObj.isResting and playerObj:isResting()
    return playerObj:isSitOnGround() or playerObj:isSittingOnFurniture() or isResting
end

local function hasTimedActionInProgress(playerObj)
    if not playerObj or not ISTimedActionQueue or not ISTimedActionQueue.getTimedActionQueue then
        return false
    end

    local queue = ISTimedActionQueue.getTimedActionQueue(playerObj)
    return queue and queue.queue and queue.queue[1] ~= nil
end

local function beginRestUntilSleepy(playerObj, settings, forceStartedRest)
    local idx = playerObj:getPlayerNum() or 0
    local threshold = getSleepyThreshold(settings)
    local startedRest = forceStartedRest == true or isCurrentlyResting(playerObj)
    local now = getTimestamp()

    activeByPlayer[idx] = {
        threshold = threshold,
        debugEnabled = settings.get("QoLforSacriel_DebugLogs") == true,
        startFatigue = playerObj:getStats():get(CharacterStat.FATIGUE),
        startTs = now,
        startedRest = startedRest,
        speedBoostApplied = false,
        restDetectedTs = startedRest and now or nil,
        requireRestSettle = forceStartedRest ~= true,
    }
end

local function stopRest(playerObj, state, logger, reason)
    if not playerObj then
        return
    end

    playerObj:StopAllActionQueue()
    if playerObj:isSitOnGround() or playerObj:isSittingOnFurniture() then
        playerObj:setVariable("forceGetUp", true)
    end

    applyGameSpeed(NORMAL_SPEED_MULTIPLIER)

    if state and state.debugEnabled then
        local currentFatigue = playerObj:getStats():get(CharacterStat.FATIGUE)
        logger.debug("RestUntilSleepy stop: " .. tostring(reason) .. " | fatigue " .. tostring(state.startFatigue) .. " -> " .. tostring(currentFatigue))
    end
end

local function onSelect(playerObj, actionOption, settings, logger)
    if not shouldOffer(playerObj) then
        return
    end

    if actionOption == nil then
        -- Sleep-only submenus can occur while already resting; arm directly.
        beginRestUntilSleepy(playerObj, settings, true)
        return
    end

    if isCurrentlyResting(playerObj) then
        beginRestUntilSleepy(playerObj, settings)
        return
    end

    local actionFn = getActionFunction(actionOption)
    if actionFn ~= ISWorldObjectContextMenu.onRest or not invokeOption(actionOption) then
        logger.warn("RestUntilSleepy could not run mapped rest action")
        return
    end

    beginRestUntilSleepy(playerObj, settings)
end

local function hasSleepThreat(playerObj)
    local stats = playerObj and playerObj:getStats()
    if not stats then
        return true
    end

    return (stats.getNumVisibleZombies and stats:getNumVisibleZombies() > 0)
        or (stats.getNumChasingZombies and stats:getNumChasingZombies() > 0)
        or (stats.getNumVeryCloseZombies and stats:getNumVeryCloseZombies() > 0)
end

local function canOfferNearbyBedSleep(playerObj, settings)
    if not shouldOffer(playerObj) or hasTimedActionInProgress(playerObj) or hasSleepThreat(playerObj) then
        return false
    end

    local stats = playerObj:getStats()
    if not stats or stats:get(CharacterStat.FATIGUE) < getSleepyThreshold(settings) then
        return false
    end

    local tabletEffect = playerObj.getSleepingTabletEffect and playerObj:getSleepingTabletEffect() or 0
    if tabletEffect >= 2000 then
        return true
    end

    if getSafeMoodleLevel(playerObj, MoodleType.PAIN, 0) >= 2 and stats:get(CharacterStat.FATIGUE) <= 0.85 then
        return false
    end

    return getSafeMoodleLevel(playerObj, MoodleType.PANIC, 0) < 1
end

local function getBedKey(bed)
    if not bed or not bed.getSquare then
        return nil
    end

    local ok, square = pcall(bed.getSquare, bed)
    if not ok or not square then
        return nil
    end

    local minX = square:getX()
    local minY = square:getY()
    local z = square:getZ()
    if bed.hasSpriteGrid and bed.getSpriteGridObjectsIncludingSelf then
        local objects = ArrayList.new()
        local gridOk = pcall(bed.getSpriteGridObjectsIncludingSelf, bed, objects)
        if gridOk then
            for index = 0, objects:size() - 1 do
                local gridObject = objects:get(index)
                local gridSquare = gridObject and gridObject:getSquare() or nil
                if gridSquare then
                    minX = math.min(minX, gridSquare:getX())
                    minY = math.min(minY, gridSquare:getY())
                end
            end
        end
    end

    return tostring(minX) .. ":" .. tostring(minY) .. ":" .. tostring(z)
end

local function getBedLabel(playerObj, candidate)
    local quality = candidate.quality or "averageBed"
    local pillow = string.find(quality, "Pillow", 1, true) ~= nil
    local baseQuality = string.gsub(quality, "Pillow", "")
    local qualityKey = "UI_QoLforSacriel_SleepNearestBed_Quality_" .. baseQuality
    local qualityLabel = getTextSafe(qualityKey, baseQuality)
    local pillowLabel = pillow
        and getTextSafe("UI_QoLforSacriel_SleepNearestBed_PillowYes", "Pillow: yes")
        or getTextSafe("UI_QoLforSacriel_SleepNearestBed_PillowNo", "Pillow: no")
    local distanceLabel = getTextSafe("UI_QoLforSacriel_SleepNearestBed_Distance", "tiles")
    return qualityLabel
        .. " | " .. pillowLabel
        .. " | " .. string.format("%.1f %s", math.sqrt(candidate.distanceSquared), distanceLabel)
end

local function isEligibleBedQuality(quality)
    if type(quality) ~= "string" then
        return false
    end

    local baseQuality = string.gsub(quality, "Pillow", "")
    return baseQuality == "averageBed"
        or baseQuality == "goodBed"
end

local function findNearbyBeds(playerObj)
    local playerSquare = playerObj:getSquare()
    local cell = playerSquare and playerSquare:getCell() or nil
    if not cell then
        return {}
    end

    local playerX = playerSquare:getX()
    local playerY = playerSquare:getY()
    local z = playerSquare:getZ()
    local candidates = {}
    local seen = {}
    local order = 0

    for y = playerY - NEARBY_BED_RADIUS, playerY + NEARBY_BED_RADIUS do
        for x = playerX - NEARBY_BED_RADIUS, playerX + NEARBY_BED_RADIUS do
            local square = cell:getGridSquare(x, y, z)
            local bed = square and square:getBed() or nil
            local key = getBedKey(bed)
            if key and not seen[key] then
                seen[key] = true
                local qualityOk, quality = pcall(ISWorldObjectContextMenu.getBedQuality, playerObj, bed)
                local bedQuality = qualityOk and tostring(quality) or nil
                local distanceSquared = (x - playerX) * (x - playerX) + (y - playerY) * (y - playerY)
                if distanceSquared <= NEARBY_BED_RADIUS * NEARBY_BED_RADIUS
                and isEligibleBedQuality(bedQuality)
                then
                    order = order + 1
                    table.insert(candidates, {
                        bed = bed,
                        quality = bedQuality,
                        distanceSquared = distanceSquared,
                        x = x,
                        y = y,
                        order = order,
                    })
                end
            end
        end
    end

    table.sort(candidates, function(left, right)
        if left.distanceSquared ~= right.distanceSquared then
            return left.distanceSquared < right.distanceSquared
        end
        if left.y ~= right.y then
            return left.y < right.y
        end
        if left.x ~= right.x then
            return left.x < right.x
        end
        return left.order < right.order
    end)
    return candidates
end

local function selectNearbyBedSleep(playerObj, bed, logger)
    if not playerObj or not bed or not bed:getSquare() then
        if logger and logger.debug then
            logger.debug("RestUntilSleepy nearby bed unavailable at selection")
        end
        return
    end

    local playerIndex = playerObj:getPlayerNum() or 0
    local restState = activeByPlayer[playerIndex]
    activeByPlayer[playerIndex] = nil
    if restState and restState.speedBoostApplied then
        applyGameSpeed(NORMAL_SPEED_MULTIPLIER)
    end

    ISWorldObjectContextMenu.onSleep(bed, playerObj:getPlayerNum())
end

local function addNearbyBedSleepOption(playerIndex, context, settings, logger)
    local playerObj = getSpecificPlayer(playerIndex)
    if not canOfferNearbyBedSleep(playerObj, settings) then
        return
    end

    local beds = findNearbyBeds(playerObj)
    if #beds == 0 then
        return
    end

    local rootLabel = getTextSafe("UI_QoLforSacriel_SleepNearestBed", "Sleep in nearest bed")
    if #beds == 1 then
        local root = context:addOption(rootLabel .. " | " .. getBedLabel(playerObj, beds[1]))
        root.onSelect = function()
            selectNearbyBedSleep(playerObj, beds[1].bed, logger)
        end
        return
    end

    local root = context:addOption(rootLabel)
    local subMenu = context:getNew(context)
    context:addSubMenu(root, subMenu)
    for _, candidate in ipairs(beds) do
        subMenu:addOption(getBedLabel(playerObj, candidate), playerObj, function(selectedPlayer, selectedBed)
            selectNearbyBedSleep(selectedPlayer, selectedBed, logger)
        end, candidate.bed)
    end
end

local function onFillWorldObjectContextMenu(playerIndex, context, worldobjects, test, settings, logger)
    if settings.isEnabled("QoLforSacriel_EnableRestSleep") ~= true then
        return
    end

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
            local canShowWhenResting = isCurrentlyResting(playerObj) and hasRelevantActionOption(subMenu)
            if (actionOption or canShowWhenResting) and not subMenu:getOptionFromName(getLabel()) then
                subMenu:addOption(getLabel(), playerObj, function(p, mappedOption)
                    onSelect(p, mappedOption, settings, logger)
                end, actionOption)
            end
        end
    end

    addNearbyBedSleepOption(playerIndex, context, settings, logger)
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

    local moodleLevel = getSafeMoodleLevel(playerObj, MoodleType.PANIC, 0)
    return math.max(0, moodleLevel) * 25
end

local function isSleepNeeded()
    if not isClient or not isClient() then
        return true
    end

    local serverOptions = getServerOptions and getServerOptions() or nil
    return serverOptions and serverOptions:getBoolean("SleepNeeded") == true
end

local function hasRecentlySlept(playerObj)
    if not isSleepNeeded() or not playerObj
        or not playerObj.getHoursSurvived or not playerObj.getLastHourSleeped then
        return false
    end

    local ok, hoursSinceSleep = pcall(function()
        return playerObj:getHoursSurvived() - playerObj:getLastHourSleeped()
    end)
    return ok and hoursSinceSleep >= 0 and hoursSinceSleep <= RECENT_SLEEP_COOLDOWN_HOURS
end

local function onPlayerUpdate(playerObj, settings, logger)
    if not playerObj then
        return
    end

    local idx = playerObj:getPlayerNum() or 0
    if settings.isEnabled("QoLforSacriel_EnableRestSleep") ~= true then
        activeByPlayer[idx] = nil
        return
    end

    local state = activeByPlayer[idx]
    if not state then
        return
    end

    local fatigue = playerObj:getStats():get(CharacterStat.FATIGUE)

    if not state.startedRest then
        local isResting = playerObj.isResting and playerObj:isResting()
        if playerObj:isSitOnGround() or playerObj:isSittingOnFurniture() or isResting then
            state.startedRest = true
            state.restDetectedTs = getTimestamp()
        elseif getTimestamp() - (state.startTs or 0) > 15 then
            activeByPlayer[idx] = nil
            return
        end
    end

    if not state.startedRest then
        return
    end

    if state.speedBoostApplied ~= true then
        local canApplySpeedBoost = true
        if state.requireRestSettle == true then
            if hasTimedActionInProgress(playerObj) then
                canApplySpeedBoost = false
            else
                local restDetectedTs = state.restDetectedTs or getTimestamp()
                state.restDetectedTs = restDetectedTs
                if getTimestamp() - restDetectedTs < REST_SPEED_SETTLE_SECONDS then
                    canApplySpeedBoost = false
                end
            end
        end

        if canApplySpeedBoost then
            applyGameSpeed(REST_SPEED_MULTIPLIER)
            state.speedBoostApplied = true
        end
    end

    if fatigue >= state.threshold and not hasRecentlySlept(playerObj) then
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

    local painLevel = getSafeMoodleLevel(playerObj, MoodleType.Pain, 0)
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
