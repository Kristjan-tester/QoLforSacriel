local SoundRadius = {}

local renderer = require "QoLforSacriel/Modules/SoundIntel/SoundOverlayRenderer"
local settingsProvider = require "QoLforSacriel/Modules/SoundIntel/SoundRadiusSettingsProvider"
local runtimeSettings = require "QoLforSacriel/Modules/SoundIntel/SoundRuntimeSettings"
local modOptions = require "QoLforSacriel/Modules/SoundIntel/SoundRadiusModOptions"

local installed = false
local rings = {}
local RING_COALESCE_MS = 200
local RING_DEDUPE_MS = 250
local MAX_RINGS_PER_REPEAT_SOURCE = 2
local REPEAT_SOURCE_PROGRESS_THRESHOLD = 0.5

local function nowMs()
    if getTimestampMs then
        return getTimestampMs()
    end
    return math.floor((getTimestamp() or 0) * 1000)
end

local function isRuntimeEnabled(gates, resolved)
    return gates and gates.enabled == true
        and gates.soundRadiusEnabled == true
        and resolved.enabled == true
end

local function prune(now)
    for index = #rings, 1, -1 do
        if now >= rings[index].expiresAtMs then
            table.remove(rings, index)
        end
    end
end

local function localPlayerName(playerObj)
    if playerObj and playerObj.getUsername then
        local ok, name = pcall(function()
            return playerObj:getUsername()
        end)
        if ok and name and tostring(name) ~= "" then
            return tostring(name)
        end
    end
    return "local-player"
end

local function logRing(logger, debugEnabled, playerObj, x, y, z, radius, volume, origin, synthetic, outcome)
    if not debugEnabled then
        return
    end
    logger.debug(
        "SoundRadius ring: origin=" .. tostring(origin)
        .. ", synthetic=" .. tostring(synthetic == true)
        .. ", player=" .. localPlayerName(playerObj)
        .. ", range=" .. tostring(radius) .. " tiles"
        .. ", volume=" .. tostring(volume)
        .. ", at=" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
        .. ", outcome=" .. tostring(outcome)
    )
end

local function repeatSourceKey(source, x, y, z, origin)
    if source ~= nil then
        return source
    end
    return "null:" .. tostring(origin)
        .. ":" .. tostring(math.floor(tonumber(x) or 0))
        .. ":" .. tostring(math.floor(tonumber(y) or 0))
        .. ":" .. tostring(math.floor(tonumber(z) or 0))
end

local function sourceRingState(sourceKey)
    local count = 0
    local oldestIndex = nil
    local newest = nil

    for index = 1, #rings do
        local ring = rings[index]
        if ring.repeatSourceKey == sourceKey then
            count = count + 1
            if oldestIndex == nil or ring.createdAtMs < rings[oldestIndex].createdAtMs then
                oldestIndex = index
            end
            if newest == nil or ring.createdAtMs > newest.createdAtMs then
                newest = ring
            end
        end
    end

    return count, oldestIndex, newest
end

local function ringProgress(ring, now)
    if not ring then
        return 1
    end
    local lifeMs = math.max(1, ring.expiresAtMs - ring.createdAtMs)
    return math.min(1, math.max(0, (now - ring.createdAtMs) / lifeMs))
end

local function createRing(x, y, z, radius, volume, now, resolved, origin, synthetic, sourceKey)
    return {
        x = x,
        y = y,
        z = z,
        radius = radius,
        volume = volume,
        origin = origin,
        synthetic = synthetic == true,
        repeatSourceKey = sourceKey,
        createdAtMs = now,
        expiresAtMs = now + resolved.ringDurationMs,
    }
end

