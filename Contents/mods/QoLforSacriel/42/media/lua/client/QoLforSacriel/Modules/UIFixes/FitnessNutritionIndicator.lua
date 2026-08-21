require "XpSystem/ISUI/ISCharacterInfoWindow"
require "XpSystem/ISUI/ISHealthPanel"
require "ISUI/ISPanel"
require "ISUI/ISButton"

-- ff-assisted

local FitnessNutritionIndicator = {}
local FitnessNutritionPanel = ISPanel:derive("FitnessNutritionPanel")

local BALANCE_CELL_COUNT = 10
local BALANCE_CELL_WIDTH = 18
local BALANCE_CELL_HEIGHT = 18
local UI_BORDER_SPACING = 10
local STRENGTH_PROTEIN_NEAR_BONUS_MIN = 1
local MIN_CALORIES = -2200
local MAX_CALORIES = 3700
local FITNESS_PANEL_INITIAL_HEIGHT = 250
local FATIGUE_ONSET_EPSILON = 0.0001
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local LAST_SLEEP_SESSION_KEY = "QoLforSacriel.SleepQuality.LastSession"
local LAST_SLEEP_SESSION_SCHEMA = 5

local installed = false
local originalCreateChildren = nil
local runtimeSettings = nil
local loggerRef = nil
local sleepSessions = {}
local invalidSavedSleepSessions = {}
local originalSleepDialogOnClick = nil
local originalContextSleep = nil
local originalContextSleepComplete = nil
local sleepDialogWrapped = false
local contextSleepWrapped = false
local contextSleepCompleteWrapped = false
local sleepWrapperRetryRegistered = false

local function getTextSafe(key, fallback)
    local value = getTextOrNull and getTextOrNull(key) or nil
    return value or fallback
end

local function logDebug(message)
    if runtimeSettings
        and runtimeSettings.get
        and runtimeSettings.get("QoLforSacriel_DebugLogs") == true
        and loggerRef
        and loggerRef.debug
    then
        loggerRef.debug("UIFixes.FitnessNutritionIndicator: " .. message)
    end
end

local function formatSleepNumber(value)
    local numberValue = tonumber(value)
    return numberValue and string.format("%.4f", numberValue) or "nil"
end

local function logSleepSnapshot(prefix, snapshot)
    if not snapshot then
        logDebug(prefix .. ": unavailable")
        return
    end
    logDebug(
        prefix
            .. ": worldAge=" .. formatSleepNumber(snapshot.worldAge)
            .. "; fatigue=" .. formatSleepNumber(snapshot.fatigue)
            .. "; endurance=" .. formatSleepNumber(snapshot.endurance)
            .. "; asleepTime=" .. formatSleepNumber(snapshot.asleepTime)
    )
end

local function isEnabled()
    return runtimeSettings
        and runtimeSettings.isEnabled
        and runtimeSettings.isEnabled("QoLforSacriel_EnableUIFixes") == true
        and runtimeSettings.get("QoLforSacriel_UIFixes_EnableFitnessNutritionIndicator") == true
end

local function showExactSleepStats()
    return runtimeSettings
        and runtimeSettings.get
        and runtimeSettings.get("QoLforSacriel_UIFixes_ShowExactSleepStats") == true
end

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

local function readFiniteNumber(target, methodName, ...)
    local ok, value = safeCall(target, methodName, ...)
    local numberValue = tonumber(value)
    if not ok or not numberValue or numberValue ~= numberValue or numberValue == math.huge or numberValue == -math.huge then
        return nil
    end
    return numberValue
end

local function readBoolean(target, methodName)
    local ok, value = safeCall(target, methodName)
    if not ok or type(value) ~= "boolean" then
        return nil
    end
    return value
end

local function hasTrait(playerObj, traitName)
    if not playerObj or not CharacterTrait or not CharacterTrait[traitName] then
        return false
    end
    local ok, value = safeCall(playerObj, "hasTrait", CharacterTrait[traitName])
    return ok and value == true
end

local function hasNutritionistTrait(playerObj)
    return hasTrait(playerObj, "NUTRITIONIST") or hasTrait(playerObj, "NUTRITIONIST2")
end

local function getWorldAgeHours()
    local gameTime = getGameTime and getGameTime() or nil
    return readFiniteNumber(gameTime, "getWorldAgeHours") or 0
end

local function getTimeOfDay()
    local gameTime = getGameTime and getGameTime() or nil
    return readFiniteNumber(gameTime, "getTimeOfDay")
end

local function getMoodleLevel(playerObj, moodleType)
    local moodlesOk, moodles = safeCall(playerObj, "getMoodles")
    if not moodlesOk or not moodles or not moodleType then
        return 0
    end
    return readFiniteNumber(moodles, "getMoodleLevel", moodleType) or 0
end

local function getFatigueRecoveryBedMultiplier(bedType)
    local multipliers = {
        averageBed = 1.00, averageBedPillow = 1.05, goodBed = 1.10, goodBedPillow = 1.15,
        badBed = 0.90, badBedPillow = 0.95, floor = 0.60, floorPillow = 0.75,
    }
    return multipliers[bedType] or 1.00
end

local function getOnsetBedMultiplier(bedType)
    local multipliers = {
        averageBed = 1.00, averageBedPillow = 1.00, goodBed = 0.80, goodBedPillow = 0.60,
        badBed = 1.30, badBedPillow = 1.25, floor = 1.60, floorPillow = 1.45,
    }
    return multipliers[bedType] or 1.00
end

local function getFitnessRecoveryMultiplier(fitnessLevel)
    local multipliers = {
        [0] = 0.70, [1] = 0.80, [2] = 0.90, [3] = 1.00, [4] = 1.10,
        [5] = 1.20, [6] = 1.30, [7] = 1.40, [8] = 1.50, [9] = 1.55, [10] = 1.60,
    }
    return multipliers[fitnessLevel]
end

local function getFatigueTraitRateMultiplier(start)
    local rateMultiplier = 1.0
    if start.needsLessSleep then
        rateMultiplier = rateMultiplier / 0.75
    elseif start.needsMoreSleep then
        rateMultiplier = rateMultiplier / 1.18
    end
    if start.insomniac then rateMultiplier = rateMultiplier * 0.5 end
    if start.nightOwl then rateMultiplier = rateMultiplier * 1.4 end
    return rateMultiplier
end

local function snapshotWakeEvidence(playerObj)
    local statsOk, stats = safeCall(playerObj, "getStats")
    if not statsOk or not stats then
        return nil
    end
    local bodyDamageOk, bodyDamage = safeCall(playerObj, "getBodyDamage")
    local neckOk, neckPart = false, nil
    if bodyDamageOk and bodyDamage and BodyPartType and BodyPartType.Neck then
        neckOk, neckPart = safeCall(bodyDamage, "getBodyPart", BodyPartType.Neck)
    end
    return {
        panic = readFiniteNumber(stats, "get", CharacterStat.PANIC) or 0,
        stress = readFiniteNumber(stats, "get", CharacterStat.STRESS) or 0,
        visibleZombies = readFiniteNumber(stats, "getNumVisibleZombies") or 0,
        chasingZombies = readFiniteNumber(stats, "getNumChasingZombies") or 0,
        veryCloseZombies = readFiniteNumber(stats, "getNumVeryCloseZombies") or 0,
        hypothermia = getMoodleLevel(playerObj, MoodleType.HYPOTHERMIA),
        hyperthermia = getMoodleLevel(playerObj, MoodleType.HYPERTHERMIA),
        neckHealth = neckOk and readFiniteNumber(neckPart, "getHealth") or nil,
        neckPain = neckOk and readFiniteNumber(neckPart, "getAdditionalPain") or nil,
    }
end

local function classifyWakeReason(session)
    local evidence = session.wakeEvidence or {}
    local previous = evidence.lastAsleep or evidence.start
    local wake = evidence.firstWake
    if not previous or not wake then
        return nil, "Unavailable"
    end
    local panicDelta = wake.panic - previous.panic
    local stressDelta = wake.stress - previous.stress
    local earlyWake = session.requestedHours and session.actualHours < session.requestedHours - 0.1
    local coldWake = earlyWake and evidence.hypothermiaThresholdRise and wake.hypothermia >= 3
    local heatWake = earlyWake and evidence.hyperthermiaThresholdRise and wake.hyperthermia >= 3
    local eventSignature = earlyWake and panicDelta >= 70
    local zombieEvidence = previous.veryCloseZombies > 0
    if coldWake and heatWake then
        logDebug("simultaneous cold and heat wake evidence; using Cold to match vanilla temperature check order")
    end
    if coldWake then
        return "Cold", "Inferred"
    end
    if heatWake then
        return "Heat", "Inferred"
    end
    if eventSignature and zombieEvidence then
        return "Zombie", "Inferred"
    end
    if eventSignature then
        return "Nightmare", "Inferred"
    end
    if earlyWake then
        return "Alarm", "Inferred"
    end
    if session.requestedHours and math.abs(session.actualHours - session.requestedHours) <= 0.1 then
        return "Normal", "Scheduled"
    end
    return nil, "Unavailable"
