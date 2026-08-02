local WaterDepthHints = {}

local installed = false
local focusPatched = false
local originalUpdateSearchFocusCategories = nil
local DEFAULT_SHALLOW_MIN_WATER_COUNT = 2
local DEFAULT_MEDIUM_MIN_WATER_COUNT = 4
local DEFAULT_DEEP_MIN_WATER_COUNT = 7
local MIN_PUDDLE_VALUE = 0.09
local PUDDLE_TO_LITERS = 10
local MAX_TILE_WATER_LITERS = 10
local OVERLAY_REFRESH_MS = 500
local OVERLAY_MARGIN = 64

local overlayStateByPlayer = {}

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

local function inferNaturalMediumMin(shallowMin, deepMin)
    local span = deepMin - shallowMin
    local inferred = shallowMin + math.floor((span * 0.4) + 0.5)
    if inferred < shallowMin then
        return shallowMin
    end
    if inferred > deepMin then
        return deepMin
    end
    return inferred
end

local function getWaterDepthConfig(settings)
    local shallowMin = clampInteger(
        settings.get("QoLforSacriel_UIFixes_WaterDepthHints_ShallowMinWaterCount"),
        DEFAULT_SHALLOW_MIN_WATER_COUNT,
        0,
        MAX_TILE_WATER_LITERS
    )
    local deepMin = clampInteger(
        settings.get("QoLforSacriel_UIFixes_WaterDepthHints_DeepMinWaterCount"),
        DEFAULT_DEEP_MIN_WATER_COUNT,
        shallowMin,
        MAX_TILE_WATER_LITERS
    )
    local mediumMin = inferNaturalMediumMin(shallowMin, deepMin)

    return {
        radius = clampInteger(settings.get("QoLforSacriel_UIFixes_WaterDepthHints_OverlayRadius"), 3, 1, 6),
        shallowMin = shallowMin,
        mediumMin = mediumMin,
        deepMin = deepMin,
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

local function getTileWaterLiters(square)
    if not square then
        return 0
    end
    local puddleValue = getPuddleValue(square)
    if puddleValue < MIN_PUDDLE_VALUE then
        return 0
    end
    return puddleValue * PUDDLE_TO_LITERS
end

local function classifyDepth(square, logger, config)
    if not square then
        return nil
    end

    local liters = getTileWaterLiters(square)
    if liters >= config.deepMin then
        if logger then
            logger.debug("UIFixes.WaterDepthHints depth=deep liters=" .. tostring(liters) .. " at " .. fmtSquare(square))
        end
        return "deep"
    end
    if liters >= config.mediumMin then
        if logger then
            logger.debug("UIFixes.WaterDepthHints depth=medium liters=" .. tostring(liters) .. " at " .. fmtSquare(square))
        end
        return "medium"
    end
    if liters >= config.shallowMin then
        if logger then
            logger.debug("UIFixes.WaterDepthHints depth=shallow liters=" .. tostring(liters) .. " at " .. fmtSquare(square))
        end
        return "shallow"
    end
    if logger then
        logger.debug("UIFixes.WaterDepthHints depth=none liters=" .. tostring(liters) .. " at " .. fmtSquare(square))
    end
    return nil
end

local function getForagingLevel(playerObj)
    if not playerObj or not playerObj.getPerkLevel then
        return 0
    end

    local perk = nil
    if Perks and Perks.PlantScavenging then
        perk = Perks.PlantScavenging
    elseif PerkFactory and PerkFactory.Perks and PerkFactory.Perks.PlantScavenging then
        perk = PerkFactory.Perks.PlantScavenging
    end

    if not perk then
        return 0
    end

    local ok, level = pcall(function()
        return playerObj:getPerkLevel(perk)
    end)
    if not ok or type(level) ~= "number" then
        return 0
    end
    return level
end

local function shouldShowLitersForPlayer(playerObj, settings)
    if settings.get("QoLforSacriel_UIFixes_WaterDepthHints_ShowLitersAboveForaging3") ~= true then
        return false
    end
    return getForagingLevel(playerObj) > 3
end

local function formatLitersText(liters)
    return string.format("%.1fL", liters)
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
                    local depthKind = classifyDepth(sq, nil, config)
                    if depthKind then
                        accepted = accepted + 1
                        state.count = state.count + 1
                        local entry = state.entries[state.count] or {}
                        state.entries[state.count] = entry
                        entry.x = sq:getX()
                        entry.y = sq:getY()
                        entry.z = sq:getZ()
                        entry.kind = depthKind
                        entry.source = "amount"
                        entry.liters = getTileWaterLiters(sq)
                        entry.text = getOverlayText(depthKind)
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

local function drawOverlayForPlayer(playerObj, playerIndex, state, settings)
    local textManager = getTextManager and getTextManager() or nil
    if not textManager then
        return
    end

    local showLiters = shouldShowLitersForPlayer(playerObj, settings)

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
                local displayText = entry.text
                if showLiters and type(entry.liters) == "number" then
                    displayText = formatLitersText(entry.liters)
                end
                local w = textManager:MeasureStringX(UIFont.Small, displayText)
                textManager:DrawString(UIFont.Small, sx - (w / 2), sy - 12, displayText, r, g, b, 0.95)
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
                drawOverlayForPlayer(playerObj, playerIndex, state, settings)
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
