local HeldBagClimb = {}

local installed = false
local retryHookInstalled = false
local retryTickCounter = 0
local RETRY_TICK_INTERVAL = 30
local MAX_WALL_RELOCATION_ATTEMPTS = 10

local settingsRef = nil
local loggerRef = nil
local originalWindowPerform = nil
local originalFencePerform = nil
local wallStateByPlayer = {}

local function logDebug(message)
    if settingsRef and settingsRef.isEnabled and settingsRef.isEnabled("QoLforSacriel_DebugLogs") == true and loggerRef and loggerRef.debug then
        loggerRef.debug("HeldBagClimb " .. tostring(message))
    end
end

local function getDirectionDelta(direction)
    if direction == IsoDirections.N then
        return 0, -1
    end
    if direction == IsoDirections.S then
        return 0, 1
    end
    if direction == IsoDirections.W then
        return -1, 0
    end
    if direction == IsoDirections.E then
        return 1, 0
    end
    return nil, nil
end

local function getAdjacentSquare(square, direction)
    if not square or not direction or not getSquare then
        return nil
    end

    local deltaX, deltaY = getDirectionDelta(direction)
    if not deltaX then
        return nil
    end

    return getSquare(square:getX() + deltaX, square:getY() + deltaY, square:getZ())
end

local function isValidDestination(square, sourceZ)
    if not square or square:getZ() ~= sourceZ then
        return false
    end

    local ok, isSolidFloor = pcall(function()
        return square:isSolidFloor()
    end)
    return ok and isSolidFloor == true
end

local function isValidWallDestination(square, sourceZ)
    return square and square:getZ() == sourceZ
end

local function isHeldContainer(playerObj, item)
    if not playerObj or not item then
        return false
    end

    local isContainerOk, isContainer = pcall(function()
        return item:IsInventoryContainer()
    end)
    if not isContainerOk or isContainer ~= true then
        return false
    end

    local containsOk, contains = pcall(function()
        return playerObj:getInventory():contains(item)
    end)
    return containsOk and contains == true
end

local function collectHeldBags(playerObj)
    local bags = {}
    local primary = playerObj:getPrimaryHandItem()
    local secondary = playerObj:getSecondaryHandItem()

    if isHeldContainer(playerObj, primary) then
        table.insert(bags, primary)
    end
    if isHeldContainer(playerObj, secondary) and secondary ~= primary then
        table.insert(bags, secondary)
    end

    return bags
end

local function clearHandReferences(playerObj, item)
    if playerObj:getPrimaryHandItem() == item then
        playerObj:setPrimaryHandItem(nil)
    end
    if playerObj:getSecondaryHandItem() == item then
        playerObj:setSecondaryHandItem(nil)
    end
end

local function getItemId(item)
    if not item or not item.getID then
        return nil
    end
    return item:getID()
end

local function isContainerItem(item)
    if not item then
        return false
    end
    return item:IsInventoryContainer() == true
end

local function snapshotHeldBagIds(playerObj)
    local ids = {}
    local primary = playerObj:getPrimaryHandItem()
    local secondary = playerObj:getSecondaryHandItem()
    local heldItems = { primary }
    if secondary ~= primary then
        table.insert(heldItems, secondary)
    end

    for index = 1, #heldItems do
        local item = heldItems[index]
        local itemId = isContainerItem(item) and getItemId(item) or nil
        if itemId then
            ids[itemId] = true
        end
    end
    return ids
end

local function isClimbingOverWall(playerObj)
    return ClimbOverWallState
        and ClimbOverWallState.instance
        and playerObj:getCurrentState() == ClimbOverWallState.instance()
end

local function removeWorldItemObject(worldItemObject)
    if not worldItemObject or not worldItemObject.removeFromWorld or not worldItemObject.removeFromSquare then
        return false
    end

    worldItemObject:removeFromWorld()
    worldItemObject:removeFromSquare()
    return true
end

