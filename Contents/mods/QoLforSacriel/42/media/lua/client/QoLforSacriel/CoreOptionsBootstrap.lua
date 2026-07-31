local logger = require "QoLforSacriel/Core/Logger"
local modOptions = require "QoLforSacriel/CoreModOptions"

local registered = false

local function ensureRegistered()
    if registered then
        return
    end

    local ok = pcall(function()
        modOptions.register(logger)
    end)
    if ok then
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
