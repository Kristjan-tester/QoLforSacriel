require "ISUI/ISUIElement"

local SoundOverlayRenderer = {}

local VERTICAL_MARKER_OFFSET = 10
local MAX_LABEL_LENGTH = 20
local ARROW_TEXTURE_PATH = "media/textures/SoundArrowBase.png"
local PLAYER_SOUND_RING_TEXTURE_PATH = "media/textures/PlayerWorldSoundRing.png"

local OverlayHost = ISUIElement:derive("QoLforSacrielSoundOverlayHost")
local overlayHost = nil
local arrowTexture = nil
local playerSoundRingTexture = nil

function OverlayHost:initialise()
    ISUIElement.initialise(self)
    self:instantiate()
    self:setWantKeyEvents(false)
    self:setWantMouseEvents(false)
    self:setWantExtraMouseEvents(false)
    self:setVisible(true)
end

function OverlayHost:onMouseMove()
    return false
end

function OverlayHost:onMouseUp()
    return false
end

function OverlayHost:onRightMouseUp()
    return false
end

function OverlayHost:onMouseDown()
    return false
end

function OverlayHost:onRightMouseDown()
    return false
end

function OverlayHost:onRightMouseDownOutside()
    return false
end

function OverlayHost:onRightMouseUpOutside()
    return false
end

function OverlayHost:prerender()
end

function OverlayHost:render()
end

local function ensureOverlayHost()
    if overlayHost and overlayHost.javaObject then
        return overlayHost
    end

    local core = getCore and getCore() or nil
    local width = core and core.getScreenWidth and core:getScreenWidth() or 1920
    local height = core and core.getScreenHeight and core:getScreenHeight() or 1080

    local host = ISUIElement:new(0, 0, width, height)
    setmetatable(host, OverlayHost)
    OverlayHost.__index = OverlayHost
    host:initialise()
    overlayHost = host
    return overlayHost
end

local function getArrowTexture()
    if arrowTexture then
        return arrowTexture
    end

    if not getTexture then
        return nil
    end

    arrowTexture = getTexture(ARROW_TEXTURE_PATH)
    return arrowTexture
end

local function getPlayerSoundRingTexture()
    if playerSoundRingTexture then
        return playerSoundRingTexture
    end

    if not getTexture then
        return nil
    end

    playerSoundRingTexture = getTexture(PLAYER_SOUND_RING_TEXTURE_PATH)
    return playerSoundRingTexture
end

local function readStringMethod(obj, methodName, ...)
    if not obj or not obj[methodName] then
        return nil
    end

    local args = {...}

    local ok, value = pcall(function()
        return obj[methodName](obj, unpack(args))
    end)
    if not ok or value == nil then
        return nil
    end

    local text = tostring(value)
    if text == "" or text == "nil" then
        return nil
    end
    return text
end

local function animalLabelFromSource(source)
    if not source then
        return nil
    end

    local kind = readStringMethod(source, "getAnimalType")
        or readStringMethod(source, "getAnimalName")
        or readStringMethod(source, "getScriptName")

    local breedText = nil
    if source.getBreed then
        local ok, breed = pcall(function()
            return source:getBreed()
        end)
        if ok and breed then
            breedText = readStringMethod(breed, "getName") or tostring(breed)
        end
    end

    if kind and breedText and breedText ~= kind then
        return kind .. " " .. breedText
    end
    if breedText then
        return breedText
    end
    if kind then
        return kind
    end

    return nil
end

local function playerSoundHintFromSource(source)
    local ext = readStringMethod(source, "getVariableString", "Ext")
    if ext and ext ~= "" and ext ~= "none" then
        return "player " .. string.lower(ext)
    end
    return nil
end

local function loudnessScaleFromCue(cue)
    if not cue or cue.hasLoudness ~= true then
        return 1.0
    end

    local volume = tonumber(cue.volume)
    if not volume or volume <= 0 then
        return 1.0
    end

    -- World-sound volumes vary widely; log scaling keeps quiet sounds near the
    -- configured minimum size while still letting loud sounds grow visibly.
    local normalized = math.log(volume + 1) / math.log(601)
    if normalized < 0 then
        normalized = 0
    elseif normalized > 1 then
        normalized = 1
    end

    return 1.0 + (normalized * 1.8)
