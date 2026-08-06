local SoundDirection = {}

local classifier = require "QoLforSacriel/Modules/SoundIntel/SoundEventClassifier"
local renderer = nil
local settingsProvider = require "QoLforSacriel/Modules/SoundIntel/SoundSettingsProvider"
local modOptions = require "QoLforSacriel/Modules/SoundIntel/SoundModOptions"
QoLforSacriel_SoundIntel_Debug = QoLforSacriel_SoundIntel_Debug or {}

local installed = false
local cues = {}
local AMBIENT_CORRELATION_WINDOW_MS = 900
local AMBIENT_CORRELATION_DISTANCE = 10
local INFERRED_ANIMAL_SCAN_INTERVAL_MS = 900
local INFERRED_ANIMAL_SCAN_RADIUS = 22
local INFERRED_ANIMAL_MAX_PER_SCAN = 4

local nextAnimalScanAtMs = 0
local rendererUnavailableLogged = false
local DEBUG_META_TEST_HOLD_MS = 5000

local function isSoundDirectionRuntimeEnabled(settings, resolved)
    if settings.isEnabled() ~= true then
        return false
    end
    if settings.get("QoLforSacriel_UIFixes_EnableSoundDirection") ~= true then
        return false
    end
    return resolved.enabled == true
end

local function resolveRenderer(logger)
    if type(renderer) == "table" and type(renderer.renderCue) == "function" then
        return renderer
    end

    local ok, loaded = pcall(function()
        return require "QoLforSacriel/Modules/SoundIntel/SoundOverlayRenderer"
    end)
    if ok and type(loaded) == "table" and type(loaded.renderCue) == "function" then
        renderer = loaded
        rendererUnavailableLogged = false
        return renderer
    end

    if logger and not rendererUnavailableLogged then
        logger.error("SoundIntel renderer unavailable; skipping overlay render until module loads")
        rendererUnavailableLogged = true
    end
    return nil
end

local function ambientBaseRadiusForCategory(category)
    if category == "Environment" then
        return 1400
    end
    if category == "AlarmAndSignal" then
        return 1000
    end
    if category == "Combat" then
        return 900
    end
    if category == "Vehicle" then
        return 500
    end
    return 800
end

local function isCategoryEnabled(category, resolved)
    if category == "PlayerLocal" then
        return resolved.categoryPlayerLocal == true
    end
    if category == "Zombie" then
        return resolved.categoryZombie == true
    end
    if category == "Combat" then
        return resolved.categoryCombat == true
    end
    if category == "Environment" then
        return resolved.categoryEnvironment == true
    end
    if category == "Vehicle" then
        return resolved.categoryVehicle == true
    end
    if category == "AlarmAndSignal" then
        return resolved.categoryAlarmAndSignal == true
    end
    if category == "Inferred" then
        return resolved.categoryInferred == true
    end
    return resolved.categoryUnknown == true
end

local function isMetaEnabled(isMeta, resolved)
    if isMeta == true then
        return resolved.categoryMeta == true
    end
    return true
end

local function getNowMs()
    if getTimestampMs then
        return getTimestampMs()
    end
    return math.floor((getTimestamp() or 0) * 1000)
end

local function adjustRadiusForPlayer(playerObj, radius)
    local r = tonumber(radius) or 0
    if r <= 0 then
        return 0
    end

    if not playerObj or not playerObj.hasTrait then
        return r
    end

    if CharacterTrait and playerObj:hasTrait(CharacterTrait.DEAF) then
        return 0
    end
    if CharacterTrait and playerObj:hasTrait(CharacterTrait.KEEN_HEARING) then
        return r * 1.2
    end
    if CharacterTrait and playerObj:hasTrait(CharacterTrait.HARD_OF_HEARING) then
        return r * 0.8
    end

    return r
end

local function trimQueue(maxTracked)
    while #cues > maxTracked do
        local dropIndex = 1
        local dropExpiresAt = cues[1] and cues[1].expiresAtMs or math.huge
        local dropCreatedAt = cues[1] and cues[1].createdAtMs or math.huge

        for i = 2, #cues do
            local cue = cues[i]
            local expiresAt = cue.expiresAtMs or math.huge
            local createdAt = cue.createdAtMs or math.huge
            if expiresAt < dropExpiresAt or (expiresAt == dropExpiresAt and createdAt < dropCreatedAt) then
                dropIndex = i
                dropExpiresAt = expiresAt
                dropCreatedAt = createdAt
            end
        end
        table.remove(cues, dropIndex)
    end