end

local function wasWokenEarly(session)
    return session.requestedHours
        and session.actualHours
        and session.actualHours < session.requestedHours - 0.1
end

local function snapshotSleepStart(playerObj)
    local statsOk, stats = safeCall(playerObj, "getStats")
    if not statsOk or not stats then
        return nil
    end
    local bedTypeOk, bedTypeValue = safeCall(playerObj, "getBedType")
    return {
        worldAge = getWorldAgeHours(),
        fatigue = readFiniteNumber(stats, "get", CharacterStat.FATIGUE),
        endurance = readFiniteNumber(stats, "get", CharacterStat.ENDURANCE),
        asleepTime = readFiniteNumber(playerObj, "getAsleepTime") or 0,
        pain = getMoodleLevel(playerObj, MoodleType.PAIN),
        stress = getMoodleLevel(playerObj, MoodleType.STRESS),
        bedType = bedTypeOk and tostring(bedTypeValue) or "averageBed",
        fitness = PerkFactory and PerkFactory.Perks and readFiniteNumber(playerObj, "getPerkLevel", PerkFactory.Perks.Fitness) or nil,
        recoveryMod = readFiniteNumber(playerObj, "getRecoveryMod"),
        insomniac = hasTrait(playerObj, "INSOMNIAC"),
        nightOwl = hasTrait(playerObj, "NIGHT_OWL"),
        needsLessSleep = hasTrait(playerObj, "NEEDS_LESS_SLEEP"),
        needsMoreSleep = hasTrait(playerObj, "NEEDS_MORE_SLEEP"),
        desensitized = hasTrait(playerObj, "DESENSITIZED"),
        sleepTraitEffectsVersion = 1,
        obese = hasTrait(playerObj, "OBESE"),
        overweight = hasTrait(playerObj, "OVERWEIGHT"),
        veryUnderweight = hasTrait(playerObj, "VERY_UNDERWEIGHT"),
        emaciated = hasTrait(playerObj, "EMACIATED"),
        enduranceTraitEffectsVersion = 1,
        sleepingTabletEffect = readFiniteNumber(playerObj, "getSleepingTabletEffect") or 0,
    }
end

local function snapshotSleepProgress(playerObj, worldAge)
    local statsOk, stats = safeCall(playerObj, "getStats")
    if not statsOk or not stats then
        return nil
    end
    return {
        worldAge = worldAge,
        fatigue = readFiniteNumber(stats, "get", CharacterStat.FATIGUE),
        endurance = readFiniteNumber(stats, "get", CharacterStat.ENDURANCE),
        asleepTime = readFiniteNumber(playerObj, "getAsleepTime") or 0,
    }
end

local function getSleepSession(playerObj)
    return sleepSessions[playerObj:getPlayerNum() or 0]
end

local function saveLastSleepSession(playerObj, session)
    local modDataOk, modData = safeCall(playerObj, "getModData")
    if not modData then
        logDebug("last sleep result was not saved: player mod data unavailable")
        return
    end
    modData[LAST_SLEEP_SESSION_KEY] = {
        schema = LAST_SLEEP_SESSION_SCHEMA,
        status = session.status,
        score = session.score,
        contributor = session.contributor,
        contributorPositive = session.contributorPositive,
        contributorNegative = session.contributorNegative,
        wakeReason = session.wakeReason,
        wakeConfidence = session.wakeConfidence,
        onsetLabel = session.onsetLabel,
        onsetContributor = session.onsetContributor,
        onsetDelay = session.onsetDelay,
        onsetEstimate = session.onsetEstimate,
        medicationOverride = session.medicationOverride == true,
        actualHours = session.actualHours,
        requestedHours = session.requestedHours,
        fatigueRemoved = session.fatigueRemoved,
        enduranceGained = session.enduranceGained,
        start = {
            bedType = session.start.bedType,
            endurance = session.start.endurance,
            pain = session.start.pain,
            stress = session.start.stress,
            fitness = session.start.fitness,
            recoveryMod = session.start.recoveryMod,
            insomniac = session.start.insomniac == true,
            nightOwl = session.start.nightOwl == true,
            needsLessSleep = session.start.needsLessSleep == true,
            needsMoreSleep = session.start.needsMoreSleep == true,
            desensitized = session.start.desensitized == true,
            sleepTraitEffectsVersion = session.start.sleepTraitEffectsVersion,
            obese = session.start.obese == true,
            overweight = session.start.overweight == true,
            veryUnderweight = session.start.veryUnderweight == true,
            emaciated = session.start.emaciated == true,
            enduranceTraitEffectsVersion = session.start.enduranceTraitEffectsVersion,
            fatigueTraitRateMultiplier = session.start.fatigueTraitRateMultiplier,
            sleepingTabletEffect = session.start.sleepingTabletEffect,
        },
        finish = {
            endurance = session.finish and session.finish.endurance,
        },
        components = {
            fatigue = session.components and session.components.fatigue,
            neckHarm = session.components and session.components.neckHarm == true,
        },
    }
    invalidSavedSleepSessions[playerObj:getPlayerNum() or 0] = nil
    logDebug("last sleep result saved")
end

local function getSavedSleepSession(playerObj)
    local playerNum = playerObj:getPlayerNum() or 0
    local modDataOk, modData = safeCall(playerObj, "getModData")
    local saved = modDataOk and modData and modData[LAST_SLEEP_SESSION_KEY] or nil
    local invalidReason = nil
    if type(saved) ~= "table" then
        invalidReason = "record is not a table"
    elseif saved.schema ~= LAST_SLEEP_SESSION_SCHEMA then
        invalidReason = "schema expected " .. tostring(LAST_SLEEP_SESSION_SCHEMA) .. ", got " .. tostring(saved.schema)
    elseif type(saved.status) ~= "string" then
        invalidReason = "status is not a string"
    elseif type(saved.start) ~= "table" then
        invalidReason = "start is not a table"
    elseif type(saved.finish) ~= "table" then
        invalidReason = "finish is not a table"
    elseif type(saved.components) ~= "table" then
        invalidReason = "components is not a table"
    end
    if invalidReason then
        if saved and not invalidSavedSleepSessions[playerNum] then
            invalidSavedSleepSessions[playerNum] = true
            logDebug("saved sleep result ignored: " .. invalidReason)
        end
        return nil
    end
    invalidSavedSleepSessions[playerNum] = nil
    return saved
end

local function beginSleepSession(playerObj, requestedHours)
    local start = snapshotSleepStart(playerObj)
    if not start then
        return
    end
    start.fatigueTraitRateMultiplier = getFatigueTraitRateMultiplier(start)
    local playerNum = playerObj:getPlayerNum() or 0
    sleepSessions[playerNum] = {
        active = true,
        requestedHours = tonumber(requestedHours),
        start = start,
        last = start,
        fatigueRemoved = 0,
        enduranceGained = 0,
        fatigueObserved = false,
        enduranceObserved = false,
        lastSampleWorldAge = start.worldAge,
        wakeEvidence = { start = snapshotWakeEvidence(playerObj) },
    }
    logDebug("sleep session started for player " .. tostring(playerNum) .. "; requested hours=" .. tostring(requestedHours))
    logSleepSnapshot("sleep start snapshot", start)
    logDebug(
        "sleep start inputs: bed=" .. tostring(start.bedType)
            .. "; pain=" .. tostring(start.pain)
            .. "; stress=" .. tostring(start.stress)
            .. "; fitness=" .. tostring(start.fitness)
            .. "; recoveryMod=" .. formatSleepNumber(start.recoveryMod)
            .. "; insomniac=" .. tostring(start.insomniac)
            .. "; nightOwl=" .. tostring(start.nightOwl)
            .. "; lessSleep=" .. tostring(start.needsLessSleep)
            .. "; moreSleep=" .. tostring(start.needsMoreSleep)
            .. "; desensitized=" .. tostring(start.desensitized)
            .. "; tablet=" .. formatSleepNumber(start.sleepingTabletEffect)
    )
end

local function sleepContributors(session)
    local candidates = {
        { label = "Bed quality", effect = getFatigueRecoveryBedMultiplier(session.start.bedType) - 1 },
        { label = "Trait", effect = (session.start.fatigueTraitRateMultiplier or 1.0) - 1.0 },
    }
    local positive = nil
    local negative = nil
    local absolute = nil
    for _, candidate in ipairs(candidates) do
        if candidate.effect > 0 and (not positive or candidate.effect > positive.effect) then
            positive = candidate
        end
        if candidate.effect < 0 and (not negative or candidate.effect < negative.effect) then
            negative = candidate
        end
        if candidate.effect ~= 0 and (not absolute or math.abs(candidate.effect) > math.abs(absolute.effect)) then
            absolute = candidate
        end
    end
    return positive, negative, absolute
