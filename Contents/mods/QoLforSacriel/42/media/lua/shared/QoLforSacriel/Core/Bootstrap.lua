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
    local soundDirection = safeRequire("QoLforSacriel/Modules/SoundIntel/SoundDirection")
    local furnitureNudge = safeRequire("QoLforSacriel/Modules/FurnitureNudge/FurnitureNudge")
    local lightSwitchToggle = safeRequire("QoLforSacriel/Modules/LightSwitchToggle/LightSwitchToggle")
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
    if soundDirection and soundDirection.init then
        registry.register("UIFixes.SoundDirection", "QoLforSacriel_EnableUIFixes", soundDirection.init)
    end
    if furnitureNudge and furnitureNudge.init then
        registry.register("FurnitureNudge.Base", "QoLforSacriel_EnableFurnitureNudge", furnitureNudge.init)
    end
    if lightSwitchToggle and lightSwitchToggle.init then
        registry.register("LightSwitchToggle.Base", "QoLforSacriel_EnableLightSwitchToggle", lightSwitchToggle.init)
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
