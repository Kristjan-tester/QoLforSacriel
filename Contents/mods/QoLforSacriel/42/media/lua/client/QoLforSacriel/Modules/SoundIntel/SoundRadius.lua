local SoundRadius = {}

local renderer = require "QoLforSacriel/Modules/SoundIntel/SoundOverlayRenderer"
local settingsProvider = require "QoLforSacriel/Modules/SoundIntel/SoundRadiusSettingsProvider"
local modOptions = require "QoLforSacriel/Modules/SoundIntel/SoundRadiusModOptions"

local installed = false
local rings = {}
local RING_COALESCE_MS = 200
local RING_DEDUPE_MS = 250
local NULL_SOURCE_MAX_DISTANCE = 2.5
local NULL_SOURCE_MAX_RADIUS = 20

local function nowMs()
    if getTimestampMs then
        return getTimestampMs()
    end
    return math.floor((getTimestamp() or 0) * 1000)
end

local function isRuntimeEnabled(settings, resolved)
    return settings.isEnabled() == true
        and settings.get("QoLforSacriel_UIFixes_EnableNoiseRadius") == true
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

local function logRing(logger, playerObj, x, y, z, radius, volume, origin, synthetic, outcome)
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

local function createRing(x, y, z, radius, volume, now, resolved, origin, synthetic)
    return {
        x = x,
        y = y,
        z = z,
        radius = radius,
        volume = volume,
        origin = origin,
        synthetic = synthetic == true,
        createdAtMs = now,
        expiresAtMs = now + resolved.ringDurationMs,
    }
end

local function queueRing(playerObj, x, y, z, radius, volume, resolved, logger, origin, synthetic)
    local rawRadius = math.floor(tonumber(radius) or 0)
    if rawRadius <= 0 then
        return
    end

    local now = nowMs()
    prune(now)
    local newest = rings[#rings]
    local ageMs = newest and now - newest.createdAtMs or nil

    if newest and ageMs <= RING_DEDUPE_MS and newest.synthetic ~= synthetic then
        if synthetic then
            if rawRadius > newest.radius then
                newest.radius = rawRadius
                newest.volume = math.max(tonumber(newest.volume) or 0, tonumber(volume) or 0)
                newest.expiresAtMs = now + resolved.ringDurationMs
                logRing(logger, playerObj, x, y, z, rawRadius, volume, origin, synthetic, "expanded-observed-ring")
            end
            return
        end

        rings[#rings] = createRing(x, y, z, math.max(rawRadius, newest.radius), math.max(tonumber(volume) or 0, tonumber(newest.volume) or 0), now, resolved, origin, false)
        logRing(logger, playerObj, x, y, z, rawRadius, volume, origin, false, "replaced-synthetic-ring")
        return
    end

    if newest and newest.synthetic == synthetic and ageMs <= RING_COALESCE_MS then
        if rawRadius >= newest.radius then
            rings[#rings] = createRing(x, y, z, rawRadius, volume, now, resolved, origin, synthetic)
            logRing(logger, playerObj, x, y, z, rawRadius, volume, origin, synthetic, "replaced-coalesced-ring")
        end
        return
    end

    table.insert(rings, createRing(x, y, z, rawRadius, volume, now, resolved, origin, synthetic))
    while #rings > resolved.maxActiveRings do
        table.remove(rings, 1)
    end
    logRing(logger, playerObj, x, y, z, rawRadius, volume, origin, synthetic, "queued")
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

local function isNearbyNullSource(x, y, z, radius, source, playerObj)
    if source ~= nil or not playerObj then
        return false, "not-null-source"
    end
    local rawRadius = tonumber(radius) or 0
    if rawRadius <= 0 or rawRadius > NULL_SOURCE_MAX_RADIUS then
        return false, "null-source-radius-out-of-range"
    end
    if z ~= nil and math.floor(playerObj:getZ()) ~= math.floor(z) then
        return false, "null-source-different-z"
    end
    if IsoUtils.DistanceTo(playerObj:getX(), playerObj:getY(), x, y) > NULL_SOURCE_MAX_DISTANCE then
        return false, "null-source-too-far"
    end
    return true, "nearby-null-source"
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

local function logWorldSound(logger, x, y, z, radius, volume, source, runtimeEnabled, matched, matchMethod)
    local movementState = matched and movementStateText(getPlayer()) or nil
    logger.debug(
        "SoundRadius OnWorldSound received: source=" .. tostring(source)
        .. ", range=" .. tostring(radius)
        .. ", volume=" .. tostring(volume)
        .. ", at=" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
        .. ", runtimeEnabled=" .. tostring(runtimeEnabled == true)
        .. ", localPlayerMatch=" .. tostring(matched == true)
        .. ", matchMethod=" .. tostring(matchMethod)
        .. (movementState and ", " .. movementState or "")
    )
end

local function onWorldSound(x, y, z, radius, volume, source, settings, logger)
    local resolved = settingsProvider.get(settings)
    local runtimeEnabled = isRuntimeEnabled(settings, resolved)
    local playerObj = getPlayer()
    local isLocalSource, matchMethod = isLocalPlayerSource(source, playerObj)
    local isNearbyNull, nullMethod = isNearbyNullSource(x, y, z, radius, source, playerObj)
    local outcome = isLocalSource and matchMethod or nullMethod
    if not runtimeEnabled then
        return
    end
    logWorldSound(logger, x, y, z, radius, volume, source, runtimeEnabled, isLocalSource, outcome)
    if isLocalSource then
        queueRing(playerObj, x, y, z, radius, volume, resolved, logger, "observed-player-world-sound", false)
    elseif isNearbyNull then
        queueRing(playerObj, x, y, z, radius, volume, resolved, logger, "nearby-null-source-world-sound", true)
    end
end

local function onPostRender(settings, logger)
    local resolved = settingsProvider.get(settings)
    if not isRuntimeEnabled(settings, resolved) then
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
    modOptions.register(logger)
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