end

local function selectSleepContributors(session)
    local interrupted = session.requestedHours
        and session.requestedHours > 0
        and session.actualHours
        and session.actualHours < session.requestedHours / 3
    if interrupted then
        return "Interrupted", nil, nil
    end
    local positive, negative, absolute = sleepContributors(session)
    if session.status == "Average" then
        return nil, positive and positive.label or (absolute and absolute.label or "None"), negative and negative.label or (absolute and absolute.label or "None")
    end
    if session.status == "VeryBad" or session.status == "Bad" then
        return (negative or absolute or { label = "None" }).label, nil, nil
    end
    if session.status == "Good" or session.status == "VeryGood" then
        return (positive or absolute or { label = "None" }).label, nil, nil
    end
    return (absolute or { label = "None" }).label, nil, nil
end

local function onsetModel(session)
    local start = session.start
    if start.sleepingTabletEffect > 1000 then
        return "Quick", "Medication", 0.1, true
    end
    local delay = start.insomniac and 1.0 or 0.3
    local traitImpact = start.insomniac and 0.7 or (start.nightOwl and 0.5 or 0)
    local contributor = traitImpact > 0 and "Trait" or "None"
    local largestImpact = traitImpact
    if start.pain > 0 then
        local painImpact = 1.0 + start.pain * 0.2
        delay = delay + painImpact
        if painImpact > largestImpact then contributor, largestImpact = "Pain", painImpact end
    end
    if start.stress > 0 then
        delay = delay * 1.2
        if 0.2 > largestImpact then contributor, largestImpact = "Stress", 0.2 end
    end
    local bedMultiplier = getOnsetBedMultiplier(start.bedType)
    local bedImpact = math.abs(bedMultiplier - 1)
    if bedImpact > largestImpact then contributor, largestImpact = "Bed quality", bedImpact end
    delay = delay * bedMultiplier
    if start.nightOwl then delay = delay * 0.5 end
    delay = math.min(2.0, delay)
    local ratio = delay / 0.3
    local label = ratio < 0.85 and "Quick" or (ratio > 1.15 and "Slow" or "Normal")
    return label, contributor, delay, false
end

local function getOnsetBaseline(start)
    local baseline = start.insomniac and 1.0 or 0.3
    if start.nightOwl then baseline = baseline * 0.5 end
    return baseline
end

local function getOnsetComparison(session)
    local onsetEstimate = tonumber(session.onsetEstimate)
    if not onsetEstimate then
        return nil, nil
    end
    local baseline = getOnsetBaseline(session.start)
    local ratio = onsetEstimate / baseline
    local comparison = ratio < 0.85 and "Quicker" or (ratio > 1.15 and "Slower" or "AsUsual")
    if comparison == "AsUsual" then
        return comparison, nil
    end
    if session.medicationOverride then
        return comparison, "Medication"
    end
    local candidates = {}
    local pain = tonumber(session.start.pain) or 0
    local stress = tonumber(session.start.stress) or 0
    if pain > 0 then
        table.insert(candidates, { label = "Pain", effect = (1.0 + pain * 0.2) / baseline })
    end
    if stress > 0 then
        table.insert(candidates, { label = "Stress", effect = 0.2 })
    end
    local bedEffect = math.abs(getOnsetBedMultiplier(session.start.bedType) - 1)
    if bedEffect > 0 then
        table.insert(candidates, { label = "Bed quality", effect = bedEffect })
    end
    local contributor = nil
    for _, candidate in ipairs(candidates) do
        if not contributor or candidate.effect > contributor.effect then contributor = candidate end
    end
    if contributor and onsetEstimate < baseline * 0.5 then
        return comparison, "Random"
    end
    if not contributor and comparison == "Quicker" then
        return comparison, "Random"
    end
    return comparison, contributor and contributor.label or nil
end

local function expectedFatigueRecovery(start, recoveryHours, initialFatigue)
    local fatigueAtReference = initialFatigue or start.fatigue
    if not fatigueAtReference or fatigueAtReference <= 0 or recoveryHours <= 0 then
        return nil
    end
    local traitRateMultiplier = start.fatigueTraitRateMultiplier
    if not traitRateMultiplier or traitRateMultiplier <= 0 then
        return nil
    end
    local recoveryMultiplier = 1.0

    local fatigue = fatigueAtReference
    local hoursLeft = recoveryHours
    local removed = 0
    if fatigue > 0.3 then
        local highRate = (0.7 / 5.0) * traitRateMultiplier * recoveryMultiplier
        local highHours = math.min(hoursLeft, (fatigue - 0.3) / highRate)
        local highRemoved = highHours * highRate
        fatigue = fatigue - highRemoved
        hoursLeft = hoursLeft - highHours
        removed = removed + highRemoved
    end
    if fatigue > 0 and hoursLeft > 0 then
        local lowRate = (0.3 / 7.0) * traitRateMultiplier * recoveryMultiplier
        local lowHours = math.min(hoursLeft, fatigue / lowRate)
        removed = removed + lowHours * lowRate
    end
    return removed > 0 and removed or nil
end

local function calculateScore(session)
    local referenceStart = session.fatigueReferenceStart
    local expectedRecoveryHours = referenceStart and session.actualHours
        and math.max(0, session.actualHours - referenceStart.elapsedHours)
        or 0
    local expectedFatigue = referenceStart and expectedFatigueRecovery(session.start, expectedRecoveryHours, referenceStart.fatigue) or nil
    local components = {}
    if session.fatigueObserved and expectedFatigue then
        local fatigue = math.min(1.5, session.fatigueRemoved / expectedFatigue)
        components.fatigue = fatigue
        local category = fatigue < 0.25 and 1
            or (fatigue < 0.75 and 2
            or (fatigue < 0.85 and 3
            or (fatigue <= 1.02 and 4 or 5)))
        local neckHarm = (session.neckHealthDelta or 0) < 0 or (session.neckPainDelta or 0) > 0
        if neckHarm then
            category = math.max(1, category - 1)
        end
        components.neckHarm = neckHarm
        session.status = ({ "VeryBad", "Bad", "Average", "Good", "VeryGood" })[category]
    end

    session.components = components
    session.score = components.fatigue
    logDebug(
        "score inputs: actual=" .. formatSleepNumber(session.actualHours)
            .. "; referenceElapsed=" .. formatSleepNumber(referenceStart and referenceStart.elapsedHours)
            .. "; expectedRecoveryHours=" .. formatSleepNumber(expectedRecoveryHours)
            .. "; fatigueRemoved=" .. formatSleepNumber(session.fatigueRemoved)
            .. "; expectedFatigue=" .. formatSleepNumber(expectedFatigue)
            .. "; fatigueRatio=" .. formatSleepNumber(components.fatigue)
            .. "; neckHarm=" .. tostring(components.neckHarm)
            .. "; status=" .. tostring(session.status)
    )
end

local function recordSleepProgress(session, playerObj, current, captureWakeEvidence)
    if not current or current.worldAge <= (session.lastSampleWorldAge or 0) then
        return false
    end
    local elapsedHours = current.worldAge - session.start.worldAge
    local previous = session.last
    local referenceJustCaptured = false
    if not session.fatigueReferenceStart
        and previous
        and previous.fatigue
        and current.fatigue
        and current.fatigue < previous.fatigue - FATIGUE_ONSET_EPSILON then
        local onsetMinimum = math.max(0, (previous.worldAge or session.start.worldAge) - session.start.worldAge)
        local onsetMaximum = math.max(onsetMinimum, elapsedHours)
        session.onsetEstimate = (onsetMinimum + onsetMaximum) / 2
        session.fatigueReferenceStart = {
            fatigue = (previous.fatigue + current.fatigue) / 2,
            elapsedHours = session.onsetEstimate,
        }
        session.fatigueObserved = true
        session.fatigueRemoved = math.max(0, session.fatigueReferenceStart.fatigue - current.fatigue)
        referenceJustCaptured = true
        logDebug(
            "fatigue onset inferred: min=" .. formatSleepNumber(onsetMinimum)
                .. "; max=" .. formatSleepNumber(onsetMaximum)
                .. "; estimate=" .. formatSleepNumber(session.onsetEstimate)
                .. "; referenceFatigue=" .. formatSleepNumber(session.fatigueReferenceStart.fatigue)
        )
    end
    if session.fatigueReferenceStart and not referenceJustCaptured and current.fatigue and previous.fatigue then
        session.fatigueObserved = true
        session.fatigueRemoved = math.max(0, session.fatigueReferenceStart.fatigue - current.fatigue)
    end
    if current.endurance and previous.endurance then
        session.enduranceObserved = true
        if current.endurance > previous.endurance then
            session.enduranceGained = session.enduranceGained + (current.endurance - previous.endurance)
        end
    end
    session.last = current
    session.lastSampleWorldAge = current.worldAge
    if captureWakeEvidence ~= false then
        local wakeEvidence = session.wakeEvidence
        local previousWakeEvidence = wakeEvidence.lastAsleep or wakeEvidence.start
        local currentWakeEvidence = snapshotWakeEvidence(playerObj)
        if currentWakeEvidence then
            if previousWakeEvidence then
                if currentWakeEvidence.hypothermia >= 3 and currentWakeEvidence.hypothermia > previousWakeEvidence.hypothermia then
                    wakeEvidence.hypothermiaThresholdRise = true
                end
                if currentWakeEvidence.hyperthermia >= 3 and currentWakeEvidence.hyperthermia > previousWakeEvidence.hyperthermia then
                    wakeEvidence.hyperthermiaThresholdRise = true
                end
            end
            wakeEvidence.lastAsleep = currentWakeEvidence
        end
    end
    return true