local function relocateDroppedWallBags(state)
    local sourceSquare = state.sourceSquare
    local destinationSquare = state.destinationSquare
    if not sourceSquare or not isValidWallDestination(destinationSquare, sourceSquare:getZ()) then
        return false, "invalid destination"
    end

    local worldObjects = sourceSquare:getWorldObjects()
    if not worldObjects then
        return false, "origin world objects unavailable"
    end

    local movedCount = 0
    for index = worldObjects:size() - 1, 0, -1 do
        local worldItemObject = worldObjects:get(index)
        if worldItemObject and instanceof(worldItemObject, "IsoWorldInventoryObject") then
            local item = worldItemObject:getItem()
            local itemId = getItemId(item)
            if itemId and state.pendingIds[itemId] then
                local offset = 0.25 + (movedCount * 0.5)
                if removeWorldItemObject(worldItemObject) then
                    destinationSquare:AddWorldInventoryItem(item, offset, offset, 0.0)
                    state.pendingIds[itemId] = nil
                    movedCount = movedCount + 1
                end
            end
        end
    end

    if movedCount > 0 and ISInventoryPage then
        ISInventoryPage.renderDirty = true
    end

    return movedCount > 0, movedCount
end

local function hasPendingIds(ids)
    for _, _ in pairs(ids) do
        return true
    end
    return false
end

local function countPendingIds(ids)
    local count = 0
    for _, _ in pairs(ids) do
        count = count + 1
    end
    return count
end

local function updateDirectWallTransfer(playerObj)
    if not playerObj or not playerObj:isLocalPlayer() then
        return
    end

    local playerIndex = playerObj:getPlayerNum() or 0
    local state = wallStateByPlayer[playerIndex] or {}
    wallStateByPlayer[playerIndex] = state

    if settingsRef and settingsRef.isEnabled and settingsRef.isEnabled("QoLforSacriel_EnableHeldBagClimb") ~= true then
        state.active = false
        state.lastHeldIds = snapshotHeldBagIds(playerObj)
        return
    end

    if not isClimbingOverWall(playerObj) then
        state.active = false
        state.lastHeldIds = snapshotHeldBagIds(playerObj)
        return
    end

    if not state.active then
        local sourceSquare = playerObj:getCurrentSquare()
        state.active = true
        state.attempts = 0
        state.sourceSquare = sourceSquare
        state.destinationSquare = nil
        state.pendingIds = state.lastHeldIds or {}
        logDebug("direct wall entered; captured bag count=" .. tostring(countPendingIds(state.pendingIds)))
    end

    if not hasPendingIds(state.pendingIds) or state.attempts >= MAX_WALL_RELOCATION_ATTEMPTS then
        return
    end

    if not state.destinationSquare then
        state.destinationSquare = getAdjacentSquare(state.sourceSquare, playerObj:getDir())
        if not state.destinationSquare then
            return
        end
        logDebug("direct wall resolved destination from cardinal direction " .. tostring(playerObj:getDir()))
    end

    state.attempts = state.attempts + 1
    local moved, detail = relocateDroppedWallBags(state)
    if moved then
        logDebug("direct wall relocated bags=" .. tostring(detail)
            .. " to " .. tostring(state.destinationSquare:getX()) .. ","
            .. tostring(state.destinationSquare:getY()) .. ","
            .. tostring(state.destinationSquare:getZ()))
    elseif state.attempts == MAX_WALL_RELOCATION_ATTEMPTS then
        logDebug("direct wall relocation skipped after retries: " .. tostring(detail)
            .. "; remaining=" .. tostring(countPendingIds(state.pendingIds)))
    end
end