end

local function arrowStyle(config, cue)
    local scalePct = (config and config.arrowScalePercent) or 100
    local baseScale = scalePct / 100
    local scale = baseScale * loudnessScaleFromCue(cue)

    local font = UIFont.Large
    if scale < 0.8 then
        font = UIFont.Small
    elseif scale < 1.2 then
        font = UIFont.Medium
    end

    return {
        font = font,
        symbolSize = math.floor((24 * scale) + 0.5),
        ringRadius = math.floor((58 * scale) + 0.5),
        textureSize = math.floor((36 * scale) + 0.5),
    }
end

local function baseRingRadius(config)
    local scalePct = (config and config.arrowScalePercent) or 100
    local baseScale = scalePct / 100
    return math.floor((58 * baseScale) + 0.5)
end

local function sourceLabelForCue(cue)
    if cue.feed == "ambient" and type(cue.source) == "string" and cue.source ~= "" then
        return cue.source
    end

    if cue.labelHint and cue.labelHint ~= "" then
        return cue.labelHint
    end

    if cue.category == "Inferred" then
        return "zombie?"
    end

    if cue.sourceType == "zombie" then
        return "zombie"
    end
    if cue.sourceType == "player" then
        return playerSoundHintFromSource(cue.source) or "player-world"
    end
    if cue.sourceType == "vehicle" then
        return "vehicle"
    end
    if cue.sourceType == "alarm-device" then
        return "alarm"
    end
    if cue.sourceType == "device" then
        return "tv/radio"
    end
    if cue.sourceType == "animal" then
        return animalLabelFromSource(cue.source) or "animal"
    end
    if cue.sourceType == "animal-inferred" then
        return animalLabelFromSource(cue.source) or "animal?"
    end

    if cue.category and cue.category ~= "" then
        return string.lower(tostring(cue.category))
    end

    return "sound"
end

local function compactLabel(label)
    local text = tostring(label or "")
    text = string.gsub(text, "_", " ")
    text = string.gsub(text, "%-", " ")
    text = string.gsub(text, "%s+", " ")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")

    if string.len(text) <= MAX_LABEL_LENGTH then
        return text
    end

    return string.sub(text, 1, MAX_LABEL_LENGTH - 1) .. "..."
end

local function colorFromCue(cue, nowMs)
    local lifeMs = math.max(1, cue.expiresAtMs - cue.createdAtMs)
    local lifeLeft = math.max(0, cue.expiresAtMs - nowMs)
    local t = lifeLeft / lifeMs
    local a = 0.25 + (0.75 * t)

    if cue.outsideHearing == true then
        return 1.0, 1.0, 1.0, a
    end

    local intensity = 0.5
    if cue.adjustedRadius and cue.adjustedRadius > 0 and cue.distance then
        intensity = 1.0 - math.min(1.0, cue.distance / cue.adjustedRadius)
    end

    local r = 0.25 + (0.75 * intensity)
    local g = 0.9 - (0.7 * intensity)
    local b = 0.2

    return r, g, b, a
end

local function symbolForVector(dx, dy)
    if math.abs(dx) >= math.abs(dy) then
        if dx >= 0 then
            return ">"
        end
        return "<"
    end

    if dy >= 0 then
        return "v"
    end
    return "^"
end

local function drawTextureArrow(host, texture, centerX, centerY, size, ux, uy, r, g, b, a)
    if not host or not host.drawTextureAllPoint or not texture then
        return false
    end

    local halfSize = size / 2
    local rightX = -uy
    local rightY = ux
    local downX = -ux
    local downY = -uy

    local function mapPoint(localX, localY)
        return centerX + (rightX * localX) + (downX * localY), centerY + (rightY * localX) + (downY * localY)
    end

    local tlx, tly = mapPoint(-halfSize, -halfSize)
    local trx, try = mapPoint(halfSize, -halfSize)
    local brx, bry = mapPoint(halfSize, halfSize)
    local blx, bly = mapPoint(-halfSize, halfSize)

    host:drawTextureAllPoint(texture, tlx, tly, trx, try, brx, bry, blx, bly, r, g, b, a)
    return true
