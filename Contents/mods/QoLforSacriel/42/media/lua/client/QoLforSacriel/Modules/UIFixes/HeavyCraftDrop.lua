local HeavyCraftDrop = {}

local installed = false
local settingsRef = nil
local loggerRef = nil

local trackedByPlayer = {}
local CANDIDATE_TTL_SECONDS = 12.0
local DROP_COOLDOWN_SECONDS = 2.0
local DAMAGE_TRIGGER_WINDOW_SECONDS = 8.0

local function logDebug(message)
    if not loggerRef or not loggerRef.debug then
        return
    end
    if not settingsRef or not settingsRef.get or settingsRef.get("QoLforSacriel_DebugLogs") ~= true then
        return
    end
    loggerRef.debug("UIFixes.HeavyCraftDrop: " .. tostring(message))
end

local function isUiFixesEnabled()
    return settingsRef
        and settingsRef.isEnabled
        and settingsRef.isEnabled("QoLforSacriel_EnableUIFixes") == true
end

local function isHeavyCraftDropEnabled()
    if not isUiFixesEnabled() then
        return false
    end
    return settingsRef and settingsRef.get and settingsRef.get("QoLforSacriel_UIFixes_EnableHeavyCraftDrop") == true
end

local function getWorldAgeHours()
    local gameTime = getGameTime and getGameTime()
    if not gameTime or not gameTime.getWorldAgeHours then
        return nil
    end
    return gameTime:getWorldAgeHours()
end

local function isLocalPlayer(playerObj)
    if not playerObj then
        return false
    end

    if playerObj.isLocalPlayer then
        local ok, result = pcall(function()
            return playerObj:isLocalPlayer()
        end)
        if ok then
            return result == true
        end
    end

    if playerObj.getPlayerNum and getSpecificPlayer then
        local ok, playerNum = pcall(function()
            return playerObj:getPlayerNum()
        end)
        if ok and playerNum and playerNum >= 0 then
            return getSpecificPlayer(playerNum) == playerObj
        end
    end

    return false
end

local function getPlayerState(playerIndex)
    local state = trackedByPlayer[playerIndex]
    if not state then
        state = {
            craftingActive = false,
            snapshotById = nil,
            candidates = {},
            lastDropAtHours = nil,
        }
        trackedByPlayer[playerIndex] = state
    end
    return state
end

local function isCraftActionActive(playerObj)
    if not playerObj or not ISTimedActionQueue or not ISTimedActionQueue.getTimedActionQueue then
        return false
    end

    local queue = ISTimedActionQueue.getTimedActionQueue(playerObj)
    if not queue then
        return false
    end

    local action = queue.current
    if not action and queue.queue then
        action = queue.queue[1] or queue.queue[0]
    end
    if not action then
        return false
    end

    local actionType = tostring(action.Type or "")
    return actionType:lower():find("craft", 1, true) ~= nil
end

