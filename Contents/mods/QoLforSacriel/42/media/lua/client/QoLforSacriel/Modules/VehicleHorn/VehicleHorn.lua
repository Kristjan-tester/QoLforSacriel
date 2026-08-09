require "TimedActions/ISBaseTimedAction"

local VehicleHorn = {}
local ExteriorHornAction = ISBaseTimedAction:derive("QoLforSacriel_ExteriorHornAction")

local installed = false
local activeHornVehicles = {}
local originalFillPartMenu = nil
local runtimeSettings = nil

local function isEnabled()
    return runtimeSettings
        and runtimeSettings.isEnabled("QoLforSacriel_EnableUIFixes") == true
        and runtimeSettings.isEnabled("QoLforSacriel_UIFixes_EnableExteriorVehicleHorn") == true
end

local function getDriverWindowPart(vehicle)
    if not vehicle or not vehicle.getPassengerDoor then
        return nil
    end

    local driverDoor = vehicle:getPassengerDoor(0)
    if not driverDoor or not VehicleUtils or not VehicleUtils.getChildWindow then
        return nil
    end

    return VehicleUtils.getChildWindow(driverDoor), driverDoor
end

local function isUsingDriverDoor(playerObj, vehicle, driverDoor)
    if not playerObj or not vehicle or not driverDoor or not vehicle.getUseablePart then
        return false
    end

    local usablePart = vehicle:getUseablePart(playerObj)
    if not usablePart then
        return false
    end
    if usablePart == driverDoor then
        return true
    end
    if usablePart.getEnclosingDoor then
        return usablePart:getEnclosingDoor() == driverDoor
    end

    return false
end

local function resolveExteriorHornTarget(playerObj, vehicle)
    if not playerObj or playerObj:isDead() or playerObj:getVehicle() then
        return nil
    end
    if not vehicle or not vehicle.hasHorn or not vehicle:hasHorn() then
        return nil
    end
    if not vehicle.getBatteryCharge or vehicle:getBatteryCharge() <= 0 then
        return nil
    end
    if playerObj:DistToProper(vehicle) >= 4 then
        return nil
    end

    local windowPart, driverDoor = getDriverWindowPart(vehicle)
    if not windowPart or not isUsingDriverDoor(playerObj, vehicle, driverDoor) then
        return nil
    end

    local window = windowPart:getWindow()
    local door = driverDoor:getDoor()
    local isDoorOpen = door and door:isOpen()
    if not isDoorOpen and (not window or (not window:isOpen() and not window:isDestroyed())) then
        return nil
    end

    return vehicle
end

function ExteriorHornAction:isValid()
    return self.character and not self.character:isDead() and self.vehicle ~= nil
end

function ExteriorHornAction:update()
    if getTimestampMs() - self.startedAt > 1500 then
        ISBaseTimedAction.forceComplete(self)
    end
end

function ExteriorHornAction:start()
    self.startedAt = getTimestampMs()
    self.vehicle:onHornStart()
end

function ExteriorHornAction:stop()
    self.vehicle:onHornStop()
    ISBaseTimedAction.stop(self)
end

function ExteriorHornAction:perform()
    self.vehicle:onHornStop()
    ISBaseTimedAction.perform(self)
end

function ExteriorHornAction:new(character, vehicle)
    local action = ISBaseTimedAction.new(self, character)
    action.character = character
    action.vehicle = vehicle
    action.maxTime = -1
    action.startedAt = getTimestampMs()
    return action
end

local function queueExteriorHorn(playerObj, vehicle)
    if not isEnabled() then
        return
    end

    local target = resolveExteriorHornTarget(playerObj, vehicle)
    if target then
        ISTimedActionQueue.add(ExteriorHornAction:new(playerObj, target))
    end
end

local function resolveNearbyVehicle(playerObj)
    if not ISVehicleMenu or not ISVehicleMenu.getVehicleToInteractWith then
        return nil
    end
    return ISVehicleMenu.getVehicleToInteractWith(playerObj)
end

local function onKeyStartPressed(key)
    if not isEnabled() then
        return
    end
    if not getCore():isKey("VehicleHorn", key) then
        return
    end

    local playerObj = getSpecificPlayer(0)
    if not playerObj or playerObj:getVehicle() then
        return
    end

    local vehicle = resolveExteriorHornTarget(playerObj, resolveNearbyVehicle(playerObj))
    if vehicle then
        activeHornVehicles[playerObj:getPlayerNum()] = vehicle
        vehicle:onHornStart()
    end
end

local function onKeyPressed(key)
    if not getCore():isKey("VehicleHorn", key) then
        return
    end

    local playerObj = getSpecificPlayer(0)
    if not playerObj then
        return
    end

    local vehicle = activeHornVehicles[playerObj:getPlayerNum()]
    if vehicle then
        vehicle:onHornStop()
        activeHornVehicles[playerObj:getPlayerNum()] = nil
    end
end

local function addExteriorHornRadialSlice(playerIndex, slice, vehicle)
    if not isEnabled() or not slice then
        return
    end

    local playerObj = getSpecificPlayer(playerIndex)
    local target = resolveExteriorHornTarget(playerObj, vehicle)
    if target then
        slice:addSlice(
            getText("ContextMenu_VehicleHorn"),
            getTexture("media/ui/vehicles/vehicle_horn.png"),
            queueExteriorHorn,
            playerObj,
            target
        )
    end
end

local function installRadialHook()
    if not ISVehicleMenu or not ISVehicleMenu.FillPartMenu or originalFillPartMenu then
        return
    end

    originalFillPartMenu = ISVehicleMenu.FillPartMenu
    ISVehicleMenu.FillPartMenu = function(playerIndex, context, slice, vehicle)
        local result = originalFillPartMenu(playerIndex, context, slice, vehicle)
        addExteriorHornRadialSlice(playerIndex, slice, vehicle)
        return result
    end
end

function VehicleHorn.init(settings, logger)
    if installed then
        if logger and logger.debug then
            logger.debug("VehicleHorn already installed")
        end
        return
    end

    runtimeSettings = settings
    installRadialHook()
    Events.OnKeyStartPressed.Add(onKeyStartPressed)
    Events.OnKeyPressed.Add(onKeyPressed)

    installed = true
    if logger and logger.info then
        logger.info("VehicleHorn installed")
    end
end

return VehicleHorn