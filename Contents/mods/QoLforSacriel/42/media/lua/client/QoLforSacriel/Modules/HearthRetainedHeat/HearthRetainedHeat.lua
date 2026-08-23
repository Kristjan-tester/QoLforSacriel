-- ff-assisted
local HearthRetainedHeat = {}

local installed = false
local trackedHearths = {}

local SOURCE_RADIUS = 8
local SCAN_RADIUS = 8
local PENDING_REMOVAL_MAX_HOURS = 7 * 24
local TRAIL_START_HEAT = 0.25
local TRAIL_START_TEMPERATURE = 35
local TRAIL_END_TEMPERATURE = 18
local MAX_SUPPORTED_OUTDOOR_TEMPERATURE = 50
local BARREL_OVEN_SPRITES = {
    crafted_05_4 = true,
    crafted_05_5 = true,
    crafted_05_6 = true,
    crafted_05_7 = true,
}

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function finiteNumber(value, fallback)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return fallback
    end
    return number
end

local function settingInRange(settings, name, minimum, maximum, fallback)
    local value = finiteNumber(settings.get(name), fallback)
    if value < minimum or value > maximum then
        return fallback
    end
    return value
end

local function settingRatio(settings)
    local value = finiteNumber(settings.get("QoLforSacriel_HearthRetainedHeat_OutsideTempBaseRatioPercent"), 30)
    if value < 0 or value >= 40 then
        return 0.30
    end
    return value / 100
end

local function getWorldHours()
    local gameTime = getGameTime and getGameTime() or nil
    if not gameTime or not gameTime.getWorldAgeHours then
        return nil
    end
    return finiteNumber(gameTime:getWorldAgeHours(), nil)
end

local function getOutdoorTemperature()
    local climateManager = getClimateManager and getClimateManager() or nil
    if not climateManager or not climateManager.getTemperature then
        return 0
    end
    return clamp(finiteNumber(climateManager:getTemperature(), 0), -MAX_SUPPORTED_OUTDOOR_TEMPERATURE, MAX_SUPPORTED_OUTDOOR_TEMPERATURE)
end

local function timingScales(settings)
    local ratio = settingRatio(settings)
    local temperature = getOutdoorTemperature()
    return 1 - ratio * temperature / 20, 1 + ratio * temperature / 20
end

local function getLocalPlayer()
    if type(getSpecificPlayer) ~= "function" then
        return nil
    end
    return getSpecificPlayer(0)
end

local function isSupportedHearth(object)
    if type(instanceof) ~= "function"
        or object == nil
        or not instanceof(object, "IsoFireplace")
        or not object.getSquare
        or not object.getFuelAmount
        or not object.hasFuel
        or not object.isLit
    then
        return false
    end

    local container = object.getContainer and object:getContainer() or nil
    if container and container.getType and container:getType() == "campfire" then
        return false
    end

    local properties = object.getProperties and object:getProperties() or nil
    return not properties or properties:get("CustomName") ~= "Metal Drum"
end

local function isInLoadedWorld(hearth)
    local square = hearth and hearth.getSquare and hearth:getSquare() or nil
    if not square or not square.getChunk or not square:getChunk() then
        return false
    end

    local objects = square.getObjects and square:getObjects() or nil
    return objects and objects:contains(hearth) or false
end

local function hearthKey(hearth)
    local square = hearth and hearth.getSquare and hearth:getSquare() or nil
    if not square or not hearth.getObjectIndex then
        return nil
    end

    local objectIndex = hearth:getObjectIndex()
    if objectIndex == nil or objectIndex < 0 then
        return nil
    end

    return tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ()) .. ":" .. tostring(objectIndex)
end

local function hearthLocation(hearth)
    local square = hearth and hearth.getSquare and hearth:getSquare() or nil
    if not square or not hearth.getObjectIndex then
        return nil
    end

    local objectIndex = hearth:getObjectIndex()
    if objectIndex == nil or objectIndex < 0 then
        return nil
    end

    return square:getX(), square:getY(), square:getZ(), objectIndex
end

local function nativeRadius(hearth)
    local fuel = math.max(0, finiteNumber(hearth:getFuelAmount(), 0))
    return math.floor(1 + 7 * math.min(fuel, 60) / 60)
end

