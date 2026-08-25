-- ff-assisted
local FurnitureNudgeContext = {}

local installed = false
local rules = require "QoLforSacriel/Modules/FurnitureNudge/FurnitureNudgeRules"
local actionModule = require "QoLforSacriel/Modules/FurnitureNudge/FurnitureNudgeAction"

if not _G.QoLforSacriel_Logger then
    _G.QoLforSacriel_Logger = nil
end

local function getLabel(key, fallback)
    local text = getTextOrNull and getTextOrNull(key)
    if text and text ~= "" then
        return text
    end
    return fallback
end

local function addUnavailableOption(context, tooltipKey, tooltipFallback)
    local option = context:addOption(getLabel("UI_QoLforSacriel_FurnitureNudge", "Nudge"))
    option.notAvailable = true
    option.toolTip = ISToolTip:new()
    option.toolTip:initialise()
    option.toolTip:setVisible(false)
    option.toolTip.description = getLabel(tooltipKey or "UI_QoLforSacriel_FurnitureNudgeUnavailable", tooltipFallback or "No valid nudge directions.")
end

local function onSelectDirection(playerObj, selected, settings, logger)
    if not selected or not selected.object or not selected.direction then
        return
    end
    ISTimedActionQueue.add(actionModule:new(playerObj, selected.object, selected.direction, settings, logger))
end

local function getDisableReasonTooltip(candidate)
    if not candidate or not candidate.disableReason then
        return "UI_QoLforSacriel_FurnitureNudgeUnavailable", "No valid nudge directions."
    end
    if candidate.disableReason == rules.CANDIDATE_REASON_MULTI_TILE then
        return "UI_QoLforSacriel_FurnitureNudgeMultiTileDisabled", "multi-tile furniture cannot be nudged"
    end
    if candidate.disableReason == rules.CANDIDATE_REASON_HAS_CONTENTS then
        local containerReason = tostring(candidate.containerReason or "")
        if containerReason == "unexplored" then
            return "UI_QoLforSacriel_FurnitureNudgeUnexplored", "search this container before nudging"
        end
        if containerReason == "option_disabled" then
            return "UI_QoLforSacriel_FurnitureNudgeKeepInventoryDisabled", "enable Experimental: Keep Furniture Inventory or empty this furniture"
        end
        if string.sub(containerReason, 1, 16) == "appliance_state[" then
            return "UI_QoLforSacriel_FurnitureNudgeApplianceState", "turn off the appliance and wait for residual heat to clear; timed ovens must also have no timer"
        end
        if containerReason == "multiplayer" then
            return "UI_QoLforSacriel_FurnitureNudgeSinglePlayerOnly", "keeping furniture inventory is available in single-player only"
        end
        if containerReason == "missing_object" then
            return "UI_QoLforSacriel_FurnitureNudgeCannotVerify", "the furniture state could not be verified"
        end
        if containerReason == "incomplete_members"
        or containerReason == "force_single_item_grid"
        then
            return "UI_QoLforSacriel_FurnitureNudgeCompoundUnsupported", "this compound furniture cannot safely keep its inventory while nudging"
        end
        if containerReason == "fluid_container" then
            return "UI_QoLforSacriel_FurnitureNudgeFluidAndItemsUnsupported", "furniture combining fluid and item storage cannot be nudged safely"
        end
        if containerReason == "unsupported_shape" then
            return "UI_QoLforSacriel_FurnitureNudgeUnsupportedType", "this furniture type cannot keep its inventory while nudging"
        end
        if containerReason == "iso_type"
        or containerReason == "specialized_class"
        or containerReason == "sprite_properties"
        or containerReason == "container_type"
        or string.sub(containerReason, 1, 10) == "component["
        or string.sub(containerReason, 1, 9) == "mod_data["
        then
            return "UI_QoLforSacriel_FurnitureNudgeStatefulUnsupported", "this furniture has state that cannot be preserved safely"
        end
        return "UI_QoLforSacriel_FurnitureNudgeHasContents", "empty furniture before nudging"
    end
    if candidate.disableReason == rules.CANDIDATE_REASON_PARALLEL_WALL then
        return "UI_QoLforSacriel_FurnitureNudgeParallelWallBlocked", "cannot nudge parallel to nearby wall"
    end
        if candidate.disableReason == rules.CANDIDATE_REASON_REQUIRES_TOOL then
            return "UI_QoLforSacriel_FurnitureNudgeRequiresTool", "cannot nudge furniture that requires tools"
        end
        if candidate.disableReason == rules.CANDIDATE_REASON_TOO_TIRED then
            return "UI_QoLforSacriel_FurnitureNudgeTooTired", "too tired to nudge"
        end
    return "UI_QoLforSacriel_FurnitureNudgeUnavailable", "No valid nudge directions."
