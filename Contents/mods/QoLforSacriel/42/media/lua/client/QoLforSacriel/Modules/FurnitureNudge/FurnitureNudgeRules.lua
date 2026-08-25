-- ff-assisted
require "Moveables/ISMoveableTools"
require "Moveables/ISMoveableSpriteProps"

local FurnitureNudgeRules = {}

local DIRECTIONS = {
    { label = "North", dx = 0, dy = -1 },
    { label = "South", dx = 0, dy = 1 },
    { label = "West", dx = -1, dy = 0 },
    { label = "East", dx = 1, dy = 0 },
}

FurnitureNudgeRules.CANDIDATE_REASON_NOT_MOVEABLE = "not_moveable"
FurnitureNudgeRules.CANDIDATE_REASON_MULTI_TILE = "multi_tile"
FurnitureNudgeRules.CANDIDATE_REASON_HAS_CONTENTS = "has_contents"
FurnitureNudgeRules.CANDIDATE_REASON_PARALLEL_WALL = "parallel_wall"
FurnitureNudgeRules.CANDIDATE_REASON_REQUIRES_TOOL = "requires_tool"
FurnitureNudgeRules.CANDIDATE_REASON_TOO_TIRED = "too_tired"

FurnitureNudgeRules.CONTAINER_ROUTE_EMPTY = "empty_existing_path"
FurnitureNudgeRules.CONTAINER_ROUTE_KEEP = "occupied_keep_inventory"
FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED = "blocked_has_contents"

local ENDURANCE_EPSILON = 0.0001
local FLUID_ENDURANCE_PER_LITER = 0.005

local EXPLICIT_NON_BLOCKING_SPRITES = {
    walls_decoration_01_91 = true,
    rooftop_furniture_34 = true,
}

local EXCLUDED_ISO_TYPES = {
    IsoBarbecue = true,
    IsoClothingDryer = true,
    IsoClothingWasher = true,
    IsoCombinationWasherDryer = true,
    IsoCompost = true,
    IsoFeedingTrough = true,
    IsoFireplace = true,
    IsoGenerator = true,
    IsoMannequin = true,
    IsoRadio = true,
    IsoTelevision = true,
}

local EXCLUDED_CLASSES = {
    "IsoBarbecue",
    "IsoClothingDryer",
    "IsoClothingWasher",
    "IsoCombinationWasherDryer",
    "IsoCompost",
    "IsoFeedingTrough",
    "IsoFireplace",
    "IsoGenerator",
    "IsoMannequin",
    "IsoWaveSignal",
}

local EXCLUDED_CONTAINER_TYPE_PARTS = {
    "barbecue",
    "clothingdryer",
    "clothingwasher",
    "fireplace",
    "generator",
    "washerdryer",
}

local ALLOWED_OBJECT_MOD_DATA_KEYS = {
    itemCondition = true,
    movableData = true,
    ["QoLforSacriel.OrganizedInventory.tags"] = true,
    ["QoLforSacriel.OrganizedInventory.tagsByContainerIndex"] = true,
}

local VANILLA_MOVE_TRANSPORT_KEYS = {
    canBeLockedByPadlock = true,
    color = true,
    health = true,
    lightSource = true,
    lockedByCode = true,
    lockedByKeyId = true,
    maxHealth = true,
    name = true,
    thumpSound = true,
}

local ORGANIZED_INVENTORY_KEYS = {
    ["QoLforSacriel.OrganizedInventory.tags"] = true,
    ["QoLforSacriel.OrganizedInventory.tagsByContainerIndex"] = true,
}

local PASSIVE_SINGLE_TILE_COMPONENTS = {
    Attributes = true,
    ContextMenuConfig = true,
    CraftRecipe = true,
    Durability = true,
    Script = true,
    SpriteConfig = true,
    SpriteOverlayConfig = true,
    UiConfig = true,
    WallCoveringConfig = true,
}

local RECONSTRUCTIBLE_MULTI_TILE_COMPONENTS = {
    ContextMenuConfig = true,
    CraftRecipe = true,
    Script = true,
    SpriteConfig = true,
    SpriteOverlayConfig = true,
    UiConfig = true,
    WallCoveringConfig = true,
}

