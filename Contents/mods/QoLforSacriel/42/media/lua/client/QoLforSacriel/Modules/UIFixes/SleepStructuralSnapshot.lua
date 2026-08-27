-- ff-assisted

local SleepStructuralSnapshot = {}

local STRUCTURAL_SNAPSHOT_SCHEMA = 1
local Z_MIN = 0
local Z_MAX = 4

local function safeCall(target, methodName, ...)
    if not target then
        return false, nil
    end
    local methodOk, method = pcall(function()
        return target[methodName]
    end)
    if not methodOk or type(method) ~= "function" then
        return false, nil
    end
    return pcall(method, target, ...)
end

local function finiteNumber(value)
    local numberValue = tonumber(value)
    if not numberValue or numberValue ~= numberValue or numberValue == math.huge or numberValue == -math.huge then
        return nil
    end
    return numberValue
end

local function readNumber(target, methodName, ...)
    local ok, value = safeCall(target, methodName, ...)
    return ok and finiteNumber(value) or nil
end

local function readBoolean(target, methodName)
    local ok, value = safeCall(target, methodName)
    if not ok or type(value) ~= "boolean" then
        return nil
    end
    return value
end

local function readString(target, methodName)
    local ok, value = safeCall(target, methodName)
    if not ok or value == nil then
        return nil
    end
    return tostring(value)
end

local function hasMethod(target, methodName)
    if not target then return false end
    local ok, method = pcall(function() return target[methodName] end)
    return ok and type(method) == "function"
end

local function nowMs()
    if getTimestampMs then
        local ok, value = pcall(getTimestampMs)
        if ok and finiteNumber(value) then
            return tonumber(value)
        end
    end
    if getTimestamp then
        local ok, value = pcall(getTimestamp)
        if ok and finiteNumber(value) then
            return tonumber(value) * 1000
        end
    end
    return 0
end

local function emit(options, eventName, fields)
    if options and options.emit then
        options.emit(eventName, fields)
    end
end

local function field(name, value)
    return { name, value }
end

local function isMultiplayer()
    if isClient then
        local ok, value = pcall(isClient)
        if ok and value == true then
            return true, "multiplayer"
        end
    end
    if isServer then
        local ok, value = pcall(isServer)
        if ok and value == true then
            return true, "server"
        end
    end
    return false, nil
end

local function instanceOf(object, className)
    if not object or type(instanceof) ~= "function" then
        return false, false
    end
    local ok, value = pcall(instanceof, object, className)
    return ok, ok and value == true
end

local function structuralKind(object)
    local ok, matches = instanceOf(object, "IsoDoor")
    if not ok then return nil, "instanceof" end
    if matches then return "door", nil end
    ok, matches = instanceOf(object, "IsoWindow")
    if not ok then return nil, "instanceof" end
    if matches then return "window", nil end
    ok, matches = instanceOf(object, "IsoBarricade")
    if not ok then return nil, "instanceof" end
    if matches then return "barricade", nil end
    return nil, nil
end

local function getSpriteName(object)
    local spriteOk, sprite = safeCall(object, "getSprite")
    return spriteOk and sprite and readString(sprite, "getName") or nil
end

local function getObjectSquare(object)
    local ok, square = safeCall(object, "getSquare")
    return ok and square or nil
end

local function getPosition(square)
    if not square then return nil, nil, nil end
    return readNumber(square, "getX"), readNumber(square, "getY"), readNumber(square, "getZ")
end

local function orientationToken(north)
    if north == true then return "N" end
    if north == false then return "E" end
    return "U"
end

local function targetScalars(object)
    local ok, target = safeCall(object, "getBarricadedObject")
    if not ok or not target then
        return nil
    end
    local targetSquare = getObjectSquare(target)
    local x, y, z = getPosition(targetSquare)
    local targetKind = structuralKind(target)
    return { kind = targetKind, x = x, y = y, z = z }
end

local function targetToken(target)
    if not target then return "nil" end
    return tostring(target.kind or "object") .. ":" .. tostring(target.x) .. ":" .. tostring(target.y) .. ":" .. tostring(target.z)
end