end

local function finaliseSleepSession(playerObj)
    local session = getSleepSession(playerObj)
    if not session or not session.active then
        return
    end
    session.active = false
    local finishWorldAge = getWorldAgeHours()
    local finish = snapshotSleepProgress(playerObj, finishWorldAge)
    recordSleepProgress(session, playerObj, finish, false)
    session.finish = session.last
    session.wakeEvidence.firstWake = snapshotWakeEvidence(playerObj)
    session.actualHours = math.max(0, (session.finish.worldAge or 0) - (session.start.worldAge or 0))
    local onsetLabel, onsetContributor, onsetDelay, medicationOverride = onsetModel(session)
    session.onsetLabel = onsetLabel
    session.onsetContributor = onsetContributor
    session.onsetDelay = onsetDelay
    session.medicationOverride = medicationOverride
    logSleepSnapshot("sleep finish snapshot", session.finish)
    logDebug(
        "onset calculation: label=" .. tostring(onsetLabel)
            .. "; contributor=" .. tostring(onsetContributor)
            .. "; maximum=" .. formatSleepNumber(onsetDelay)
            .. "; estimate=" .. formatSleepNumber(session.onsetEstimate)
            .. "; medicationOverride=" .. tostring(medicationOverride)
    )
    session.wakeReason, session.wakeConfidence = classifyWakeReason(session)
    local lastAsleepEvidence = session.wakeEvidence.lastAsleep or session.wakeEvidence.start
    local wakeEvidence = session.wakeEvidence.firstWake
    if lastAsleepEvidence and wakeEvidence then
        session.neckHealthDelta = (wakeEvidence.neckHealth or 0) - (lastAsleepEvidence.neckHealth or 0)
        session.neckPainDelta = (wakeEvidence.neckPain or 0) - (lastAsleepEvidence.neckPain or 0)
        logDebug(
            "wake evidence: panicDelta=" .. formatSleepNumber(wakeEvidence.panic - lastAsleepEvidence.panic)
                .. "; stressDelta=" .. formatSleepNumber(wakeEvidence.stress - lastAsleepEvidence.stress)
                .. "; zombies=" .. tostring(lastAsleepEvidence.visibleZombies) .. "/" .. tostring(lastAsleepEvidence.chasingZombies) .. "/" .. tostring(lastAsleepEvidence.veryCloseZombies)
                .. "; hypothermia=" .. tostring(lastAsleepEvidence.hypothermia) .. "/" .. tostring(wakeEvidence.hypothermia)
                .. " (delta=" .. formatSleepNumber(wakeEvidence.hypothermia - lastAsleepEvidence.hypothermia) .. ")"
                .. "; hypothermiaThresholdRise=" .. tostring(session.wakeEvidence.hypothermiaThresholdRise == true)
                .. "; hyperthermia=" .. tostring(lastAsleepEvidence.hyperthermia) .. "/" .. tostring(wakeEvidence.hyperthermia)
                .. " (delta=" .. formatSleepNumber(wakeEvidence.hyperthermia - lastAsleepEvidence.hyperthermia) .. ")"
                .. "; hyperthermiaThresholdRise=" .. tostring(session.wakeEvidence.hyperthermiaThresholdRise == true)
                .. "; neckHealthDelta=" .. formatSleepNumber(session.neckHealthDelta)
                .. "; neckPainDelta=" .. formatSleepNumber(session.neckPainDelta)
                .. "; reason=" .. tostring(session.wakeReason)
                .. "; confidence=" .. tostring(session.wakeConfidence)
        )
    end
    if session.actualHours < (session.onsetEstimate or onsetDelay) then
        session.status = "Woke before deep sleep"
        session.contributor, session.contributorPositive, session.contributorNegative = selectSleepContributors(session)
        session.components = session.components or {}
        session.components.neckHarm = (session.neckHealthDelta or 0) < 0 or (session.neckPainDelta or 0) > 0
        saveLastSleepSession(playerObj, session)
        return
    end
    calculateScore(session)
    if not session.requestedHours or session.requestedHours <= 0 then
        session.score = nil
        session.status = "Partial"
    elseif not session.score then
        session.status = "Partial"
    end
    session.contributor, session.contributorPositive, session.contributorNegative = selectSleepContributors(session)
    saveLastSleepSession(playerObj, session)
    if not session.loggedFirstSleepTick then
        logDebug("no OnSleepingTick sample received; recovery components unavailable")
    elseif not session.fatigueReferenceStart then
        logDebug("no fatigue decrease observed; onset estimate and fatigue recovery unavailable")
    end
    logDebug(
        "sleep session completed: status=" .. tostring(session.status)
            .. "; score=" .. formatSleepNumber(session.score)
            .. "; fatigueRemoved=" .. formatSleepNumber(session.fatigueRemoved)
            .. "; enduranceGained=" .. formatSleepNumber(session.enduranceGained)
            .. "; fatigueObserved=" .. tostring(session.fatigueObserved)
            .. "; enduranceObserved=" .. tostring(session.enduranceObserved)
            .. "; contributor=" .. tostring(session.contributor)
            .. "; contributorPositive=" .. tostring(session.contributorPositive)
            .. "; contributorNegative=" .. tostring(session.contributorNegative)
    )
end

local function updateSleepSession(playerObj)
    local session = getSleepSession(playerObj)
    if playerObj:isAsleep() then
        if not session or not session.active then beginSleepSession(playerObj, nil) end
        return
    end
    if session and session.active then finaliseSleepSession(playerObj) end
end

local function sampleSleepingPlayer(playerIndex)
    local playerObj = getSpecificPlayer and getSpecificPlayer(playerIndex) or nil
    local session = playerObj and getSleepSession(playerObj) or nil
    if not playerObj or not playerObj:isAsleep() or not session or not session.active then return end
    local worldAge = getWorldAgeHours()
    if worldAge <= (session.lastSampleWorldAge or 0) then return end
    local current = snapshotSleepProgress(playerObj, worldAge)
    if not session.loggedFirstSleepTick and current then
        session.loggedFirstSleepTick = true
        logDebug("first OnSleepingTick sample received for player " .. tostring(playerIndex))
    end
    recordSleepProgress(session, playerObj, current)
end

local function getFitnessXpBlockReason(playerObj)
    if not playerObj or not PerkFactory or not PerkFactory.Perks or not PerkFactory.Perks.Fitness then
        return nil
    end

    local fitnessLevelOk, fitnessLevelValue = safeCall(playerObj, "getPerkLevel", PerkFactory.Perks.Fitness)
    local fitnessLevel = fitnessLevelOk and tonumber(fitnessLevelValue) or nil
    if not fitnessLevel then
        return nil
    end
    fitnessLevel = math.floor(fitnessLevel)

    local emaciated = hasTrait(playerObj, "EMACIATED")
    local veryUnderweight = hasTrait(playerObj, "VERY_UNDERWEIGHT")
    local obese = hasTrait(playerObj, "OBESE")
    local underweight = hasTrait(playerObj, "UNDERWEIGHT")
    local overweight = hasTrait(playerObj, "OVERWEIGHT")

    if fitnessLevel >= 9 and (emaciated or veryUnderweight or obese or underweight or overweight) then
        return getTextSafe("UI_QoLforSacriel_FitnessXpBlocked", "Fitness XP blocked by current weight trait")
    end
    if fitnessLevel >= 6 and (emaciated or veryUnderweight or obese) then
        return getTextSafe("UI_QoLforSacriel_FitnessXpBlocked", "Fitness XP blocked by current weight trait")
    end
    return nil
end

