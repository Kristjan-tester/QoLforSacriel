-- ff-assisted
local Bootstrap = {}

local logger = require "QoLforSacriel/Core/Logger"
local settings = require "QoLforSacriel/Core/Settings"
local registry = require "QoLforSacriel/Core/ModuleRegistry"
local version = require "QoLforSacriel/Core/Version"

local installed = false
local initialized = false

local function safeRequire(path)
    local ok, mod = pcall(require, path)
    if not ok then
        logger.error("Require failed: " .. tostring(path) .. " | " .. tostring(mod))
        return nil
    end
    if mod == nil then
        logger.error("Require returned nil: " .. tostring(path))
        return nil
    end
    return mod
end

local function registerModules()
    local skillFilter = safeRequire("QoLforSacriel/Modules/UIFixes/SkillFilter")
    local waterDepthHints = safeRequire("QoLforSacriel/Modules/UIFixes/WaterDepthHints")
    local heavyLoadHurtFeedback = safeRequire("QoLforSacriel/Modules/UIFixes/HeavyLoadHurtFeedback")
    local fitnessNutritionIndicator = safeRequire("QoLforSacriel/Modules/UIFixes/FitnessNutritionIndicator")
    local equipmentStatsDisplay = safeRequire("QoLforSacriel/Modules/UIFixes/EquipmentStatsDisplay")
    local craftToolSubmenu = safeRequire("QoLforSacriel/Modules/UIFixes/CraftToolSubmenu")
    local inventoryUpdate = safeRequire("QoLforSacriel/Modules/UIFixes/InventoryUpdate")
    local heavyCraftDrop = safeRequire("QoLforSacriel/Modules/UIFixes/HeavyCraftDrop")
    local washAllOrder = safeRequire("QoLforSacriel/Modules/UIFixes/WashAllOrder")
    local fishingNearbyLures = safeRequire("QoLforSacriel/Modules/UIFixes/FishingNearbyLures")
    local heldItemContainerMenu = safeRequire("QoLforSacriel/Modules/UIFixes/HeldItemContainerMenu")
    local foragingRefinement = safeRequire("QoLforSacriel/Modules/ForagingRefinement/ForagingRefinement")
    local soundDirection = safeRequire("QoLforSacriel/Modules/SoundIntel/SoundDirection")
    local soundRadius = safeRequire("QoLforSacriel/Modules/SoundIntel/SoundRadius")
    local furnitureNudge = safeRequire("QoLforSacriel/Modules/FurnitureNudge/FurnitureNudge")
    local lightSwitchToggle = safeRequire("QoLforSacriel/Modules/LightSwitchToggle/LightSwitchToggle")
    local nearbyDeviceOff = safeRequire("QoLforSacriel/Modules/NearbyDeviceOff/NearbyDeviceOff")
    local heldBagClimb = safeRequire("QoLforSacriel/Modules/HeldBagClimb/HeldBagClimb")
    local vehicleEntryAssist = safeRequire("QoLforSacriel/Modules/VehicleEntryAssist/VehicleEntryAssist")
    local drySelfDivisor = safeRequire("QoLforSacriel/Modules/DrySelf/DrySelfDivisor")
    local vehicleHorn = safeRequire("QoLforSacriel/Modules/VehicleHorn/VehicleHorn")
    local dragDrop = safeRequire("QoLforSacriel/Modules/DragDrop/DragDropFatigue")
    local restSleep = safeRequire("QoLforSacriel/Modules/RestSleep/RestUntilSleepy")
    local equipmentPresets = safeRequire("QoLforSacriel/Modules/Equipment/EquipmentPresets")
    local armorMood = safeRequire("QoLforSacriel/Modules/ArmorMood/ArmorMoodBase")

    if skillFilter and skillFilter.init then
        registry.register("UIFixes.SkillFilter", "QoLforSacriel_EnableUIFixes", skillFilter.init)
    end
    if waterDepthHints and waterDepthHints.init then
        registry.register("UIFixes.WaterDepthHints", "QoLforSacriel_EnableUIFixes", waterDepthHints.init)
    end
    if heavyLoadHurtFeedback and heavyLoadHurtFeedback.init then
        registry.register("UIFixes.HeavyLoadHurtFeedback", "QoLforSacriel_EnableUIFixes", heavyLoadHurtFeedback.init)
    end
    if fitnessNutritionIndicator and fitnessNutritionIndicator.init then
        registry.register("UIFixes.FitnessNutritionIndicator", "QoLforSacriel_EnableUIFixes", fitnessNutritionIndicator.init)
    end
    if equipmentStatsDisplay and equipmentStatsDisplay.init then
        registry.register("UIFixes.EquipmentStatsDisplay", "QoLforSacriel_EnableUIFixes", equipmentStatsDisplay.init)
    end
    if craftToolSubmenu and craftToolSubmenu.init then
        registry.register("UIFixes.CraftToolSubmenu", "QoLforSacriel_EnableUIFixes", craftToolSubmenu.init)
    end
    if inventoryUpdate and inventoryUpdate.init then
        registry.register("UIFixes.InventoryUpdate", "QoLforSacriel_EnableUIFixes", inventoryUpdate.init)
    end
    if heavyCraftDrop and heavyCraftDrop.init then
        registry.register("UIFixes.HeavyCraftDrop", "QoLforSacriel_EnableUIFixes", heavyCraftDrop.init)
    end
    if washAllOrder and washAllOrder.init then
        registry.register("UIFixes.WashAllOrder", "QoLforSacriel_EnableUIFixes", washAllOrder.init)
    end
    if fishingNearbyLures and fishingNearbyLures.init then
        registry.register("UIFixes.FishingNearbyLures", "QoLforSacriel_EnableUIFixes", fishingNearbyLures.init)
    end
    if heldItemContainerMenu and heldItemContainerMenu.init then
        registry.register("UIFixes.HeldItemContainerMenu", "QoLforSacriel_EnableUIFixes", heldItemContainerMenu.init)
    end
    if foragingRefinement and foragingRefinement.init then
        registry.register("ForagingRefinement.Base", "QoLforSacriel_EnableForagingRefinement", foragingRefinement.init)
    end
    if soundDirection and soundDirection.init then
        registry.register("SoundDirection.Base", "QoLforSacriel_EnableMod", soundDirection.init)
    end
    if soundRadius and soundRadius.init then
        registry.register("SoundRadius.Base", "QoLforSacriel_EnableMod", soundRadius.init)
    end
    if furnitureNudge and furnitureNudge.init then
        registry.register("FurnitureNudge.Base", "QoLforSacriel_EnableFurnitureNudge", furnitureNudge.init)
    end
    if lightSwitchToggle and lightSwitchToggle.init then
        registry.register("LightSwitchToggle.Base", "QoLforSacriel_EnableLightSwitchToggle", lightSwitchToggle.init)
    end
    if nearbyDeviceOff and nearbyDeviceOff.init then
        registry.register("NearbyDeviceOff.Base", "QoLforSacriel_EnableNearbyDeviceOff", nearbyDeviceOff.init)
    end
    if heldBagClimb and heldBagClimb.init then
        registry.register("HeldBagClimb.Base", "QoLforSacriel_EnableHeldBagClimb", heldBagClimb.init)
    end
    if vehicleEntryAssist and vehicleEntryAssist.init then
        registry.register("VehicleEntryAssist.Base", "QoLforSacriel_EnableVehicleEntryAssist", vehicleEntryAssist.init)
    end
    if drySelfDivisor and drySelfDivisor.init then
        registry.register("DrySelf.WetnessPerUse", "QoLforSacriel_EnableDrySelfDivisor", drySelfDivisor.init)
    end
    if vehicleHorn and vehicleHorn.init then
        registry.register("UIFixes.ExteriorVehicleHorn", "QoLforSacriel_EnableUIFixes", vehicleHorn.init)
    end
    if dragDrop and dragDrop.init then
        registry.register("DragDrop.Fatigue", "QoLforSacriel_EnableDragDrop", dragDrop.init)
    end
    if restSleep and restSleep.init then
        registry.register("RestSleep.RestUntilSleepy", "QoLforSacriel_EnableRestSleep", restSleep.init)
    end
    if equipmentPresets and equipmentPresets.init then
        registry.register("Equipment.Presets", "QoLforSacriel_EnableEquipment", equipmentPresets.init)
    end
    if armorMood and armorMood.init then
        registry.register("ArmorMood.Base", "QoLforSacriel_EnableArmorMood", armorMood.init)
    end
end

local function onGameStart()
    if initialized then
        return
    end

    if isServer() and not isClient() then
        logger.info("Server-only context detected; skipping client module startup")
        initialized = true
        return
    end

    if isClient and isClient() then
        logger.info("Multiplayer client detected; QoLforSacriel is single-player only, skipping module startup")
        initialized = true
        return
    end

    logger.info("Runtime " .. tostring(version.runtime) .. " startup")

    registerModules()
    registry.initAll(settings, logger)

    initialized = true
end

function Bootstrap.install()
    if installed then
        return
    end

    Events.OnGameStart.Add(onGameStart)
    installed = true
end

return Bootstrap