local function buildEntry(object, kind, square, capabilities)
    capabilities.objectSquare = capabilities.objectSquare or hasMethod(object, "getSquare")
    capabilities.health = capabilities.health or hasMethod(object, "getHealth")
    capabilities.maximumHealth = capabilities.maximumHealth or hasMethod(object, "getMaxHealth")
    capabilities.destroyedState = capabilities.destroyedState or hasMethod(object, "isDestroyed")
    capabilities.orientation = capabilities.orientation
        or hasMethod(object, "getNorth")
        or hasMethod(object, "isNorth")
        or hasMethod(object, "getDir")
    capabilities.spriteName = capabilities.spriteName
        or (hasMethod(object, "getSprite") and getSpriteName(object) ~= nil)
    if kind == "barricade" then
        capabilities.barricadePlanks = capabilities.barricadePlanks or hasMethod(object, "getNumPlanks")
        capabilities.barricadedTarget = capabilities.barricadedTarget or hasMethod(object, "getBarricadedObject")
    end
    local x, y, z = getPosition(square)
    if x == nil or y == nil or z == nil then
        return nil, "unsupported-state"
    end
    local north = readBoolean(object, "getNorth")
    if north == nil then
        north = readBoolean(object, "isNorth")
    end
    if (kind == "door" or kind == "window") and north == nil then
        return nil, "orientation-unavailable"
    end
    local destroyed = readBoolean(object, "isDestroyed")
    if destroyed == nil then
        return nil, "destroyed-state-unavailable"
    end
    local sprite = getSpriteName(object)
    local target = kind == "barricade" and targetScalars(object) or nil
    local key = kind .. ":" .. tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z) .. ":" .. orientationToken(north)
    if kind == "door" then
        key = key .. ":" .. tostring(sprite or "unknown")
    elseif kind == "barricade" then
        key = key .. ":" .. targetToken(target)
    end
    return {
        key = key,
        kind = kind,
        x = x,
        y = y,
        z = z,
        north = north,
        sprite = sprite,
        health = readNumber(object, "getHealth"),
        maxHealth = readNumber(object, "getMaxHealth"),
        destroyed = destroyed,
        planks = kind == "barricade" and readNumber(object, "getNumPlanks") or nil,
        barricadedTarget = target,
    }, nil
end

local function entryState(entry, present)
    if not present then
        return "present:false,destroyed:nil,health:nil,maxHealth:nil,planks:nil,sprite:nil"
    end
    return "present:true,destroyed:" .. tostring(entry.destroyed)
        .. ",health:" .. tostring(entry.health)
        .. ",maxHealth:" .. tostring(entry.maxHealth)
        .. ",planks:" .. tostring(entry.planks)
        .. ",sprite:" .. tostring(entry.sprite)
end

local function positionToken(entry)
    return tostring(entry.x) .. "," .. tostring(entry.y) .. "," .. tostring(entry.z)
end

local function sortedKeys(map)
    local keys = {}
    for key, _ in pairs(map or {}) do
        table.insert(keys, key)
    end
    table.sort(keys)
    return keys
end

local function addSample(samples, value, limit)
    if #samples < limit then
        table.insert(samples, value)
    end
end

local function resolveBuilding(playerObj)
    local squareOk, square = safeCall(playerObj, "getSquare")
    if not squareOk or not square then return nil, "no-square", "player.getSquare" end
    local buildingOk, building = safeCall(square, "getBuilding")
    if not buildingOk then return nil, "api-unavailable", "square.getBuilding" end
    if not building then return nil, "no-building", nil end
    local defOk, buildingDef = safeCall(building, "getDef")
    if not defOk or not buildingDef then return nil, "api-unavailable", "building.getDef" end
    local id = readString(buildingDef, "getIDString") or readString(buildingDef, "getID")
    local x = readNumber(buildingDef, "getX")
    local y = readNumber(buildingDef, "getY")
    local x2 = readNumber(buildingDef, "getX2")
    local y2 = readNumber(buildingDef, "getY2")
    if id == nil or x == nil or y == nil or x2 == nil or y2 == nil or x2 < x or y2 < y then
        return nil, "api-unavailable", "buildingDef.bounds"
    end
    return { object = buildingDef, id = id, x = x, y = y, x2 = x2, y2 = y2 }, nil, nil
end