local function queueRing(playerObj, x, y, z, radius, volume, resolved, logger, debugEnabled, origin, synthetic, source)
    local rawRadius = math.floor(tonumber(radius) or 0)
    if rawRadius <= 0 then
        return
    end

    local now = nowMs()
    prune(now)
    local sourceKey = repeatSourceKey(source, x, y, z, origin)
    local newest = rings[#rings]
    local ageMs = newest and now - newest.createdAtMs or nil

    if newest and newest.repeatSourceKey == sourceKey and ageMs <= RING_DEDUPE_MS and newest.synthetic ~= synthetic then
        if synthetic then
            if rawRadius > newest.radius then
                newest.radius = rawRadius
                newest.volume = math.max(tonumber(newest.volume) or 0, tonumber(volume) or 0)
                newest.expiresAtMs = now + resolved.ringDurationMs
                logRing(logger, debugEnabled, playerObj, x, y, z, rawRadius, volume, origin, synthetic, "expanded-observed-ring")
            end
            return
        end

        rings[#rings] = createRing(x, y, z, math.max(rawRadius, newest.radius), math.max(tonumber(volume) or 0, tonumber(newest.volume) or 0), now, resolved, origin, false, sourceKey)
        logRing(logger, debugEnabled, playerObj, x, y, z, rawRadius, volume, origin, false, "replaced-synthetic-ring")
        return
    end

    if newest and newest.repeatSourceKey == sourceKey and newest.synthetic == synthetic and ageMs <= RING_COALESCE_MS then
        if rawRadius >= newest.radius then
            newest.radius = rawRadius
            newest.volume = math.max(tonumber(newest.volume) or 0, tonumber(volume) or 0)
            logRing(logger, debugEnabled, playerObj, x, y, z, rawRadius, volume, origin, synthetic, "updated-coalesced-ring")
        end
        return
    end

    local sourceRingCount, oldestSourceRingIndex, newestSourceRing = sourceRingState(sourceKey)
    if newestSourceRing and ringProgress(newestSourceRing, now) < REPEAT_SOURCE_PROGRESS_THRESHOLD then
        logRing(logger, debugEnabled, playerObj, x, y, z, rawRadius, volume, origin, synthetic, "suppressed-repeat-source-halfway")
        return
    end
    if sourceRingCount >= MAX_RINGS_PER_REPEAT_SOURCE and oldestSourceRingIndex then
        table.remove(rings, oldestSourceRingIndex)
    end

    table.insert(rings, createRing(x, y, z, rawRadius, volume, now, resolved, origin, synthetic, sourceKey))
    while #rings > resolved.maxActiveRings do
        table.remove(rings, 1)
    end
    logRing(logger, debugEnabled, playerObj, x, y, z, rawRadius, volume, origin, synthetic, "queued")
end

local function isLocalPlayerSource(source, playerObj)
    if not source or not playerObj then
        return false, "missing-source-or-player"
    end
    if source == playerObj then
        return true, "identity"
    end
    if not instanceof or not instanceof(source, "IsoPlayer") or not source.isLocalPlayer then
        return false, "not-local-player"
    end
    local ok, localPlayer = pcall(function()
        return source:isLocalPlayer()
    end)
    return ok and localPlayer == true, ok and "isLocalPlayer" or "non-local-player"
end

local function isEligibleWorldObjectSource(source)
    if source == nil then
        return false, "null-source"
    end
    if instanceof and instanceof(source, "IsoPlayer") then
        return false, "player-source"
    end
    if instanceof and instanceof(source, "IsoZombie") then
        return false, "zombie-source"
    end
    if instanceof and instanceof(source, "IsoAnimal") then
        return false, "animal-source"
    end
    return true, "world-object"
end

local function isNearbyNullSource(x, y, z, radius, source, playerObj)
    if source ~= nil then
        return false, "not-null-source"
    end
    return true, "null-source"
end

local function movementStateText(playerObj)
    if not playerObj then
        return "unknown"
    end

    local function readState(methodName)
        if not playerObj[methodName] then
            return false
        end
        local ok, value = pcall(function()
            return playerObj[methodName](playerObj)
        end)
        return ok and value == true
    end

    return "sneaking=" .. tostring(readState("isSneaking"))
        .. ", running=" .. tostring(readState("isRunning"))
        .. ", sprinting=" .. tostring(readState("isSprinting"))
end

local function logWorldSound(logger, debugEnabled, x, y, z, radius, volume, source, disposition, isLocalSource)
    if not debugEnabled then
        return
    end
    local movementState = isLocalSource and movementStateText(getPlayer()) or nil
    logger.debug(
        "SoundRadius OnWorldSound received: source=" .. tostring(source)
        .. ", range=" .. tostring(radius)
        .. ", volume=" .. tostring(volume)
        .. ", at=" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
        .. ", sourceDisposition=" .. tostring(disposition)
        .. ", localPlayerMatch=" .. tostring(isLocalSource == true)
        .. (movementState and ", " .. movementState or "")
    )
end

local function onWorldSound(x, y, z, radius, volume, source, settings, logger)
    local gates = runtimeSettings.getCached(settings, logger)
    if not gates or gates.enabled ~= true or gates.soundRadiusEnabled ~= true then
        return
    end
    local resolved = settingsProvider.getCached(settings)
    local runtimeEnabled = isRuntimeEnabled(gates, resolved)
    if not runtimeEnabled then
        return
    end
    local playerObj = getPlayer()
    local isLocalSource, matchMethod = isLocalPlayerSource(source, playerObj)
    local isWorldObject, objectMethod = isEligibleWorldObjectSource(source)
    local isNearbyNull, nullMethod = isNearbyNullSource(x, y, z, radius, source, playerObj)
    local disposition = isLocalSource and matchMethod or (isWorldObject and objectMethod or (isNearbyNull and nullMethod or objectMethod))
    logWorldSound(logger, gates.debugEnabled, x, y, z, radius, volume, source, disposition, isLocalSource)
    if isLocalSource then
        queueRing(playerObj, x, y, z, radius, volume, resolved, logger, gates.debugEnabled, "observed-player-world-sound", false, source)
    elseif isWorldObject then
        queueRing(playerObj, x, y, z, radius, volume, resolved, logger, gates.debugEnabled, "observed-world-object-sound", false, source)
    elseif isNearbyNull then
        queueRing(playerObj, x, y, z, radius, volume, resolved, logger, gates.debugEnabled, "observed-null-source-world-sound", false, source)
    end
end

local function onPostRender(settings, logger)
    local gates = runtimeSettings.getCached(settings, logger)
    if not gates or gates.enabled ~= true or gates.soundRadiusEnabled ~= true then
        rings = {}
        return
    end
    local resolved = settingsProvider.getCached(settings)
    if not isRuntimeEnabled(gates, resolved) then
        rings = {}
        return
    end
    local playerObj = getPlayer()
    if not playerObj or type(renderer.renderPlayerWorldSoundRing) ~= "function" then
        return
    end
    local now = nowMs()
    prune(now)
    for index = 1, #rings do
        local ok, err = pcall(function()
            renderer.renderPlayerWorldSoundRing(playerObj, rings[index], now, resolved)
        end)
        if not ok then
            logger.error("SoundRadius render error: " .. tostring(err))
        end
    end
end

function SoundRadius.init(settings, logger)
    if installed then
        return
    end
    runtimeSettings.init(settings, logger)
    modOptions.register(logger, function()
        settingsProvider.refresh(settings)
        local gates = runtimeSettings.getCached(settings, logger)
        if gates and gates.debugEnabled then
            logger.debug("Noise Radius options cache refreshed from Mod Options")
        end
    end)
    settingsProvider.refresh(settings)
    if not Events.OnWorldSound and LuaEventManager and LuaEventManager.AddEvent then
        LuaEventManager.AddEvent("OnWorldSound")
    end
    Events.OnWorldSound.Add(function(x, y, z, radius, volume, source)
        onWorldSound(x, y, z, radius, volume, source, settings, logger)
    end)
    Events.OnPostRender.Add(function()
        onPostRender(settings, logger)
    end)
    installed = true
    logger.info("UIFixes.SoundRadius installed (local player world-sound rings)")
end

return SoundRadius