local function normalizeSpriteIdentifier(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    return (value:gsub("^Base%.", ""))
end

local function isRooftopAirConditionerVariant(spriteId)
    if type(spriteId) ~= "string" then
        return false
    end

    local id = spriteId:match("^rooftop_furniture_(%d+)$")
    id = id and tonumber(id) or nil
    if not id then
        return false
    end

    -- AC variants around the known non-blocking rooftop unit id.
    return id >= 34 and id <= 37
end

local function hasNonBlockingChildSprite(object)
    if not object or not object.getChildSprites then
        return false
    end

    local childList = object:getChildSprites()
    if not childList or not childList.size or not childList.get then
        return false
    end

    local okSize, count = pcall(function()
        return childList:size()
    end)
    if not okSize or not count or count <= 0 then
        return false
    end

    for i = 0, count - 1 do
        local child = childList:get(i)
        local parentSprite = child and child.getParentSprite and child:getParentSprite() or nil
        local name = parentSprite and parentSprite.getName and normalizeSpriteIdentifier(parentSprite:getName()) or nil
        if name and (EXPLICIT_NON_BLOCKING_SPRITES[name] == true or isRooftopAirConditionerVariant(name)) then
            return true
        end
    end

    return false
end

local function getSpriteIdentifier(object, moveProps)
    if moveProps and moveProps.spriteName and moveProps.spriteName ~= "" then
        return normalizeSpriteIdentifier(moveProps.spriteName)
    end
    if object and object.getSprite then
        local sprite = object:getSprite()
        if sprite and sprite.getName then
            return normalizeSpriteIdentifier(sprite:getName())
        end
    end
    return nil
end

local function isExplicitNonBlockingSprite(object, moveProps)
    local spriteId = getSpriteIdentifier(object, moveProps)
    if spriteId and EXPLICIT_NON_BLOCKING_SPRITES[spriteId] == true then
        return true
    end
    if spriteId and isRooftopAirConditionerVariant(spriteId) then
        return true
    end
    return hasNonBlockingChildSprite(object)
end

local function isRugLike(obj)
    if not obj or not obj.getSprite then
        return false
    end
    local sprite = obj:getSprite()
    if not sprite then
        return false
    end
    local props = sprite:getProperties()
    return props and props:has("MoveType") and props:get("MoveType") == "FloorRug"
end

local function isVegetationOverlay(obj)
    if not obj or not obj.getProperties then
        return false
    end
    local props = obj:getProperties()
    return props and props:has(IsoFlagType.canBeCut)
end

local function isDecorativeWallOverlay(obj)
    if not obj or not obj.getSprite then
        return false
    end

    local sprite = obj:getSprite()
    if not sprite then
        return false
    end

    local props = sprite:getProperties()
    if not props then
        return false
    end

    if props:has("MoveType") and props:get("MoveType") == "WallOverlay" then
        return true
    end

    return props:has("attachedN") or props:has("attachedW") or props:has("attachedS") or props:has("attachedE")
end

local function isAllowedNonBlocker(obj, settings)
    if not obj then
        return true
    end
    if isExplicitNonBlockingSprite(obj, nil) then
        return true
    end
    if obj.isFloor and obj:isFloor() then
        return true
    end
    if instanceof(obj, "IsoWorldInventoryObject") and settings.get("QoLforSacriel_FurnitureNudge_BlockOnFloorItems") ~= true then
        return true
    end
    if isRugLike(obj) and settings.get("QoLforSacriel_FurnitureNudge_BlockOnRugs") ~= true then
        return true
    end
    if isVegetationOverlay(obj) then
        return true
    end
    if isDecorativeWallOverlay(obj) then
        return true
    end
    return false
end

local function hasPassabilityBlocker(square)
    if not square then
        return true
    end
    if square:isSolid() or square:isSolidTrans() then
        return true
    end
    if square:HasStairs() or square:HasStairsBelow() then
        return true
    end
    return false
end

local function hasEdgeBlocker(fromSquare, toSquare)
    if not fromSquare or not toSquare then
        return true
    end
    if fromSquare:isWallTo(toSquare) or toSquare:isWallTo(fromSquare) then
        return true
    end
    if fromSquare:isWindowBlockedTo(toSquare) or toSquare:isWindowBlockedTo(fromSquare) then
        return true
    end
    if fromSquare:isDoorBlockedTo(toSquare) or toSquare:isDoorBlockedTo(fromSquare) then
        return true
    end
    return false
end

local function isMoveableStructureObject(obj)
    if not obj or not obj.getSprite then
        return false
    end

    local sprite = obj:getSprite()
    if not sprite then
        return false
    end

    local props = sprite:getProperties()
    if not props then
        return false
    end

    local moveType = props:has("MoveType") and props:get("MoveType") or nil
    if moveType == "Object" then
        return true
    end

    if props:has("IsMoveAble") and (moveType == nil or moveType == "") then
        return true
    end

    return false
end

local function requiresTool(moveProps)
    if not moveProps then
        return false
    end
    return moveProps.pickUpTool ~= nil or moveProps.placeTool ~= nil
end

local function isWindowLike(object, moveProps)
    if not object or not moveProps then
        return true
    end
    if moveProps.type == "Window" or moveProps.type == "WindowObject" then
        return true
    end

    local okWindow, isWindow = pcall(instanceof, object, "IsoWindow")
    if not okWindow or isWindow then
        return true
    end

    if object.isWindow then
        local ok, result = pcall(object.isWindow, object)
        if not ok or result == true then
            return true
        end
    end
    if object.isWindowFrame then
        local ok, result = pcall(object.isWindowFrame, object)
        if not ok or result == true then
            return true
        end
    end
    return false
end

local function getNudgeRuleOptions(settings)
    return {
        allowMultiTile = settings and settings.get and settings.get("QoLforSacriel_FurnitureNudge_AllowMultiTile") == true,
        ignoreToolRequirements = settings and settings.get and settings.get("QoLforSacriel_FurnitureNudge_IgnoreToolRequirements") == true,
        keepInventory = settings and settings.get and settings.get("QoLforSacriel_FurnitureNudge_KeepInventoryExperimental") == true,
    }
end

local function copyPersistentValue(value, active)
    local valueType = type(value)
    if valueType == "nil"
    or valueType == "boolean"
    or valueType == "number"
    or valueType == "string"
    then
        return true, value
    end
    if valueType ~= "table" then
        return false, nil
    end

    active = active or {}
    if active[value] then
        return false, nil
    end
    active[value] = true

    local copy = {}
    for key, nestedValue in pairs(value) do
        local keyOk, copiedKey = copyPersistentValue(key, active)
        local valueOk, copiedValue = copyPersistentValue(nestedValue, active)
        if not keyOk or not valueOk then
            active[value] = nil
            return false, nil
        end
        copy[copiedKey] = copiedValue
    end
    active[value] = nil
    return true, copy
end

local function analyzeObjectModData(object)
    if not object or not object.hasModData or not object:hasModData() then
        return {}, nil
    end

    local modData = object:getModData()
    local persistentData = {}
    local unknownKeys = {}

    local function isVanillaTransportEnvelope(tableValue)
        return type(tableValue.modData) == "table"
            and type(tableValue.name) == "string"
            and tonumber(tableValue.health) ~= nil
            and tonumber(tableValue.maxHealth) ~= nil
    end

    local function isValidTransportValue(keyText, value)
        if keyText == "name" or keyText == "thumpSound" then
            return type(value) == "string"
        end
        if keyText == "health"
        or keyText == "maxHealth"
        or keyText == "lockedByKeyId"
        or keyText == "lockedByCode"
        then
            return tonumber(value) ~= nil
        end
        if keyText == "canBeLockedByPadlock" then
            return value == true
        end
        if keyText == "color" then
            return type(value) == "userdata"
        end
        if keyText == "lightSource" then
            if type(value) ~= "table"
            or tonumber(value.radius) == nil
            or tonumber(value.xoffset) == nil
            or tonumber(value.yoffset) == nil
            or tonumber(value.life) == nil
            then
                return false
            end

            local allowedLightKeys = {
                fuel = true,
                life = true,
                radius = true,
                xoffset = true,
                yoffset = true,
            }
            for lightKey, _ in pairs(value) do
                if not allowedLightKeys[tostring(lightKey)] then
                    return false
                end
            end

            local fuelType = type(value.fuel)
            return value.fuel == nil
                or fuelType == "boolean"
                or fuelType == "number"
                or fuelType == "string"
                or fuelType == "userdata"
        end
        return false
    end

    local function inspect(tableValue, path, visited, isTopLevel)
        if visited[tableValue] then
            unknownKeys[#unknownKeys + 1] = path .. "<cycle>"
            return
        end
        visited[tableValue] = true

        local isEnvelope = isVanillaTransportEnvelope(tableValue)
        local nestedEnvelope = tableValue.modData
        if nestedEnvelope ~= nil then
            if isEnvelope then
                inspect(nestedEnvelope, path .. "modData.", visited, false)
            else
                unknownKeys[#unknownKeys + 1] = path .. "modData"
            end
        end

        for key, value in pairs(tableValue) do
            local keyText = tostring(key)
            if keyText ~= "modData" then
                if ALLOWED_OBJECT_MOD_DATA_KEYS[keyText]
                or string.sub(keyText, -20) == "_customContainerName"
                then
                    if isTopLevel or not ORGANIZED_INVENTORY_KEYS[keyText] then
                        local copiedOk, copiedValue = copyPersistentValue(value)
                        if not copiedOk then
                            unknownKeys[#unknownKeys + 1] = path .. keyText .. "<invalid>"
                        elseif persistentData[keyText] == nil or isTopLevel then
                            persistentData[keyText] = copiedValue
                        end
                    end
                elseif not isEnvelope
                or not VANILLA_MOVE_TRANSPORT_KEYS[keyText]
                or not isValidTransportValue(keyText, value)
                then
                    unknownKeys[#unknownKeys + 1] = path .. keyText
                end
            end
        end
        visited[tableValue] = nil
    end

    inspect(modData, "", {}, true)

    if #unknownKeys == 0 then
        return persistentData, nil
    end
    table.sort(unknownKeys)
    return persistentData, table.concat(unknownKeys, ",")
end

local function isExcludedClass(object)
    for _, className in ipairs(EXCLUDED_CLASSES) do
        local ok, matches = pcall(instanceof, object, className)
        if not ok or matches then
            return true
        end
    end
    return false
end

local function isSafeInactiveStove(object)
    local okClass, isStove = pcall(instanceof, object, "IsoStove")
    if not okClass then
        return false, "unreadable"
    end
    if not isStove then
        return true, nil
    end

    local ok, safe = pcall(function()
        return object:Activated() ~= true
            and object:isTemperatureChanging() ~= true
            and (object:isMicrowave() or object:getTimer() == -1)
    end)
    if not ok or not safe then
        return false, "active_or_used"
    end
    return true, nil
end

local function hasExcludedProperties(object)
    local properties = object and object.getProperties and object:getProperties() or nil
    if not properties then
        return true
    end

    return properties:has("waterPiped")
end

local function hasExcludedContainerType(container)
    if not container or not container.getType then
        return true
    end

    local containerType = string.lower(tostring(container:getType() or ""))
    if containerType == "" then
        return true
    end

    for _, part in ipairs(EXCLUDED_CONTAINER_TYPE_PARTS) do
        if string.find(containerType, part, 1, true) then
            return true
        end
    end
    return false
end

local function getOccupiedMoveMembers(object, moveProps)
    if moveProps.isMultiSprite then
        local square = object and object:getSquare() or nil
        local members = square and moveProps:getSpriteGridInfo(square, true) or nil
        if not members or #members == 0 then
            return nil
        end
        return members
    end
    return { { object = object, square = object:getSquare(), sprite = object:getSprite() } }
end

local function validatePassiveComponents(object, isMultiSprite)
    local allowed = isMultiSprite
        and RECONSTRUCTIBLE_MULTI_TILE_COMPONENTS
        or PASSIVE_SINGLE_TILE_COMPONENTS
    local ok, valid, reason = pcall(function()
        for index = 0, object:componentSize() - 1 do
            local component = object:getComponentForIndex(index)
            local componentType = component and component:getComponentType() or nil
            local componentName = componentType and tostring(componentType) or "unknown"
            if not allowed[componentName] then
                return false, componentName
            end
        end
        return true, nil
    end)
    if not ok then
        return false, "unreadable"
    end
    return valid == true, reason
end

local function classifyContainerMove(object, moveProps, options)
    if not object or not moveProps then
        return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED, "missing_object"
    end

    if isClient and isClient() then
        return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED, "multiplayer"
    end

    local members = getOccupiedMoveMembers(object, moveProps)
    if not members then
        return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED, "incomplete_members"
    end

    local containerCount = 0
    local hasItems = false
    local hasFluidContainer = false
    for _, member in ipairs(members) do
        local memberObject = member.object
        if not memberObject then
            return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED, "incomplete_members"
        end

        if memberObject.getFluidContainer and memberObject:getFluidContainer() then
            hasFluidContainer = true
        end

        local memberContainerCount = memberObject:getContainerCount() or 0
        containerCount = containerCount + memberContainerCount
        for containerIndex = 0, memberContainerCount - 1 do
            local container = memberObject:getContainerByIndex(containerIndex)
            if not container or not container.isExplored or not container:isExplored() then
                return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED, "unexplored"
            end
            local items = container:getItems()
            if items and items:size() > 0 then
                hasItems = true
            end
        end
    end

    if containerCount == 0 and hasFluidContainer then
        return FurnitureNudgeRules.CONTAINER_ROUTE_EMPTY, "fluid_only_legacy"
    end

    for _, member in ipairs(members) do
        local componentsOk, componentReason = validatePassiveComponents(
            member.object,
            moveProps.isMultiSprite == true
        )
        if not componentsOk then
            return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED,
                "component[" .. tostring(componentReason) .. "]"
        end
    end

    if containerCount == 0 then
        return FurnitureNudgeRules.CONTAINER_ROUTE_EMPTY, "no_containers"
    end
    if not options or options.keepInventory ~= true then
        if hasItems then
            return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED, "option_disabled"
        end
        return FurnitureNudgeRules.CONTAINER_ROUTE_EMPTY, "option_disabled_empty"
    end
    local isIsoStove = tostring(moveProps.isoType or "") == "IsoStove"
    if (moveProps.type ~= "Object" and moveProps.type ~= "WallObject")
    or (moveProps.isTableTop and not isIsoStove)
    then
        return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED, "unsupported_shape"
    end
    if moveProps.isMultiSprite and moveProps.isForceSingleItem then
        return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED, "force_single_item_grid"
    end
    if moveProps.isoType
    and EXCLUDED_ISO_TYPES[tostring(moveProps.isoType)]
    and not isIsoStove
    then
        return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED, "iso_type"
    end
    if isExcludedClass(object) then
        return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED, "specialized_class"
    end
    local stoveSafe, stoveReason = isSafeInactiveStove(object)
    if not stoveSafe then
        return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED,
            "appliance_state[" .. tostring(stoveReason) .. "]"
    end
    for _, member in ipairs(members) do
        local memberObject = member.object
        if isExcludedClass(memberObject) then
            return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED, "specialized_class"
        end
        local memberStoveSafe, memberStoveReason = isSafeInactiveStove(memberObject)
        if not memberStoveSafe then
            return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED,
                "appliance_state[" .. tostring(memberStoveReason) .. "]"
        end
        if memberObject.getFluidContainer and memberObject:getFluidContainer() then
            return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED, "fluid_container"
        end
        if hasExcludedProperties(memberObject) then
            return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED, "sprite_properties"
        end
        for containerIndex = 0, memberObject:getContainerCount() - 1 do
            if hasExcludedContainerType(memberObject:getContainerByIndex(containerIndex)) then
                return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED, "container_type"
            end
        end
        local _, memberUnknownModData = analyzeObjectModData(memberObject)
        if memberUnknownModData then
            return FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED,
                "mod_data[" .. tostring(memberUnknownModData) .. "]"
        end
    end

    return FurnitureNudgeRules.CONTAINER_ROUTE_KEEP,
        hasItems and "eligible_occupied" or "eligible_empty"
end

local function isFurnitureMoveableCandidate(object, moveProps)
    if not object or not moveProps then
        return false
    end
    if moveProps.isMoveable ~= true then
        return false
    end
    if instanceof(object, "IsoDoor") or isWindowLike(object, moveProps) then
        return false
    end
    return true
end

local function shouldIgnoreToolRequirement(object, moveProps, options)
    if not options or options.ignoreToolRequirements ~= true then
        return false
    end
    return isFurnitureMoveableCandidate(object, moveProps)
end

local function logCandidateDecision(settings, logger, object, reason, blocked, options)
    if not logger or not settings or settings.get("QoLforSacriel_DebugLogs") ~= true then
        return
    end

    local coords = ""
    if object and object.getSquare then
        local square = object:getSquare()
        if square then
            coords = " @(" .. tostring(square:getX()) .. "," .. tostring(square:getY()) .. "," .. tostring(square:getZ()) .. ")"
        end
    end

    logger.debug("FurnitureNudge candidate " .. (blocked and "blocked" or "allowed") .. ": reason=" .. tostring(reason) .. " allowMultiTile=" .. tostring(options and options.allowMultiTile == true) .. " ignoreTools=" .. tostring(options and options.ignoreToolRequirements == true) .. coords)
end

local function collectMultiTileMembers(moveProps, sourceSquare)
    local members = {}
    local memberSet = {}

    if moveProps and moveProps.isMultiSprite and moveProps.getSpriteGridInfo then
        local info = moveProps:getSpriteGridInfo(sourceSquare, true)
        if info then
            for _, entry in ipairs(info) do
                table.insert(members, entry)
                if entry.object then
                    memberSet[entry.object] = true
                end
            end
        end
    end

    return members, memberSet
end

local function squareKey(square)
    return tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ())
end

local function buildMemberSquareSet(members)
    local out = {}
    for _, member in ipairs(members) do
        if member.square then
            out[squareKey(member.square)] = true
        end
    end
    return out
end

local function passesNudgeFallbackPlaceCheck(targetSquare, memberSet, settings)
    if not targetSquare then
        return false
    end
    if hasPassabilityBlocker(targetSquare) then
        return false
    end

    local objects = targetSquare:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if not memberSet[obj] and isMoveableStructureObject(obj) then
            if not isAllowedNonBlocker(obj, settings) then
                return false
            end
        end
    end

    return true
end

local function passesVanillaPlaceCheck(moveProps, targetSquare, memberSet, settings)
    if not moveProps or not targetSquare then
        return false
    end

    local ok = moveProps:canPlaceMoveableInternal(nil, targetSquare, nil)
    if ok then
        return true
    end

    if moveProps.isTableTop then
        return false
    end

    local fallbackOk = passesNudgeFallbackPlaceCheck(targetSquare, memberSet or {}, settings)
    if fallbackOk and settings and settings.get("QoLforSacriel_DebugLogs") == true then
        local logger = _G.QoLforSacriel_Logger
        if logger and logger.debug then
            logger.debug("FurnitureNudge fallback place-check override at (" .. tostring(targetSquare:getX()) .. "," .. tostring(targetSquare:getY()) .. "," .. tostring(targetSquare:getZ()) .. ")")
        end
    end
    return fallbackOk
end

local function calculateEnduranceCostForMoveProps(moveProps, settings)
    local rawWeight = 50
    if moveProps and moveProps.rawWeight then
        rawWeight = tonumber(moveProps.rawWeight) or rawWeight
    end

    local scale = tonumber(settings.get("QoLforSacriel_FurnitureNudge_EnduranceScale")) or 0.25
    local minCost = tonumber(settings.get("QoLforSacriel_FurnitureNudge_EnduranceMin")) or 0.005
    local cost = minCost + (rawWeight * 0.0007 * scale)

    if cost < minCost then
        return minCost
    end
    return cost
end

local function getFluidLitersFromObject(object)
    if not object then
        return 0
    end

    if object.getFluidContainer then
        local fluidContainer = object:getFluidContainer()
        if fluidContainer and fluidContainer.getAmount then
            local amount = tonumber(fluidContainer:getAmount())
            if amount and amount > 0 then
                return amount
            end
        end
    end

    return 0
end

local function isSquareBlockedForMove(square, memberSet, settings)
    if hasPassabilityBlocker(square) then
        return true
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if not memberSet[obj] then
            if not isAllowedNonBlocker(obj, settings) and isMoveableStructureObject(obj) then
                return true
            end
        end
    end
    return false
end

local function isCandidateDisallowed(object, moveProps, options)
    if not object or not moveProps then
        return true, FurnitureNudgeRules.CANDIDATE_REASON_NOT_MOVEABLE
    end

    if isWindowLike(object, moveProps) then
        return true, FurnitureNudgeRules.CANDIDATE_REASON_NOT_MOVEABLE
    end

    local ignoreTools = shouldIgnoreToolRequirement(object, moveProps, options)
    if requiresTool(moveProps) and not ignoreTools then
        return true, FurnitureNudgeRules.CANDIDATE_REASON_REQUIRES_TOOL
    end
    if moveProps.isMultiSprite and (not options or options.allowMultiTile ~= true) then
        return true, FurnitureNudgeRules.CANDIDATE_REASON_MULTI_TILE
    end
    local containerRoute, containerReason = classifyContainerMove(object, moveProps, options)
    if containerRoute == FurnitureNudgeRules.CONTAINER_ROUTE_BLOCKED then
        return true, FurnitureNudgeRules.CANDIDATE_REASON_HAS_CONTENTS, containerReason
    end
    if instanceof(object, "IsoDoor") then
        return true, FurnitureNudgeRules.CANDIDATE_REASON_NOT_MOVEABLE
    end
    return false, nil
end

function FurnitureNudgeRules.requiresTool(moveProps)
    return requiresTool(moveProps)
end

function FurnitureNudgeRules.isWindowLike(object, moveProps)
    return isWindowLike(object, moveProps)
end

function FurnitureNudgeRules.classifyContainerMove(object, moveProps, settings)
    return classifyContainerMove(object, moveProps, getNudgeRuleOptions(settings))
end

function FurnitureNudgeRules.capturePersistentObjectModData(object)
    return analyzeObjectModData(object)
end

function FurnitureNudgeRules.validateOccupiedComponents(object, isMultiSprite)
    return validatePassiveComponents(object, isMultiSprite == true)
end

function FurnitureNudgeRules.isMultiTileAllowed(settings)
    local options = getNudgeRuleOptions(settings)
    return options.allowMultiTile == true
end

function FurnitureNudgeRules.shouldIgnoreToolRequirementForCandidate(candidate, settings)
    if not candidate then
        return false
    end
    local options = getNudgeRuleOptions(settings)
    return shouldIgnoreToolRequirement(candidate.object, candidate.moveProps, options)
end

function FurnitureNudgeRules.getEnduranceCost(candidate, settings, suppressDebugLog)
    if not candidate then
        return 0
    end
    local moveProps = candidate.moveProps or (candidate.object and ISMoveableSpriteProps.fromObject(candidate.object)) or nil
    local baseCost = calculateEnduranceCostForMoveProps(moveProps, settings)
    local fluidLiters = getFluidLitersFromObject(candidate.object)
    local fluidSurcharge = fluidLiters * FLUID_ENDURANCE_PER_LITER
    local finalCost = baseCost + fluidSurcharge

    if not suppressDebugLog and settings and settings.get("QoLforSacriel_DebugLogs") == true then
        local logger = _G.QoLforSacriel_Logger
        if logger and logger.debug then
            logger.debug("FurnitureNudge endurance cost: base=" .. tostring(baseCost) .. " fluidLiters=" .. tostring(fluidLiters) .. " fluidExtra=" .. tostring(fluidSurcharge) .. " final=" .. tostring(finalCost))
        end
    end

    return finalCost
end

function FurnitureNudgeRules.isTooTiredForCandidate(playerObj, candidate, settings, suppressDebugLog)
    if not playerObj or not candidate then
        return false
    end
    if playerObj.isUnlimitedEndurance and playerObj:isUnlimitedEndurance() then
        return false
    end

    local stats = playerObj:getStats()
    if not stats then
        return false
    end

    local currentEndurance = stats:get(CharacterStat.ENDURANCE)
    local cost = FurnitureNudgeRules.getEnduranceCost(candidate, settings, suppressDebugLog)
    local projectedEndurance = currentEndurance - cost

    if not suppressDebugLog and settings and settings.get("QoLforSacriel_DebugLogs") == true then
        local logger = _G.QoLforSacriel_Logger
        if logger and logger.debug then
            logger.debug("FurnitureNudge endurance gate: current=" .. tostring(currentEndurance) .. " cost=" .. tostring(cost) .. " projected=" .. tostring(projectedEndurance))
        end
    end

    if stats.isAtMinimum and stats:isAtMinimum(CharacterStat.ENDURANCE) then
        return true
    end

    return projectedEndurance <= ENDURANCE_EPSILON
end

local function describeCandidate(entry)
    local moveProps = entry and entry.moveProps or nil
    if moveProps and moveProps.name and moveProps.name ~= "" then
        return Translator and Translator.getMoveableDisplayName and Translator.getMoveableDisplayName(moveProps.name) or moveProps.name
    end
    return "Furniture"
end

local function addCandidate(out, seenByObject, entry, square, settings, logger)
    if not entry or not entry.object or seenByObject[entry.object] then
        return
    end

    seenByObject[entry.object] = true

    local options = getNudgeRuleOptions(settings)
    local disallowed, reason, detail = isCandidateDisallowed(entry.object, entry.moveProps, options)
    local logReason = reason or "ok"
    if detail then
        logReason = logReason .. ":" .. detail
    end
    logCandidateDecision(settings, logger, entry.object, logReason, disallowed, options)
    table.insert(out, {
        object = entry.object,
        moveProps = entry.moveProps,
        square = square,
        isNudgeDisabled = disallowed,
        disableReason = reason,
        containerReason = detail,
        displayName = describeCandidate(entry),
    })
end

local function getCandidateKey(candidate)
    if not candidate then
        return nil
    end
    local square = candidate.square
    if not square then
        return nil
    end
    local name = candidate.displayName or ""
    return tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ()) .. ":" .. tostring(name)
end

local function collapseDuplicateCandidates(candidates, settings, logger)
    if not candidates or #candidates <= 1 then
        return candidates
    end

    local keyed = {}
    local ordered = {}
    for _, candidate in ipairs(candidates) do
        local key = getCandidateKey(candidate)
        if not key then
            table.insert(ordered, candidate)
        elseif not keyed[key] then
            keyed[key] = candidate
            table.insert(ordered, candidate)
        else
            local current = keyed[key]
            local currentBlocked = current.isNudgeDisabled == true
            local incomingBlocked = candidate.isNudgeDisabled == true
            if currentBlocked and not incomingBlocked then
                keyed[key] = candidate
                for i = 1, #ordered do
                    if ordered[i] == current then
                        ordered[i] = candidate
                        break
                    end
                end
            end
        end
    end

    if logger and settings and settings.get("QoLforSacriel_DebugLogs") == true and #ordered ~= #candidates then
        logger.debug("FurnitureNudge deduped candidates: before=" .. tostring(#candidates) .. " after=" .. tostring(#ordered))
    end

    return ordered
end

function FurnitureNudgeRules.resolveCandidates(worldobjects, settings, logger)
    if not worldobjects then
        return {}
    end

    local out = {}
    local seenByObject = {}

    for _, clicked in ipairs(worldobjects) do
        if clicked and clicked.getSquare and clicked:getSquare() then
            local square = clicked:getSquare()
            local moveables = ISMoveableTools.getMoveableList(square)

            for _, entry in ipairs(moveables) do
                if entry and entry.object == clicked and entry.moveProps and entry.moveProps.isMoveable then
                    addCandidate(out, seenByObject, entry, square, settings, logger)
                end
            end
        end
    end

    for _, clicked in ipairs(worldobjects) do
        local square = clicked and clicked.getSquare and clicked:getSquare() or nil
        if square then
            local moveables = ISMoveableTools.getMoveableList(square)
            for _, entry in ipairs(moveables) do
                if entry and entry.object and entry.moveProps and entry.moveProps.isMoveable then
                    addCandidate(out, seenByObject, entry, square, settings, logger)
                end
            end
        end
    end

    return collapseDuplicateCandidates(out, settings, logger)
end

function FurnitureNudgeRules.resolveCandidate(worldobjects, settings, logger)
    local candidates = FurnitureNudgeRules.resolveCandidates(worldobjects, settings, logger)
    if #candidates == 0 then
        return nil
    end
    return candidates[1]
end

local function getLateralOffsets(direction)
    if direction.dx ~= 0 then
        return {
            { dx = 0, dy = -1 },
            { dx = 0, dy = 1 },
        }
    end
    return {
        { dx = -1, dy = 0 },
        { dx = 1, dy = 0 },
    }
end

local function hasWallOnSide(square, sideOffset)
    local sideSquare = getCell():getGridSquare(square:getX() + sideOffset.dx, square:getY() + sideOffset.dy, square:getZ())
    if not sideSquare then
        return false
    end
    return square:isWallTo(sideSquare) or sideSquare:isWallTo(square)
end

local function isParallelWallSlideBlocked(sourceSquare, targetSquare, direction)
    if not sourceSquare or not targetSquare then
        return false
    end

    local lateralOffsets = getLateralOffsets(direction)
    local blockedSides = 0
    for _, lateral in ipairs(lateralOffsets) do
        local sourceHasWall = hasWallOnSide(sourceSquare, lateral)
        local targetHasWall = hasWallOnSide(targetSquare, lateral)
        if sourceHasWall and targetHasWall then
            blockedSides = blockedSides + 1
        end
    end

    -- Only block when movement stays pinched between walls on both lateral sides.
    return blockedSides >= 2
end

function FurnitureNudgeRules.canMoveDirection(playerObj, candidate, direction, settings)
    if not playerObj or not candidate or not candidate.object or not direction then
        return false
    end

    local sourceSquare = candidate.object:getSquare()
    if not sourceSquare then
        return false
    end

    local targetSquare = getCell():getGridSquare(sourceSquare:getX() + direction.dx, sourceSquare:getY() + direction.dy, sourceSquare:getZ())
    if not targetSquare then
        return false
    end

    if hasEdgeBlocker(sourceSquare, targetSquare) then
        return false
    end

    if isParallelWallSlideBlocked(sourceSquare, targetSquare, direction) then
        if candidate then
            candidate.disableReason = FurnitureNudgeRules.CANDIDATE_REASON_PARALLEL_WALL
        end
        return false
    end

    local moveProps = candidate.moveProps or ISMoveableSpriteProps.fromObject(candidate.object)
    if not moveProps or not moveProps.isMoveable then
        return false
    end

    local members, memberSet = collectMultiTileMembers(moveProps, sourceSquare)
    local memberSquareSet = buildMemberSquareSet(members)

    if #members > 0 then
        for _, member in ipairs(members) do
            local memberSquare = member.square
            local memberTarget = getCell():getGridSquare(memberSquare:getX() + direction.dx, memberSquare:getY() + direction.dy, memberSquare:getZ())
            if not memberTarget then
                return false
            end
            if hasEdgeBlocker(memberSquare, memberTarget) then
                return false
            end
            local memberTargetKey = squareKey(memberTarget)
            local targetAlreadyCoveredByCurrentFootprint = memberTargetKey and memberSquareSet[memberTargetKey] == true
            if not targetAlreadyCoveredByCurrentFootprint then
                if isSquareBlockedForMove(memberTarget, memberSet, settings) then
                    return false
                end
            end
            -- For multi-tile nudges, per-member vanilla placement checks can reject valid
            -- "slide along own footprint" moves. Keep strict blocker checks per member,
            -- then run one vanilla place check for the root target square below.
        end
        local rootTargetKey = squareKey(targetSquare)
        local rootTargetAlreadyCovered = rootTargetKey and memberSquareSet[rootTargetKey] == true
        if not rootTargetAlreadyCovered and not passesVanillaPlaceCheck(moveProps, targetSquare, memberSet, settings) then
            return false
        end
    else
        if isSquareBlockedForMove(targetSquare, memberSet, settings) then
            return false
        end
        if not passesVanillaPlaceCheck(moveProps, targetSquare, memberSet, settings) then
            return false
        end
    end

    return true
end

function FurnitureNudgeRules.getValidDirections(playerObj, candidate, settings)
    local out = {}
    for _, direction in ipairs(DIRECTIONS) do
        if FurnitureNudgeRules.canMoveDirection(playerObj, candidate, direction, settings) then
            table.insert(out, direction)
        end
    end
    return out
end

function FurnitureNudgeRules.isPlayerCloseEnough(playerObj, candidate)
    if not playerObj or not candidate or not candidate.object then
        return false
    end

    local playerSquare = playerObj:getSquare()
    local sourceSquare = candidate.object:getSquare()
    if not playerSquare or not sourceSquare then
        return false
    end
    if playerSquare:getZ() ~= sourceSquare:getZ() then
        return false
    end

    local moveProps = candidate.moveProps or ISMoveableSpriteProps.fromObject(candidate.object)
    if moveProps and moveProps.isMultiSprite then
        local members = select(1, collectMultiTileMembers(moveProps, sourceSquare))
        for _, member in ipairs(members) do
            local square = member.square
            if square and (playerSquare == square or playerSquare:isAdjacentTo(square)) then
                return true
            end
        end
        return false
    end

    return playerSquare == sourceSquare or playerSquare:isAdjacentTo(sourceSquare)
end

return FurnitureNudgeRules
