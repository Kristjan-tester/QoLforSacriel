local WaterDepthHints = {}

local installed = false
local focusPatched = false
local originalUpdateSearchFocusCategories = nil
local DEFAULT_SHALLOW_MIN_WATER_COUNT = 2
local DEFAULT_MEDIUM_MIN_WATER_COUNT = 4
local DEFAULT_DEEP_MIN_WATER_COUNT = 7
local PUDDLE_MIN = 0.09
local DEFAULT_SHALLOW_MIN_PUDDLE = 0.20
local DEFAULT_MEDIUM_MIN_PUDDLE = 0.50
local DEFAULT_DEEP_MIN_PUDDLE = 0.75
local OVERLAY_REFRESH_MS = 500
local OVERLAY_MARGIN = 64

local overlayStateByPlayer = {}

local IsoFlagType_water = (IsoFlagType and IsoFlagType.water) or nil
local WATER_IDX = 63
if IsoFlagType_water and IsoFlagType_water.index then
    local ok, value = pcall(function()
        return IsoFlagType_water:index()
    end)
    if ok and type(value) == "number" then
        WATER_IDX = value
    end
end

local hasEnumHas = nil
local hasEnumIs = nil
local hasSquareEnumIs = nil

local function clampInteger(value, fallback, minValue, maxValue)
    local n = tonumber(value)
    if not n then
        n = fallback
    end
    n = math.floor(n)
    if n < minValue then
        return minValue
    end
    if n > maxValue then
        return maxValue
    end
    return n
end

local function clampNumber(value, fallback, minValue, maxValue)
    local n = tonumber(value)
    if not n then
        n = fallback
    end
    if n < minValue then
        return minValue
    end
    if n > maxValue then
        return maxValue
    end
    return n
end

local function getWaterDepthConfig(settings)
    local shallowPuddleMin = clampNumber(
        settings.get("QoLforSacriel_UIFixes_WaterDepthHints_ShallowMinPuddle"),
        DEFAULT_SHALLOW_MIN_PUDDLE,
        PUDDLE_MIN,
        1.0
    )
    local mediumPuddleMin = clampNumber(
        settings.get("QoLforSacriel_UIFixes_WaterDepthHints_MediumMinPuddle"),
        DEFAULT_MEDIUM_MIN_PUDDLE,
        shallowPuddleMin,
        1.0
    )
    local deepPuddleMin = clampNumber(
        settings.get("QoLforSacriel_UIFixes_WaterDepthHints_DeepMinPuddle"),
        DEFAULT_DEEP_MIN_PUDDLE,
        mediumPuddleMin,
        1.0
    )

    return {
        radius = clampInteger(settings.get("QoLforSacriel_UIFixes_WaterDepthHints_OverlayRadius"), 3, 1, 6),
        shallowMin = clampInteger(settings.get("QoLforSacriel_UIFixes_WaterDepthHints_ShallowMinWaterCount"), DEFAULT_SHALLOW_MIN_WATER_COUNT, 0, 25),
        mediumMin = clampInteger(settings.get("QoLforSacriel_UIFixes_WaterDepthHints_MediumMinWaterCount"), DEFAULT_MEDIUM_MIN_WATER_COUNT, 0, 25),
        deepMin = clampInteger(settings.get("QoLforSacriel_UIFixes_WaterDepthHints_DeepMinWaterCount"), DEFAULT_DEEP_MIN_WATER_COUNT, 0, 25),
        shallowPuddleMin = shallowPuddleMin,
        mediumPuddleMin = mediumPuddleMin,
        deepPuddleMin = deepPuddleMin,
    }
end

local function fmtSquare(square)
    if not square then
        return "nil"
    end
    return tostring(square:getX()) .. "," .. tostring(square:getY()) .. "," .. tostring(square:getZ())
end

local function getPlayerSquare(playerObj)
    if not playerObj or not playerObj.getSquare then
        return nil
    end
    return playerObj:getSquare()
end

local function getWaterFocusLabel()
    return getTextOrNull("UI_QoLforSacriel_ForagingSearchFocusWater") or "Water"
end