end

local function getRootLabel(candidate)
    if candidate and candidate.displayName and candidate.displayName ~= "" then
        local key = "UI_QoLforSacriel_FurnitureNudgeNamed"
        local label = getText and getText(key, candidate.displayName)
        if label and label ~= "" and label ~= key then
            return label
        end
        return "Nudge - " .. candidate.displayName
    end
    return getLabel("UI_QoLforSacriel_FurnitureNudge", "Nudge")
end

local function logDisableReason(settings, logger, reason, candidate)
    if not logger or not settings or settings.get("QoLforSacriel_DebugLogs") ~= true then
        return
    end

    local itemName = candidate and candidate.displayName or nil
    if (not itemName or itemName == "") and candidate and candidate.moveProps and candidate.moveProps.name then
        itemName = candidate.moveProps.name
    end
    if not itemName or itemName == "" then
        itemName = "unknown"
    end

    local details = ""
    if candidate and candidate.object and candidate.object.getSquare then
        local square = candidate.object:getSquare()
        if square then
            details = " @(" .. tostring(square:getX()) .. "," .. tostring(square:getY()) .. "," .. tostring(square:getZ()) .. ")"
        end
    end

    logger.debug("FurnitureNudge disabled: " .. tostring(reason) .. " item=" .. tostring(itemName) .. details)
end

local function addDisabledNamedOption(context, label, tooltipKey, tooltipFallback)
    local option = context:addOption(label)
    option.notAvailable = true
    option.toolTip = ISToolTip:new()
    option.toolTip:initialise()
    option.toolTip:setVisible(false)
    option.toolTip.description = getLabel(tooltipKey, tooltipFallback)
end

local function addDirectionMenuForCandidate(menuContext, candidate, playerObj, settings, logger, label)
    if candidate.isNudgeDisabled == true then
        local key, fallback = getDisableReasonTooltip(candidate)
        logDisableReason(settings, logger, candidate.disableReason or "disabled", candidate)
        addDisabledNamedOption(menuContext, label, key, fallback)
        return
    end

    if rules.isTooTiredForCandidate(playerObj, candidate, settings, true) then
        candidate.disableReason = rules.CANDIDATE_REASON_TOO_TIRED
        logDisableReason(settings, logger, candidate.disableReason, candidate)
        addDisabledNamedOption(menuContext, label, "UI_QoLforSacriel_FurnitureNudgeTooTired", "too tired to nudge")
        return
    end

    if not rules.isPlayerCloseEnough(playerObj, candidate) then
        logDisableReason(settings, logger, "not_close_enough", candidate)
        addDisabledNamedOption(menuContext, label, "UI_QoLforSacriel_FurnitureNudgeNotCloseEnough", "not close enough")
        return
    end

    local validDirections = rules.getValidDirections(playerObj, candidate, settings)
    if #validDirections == 0 then
        logDisableReason(settings, logger, candidate.disableReason or "no_valid_directions", candidate)
        local key, fallback = getDisableReasonTooltip(candidate)
        addDisabledNamedOption(menuContext, label, key, fallback)
        return
    end

    local candidateOption = menuContext:addOption(label)
    local directionsSubMenu = menuContext:getNew(menuContext)
    menuContext:addSubMenu(candidateOption, directionsSubMenu)

    for _, direction in ipairs(validDirections) do
        local key = "UI_QoLforSacriel_FurnitureNudge" .. direction.label
        local directionLabel = getLabel(key, direction.label)
        directionsSubMenu:addOption(directionLabel, playerObj, function(pl)
            onSelectDirection(pl, {
                object = candidate.object,
                direction = direction
            }, settings, logger)
        end)
    end
