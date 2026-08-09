require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISStopAlarmClockAction"

local NearbyDeviceOff = {}
local DeviceOffAction = ISBaseTimedAction:derive("QoLforSacriel_NearbyDeviceOffAction")

local installed = false
local DEFAULT_RANGE = 3
local MAX_RANGE = 3
local MOD_OPTIONS_ID = "QoLforSacriel.Modules"
local HOTKEY_OPTION_ID = "nearbyDeviceOffHotkey"

local function getHotkeyOption()
    if not PZAPI or not PZAPI.ModOptions or not PZAPI.ModOptions.getOptions then
        return nil
    end

    local options = PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)
    if not options or not options.getOption then
        return nil
    end

    return options:getOption(HOTKEY_OPTION_ID)
end

local function getHotkeyBindingName()
    local option = getHotkeyOption()
    if option and option.name and option.name ~= "" then
        return option.name
    end

    return getTextOrNull("UI_QoLforSacriel_Modules_NearbyDeviceOffHotkey") or "Turn Off Nearby Device Key"
end

local function getExpectedModifierState()
    local option = getHotkeyOption()
    local source = option
    if option and type(option.element) == "table" then
        source = option.element
    end

    local ctrl = true
    local shift = false
    local alt = false

    if source then
        if source.ctrl ~= nil then
            ctrl = source.ctrl == true
        end
        if source.shift ~= nil then
            shift = source.shift == true
        end
        if source.alt ~= nil then
            alt = source.alt == true
        end
    end

    return ctrl, shift, alt
end

local function isModifierDown(functionName)
    local fn = _G[functionName]
    if type(fn) ~= "function" then
        return false
    end

    local ok, state = pcall(fn)
    return ok and state == true
end

local function matchesHotkey(key)
    local core = getCore and getCore()
    if not core or not core.isKey then
        return false
    end

    local ok, matched = pcall(core.isKey, core, getHotkeyBindingName(), key)
    if not ok or matched ~= true then
        return false
    end

    local expectedCtrl, expectedShift, expectedAlt = getExpectedModifierState()
    return isModifierDown("isCtrlKeyDown") == expectedCtrl
        and isModifierDown("isShiftKeyDown") == expectedShift
        and isModifierDown("isAltKeyDown") == expectedAlt
end

local function getSearchRange(settings)
    local range = math.floor(tonumber(settings.get("QoLforSacriel_NearbyDeviceOff_Range")) or DEFAULT_RANGE)
    if range < 1 then
        return 1
    end
    if range > MAX_RANGE then
        return MAX_RANGE
    end
    return range
end

local function getDeviceData(target)
    if not target or not target.getDeviceData then
        return nil
    end

    local ok, deviceData = pcall(target.getDeviceData, target)
    return ok and deviceData or nil
end

local function isDeviceTurnedOn(target)
    local deviceData = getDeviceData(target)
    if not deviceData or not deviceData.getIsTurnedOn then
        return nil
    end

    local ok, isTurnedOn = pcall(deviceData.getIsTurnedOn, deviceData)
    if not ok or isTurnedOn ~= true then
        return nil
    end

    return deviceData
end

local function isRingingAlarm(target)
    if not target or not target.isRinging then
        return false
    end

    local ok, isRinging = pcall(target.isRinging, target)
    return ok and isRinging == true
end

local function addCandidate(best, candidate)
    if not best then
        return candidate
    end
    if candidate.priority ~= best.priority then
        return candidate.priority < best.priority and candidate or best
    end
    if candidate.distance ~= best.distance then
        return candidate.distance < best.distance and candidate or best
    end
    if candidate.x ~= best.x then
        return candidate.x < best.x and candidate or best
    end
    if candidate.y ~= best.y then
        return candidate.y < best.y and candidate or best
    end
    return candidate.order < best.order and candidate or best
end

