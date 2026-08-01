local LightSwitchToggle = {}

local installed = false
local DEFAULT_RANGE = 1
local MAX_RANGE = 5
local MOD_OPTIONS_ID = "QoLforSacriel.Modules"
local HOTKEY_SETTING = "QoLforSacriel_LightSwitchToggle_Hotkey"
local HOTKEY_OPTION_ID = "lightSwitchToggleHotkey"

local FKEY_TO_CODE = {
    F1 = Keyboard.KEY_F1,
    F2 = Keyboard.KEY_F2,
    F3 = Keyboard.KEY_F3,
    F4 = Keyboard.KEY_F4,
    F5 = Keyboard.KEY_F5,
    F6 = Keyboard.KEY_F6,
    F7 = Keyboard.KEY_F7,
    F8 = Keyboard.KEY_F8,
    F9 = Keyboard.KEY_F9,
    F10 = Keyboard.KEY_F10,
    F11 = Keyboard.KEY_F11,
    F12 = Keyboard.KEY_F12,
}

local ALPHA_TO_CODE = {
    A = Keyboard.KEY_A, B = Keyboard.KEY_B, C = Keyboard.KEY_C, D = Keyboard.KEY_D,
    E = Keyboard.KEY_E, F = Keyboard.KEY_F, G = Keyboard.KEY_G, H = Keyboard.KEY_H,
    I = Keyboard.KEY_I, J = Keyboard.KEY_J, K = Keyboard.KEY_K, L = Keyboard.KEY_L,
    M = Keyboard.KEY_M, N = Keyboard.KEY_N, O = Keyboard.KEY_O, P = Keyboard.KEY_P,
    Q = Keyboard.KEY_Q, R = Keyboard.KEY_R, S = Keyboard.KEY_S, T = Keyboard.KEY_T,
    U = Keyboard.KEY_U, V = Keyboard.KEY_V, W = Keyboard.KEY_W, X = Keyboard.KEY_X,
    Y = Keyboard.KEY_Y, Z = Keyboard.KEY_Z,
}

local DIGIT_TO_CODE = {
    ["0"] = Keyboard.KEY_0,
    ["1"] = Keyboard.KEY_1,
    ["2"] = Keyboard.KEY_2,
    ["3"] = Keyboard.KEY_3,
    ["4"] = Keyboard.KEY_4,
    ["5"] = Keyboard.KEY_5,
    ["6"] = Keyboard.KEY_6,
    ["7"] = Keyboard.KEY_7,
    ["8"] = Keyboard.KEY_8,
    ["9"] = Keyboard.KEY_9,
}

local NUMPAD_TO_CODE = {
    NUMPAD0 = Keyboard.KEY_NUMPAD0,
    NUMPAD1 = Keyboard.KEY_NUMPAD1,
    NUMPAD2 = Keyboard.KEY_NUMPAD2,
    NUMPAD3 = Keyboard.KEY_NUMPAD3,
    NUMPAD4 = Keyboard.KEY_NUMPAD4,
    NUMPAD5 = Keyboard.KEY_NUMPAD5,
    NUMPAD6 = Keyboard.KEY_NUMPAD6,
    NUMPAD7 = Keyboard.KEY_NUMPAD7,
    NUMPAD8 = Keyboard.KEY_NUMPAD8,
    NUMPAD9 = Keyboard.KEY_NUMPAD9,
}

local EXTRA_TOKEN_TO_CODE = {
    MINUS = Keyboard.KEY_MINUS,
    EQUALS = Keyboard.KEY_EQUALS,
    COMMA = Keyboard.KEY_COMMA,
    PERIOD = Keyboard.KEY_PERIOD,
    SLASH = Keyboard.KEY_SLASH,
    SEMICOLON = Keyboard.KEY_SEMICOLON,
    APOSTROPHE = Keyboard.KEY_APOSTROPHE,
    LBRACKET = Keyboard.KEY_LBRACKET,
    RBRACKET = Keyboard.KEY_RBRACKET,
    BACKSLASH = Keyboard.KEY_BACKSLASH,
    GRAVE = Keyboard.KEY_GRAVE,
    SPACE = Keyboard.KEY_SPACE,
    TAB = Keyboard.KEY_TAB,
}

local function trimText(value)
    local text = tostring(value or "")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function normalizeHotkeyToken(value)
    local token = trimText(value)
    if token == "" then
        return nil
    end

    token = string.upper(token)
    token = token:gsub("%s+", "")
    if token:sub(1, 4) == "KEY_" then
        token = token:sub(5)
    end
    if token == "UNBOUND" or token == "NONE" then
        return nil
    end
    return token
end

local function resolveKeyCodeFromToken(token)
    local normalized = normalizeHotkeyToken(token)
    if not normalized then
        return nil
    end

    local keyCode = FKEY_TO_CODE[normalized]
    if keyCode then
        return keyCode
    end

    keyCode = ALPHA_TO_CODE[normalized]
    if keyCode then
        return keyCode
    end

    keyCode = DIGIT_TO_CODE[normalized]
    if keyCode then
        return keyCode
    end

    keyCode = NUMPAD_TO_CODE[normalized]
    if keyCode then
        return keyCode
    end

    return EXTRA_TOKEN_TO_CODE[normalized]
end

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

local function getConfiguredHotkeyBinding(settings)
    local value = settings.get(HOTKEY_SETTING)
    if value == nil then
        return Keyboard.KEY_F
    end

    local numericValue = tonumber(value)
    if numericValue ~= nil then
        local keyCode = math.floor(numericValue)
        if keyCode > 0 then
            return keyCode
        end
        return nil
    end

    local token = normalizeHotkeyToken(value)
    if not token then
        return Keyboard.KEY_F
    end

    return resolveKeyCodeFromToken(token)
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

local function isFallbackHotkeyMatch(key, settings)
    local expectedKey = getConfiguredHotkeyBinding(settings)
    if not expectedKey or key ~= expectedKey then
        return false
    end

    local expectedCtrl, expectedShift, expectedAlt = getExpectedModifierState()
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
    return dx + dy, targetSquare:getX(), targetSquare:getY()
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

local function matchesToggleHotkey(key, settings)
    local core = getCore and getCore()
    if core and core.isKey then
        local ok, matched = pcall(core.isKey, core, getHotkeyBindingName(), key)
        if ok and matched == true then
            return true
        end
    end

    return isFallbackHotkeyMatch(key, settings)
end

local function onKeyStartPressed(key, settings, logger)
    if settings.isEnabled("QoLforSacriel_EnableLightSwitchToggle") ~= true then
        return
    end
    if not matchesToggleHotkey(key, settings) then
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