end

local function cueScreenVector(playerObj, cue)
    local pz = playerObj:getZ()
    local cueZ = cue.z or pz

    local px = IsoUtils.XToScreenExact(playerObj:getX() + 0.5, playerObj:getY() + 0.5, pz, 0)
    local py = IsoUtils.YToScreenExact(playerObj:getX() + 0.5, playerObj:getY() + 0.5, pz, 0)

    local sx = IsoUtils.XToScreenExact(cue.x + 0.5, cue.y + 0.5, cueZ, 0)
    local sy = IsoUtils.YToScreenExact(cue.x + 0.5, cue.y + 0.5, cueZ, 0)

    return (sx - px), (sy - py), px, py
end

function SoundOverlayRenderer.renderCue(playerObj, cue, nowMs, config)
    if not playerObj or not cue then
        return
    end

    local style = arrowStyle(config, cue)
    local dx, dy, centerX, centerY = cueScreenVector(playerObj, cue)
    local len = math.sqrt((dx * dx) + (dy * dy))
    if len < 0.001 then
        return
    end

    local ux = dx / len
    local uy = dy / len

    local x = centerX + (ux * style.ringRadius)
    local y = centerY + (uy * style.ringRadius)
    local symbol = symbolForVector(dx, dy)
    local r, g, b, a = colorFromCue(cue, nowMs)
    local host = ensureOverlayHost()
    local texture = getArrowTexture()
    local usedTexture = false

    if host and texture then
        usedTexture = drawTextureArrow(host, texture, x, y, style.textureSize, ux, uy, r, g, b, a)
    end

    if not usedTexture then
        getTextManager():DrawString(style.font, x - style.symbolSize, y - style.symbolSize, symbol, r, g, b, a)
    end

    if config and config.showSourceLabel == true then
        local label = compactLabel(sourceLabelForCue(cue))
        if label == "" then
            label = "sound"
        end
        local labelRadius = baseRingRadius(config)
        local labelX = centerX + (ux * (labelRadius + 8))
        local labelY = centerY + (uy * (labelRadius + 8))
        getTextManager():DrawString(UIFont.Small, labelX + 6, labelY + 4, label, 1.0, 1.0, 1.0, a)
    end

    if config and config.zMarkerEnabled ~= true then
        return
    end

    if cue.hasZ == true and cue.z ~= nil then
        local playerZ = playerObj:getZ()
        local zDelta = cue.z - playerZ
        if zDelta ~= 0 then
            local vertical = zDelta > 0 and "^" or "v"
            local markerOffset = math.max(VERTICAL_MARKER_OFFSET, math.floor((style.textureSize or 0) * 0.6))
            local markerX = x + (-uy * markerOffset)
            local markerY = y + (ux * markerOffset)
            getTextManager():DrawString(UIFont.Medium, markerX - 6, markerY - 6, vertical, r, g, b, a)
        end
    end
end

local function playerSoundRingAlpha(ring, nowMs, config)
    local lifeMs = math.max(1, ring.expiresAtMs - ring.createdAtMs)
    local lifeLeft = math.max(0, ring.expiresAtMs - nowMs)
    local opacityPercent = (config and config.playerWorldSoundRingOpacityPercent) or 25
    local maxAlpha = math.max(0.05, math.min(0.80, opacityPercent / 100))
    return maxAlpha * (lifeLeft / lifeMs)
end

local function playerSoundRingProgress(ring, nowMs)
    local lifeMs = math.max(1, ring.expiresAtMs - ring.createdAtMs)
    local elapsed = math.max(0, nowMs - ring.createdAtMs)
    return math.min(1, elapsed / lifeMs)
end

local function projectWorldPoint(x, y, z)
    return IsoUtils.XToScreenExact(x, y, z, 0), IsoUtils.YToScreenExact(x, y, z, 0)
end