local function squareMatchesBuilding(square, buildingId)
    local buildingOk, building = safeCall(square, "getBuilding")
    if not buildingOk or not building then return false end
    local defOk, buildingDef = safeCall(building, "getDef")
    if not defOk or not buildingDef then return false end
    local id = readString(buildingDef, "getIDString") or readString(buildingDef, "getID")
    return id ~= nil and tostring(id) == tostring(buildingId)
end

local function multiplayerResult()
    local multiplayer, mode = isMultiplayer()
    if multiplayer then
        return { status = mode == "multiplayer" and "unavailable" or "unsupported", reason = mode }
    end
    return nil
end

function SleepStructuralSnapshot.probe(playerObj, options)
    options = options or {}
    local result = SleepStructuralSnapshot.capture(playerObj, {
        maxLookups = options.maxLookups or math.huge,
        sampleLimit = 0,
        worldAge = options.worldAge,
    })
    return {
        status = result.status,
        reason = result.reason,
        failedApi = result.failedApi,
        error = result.error,
        candidateLookups = result.candidateLookups
            or (result.snapshot and result.snapshot.capture and result.snapshot.capture.candidateLookups),
        capabilities = result.capabilities,
    }
end

function SleepStructuralSnapshot.capture(playerObj, limits)
    limits = limits or {}
    local options = limits.options or limits
    local capabilities = {
        playerSquare = false, squareBuilding = false, buildingDef = false, buildingBounds = false,
        cellSquare = false, objectList = false, typeChecks = type(instanceof) == "function",
        objectSquare = false, health = false, maximumHealth = false, destroyedState = false,
        orientation = false, spriteName = false, barricadePlanks = false, barricadedTarget = false,
    }
    local multiplayer = multiplayerResult()
    if multiplayer then
        emit(options, "CAPTURE_SKIP", { field("status", multiplayer.status), field("reason", multiplayer.reason), field("candidateLookups", nil), field("scanCap", limits.maxLookups), field("error", nil) })
        multiplayer.capabilities = capabilities
        return multiplayer
    end
    local building, reason, failedApi = resolveBuilding(playerObj)
    if not building then
        local status = reason == "no-building" and "unavailable" or "unsupported"
        emit(options, "CAPTURE_SKIP", { field("status", status), field("reason", reason), field("candidateLookups", nil), field("scanCap", limits.maxLookups), field("error", failedApi) })
        return { status = status, reason = reason, failedApi = failedApi, capabilities = capabilities }
    end
    capabilities.playerSquare = true
    capabilities.squareBuilding = true
    capabilities.buildingDef = true
    capabilities.buildingBounds = true
    local candidateLookups = (building.x2 - building.x + 1) * (building.y2 - building.y + 1) * (Z_MAX - Z_MIN + 1)
    local playerSquareOk, playerSquare = safeCall(playerObj, "getSquare")
    local playerX, playerY, playerZ = playerSquareOk and getPosition(playerSquare) or nil, nil, nil
    if playerSquareOk then playerX, playerY, playerZ = getPosition(playerSquare) end
    local worldAge = limits.worldAge
    emit(options, "CAPTURE_BEGIN", {
        field("buildingId", building.id), field("bounds", tostring(building.x) .. "," .. tostring(building.y) .. "," .. tostring(building.x2) .. "," .. tostring(building.y2)),
        field("zRange", tostring(Z_MIN) .. "-" .. tostring(Z_MAX)), field("candidateLookups", candidateLookups), field("scanCap", limits.maxLookups),
        field("playerPos", tostring(playerX) .. "," .. tostring(playerY) .. "," .. tostring(playerZ)), field("worldAge", worldAge),
    })
    if not limits.maxLookups or candidateLookups > limits.maxLookups then
        emit(options, "CAPTURE_SKIP", { field("status", "capped"), field("reason", "scan-cap"), field("candidateLookups", candidateLookups), field("scanCap", limits.maxLookups), field("error", nil) })
        return { status = "capped", reason = "scan-cap", candidateLookups = candidateLookups, capabilities = capabilities }
    end
    local startedMs = nowMs()
    local sampleLimit = tonumber(limits.sampleLimit) or 0
    local metrics = {
        candidateLookups = candidateLookups, visitedSquares = 0, unavailableSquares = 0,
        buildingMismatchSquares = 0, objectsInspected = 0, structuralEntries = 0, ambiguousEntries = 0,
        nullSamples = {}, buildingMismatchSamples = {},
    }
    local entries = {}
    local ambiguous = {}
    local cellOk, cell = pcall(function() return getCell and getCell() or nil end)
    local failedOperation = not cellOk and "getCell" or nil
    if cellOk and not cell then failedOperation = "getCell" end
    capabilities.cellSquare = not failedOperation and hasMethod(cell, "getGridSquare")
    if not failedOperation then
        for z = Z_MIN, Z_MAX do
            for y = building.y, building.y2 do
                for x = building.x, building.x2 do
                    local squareOk, square = safeCall(cell, "getGridSquare", x, y, z)
                    local coordinate = tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
                    if not squareOk then
                        failedOperation = "cell.getGridSquare"
                    elseif not square then
                        metrics.unavailableSquares = metrics.unavailableSquares + 1
                        addSample(metrics.nullSamples, coordinate, sampleLimit)
                    else
                        metrics.visitedSquares = metrics.visitedSquares + 1
                        if not squareMatchesBuilding(square, building.id) then
                            metrics.buildingMismatchSquares = metrics.buildingMismatchSquares + 1
                            addSample(metrics.buildingMismatchSamples, coordinate, sampleLimit)
                        else
                            local objectsOk, objects = safeCall(square, "getObjects")
                            local size = objectsOk and objects and readNumber(objects, "size") or nil
                            if not objectsOk or size == nil then
                                failedOperation = "square.getObjects"
                            else
                                capabilities.objectList = true
                                for index = 0, size - 1 do
                                    local objectOk, object = safeCall(objects, "get", index)
                                    if not objectOk then
                                        failedOperation = "objects.get"
                                    elseif object then
                                        metrics.objectsInspected = metrics.objectsInspected + 1
                                        local kind, typeError = structuralKind(object)
                                        if typeError then
                                            failedOperation = typeError
                                        elseif kind then
                                            local entry, entryError = buildEntry(object, kind, square, capabilities)
                                            if not entry then
                                                metrics.ambiguousEntries = metrics.ambiguousEntries + 1
                                                emit(options, "CAPTURE_AMBIGUOUS", { field("key", nil), field("kind", kind), field("pos", coordinate), field("reason", entryError), field("matches", 1) })
                                                if entryError == "orientation-unavailable" or entryError == "destroyed-state-unavailable" then
                                                    failedOperation = kind .. ".requiredState"
                                                end
                                            elseif entries[entry.key] then
                                                ambiguous[entry.key] = true
                                                entries[entry.key] = nil
                                                metrics.structuralEntries = metrics.structuralEntries - 1
                                                metrics.ambiguousEntries = metrics.ambiguousEntries + 1
                                                emit(options, "CAPTURE_AMBIGUOUS", { field("key", entry.key), field("kind", kind), field("pos", coordinate), field("reason", "duplicate-start-key"), field("matches", 2) })
                                            elseif not ambiguous[entry.key] then
                                                entries[entry.key] = entry
                                                metrics.structuralEntries = metrics.structuralEntries + 1
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    local status = failedOperation and "error" or (metrics.unavailableSquares > 0 and "incomplete" or "complete")
    local elapsedMs = math.max(0, nowMs() - startedMs)
    if failedOperation then
        emit(options, "ERROR", { field("stage", "capture"), field("operation", failedOperation), field("key", nil), field("error", failedOperation) })
    end
    emit(options, "CAPTURE_SUMMARY", {
        field("status", status), field("elapsedMs", elapsedMs), field("candidateLookups", candidateLookups),
        field("visitedSquares", metrics.visitedSquares), field("nullSquares", metrics.unavailableSquares),
        field("buildingMismatchSquares", metrics.buildingMismatchSquares), field("objectsInspected", metrics.objectsInspected),
        field("entries", metrics.structuralEntries), field("ambiguousEntries", metrics.ambiguousEntries),
        field("nullSamples", table.concat(metrics.nullSamples, "|")), field("nullOmitted", math.max(0, metrics.unavailableSquares - #metrics.nullSamples)),
        field("buildingMismatchSamples", table.concat(metrics.buildingMismatchSamples, "|")), field("buildingMismatchOmitted", math.max(0, metrics.buildingMismatchSquares - #metrics.buildingMismatchSamples)),
    })
    if failedOperation then
        return { status = "error", reason = "api-unavailable", error = failedOperation, candidateLookups = candidateLookups, capabilities = capabilities }
    end
    return {
        status = status,
        snapshot = {
            schema = STRUCTURAL_SNAPSHOT_SCHEMA,
            building = { id = building.id, x = building.x, y = building.y, x2 = building.x2, y2 = building.y2, zMin = Z_MIN, zMax = Z_MAX },
            capture = {
                worldAge = worldAge, playerX = playerX, playerY = playerY, playerZ = playerZ,
                candidateLookups = candidateLookups, visitedSquares = metrics.visitedSquares,
                unavailableSquares = metrics.unavailableSquares, structuralEntries = metrics.structuralEntries,
            },
            entries = entries,
        },
        capabilities = capabilities,
    }
end

local function samePosition(entry, candidate)
    return entry.kind == candidate.kind and entry.x == candidate.x and entry.y == candidate.y and entry.z == candidate.z and entry.north == candidate.north
end

local function collectCurrentEntries(square)
    local current = {}
    local objectsOk, objects = safeCall(square, "getObjects")
    local size = objectsOk and objects and readNumber(objects, "size") or nil
    if not objectsOk or size == nil then return nil, "square.getObjects" end
    for index = 0, size - 1 do
        local objectOk, object = safeCall(objects, "get", index)
        if not objectOk then return nil, "objects.get" end
        local kind, typeError = structuralKind(object)
        if typeError then return nil, typeError end
        if kind then
            local entry, entryError = buildEntry(object, kind, square, {})
            if not entry then return nil, entryError or "unsupported-state" end
            table.insert(current, entry)
        end
    end
    return current, nil
end

local function findMatches(startEntry, currentEntries)
    local exact = {}
    local samePlace = {}
    for _, candidate in ipairs(currentEntries or {}) do
        if candidate.key == startEntry.key then table.insert(exact, candidate) end
        if samePosition(startEntry, candidate) then table.insert(samePlace, candidate) end
    end
    return exact, samePlace
end

function SleepStructuralSnapshot.compare(startSnapshot, options)
    options = options or {}
    if type(startSnapshot) ~= "table" or startSnapshot.schema ~= STRUCTURAL_SNAPSHOT_SCHEMA or type(startSnapshot.entries) ~= "table" then
        return { status = "unavailable", breach = false, confidence = "Unavailable", reason = "invalid-snapshot", transitions = {}, ambiguous = {} }
    end
    local multiplayer = multiplayerResult()
    if multiplayer then return multiplayer end
    local keys = sortedKeys(startSnapshot.entries)
    local squareKeys = {}
    for _, key in ipairs(keys) do
        local entry = startSnapshot.entries[key]
        squareKeys[positionToken(entry)] = true
    end
    local uniqueSquareCount = #sortedKeys(squareKeys)
    emit(options, "COMPARE_BEGIN", {
        field("captureStatus", options.captureStatus), field("startEntries", #keys), field("uniqueEntrySquares", uniqueSquareCount),
        field("actualHours", options.actualHours), field("requestedHours", options.requestedHours), field("earlyWake", options.earlyWake == true),
    })
    local startedMs = nowMs()
    local cellOk, cell = pcall(function() return getCell and getCell() or nil end)
    if not cellOk or not cell then
        emit(options, "ERROR", { field("stage", "compare"), field("operation", "getCell"), field("key", nil), field("error", "getCell") })
        emit(options, "COMPARE_SUMMARY", {
            field("status", "error"), field("elapsedMs", math.max(0, nowMs() - startedMs)),
            field("comparedEntries", 0), field("unavailableEntries", 0), field("unchangedEntries", 0),
            field("partialDamageEntries", 0), field("ambiguousEntries", 0), field("acceptedTransitions", 0), field("breach", false),
        })
        return { status = "error", breach = false, confidence = "Unavailable", transitions = {}, ambiguous = {} }
    end
    local cache = {}
    local result = {
        status = "complete", breach = false, confidence = "Unavailable", transitions = {}, ambiguous = {},
        comparedEntries = 0, unavailableEntries = 0, unchangedEntries = 0, partialDamageEntries = 0,
    }
    for _, key in ipairs(keys) do
        local startEntry = startSnapshot.entries[key]
        result.comparedEntries = result.comparedEntries + 1
        local pos = positionToken(startEntry)
        if cache[pos] == nil then
            local squareOk, square = safeCall(cell, "getGridSquare", startEntry.x, startEntry.y, startEntry.z)
            if not squareOk or not square then
                cache[pos] = false
            else
                local currentEntries, currentError = collectCurrentEntries(square)
                cache[pos] = currentError and { error = currentError } or currentEntries
            end
        end
        local currentEntries = cache[pos]
        local decision = "unchanged"
        local reason = nil
        local wakeEntry = nil
        local wakeMatches = 0
        local transition = nil
        if currentEntries == false then
            if result.status ~= "error" then result.status = "incomplete" end
            result.unavailableEntries = result.unavailableEntries + 1
            decision = "unavailable"
            reason = "wake-square-unavailable"
        elseif currentEntries.error then
            result.status = "error"
            decision = "error"
            reason = currentEntries.error
            emit(options, "ERROR", { field("stage", "compare"), field("operation", currentEntries.error), field("key", key), field("error", currentEntries.error) })
        else
            local exact, samePlace = findMatches(startEntry, currentEntries)
            wakeMatches = #samePlace
            wakeEntry = exact[1]
            if startEntry.destroyed then
                decision = "ambiguous"
                reason = "start-already-destroyed"
            elseif #exact > 1 or #samePlace > 1 then
                decision = "ambiguous"
                reason = "multiple-wake-matches"
            elseif startEntry.kind == "window" and wakeEntry and wakeEntry.destroyed then
                decision = "accepted"
                transition = "window-destroyed"
            elseif (startEntry.kind == "door" or startEntry.kind == "barricade") and not wakeEntry and #samePlace == 0 then
                decision = "accepted"
                transition = startEntry.kind .. "-removed"
            elseif not wakeEntry and #samePlace > 0 then
                decision = "ambiguous"
                reason = "replacement-present"
                wakeEntry = samePlace[1]
            elseif wakeEntry and startEntry.kind == "barricade" and startEntry.planks and wakeEntry.planks and wakeEntry.planks < startEntry.planks then
                decision = "ambiguous"
                reason = "planks-reduced"
                result.partialDamageEntries = result.partialDamageEntries + 1
            elseif wakeEntry and startEntry.health and wakeEntry.health and wakeEntry.health < startEntry.health then
                decision = "ambiguous"
                reason = "partial-damage"
                result.partialDamageEntries = result.partialDamageEntries + 1
            else
                result.unchangedEntries = result.unchangedEntries + 1
            end
        end
        local startState = entryState(startEntry, true)
        local wakeState = currentEntries == false and "unknown" or entryState(wakeEntry, wakeEntry ~= nil)
        if transition then
            table.insert(result.transitions, { key = key, kind = startEntry.kind, x = startEntry.x, y = startEntry.y, z = startEntry.z, transition = transition })
            emit(options, "TRANSITION_ACCEPTED", {
                field("key", key), field("kind", startEntry.kind), field("pos", pos), field("transition", transition),
                field("startState", startState), field("wakeState", wakeState),
            })
        elseif reason and decision ~= "unavailable" and decision ~= "error" then
            table.insert(result.ambiguous, { key = key, reason = reason })
            emit(options, "TRANSITION_AMBIGUOUS", {
                field("key", key), field("kind", startEntry.kind), field("pos", pos), field("reason", reason),
                field("startState", startState), field("wakeState", wakeState), field("wakeMatches", wakeMatches),
            })
        end
    end
    result.breach = #result.transitions > 0
    result.confidence = result.breach and "Inferred" or "Unavailable"
    emit(options, "COMPARE_SUMMARY", {
        field("status", result.status), field("elapsedMs", math.max(0, nowMs() - startedMs)),
        field("comparedEntries", result.comparedEntries), field("unavailableEntries", result.unavailableEntries),
        field("unchangedEntries", result.unchangedEntries), field("partialDamageEntries", result.partialDamageEntries),
        field("ambiguousEntries", #result.ambiguous), field("acceptedTransitions", #result.transitions), field("breach", result.breach),
    })
    return result
end

function SleepStructuralSnapshot.describe(result)
    if type(result) ~= "table" then return "unavailable" end
    return tostring(result.status) .. ":" .. tostring(result.reason or (result.breach and "breach" or "none"))
end

return SleepStructuralSnapshot