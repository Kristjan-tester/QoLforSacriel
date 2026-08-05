local HeavyLoadHurtFeedback = {}

local installed = false
local lastTriggerAtHours = -1
local COOLDOWN_SECONDS = 2.0
local PAIN_VOICE_SUFFIX = "PainFromGlassCut"

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

local function playPainFeedback(playerObj, settings)
    if not playerObj or not playerObj.playerVoiceSound then
        return "unavailable"
    end

    local ok, result = pcall(function()
        return playerObj:playerVoiceSound(PAIN_VOICE_SUFFIX)
    end)
    if not ok then
        return "unavailable"
    end
    if type(result) == "number" and result > 0 then
        debugLog(settings, "audio voice started: suffix=" .. PAIN_VOICE_SUFFIX)
        return "started"
    end

    -- Vanilla returns zero when this exact voice event is already playing.
    return "already-playing"
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

    local playbackResult = playPainFeedback(playerObj, settings)
    if playbackResult == "started" then
        lastTriggerAtHours = nowHours or -1
        debugLog(settings, "triggered: heavy-load hurt feedback")
    elseif playbackResult == "already-playing" then
        debugLog(settings, "suppressed: pain voice already playing")
    else
        debugLog(settings, "suppressed: pain voice API unavailable")
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