local function getBalanceState(calories, lossThreshold, gainThreshold)
    if calories >= lossThreshold and calories <= gainThreshold then
        return nil, getTextSafe("UI_QoLforSacriel_FitnessBalance_Maintain", "Maintain")
    end

    if calories < lossThreshold then
        local range = lossThreshold - MIN_CALORIES
        if range <= 0 then
            return nil, getTextSafe("UI_QoLforSacriel_FitnessBalance_Maintain", "Maintain")
        end
        local fraction = (calories - MIN_CALORIES) / range
        local index = math.max(1, math.min(4, math.floor(fraction * 4) + 1))
        return index, getTextSafe("UI_QoLforSacriel_FitnessBalance_Loss", "Loss")
    end

    local range = MAX_CALORIES - gainThreshold
    if range <= 0 then
        return nil, getTextSafe("UI_QoLforSacriel_FitnessBalance_Maintain", "Maintain")
    end
    local fraction = (calories - gainThreshold) / range
    local index = 5 + math.max(1, math.min(5, math.floor(fraction * 5) + 1))
    return index, getTextSafe("UI_QoLforSacriel_FitnessBalance_Gain", "Gain")
end

local function getNutritionistTooltip(model)
    if not model.nutritionist then
        return nil
    end

    local toGain = math.max(0, model.gainThreshold - model.calories)
    local toLoss = math.max(0, model.calories - model.lossThreshold)
    return string.format(
        "%s: %.0f\n%s: %.0f\n%s: %.0f\n%s: %.0f\n%s: %.0f\n%s: %.0f\n%s: x%d",
        getTextSafe("UI_QoLforSacriel_FitnessTooltip_Calories", "Calories"), model.calories,
        getTextSafe("UI_QoLforSacriel_FitnessTooltip_Protein", "Protein"), model.proteins,
        getTextSafe("UI_QoLforSacriel_FitnessTooltip_Lipids", "Lipids"), model.lipids,
        getTextSafe("UI_QoLforSacriel_FitnessTooltip_GainGap", "Calories to gain"), toGain,
        getTextSafe("UI_QoLforSacriel_FitnessTooltip_LossGap", "Calories to loss"), toLoss,
        getTextSafe("UI_QoLforSacriel_FitnessTooltip_GainThreshold", "Gain threshold"), model.gainThreshold,
        getTextSafe("UI_QoLforSacriel_FitnessTooltip_GainMultiplier", "Gain multiplier"), model.gainMultiplier
    )
end

local function getNutritionModel(playerObj)
    local nutritionOk, nutrition = safeCall(playerObj, "getNutrition")
    if not nutritionOk or not nutrition then
        return { available = false }
    end

    local calories = readFiniteNumber(nutrition, "getCalories")
    local weight = readFiniteNumber(nutrition, "getWeight")
    local carbohydrates = readFiniteNumber(nutrition, "getCarbohydrates")
    local lipids = readFiniteNumber(nutrition, "getLipids")
    local proteins = readFiniteNumber(nutrition, "getProteins")
    if not calories or not weight or not carbohydrates or not lipids or not proteins then
        return { available = false }
    end

    local gainBase = 1000
    if weight < 90 and hasTrait(playerObj, "WEIGHT_GAIN") then
        gainBase = 700
    end
    if weight > 70 and hasTrait(playerObj, "WEIGHT_LOSS") then
        gainBase = 1800
    end

    local gainThreshold = gainBase + ((weight - 80) * 40)
    local lossThreshold = math.min((weight - 70) * 30, 0)
    local gainMultiplier = 1
    if carbohydrates > 700 or lipids > 700 then
        gainMultiplier = 3
    elseif carbohydrates > 400 or lipids > 400 then
        gainMultiplier = 2
    end

    local strengthColor = "red"
    local strengthReason = getTextSafe("UI_QoLforSacriel_FitnessStrength_Red", "Protein is not near the Strength XP bonus range")
    if proteins >= 300 then
        strengthColor = "purple"
        strengthReason = getTextSafe("UI_QoLforSacriel_FitnessStrength_Purple", "Protein is above the Strength XP bonus range")
    elseif proteins > 50 then
        strengthColor = "green"
        strengthReason = getTextSafe("UI_QoLforSacriel_FitnessStrength_Green", "Strength XP protein bonus active (+50%)")
    elseif proteins >= STRENGTH_PROTEIN_NEAR_BONUS_MIN then
        strengthColor = "yellow"
        strengthReason = getTextSafe("UI_QoLforSacriel_FitnessStrength_Yellow", "Protein is near the Strength XP bonus range")
    elseif proteins < -300 then
        strengthReason = getTextSafe("UI_QoLforSacriel_FitnessStrength_Penalty", "Strength XP penalty active (-30%)")
    elseif proteins >= -300 then
        strengthColor = "grey"
        strengthReason = getTextSafe("UI_QoLforSacriel_FitnessStrength_Grey", "Protein has no Strength XP modifier")
    end

    local fitnessXpBlockReason = getFitnessXpBlockReason(playerObj)
    local fitnessColor = "green"
    local fitnessReason = getTextSafe("UI_QoLforSacriel_FitnessEndurance_Green", "Fitness XP is allowed at current weight")
    if fitnessXpBlockReason then
        fitnessColor = "red"
        fitnessReason = fitnessXpBlockReason
    end

    local balanceIndex, balanceLabel = getBalanceState(calories, lossThreshold, gainThreshold)
    if balanceIndex and balanceIndex > 5 and gainMultiplier > 1 then
        if gainMultiplier == 3 then
            balanceLabel = getTextSafe("UI_QoLforSacriel_FitnessBalance_GainTriple", "Gain (3x carbohydrates/lipids)")
        else
            balanceLabel = getTextSafe("UI_QoLforSacriel_FitnessBalance_GainDouble", "Gain (2x carbohydrates/lipids)")
        end
    end
    return {
        available = true,
        balanceIndex = balanceIndex,
        balanceLabel = balanceLabel,
        calories = calories,
        carbohydrates = carbohydrates,
        gainMultiplier = gainMultiplier,
        gainThreshold = gainThreshold,
        lossThreshold = lossThreshold,
        nutritionist = hasNutritionistTrait(playerObj),
        proteins = proteins,
        lipids = lipids,
        strengthColor = strengthColor,
        strengthReason = strengthReason,
        fitnessColor = fitnessColor,
        fitnessReason = fitnessReason,
    }
end

local COLORS = {
    red = { r = 0.79, g = 0.21, b = 0.20 },
    yellow = { r = 0.91, g = 0.73, b = 0.18 },
    green = { r = 0.24, g = 0.67, b = 0.34 },
    purple = { r = 0.60, g = 0.33, b = 0.74 },
    grey = { r = 0.48, g = 0.50, b = 0.52 },
    neutral = { r = 0, g = 0, b = 0 },
    cellBorder = { r = 0.48, g = 0.50, b = 0.52 },
}

local function getSleepBedLabel(bedType)
    local labels = {
        averageBed = "Average bed", averageBedPillow = "Average bed",
        goodBed = "Good bed", goodBedPillow = "Good bed",
        badBed = "Bad bed", badBedPillow = "Bad bed",
        floor = "Floor", floorPillow = "Floor",
    }
    return getTextSafe("UI_QoLforSacriel_SleepQuality_Bed_" .. tostring(bedType), labels[bedType] or tostring(bedType))
end

local function getSleepTraitExactRows(start)
    if start.sleepTraitEffectsVersion ~= 1 then
        return nil
    end
    local fatigueLabel = getTextSafe("UI_QoLforSacriel_SleepQuality_ExactTraitFatigue", "Fatigue")
    local onsetLabel = getTextSafe("UI_QoLforSacriel_SleepQuality_ExactTraitOnsetMax", "Onset max")
    local nightmareLabel = getTextSafe("UI_QoLforSacriel_SleepQuality_ExactTraitNightmare", "Nightmare")
    local rows = {}
    if start.insomniac then
        table.insert(rows, getTextSafe("UI_QoLforSacriel_SleepQuality_Trait_Insomniac", "Insomniac") .. " - " .. fatigueLabel .. " x0.50 | " .. onsetLabel .. " x3.33")
    end
    if start.nightOwl then
        table.insert(rows, getTextSafe("UI_QoLforSacriel_SleepQuality_Trait_NightOwl", "Night Owl") .. " - " .. fatigueLabel .. " x1.40 | " .. onsetLabel .. " x0.50")
    end
    if start.needsLessSleep then
        table.insert(rows, getTextSafe("UI_QoLforSacriel_SleepQuality_Trait_LessSleep", "Needs Less Sleep") .. " - " .. fatigueLabel .. " x1.33")
    elseif start.needsMoreSleep then
        table.insert(rows, getTextSafe("UI_QoLforSacriel_SleepQuality_Trait_MoreSleep", "Needs More Sleep") .. " - " .. fatigueLabel .. " x0.85")
    end
    if start.desensitized then
        table.insert(rows, getTextSafe("UI_QoLforSacriel_SleepQuality_Trait_Desensitized", "Desensitized") .. " - " .. nightmareLabel .. " +5%")
    end
    if start.enduranceTraitEffectsVersion == 1 then
        local enduranceLabel = getTextSafe("UI_QoLforSacriel_SleepQuality_ExactTraitEndurance", "Endurance")
        if start.obese then table.insert(rows, getTextSafe("UI_QoLforSacriel_SleepQuality_Trait_Obese", "Obese") .. " - " .. enduranceLabel .. " x0.40") end
        if start.overweight then table.insert(rows, getTextSafe("UI_QoLforSacriel_SleepQuality_Trait_Overweight", "Overweight") .. " - " .. enduranceLabel .. " x0.70") end
        if start.veryUnderweight then table.insert(rows, getTextSafe("UI_QoLforSacriel_SleepQuality_Trait_VeryUnderweight", "Very Underweight") .. " - " .. enduranceLabel .. " x0.70") end
        if start.emaciated then table.insert(rows, getTextSafe("UI_QoLforSacriel_SleepQuality_Trait_Emaciated", "Emaciated") .. " - " .. enduranceLabel .. " x0.30") end
    end
    return rows
