local VehicleEntryAssist = {}

local installed = false
local runtimeSettings = nil
local loggerRef = nil
local NEARBY_VEHICLE_DISTANCE_SQUARED = 16

local function logDebug(message)
    if runtimeSettings
        and runtimeSettings.get
        and runtimeSettings.get("QoLforSacriel_DebugLogs") == true
        and loggerRef
        and loggerRef.debug
    then
        loggerRef.debug("VehicleEntryAssist: " .. tostring(message))
    end
end

local function logError(message)
    if loggerRef and loggerRef.error then
        loggerRef.error("VehicleEntryAssist: " .. tostring(message))
    end
end

local function isEnabled()
    return runtimeSettings
        and runtimeSettings.isEnabled
        and runtimeSettings.isEnabled("QoLforSacriel_EnableVehicleEntryAssist") == true
end

local function isInteractKey(key)
    local core = getCore and getCore()
    if not core or not core.isKey then
        return false
    end

    local ok, matched = pcall(core.isKey, core, "Interact", key)
    if not ok then
        logError("Interact key lookup failed | " .. tostring(matched))
        return false
    end
    return matched == true
end

local function getEligiblePlayer()
    local playerObj = getSpecificPlayer and getSpecificPlayer(0)
    if not playerObj or playerObj:isDead() or playerObj:getVehicle() or playerObj:isBlockMovement() then
        return nil
    end
    return playerObj
end

local function safeCall(target, methodName)
    if not target or not target[methodName] then
        return nil
    end

    local ok, value = pcall(target[methodName], target)
    if not ok then
        return nil
    end
    return value
end

local function describeVehicle(vehicle, distanceSquared)
    local id = safeCall(vehicle, "getId")
    local script = safeCall(vehicle, "getScript")
    local scriptName = safeCall(script, "getName")
    return "id=" .. tostring(id)
        .. ", script=" .. tostring(scriptName)
        .. ", distanceSq=" .. string.format("%.2f", distanceSquared)
end

local function getNearbyVehicle(playerObj)
    local cell = getCell and getCell()
    local vehicles = cell and safeCall(cell, "getVehicles")
    if not vehicles then
        logDebug("loaded vehicle collection unavailable")
        return nil
    end

    local playerX = safeCall(playerObj, "getX")
    local playerY = safeCall(playerObj, "getY")
    local playerZ = safeCall(playerObj, "getZ")
    if type(playerX) ~= "number" or type(playerY) ~= "number" or type(playerZ) ~= "number" then
        logError("Player position lookup failed")
        return nil
    end

    local closestVehicle = nil
    local closestDistanceSquared = nil
    local iterator = safeCall(vehicles, "iterator")
    if not iterator or not iterator.hasNext or not iterator.next then
        logError("loaded vehicle collection cannot be iterated")
        return nil
    end

    while iterator:hasNext() do
        local vehicle = iterator:next()
        local script = safeCall(vehicle, "getScript")
        local vehicleX = safeCall(vehicle, "getX")
        local vehicleY = safeCall(vehicle, "getY")
        local vehicleZ = safeCall(vehicle, "getZ")
        if script
            and type(vehicleX) == "number"
            and type(vehicleY) == "number"
            and type(vehicleZ) == "number"
            and math.floor(playerZ) == math.floor(vehicleZ)
        then
            local dx = vehicleX - playerX
            local dy = vehicleY - playerY
            local distanceSquared = dx * dx + dy * dy
            if distanceSquared < NEARBY_VEHICLE_DISTANCE_SQUARED
                and (not closestDistanceSquared or distanceSquared < closestDistanceSquared)
            then
                closestVehicle = vehicle
                closestDistanceSquared = distanceSquared
            end
        end
    end

    if not closestVehicle then
        logDebug("no nearby car detected within four tiles")
        return nil
    end

    logDebug("nearby car detected | " .. describeVehicle(closestVehicle, closestDistanceSquared))
    return closestVehicle
end