local function getAllInventoryItemsById(playerObj)
    local byId = {}
    local list = {}

    if not playerObj or not playerObj.getInventory then
        return byId, list
    end

    local inventory = playerObj:getInventory()
    if not inventory or not inventory.getAllEvalRecurse then
        return byId, list
    end

    local allItems = inventory:getAllEvalRecurse(function(_item)
        return true
    end, ArrayList.new())

    if not allItems or not allItems.size then
        return byId, list
    end

    for i = 0, allItems:size() - 1 do
        local item = allItems:get(i)
        if item and item.getID then
            local id = item:getID()
            byId[id] = item
            list[#list + 1] = item
        end
    end

    return byId, list
end

local function pruneExpiredCandidates(state, nowHours)
    if not state or not state.candidates then
        return
    end

    local kept = {}
    for i = 1, #state.candidates do
        local candidate = state.candidates[i]
        local ageSeconds = (nowHours - (candidate.addedAtHours or nowHours)) * 3600
        if ageSeconds <= CANDIDATE_TTL_SECONDS then
            kept[#kept + 1] = candidate
        end
    end

    state.candidates = kept
end

local function addCandidatesFromSnapshotDelta(state, snapshotById, currentById, nowHours)
    if not state or not snapshotById or not currentById then
        return
    end

    for id, item in pairs(currentById) do
        if not snapshotById[id] then
            local alreadyTracked = false
            for i = 1, #state.candidates do
                if state.candidates[i].id == id then
                    alreadyTracked = true
                    break
                end
            end

            if not alreadyTracked then
                local weight = 0
                if item and item.getActualWeight then
                    local okWeight, w = pcall(function()
                        return item:getActualWeight()
                    end)
                    if okWeight and tonumber(w) then
                        weight = tonumber(w)
                    end
                end

                state.candidates[#state.candidates + 1] = {
                    id = id,
                    weight = weight,
                    addedAtHours = nowHours,
                }

                state.lastCraftOutputAtHours = nowHours
            end
        end
    end
end

local function isCoolingDown(state, nowHours)
    if not state or not nowHours or not state.lastDropAtHours then
        return false
    end
    return ((nowHours - state.lastDropAtHours) * 3600) < DROP_COOLDOWN_SECONDS
end

local function hasRecentCraftOutput(state, nowHours)
    if not state or not nowHours or not state.lastCraftOutputAtHours then
        return false
    end

    local ageSeconds = (nowHours - state.lastCraftOutputAtHours) * 3600
    return ageSeconds <= DAMAGE_TRIGGER_WINDOW_SECONDS
end

local function canDropItem(playerObj, item)
    if not playerObj or not item then
        return false
    end

    if item.isFavorite and item:isFavorite() then
        return false
    end

    if playerObj.isHandItem and playerObj:isHandItem(item) then
        return false
    end

    return item.getContainer and item:getContainer() ~= nil
end

local function pickDropCandidate(playerObj, state)
    if not playerObj or not state then
        return nil, nil
    end

    local currentById = getAllInventoryItemsById(playerObj)
    local bestIndex = nil
    local bestItem = nil
    local bestWeight = -1

    for i = 1, #state.candidates do
        local candidate = state.candidates[i]
        local item = currentById[candidate.id]
        if item and canDropItem(playerObj, item) then
            local weight = tonumber(candidate.weight) or 0
            if weight > bestWeight then
                bestWeight = weight
                bestIndex = i
                bestItem = item
            end
        end
    end

    return bestIndex, bestItem
end

local function removeCandidateAt(state, index)
    if not state or not index then
        return
    end
    table.remove(state.candidates, index)
end

local function onPlayerUpdate(playerObj)
    if not playerObj or playerObj:isDead() then
        return
    end

    local playerIndex = playerObj:getPlayerNum() or 0
    local state = getPlayerState(playerIndex)
    local nowHours = getWorldAgeHours()
    if not nowHours then
        return
    end

    pruneExpiredCandidates(state, nowHours)

    if not isHeavyCraftDropEnabled() then
        state.craftingActive = false
        state.snapshotById = nil
        state.candidates = {}
        return
    end

    local craftActive = isCraftActionActive(playerObj)
    local currentById = getAllInventoryItemsById(playerObj)

    if craftActive and not state.craftingActive then
        state.craftingActive = true
        state.snapshotById = currentById
        return
    end

    if craftActive and state.craftingActive and state.snapshotById then
        addCandidatesFromSnapshotDelta(state, state.snapshotById, currentById, nowHours)
        state.snapshotById = currentById
        return
    end

    if (not craftActive) and state.craftingActive then
        addCandidatesFromSnapshotDelta(state, state.snapshotById, currentById, nowHours)
        state.snapshotById = nil
        state.craftingActive = false
        logDebug("registered crafted output candidates=" .. tostring(#state.candidates))
    end
end

local function onPlayerGetDamage(playerObj, damageType, damageAmount)
    if not isHeavyCraftDropEnabled() then
        return
    end

    if not playerObj or damageType ~= "HEAVYLOAD" then
        return
    end

    local amount = tonumber(damageAmount) or 0
    if amount <= 0 then
        return
    end

    if not isLocalPlayer(playerObj) then
        return
    end

    -- Avoid mutating inventory while a craft action is still running.
    if isCraftActionActive(playerObj) then
        logDebug("suppressed drop: craft action still active")
        return
    end

    local nowHours = getWorldAgeHours()
    if not nowHours then
        return
    end

    local playerIndex = playerObj:getPlayerNum() or 0
    local state = getPlayerState(playerIndex)
    pruneExpiredCandidates(state, nowHours)

    if isCoolingDown(state, nowHours) then
        return
    end

    if not hasRecentCraftOutput(state, nowHours) then
        return
    end

    if not ISInventoryPaneContextMenu or type(ISInventoryPaneContextMenu.dropItem) ~= "function" then
        return
    end

    local candidateIndex, item = pickDropCandidate(playerObj, state)
    if not item then
        return
    end

    ISInventoryPaneContextMenu.dropItem(item, playerIndex)
    removeCandidateAt(state, candidateIndex)
    state.lastDropAtHours = nowHours

    if item.getName then
        logDebug("auto-dropped crafted heavy item: " .. tostring(item:getName()))
    else
        logDebug("auto-dropped crafted heavy item id=" .. tostring(item:getID()))
    end
end

function HeavyCraftDrop.init(settings, logger)
    if installed then
        if logger and logger.debug then
            logger.debug("UIFixes.HeavyCraftDrop already installed")
        end
        return
    end

    settingsRef = settings
    loggerRef = logger

    Events.OnPlayerUpdate.Add(function(playerObj)
        local ok, err = pcall(function()
            onPlayerUpdate(playerObj)
        end)
        if not ok and loggerRef and loggerRef.error then
            loggerRef.error("UIFixes.HeavyCraftDrop update error: " .. tostring(err))
        end
    end)

    Events.OnPlayerGetDamage.Add(function(playerObj, damageType, damageAmount)
        local ok, err = pcall(function()
            onPlayerGetDamage(playerObj, damageType, damageAmount)
        end)
        if not ok and loggerRef and loggerRef.error then
            loggerRef.error("UIFixes.HeavyCraftDrop damage error: " .. tostring(err))
        end
    end)

    installed = true
    if logger and logger.info then
        logger.info("UIFixes.HeavyCraftDrop installed")
    end
end

return HeavyCraftDrop