local function transferHeldBags(playerObj, destinationSquare, actionName)
    if not playerObj or not destinationSquare then
        return false
    end

    local bags = collectHeldBags(playerObj)
    if #bags == 0 then
        return false
    end

    local inventory = playerObj:getInventory()
    if not inventory or not inventory.Remove then
        return false
    end

    for index = 1, #bags do
        local bag = bags[index]
        if not isHeldContainer(playerObj, bag) then
            logDebug(actionName .. " transfer skipped: bag is no longer held")
            return false
        end
    end

    for index = 1, #bags do
        local bag = bags[index]
        local offset = 0.25 + ((index - 1) * 0.5)
        clearHandReferences(playerObj, bag)
        inventory:Remove(bag)
        destinationSquare:AddWorldInventoryItem(bag, offset, offset, 0.0)
        if bag.getContainer and bag:getContainer() then
            bag:getContainer():setDrawDirty(true)
        end
    end

    if ISInventoryPage then
        ISInventoryPage.renderDirty = true
    end

    logDebug(actionName .. " transferred " .. tostring(#bags) .. " held bag(s) to "
        .. tostring(destinationSquare:getX()) .. "," .. tostring(destinationSquare:getY()) .. "," .. tostring(destinationSquare:getZ()))
    return true
end

local function transferForWindowAction(action)
    local playerObj = action and action.character
    local sourceSquare = action and action.item and action.item.getSquare and action.item:getSquare() or nil
    local direction = action and action.getFacingDirection and action:getFacingDirection() or nil
    local destinationSquare = getAdjacentSquare(sourceSquare, direction)

    if not sourceSquare or not isValidDestination(destinationSquare, sourceSquare:getZ()) then
        logDebug("window transfer skipped: invalid opposite square")
        return false
    end

    return transferHeldBags(playerObj, destinationSquare, "window")
end

local function transferForFenceAction(action)
    local playerObj = action and action.character
    local sourceSquare = playerObj and playerObj:getCurrentSquare() or nil
    local direction = action and action.getFacingDirection and action:getFacingDirection() or nil
    local destinationSquare = getAdjacentSquare(sourceSquare, direction)

    if not sourceSquare or not isValidDestination(destinationSquare, sourceSquare:getZ()) then
        logDebug("fence transfer skipped: invalid opposite square")
        return false
    end

    return transferHeldBags(playerObj, destinationSquare, "fence")
end

local function isEnabled()
    return settingsRef and settingsRef.isEnabled and settingsRef.isEnabled("QoLforSacriel_EnableHeldBagClimb") == true
end

local function patchWindowAction()
    if originalWindowPerform then
        return true
    end

    pcall(require, "TimedActions/ISClimbThroughWindow")
    if not ISClimbThroughWindow or type(ISClimbThroughWindow.perform) ~= "function" then
        return false
    end

    originalWindowPerform = ISClimbThroughWindow.perform
    ISClimbThroughWindow.perform = function(self)
        if isEnabled() then
            local ok, err = pcall(transferForWindowAction, self)
            if not ok and loggerRef and loggerRef.error then
                loggerRef.error("HeldBagClimb window transfer error: " .. tostring(err))
            end
        end
        return originalWindowPerform(self)
    end

    if loggerRef and loggerRef.info then
        loggerRef.info("HeldBagClimb patched ISClimbThroughWindow")
    end
    return true
end

local function patchFenceAction()
    if originalFencePerform then
        return true
    end

    pcall(require, "TimedActions/ISClimbOverFence")
    if not ISClimbOverFence or type(ISClimbOverFence.perform) ~= "function" then
        return false
    end

    originalFencePerform = ISClimbOverFence.perform
    ISClimbOverFence.perform = function(self)
        if isEnabled() then
            local ok, err = pcall(transferForFenceAction, self)
            if not ok and loggerRef and loggerRef.error then
                loggerRef.error("HeldBagClimb fence transfer error: " .. tostring(err))
            end
        end
        return originalFencePerform(self)
    end

    if loggerRef and loggerRef.info then
        loggerRef.info("HeldBagClimb patched ISClimbOverFence")
    end
    return true
end

local function tryPatchAll()
    local windowPatched = patchWindowAction()
    local fencePatched = patchFenceAction()
    return windowPatched and fencePatched
end

local function onRetryTick()
    retryTickCounter = retryTickCounter + 1
    if retryTickCounter % RETRY_TICK_INTERVAL ~= 0 then
        return
    end

    if tryPatchAll() and retryHookInstalled and Events and Events.OnTick then
        Events.OnTick.Remove(onRetryTick)
        retryHookInstalled = false
        logDebug("delayed action patching completed")
    end
end

function HeldBagClimb.init(settings, logger)
    settingsRef = settings
    loggerRef = logger

    if installed then
        if logger and logger.debug then
            logger.debug("HeldBagClimb already installed")
        end
        return
    end

    local patchedNow = tryPatchAll()
    if not patchedNow and Events and Events.OnTick then
        Events.OnTick.Add(onRetryTick)
        retryHookInstalled = true
        if logger and logger.warn then
            logger.warn("HeldBagClimb waiting for climb action classes")
        end
    end

    installed = true
    Events.OnPlayerUpdate.Add(updateDirectWallTransfer)
    if logger and logger.info then
        logger.info("HeldBagClimb installed; actions patched=" .. tostring(patchedNow))
    end
end

return HeldBagClimb