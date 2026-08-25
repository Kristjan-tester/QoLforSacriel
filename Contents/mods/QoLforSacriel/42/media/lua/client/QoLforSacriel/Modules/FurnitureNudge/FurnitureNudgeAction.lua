-- ff-assisted
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

local function refreshContainerState(object)
    if object and ItemPickerJava and ItemPickerJava.updateOverlaySprite then
        ItemPickerJava.updateOverlaySprite(object)
    end
    triggerEvent("OnContainerUpdate")
    if ISInventoryPage then
        ISInventoryPage.renderDirty = true
    end
end

local function objectIsOnSquare(object, square)
    return object
        and square
        and object:getSquare() == square
        and square:getObjects()
        and square:getObjects():contains(object)
end

local function findUniqueObjectOnSquare(square, spriteName)
    if not square or not spriteName or not square:getObjects() then
        return nil
    end

    local found = nil
    local count = 0
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        local sprite = object and object:getSprite() or nil
        if sprite and sprite:getName() == spriteName then
            found = object
            count = count + 1
        end
    end

    if count == 1 then
        return found
    end
    return nil
end

local function captureContainerSnapshot(object)
    if not object or object:getContainerCount() < 1 then
        return nil
    end

    local persistentModData, unknownModDataKeys = rules.capturePersistentObjectModData(object)
    if unknownModDataKeys then
        return nil
    end

    local snapshot = {
        containers = {},
        persistentModData = persistentModData,
        items = {},
        ids = {},
    }
    for containerIndex = 0, object:getContainerCount() - 1 do
        local container = object:getContainerByIndex(containerIndex)
        if not container or not container:isExplored() then
            return nil
        end

        local containerSnapshot = {
            index = containerIndex,
            source = container,
            containerType = tostring(container:getType() or ""),
            customName = container:getCustomName(),
            customTemperature = container.getCustomTemperature
                and container:getCustomTemperature() or 0,
            items = {},
            ids = {},
        }
        local javaItems = container:getItems()
        for itemIndex = 0, javaItems:size() - 1 do
            local item = javaItems:get(itemIndex)
            local itemId = item and item:getID() or nil
            if not item or itemId == nil or snapshot.ids[itemId] then
                return nil
            end
            snapshot.ids[itemId] = true
            containerSnapshot.ids[itemId] = true
            snapshot.items[#snapshot.items + 1] = item
            containerSnapshot.items[#containerSnapshot.items + 1] = item
        end
        if containerSnapshot.customName then
            persistentModData[
                containerSnapshot.containerType .. "_customContainerName"
            ] = containerSnapshot.customName
        end
        snapshot.containers[#snapshot.containers + 1] = containerSnapshot
    end
    return snapshot
end

local function captureMultiFurnitureSnapshot(moveProps, sourceSquare)
    local members = getMembers(moveProps, sourceSquare)
    if #members == 0 then
        return nil
    end

    local snapshot = { members = {}, totalItems = 0 }
    local allIds = {}
    for memberIndex, member in ipairs(members) do
        local object = member.object
        if not object or not member.square or not member.sprite then
            return nil
        end

        local persistentModData, unknownModDataKeys = rules.capturePersistentObjectModData(object)
        if unknownModDataKeys then
            return nil
        end

        local memberSnapshot = {
            index = memberIndex,
            object = object,
            square = member.square,
            spriteName = member.sprite:getName(),
            sprInstance = member.sprInstance,
            persistentModData = persistentModData,
            containers = {},
            worldObjectsBefore = {},
        }

        local worldObjects = member.square:getWorldObjects()
        if worldObjects then
            for index = 0, worldObjects:size() - 1 do
                memberSnapshot.worldObjectsBefore[worldObjects:get(index)] = true
            end
        end

        for containerIndex = 0, object:getContainerCount() - 1 do
            local container = object:getContainerByIndex(containerIndex)
            if not container or not container:isExplored() then
                return nil
            end

            local containerSnapshot = {
                index = containerIndex,
                source = container,
                containerType = tostring(container:getType() or ""),
                customName = container:getCustomName(),
                customTemperature = container.getCustomTemperature
                    and container:getCustomTemperature() or 0,
                items = {},
                ids = {},
            }
            local javaItems = container:getItems()
            for itemIndex = 0, javaItems:size() - 1 do
                local item = javaItems:get(itemIndex)
                local itemId = item and item:getID() or nil
                if not item or itemId == nil or allIds[itemId] then
                    return nil
                end
                allIds[itemId] = true
                containerSnapshot.ids[itemId] = true
                containerSnapshot.items[#containerSnapshot.items + 1] = item
                snapshot.totalItems = snapshot.totalItems + 1
            end
            if containerSnapshot.customName then
                memberSnapshot.persistentModData[
                    containerSnapshot.containerType .. "_customContainerName"
                ] = containerSnapshot.customName
            end
            memberSnapshot.containers[#memberSnapshot.containers + 1] = containerSnapshot
        end
        snapshot.members[#snapshot.members + 1] = memberSnapshot
    end

    return snapshot
end

local function copyPersistentValue(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for key, nestedValue in pairs(value) do
        copy[copyPersistentValue(key, seen)] = copyPersistentValue(nestedValue, seen)
    end
    return copy
end

local function applyPersistentObjectModData(object, snapshot)
    if not object or not snapshot then
        return false
    end

    local modData = object:getModData()
    local keys = {}
    for key, _ in pairs(modData) do
        keys[#keys + 1] = key
    end
    for _, key in ipairs(keys) do
        modData[key] = nil
    end
    for key, value in pairs(snapshot.persistentModData or {}) do
        modData[key] = copyPersistentValue(value)
    end
    return true
end

local function applyMemberPersistentModData(object, memberSnapshot)
    return applyPersistentObjectModData(object, {
        persistentModData = memberSnapshot.persistentModData,
    })
end

local function snapshotMatchesContainer(snapshot, container)
    if not snapshot or not container or container:getItems():size() ~= #snapshot.items then
        return false
    end

    for _, item in ipairs(snapshot.items) do
        if not container:contains(item)
        or item:getContainer() ~= container
        or not snapshot.ids[item:getID()]
        then
            return false
        end
    end
    return true
end

local function detachSnapshot(snapshot)
    for _, containerSnapshot in ipairs(snapshot.containers) do
        for index = #containerSnapshot.items, 1, -1 do
            local item = containerSnapshot.items[index]
            if not containerSnapshot.source:contains(item) then
                return false
            end
            containerSnapshot.source:Remove(item)
            if item:getContainer() ~= nil then
                return false
            end
        end
    end
    return true
end

local function detachMultiSnapshot(snapshot)
    for _, member in ipairs(snapshot.members) do
        for _, container in ipairs(member.containers) do
            for index = #container.items, 1, -1 do
                local item = container.items[index]
                if not container.source:contains(item) then
                    return false
                end
                container.source:Remove(item)
                if item:getContainer() ~= nil then
                    return false
                end
            end
        end
    end
    return true
end

local function restoreSnapshot(snapshot, container)
    if not snapshot or not container or container:getItems():size() ~= 0 then
        return false
    end

    if snapshot.customName and container.setCustomName then
        container:setCustomName(snapshot.customName)
    end
    if container.setCustomTemperature then
        container:setCustomTemperature(tonumber(snapshot.customTemperature) or 0)
    end

    for _, item in ipairs(snapshot.items) do
        container:AddItem(item)
        if not container:contains(item)
        or item:getContainer() ~= container
        or not snapshot.ids[item:getID()]
        then
            return false
        end
    end
    return snapshotMatchesContainer(snapshot, container)
end

local function restoreSnapshotToExistingContainer(snapshot, container)
    if not snapshot or not container then
        return false
    end

    local currentItems = container:getItems()
    for index = 0, currentItems:size() - 1 do
        local currentItem = currentItems:get(index)
        if not currentItem or not snapshot.ids[currentItem:getID()] then
            return false
        end
    end

    if snapshot.customName and container.setCustomName then
        container:setCustomName(snapshot.customName)
    end
    if container.setCustomTemperature then
        container:setCustomTemperature(tonumber(snapshot.customTemperature) or 0)
    end

    for _, item in ipairs(snapshot.items) do
        if not container:contains(item) then
            container:AddItem(item)
        end
    end
    return snapshotMatchesContainer(snapshot, container)
end

local function restoreObjectContainers(snapshot, object, allowExisting)
    if not snapshot or not object
    or object:getContainerCount() ~= #snapshot.containers
    then
        return false
    end

    for _, containerSnapshot in ipairs(snapshot.containers) do
        local container = object:getContainerByIndex(containerSnapshot.index)
        if not container
        or tostring(container:getType() or "") ~= containerSnapshot.containerType
        then
            return false
        end
        local restored = allowExisting
            and restoreSnapshotToExistingContainer(containerSnapshot, container)
            or restoreSnapshot(containerSnapshot, container)
        if not restored then
            return false
        end
    end
    return applyPersistentObjectModData(object, snapshot)
end

local function restoreMemberContainers(memberSnapshot, object, allowExisting)
    if not memberSnapshot or not object
    or object:getContainerCount() ~= #memberSnapshot.containers
    then
        return false
    end

    for _, containerSnapshot in ipairs(memberSnapshot.containers) do
        local container = object:getContainerByIndex(containerSnapshot.index)
        if not container
        or tostring(container:getType() or "") ~= containerSnapshot.containerType
        then
            return false
        end
        local restored = allowExisting
            and restoreSnapshotToExistingContainer(containerSnapshot, container)
            or restoreSnapshot(containerSnapshot, container)
        if not restored then
            return false
        end
    end
    return applyMemberPersistentModData(object, memberSnapshot)
end

local function detachSnapshotItemsFromCurrentContainers(snapshot)
    for _, item in ipairs(snapshot.items) do
        pcall(function()
            local container = item:getContainer()
            if container and container.contains and container:contains(item) then
                container:Remove(item)
            end
        end)
    end
end

local function detachMultiSnapshotItemsFromCurrentContainers(snapshot)
    for _, member in ipairs(snapshot.members) do
        for _, container in ipairs(member.containers) do
            detachSnapshotItemsFromCurrentContainers(container)
        end
    end
end

local function rescueFurnitureItemToFloor(state)
    local item = state.rollbackItem or state.temporaryItem
    if not item or item:getContainer() or item:getWorldItem() then
        return false
    end

    local square = state.sourceSquare or state.targetSquare
    if not square then
        return false
    end

    local ok = pcall(function()
        square:AddWorldInventoryItem(item, 0.5, 0.5, 0.0)
    end)
    return ok and item:getWorldItem() ~= nil
end

local function captureInventoryItemReferences(character)
    local references = {}
    local inventory = character and character:getInventory() or nil
    local items = inventory and inventory:getItems() or nil
    if items then
        for index = 0, items:size() - 1 do
            references[items:get(index)] = true
        end
    end
    return references
end

local function findNewFurnitureItem(character, spriteName, previousItems)
    local inventory = character and character:getInventory() or nil
    local items = inventory and inventory:getItems() or nil
    if not items then
        return nil
    end

    local found = nil
    local count = 0
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local okMoveable, isMoveable = pcall(instanceof, item, "Moveable")
        if okMoveable
        and isMoveable
        and not previousItems[item]
        and item:getWorldSprite() == spriteName
        then
            found = item
            count = count + 1
        end
    end

    if count == 1 then
        return found
    end
    return nil
end

local function removeTemporaryFurnitureFromInventory(character, item)
    if not item then
        return true
    end
    local inventory = character and character:getInventory() or nil
    if item:getContainer() ~= inventory then
        return item:getContainer() == nil
    end
    inventory:Remove(item)
    return item:getContainer() == nil
end

local function rescueSnapshotItems(character, sourceSquare, targetSquare, snapshot)
    local inventory = character and character:getInventory() or nil
    local floorSquare = sourceSquare or targetSquare
    local rescuedToInventory = 0
    local rescuedToFloor = 0

    for _, item in ipairs(snapshot.items) do
        if not item:getContainer() and not item:getWorldItem() and inventory then
            pcall(function()
                inventory:AddItem(item)
            end)
        end
        if item:getContainer() == inventory then
            rescuedToInventory = rescuedToInventory + 1
        elseif not item:getContainer() and not item:getWorldItem() and floorSquare then
            pcall(function()
                floorSquare:AddWorldInventoryItem(item, 0.5, 0.5, 0.0)
            end)
            if item:getWorldItem() then
                rescuedToFloor = rescuedToFloor + 1
            end
        end
    end

    return rescuedToInventory, rescuedToFloor
end

local function rescueMultiSnapshotItems(character, sourceSquare, targetSquare, snapshot)
    local inventoryCount = 0
    local floorCount = 0
    for _, member in ipairs(snapshot.members) do
        for _, container in ipairs(member.containers) do
            local memberInventory, memberFloor = rescueSnapshotItems(
                character,
                sourceSquare,
                targetSquare,
                container
            )
            inventoryCount = inventoryCount + memberInventory
            floorCount = floorCount + memberFloor
        end
    end
    return inventoryCount, floorCount
end

local function findTemporaryWorldItem(memberSnapshot)
    local worldObjects = memberSnapshot.square:getWorldObjects()
    if not worldObjects then
        return nil, nil
    end

    local foundObject = nil
    local foundItem = nil
    local count = 0
    for index = 0, worldObjects:size() - 1 do
        local worldObject = worldObjects:get(index)
        if not memberSnapshot.worldObjectsBefore[worldObject]
        and instanceof(worldObject, "IsoWorldInventoryObject")
        then
            local item = worldObject:getItem()
            if item and item:getWorldSprite() == memberSnapshot.spriteName then
                foundObject = worldObject
                foundItem = item
                count = count + 1
            end
        end
    end
    if count == 1 then
        return foundObject, foundItem
    end
    return nil, nil
end

local function removeTemporaryWorldObject(worldObject, item)
    if not worldObject then
        return true
    end
    local square = worldObject:getSquare()
    if not square then
        return false
    end
    square:transmitRemoveItemFromSquare(worldObject)
    square:removeWorldObject(worldObject)
    if item then
        item:setWorldItem(nil)
    end
    return item == nil or item:getWorldItem() == nil
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
    if rules.isWindowLike(self.object, candidate.moveProps) then
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
    local containerRoute = rules.classifyContainerMove(self.object, candidate.moveProps, self.settings)
    if containerRoute == rules.CONTAINER_ROUTE_BLOCKED then
        return false
    end
    if rules.isTooTiredForCandidate(self.character, candidate, self.settings, true) then
        return false
    end

    return rules.canMoveDirection(self.character, candidate, self.direction, self.settings)
end

function FurnitureNudgeAction:recoverKeepInventoryMultiMove(state, failure)
    local restoredMembers = 0
    local inventoryItems = 0
    local floorItems = 0

    for _, member in ipairs(state.snapshot.members) do
        if not state.temporaryItems[member.index] then
            local worldObject, item = findTemporaryWorldItem(member)
            state.temporaryWorldObjects[member.index] = worldObject
            state.temporaryItems[member.index] = item
        end

        local sourceObject = objectIsOnSquare(member.object, member.square)
            and member.object or nil
        local targetMember = state.targetGrid[member.index]
        local destinationObject = state.destinationObjects[member.index]
        if not sourceObject
        and destinationObject
        and objectIsOnSquare(destinationObject, targetMember.square)
        then
            pcall(function()
                for _, container in ipairs(member.containers) do
                    detachSnapshotItemsFromCurrentContainers(container)
                end
                local rollbackItem = state.placeProps:pickUpMoveableInternal(
                    self.character,
                    targetMember.square,
                    destinationObject,
                    nil,
                    targetMember.sprite:getName(),
                    false,
                    true
                )
                if rollbackItem then
                    sourceObject = state.placeProps:placeMoveableInternal(
                        member.square,
                        rollbackItem,
                        member.spriteName
                    )
                    if not sourceObject and not rollbackItem:getWorldItem() then
                        member.square:AddWorldInventoryItem(rollbackItem, 0.5, 0.5, 0.0)
                    end
                end
            end)
        end

        if not sourceObject and state.temporaryItems[member.index] then
            pcall(function()
                removeTemporaryWorldObject(
                    state.temporaryWorldObjects[member.index],
                    state.temporaryItems[member.index]
                )
                sourceObject = state.placeProps:placeMoveableInternal(
                    member.square,
                    state.temporaryItems[member.index],
                    member.spriteName
                )
            end)
        end

        if not sourceObject then
            sourceObject = findUniqueObjectOnSquare(member.square, member.spriteName)
        end

        local restored = false
        if sourceObject and objectIsOnSquare(sourceObject, member.square) then
            pcall(function()
                restored = restoreMemberContainers(member, sourceObject, true)
                if restored then
                    refreshContainerState(sourceObject)
                end
            end)
        end
        if restored then
            restoredMembers = restoredMembers + 1
        else
            for _, container in ipairs(member.containers) do
                detachSnapshotItemsFromCurrentContainers(container)
                local rescuedInventory, rescuedFloor = rescueSnapshotItems(
                    self.character,
                    member.square,
                    targetMember and targetMember.square or state.targetSquare,
                    container
                )
                inventoryItems = inventoryItems + rescuedInventory
                floorItems = floorItems + rescuedFloor
            end
        end

        pcall(function()
            removeTemporaryWorldObject(
                state.temporaryWorldObjects[member.index],
                state.temporaryItems[member.index]
            )
        end)
    end

    refreshContainerState(nil)
    if self.logger and self.logger.error then
        self.logger.error(
            "FurnitureNudge multi keep-inventory failed phase=" .. tostring(state.phase)
            .. " error=" .. tostring(failure)
            .. " restoredMembers=" .. tostring(restoredMembers)
            .. "/" .. tostring(#state.snapshot.members)
            .. " inventory=" .. tostring(inventoryItems)
            .. " floor=" .. tostring(floorItems)
        )
    end
    return false
end

function FurnitureNudgeAction:executeKeepInventoryMultiMove(object, moveProps, sourceSquare, targetSquare)
    local route = rules.classifyContainerMove(object, moveProps, self.settings)
    local snapshot = captureMultiFurnitureSnapshot(moveProps, sourceSquare)
    local targetGrid = moveProps:getSpriteGridInfo(targetSquare, false)
    local placeProps = ISMoveableSpriteProps.new(moveProps.spriteName)
    if route ~= rules.CONTAINER_ROUTE_KEEP
    or not snapshot
    or not targetGrid
    or #targetGrid ~= #snapshot.members
    or not placeProps
    or not ItemPickerJava
    or not ItemPickerJava.updateOverlaySprite
    then
        return false
    end

    local state = {
        phase = "detach",
        snapshot = snapshot,
        sourceSquare = sourceSquare,
        targetSquare = targetSquare,
        targetGrid = targetGrid,
        placeProps = placeProps,
        temporaryWorldObjects = {},
        temporaryItems = {},
        destinationObjects = {},
    }

    local ok, result = pcall(function()
        if not detachMultiSnapshot(snapshot) then
            error("multi detach verification failed")
        end

        state.phase = "pickup"
        moveProps:pickUpMoveable(self.character, sourceSquare, true, true)
        for _, member in ipairs(snapshot.members) do
            local worldObject, item = findTemporaryWorldItem(member)
            if not worldObject or not item then
                error("multi temporary item missing index=" .. tostring(member.index))
            end
            state.temporaryWorldObjects[member.index] = worldObject
            state.temporaryItems[member.index] = item
        end

        state.phase = "placement"
        for _, member in ipairs(snapshot.members) do
            local targetMember = targetGrid[member.index]
            local placedObject = placeProps:placeMoveableInternal(
                targetMember.square,
                state.temporaryItems[member.index],
                targetMember.sprite:getName()
            )
            if not placedObject
            or not objectIsOnSquare(placedObject, targetMember.square)
            or placedObject:getSprite():getName() ~= targetMember.sprite:getName()
            then
                error("multi placement failed index=" .. tostring(member.index))
            end
            local componentsOk, componentReason = rules.validateOccupiedComponents(
                placedObject,
                true
            )
            if not componentsOk then
                error("multi destination component=" .. tostring(componentReason))
            end
            state.destinationObjects[member.index] = placedObject
        end

        state.phase = "restore"
        for _, member in ipairs(snapshot.members) do
            local placedObject = state.destinationObjects[member.index]
            if not restoreMemberContainers(member, placedObject, false) then
                error("multi restore failed index=" .. tostring(member.index))
            end
            refreshContainerState(placedObject)
        end

        state.phase = "cleanup"
        for _, member in ipairs(snapshot.members) do
            if not removeTemporaryWorldObject(
                state.temporaryWorldObjects[member.index],
                state.temporaryItems[member.index]
            ) then
                error("multi temporary cleanup failed index=" .. tostring(member.index))
            end
        end
        if ISMoveableCursor and ISMoveableCursor.clearCacheForAllPlayers then
            ISMoveableCursor.clearCacheForAllPlayers()
        end
        return true
    end)

    if not ok or result ~= true then
        return self:recoverKeepInventoryMultiMove(
            state,
            ok and "transaction returned false" or result
        )
    end
    self:debugLog("multi keep-inventory move complete items=" .. tostring(snapshot.totalItems))
    return true
end

function FurnitureNudgeAction:recoverKeepInventoryMove(state, failure)
    local sourceObject = objectIsOnSquare(state.object, state.sourceSquare) and state.object or nil

    if not state.temporaryItem then
        state.temporaryItem = findNewFurnitureItem(
            self.character,
            state.spriteName,
            state.previousInventoryItems
        )
    end

    if not sourceObject and not objectIsOnSquare(state.destinationObject, state.targetSquare) then
        state.destinationObject = findUniqueObjectOnSquare(state.targetSquare, state.spriteName)
    end

    if not sourceObject and objectIsOnSquare(state.destinationObject, state.targetSquare) then
        pcall(function()
            detachSnapshotItemsFromCurrentContainers(state.snapshot)
            if not removeTemporaryFurnitureFromInventory(self.character, state.temporaryItem) then
                error("temporary furniture inventory removal failed")
            end
            state.temporaryItem = nil
            state.rollbackItem = state.placeProps:pickUpMoveableInternal(
                self.character,
                state.targetSquare,
                state.destinationObject,
                nil,
                state.spriteName,
                false,
                true
            )
            if state.rollbackItem then
                sourceObject = state.placeProps:placeMoveableInternal(
                    state.sourceSquare,
                    state.rollbackItem,
                    state.spriteName
                )
                if sourceObject then
                    state.rollbackItem = nil
                end
            end
        end)
    elseif not sourceObject and state.temporaryItem then
        pcall(function()
            sourceObject = state.placeProps:placeMoveableInternal(
                state.sourceSquare,
                state.temporaryItem,
                state.spriteName
            )
            if sourceObject then
                state.temporaryItem = nil
            end
        end)
    end

    if not sourceObject then
        sourceObject = findUniqueObjectOnSquare(state.sourceSquare, state.spriteName)
        if sourceObject then
            state.rollbackItem = nil
            state.temporaryItem = nil
        end
    end

    local restored = false
    if objectIsOnSquare(sourceObject, state.sourceSquare) then
        pcall(function()
            restored = restoreObjectContainers(state.snapshot, sourceObject, true)
            if restored then
                refreshContainerState(sourceObject)
            end
        end)
    end

    local rescuedToInventory = 0
    local rescuedToFloor = 0
    local furnitureRescuedToFloor = false
    if not restored then
        detachSnapshotItemsFromCurrentContainers(state.snapshot)
        rescuedToInventory, rescuedToFloor = rescueSnapshotItems(
            self.character,
            state.sourceSquare,
            state.targetSquare,
            state.snapshot
        )
        furnitureRescuedToFloor = rescueFurnitureItemToFloor(state)
        refreshContainerState(nil)
        local message = getTextOrNull and getTextOrNull("UI_QoLforSacriel_FurnitureNudgeKeepInventoryRecovery")
            or "The furniture could not be moved safely. Its items were recovered nearby."
        if self.character and self.character.setHaloNote then
            self.character:setHaloNote(message)
        end
    end

    if self.logger and self.logger.error then
        self.logger.error(
            "FurnitureNudge keep-inventory failed phase=" .. tostring(state.phase)
            .. " error=" .. tostring(failure)
            .. " restored=" .. tostring(restored)
            .. " inventory=" .. tostring(rescuedToInventory)
            .. " floor=" .. tostring(rescuedToFloor)
            .. " furnitureFloor=" .. tostring(furnitureRescuedToFloor)
        )
    end
    return false
end

function FurnitureNudgeAction:executeKeepInventoryMove(object, moveProps, sourceSquare, targetSquare)
    local route = rules.classifyContainerMove(object, moveProps, self.settings)
    if route ~= rules.CONTAINER_ROUTE_KEEP then
        return false
    end

    local exactObject, spriteInstance = moveProps:findOnSquare(sourceSquare, moveProps.spriteName)
    local placeProps = ISMoveableSpriteProps.new(moveProps.spriteName)
    local snapshot = captureContainerSnapshot(object)
    if exactObject ~= object
    or spriteInstance ~= nil
    or not placeProps
    or not snapshot
    or not ItemPickerJava
    or not ItemPickerJava.updateOverlaySprite
    then
        return false
    end

    local state = {
        phase = "detach",
        object = object,
        sourceSquare = sourceSquare,
        targetSquare = targetSquare,
        spriteName = moveProps.spriteName,
        placeProps = placeProps,
        snapshot = snapshot,
        previousInventoryItems = captureInventoryItemReferences(self.character),
        temporaryItem = nil,
        destinationObject = nil,
        rollbackItem = nil,
    }

    local ok, result = pcall(function()
        if not detachSnapshot(snapshot) then
            error("detach verification failed")
        end

        state.phase = "pickup"
        moveProps:pickUpMoveable(self.character, sourceSquare, true, true)
        state.temporaryItem = findNewFurnitureItem(
            self.character,
            moveProps.spriteName,
            state.previousInventoryItems
        )
        if not state.temporaryItem then
            error("pickup failed")
        end

        state.phase = "placement"
        state.destinationObject = placeProps:placeMoveableInternal(
            targetSquare,
            state.temporaryItem,
            moveProps.spriteName
        )
        if state.destinationObject then
            if not removeTemporaryFurnitureFromInventory(self.character, state.temporaryItem) then
                error("temporary furniture inventory removal failed")
            end
            state.temporaryItem = nil
        end
        if not state.destinationObject
        or not objectIsOnSquare(state.destinationObject, targetSquare)
        or findUniqueObjectOnSquare(targetSquare, moveProps.spriteName) ~= state.destinationObject
        or not state.destinationObject:getSprite()
        or state.destinationObject:getSprite():getName() ~= moveProps.spriteName
        or state.destinationObject:getContainerCount() ~= #snapshot.containers
        then
            error("destination verification failed")
        end

        local componentsOk, componentReason = rules.validateOccupiedComponents(
            state.destinationObject,
            false
        )
        if not componentsOk then
            error("destination layout changed component=" .. tostring(componentReason))
        end

        state.phase = "restore"
        if not restoreObjectContainers(snapshot, state.destinationObject, false) then
            error("item restore verification failed")
        end

        state.phase = "refresh"
        refreshContainerState(state.destinationObject)
        return true
    end)

    if not ok or result ~= true then
        return self:recoverKeepInventoryMove(state, ok and "transaction returned false" or result)
    end

    self:debugLog("keep-inventory move complete items=" .. tostring(#snapshot.items))
    return true
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
    if rules.isWindowLike(self.object, moveProps) then
        self:debugLog("execute blocked: window-like object")
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

    local containerRoute = rules.classifyContainerMove(self.object, moveProps, self.settings)
    if containerRoute == rules.CONTAINER_ROUTE_BLOCKED then
        self:debugLog("execute blocked: container route")
        return false
    end
    if containerRoute == rules.CONTAINER_ROUTE_KEEP then
        if moveProps.isMultiSprite then
            return self:executeKeepInventoryMultiMove(
                self.object,
                moveProps,
                sourceSquare,
                targetSquare
            )
        end
        return self:executeKeepInventoryMove(self.object, moveProps, sourceSquare, targetSquare)
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