local function getOverlayText(kind)
    if kind == "deep" then
        return getTextOrNull("UI_QoLforSacriel_WaterOverlay_Deep") or "Deep"
    end
    if kind == "medium" then
        return getTextOrNull("UI_QoLforSacriel_WaterOverlay_Medium") or "Medium"
    end
    return getTextOrNull("UI_QoLforSacriel_WaterOverlay_Shallow") or "Shallow"
end

local function patchForagingSearchFocus(logger)
    if focusPatched then
        return
    end
    if not ISSearchWindow or not ISSearchWindow.updateSearchFocusCategories then
        logger.debug("UIFixes.WaterDepthHints could not patch ISSearchWindow focus list")
        return
    end

    originalUpdateSearchFocusCategories = ISSearchWindow.updateSearchFocusCategories

    ISSearchWindow.updateSearchFocusCategories = function(self)
        local previousFocus = self.searchFocusCategory
        originalUpdateSearchFocusCategories(self)

        local hasWater = false
        for i = 1, #self.searchFocus.options do
            if self.searchFocus.options[i].data == "Water" then
                hasWater = true
                break
            end
        end

        if not hasWater then
            self.searchFocus:addOptionWithData(getWaterFocusLabel(), "Water")
        end

        if previousFocus == "Water" then
            for i = 1, #self.searchFocus.options do
                if self.searchFocus.options[i].data == "Water" then
                    self.searchFocus.selected = i
                    self.searchFocusCategory = "Water"
                    break
                end
            end
        end
    end

    focusPatched = true
    logger.info("UIFixes.WaterDepthHints added Foraging focus option: Water")
end

local function isWaterFocusSelected(playerIndex)
    if not ISSearchWindow or not ISSearchWindow.players then
        return false
    end

    local playerObj = getSpecificPlayer(playerIndex)
    if not playerObj then
        return false
    end

    local searchWindow = ISSearchWindow.players[playerObj]
    if not searchWindow then
        return false
    end

    return searchWindow.searchFocusCategory == "Water"
end

local function isSearchModeEnabled(playerIndex)
    if not ISSearchManager or not ISSearchManager.players then
        return false
    end

    local playerObj = getSpecificPlayer(playerIndex)
    if not playerObj then
        return false
    end

    local manager = ISSearchManager.players[playerObj]
    return manager and manager.isSearchMode == true
end

local function isNaturalWaterSquare(square)
    if not square then
        return false
    end

    local props = square.getProperties and square:getProperties() or nil
    if props then
        if props.has then
            if props:has(WATER_IDX) then
                return true
            end
            if IsoFlagType_water then
                if hasEnumHas == nil then
                    hasEnumHas = pcall(function()
                        return props:has(IsoFlagType_water)
                    end)
                end
                if hasEnumHas and props:has(IsoFlagType_water) then
                    return true
                end
            end
        end

        if props.Is then
            if props:Is(WATER_IDX) then
                return true
            end
            if props:Is("water") then
                return true
            end
            if IsoFlagType_water then
                if hasEnumIs == nil then
                    hasEnumIs = pcall(function()
                        return props:Is(IsoFlagType_water)
                    end)
                end
                if hasEnumIs and props:Is(IsoFlagType_water) then
                    return true
                end
            end
        end
    end

    if square.Is then
        if square:Is("water") then
            return true
        end
        if IsoFlagType_water then
            if hasSquareEnumIs == nil then
                hasSquareEnumIs = pcall(function()
                    return square:Is(IsoFlagType_water)
                end)
            end
            if hasSquareEnumIs and square:Is(IsoFlagType_water) then
                return true
            end
        end
    end

    local floor = square:getFloor()
    if floor and floor:hasProperty(IsoFlagType.water) then
        return true
    end
    return false
end

local function getPuddleValue(square)
    if not square or not square.getPuddlesInGround then
        return 0
    end
    local value = square:getPuddlesInGround()
    if type(value) ~= "number" then
        return 0
    end
    return value
end

local function isPuddleSquare(square, minValue)
    local threshold = tonumber(minValue) or PUDDLE_MIN
    return getPuddleValue(square) >= threshold
end