local function candidateForTarget(target, actionTarget, alarmPriority, devicePriority, requiresWalk, square, distance, order)
    if isRingingAlarm(target) then
        return {
            kind = "alarm",
            target = actionTarget,
            priority = alarmPriority,
            requiresWalk = requiresWalk,
            square = square,
            distance = distance,
            x = square and square:getX() or 0,
            y = square and square:getY() or 0,
            order = order,
        }
    end

    local deviceData = isDeviceTurnedOn(target)
    if deviceData then
        return {
            kind = "device",
            target = target,
            deviceData = deviceData,
            priority = devicePriority,
            requiresWalk = requiresWalk,
            square = square,
            distance = distance,
            x = square and square:getX() or 0,
            y = square and square:getY() or 0,
            order = order,
        }
    end

    return nil
end

local function scanInventoryContainer(container, best, order)
    if not container or not container.getItems then
        return best, order
    end

    local ok, items = pcall(container.getItems, container)
    if not ok or not items then
        return best, order
    end

    for index = 0, items:size() - 1 do
        local item = items:get(index)
        order = order + 1
        local candidate = candidateForTarget(item, item, 1, 2, false, nil, 0, order)
        if candidate then
            best = addCandidate(best, candidate)
        end

        if item and item.getItemContainer then
            local containerOk, itemContainer = pcall(item.getItemContainer, item)
            if containerOk and itemContainer then
                best, order = scanInventoryContainer(itemContainer, best, order)
            end
        end
    end

    return best, order
end

local function findInventoryCandidate(playerObj)
    if not playerObj or not playerObj.getInventory then
        return nil
    end

    local inventory = playerObj:getInventory()
    if not inventory then
        return nil
    end

    return scanInventoryContainer(inventory, nil, 0)
end

local function getWorldTarget(object)
    if object and instanceof(object, "IsoWorldInventoryObject") then
        local ok, item = pcall(object.getItem, object)
        return ok and item or nil, object
    end
    return object, object
end

local function findWorldCandidate(playerObj, settings)
    local playerSquare = playerObj and playerObj:getSquare()
    if not playerSquare then
        return nil
    end

    local range = getSearchRange(settings)
    local playerX = playerSquare:getX()
    local playerY = playerSquare:getY()
    local z = playerSquare:getZ()
    local best = nil
    local order = 0

    for y = playerY - range, playerY + range do
        for x = playerX - range, playerX + range do
            local square = getCell():getGridSquare(x, y, z)
            if square then
                local objects = square:getObjects()
                if objects then
                    local distance = math.max(math.abs(x - playerX), math.abs(y - playerY))
                    for index = 0, objects:size() - 1 do
                        local object = objects:get(index)
                        local target, actionTarget = getWorldTarget(object)
                        order = order + 1
                        if target then
                            local candidate = candidateForTarget(target, actionTarget, 3, 4, true, square, distance, order)
                            if candidate then
                                best = addCandidate(best, candidate)
                            end
                        end
                    end
                end
            end
        end
    end

    return best
end

function DeviceOffAction:isValid()
    local deviceData = getDeviceData(self.target)
    return self.character
        and not self.character:isDead()
        and deviceData ~= nil
        and deviceData == self.deviceData
        and isDeviceTurnedOn(self.target) ~= nil
end

local function turnOffDevice(target, expectedDeviceData)
    local deviceData = getDeviceData(target)
    if not deviceData or deviceData ~= expectedDeviceData or not deviceData.setIsTurnedOn or not isDeviceTurnedOn(target) then
        return false
    end

    local ok = pcall(deviceData.setIsTurnedOn, deviceData, false)
    return ok
end

function DeviceOffAction:turnOff()
    if not self:isValid() then
        return false
    end

    return turnOffDevice(self.target, self.deviceData)
end

function DeviceOffAction:complete()
    return self:turnOff()
end

function DeviceOffAction:stop()
    ISBaseTimedAction.stop(self)
end

function DeviceOffAction:perform()
    self:turnOff()
    ISBaseTimedAction.perform(self)
end

function DeviceOffAction:new(character, target, deviceData, requiresWalk)
    local action = ISBaseTimedAction.new(self, character)
    action.target = target
    action.deviceData = deviceData
    action.stopOnWalk = requiresWalk == true
    action.stopOnRun = true
    action.maxTime = character:isTimedActionInstant() and 1 or 20
    return action