local function vanillaSourceName(hearth)
    local properties = hearth and hearth.getProperties and hearth:getProperties() or nil
    local customName = properties and properties:get("CustomName") or nil
    if customName and customName ~= "" then
        local name = tostring(customName)
        if string.lower(name) == "barreloven" then
            return "BarrelOven"
        end
        if string.lower(name) == "woodoven" then
            return "woodoven"
        end
        return name
    end

    local sprite = hearth and hearth.getSprite and hearth:getSprite() or nil
    local spriteName = sprite and sprite.getName and sprite:getName() or nil
    if spriteName and spriteName ~= "" then
        local name = tostring(spriteName)
        local lowerName = string.lower(name)
        if BARREL_OVEN_SPRITES[name] or string.find(lowerName, "barreloven", 1, true) then
            return "BarrelOven"
        end
        if string.find(lowerName, "woodoven", 1, true) then
            return "woodoven"
        end
    end

    local container = hearth and hearth.getContainer and hearth:getContainer() or nil
    local containerType = container and container.getType and container:getType() or nil
    if containerType and containerType ~= "" then
        local suffix = spriteName and " | sprite=" .. tostring(spriteName) or ""
        return tostring(containerType) .. suffix
    end

    return "IsoFireplace"
end

local function sourceTemperature(state, retentionHours)
    local trailConstant = -retentionHours / math.log(TRAIL_END_TEMPERATURE / TRAIL_START_TEMPERATURE)
    local rawTemperature = TRAIL_START_TEMPERATURE * math.exp(-state.trailElapsedHours / trailConstant)
    local retainedTemperature = clamp(rawTemperature, TRAIL_END_TEMPERATURE, TRAIL_START_TEMPERATURE)
    return math.floor(math.max(retainedTemperature, getOutdoorTemperature()) + 0.5)
end

local function trailStartTemperature()
    return math.floor(math.max(TRAIL_START_TEMPERATURE, getOutdoorTemperature()) + 0.5)
end

local function removeSource(state)
    if not state or not state.retainedSource then
        return
    end

    local cell = getCell and getCell() or nil
    if cell and cell.removeHeatSource then
        pcall(function()
            cell:removeHeatSource(state.retainedSource)
        end)
    end
    state.retainedSource = nil
end

local function clearState(key, state)
    removeSource(state)
    trackedHearths[key] = nil
end

local function ensureSource(state, hearth, temperature)
    local square = hearth:getSquare()
    if not square then
        return false
    end

    local cell = getCell and getCell() or nil
    if not cell then
        return false
    end

    if not state.retainedSource then
        if not IsoHeatSource or not IsoHeatSource.new or not cell.addHeatSource then
            return false
        end

        local ok, source = pcall(function()
            return IsoHeatSource.new(square:getX(), square:getY(), square:getZ(), SOURCE_RADIUS, temperature)
        end)
        if not ok or not source then
            return false
        end

        ok = pcall(function()
            cell:addHeatSource(source)
        end)
        if not ok then
            return false
        end

        state.retainedSource = source
        return true
    end

    if state.retainedSource:getRadius() ~= SOURCE_RADIUS then
        state.retainedSource:setRadius(SOURCE_RADIUS)
    end
    if state.retainedSource:getTemperature() ~= temperature then
        state.retainedSource:setTemperature(temperature)
    end
    return true
end

local function bindHearth(key, state, hearth, logger)
    local newKey = hearthKey(hearth)
    local x, y, z, objectIndex = hearthLocation(hearth)
    if not newKey or not x or trackedHearths[newKey] and trackedHearths[newKey] ~= state then
        return false
    end

    trackedHearths[key] = nil
    trackedHearths[newKey] = state
    state.hearth = hearth
    state.x = x
    state.y = y
    state.z = z
    state.objectIndex = objectIndex
    state.unloaded = false
    state.reloaded = true
    state.pendingRemoval = false
    state.pendingRemovalSinceWorldAgeHours = nil
    logger.debug(string.format(
        "Hearth reloaded: %s | vanillaSource=%s | retained trail recalculating",
        tostring(newKey), vanillaSourceName(hearth)
    ))
    return true
end