local function isQuadNearViewport(points, config)
    local core = getCore and getCore() or nil
    local width = getPlayerScreenWidth and getPlayerScreenWidth(0) or (core and core.getScreenWidth and core:getScreenWidth() or 0)
    local height = getPlayerScreenHeight and getPlayerScreenHeight(0) or (core and core.getScreenHeight and core:getScreenHeight() or 0)
    local zoom = core and core.getZoom and core:getZoom(0) or 1
    local margin = (config and config.playerWorldSoundRingCullingMarginPx) or 128
    margin = math.max(0, math.floor(tonumber(margin) or 128))
    local maxX = (width * zoom) + margin
    local maxY = (height * zoom) + margin
    local minQuadX = points[1].x
    local maxQuadX = points[1].x
    local minQuadY = points[1].y
    local maxQuadY = points[1].y

    for i = 2, #points do
        local point = points[i]
        if point.x < minQuadX then
            minQuadX = point.x
        elseif point.x > maxQuadX then
            maxQuadX = point.x
        end
        if point.y < minQuadY then
            minQuadY = point.y
        elseif point.y > maxQuadY then
            maxQuadY = point.y
        end
    end

    return maxQuadX >= -margin and minQuadX <= maxX and maxQuadY >= -margin and minQuadY <= maxY
end

function SoundOverlayRenderer.renderPlayerWorldSoundRing(playerObj, ring, nowMs, config)
    if not playerObj or not ring then
        return
    end
    if not config or config.playerWorldSoundRingsEnabled ~= true then
        return
    end

    local texture = getPlayerSoundRingTexture()
    if not texture then
        return
    end

    local progress = playerSoundRingProgress(ring, nowMs)
    local rawRadius = tonumber(ring.radius) or 0
    local worldRadius = math.max(0.25, rawRadius * progress)
    local z = ring.z ~= nil and ring.z or playerObj:getZ()
    local x = ring.x + 0.5
    local y = ring.y + 0.5
    local topLeftX, topLeftY = projectWorldPoint(x - worldRadius, y - worldRadius, z)
    local topRightX, topRightY = projectWorldPoint(x + worldRadius, y - worldRadius, z)
    local bottomRightX, bottomRightY = projectWorldPoint(x + worldRadius, y + worldRadius, z)
    local bottomLeftX, bottomLeftY = projectWorldPoint(x - worldRadius, y + worldRadius, z)
    local points = {
        { x = topLeftX, y = topLeftY },
        { x = topRightX, y = topRightY },
        { x = bottomRightX, y = bottomRightY },
        { x = bottomLeftX, y = bottomLeftY },
    }

    local alpha = playerSoundRingAlpha(ring, nowMs, config)
    if isQuadNearViewport(points, config) then
        local host = ensureOverlayHost()
        if host and host.drawTextureAllPoint then
            host:drawTextureAllPoint(
                texture,
                points[1].x,
                points[1].y,
                points[2].x,
                points[2].y,
                points[3].x,
                points[3].y,
                points[4].x,
                points[4].y,
                0.25,
                0.95,
                0.45,
                alpha
            )
        end
    end

    if config.showPlayerWorldSoundRadiusLabel == true then
        local centerX, centerY = projectWorldPoint(x, y, z)
        local label = tostring(math.floor(rawRadius)) .. " tiles"
        local labelFont = config.playerWorldSoundRadiusLabelFont or UIFont.Small
        local zDelta = z - playerObj:getZ()
        if zDelta > 0 then
            label = label .. " ^"
        elseif zDelta < 0 then
            label = label .. " v"
        end
        local textManager = getTextManager and getTextManager() or nil
        if textManager then
            local labelWidth = textManager:MeasureStringX(labelFont, label)
            local labelHeight = textManager:getFontHeight(labelFont)
            local labelStackOffsetPx = math.max(0, tonumber(ring.labelStackOffsetPx) or 0)
            textManager:DrawString(labelFont, centerX - (labelWidth / 2), centerY - labelHeight - 6 - labelStackOffsetPx, label, 0.85, 1.0, 0.85, math.max(0.60, alpha))
        end
    end
end

return SoundOverlayRenderer
