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

local ENDURANCE_EPSILON = 0.0001
local FLUID_ENDURANCE_PER_LITER = 0.005

local EXPLICIT_NON_BLOCKING_SPRITES = {
    walls_decoration_01_91 = true,
    rooftop_furniture_34 = true,
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

local function getNudgeRuleOptions(settings)
    return {
        allowMultiTile = settings and settings.get and settings.get("QoLforSacriel_FurnitureNudge_AllowMultiTile") == true,
        ignoreToolRequirements = settings and settings.get and settings.get("QoLforSacriel_FurnitureNudge_IgnoreToolRequirements") == true,
    }
end

local function isFurnitureMoveableCandidate(object, moveProps)
    if not object or not moveProps then
        return false
    end
    if moveProps.isMoveable ~= true then
        return false
    end
    if instanceof(object, "IsoDoor") or instanceof(object, "IsoWindow") then
        return false
    end
    if moveProps.type == "Window" or moveProps.type == "WindowObject" then
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

    local ignoreTools = shouldIgnoreToolRequirement(object, moveProps, options)
    if requiresTool(moveProps) and not ignoreTools then
        return true, FurnitureNudgeRules.CANDIDATE_REASON_REQUIRES_TOOL
    end
    if moveProps.isMultiSprite and (not options or options.allowMultiTile ~= true) then
        return true, FurnitureNudgeRules.CANDIDATE_REASON_MULTI_TILE
    end
    if not object:isObjectNoContainerOrEmpty() then
        return true, FurnitureNudgeRules.CANDIDATE_REASON_HAS_CONTENTS
    end
    if instanceof(object, "IsoDoor") or instanceof(object, "IsoWindow") then
        return true, FurnitureNudgeRules.CANDIDATE_REASON_NOT_MOVEABLE
    end
    if moveProps.type == "Window" or moveProps.type == "WindowObject" then
        return true, FurnitureNudgeRules.CANDIDATE_REASON_NOT_MOVEABLE
    end
    return false, nil
end

function FurnitureNudgeRules.requiresTool(moveProps)
    return requiresTool(moveProps)
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
    local disallowed, reason = isCandidateDisallowed(entry.object, entry.moveProps, options)
    logCandidateDecision(settings, logger, entry.object, reason or "ok", disallowed, options)
    table.insert(out, {
        object = entry.object,
        moveProps = entry.moveProps,
        square = square,
        isNudgeDisabled = disallowed,
        disableReason = reason,
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
