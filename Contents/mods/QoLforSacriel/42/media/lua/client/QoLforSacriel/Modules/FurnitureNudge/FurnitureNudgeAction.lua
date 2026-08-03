require "TimedActions/ISBaseTimedAction"
require "Moveables/ISMoveableSpriteProps"

local rules = require "QoLforSacriel/Modules/FurnitureNudge/FurnitureNudgeRules"

FurnitureNudgeAction = ISBaseTimedAction:derive("FurnitureNudgeAction")

local function squareKey(square)
    if not square then
        return nil
    end
    return tostring(square:getX()) .. ":" .. tostring(square:getY()) .. ":" .. tostring(square:getZ())
end

local function getMembers(moveProps, sourceSquare)
    local members = {}
    if not moveProps or not sourceSquare or not moveProps.isMultiSprite or not moveProps.getSpriteGridInfo then
        return members
    end

    local info = moveProps:getSpriteGridInfo(sourceSquare, true)
    if not info then
        return members
    end

    for _, entry in ipairs(info) do
        table.insert(members, entry)
    end

    return members
end

function FurnitureNudgeAction:debugLog(message)
    if not self.logger or not self.settings or self.settings.get("QoLforSacriel_DebugLogs") ~= true then
        return
    end
    self.logger.debug("FurnitureNudge action: " .. tostring(message))
end

