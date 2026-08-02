local HeavyLoadHurtFeedback = {}

local installed = false
local lastTriggerAtHours = -1
local COOLDOWN_SECONDS = 2.0
local FIXED_VARIANT = "glasscut"
local FIXED_ROUTE = "voice"

local function getLogger()
    return _G.QoLforSacriel_Logger
end

local function isDebugEnabled(settings)
    return settings and settings.get and settings.get("QoLforSacriel_DebugLogs") == true
end

local function debugLog(settings, message)
    if not isDebugEnabled(settings) then
        return
    end
    local logger = getLogger()
    if logger and logger.debug then
        logger.debug("UIFixes.HeavyLoadHurtFeedback: " .. tostring(message))
    end
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

local function getWorldAgeHours()
    local gameTime = getGameTime and getGameTime()
    if not gameTime or not gameTime.getWorldAgeHours then
        return nil
    end
    return gameTime:getWorldAgeHours()
end

local function isCoolingDown(nowHours)
    if not nowHours or lastTriggerAtHours < 0 then
        return false
    end
    local elapsedSeconds = (nowHours - lastTriggerAtHours) * 3600
    return elapsedSeconds < COOLDOWN_SECONDS
end

local SOUND_SUFFIX_BY_VARIANT = {
    moodle = "PainMoodle",
    scratch = "PainFromScratch",
    lacerate = "PainFromLacerate",
    glasscut = "PainFromGlassCut",
}

local function normalizeVariant(value)
    local key = tostring(value or ""):lower():gsub("[^a-z]", "")
    if SOUND_SUFFIX_BY_VARIANT[key] then
        return key
    end
    return "scratch"
end

local function normalizeFunctionRoute(value)
    local key = tostring(value or ""):lower():gsub("[^a-z]", "")
    if key == "voice" or key == "transmit" or key == "localvoice" or key == "worldsound" then
        return key
    end
    return "voice"
end

local function getVoicePrefix(playerObj)
    if not playerObj or not playerObj.getDescriptor then
        return nil
    end

    local okDescriptor, descriptor = pcall(function()
        return playerObj:getDescriptor()
    end)
    if not okDescriptor or not descriptor or not descriptor.getVoicePrefix then
        return nil
    end

    local okPrefix, prefix = pcall(function()
        return descriptor:getVoicePrefix()
    end)
    if not okPrefix then
        return nil
    end
    return prefix
end

local function didPlaySound(result)
    return type(result) == "number" and result > 0
end

local function tryVoiceRoute(playerObj, route, suffix)
    if not playerObj then
        return false
    end

    if route == "voice" and playerObj.playerVoiceSound then
        local ok, result = pcall(function()
            return playerObj:playerVoiceSound(suffix)
        end)
        return ok and didPlaySound(result)
    end

    if route == "transmit" and playerObj.transmitPlayerVoiceSound then
        local ok, result = pcall(function()
            return playerObj:transmitPlayerVoiceSound(suffix)
        end)
        return ok and didPlaySound(result)
    end

    if route == "localvoice" and playerObj.playSoundLocal then
        local voicePrefix = getVoicePrefix(playerObj)
        if not voicePrefix then
            return false
        end
        local ok, result = pcall(function()
            return playerObj:playSoundLocal(voicePrefix .. suffix)
        end)
        return ok and didPlaySound(result)
    end

    if route == "worldsound" and playerObj.playSound then
        local voicePrefix = getVoicePrefix(playerObj)
        if not voicePrefix then
            return false
        end
        local ok, result = pcall(function()
            return playerObj:playSound(voicePrefix .. suffix)
        end)
        return ok and didPlaySound(result)
    end

    return false
end

local function playPainFeedback(playerObj, settings)
    local variant = normalizeVariant(FIXED_VARIANT)
    local route = normalizeFunctionRoute(FIXED_ROUTE)
    local suffix = SOUND_SUFFIX_BY_VARIANT[variant]

    if tryVoiceRoute(playerObj, route, suffix) then
        debugLog(settings, "audio route success: route=" .. tostring(route) .. " variant=" .. tostring(variant) .. " suffix=" .. tostring(suffix))
        return true
    end

    -- If the selected route fails on this runtime, fall back to primary voice route.
    if route ~= "voice" and tryVoiceRoute(playerObj, "voice", suffix) then
        debugLog(settings, "audio route fallback success: selected=" .. tostring(route) .. " fallback=voice variant=" .. tostring(variant) .. " suffix=" .. tostring(suffix))
        return true
    end

    -- Last fallback keeps original behavior for resilience.
    if playerObj and playerObj.playerVoiceSound then
        local ok, result = pcall(function()
            return playerObj:playerVoiceSound("PainMoodle")
        end)
        if ok and didPlaySound(result) then
            debugLog(settings, "audio route final fallback success: route=voice variant=moodle suffix=PainMoodle")
            return true
        end
    end


    return false
end

local function onPlayerGetDamage(playerObj, damageType, damageAmount)
    if not installed then
        return
    end

    if not playerObj or damageType ~= "HEAVYLOAD" then
        return
    end

    local settings = HeavyLoadHurtFeedback._settings
    if not settings or settings.isEnabled("QoLforSacriel_EnableUIFixes") ~= true then
        debugLog(settings, "suppressed: UI Fixes disabled")
        return
    end

    if settings.get("QoLforSacriel_UIFixes_EnableHeavyLoadHurtFeedback") ~= true then
        debugLog(settings, "suppressed: feature toggle disabled")
        return
    end

    if not isLocalPlayer(playerObj) then
        debugLog(settings, "suppressed: non-local player")
        return
    end

    local damage = tonumber(damageAmount) or 0
    if damage <= 0 then
        debugLog(settings, "suppressed: non-positive damage")
        return
    end

    local nowHours = getWorldAgeHours()
    if isCoolingDown(nowHours) then
        debugLog(settings, "suppressed: cooldown active")
        return
    end

    if playPainFeedback(playerObj, settings) then
        lastTriggerAtHours = nowHours or -1
        debugLog(settings, "triggered: heavy-load hurt feedback")
    else
        debugLog(settings, "suppressed: no playable pain sound route")
    end
end

function HeavyLoadHurtFeedback.init(settings, logger)
    if installed then
        if logger and logger.debug then
            logger.debug("UIFixes.HeavyLoadHurtFeedback already installed")
        end
        return
    end

    HeavyLoadHurtFeedback._settings = settings
    Events.OnPlayerGetDamage.Add(onPlayerGetDamage)
    installed = true

    if logger and logger.info then
        logger.info("UIFixes.HeavyLoadHurtFeedback installed")
    end
end

return HeavyLoadHurtFeedback