end

function FitnessNutritionPanel:refreshModel()
    self.model = getNutritionModel(self.playerObj)
    self.tooltip = self.model.available and getNutritionistTooltip(self.model) or nil
end

function FitnessNutritionPanel:prerender()
    ISPanel.prerender(self)
    self:refreshModel()
end

function FitnessNutritionPanel:drawTrafficLight(x, y, color)
    local swatch = COLORS[color] or COLORS.grey
    self:drawRect(x, y, 14, 14, 1, swatch.r, swatch.g, swatch.b)
    self:drawRectBorder(x, y, 14, 14, 1, 0.1, 0.1, 0.1)
end

function FitnessNutritionPanel:render()
    local model = self.model or { available = false }
    local x = UI_BORDER_SPACING
    local y = UI_BORDER_SPACING
    local labelColor = { r = 0.9, g = 0.9, b = 0.9 }
    local maxRight = x
    local bottom = y

    local function drawTrackedText(text, drawX, drawY, red, green, blue)
        self:drawText(text, drawX, drawY, red, green, blue, 1, UIFont.Small)
        maxRight = math.max(maxRight, drawX + getTextManager():MeasureStringX(UIFont.Small, text))
        bottom = math.max(bottom, drawY + FONT_HGT_SMALL)
    end

    local function trackBounds(right, lower)
        maxRight = math.max(maxRight, right)
        bottom = math.max(bottom, lower)
    end

    drawTrackedText(getTextSafe("UI_QoLforSacriel_FitnessBalance", "Calorie Balance"), x, y, labelColor.r, labelColor.g, labelColor.b)
    y = y + 20
    for index = 1, BALANCE_CELL_COUNT do
        local color = COLORS.neutral
        if model.available and not model.balanceIndex and (index == 5 or index == 6) then
            color = COLORS.grey
        elseif model.available and model.balanceIndex == index then
            color = index <= 4 and COLORS.red or COLORS.green
        end
        local cellX = x + ((index - 1) * (BALANCE_CELL_WIDTH + 2))
        self:drawRect(cellX, y, BALANCE_CELL_WIDTH, BALANCE_CELL_HEIGHT, 1, color.r, color.g, color.b)
        self:drawRectBorder(cellX, y, BALANCE_CELL_WIDTH, BALANCE_CELL_HEIGHT, 1, COLORS.cellBorder.r, COLORS.cellBorder.g, COLORS.cellBorder.b)
        if model.available and model.balanceIndex == index and index > 5 and model.gainMultiplier > 1 then
            local marker = model.gainMultiplier == 3 and "^^" or "^"
            self:drawTextCentre(marker, cellX + (BALANCE_CELL_WIDTH / 2), y + 1, 1, 1, 1, 1, UIFont.Small)
        end
    end
    self:drawLine2(x + (4 * (BALANCE_CELL_WIDTH + 2)) - 1, y - 2, x + (4 * (BALANCE_CELL_WIDTH + 2)) - 1, y + BALANCE_CELL_HEIGHT + 2, 1, 0.9, 0.9, 0.9)
    trackBounds(x + BALANCE_CELL_COUNT * (BALANCE_CELL_WIDTH + 2) - 2, y + BALANCE_CELL_HEIGHT + 2)
    y = y + BALANCE_CELL_HEIGHT + 6
    drawTrackedText(model.available and model.balanceLabel or getTextSafe("UI_QoLforSacriel_FitnessUnavailable", "Nutrition unavailable"), x, y, labelColor.r, labelColor.g, labelColor.b)

    y = y + 30
    drawTrackedText(getTextSafe("UI_QoLforSacriel_FitnessStrength", "Strength Training"), x, y, labelColor.r, labelColor.g, labelColor.b)
    y = y + 18
    self:drawTrafficLight(x, y, model.available and model.strengthColor or "grey")
    trackBounds(x + 14, y + 14)
    drawTrackedText(model.available and model.strengthReason or getTextSafe("UI_QoLforSacriel_FitnessUnavailable", "Nutrition unavailable"), x + 22, y, labelColor.r, labelColor.g, labelColor.b)

    y = y + 32
    drawTrackedText(getTextSafe("UI_QoLforSacriel_FitnessEndurance", "Fitness Endurance"), x, y, labelColor.r, labelColor.g, labelColor.b)
    y = y + 18
    self:drawTrafficLight(x, y, model.available and model.fitnessColor or "grey")
    trackBounds(x + 14, y + 14)
    drawTrackedText(model.available and model.fitnessReason or getTextSafe("UI_QoLforSacriel_FitnessUnavailable", "Nutrition unavailable"), x + 22, y, labelColor.r, labelColor.g, labelColor.b)

    y = y + 34
    local sleepTitle = getTextSafe("UI_QoLforSacriel_SleepQuality_Title", "Quality of Sleep")
    drawTrackedText(sleepTitle, x, y, labelColor.r, labelColor.g, labelColor.b)
    drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_Caveat", "vanilla code hides things, so this is sometimes wrong"), x + getTextManager():MeasureStringX(UIFont.Small, sleepTitle) + 8, y, COLORS.grey.r, COLORS.grey.g, COLORS.grey.b)
    y = y + 18
    local session = getSleepSession(self.playerObj)
    if (session and session.active) or readBoolean(self.playerObj, "isAsleep") then
        drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_InProgress", "Sleep in progress"), x, y, COLORS.grey.r, COLORS.grey.g, COLORS.grey.b)
    else
        if not session then
            session = getSavedSleepSession(self.playerObj)
        end
        if not session then
            drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_NoRecord", "No completed sleep recorded"), x, y, COLORS.grey.r, COLORS.grey.g, COLORS.grey.b)
        else
            local wokeBeforeDeepSleep = session.status == "Woke before deep sleep"
            if wokeBeforeDeepSleep then
                drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_Title", "Quality of Sleep") .. ": " .. getTextSafe("UI_QoLforSacriel_SleepQuality_BeforeDeepSleep", "Woke before deep sleep"), x, y, COLORS.yellow.r, COLORS.yellow.g, COLORS.yellow.b)
            else
                local statusText = session.status == "Partial"
                    and getTextSafe("UI_QoLforSacriel_SleepQuality_Partial", "Partial")
                    or getTextSafe("UI_QoLforSacriel_SleepQuality_Status_" .. tostring(session.status), tostring(session.status))
                local contributor = nil
                if session.status == "Average" and session.contributorPositive and session.contributorNegative then
                    local positive = getTextSafe("UI_QoLforSacriel_SleepQuality_Contributor_" .. session.contributorPositive, session.contributorPositive)
                    local negative = getTextSafe("UI_QoLforSacriel_SleepQuality_Contributor_" .. session.contributorNegative, session.contributorNegative)
                    contributor = positive .. " / " .. negative
                else
                    contributor = getTextSafe("UI_QoLforSacriel_SleepQuality_Contributor_" .. tostring(session.contributor or "None"), tostring(session.contributor or "None"))
                end
                drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_General", "General quality") .. ": " .. statusText .. " (" .. contributor .. ")", x, y, labelColor.r, labelColor.g, labelColor.b)
            end

            y = y + 18
            local wakeReason = session.wakeReason and getTextSafe("UI_QoLforSacriel_SleepQuality_Wake_" .. session.wakeReason, session.wakeReason)
                or getTextSafe("UI_QoLforSacriel_SleepQuality_Unavailable", "Unavailable")
            drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_WakeReason", "Wake-up reason") .. ": " .. wakeReason, x, y, labelColor.r, labelColor.g, labelColor.b)
            y = y + 18

            local onsetComparison, onsetContributor = getOnsetComparison(session)
            if onsetComparison == "AsUsual" then
                drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_OnsetAsUsual", "Falling asleep as usual"), x, y, labelColor.r, labelColor.g, labelColor.b)
            elseif onsetComparison then
                local comparisonText = getTextSafe("UI_QoLforSacriel_SleepQuality_OnsetComparison_" .. onsetComparison, onsetComparison)
                local contributorText = onsetContributor and " (" .. getTextSafe("UI_QoLforSacriel_SleepQuality_OnsetContributor_" .. onsetContributor, onsetContributor) .. ")" or ""
                drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_Onset", "Falling asleep") .. " " .. comparisonText .. contributorText .. " " .. getTextSafe("UI_QoLforSacriel_SleepQuality_OnsetThanUsual", "than usual"), x, y, labelColor.r, labelColor.g, labelColor.b)
            else
                drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_Onset", "Falling asleep") .. ": " .. getTextSafe("UI_QoLforSacriel_SleepQuality_Unavailable", "Unavailable"), x, y, labelColor.r, labelColor.g, labelColor.b)
            end

            if showExactSleepStats() then
                y = y + 18
                local requestedText = session.requestedHours and string.format("%.2fh", session.requestedHours) or getTextSafe("UI_QoLforSacriel_SleepQuality_Unavailable", "Unavailable")
                local neckPainText = session.components and session.components.neckHarm and " | " .. getTextSafe("UI_QoLforSacriel_SleepQuality_ExactNeckPain", "Neck pain") or ""
                local exactStatus = wokeBeforeDeepSleep
                    and getTextSafe("UI_QoLforSacriel_SleepQuality_BeforeDeepSleep", "Woke before deep sleep")
                    or getTextSafe("UI_QoLforSacriel_SleepQuality_ExactScore", "Score") .. " " .. (session.score and string.format("%.2fx", session.score) or getTextSafe("UI_QoLforSacriel_SleepQuality_Unavailable", "Unavailable"))
                local onsetEstimateText = session.onsetEstimate
                    and string.format("%.2fh", session.onsetEstimate) .. " (" .. getTextSafe("UI_QoLforSacriel_SleepQuality_ExactEstimated", "est.") .. ")"
                    or getTextSafe("UI_QoLforSacriel_SleepQuality_Unavailable", "Unavailable")
                local onsetMaximumText = string.format("%.2fh", session.onsetDelay or 0) .. " (" .. getTextSafe("UI_QoLforSacriel_SleepQuality_ExactMaximum", "max") .. ")"
                drawTrackedText(exactStatus .. " | " .. string.format("%.2fh", session.actualHours or 0) .. " / " .. requestedText .. " | " .. getTextSafe("UI_QoLforSacriel_SleepQuality_ExactOnset", "Onset") .. " " .. onsetEstimateText .. " / " .. onsetMaximumText .. neckPainText, x, y, COLORS.grey.r, COLORS.grey.g, COLORS.grey.b)
                y = y + 16
                local fatigueRatio = not wokeBeforeDeepSleep and session.components and session.components.fatigue and string.format("%.2fx", session.components.fatigue) or getTextSafe("UI_QoLforSacriel_SleepQuality_Unavailable", "Unavailable")
                drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_ExactFatigue", "Fatigue") .. ": -" .. string.format("%.3f", session.fatigueRemoved or 0) .. " | " .. getTextSafe("UI_QoLforSacriel_SleepQuality_ExactRatio", "Ratio") .. " " .. fatigueRatio, x, y, COLORS.grey.r, COLORS.grey.g, COLORS.grey.b)
                y = y + 16
                local enduranceStartText = session.start.endurance and string.format("%.2f", session.start.endurance) or getTextSafe("UI_QoLforSacriel_SleepQuality_Unavailable", "Unavailable")
                local enduranceFinishText = session.finish.endurance
                    and ((session.finish.endurance >= 1 and "1 (" .. getTextSafe("UI_QoLforSacriel_SleepQuality_ExactMaximum", "max") .. ")") or string.format("%.2f", session.finish.endurance))
                    or getTextSafe("UI_QoLforSacriel_SleepQuality_Unavailable", "Unavailable")
                local fitnessRecoveryMultiplier = getFitnessRecoveryMultiplier(session.start.fitness)
                local fitnessText = getTextSafe("UI_QoLforSacriel_SleepQuality_ExactFitness", "Fitness") .. " " .. tostring(session.start.fitness or "?") .. ": " .. (fitnessRecoveryMultiplier and "x" .. string.format("%.2f", fitnessRecoveryMultiplier) or getTextSafe("UI_QoLforSacriel_SleepQuality_Unavailable", "Unavailable"))
                drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_ExactEndurance", "Endurance") .. ": " .. getTextSafe("UI_QoLforSacriel_SleepQuality_ExactRate", "Rate") .. " x" .. string.format("%.2f", session.start.recoveryMod or 1) .. " | " .. getTextSafe("UI_QoLforSacriel_SleepQuality_ExactStart", "start") .. ": " .. enduranceStartText .. " | " .. getTextSafe("UI_QoLforSacriel_SleepQuality_ExactEnd", "end") .. ": " .. enduranceFinishText .. " | " .. fitnessText, x, y, COLORS.grey.r, COLORS.grey.g, COLORS.grey.b)
                y = y + 16
                local pillowText = string.find(session.start.bedType or "", "Pillow", 1, true) and getTextSafe("UI_QoLforSacriel_SleepQuality_ExactPillowYes", "yes") or getTextSafe("UI_QoLforSacriel_SleepQuality_ExactPillowNo", "no")
                drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_ExactBed", "Bed") .. ": " .. getSleepBedLabel(session.start.bedType) .. " | " .. getTextSafe("UI_QoLforSacriel_SleepQuality_ExactPillow", "Pillow") .. " " .. pillowText .. " | " .. getTextSafe("UI_QoLforSacriel_SleepQuality_ExactRecovery", "Recovery") .. " x" .. string.format("%.2f", getFatigueRecoveryBedMultiplier(session.start.bedType)) .. " | " .. getTextSafe("UI_QoLforSacriel_SleepQuality_ExactOnset", "Onset") .. " x" .. string.format("%.2f", getOnsetBedMultiplier(session.start.bedType)), x, y, COLORS.grey.r, COLORS.grey.g, COLORS.grey.b)
                y = y + 16
                local traitRows = getSleepTraitExactRows(session.start)
                if not traitRows then
                    drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_ExactTraits", "Traits") .. ": " .. getTextSafe("UI_QoLforSacriel_SleepQuality_Unavailable", "Unavailable"), x, y, COLORS.grey.r, COLORS.grey.g, COLORS.grey.b)
                    y = y + 16
                elseif #traitRows == 0 then
                    drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_ExactTraits", "Traits") .. ": " .. getTextSafe("UI_QoLforSacriel_SleepQuality_ExactTraitsNone", "none"), x, y, COLORS.grey.r, COLORS.grey.g, COLORS.grey.b)
                    y = y + 16
                else
                    drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_ExactTraits", "Traits") .. ":", x, y, COLORS.grey.r, COLORS.grey.g, COLORS.grey.b)
                    y = y + 16
                    for _, traitRow in ipairs(traitRows) do
                        drawTrackedText("  " .. traitRow, x, y, COLORS.grey.r, COLORS.grey.g, COLORS.grey.b)
                        y = y + 16
                    end
                end
                local nightmareChanceText = getTextSafe("UI_QoLforSacriel_SleepQuality_Unavailable", "Unavailable")
                if session.requestedHours and session.requestedHours >= 3 and session.start.stress ~= nil and session.start.sleepTraitEffectsVersion == 1 then
                    local stressChance = session.start.stress * 10
                    local traitChance = session.start.desensitized and 5 or 0
                    local totalChance = 5 + stressChance + traitChance
                    nightmareChanceText = getTextSafe("UI_QoLforSacriel_SleepQuality_ExactNightmareBase", "Base") .. " 5%"
                        .. " | +" .. tostring(stressChance) .. "% " .. getTextSafe("UI_QoLforSacriel_SleepQuality_ExactNightmareStress", "stress")
                        .. " (" .. tostring(session.start.stress) .. ")"
                        .. " | +" .. tostring(traitChance) .. "% " .. getTextSafe("UI_QoLforSacriel_SleepQuality_ExactNightmareTrait", "trait")
                        .. " | " .. getTextSafe("UI_QoLforSacriel_SleepQuality_ExactNightmareTotal", "Total") .. " " .. tostring(totalChance) .. "%"
                elseif session.requestedHours and session.requestedHours < 3 then
                    nightmareChanceText = getTextSafe("UI_QoLforSacriel_SleepQuality_ExactNightmareIneligible", "Not eligible (under 3h)")
                end
                drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_ExactNightmareChance", "Nightmare chance") .. ": " .. nightmareChanceText, x, y, COLORS.grey.r, COLORS.grey.g, COLORS.grey.b)
                y = y + 16
                local medicationText = session.medicationOverride and getTextSafe("UI_QoLforSacriel_SleepQuality_ExactMedicationOverride", "override") or getTextSafe("UI_QoLforSacriel_SleepQuality_ExactMedicationNone", "none")
                drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_ExactMedication", "Medication") .. ": " .. medicationText .. " (" .. string.format("%.1f", session.start.sleepingTabletEffect or 0) .. ")", x, y, COLORS.grey.r, COLORS.grey.g, COLORS.grey.b)
                y = y + 16
                drawTrackedText(getTextSafe("UI_QoLforSacriel_SleepQuality_ExactWake", "Wake") .. ": " .. wakeReason .. " (" .. getTextSafe("UI_QoLforSacriel_SleepQuality_Confidence_" .. tostring(session.wakeConfidence), tostring(session.wakeConfidence)) .. ")", x, y, COLORS.grey.r, COLORS.grey.g, COLORS.grey.b)
            end
        end
    end

    if self.exerciseButton then
        self.exerciseButton:setX(x)
        self.exerciseButton:setY(bottom + UI_BORDER_SPACING)
        self.exerciseButton:setVisible(true)
        trackBounds(self.exerciseButton:getRight(), self.exerciseButton:getBottom())
    end

    self:setWidthAndParentWidth(maxRight + UI_BORDER_SPACING)
    self:setHeightAndParentHeight(bottom + UI_BORDER_SPACING)
