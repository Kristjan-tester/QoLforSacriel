-- ff-assisted
require "Moveables/ISMoveablesAction"
require "TimedActions/ISDismantleAction"

local DismantleProgress = {}

local MODULE_SETTING = "QoLforSacriel_EnableDismantleProgress"
local PROGRESS_KEY = "QoLforSacriel.DismantleProgress"
local RECORD_VERSION = 1
local MOVEABLE_ROUTE = "moveable-scrap"
local THUMPABLE_ROUTE = "thumpable-dismantle"

local installed = false
local settingsRef = nil
local loggerRef = nil

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isEnabled()
    return settingsRef
        and settingsRef.isEnabled
        and settingsRef.isEnabled(MODULE_SETTING) == true
end

local function logDebug(message)
    if loggerRef and loggerRef.debug then
        loggerRef.debug("DismantleProgress " .. tostring(message))
    end
end

local function describeTarget(target)
    local square = target and target.getSquare and target:getSquare() or nil
    local sprite = target and target.getSprite and target:getSprite() or nil
    local objectName = target and target.getObjectName and target:getObjectName() or "unknown"
    local spriteName = sprite and sprite.getName and sprite:getName() or "none"
    if square then
        return "object=" .. tostring(objectName)
            .. " sprite=" .. tostring(spriteName)
            .. " square=" .. tostring(square:getX()) .. "," .. tostring(square:getY()) .. "," .. tostring(square:getZ())
    end
    return "object=" .. tostring(objectName) .. " sprite=" .. tostring(spriteName) .. " square=unknown"
end

local function getRecord(target)
    if not target or not target.getModData then
        return nil
    end
    local modData = target:getModData()
    return modData and modData[PROGRESS_KEY] or nil
end

local function transmitModData(target)
    if target and target.getSquare and target:getSquare() and target.transmitModData then
        target:transmitModData()
    end
end

local function clearRecord(target, route, reason)
    if not target or not target.getModData then
        return
    end

    local modData = target:getModData()
    if modData and modData[PROGRESS_KEY] ~= nil then
        modData[PROGRESS_KEY] = nil
        transmitModData(target)
        logDebug("cleared route=" .. tostring(route) .. " target=" .. describeTarget(target) .. " reason=" .. tostring(reason))
    end
end

local function getValidRecord(target, route)
    local record = getRecord(target)
    if record == nil then
        logDebug("resume skipped route=" .. tostring(route) .. " target=" .. describeTarget(target) .. " reason=no-record")
        return nil
    end

    local valid = type(record) == "table"
        and record.version == RECORD_VERSION
        and record.route == route
        and isFiniteNumber(record.progress)
        and record.progress > 0
        and record.progress < 1
        and isFiniteNumber(record.originalDuration)
        and record.originalDuration > 0

    if valid then
        logDebug("resume record found route=" .. tostring(route) .. " target=" .. describeTarget(target) .. " progress=" .. tostring(record.progress))
        return record
    end

    logDebug("resume skipped route=" .. tostring(route) .. " target=" .. describeTarget(target) .. " reason=invalid-record")
    clearRecord(target, route, "invalid-record")
    return nil
end

local function getWorldAgeHours()
    local gameTime = getGameTime and getGameTime() or nil
    if gameTime and gameTime.getWorldAgeHours then
        return gameTime:getWorldAgeHours()
    end
    return 0
end

local function savePartialProgress(action, target, route)
    if not target or not target.getModData then
        logDebug("interrupt skipped route=" .. tostring(route) .. " reason=no-mod-data-target")
        return
    end

    local progress = action:getJobDelta()
    if not isFiniteNumber(progress) or progress <= 0 then
        logDebug("interrupt skipped route=" .. tostring(route) .. " target=" .. describeTarget(target) .. " progress=" .. tostring(progress) .. " reason=no-progress")
        return
    end
    if progress >= 1 then
        logDebug("interrupt reached completion route=" .. tostring(route) .. " target=" .. describeTarget(target) .. " progress=" .. tostring(progress))
        clearRecord(target, route, "completed-progress")
        return
    end

    local duration = action.maxTime
    if not isFiniteNumber(duration) or duration <= 1 then
        logDebug("interrupt skipped route=" .. tostring(route) .. " target=" .. describeTarget(target) .. " duration=" .. tostring(duration) .. " reason=invalid-duration")
        return
    end

    target:getModData()[PROGRESS_KEY] = {
        version = RECORD_VERSION,
        route = route,
        progress = progress,
        originalDuration = duration,
        updatedAt = getWorldAgeHours(),
    }
    transmitModData(target)
    logDebug("interrupted and saved route=" .. tostring(route) .. " target=" .. describeTarget(target) .. " progress=" .. tostring(progress) .. " percent=" .. tostring(math.floor(progress * 100)) .. " duration=" .. tostring(duration))
end