local function getInteractionPoint(vehicle, part)
    local okAreaId, areaId = pcall(function()
        return part:getArea()
    end)
    if not okAreaId or not areaId then
        return nil
    end

    local okScript, script = pcall(function()
        return vehicle:getScript()
    end)
    if not okScript or not script then
        return nil
    end

    local okArea, area = pcall(function()
        return script:getAreaById(areaId)
    end)
    if not okArea or not area then
        return nil
    end

    local okPoint, x, y = pcall(function()
        local areaX = area:getX()
        local areaY = area:getY()
        local extents = script:getExtents()
        local centerOfMass = script:getCenterOfMassOffset()
        local centerZ = centerOfMass:z()
        local extentZ = extents:z()
        local minimumY = centerZ - extentZ / 2
        local maximumY = centerZ + extentZ / 2
        local localX = 0
        local localZ = 0

        if areaY >= maximumY or areaY <= minimumY then
            localX = areaX
        else
            localZ = areaY
        end

        local worldPoint = Vector3f.new()
        vehicle:getWorldPos(localX, 0, localZ, worldPoint)
        return worldPoint:x(), worldPoint:y()
    end)
    if not okPoint or type(x) ~= "number" or type(y) ~= "number" then
        return nil
    end

    return x, y
end

local function resolveDirectionAssist(playerObj)
    if not playerObj.getUseableVehicle then
        logDebug("vanilla usable-vehicle method unavailable")
        return nil
    end

    local okUseableVehicle, useableVehicle = pcall(playerObj.getUseableVehicle, playerObj)
    if not okUseableVehicle then
        logError("Vanilla usable vehicle lookup failed | " .. tostring(useableVehicle))
        return nil
    end
    if useableVehicle then
        logDebug("already usable")
        return nil
    end

    local vehicle = getNearbyVehicle(playerObj)
    if not vehicle or not vehicle.getUseablePart then
        return nil
    end

    local okPart, part = pcall(vehicle.getUseablePart, vehicle, playerObj, false)
    if not okPart then
        logError("Direction-independent usable-part lookup failed | " .. tostring(part))
        return nil
    end
    if not part then
        logDebug("no direction-independent part")
        return nil
    end

    local x, y = getInteractionPoint(vehicle, part)
    if x and y then
        return vehicle, x, y
    end

    x = safeCall(vehicle, "getX")
    y = safeCall(vehicle, "getY")
    if type(x) ~= "number" or type(y) ~= "number" then
        logDebug("vehicle position unavailable for direction correction")
        return nil
    end

    logDebug("interaction point unavailable; using vehicle-center fallback")
    return vehicle, x, y
end

local function applyDirectionAssist(playerObj, vehicle, x, y)
    if not playerObj.faceLocation then
        logDebug("fractional facing method unavailable")
        return false
    end

    local okFace, faceResult = pcall(playerObj.faceLocation, playerObj, x - 0.5, y - 0.5)
    if not okFace then
        logError("Facing adjustment failed | " .. tostring(faceResult))
        return false
    end

    local okRecheck, usablePart = pcall(vehicle.getUseablePart, vehicle, playerObj)
    if not okRecheck then
        logError("Post-turn usable-part recheck failed | " .. tostring(usablePart))
        return false
    end
    if not usablePart then
        logDebug("post-turn recheck failed")
        return false
    end

    logDebug("direction corrected toward " .. tostring(x) .. "," .. tostring(y))
    return true
end

local function onKeyStartPressed(key)
    if not isEnabled() or not isInteractKey(key) then
        return
    end

    logDebug("Interact key detected")

    local playerObj = getEligiblePlayer()
    if not playerObj then
        logDebug("Interact ignored: player is unavailable, seated, dead, or movement-blocked")
        return
    end

    local vehicle, x, y = resolveDirectionAssist(playerObj)
    if vehicle then
        applyDirectionAssist(playerObj, vehicle, x, y)
    end
end

function VehicleEntryAssist.init(settings, logger)
    if installed then
        logDebug("already installed")
        return
    end

    runtimeSettings = settings
    loggerRef = logger

    Events.OnKeyStartPressed.Add(function(key)
        local ok, err = pcall(onKeyStartPressed, key)
        if not ok then
            logError("Interact key handler failed | " .. tostring(err))
        end
    end)

    installed = true
    if loggerRef and loggerRef.info then
        loggerRef.info("VehicleEntryAssist installed")
    end
end

return VehicleEntryAssist