end

function FitnessNutritionPanel:new(playerObj, x, y, width, height)
    local panel = ISPanel.new(self, x, y, width, height)
    setmetatable(panel, self)
    self.__index = self
    panel.playerObj = playerObj
    panel.character = playerObj
    panel.playerNum = playerObj:getPlayerNum()
    panel.backgroundColor = { r = 0.08, g = 0.10, b = 0.11, a = 0.85 }
    return panel
end

local function addFitnessView(window)
    if not window or not window.panel or window.fitnessNutritionView then
        return
    end
    local playerObj = getSpecificPlayer and getSpecificPlayer(window.playerNum) or nil
    if not playerObj then
        return
    end

    local view = FitnessNutritionPanel:new(playerObj, 0, 8, window.panel:getWidth(), FITNESS_PANEL_INITIAL_HEIGHT)
    view:initialise()
    view.anchorLeft = true
    view.anchorRight = false
    view.anchorTop = true
    view.anchorBottom = false
    window.panel:addView(getTextSafe("UI_QoLforSacriel_FitnessTab", "Fitness"), view)

    local button = ISButton:new(UI_BORDER_SPACING, 0, 100, 22, getTextSafe("ContextMenu_Fitness", "Fitness"), view, ISNewHealthPanel.onClick)
    button.internal = "FITNESS"
    button:initialise()
    button:instantiate()
    view:addChild(button)
    view.exerciseButton = button
    window.fitnessNutritionView = view

    logDebug("Fitness tab added")