local function restorePartialProgress(action, target, route)
    local record = getValidRecord(target, route)
    if not record then
        return
    end

    local duration = action.maxTime
    if not isFiniteNumber(duration) or duration <= 1 then
        logDebug("resume skipped route=" .. tostring(route) .. " target=" .. describeTarget(target) .. " duration=" .. tostring(duration) .. " reason=invalid-duration")
        clearRecord(target, route, "instant-action")
        return
    end

    local restoredTime = math.min(record.progress * duration, duration - 1)
    if restoredTime <= 0 then
        logDebug("resume skipped route=" .. tostring(route) .. " target=" .. describeTarget(target) .. " reason=invalid-restored-time")
        clearRecord(target, route, "invalid-restored-time")
        return
    end

    action:setCurrentTime(restoredTime)
    logDebug("resumed route=" .. tostring(route) .. " target=" .. describeTarget(target) .. " progress=" .. tostring(record.progress) .. " percent=" .. tostring(math.floor(record.progress * 100)) .. " duration=" .. tostring(duration) .. " time=" .. tostring(restoredTime))
end

local function getMoveableTarget(action)
    return action.mode == "scrap" and action.moveProps and action.moveProps.object or nil
end

local function wrapMoveableAction()
    if not ISMoveablesAction
        or type(ISMoveablesAction.start) ~= "function"
        or type(ISMoveablesAction.stop) ~= "function"
        or type(ISMoveablesAction.complete) ~= "function"
    then
        if loggerRef and loggerRef.error then
            loggerRef.error("DismantleProgress unavailable: ISMoveablesAction lifecycle methods are missing")
        end
        return
    end

    local originalStart = ISMoveablesAction.start
    local originalStop = ISMoveablesAction.stop
    local originalComplete = ISMoveablesAction.complete

    ISMoveablesAction.start = function(self)
        local result = originalStart(self)
        local target = getMoveableTarget(self)
        if isEnabled() and target then
            logDebug("dismantling detected route=" .. MOVEABLE_ROUTE .. " target=" .. describeTarget(target))
            restorePartialProgress(self, target, MOVEABLE_ROUTE)
        elseif self.mode == "scrap" then
            logDebug("dismantling skipped route=" .. MOVEABLE_ROUTE .. " reason=" .. (isEnabled() and "no-target" or "feature-disabled"))
        end
        return result
    end

    ISMoveablesAction.stop = function(self)
        local target = getMoveableTarget(self)
        if isEnabled() and target then
            savePartialProgress(self, target, MOVEABLE_ROUTE)
        end
        return originalStop(self)
    end

    ISMoveablesAction.complete = function(self)
        local target = getMoveableTarget(self)
        if isEnabled() and target then
            logDebug("dismantling completed route=" .. MOVEABLE_ROUTE .. " target=" .. describeTarget(target))
            clearRecord(target, MOVEABLE_ROUTE, "completed")
        end
        return originalComplete(self)
    end

    logDebug("installed route=" .. MOVEABLE_ROUTE)
end

local function wrapThumpableAction()
    if not ISDismantleAction
        or type(ISDismantleAction.start) ~= "function"
        or type(ISDismantleAction.stop) ~= "function"
        or type(ISDismantleAction.complete) ~= "function"
    then
        if loggerRef and loggerRef.error then
            loggerRef.error("DismantleProgress unavailable: ISDismantleAction lifecycle methods are missing")
        end
        return
    end

    local originalStart = ISDismantleAction.start
    local originalStop = ISDismantleAction.stop
    local originalComplete = ISDismantleAction.complete

    ISDismantleAction.start = function(self)
        local result = originalStart(self)
        if isEnabled() and self.thumpable then
            logDebug("dismantling detected route=" .. THUMPABLE_ROUTE .. " target=" .. describeTarget(self.thumpable))
            restorePartialProgress(self, self.thumpable, THUMPABLE_ROUTE)
        else
            logDebug("dismantling skipped route=" .. THUMPABLE_ROUTE .. " reason=" .. (isEnabled() and "no-target" or "feature-disabled"))
        end
        return result
    end

    ISDismantleAction.stop = function(self)
        if isEnabled() and self.thumpable then
            savePartialProgress(self, self.thumpable, THUMPABLE_ROUTE)
        end
        return originalStop(self)
    end

    ISDismantleAction.complete = function(self)
        if isEnabled() and self.thumpable then
            logDebug("dismantling completed route=" .. THUMPABLE_ROUTE .. " target=" .. describeTarget(self.thumpable))
            clearRecord(self.thumpable, THUMPABLE_ROUTE, "completed")
        end
        return originalComplete(self)
    end

    logDebug("installed route=" .. THUMPABLE_ROUTE)
end

function DismantleProgress.init(settings, logger)
    if installed then
        return
    end

    settingsRef = settings
    loggerRef = logger
    if loggerRef and loggerRef.info then
        loggerRef.info("DismantleProgress initialized; enable Debug Logs in Mod Options to trace detection, interruption, and resumption")
    end
    wrapMoveableAction()
    wrapThumpableAction()
    installed = true
end

return DismantleProgress