local function trackHearth(hearth, logger)
    if not isSupportedHearth(hearth) then
        return nil, nil
    end

    local key = hearthKey(hearth)
    if not key then
        return nil, nil
    end

    local state = trackedHearths[key]
    if not state then
        local x, y, z, objectIndex = hearthLocation(hearth)
        state = {
            hearth = hearth,
            x = x,
            y = y,
            z = z,
            objectIndex = objectIndex,
            unloaded = false,
            reloaded = false,
            pendingRemoval = false,
            pendingRemovalSinceWorldAgeHours = nil,
            wasLit = false,
            storedHeat = 0,
            normalizedBurnHours = 0,
            trailElapsedHours = 0,
            trailInitialCharge = 0,
            trailDurationHours = 0,
            retentionStarted = false,
            trailStarted = false,
            trailExpiredThisBurn = false,
            retainedSource = nil,
            lastUpdateWorldAgeHours = nil,
            lastLoggedTrailHour = -1,
        }
        trackedHearths[key] = state
        if hearth:isLit() and hearth:hasFuel() then
            logger.debug(string.format(
                "Hearth discovered: %s | vanillaSource=%s",
                tostring(key), vanillaSourceName(hearth)
            ))
        end
    elseif state.unloaded then
        bindHearth(key, state, hearth, logger)
    end
    return key, state
end

local function markPendingRemoval(key, state, logger)
    if state.pendingRemoval then
        return
    end

    state.pendingRemoval = true
    state.pendingRemovalSinceWorldAgeHours = getWorldHours()
    logger.debug(string.format(
        "Hearth pending removal: %s | exact object missing after chunk reload",
        tostring(key)
    ))
end

local function reconcileUnloadedHearths(logger)
    local cell = getCell and getCell() or nil
    if not cell or not cell.getGridSquare then
        return
    end

    for key, state in pairs(trackedHearths) do
        if state.unloaded then
            local square = cell:getGridSquare(state.x, state.y, state.z)
            local objects = square and square.getObjects and square:getObjects() or nil
            if objects then
                local matched = false
                for index = 0, objects:size() - 1 do
                    local hearth = objects:get(index)
                    if hearthKey(hearth) == key and isInLoadedWorld(hearth) then
                        bindHearth(key, state, hearth, logger)
                        matched = true
                        break
                    end
                end
                if not matched then
                    markPendingRemoval(key, state, logger)
                end
            end
        end
    end
end

local function reconcilePendingRemovalHearths(logger)
    local playerObject = getLocalPlayer()
    local playerSquare = playerObject and playerObject.getSquare and playerObject:getSquare() or nil
    local cell = getCell and getCell() or nil
    if not playerSquare or not cell or not cell.getGridSquare then
        return
    end

    local playerX = playerSquare:getX()
    local playerY = playerSquare:getY()
    local playerZ = playerSquare:getZ()
    for key, state in pairs(trackedHearths) do
        if state.pendingRemoval
            and state.z == playerZ
            and math.abs(state.x - playerX) <= SCAN_RADIUS
            and math.abs(state.y - playerY) <= SCAN_RADIUS
        then
            local square = cell:getGridSquare(state.x, state.y, state.z)
            local objects = square and square.getObjects and square:getObjects() or nil
            local candidate = nil
            if objects then
                for index = 0, objects:size() - 1 do
                    local hearth = objects:get(index)
                    if isSupportedHearth(hearth) and isInLoadedWorld(hearth) then
                        if candidate then
                            candidate = nil
                            break
                        end
                        candidate = hearth
                    end
                end
            end
            if candidate and bindHearth(key, state, candidate, logger) then
                logger.debug(string.format(
                    "Hearth pending removal cleared: %s | matched supported hearth on tile",
                    tostring(hearthKey(candidate))
                ))
            elseif not candidate then
                clearState(key, state)
                logger.debug(string.format(
                    "Hearth pending trail removed: %s | no supported hearth on tile",
                    tostring(key)
                ))
            end
        end
    end
end

local function expirePendingRemovalHearths(logger)
    local nowHours = getWorldHours()
    if not nowHours then
        return
    end

    for key, state in pairs(trackedHearths) do
        if state.pendingRemoval
            and state.pendingRemovalSinceWorldAgeHours
            and nowHours - state.pendingRemovalSinceWorldAgeHours >= PENDING_REMOVAL_MAX_HOURS
        then
            clearState(key, state)
            logger.debug(string.format(
                "Hearth pending trail expired: %s | unresolved for %.0fh",
                tostring(key), PENDING_REMOVAL_MAX_HOURS
            ))
        end
    end
end

