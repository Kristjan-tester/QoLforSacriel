local SoundEventClassifier = {}

local function contains(text, needle)
    return string.find(text, needle, 1, true) ~= nil
end

local function sourceClassText(source)
    if not source then
        return ""
    end

    local raw = string.lower(tostring(source))
    return raw
end

local function classFromSource(source)
    if not source then
        return "Unknown", "unknown"
    end

    if instanceof and instanceof(source, "IsoZombie") then
        return "Zombie", "zombie"
    end
    if instanceof and instanceof(source, "IsoPlayer") then
        return "PlayerLocal", "player"
    end
    if instanceof and instanceof(source, "BaseVehicle") then
        return "Vehicle", "vehicle"
    end
    if instanceof and instanceof(source, "IsoGenerator") then
        return "AlarmAndSignal", "generator"
    end
    if instanceof and instanceof(source, "IsoAnimal") then
        return "Environment", "animal"
    end

    local src = sourceClassText(source)
    if contains(src, "alarm") or contains(src, "clock") or contains(src, "siren") then
        return "AlarmAndSignal", "alarm-device"
    end
    if contains(src, "television") or contains(src, "radio") or contains(src, "wave") or contains(src, "speaker") then
        return "Environment", "device"
    end

    return "Unknown", "object"
end

function SoundEventClassifier.classifyWorldSound(source)
    local category, sourceType = classFromSource(source)
    return {
        category = category,
        sourceType = sourceType,
        isMeta = false,
    }
end

function SoundEventClassifier.classifyAmbientSound(name)
    local text = string.lower(tostring(name or ""))

    if contains(text, "gun") or contains(text, "shot") or contains(text, "scream") or contains(text, "rifle") or contains(text, "pistol") then
        return {
            category = "Combat",
            sourceType = "ambient-meta",
            isMeta = true,
        }
    end

    if contains(text, "thunder") or contains(text, "storm") or contains(text, "rain") or contains(text, "wind") or contains(text, "ambient") then
        return {
            category = "Environment",
            sourceType = "ambient-meta",
            isMeta = true,
        }
    end

    if contains(text, "alarm") or contains(text, "siren") then
        return {
            category = "AlarmAndSignal",
            sourceType = "ambient-meta",
            isMeta = true,
        }
    end

    if contains(text, "dog") or contains(text, "wolf") or contains(text, "bird") or contains(text, "crow") or contains(text, "owl") or contains(text, "animal") or contains(text, "coyote") or contains(text, "cow") or contains(text, "cattle") or contains(text, "sheep") or contains(text, "goat") or contains(text, "pig") or contains(text, "chicken") or contains(text, "rooster") or contains(text, "hen") then
        return {
            category = "Environment",
            sourceType = "ambient-meta",
            isMeta = true,
        }
    end

    if contains(text, "meta") then
        return {
            category = "Environment",
            sourceType = "ambient-meta",
            isMeta = true,
        }
    end

    return {
        category = "Unknown",
        sourceType = "ambient-meta",
        isMeta = true,
    }
end

return SoundEventClassifier
