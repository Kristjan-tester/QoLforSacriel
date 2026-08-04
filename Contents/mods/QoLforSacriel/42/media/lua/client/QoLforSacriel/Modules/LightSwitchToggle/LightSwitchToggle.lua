local LightSwitchToggle = {}

local installed = false
local DEFAULT_RANGE = 1
local MAX_RANGE = 3
local MOD_OPTIONS_ID = "QoLforSacriel.Modules"
local HOTKEY_OPTION_ID = "lightSwitchToggleHotkey"

local function getLightSwitchHotkeyOption()
    if not PZAPI or not PZAPI.ModOptions or not PZAPI.ModOptions.getOptions then
        return nil
    end

    local options = PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)
    if not options or not options.getOption then
        return nil
    end

    return options:getOption(HOTKEY_OPTION_ID)
end

local function getHotkeyBindingName()
    local option = getLightSwitchHotkeyOption()
    if option and option.name and option.name ~= "" then
        return option.name
    end

    return getTextOrNull("UI_QoLforSacriel_Modules_LightSwitchToggleHotkey") or "Toggle Nearby Light Switch Key"
end

local function getExpectedModifierState()
    local option = getLightSwitchHotkeyOption()
    local source = option
    if option and type(option.element) == "table" then
        source = option.element
    end

    local ctrl = true
    local shift = false
    local alt = false

    if source then
        if source.ctrl ~= nil then
            ctrl = source.ctrl == true
        end
        if source.shift ~= nil then
            shift = source.shift == true
        end
        if source.alt ~= nil then
            alt = source.alt == true
        end
    end

    return ctrl, shift, alt
end

local function isModifierDown(functionName)
    local fn = _G[functionName]
    if type(fn) ~= "function" then
        return false
    end

    local ok, state = pcall(fn)
    if not ok then
        return false
    end
    return state == true
end

local function isModifierStateMatched(expectedCtrl, expectedShift, expectedAlt)
    local ctrlDown = isModifierDown("isCtrlKeyDown")
    local shiftDown = isModifierDown("isShiftKeyDown")
    local altDown = isModifierDown("isAltKeyDown")

    return ctrlDown == expectedCtrl
        and shiftDown == expectedShift
        and altDown == expectedAlt
end

local function toInteger(value, fallback)
    local n = tonumber(value)
    if not n then
        return fallback
    end
    n = math.floor(n)
    return n
end

local function getSearchRange(settings)
    local value = settings.get("QoLforSacriel_LightSwitchToggle_Range")
    local range = toInteger(value, DEFAULT_RANGE)
    if range < 0 then
        range = 0
    elseif range > MAX_RANGE then
        range = MAX_RANGE
    end
    return range
end

local function shouldRequireSameRoom(settings)
    return settings.get("QoLforSacriel_LightSwitchToggle_RequireSameRoom") == true
end

local function isSameRoom(playerSquare, targetSquare)
    if not playerSquare or not targetSquare then
        return false
    end

    local playerRoom = playerSquare:getRoom()
    local targetRoom = targetSquare:getRoom()

    if playerRoom == nil or targetRoom == nil then
        return playerRoom == targetRoom
    end

    return playerRoom == targetRoom
end

local function canSwitchLight(lightSwitch)
    if not lightSwitch then
        return false
    end
    if not lightSwitch.canSwitchLight then
        return true
    end

    local ok, result = pcall(lightSwitch.canSwitchLight, lightSwitch)
    if not ok then
        return true
    end

    return result ~= false
end

local function scoreSwitch(playerSquare, targetSquare)
    local dx = math.abs(targetSquare:getX() - playerSquare:getX())
    local dy = math.abs(targetSquare:getY() - playerSquare:getY())
    -- Chebyshev distance keeps diagonals in-range (range=1 includes 8 neighboring tiles).
    return math.max(dx, dy), targetSquare:getX(), targetSquare:getY()
end

local function chooseBetterCandidate(current, candidate)
    if not current then
        return true
    end
    if candidate.distance ~= current.distance then
        return candidate.distance < current.distance
    end
    if candidate.x ~= current.x then
        return candidate.x < current.x
    end
    return candidate.y < current.y
end

local function findNearestLightSwitch(playerObj, settings)
    local playerSquare = playerObj and playerObj:getSquare()
    if not playerSquare then
        return nil
    end

    local range = getSearchRange(settings)
    local requireSameRoom = shouldRequireSameRoom(settings)
    local z = playerSquare:getZ()
    local best = nil

    for y = playerSquare:getY() - range, playerSquare:getY() + range do
        for x = playerSquare:getX() - range, playerSquare:getX() + range do
            local square = getCell():getGridSquare(x, y, z)
            if square then
                local objects = square:getObjects()
                if objects then
                    for i = 0, objects:size() - 1 do
                        local obj = objects:get(i)
                        if obj and instanceof(obj, "IsoLightSwitch") then
                            local distance, targetX, targetY = scoreSwitch(playerSquare, square)
                            if distance <= range then
                                if (not requireSameRoom or isSameRoom(playerSquare, square)) and canSwitchLight(obj) then
                                    local candidate = {
                                        lightSwitch = obj,
                                        distance = distance,
                                        x = targetX,
                                        y = targetY,
                                    }
                                    if chooseBetterCandidate(best, candidate) then
                                        best = candidate
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return best and best.lightSwitch or nil
end

local function matchesToggleHotkey(key)
    local core = getCore and getCore()
    if not core or not core.isKey then
        return false
    end

    local ok, matched = pcall(core.isKey, core, getHotkeyBindingName(), key)
    if not ok or matched ~= true then
        return false
    end

    local expectedCtrl, expectedShift, expectedAlt = getExpectedModifierState()
    return isModifierStateMatched(expectedCtrl, expectedShift, expectedAlt)
end

local function onKeyStartPressed(key, settings, logger)
    if settings.isEnabled("QoLforSacriel_EnableLightSwitchToggle") ~= true then
        return
    end
    if not matchesToggleHotkey(key) then
        return
    end

    local playerObj = getSpecificPlayer(0)
    if not playerObj or playerObj:isDead() then
        return
    end

    local lightSwitch = findNearestLightSwitch(playerObj, settings)
    if not lightSwitch then
        if logger and logger.debug then
            logger.debug("LightSwitchToggle: no eligible light switch found")
        end
        return
    end

    local ok, toggled = pcall(lightSwitch.toggle, lightSwitch)
    if not ok then
        if logger and logger.error then
            logger.error("LightSwitchToggle: toggle failed | " .. tostring(toggled))
        end
        return
    end

    if toggled == false and logger and logger.debug then
        logger.debug("LightSwitchToggle: toggle call returned false")
    end
end

function LightSwitchToggle.init(settings, logger)
    if installed then
        if logger and logger.debug then
            logger.debug("LightSwitchToggle already installed")
        end
        return
    end

    Events.OnKeyStartPressed.Add(function(key)
        local ok, err = pcall(function()
            onKeyStartPressed(key, settings, logger)
        end)
        if not ok and logger and logger.error then
            logger.error("LightSwitchToggle key error: " .. tostring(err))
        end
    end)

    installed = true
    if logger and logger.info then
        logger.info("LightSwitchToggle installed")
    end
end

return LightSwitchToggle