end

local function removeFitnessView(window)
    if not window or not window.panel or not window.fitnessNutritionView then
        return
    end
    window.panel:removeView(window.fitnessNutritionView)
    window.fitnessNutritionView = nil
    logDebug("Fitness tab removed")
end

local function beginContextSleepSession(playerIndex)
    local playerObj = getSpecificPlayer and getSpecificPlayer(playerIndex) or nil
    if not playerObj or not readBoolean(playerObj, "isAsleep") then
        logDebug("context sleep completion did not enter sleep for player " .. tostring(playerIndex))
        return
    end
    local activeSession = getSleepSession(playerObj)
    if activeSession and activeSession.active then
        logDebug("context sleep completion retained existing session for player " .. tostring(playerIndex))
        return
    end
    local forceWakeTime = readFiniteNumber(playerObj, "getForceWakeUpTime")
    local timeOfDay = getTimeOfDay()
    if not forceWakeTime or not timeOfDay then
        logDebug("context sleep duration unavailable: timeOfDay=" .. formatSleepNumber(timeOfDay) .. "; forceWake=" .. formatSleepNumber(forceWakeTime))
        return
    end
    local requestedHours = forceWakeTime - timeOfDay
    if requestedHours <= 0 then
        requestedHours = requestedHours + 24
    end
    if requestedHours <= 0 or requestedHours > 16 then
        logDebug("context sleep duration invalid: timeOfDay=" .. formatSleepNumber(timeOfDay) .. "; forceWake=" .. formatSleepNumber(forceWakeTime) .. "; derived=" .. formatSleepNumber(requestedHours))
        return
    end
    logDebug("context sleep duration derived: player=" .. tostring(playerIndex) .. "; timeOfDay=" .. formatSleepNumber(timeOfDay) .. "; forceWake=" .. formatSleepNumber(forceWakeTime) .. "; requested=" .. formatSleepNumber(requestedHours))
    beginSleepSession(playerObj, requestedHours)
end

local function installSleepWrappers()
    if not sleepDialogWrapped and ISSleepDialog and ISSleepDialog.onClick then
        originalSleepDialogOnClick = ISSleepDialog.onClick
        ISSleepDialog.onClick = function(dialog, button)
            if button and button.internal == "YES" and dialog.player and dialog.spinBox then
                beginSleepSession(dialog.player, dialog.spinBox.selected)
            end
            return originalSleepDialogOnClick(dialog, button)
        end
        sleepDialogWrapped = true
        logDebug("sleep dialog wrapper installed")
    end
    if not contextSleepWrapped and ISWorldObjectContextMenu and ISWorldObjectContextMenu.onSleep then
        originalContextSleep = ISWorldObjectContextMenu.onSleep
        ISWorldObjectContextMenu.onSleep = function(bed, playerIndex)
            logDebug("context sleep opened for player index " .. tostring(playerIndex))
            return originalContextSleep(bed, playerIndex)
        end
        contextSleepWrapped = true
        logDebug("context sleep wrapper installed")
    end
    if not contextSleepCompleteWrapped and ISWorldObjectContextMenu and ISWorldObjectContextMenu.onSleepWalkToComplete then
        originalContextSleepComplete = ISWorldObjectContextMenu.onSleepWalkToComplete
        ISWorldObjectContextMenu.onSleepWalkToComplete = function(playerIndex, bed)
            local result = originalContextSleepComplete(playerIndex, bed)
            beginContextSleepSession(playerIndex)
            return result
        end
        contextSleepCompleteWrapped = true
        logDebug("context sleep completion wrapper installed")
    end
    logDebug("sleep wrapper state: dialog=" .. tostring(sleepDialogWrapped) .. "; context=" .. tostring(contextSleepWrapped) .. "; contextComplete=" .. tostring(contextSleepCompleteWrapped))
    return sleepDialogWrapped and contextSleepWrapped and contextSleepCompleteWrapped
end

function FitnessNutritionIndicator.init(settings, logger)
    if installed then
        return
    end
    if not ISCharacterInfoWindow or not ISCharacterInfoWindow.createChildren then
        if logger and logger.warn then
            logger.warn("UIFixes.FitnessNutritionIndicator could not patch Character Info")
        end
        return
    end

    runtimeSettings = settings
    loggerRef = logger
    originalCreateChildren = ISCharacterInfoWindow.createChildren
    ISCharacterInfoWindow.createChildren = function(self)
        originalCreateChildren(self)
        if isEnabled() then
            addFitnessView(self)
        end
    end

    if not installSleepWrappers() and Events and Events.OnGameStart and not sleepWrapperRetryRegistered then
        sleepWrapperRetryRegistered = true
        Events.OnGameStart.Add(function()
            if not installSleepWrappers() then
                logDebug("sleep wrappers unavailable after OnGameStart; requested duration may be unavailable")
            end
        end)
    end
    if Events and Events.OnPlayerUpdate then
        Events.OnPlayerUpdate.Add(function(playerObj)
            local playerNum = playerObj:getPlayerNum() or 0
            local window = getPlayerInfoPanel and getPlayerInfoPanel(playerNum) or nil
            if not isEnabled() or playerObj:isDead() then
                sleepSessions[playerNum] = nil
                if window then
                    removeFitnessView(window)
                end
                return
            end
            local session = sleepSessions[playerNum]
            if session and session.start and getWorldAgeHours() < (session.start.worldAge or 0) then
                sleepSessions[playerNum] = nil
            end
            updateSleepSession(playerObj)
            if window then
                if isEnabled() then
                    addFitnessView(window)
                else
                    removeFitnessView(window)
                end
            end
        end)
    end
    if Events and Events.OnSleepingTick then
        Events.OnSleepingTick.Add(function(playerIndex)
            if isEnabled() then
                sampleSleepingPlayer(playerIndex)
            end
        end)
    end

    installed = true
end

return FitnessNutritionIndicator