end

local function isRenderEnabledForCue(cue, resolved)
    if cue.inferred == true and resolved.categoryInferred ~= true then
        return false
    end
    if cue.isMeta == true then
        return isMetaEnabled(true, resolved)
    end
    return isCategoryEnabled(cue.category, resolved)
end

local function upsertInferredCue(feed, source, nowMs, resolved, cueFactory)
    for i = #cues, 1, -1 do
        local cue = cues[i]
        if cue.feed == feed and cue.source == source then
            local updated = cueFactory()
            updated.createdAtMs = nowMs
            updated.expiresAtMs = nowMs + resolved.cueDurationMs
            cues[i] = updated
            return
        end
    end

    local created = cueFactory()
    created.createdAtMs = nowMs
    created.expiresAtMs = nowMs + resolved.cueDurationMs
    table.insert(cues, created)
    trimQueue(resolved.maxTrackedCues)
end

local function pruneExpired(nowMs)
    for i = #cues, 1, -1 do
        if nowMs >= cues[i].expiresAtMs then
            table.remove(cues, i)
        end
    end
end

local function isIgnoredSource(source, playerObj)
    if not source or not playerObj then
        return false
    end

    if source == playerObj then
        return true
    end

    if instanceof and instanceof(source, "BaseVehicle") and source.getDriver and source:getDriver() == playerObj then
        return true
    end

    if instanceof and instanceof(source, "IsoGenerator") then
        return true
    end

    return false
end

local function addWorldCue(x, y, z, radius, volume, source, resolved, logger)
    local playerObj = getPlayer()
    if not playerObj then
        return
    end

    if isIgnoredSource(source, playerObj) then
        return
    end

    local classification = classifier.classifyWorldSound(source)
    if not isMetaEnabled(classification.isMeta == true, resolved) then
        return
    end
    if classification.isMeta ~= true and not isCategoryEnabled(classification.category, resolved) then
        return
    end

    local adjustedRadius = adjustRadiusForPlayer(playerObj, radius)
    if adjustedRadius <= 0 then
        return
    end

    local detectRadius = adjustedRadius

    local distance = IsoUtils.DistanceTo(playerObj:getX(), playerObj:getY(), x, y)
    local outsideHearing = distance > detectRadius
    if outsideHearing and resolved.showOutsideHearing ~= true then
        return
    end

    local nowMs = getNowMs()

    pruneExpired(nowMs)

    table.insert(cues, {
        x = x,
        y = y,
        z = z,
        hasZ = z ~= nil,
        radius = radius,
        volume = volume,
        hasLoudness = true,
        adjustedRadius = detectRadius,
        distance = distance,
        source = source,
        sourceType = classification.sourceType,
        category = classification.category,
        isMeta = classification.isMeta == true,
        feed = "world",
        confidence = "high",
        outsideHearing = outsideHearing,
        createdAtMs = nowMs,
        expiresAtMs = nowMs + resolved.cueDurationMs,
    })

    trimQueue(resolved.maxTrackedCues)

    if logger then
        logger.debug("SoundIntel cue added: cat=" .. tostring(classification.category) .. ", dist=" .. tostring(math.floor(distance)) .. ", rad=" .. tostring(math.floor(detectRadius)))
    end
end

local function findAmbientCorrelation(x, y, nowMs)
    local best = nil
    local bestScore = nil

    for i = #cues, 1, -1 do
        local cue = cues[i]
        if cue.feed == "world" then
            local dt = math.abs(nowMs - cue.createdAtMs)
            if dt <= AMBIENT_CORRELATION_WINDOW_MS then
                local d = IsoUtils.DistanceTo(x, y, cue.x, cue.y)
                if d <= AMBIENT_CORRELATION_DISTANCE then
                    local score = (dt * 0.01) + d
                    if bestScore == nil or score < bestScore then
                        best = cue
                        bestScore = score
                    end
                end
            end
        end
    end

    return best
