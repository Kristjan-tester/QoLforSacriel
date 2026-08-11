require "TimedActions/ISDryMyself"

local DrySelfDivisor = {}
local coreModOptions = require "QoLforSacriel/CoreModOptions"

local DEFAULT_WETNESS_PER_USE = 6.25
local VANILLA_WETNESS_PER_USE = 4
local MAX_BUFFER_TICKS = 20
local installed = false
local originalGetDuration = nil
local originalUpdate = nil
local runtimeSettings = nil
local loggerRef = nil
local actionStates = setmetatable({}, { __mode = "k" })

local function logDebug(message)
    if runtimeSettings
        and runtimeSettings.get
        and runtimeSettings.get("QoLforSacriel_DebugLogs") == true
        and loggerRef
        and loggerRef.debug
    then
        loggerRef.debug("DrySelf.WetnessPerUse: " .. message)
    end
end

local function formatWetness(value)
    return string.format("%.2f", tonumber(value) or 0)
end

local function getWetnessPerUse()
    local value = runtimeSettings and runtimeSettings.get
        and runtimeSettings.get("QoLforSacriel_DrySelf_WetnessPerUse")
    local wetnessPerUse = tonumber(value)

    if not wetnessPerUse
        or wetnessPerUse ~= wetnessPerUse
        or wetnessPerUse == math.huge
        or wetnessPerUse == -math.huge
        or wetnessPerUse <= 0
    then
        return DEFAULT_WETNESS_PER_USE
    end

    return wetnessPerUse
end

local function getBufferTicks(wetnessPerUse)
    local extraTicks = math.ceil((wetnessPerUse - VANILLA_WETNESS_PER_USE) / VANILLA_WETNESS_PER_USE)
    return math.min(MAX_BUFFER_TICKS, math.max(0, extraTicks))
end

local function getTowelUseInfo(item)
    local currentUses = item:getCurrentUsesFloat()
    local useDelta = item:getUseDelta()

    if useDelta and useDelta > 0 then
        return math.ceil(currentUses / useDelta), math.ceil(1 / useDelta)
    end

    return math.ceil(currentUses * 10), 10
end

local function getDrySelfDuration(action)
    local duration = originalGetDuration(action)
    if not runtimeSettings
        or not runtimeSettings.isEnabled
        or runtimeSettings.isEnabled("QoLforSacriel_EnableDrySelfDivisor") ~= true
        or action.character:isTimedActionInstant()
    then
        return duration
    end

    local remainingUses = getTowelUseInfo(action.item)
    local ticksPerWetnessUse = getBufferTicks(getWetnessPerUse()) + 1
    local requiredDuration = (remainingUses + 1) * 20 * ticksPerWetnessUse
    return math.max(duration, requiredDuration)
end

local function getActionState(action)
    local state = actionStates[action]
    if state then
        return state
    end

    local timer = 0.05
    local remainingUses = 0
    local towelCapacity = 0
    local bufferTicks = 0
    if not action.character:isTimedActionInstant() then
        remainingUses, towelCapacity = getTowelUseInfo(action.item)
        timer = remainingUses + 1
        bufferTicks = getBufferTicks(getWetnessPerUse())
    end

    state = {
        bufferTicks = bufferTicks,
        bufferTicksRemaining = bufferTicks,
        tick = 0,
        timer = timer,
    }
    actionStates[action] = state
    logDebug(
        "action timing initialized: timer=" .. formatWetness(timer)
        .. ", uses remaining=" .. tostring(remainingUses)
        .. ", towel capacity=" .. tostring(towelCapacity)
        .. ", buffer ticks=" .. tostring(bufferTicks)
    )
    return state
end

local function consumeTowelUse(action)
    if isClient() then
        if action.item then
            local usesRemaining = action.item:getCurrentUsesFloat() - action.item:getUseDelta()
            if usesRemaining > 0 then
                action.item:setUsedDelta(usesRemaining)
            else
                action:forceStop()
            end
        end
    else
        action.item:Use()
    end
end

local function updateDrySelf(action)
    if not runtimeSettings
        or not runtimeSettings.isEnabled
        or runtimeSettings.isEnabled("QoLforSacriel_EnableDrySelfDivisor") ~= true
    then
        return originalUpdate(action)
    end

    local state = getActionState(action)

    state.tick = state.tick + 1
    if state.tick >= state.timer then
        state.tick = 0
        if state.bufferTicksRemaining > 0 then
            state.bufferTicksRemaining = state.bufferTicksRemaining - 1
            logDebug("buffer tick; buffer ticks remaining=" .. tostring(state.bufferTicksRemaining))
        else
            local wetnessPerUse = getWetnessPerUse()
            local wetness = action.character:getStats():get(CharacterStat.WETNESS)
            local wetnessRemoved = math.min(wetness, wetnessPerUse)
            state.bufferTicksRemaining = state.bufferTicks
            action.character:getBodyDamage():decreaseBodyWetness(wetnessRemoved)
            consumeTowelUse(action)

            logDebug(
                "periodic use timer=" .. formatWetness(state.timer)
                .. ", removed="
                .. formatWetness(wetnessRemoved)
                .. ", buffer ticks=" .. tostring(state.bufferTicks)
                .. ", wetness remaining="
                .. formatWetness(action.character:getStats():get(CharacterStat.WETNESS))
            )
        end
    end

    action.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function DrySelfDivisor.init(settings, logger)
    if installed then
        return
    end

    if not ISDryMyself or not ISDryMyself.getDuration or not ISDryMyself.update then
        if logger and logger.error then
            logger.error("DrySelf.WetnessPerUse unavailable: vanilla ISDryMyself methods are missing")
        end
        return
    end

    runtimeSettings = settings
    loggerRef = logger
    originalGetDuration = ISDryMyself.getDuration
    originalUpdate = ISDryMyself.update
    ISDryMyself.getDuration = getDrySelfDuration
    ISDryMyself.update = updateDrySelf
    installed = true

    coreModOptions.addApplyListener(function()
        local wetnessPerUse = getWetnessPerUse()
        logDebug(
            "setting saved: wetness per use=" .. formatWetness(wetnessPerUse)
            .. ", buffer ticks=" .. tostring(getBufferTicks(wetnessPerUse))
        )
    end)

    if logger and logger.info then
        logger.info("DrySelf.WetnessPerUse installed")
    end
end

return DrySelfDivisor