local function resolveWaterSource(square, logger, config)
    if not square then
        return nil, nil
    end

    if isNaturalWaterSquare(square) then
        if logger then
            logger.debug("UIFixes.WaterDepthHints source=natural at " .. fmtSquare(square))
        end
        return square, "natural"
    end

    local shallowPuddleMin = config and config.shallowPuddleMin or PUDDLE_MIN
    if isPuddleSquare(square, shallowPuddleMin) then
        if logger then
            logger.debug("UIFixes.WaterDepthHints source=puddle at " .. fmtSquare(square) .. " puddles=" .. tostring(getPuddleValue(square)))
        end
        return square, "puddle"
    end

    if logger then
        logger.debug("UIFixes.WaterDepthHints source=none at " .. fmtSquare(square) .. " puddles=" .. tostring(getPuddleValue(square)))
    end

    return nil, nil
end

local function classifyDepth(square, sourceKind, logger, config)
    if not square then
        return nil
    end

    if sourceKind == "puddle" then
        local puddleValue = getPuddleValue(square)
        if puddleValue < config.shallowPuddleMin then
            if logger then
                logger.debug("UIFixes.WaterDepthHints depth=none source=puddle value=" .. tostring(puddleValue) .. " below shallowMin=" .. tostring(config.shallowPuddleMin) .. " at " .. fmtSquare(square))
            end
            return nil
        end
        if puddleValue >= config.deepPuddleMin then
            if logger then
                logger.debug("UIFixes.WaterDepthHints depth=deep source=puddle value=" .. tostring(puddleValue) .. " at " .. fmtSquare(square))
            end
            return "deep"
        end
        if puddleValue >= config.mediumPuddleMin then
            if logger then
                logger.debug("UIFixes.WaterDepthHints depth=medium source=puddle value=" .. tostring(puddleValue) .. " at " .. fmtSquare(square))
            end
            return "medium"
        end
        if logger then
            logger.debug("UIFixes.WaterDepthHints depth=shallow source=puddle value=" .. tostring(puddleValue) .. " at " .. fmtSquare(square))
        end
        return "shallow"
    end

    local waterCount = 0
    for dy = -2, 2 do
        for dx = -2, 2 do
            local sq = getSquare(square:getX() + dx, square:getY() + dy, square:getZ())
            if isNaturalWaterSquare(sq) then
                waterCount = waterCount + 1
            end
        end
    end

    if waterCount >= config.deepMin then
        if logger then
            logger.debug("UIFixes.WaterDepthHints depth=deep naturalCount=" .. tostring(waterCount) .. " at " .. fmtSquare(square))
        end
        return "deep"
    end
    if waterCount >= config.mediumMin then
        if logger then
            logger.debug("UIFixes.WaterDepthHints depth=medium naturalCount=" .. tostring(waterCount) .. " at " .. fmtSquare(square))
        end
        return "medium"
    end
    if waterCount >= config.shallowMin then
        if logger then
            logger.debug("UIFixes.WaterDepthHints depth=shallow naturalCount=" .. tostring(waterCount) .. " at " .. fmtSquare(square))
        end
        return "shallow"
    end
    if logger then
        logger.debug("UIFixes.WaterDepthHints depth=none naturalCount=" .. tostring(waterCount) .. " at " .. fmtSquare(square))
    end
    return nil
end

local function shouldRenderForPlayer(playerIndex, settings, logger)
    if settings.isEnabled("QoLforSacriel_EnableUIFixes") ~= true then
        return false
    end
    if settings.isEnabled("QoLforSacriel_UIFixes_EnableWaterDepthHints") ~= true then
        return false
    end
    if not isSearchModeEnabled(playerIndex) then
        return false
    end
    if not isWaterFocusSelected(playerIndex) then
        return false
    end
    return true
end

local function ensurePlayerOverlayState(playerIndex)
    local state = overlayStateByPlayer[playerIndex]
    if not state then
        state = {
            entries = {},
            count = 0,
            nextRefresh = 0,
            lastCenterX = nil,
            lastCenterY = nil,
            lastCenterZ = nil,
        }
        overlayStateByPlayer[playerIndex] = state
    end
    return state
end