end

local function silenceAlarm(target)
    local alarm = target
    if alarm and instanceof(alarm, "IsoWorldInventoryObject") then
        local itemOk, item = pcall(alarm.getItem, alarm)
        if not itemOk then
            return false
        end
        alarm = item
    end
    if not alarm or not alarm.stopRinging or not alarm.syncStopRinging then
        return false
    end

    local stopped = pcall(alarm.stopRinging, alarm)
    if not stopped then
        return false
    end
    local synced = pcall(alarm.syncStopRinging, alarm)
    return synced
end

local function isAlreadyAdjacent(playerObj, targetSquare)
    local playerSquare = playerObj and playerObj:getSquare()
    if not playerSquare or not targetSquare or playerSquare:getZ() ~= targetSquare:getZ() then
        return false
    end

    local dx = math.abs(playerSquare:getX() - targetSquare:getX())
    local dy = math.abs(playerSquare:getY() - targetSquare:getY())
    return math.max(dx, dy) <= 1
end

local function queueCandidate(playerObj, candidate, logger)
    local mustWalk = candidate.requiresWalk and not isAlreadyAdjacent(playerObj, candidate.square)
    if mustWalk then
        if not luautils or not luautils.walkAdj then
            return false
        end
        local walked, queuedWalk = pcall(luautils.walkAdj, playerObj, candidate.square)
        if not walked or queuedWalk ~= true then
            return false
        end
    end

    if candidate.kind == "alarm" and not mustWalk then
        local silenced = silenceAlarm(candidate.target)
        if logger and logger.debug then
            logger.debug("NearbyDeviceOff: alarm silence=" .. tostring(silenced) .. " | adjacent=" .. tostring(isAlreadyAdjacent(playerObj, candidate.square)))
        end
        return silenced
    end

    if candidate.kind == "device" and not mustWalk then
        local turnedOff = turnOffDevice(candidate.target, candidate.deviceData)
        if logger and logger.debug then
            logger.debug("NearbyDeviceOff: device shutdown=" .. tostring(turnedOff) .. " | adjacent=" .. tostring(isAlreadyAdjacent(playerObj, candidate.square)))
        end
        return turnedOff
    end

    if not ISTimedActionQueue or not ISTimedActionQueue.add then
        return false
    end

    if candidate.kind == "alarm" then
        ISTimedActionQueue.add(ISStopAlarmClockAction:new(playerObj, candidate.target))
    else
        ISTimedActionQueue.add(DeviceOffAction:new(playerObj, candidate.target, candidate.deviceData, mustWalk))
    end

    if logger and logger.debug then
        logger.debug("NearbyDeviceOff: queued " .. candidate.kind .. " | walk=" .. tostring(mustWalk) .. " | adjacent=" .. tostring(isAlreadyAdjacent(playerObj, candidate.square)))
    end
    return true
end

local function onKeyStartPressed(key, settings, logger)
    if settings.isEnabled("QoLforSacriel_EnableNearbyDeviceOff") ~= true or not matchesHotkey(key) then
        return
    end

    local playerObj = getSpecificPlayer(0)
    if not playerObj or playerObj:isDead() then
        return
    end

    local candidate = findInventoryCandidate(playerObj)
    if not candidate then
        candidate = findWorldCandidate(playerObj, settings)
    end

    if not candidate then
        if logger and logger.debug then
            logger.debug("NearbyDeviceOff: no eligible device found")
        end
        return
    end

    queueCandidate(playerObj, candidate, logger)
end

function NearbyDeviceOff.init(settings, logger)
    if installed then
        return
    end

    Events.OnKeyStartPressed.Add(function(key)
        local ok, err = pcall(function()
            onKeyStartPressed(key, settings, logger)
        end)
        if not ok and logger and logger.error then
            logger.error("NearbyDeviceOff key error: " .. tostring(err))
        end
    end)

    installed = true
    if logger and logger.info then
        logger.info("NearbyDeviceOff installed")
    end
end

return NearbyDeviceOff