end

local function addAmbientCue(name, x, y, resolved, logger)
    local playerObj = getPlayer()
    if not playerObj then
        return
    end

    local nowMs = getNowMs()
    pruneExpired(nowMs)

    local classification = classifier.classifyAmbientSound(name)
    if not isMetaEnabled(classification.isMeta == true, resolved) then
        return
    end
    local correlated = nil
    if resolved.useAmbientCorrelation == true then
        correlated = findAmbientCorrelation(x, y, nowMs)
    end

    if classification.isMeta ~= true and not isCategoryEnabled(classification.category, resolved) then
        return
    end

    local cueRadius = adjustRadiusForPlayer(playerObj, ambientBaseRadiusForCategory(classification.category))
    local cueVolume = 0
    local hasZ = false
    local cueZ = nil
    local confidence = "low"
    local hasLoudness = false

    if correlated then
        cueRadius = math.max(cueRadius, correlated.adjustedRadius or 0)
        cueVolume = correlated.volume or 0
        hasLoudness = correlated.hasLoudness == true
        if correlated.hasZ == true then
            hasZ = true
            cueZ = correlated.z
        end
        confidence = "medium"
        if classification.category == "Unknown" and correlated.category and correlated.category ~= "Unknown" then
            classification.category = correlated.category
            if classification.isMeta ~= true and not isCategoryEnabled(classification.category, resolved) then
                return
            end
        end
    end

    local distance = IsoUtils.DistanceTo(playerObj:getX(), playerObj:getY(), x, y)
    local outsideHearing = cueRadius > 0 and distance > cueRadius
    if outsideHearing and resolved.showOutsideHearing ~= true then
        return
    end

    table.insert(cues, {
        x = x,
        y = y,
        z = cueZ,
        hasZ = hasZ,
        radius = cueRadius,
        volume = cueVolume,
        hasLoudness = hasLoudness,
        adjustedRadius = cueRadius,
        distance = distance,
        source = name,
        sourceType = classification.sourceType,
        category = classification.category,
        isMeta = classification.isMeta == true,
        feed = "ambient",
        confidence = confidence,
        outsideHearing = outsideHearing,
        createdAtMs = nowMs,
        expiresAtMs = nowMs + resolved.cueDurationMs,
    })

    trimQueue(resolved.maxTrackedCues)

    if logger then
        logger.debug("SoundIntel ambient cue added: name=" .. tostring(name) .. ", cat=" .. tostring(classification.category) .. ", corr=" .. tostring(correlated ~= nil))
    end
end

local function consumePendingMetaTest(resolved, logger)
    local pending = QoLforSacriel_SoundIntel_Debug.pendingMetaTest
    if not pending or not pending.name then
        return
    end

    local playerObj = getPlayer()
    if not playerObj then
        return
    end

    local nowMs = getNowMs()
    if pending.queuedAtMs and nowMs - pending.queuedAtMs > 8000 then
        QoLforSacriel_SoundIntel_Debug.pendingMetaTest = nil
        return
    end

    local angle = ((ZombRand(628) or 0) / 100) - 3.14
    local distance = 12
    local x = playerObj:getX() + (math.cos(angle) * distance)
    local y = playerObj:getY() + (math.sin(angle) * distance)

    local originalDuration = resolved.cueDurationMs
    resolved.cueDurationMs = math.max(originalDuration, DEBUG_META_TEST_HOLD_MS)
    addAmbientCue(pending.name, x, y, resolved, logger)
    resolved.cueDurationMs = originalDuration

    QoLforSacriel_SoundIntel_Debug.pendingMetaTest = nil

    if logger then
        logger.info("SoundIntel meta test cue injected: " .. tostring(pending.name))
    end
end