function FurnitureNudgeAction:verifyMultiTilePlacement(moveProps, targetSquare, members)
    if #members == 0 or not moveProps or not moveProps.getSpriteGridInfo then
        return false
    end

    local expected = {}
    local expectedCount = 0
    for _, member in ipairs(members) do
        local memberSquare = member.square
        if memberSquare then
            local shifted = getCell():getGridSquare(memberSquare:getX() + self.direction.dx, memberSquare:getY() + self.direction.dy, memberSquare:getZ())
            local key = squareKey(shifted)
            if key and not expected[key] then
                expected[key] = true
                expectedCount = expectedCount + 1
            end
        end
    end

    local placedInfo = moveProps:getSpriteGridInfo(targetSquare, true)
    if not placedInfo then
        self:debugLog("multi-tile verification failed: no placed grid info")
        return false
    end

    local actual = {}
    for _, entry in ipairs(placedInfo) do
        if entry.square then
            actual[squareKey(entry.square)] = true
        end
    end

    for key, _ in pairs(expected) do
        if not actual[key] then
            self:debugLog("multi-tile verification missing square " .. tostring(key))
            return false
        end
    end

    self:debugLog("multi-tile placement verified; expectedSquares=" .. tostring(expectedCount) .. " actualEntries=" .. tostring(#placedInfo))
    return true
end

function FurnitureNudgeAction:placeMultiTileMoveableDirect(moveProps, sourceSquare, targetSquare)
    if not moveProps or not sourceSquare or not targetSquare then
        return false
    end

    local pickedItems = moveProps:pickUpMoveable(self.character, sourceSquare, false, true)
    if not pickedItems or #pickedItems == 0 then
        self:debugLog("multi-tile direct place failed: pickUpMoveable returned no items")
        return false
    end

    local targetGrid = moveProps:getSpriteGridInfo(targetSquare, false)
    if not targetGrid or #targetGrid == 0 then
        self:debugLog("multi-tile direct place failed: no target grid info")
        return false
    end

    if #pickedItems ~= #targetGrid then
        self:debugLog("multi-tile direct place mismatch: pickedItems=" .. tostring(#pickedItems) .. " targetGrid=" .. tostring(#targetGrid))
        return false
    end

    for index, gridMember in ipairs(targetGrid) do
        local item = pickedItems[index]
        if not item or not gridMember or not gridMember.square or not gridMember.sprite then
            self:debugLog("multi-tile direct place failed: missing item or grid member at index=" .. tostring(index))
            return false
        end
        moveProps:placeMoveableInternal(gridMember.square, item, gridMember.sprite:getName())
    end

    if ISMoveableCursor and ISMoveableCursor.clearCacheForAllPlayers then
        ISMoveableCursor.clearCacheForAllPlayers()
    end

    self:debugLog("multi-tile direct place complete: items=" .. tostring(#pickedItems))
    return true
end

function FurnitureNudgeAction:runWithNudgePlaceBypass(moveProps, shouldBypass, fn)
    if not shouldBypass or not moveProps then
        return fn()
    end

    local originalHasRequiredSkill = moveProps.hasRequiredSkill
    local originalHasTool = moveProps.hasTool

    moveProps.hasRequiredSkill = function(_, character, mode)
        if mode == "place" then
            return true
        end
        if originalHasRequiredSkill then
            return originalHasRequiredSkill(moveProps, character, mode)
        end
        return true
    end

    moveProps.hasTool = function(_, character, mode)
        if mode == "place" then
            return true
        end
        if originalHasTool then
            return originalHasTool(moveProps, character, mode)
        end
        return true
    end

    local ok, result = pcall(fn)

    moveProps.hasRequiredSkill = originalHasRequiredSkill
    moveProps.hasTool = originalHasTool

    if not ok then
        self:debugLog("place bypass wrapper error: " .. tostring(result))
        return false
    end

    return result
end

function FurnitureNudgeAction:isValid()
    if not self.character or self.character:isDead() then
        return false
    end
    if not self.object or not self.object:getSquare() then
        return false
    end

    local candidate = {
        object = self.object,
        moveProps = ISMoveableSpriteProps.fromObject(self.object),
        square = self.object:getSquare(),
    }

    if not candidate.moveProps then
        return false
    end

    local allowMultiTile = rules.isMultiTileAllowed(self.settings)
    local ignoreTools = rules.shouldIgnoreToolRequirementForCandidate(candidate, self.settings)

    if candidate.moveProps.isMultiSprite and not allowMultiTile then
        return false
    end

    if rules.requiresTool(candidate.moveProps) and not ignoreTools then
        return false
    end
    if not self.object:isObjectNoContainerOrEmpty() then
        return false
    end
    if rules.isTooTiredForCandidate(self.character, candidate, self.settings, true) then
        return false
    end

    return rules.canMoveDirection(self.character, candidate, self.direction, self.settings)
end

function FurnitureNudgeAction:waitToStart()
    if not self.object then
        return false
    end
    self.character:faceThisObject(self.object)
    return self.character:shouldBeTurning()
end

function FurnitureNudgeAction:update()
    if self.object then
        self.character:faceThisObject(self.object)
    end
    self.character:setMetabolicTarget(Metabolics.UsingTools)
end

function FurnitureNudgeAction:start()
    self:setActionAnim("Shove")
end

function FurnitureNudgeAction:stop()
    ISBaseTimedAction.stop(self)
end

function FurnitureNudgeAction:perform()
    local preCandidate = {
        object = self.object,
        moveProps = self.object and ISMoveableSpriteProps.fromObject(self.object) or nil,
        square = self.object and self.object:getSquare() or nil,
    }
    local plannedCost = rules.getEnduranceCost(preCandidate, self.settings, false)
    self._plannedEnduranceCost = plannedCost

    if rules.isTooTiredForCandidate(self.character, preCandidate, self.settings, false) then
        if self.logger then
            self.logger.debug("FurnitureNudge move blocked at perform stage: too tired")
        end
        ISBaseTimedAction.perform(self)
        return
    end

    local ok = self:executeMove()
    if ok then
        self:applyEnduranceCost()
    elseif self.logger then
        self.logger.debug("FurnitureNudge move failed at perform stage")
    end

    ISBaseTimedAction.perform(self)
end

function FurnitureNudgeAction:executeMove()
    if not self.object or not self.object:getSquare() then
        return false
    end

    local sourceSquare = self.object:getSquare()
    local moveProps = ISMoveableSpriteProps.fromObject(self.object)
    if not moveProps or not moveProps.isMoveable then
        return false
    end

    local targetSquare = getCell():getGridSquare(sourceSquare:getX() + self.direction.dx, sourceSquare:getY() + self.direction.dy, sourceSquare:getZ())
    if not targetSquare then
        return false
    end

    local candidate = {
        object = self.object,
        moveProps = moveProps,
        square = sourceSquare,
    }

    local allowMultiTile = rules.isMultiTileAllowed(self.settings)
    local ignoreTools = rules.shouldIgnoreToolRequirementForCandidate(candidate, self.settings)
    if moveProps.isMultiSprite and not allowMultiTile then
        self:debugLog("execute blocked: multi-tile disabled")
        return false
    end
    if rules.requiresTool(moveProps) and not ignoreTools then
        self:debugLog("execute blocked: tool requirement still active")
        return false
    end

    if not rules.canMoveDirection(self.character, candidate, self.direction, self.settings) then
        self:debugLog("execute blocked: canMoveDirection=false")
        return false
    end

    local members = getMembers(moveProps, sourceSquare)
    self:debugLog("execute begin: multiTile=" .. tostring(moveProps.isMultiSprite == true) .. " members=" .. tostring(#members) .. " ignoreTools=" .. tostring(ignoreTools))
    local placedOk
    if moveProps.isMultiSprite then
        self:debugLog("placing multi-tile moveable via direct path")
        local multiPlaced = self:runWithNudgePlaceBypass(moveProps, ignoreTools, function()
            return self:placeMultiTileMoveableDirect(moveProps, sourceSquare, targetSquare)
        end)
        if not multiPlaced then
            self:debugLog("multi-tile direct place invocation failed")
            return false
        end
        placedOk = self:verifyMultiTilePlacement(moveProps, targetSquare, members)
    else
        local picked = moveProps:pickUpMoveable(self.character, sourceSquare, true, true)
        if not picked then
            self:debugLog("pickUpMoveable returned false")
            return false
        end

        local forceAllowPlace = ignoreTools
        self:debugLog("placing single-tile moveable with forceAllow=" .. tostring(forceAllowPlace))
        local placeInvocationOk = self:runWithNudgePlaceBypass(moveProps, ignoreTools, function()
            moveProps:placeMoveable(self.character, targetSquare, moveProps.spriteName, forceAllowPlace)
            return true
        end)
        if not placeInvocationOk then
            self:debugLog("placeMoveable invocation failed")
            return false
        end

        local placed = moveProps:findOnSquare(targetSquare, moveProps.spriteName)
        placedOk = placed ~= nil
        self:debugLog("single-tile placement check: " .. tostring(placedOk))
    end

    if not placedOk then
        self:debugLog("placement verification failed")
        return false
    end

    return true
end

function FurnitureNudgeAction:applyEnduranceCost()
    if not self.character then
        return
    end

    local stats = self.character:getStats()
    if not stats then
        return
    end

    local cost = tonumber(self._plannedEnduranceCost) or 0
    if cost <= 0 then
        local candidate = {
            object = self.object,
            moveProps = self.object and ISMoveableSpriteProps.fromObject(self.object) or nil,
            square = self.object and self.object:getSquare() or nil,
        }
        cost = rules.getEnduranceCost(candidate, self.settings, false)
    end

    stats:remove(CharacterStat.ENDURANCE, cost)
    if syncPlayerStats then
        syncPlayerStats(self.character, 0x00000002)
    end
end

function FurnitureNudgeAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end

    local rawWeight = 50
    if self.object then
        local props = ISMoveableSpriteProps.fromObject(self.object)
        if props and props.rawWeight then
            rawWeight = tonumber(props.rawWeight) or rawWeight
        end
    end

    local duration = 30 + math.floor(rawWeight * 0.6)
    return math.max(20, duration)
end

function FurnitureNudgeAction:new(character, object, direction, settings, logger)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.object = object
    o.direction = direction
    o.settings = settings
    o.logger = logger
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    o.maxTime = o:getDuration()
    return o
end

return FurnitureNudgeAction