end

local function installMenuHook(settings, logger)
    Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldobjects, test)
        if test then
            return
        end
        if settings.isEnabled("QoLforSacriel_EnableFurnitureNudge") ~= true then
            return
        end
        local playerObj = getSpecificPlayer(playerIndex)
        if not playerObj or playerObj:isDead() or playerObj:getVehicle() then
            return
        end

        local candidates = rules.resolveCandidates(worldobjects, settings, logger)
        if #candidates == 0 then
            return
        end

        if logger and settings.get("QoLforSacriel_DebugLogs") == true then
            logger.debug("FurnitureNudge context candidates: " .. tostring(#candidates))
        end

        if #candidates == 1 then
            local candidate = candidates[1]
            if candidate.isNudgeDisabled == true then
                local key, fallback = getDisableReasonTooltip(candidate)
                logDisableReason(settings, logger, candidate.disableReason or "disabled", candidate)
                addUnavailableOption(context, key, fallback)
                return
            end

            if rules.isTooTiredForCandidate(playerObj, candidate, settings, true) then
                candidate.disableReason = rules.CANDIDATE_REASON_TOO_TIRED
                logDisableReason(settings, logger, candidate.disableReason, candidate)
                addUnavailableOption(context, "UI_QoLforSacriel_FurnitureNudgeTooTired", "too tired to nudge")
                return
            end

            if not rules.isPlayerCloseEnough(playerObj, candidate) then
                logDisableReason(settings, logger, "not_close_enough", candidate)
                addUnavailableOption(context, "UI_QoLforSacriel_FurnitureNudgeNotCloseEnough", "not close enough")
                return
            end

            local validDirections = rules.getValidDirections(playerObj, candidate, settings)
            if #validDirections == 0 then
                logDisableReason(settings, logger, candidate.disableReason or "no_valid_directions", candidate)
                local key, fallback = getDisableReasonTooltip(candidate)
                addUnavailableOption(context, key, fallback)
                return
            end

            local root = context:addOption(getRootLabel(candidate))
            local subMenu = context:getNew(context)
            context:addSubMenu(root, subMenu)

            for _, direction in ipairs(validDirections) do
                local key = "UI_QoLforSacriel_FurnitureNudge" .. direction.label
                local label = getLabel(key, direction.label)
                subMenu:addOption(label, playerObj, function(pl)
                    onSelectDirection(pl, {
                        object = candidate.object,
                        direction = direction
                    }, settings, logger)
                end)
            end
            return
        end

        local root = context:addOption(getLabel("UI_QoLforSacriel_FurnitureNudge", "Nudge"))
        local subMenu = context:getNew(context)
        context:addSubMenu(root, subMenu)

        local nameCounts = {}
        for _, candidate in ipairs(candidates) do
            local baseLabel = candidate.displayName or getLabel("UI_QoLforSacriel_FurnitureNudgeObjectFallback", "Furniture")
            local count = (nameCounts[baseLabel] or 0) + 1
            nameCounts[baseLabel] = count
            local itemLabel = baseLabel
            if count > 1 then
                itemLabel = baseLabel .. " #" .. tostring(count)
            end
            addDirectionMenuForCandidate(subMenu, candidate, playerObj, settings, logger, itemLabel)
        end
    end)
end

function FurnitureNudgeContext.install(settings, logger)
    if installed then
        return
    end
    _G.QoLforSacriel_Logger = logger
    installMenuHook(settings, logger)
    installed = true
end

return FurnitureNudgeContext