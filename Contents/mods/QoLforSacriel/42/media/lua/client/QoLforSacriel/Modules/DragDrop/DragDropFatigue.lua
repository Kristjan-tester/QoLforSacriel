local DragDropFatigue = {}

local patched = false
local corpseDragByPlayer = {}
local POLL_SECONDS = 0.4

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function isGrabCorpseActionActive(playerObj)
    if not playerObj or not ISTimedActionQueue or not ISTimedActionQueue.getTimedActionQueue then
        return false
    end

    local queue = ISTimedActionQueue.getTimedActionQueue(playerObj)
    if not queue or not queue.queue or not queue.queue[1] then
        return false
    end

    local action = queue.queue[1]
    return action and action.Type == "ISGrabCorpseAction"
end

local function applyCorpseDragEnduranceCompensation(playerObj, settings)
    if not playerObj then
        return
    end

    local playerIndex = playerObj:getPlayerNum() or 0
    if settings.isEnabled("QoLforSacriel_EnableDragDrop") ~= true then
        corpseDragByPlayer[playerIndex] = nil
        return
    end

    local isDragging = playerObj:isDraggingCorpse()
    local isGrabAction = isGrabCorpseActionActive(playerObj)

    if not isDragging and not isGrabAction then
        if playerObj then
            corpseDragByPlayer[playerIndex] = nil
        end
        return
    end

    local state = corpseDragByPlayer[playerIndex]
    local now = getTimestamp()
    local gameTime = getGameTime()
    local worldHours = gameTime and gameTime:getWorldAgeHours() or 0
    local stats = playerObj:getStats()

    if not stats then
        return
    end

    if not state then
        state = {
            startTs = now,
            lastTs = now,
            lastPollHours = worldHours,
            lastEndurance = stats:get(CharacterStat.ENDURANCE),
        }
        corpseDragByPlayer[playerIndex] = state
    end

    local startMult = tonumber(settings.get("QoLforSacriel_DragDrop_FatigueStartMultiplier")) or 0.35
    local maxMult = tonumber(settings.get("QoLforSacriel_DragDrop_FatigueMaxMultiplier")) or 1.0
    local rampSeconds = tonumber(settings.get("QoLforSacriel_DragDrop_RampSeconds")) or 90

    startMult = clamp(startMult, 0.0, 3.0)
    maxMult = clamp(maxMult, 0.0, 3.0)
    rampSeconds = math.max(1, rampSeconds)

    local elapsed = math.max(0, now - state.startTs)
    local progress = clamp(elapsed / rampSeconds, 0.0, 1.0)
    local currentMult = startMult + ((maxMult - startMult) * progress)
    local compensationShare = clamp(1.0 - currentMult, 0.0, 1.0)

    local deltaSeconds = math.max(0, (worldHours - (state.lastPollHours or worldHours)) * 3600)
    if deltaSeconds < POLL_SECONDS then
        return
    end

    state.lastPollHours = worldHours
    state.lastTs = now

    if deltaSeconds <= 0 or compensationShare <= 0 then
        state.lastEndurance = stats:get(CharacterStat.ENDURANCE)
        return
    end

    local currentEndurance = stats:get(CharacterStat.ENDURANCE)
    local previousEndurance = state.lastEndurance or currentEndurance

    if isDragging and currentEndurance < previousEndurance then
        -- Polling model: restore a share of the measured endurance loss this interval.
        local enduranceLoss = previousEndurance - currentEndurance
        local restoreAmount = enduranceLoss * compensationShare
        if restoreAmount > 0 then
            stats:add(CharacterStat.ENDURANCE, restoreAmount)
            currentEndurance = currentEndurance + restoreAmount
        end
    end

    state.lastEndurance = currentEndurance
end

function DragDropFatigue.init(settings, logger)
    if patched then
        logger.debug("DragDrop.Fatigue already patched")
        return
    end

    Events.OnPlayerUpdate.Add(function(playerObj)
        local ok, err = pcall(function()
            applyCorpseDragEnduranceCompensation(playerObj, settings)
        end)
        if not ok then
            logger.error("DragDrop.Fatigue corpse-drag update error: " .. tostring(err))
        end
    end)

    patched = true
    logger.info("DragDrop.Fatigue corpse-drag endurance patch active (key: GrabCorpse)")
end

return DragDropFatigue
