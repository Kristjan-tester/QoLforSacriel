local logger = require "QoLforSacriel/Core/Logger"
local modOptions = require "QoLforSacriel/Modules/SoundIntel/SoundModOptions"

local registered = false

local function ensureRegistered()
    if registered then
        return
    end

    local ok, options = pcall(function()
        return modOptions.register(logger)
    end)
    if ok and options then
        registered = true
    end
end

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(ensureRegistered)
end
if Events and Events.OnMainMenuEnter then
    Events.OnMainMenuEnter.Add(ensureRegistered)
end

ensureRegistered()