local function addInferredZombieCue(zombie, resolved, logger)
    if resolved.enableInferredZombie ~= true then
        return
    end
    if resolved.categoryInferred ~= true or resolved.categoryZombie ~= true then
        return
    end
    if not zombie then
        return
    end
    if zombie.isUseless and zombie:isUseless() then
        return
    end

    local playerObj = getPlayer()
    if not playerObj then
        return
    end

    local zx = zombie:getX()
    local zy = zombie:getY()
    local zz = zombie:getZ()
    local dist = IsoUtils.DistanceTo(playerObj:getX(), playerObj:getY(), zx, zy)
    if dist > 18 then
        return
    end

    local gate = 20 + math.floor(dist * 8)
    if gate < 1 then
        gate = 1
    end
    if ZombRand(gate) ~= 0 then
        return
    end

    local nowMs = getNowMs()
    pruneExpired(nowMs)

    upsertInferredCue("inferred-zombie", zombie, nowMs, resolved, function()
        return {
            x = zx,
            y = zy,
            z = zz,
            hasZ = zz ~= nil,
            radius = 15,
            volume = 7,
            hasLoudness = false,
            adjustedRadius = 15,
            distance = dist,
            source = zombie,
            sourceType = "zombie-inferred",
            category = "Zombie",
            isMeta = false,
            feed = "inferred-zombie",
            inferred = true,
            confidence = "low",
        }
    end)

    if logger then
        logger.debug("SoundIntel inferred zombie cue added: dist=" .. tostring(math.floor(dist)))
    end
end

local function addInferredAnimalCue(animal, resolved, logger)
    if resolved.enableInferredAnimal ~= true then
        return
    end
    if resolved.categoryInferred ~= true or resolved.categoryEnvironment ~= true then
        return
    end
    if not animal then
        return
    end
    if animal.isDead and animal:isDead() then
        return
    end

    local playerObj = getPlayer()
    if not playerObj then
        return
    end

    local ax = animal:getX()
    local ay = animal:getY()
    local az = animal:getZ()
    local dist = IsoUtils.DistanceTo(playerObj:getX(), playerObj:getY(), ax, ay)
    if dist > INFERRED_ANIMAL_SCAN_RADIUS then
        return
    end

    local detectRadius = adjustRadiusForPlayer(playerObj, 18)
    local outsideHearing = detectRadius <= 0 or dist > detectRadius
    if outsideHearing and resolved.showOutsideHearing ~= true then
        return
    end

    local nowMs = getNowMs()
    pruneExpired(nowMs)

    local labelHint = nil
    if animal.getAnimalType then
        local okType, animalType = pcall(function()
            return animal:getAnimalType()
        end)
        if okType and animalType ~= nil and tostring(animalType) ~= "" then
            labelHint = tostring(animalType)
        end
    end

    upsertInferredCue("inferred-animal", animal, nowMs, resolved, function()
        return {
            x = ax,
            y = ay,
            z = az,
            hasZ = az ~= nil,
            radius = detectRadius,
            volume = 6,
            hasLoudness = false,
            adjustedRadius = detectRadius,
            distance = dist,
            source = animal,
            sourceType = "animal-inferred",
            category = "Environment",
            isMeta = false,
            feed = "inferred-animal",
            inferred = true,
            confidence = "low",
            outsideHearing = outsideHearing,
            labelHint = labelHint,
        }
    end)

    if logger then
        logger.debug("SoundIntel inferred animal cue added: dist=" .. tostring(math.floor(dist)))
    end
end

local function sampleAnimalsForInferredCues(resolved, logger)
    if resolved.enableInferredAnimal ~= true then
        return
    end
    if resolved.categoryInferred ~= true or resolved.categoryEnvironment ~= true then
        return
    end

    local playerObj = getPlayer()
    local cell = getCell and getCell()
    if not playerObj or not cell then
        return
    end

    local nowMs = getNowMs()
    if nowMs < nextAnimalScanAtMs then
        return
    end
    nextAnimalScanAtMs = nowMs + INFERRED_ANIMAL_SCAN_INTERVAL_MS

    local px = math.floor(playerObj:getX())
    local py = math.floor(playerObj:getY())
    local pz = playerObj:getZ()
    local emitted = 0

    for dx = -INFERRED_ANIMAL_SCAN_RADIUS, INFERRED_ANIMAL_SCAN_RADIUS do
        for dy = -INFERRED_ANIMAL_SCAN_RADIUS, INFERRED_ANIMAL_SCAN_RADIUS do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            if sq then
                local moving = sq:getMovingObjects()
                if moving and moving.size and moving.get then
                    for i = 0, moving:size() - 1 do
                        local obj = moving:get(i)
                        if obj and instanceof and instanceof(obj, "IsoAnimal") then
                            addInferredAnimalCue(obj, resolved, logger)
                            emitted = emitted + 1
                            if emitted >= INFERRED_ANIMAL_MAX_PER_SCAN then
                                return
                            end
                        end
                    end
                end
            end
        end
    end