local function reconcileNearbyHearths(logger)
    local playerObject = getLocalPlayer()
    local playerSquare = playerObject and playerObject.getSquare and playerObject:getSquare() or nil
    local cell = getCell and getCell() or nil
    if not playerSquare or not cell or not cell.getGridSquare then
        return
    end

    local z = playerSquare:getZ()
    for y = playerSquare:getY() - SCAN_RADIUS, playerSquare:getY() + SCAN_RADIUS do
        for x = playerSquare:getX() - SCAN_RADIUS, playerSquare:getX() + SCAN_RADIUS do
            local square = cell:getGridSquare(x, y, z)
            local objects = square and square.getObjects and square:getObjects() or nil
            if objects then
                for index = 0, objects:size() - 1 do
                    trackHearth(objects:get(index), logger)
                end
            end
        end
    end
end

local function updateHearth(key, state, settings, logger)
    if state.unloaded then
        return
    end

    local hearth = state.hearth
    if not isSupportedHearth(hearth) then
        clearState(key, state)
        return
    end
    if not isInLoadedWorld(hearth) then
        logger.debug(string.format(
            "Hearth unloaded: %s | vanillaSource=%s | retained trail paused",
            tostring(key), vanillaSourceName(hearth)
        ))
        removeSource(state)
        state.hearth = nil
        state.unloaded = true
        return
    end

    local nowHours = getWorldHours()
    if not nowHours then
        return
    end

    if state.lastUpdateWorldAgeHours == nil or nowHours < state.lastUpdateWorldAgeHours then
        state.lastUpdateWorldAgeHours = nowHours
        if state.trailStarted then
            local temperature = state.retentionStarted
                and sourceTemperature(state, state.trailDurationHours)
                or trailStartTemperature()
            ensureSource(state, hearth, temperature)
        end
        return
    end

    local elapsedHours = math.max(0, nowHours - state.lastUpdateWorldAgeHours)
    state.lastUpdateWorldAgeHours = nowHours
    local reloaded = state.reloaded
    state.reloaded = false
    if elapsedHours <= 0 then
        return
    end

    local capacityHours = settingInRange(settings, "QoLforSacriel_HearthRetainedHeat_MaxBurnCapacityHours", 1, 8, 4)
    local retentionHours = settingInRange(settings, "QoLforSacriel_HearthRetainedHeat_MaxRetentionHours", 12, 36, 24)
    local chargeScale, retentionScale = timingScales(settings)
    local isLitWithFuel = hearth:isLit() and hearth:hasFuel()
    local trailWasStarted = state.trailStarted

    if isLitWithFuel then
        if not state.wasLit then
            state.trailExpiredThisBurn = false
        end
        if state.trailStarted and state.retentionStarted then
            state.retentionStarted = false
            logger.debug(string.format(
                "Hearth retention paused for relight: %s | vanillaSource=%s | charge=%.3f/1.000",
                tostring(key), vanillaSourceName(hearth), state.storedHeat
            ))
        end

        local chargeElapsed = elapsedHours / chargeScale
        if state.trailStarted then
            chargeElapsed = chargeElapsed * 0.70
        end
        local chargeConstant = -(capacityHours / 2) / math.log(0.20)
        state.storedHeat = 1 - (1 - state.storedHeat) * math.exp(-chargeElapsed / chargeConstant)
        state.normalizedBurnHours = math.min(capacityHours, state.normalizedBurnHours + chargeElapsed)
        if state.normalizedBurnHours >= capacityHours then
            state.storedHeat = 1
        end

        if state.trailStarted then
            ensureSource(state, hearth, trailStartTemperature())
        end

        if not state.trailStarted
            and not state.trailExpiredThisBurn
            and state.storedHeat >= TRAIL_START_HEAT
            and nativeRadius(hearth) < SOURCE_RADIUS
        then
            local temperature = trailStartTemperature()
            state.trailStarted = ensureSource(state, hearth, temperature)
            state.trailElapsedHours = 0
            if state.trailStarted then
                state.trailInitialCharge = 0
                state.trailDurationHours = 0
                state.retentionStarted = false
                state.lastLoggedTrailHour = 0
                logger.debug(string.format(
                    "Hearth trail started: %s | vanillaSource=%s | charge=%.3f/1.000 | sourceTemp=%d | retention=pending",
                    tostring(key), vanillaSourceName(hearth), state.storedHeat, temperature
                ))
            end
        end
    end

    if state.trailStarted and not isLitWithFuel and not state.retentionStarted then
        state.trailInitialCharge = state.storedHeat
        state.trailDurationHours = retentionHours * state.trailInitialCharge
        state.trailElapsedHours = 0
        state.retentionStarted = true
        state.lastLoggedTrailHour = 0
        logger.debug(string.format(
            "Hearth retention started: %s | vanillaSource=%s | charge=%.3f/1.000 | sourceTemp=%d | trail=0.00/%.2fh",
            tostring(key), vanillaSourceName(hearth), state.storedHeat,
            trailStartTemperature(), state.trailDurationHours
        ))
    end

    if state.trailStarted and state.retentionStarted and trailWasStarted and not isLitWithFuel then
        state.trailElapsedHours = state.trailElapsedHours + elapsedHours / retentionScale
        state.storedHeat = math.max(0, state.trailInitialCharge * (1 - state.trailElapsedHours / state.trailDurationHours))
        local temperature = sourceTemperature(state, state.trailDurationHours)
        ensureSource(state, hearth, temperature)

        if reloaded then
            logger.debug(string.format(
                "Hearth trail recalculated: %s | vanillaSource=%s | elapsed=%.2fh | sourceTemp=%d | trail=%.2f/%.2fh",
                tostring(key), vanillaSourceName(hearth), elapsedHours, temperature,
                state.trailElapsedHours, state.trailDurationHours
            ))
        end

        local completedTrailHours = math.floor(state.trailElapsedHours)
        if completedTrailHours > state.lastLoggedTrailHour then
            state.lastLoggedTrailHour = completedTrailHours
            local outsideTemp = getOutdoorTemperature()
            logger.debug(string.format(
                "Hearth trail update: %s | vanillaSource=%s | charge=%.3f/1.000 | sourceTemp=%d | outsideTemp=%d | trail=%.2f/%.2fh",
                tostring(key), vanillaSourceName(hearth), state.storedHeat, temperature, outsideTemp,
                state.trailElapsedHours, state.trailDurationHours
            ))
        end
    end

    if not isLitWithFuel
        and state.trailStarted
        and state.retentionStarted
        and state.trailElapsedHours >= state.trailDurationHours
    then
        removeSource(state)
        state.trailStarted = false
        clearState(key, state)
        logger.debug(string.format(
            "Hearth trail expired: %s | vanillaSource=%s",
            tostring(key), vanillaSourceName(hearth)
        ))
        return
    end

    if not isLitWithFuel and not state.trailStarted then
        clearState(key, state)
        return
    end

    state.wasLit = isLitWithFuel
