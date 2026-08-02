require "TimedActions/ISBaseTimedAction"
require "Moveables/ISMoveableSpriteProps"

local rules = require "QoLforSacriel/Modules/FurnitureNudge/FurnitureNudgeRules"

FurnitureNudgeAction = ISBaseTimedAction:derive("FurnitureNudgeAction")

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

    if not candidate.moveProps or candidate.moveProps.isMultiSprite then
        return false
    end
    if rules.requiresTool(candidate.moveProps) then
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
    if not rules.canMoveDirection(self.character, candidate, self.direction, self.settings) then
        return false
    end

    local picked = moveProps:pickUpMoveable(self.character, sourceSquare, true, true)
    if not picked then
        return false
    end

    moveProps:placeMoveable(self.character, targetSquare, moveProps.spriteName, false)

    local placed = moveProps:findOnSquare(targetSquare, moveProps.spriteName)
    return placed ~= nil
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
