require "ISUI/ISUIElement"

local SoundOverlayRenderer = {}

local VERTICAL_MARKER_OFFSET = 10
local MAX_LABEL_LENGTH = 20
local ARROW_TEXTURE_PATH = "media/textures/SoundArrowBase.png"

local OverlayHost = ISUIElement:derive("QoLforSacrielSoundOverlayHost")
local overlayHost = nil
local arrowTexture = nil

function OverlayHost:initialise()
    ISUIElement.initialise(self)
    self:addToUIManager()
    self.javaObject:setWantKeyEvents(false)
    self.javaObject:setConsumeMouseEvents(false)
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
        local labelX = x + (ux * 8)
        local labelY = y + (uy * 8)
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

return SoundOverlayRenderer
