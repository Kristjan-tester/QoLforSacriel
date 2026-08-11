local logger = require "QoLforSacriel/Core/Logger"
local modOptions = require "QoLforSacriel/CoreModOptions"

local registered = false
local persistedOptionsLoaded = false

local function loadPersistedOptions()
    if persistedOptionsLoaded then
        return
    end

    if not PZAPI
        or not PZAPI.ModOptions
        or type(PZAPI.ModOptions.load) ~= "function"
    then
        return
    end

    local ok, err = pcall(PZAPI.ModOptions.load, PZAPI.ModOptions)
    if not ok then
        logger.error("Failed to load persisted ModOptions: " .. tostring(err))
        return
    end

    persistedOptionsLoaded = true
end

local function ensureRegistered()
    if registered then
        pcall(function()
            modOptions.syncKeybinds(logger)
        end)
        return
    end

    local ok, options = pcall(function()
        return modOptions.register(logger)
    end)
    if ok and options then
        loadPersistedOptions()
        registered = true
    end

    if ok then
        pcall(function()
            modOptions.syncKeybinds(logger)
        end)
    end
end

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(ensureRegistered)
end
if Events and Events.OnMainMenuEnter then
    Events.OnMainMenuEnter.Add(ensureRegistered)
end
if Events and Events.OnGameStart then
    Events.OnGameStart.Add(ensureRegistered)
end
if Events and Events.OnCreatePlayer then
    Events.OnCreatePlayer.Add(function()
        ensureRegistered()
    end)
end

ensureRegistered()