local function refreshOverlayData(playerObj, playerIndex, state, logger, settings)
    local square = getPlayerSquare(playerObj)
    if not square then
        state.count = 0
        return
    end

    local cx = square:getX()
    local cy = square:getY()
    local cz = square:getZ()
    local config = getWaterDepthConfig(settings)

    local scanned = 0
    local accepted = 0
    state.count = 0
    for dy = -config.radius, config.radius do
        for dx = -config.radius, config.radius do
            if dx * dx + dy * dy <= config.radius * config.radius then
                local sq = getSquare(cx + dx, cy + dy, cz)
                if sq then
                    scanned = scanned + 1
                    local sourceSquare, sourceKind = resolveWaterSource(sq, nil, config)
                    if sourceSquare then
                        local depthKind = classifyDepth(sourceSquare, sourceKind, nil, config)
                        if depthKind then
                            accepted = accepted + 1
                            state.count = state.count + 1
                            local entry = state.entries[state.count] or {}
                            state.entries[state.count] = entry
                            entry.x = sourceSquare:getX()
                            entry.y = sourceSquare:getY()
                            entry.z = sourceSquare:getZ()
                            entry.kind = depthKind
                            entry.source = sourceKind
                            entry.text = getOverlayText(depthKind)
                        end
                    end
                end
            end
        end
    end

    for i = state.count + 1, #state.entries do
        state.entries[i] = nil
    end

    state.lastCenterX = cx
    state.lastCenterY = cy
    state.lastCenterZ = cz
    state.nextRefresh = getTimestampMs() + OVERLAY_REFRESH_MS

    -- Intentionally no per-refresh debug log to avoid render-loop spam.
end

local function colorForKind(kind)
    if kind == "deep" then
        return 0.05, 0.35, 1.00
    end
    if kind == "medium" then
        return 0.10, 0.85, 1.00
    end
    return 1.00, 0.92, 0.20
end

local function drawOverlayForPlayer(playerObj, playerIndex, state)
    local textManager = getTextManager and getTextManager() or nil
    if not textManager then
        return
    end

    local z = playerObj:getZ()
    local playerNum = playerObj:getPlayerNum()
    local core = getCore and getCore() or nil
    local zoom = core and core.getZoom and core:getZoom(playerNum) or 1
    local screenW = getPlayerScreenWidth and getPlayerScreenWidth(playerNum) or (core and core:getScreenWidth() or 0)
    local screenH = getPlayerScreenHeight and getPlayerScreenHeight(playerNum) or (core and core:getScreenHeight() or 0)
    local worldW = screenW * zoom
    local worldH = screenH * zoom

    for i = 1, state.count do
        local entry = state.entries[i]
        if entry and entry.z == z then
            local sx = IsoUtils.XToScreenExact(entry.x + 0.5, entry.y + 0.5, z, 0)
            local sy = IsoUtils.YToScreenExact(entry.x + 0.5, entry.y + 0.5, z, 0)
            if sx >= -OVERLAY_MARGIN and sy >= -OVERLAY_MARGIN and sx <= worldW + OVERLAY_MARGIN and sy <= worldH + OVERLAY_MARGIN then
                local r, g, b = colorForKind(entry.kind)
                local w = textManager:MeasureStringX(UIFont.Small, entry.text)
                textManager:DrawString(UIFont.Small, sx - (w / 2), sy - 12, entry.text, r, g, b, 0.95)
            end
        end
    end
end

local function onPostRender(settings, logger)
    if isServer and isServer() and not isClient() then
        return
    end

    local activePlayers = getNumActivePlayers and getNumActivePlayers() or 1
    for playerIndex = 0, activePlayers - 1 do
        local playerObj = getSpecificPlayer(playerIndex)
        if playerObj then
            local state = ensurePlayerOverlayState(playerIndex)
            if shouldRenderForPlayer(playerIndex, settings, logger) then
                if getTimestampMs() >= state.nextRefresh then
                    refreshOverlayData(playerObj, playerIndex, state, logger, settings)
                end
                drawOverlayForPlayer(playerObj, playerIndex, state)
            else
                state.count = 0
            end
        end
    end
end

function WaterDepthHints.init(settings, logger)
    if installed then
        logger.debug("UIFixes.WaterDepthHints already installed")
        return
    end

    patchForagingSearchFocus(logger)

    Events.OnPostRender.Add(function()
        local ok, err = pcall(function()
            onPostRender(settings, logger)
        end)
        if not ok then
            logger.error("UIFixes.WaterDepthHints render error: " .. tostring(err))
        end
    end)

    installed = true
    logger.info("UIFixes.WaterDepthHints installed (overlay mode)")
end

return WaterDepthHints