end

local function onWorldSound(x, y, z, radius, volume, source, settings, logger)
    local resolved = settingsProvider.get(settings)
    if not isSoundDirectionRuntimeEnabled(settings, resolved) then
        return
    end

    local ok, err = pcall(function()
        addWorldCue(x, y, z, radius, volume, source, resolved, logger)
    end)
    if not ok and logger then
        logger.error("SoundIntel OnWorldSound error: " .. tostring(err))
    end
end

local function onAmbientSound(name, x, y, settings, logger)
    local resolved = settingsProvider.get(settings)
    if not isSoundDirectionRuntimeEnabled(settings, resolved) then
        return
    end

    local ok, err = pcall(function()
        addAmbientCue(name, x, y, resolved, logger)
    end)
    if not ok and logger then
        logger.error("SoundIntel OnAmbientSound error: " .. tostring(err))
    end
end

local function onZombieUpdate(zombie, settings, logger)
    local resolved = settingsProvider.get(settings)
    if not isSoundDirectionRuntimeEnabled(settings, resolved) then
        return
    end

    local ok, err = pcall(function()
        addInferredZombieCue(zombie, resolved, logger)
    end)
    if not ok and logger then
        logger.error("SoundIntel OnZombieUpdate error: " .. tostring(err))
    end
end

local function onPostRender(settings, logger)
    local resolved = settingsProvider.get(settings)
    if not isSoundDirectionRuntimeEnabled(settings, resolved) then
        cues = {}
        return
    end

    local nowMs = getNowMs()
    local renderModule = resolveRenderer(logger)
    if not renderModule then
        return
    end

    pruneExpired(nowMs)

    local okAnimals, errAnimals = pcall(function()
        sampleAnimalsForInferredCues(resolved, logger)
    end)
    if not okAnimals and logger then
        logger.error("SoundIntel inferred animal scan error: " .. tostring(errAnimals))
    end

    local okDebugMeta, errDebugMeta = pcall(function()
        consumePendingMetaTest(resolved, logger)
    end)
    if not okDebugMeta and logger then
        logger.error("SoundIntel meta test cue error: " .. tostring(errDebugMeta))
    end

    local playerObj = getPlayer()
    if not playerObj then
        return
    end

    for i = 1, #cues do
        local cue = cues[i]
        if isRenderEnabledForCue(cue, resolved) then
            local ok, err = pcall(function()
                renderModule.renderCue(playerObj, cue, nowMs, resolved)
            end)
            if not ok and logger then
                logger.error("SoundIntel render error: " .. tostring(err))
            end
        end
    end
end

function SoundDirection.init(settings, logger)
    if installed then
        logger.debug("UIFixes.SoundDirection already installed")
        return
    end

    modOptions.register(logger)

    if not Events.OnWorldSound and LuaEventManager and LuaEventManager.AddEvent then
        LuaEventManager.AddEvent("OnWorldSound")
    end
    if not Events.OnAmbientSound and LuaEventManager and LuaEventManager.AddEvent then
        LuaEventManager.AddEvent("OnAmbientSound")
    end

    Events.OnWorldSound.Add(function(x, y, z, radius, volume, source)
        onWorldSound(x, y, z, radius, volume, source, settings, logger)
    end)

    Events.OnAmbientSound.Add(function(name, x, y)
        onAmbientSound(name, x, y, settings, logger)
    end)

    Events.OnZombieUpdate.Add(function(zombie)
        onZombieUpdate(zombie, settings, logger)
    end)

    Events.OnPostRender.Add(function()
        local ok, err = pcall(function()
            onPostRender(settings, logger)
        end)
        if not ok then
            logger.error("SoundIntel post-render error: " .. tostring(err))
        end
    end)

    installed = true
    logger.info("UIFixes.SoundDirection installed (world + ambient feed)")
end

return SoundDirection