end

local function removeAllSources()
    local keys = {}
    for key, state in pairs(trackedHearths) do
        table.insert(keys, key)
    end
    for index = 1, #keys do
        local key = keys[index]
        clearState(key, trackedHearths[key])
    end
end

local function onMinute(settings, logger)
    if settings.isEnabled("QoLforSacriel_EnableHearthRetainedHeat") ~= true then
        removeAllSources()
        return
    end

    reconcileUnloadedHearths(logger)
    reconcilePendingRemovalHearths(logger)
    expirePendingRemovalHearths(logger)
    reconcileNearbyHearths(logger)
    for key, state in pairs(trackedHearths) do
        local ok, errorMessage = pcall(function()
            updateHearth(key, state, settings, logger)
        end)
        if not ok then
            logger.error("Hearth retained heat update failed: " .. tostring(errorMessage))
            clearState(key, state)
        end
    end
end

local function onObjectAboutToBeRemoved(object)
    local key = hearthKey(object)
    if key and trackedHearths[key] then
        clearState(key, trackedHearths[key])
    end
end

function HearthRetainedHeat.init(settings, logger)
    if installed then
        logger.debug("HearthRetainedHeat.Base already installed")
        return
    end

    Events.EveryOneMinute.Add(function()
        local ok, errorMessage = pcall(function()
            onMinute(settings, logger)
        end)
        if not ok then
            logger.error("Hearth retained heat minute update failed: " .. tostring(errorMessage))
        end
    end)
    Events.OnObjectAboutToBeRemoved.Add(onObjectAboutToBeRemoved)
    installed = true
    logger.info("HearthRetainedHeat.Base installed")
end

return HearthRetainedHeat