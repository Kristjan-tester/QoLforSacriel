-- ff-assisted
local ForagingClothingPenaltyFix = {}

require "Foraging/forageSystem"
require "Foraging/ISSearchManager"

local coreModOptions = require "QoLforSacriel/CoreModOptions"

local MODULE_SETTING = "QoLforSacriel_ForagingClothingPenaltyFix_Enabled"
local FLOAT_TOLERANCE = 0.000001

local installed = false
local settingsRef = nil
local loggerRef = nil
local originalGetClothingPenalty = nil
local locationPenaltyKeys = nil
local failureLogged = false
local refreshFailureLogged = false

local function logFailure(reason)
    if failureLogged then
        return
    end
    failureLogged = true
    if loggerRef and loggerRef.debug then
        loggerRef.debug("ForagingClothingPenaltyFix unavailable: " .. tostring(reason))
    end
end

local function isEnabled()
    return settingsRef
        and settingsRef.isEnabled
        and settingsRef.isEnabled()
        and settingsRef.isEnabled(MODULE_SETTING) == true
end

local function clamp(value, minimum, maximum)
    if minimum > maximum then
        minimum, maximum = maximum, minimum
    end
    return math.min(math.max(value, minimum), maximum)
end

local function buildLocationPenaltyKeys()
    if not ItemBodyLocation then
        return nil
    end

    if not ItemBodyLocation.FULL_SUIT_HEAD
        or not ItemBodyLocation.FULL_HAT
        or not ItemBodyLocation.MASK_FULL
        or not ItemBodyLocation.SCBA
        or not ItemBodyLocation.SCBANOTANK
        or not ItemBodyLocation.MASK_EYES
        or not ItemBodyLocation.MASK
        or not ItemBodyLocation.EYES
        or not ItemBodyLocation.LEFT_EYE
        or not ItemBodyLocation.RIGHT_EYE
    then
        return nil
    end

    return {
        [ItemBodyLocation.FULL_SUIT_HEAD] = "FullSuitHead",
        [ItemBodyLocation.FULL_HAT] = "FullHat",
        [ItemBodyLocation.MASK_FULL] = "MaskFull",
        [ItemBodyLocation.SCBA] = "SCBA",
        [ItemBodyLocation.SCBANOTANK] = "SCBAnotank",
        [ItemBodyLocation.MASK_EYES] = "MaskEyes",
        [ItemBodyLocation.MASK] = "Mask",
        [ItemBodyLocation.EYES] = "Eyes",
        [ItemBodyLocation.LEFT_EYE] = "LeftEye",
        [ItemBodyLocation.RIGHT_EYE] = "RightEye",
    }
end

local function calculateCorrectedMultiplier(character)
    if not character or not character.getWornItems then
        return nil
    end

    local penalties = forageSystem and forageSystem.clothingPenalties
    local maximumPenalty = forageSystem and tonumber(forageSystem.clothingPenaltyMax)
    if not locationPenaltyKeys or type(penalties) ~= "table" or not maximumPenalty then
        return nil
    end

    local wornItems = character:getWornItems()
    if not wornItems or not wornItems.size or not wornItems.get then
        return nil
    end

    local clothingPenalty = 0
    for index = 0, wornItems:size() - 1 do
        local wornItem = wornItems:get(index)
        local location = wornItem and wornItem.getLocation and wornItem:getLocation()
        local penaltyKey = location and locationPenaltyKeys[location]
        if penaltyKey then
            local penalty = tonumber(penalties[penaltyKey])
            if not penalty then
                return nil
            end
            clothingPenalty = clothingPenalty + penalty
        end
    end

    return clamp(1 - (clothingPenalty / 100), 1 - (maximumPenalty / 100), 1)
end

local function getClothingPenalty(character)
    local vanillaMultiplier = originalGetClothingPenalty(character)
    if not isEnabled() then
        return vanillaMultiplier
    end

    if vanillaMultiplier < 1 - FLOAT_TOLERANCE then
        return vanillaMultiplier
    end

    local correctedMultiplier = calculateCorrectedMultiplier(character)
    if not correctedMultiplier then
        logFailure("required clothing location or penalty data is unavailable")
        return vanillaMultiplier
    end

    if math.abs(correctedMultiplier - vanillaMultiplier) <= FLOAT_TOLERANCE then
        return vanillaMultiplier
    end

    return correctedMultiplier
end

local function refreshActiveManagers()
    if not ISSearchManager or not ISSearchManager.players then
        return
    end

    for _, manager in pairs(ISSearchManager.players) do
        if manager and manager.character and manager.updateModifiers then
            local ok, err = pcall(manager.updateModifiers, manager)
            if not ok and not refreshFailureLogged then
                refreshFailureLogged = true
                if loggerRef and loggerRef.debug then
                    loggerRef.debug("ForagingClothingPenaltyFix manager refresh failed: " .. tostring(err))
                end
            end
        end
    end
end

local function hasRequiredVanillaApis()
    return forageSystem
        and type(forageSystem.getClothingPenalty) == "function"
        and ISSearchManager
        and ItemBodyLocation
        and buildLocationPenaltyKeys() ~= nil
end

function ForagingClothingPenaltyFix.init(settings, logger)
    if installed then
        return
    end

    settingsRef = settings
    loggerRef = logger

    if not hasRequiredVanillaApis() then
        if loggerRef and loggerRef.error then
            loggerRef.error("ForagingClothingPenaltyFix unavailable: expected vanilla Foraging APIs are missing")
        end
        return
    end

    locationPenaltyKeys = buildLocationPenaltyKeys()
    originalGetClothingPenalty = forageSystem.getClothingPenalty
    forageSystem.getClothingPenalty = getClothingPenalty

    coreModOptions.addApplyListener(refreshActiveManagers)
    installed = true

    if loggerRef and loggerRef.info then
        loggerRef.info("ForagingClothingPenaltyFix installed")
    end
end

return ForagingClothingPenaltyFix