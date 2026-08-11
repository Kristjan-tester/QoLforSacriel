require "XpSystem/ISUI/ISCharacterInfoWindow"
require "XpSystem/ISUI/ISHealthPanel"
require "ISUI/ISPanel"
require "ISUI/ISButton"

local FitnessNutritionIndicator = {}
local FitnessNutritionPanel = ISPanel:derive("FitnessNutritionPanel")

local BALANCE_CELL_COUNT = 10
local BALANCE_CELL_WIDTH = 18
local BALANCE_CELL_HEIGHT = 18
local UI_BORDER_SPACING = 10
local STRENGTH_PROTEIN_NEAR_BONUS_MIN = 1
local MIN_CALORIES = -2200
local MAX_CALORIES = 3700
local FITNESS_PANEL_HEIGHT = 230

local installed = false
local originalCreateChildren = nil
local runtimeSettings = nil
local loggerRef = nil
local resizeFitnessHost = nil

local function getTextSafe(key, fallback)
    local value = getTextOrNull and getTextOrNull(key) or nil
    return value or fallback
end

local function logDebug(message)
    if runtimeSettings
        and runtimeSettings.get
        and runtimeSettings.get("QoLforSacriel_DebugLogs") == true
        and loggerRef
        and loggerRef.debug
    then
        loggerRef.debug("UIFixes.FitnessNutritionIndicator: " .. message)
    end
end

local function isEnabled()
    return runtimeSettings
        and runtimeSettings.isEnabled
        and runtimeSettings.isEnabled("QoLforSacriel_EnableUIFixes") == true
        and runtimeSettings.get("QoLforSacriel_UIFixes_EnableFitnessNutritionIndicator") == true
end

local function safeCall(target, methodName, ...)
    if not target then
        return false, nil
    end
    local method = target[methodName]
    if type(method) ~= "function" then
        return false, nil
    end
    return pcall(method, target, ...)
end

local function readFiniteNumber(target, methodName)
    local ok, value = safeCall(target, methodName)
    local numberValue = tonumber(value)
    if not ok or not numberValue or numberValue ~= numberValue or numberValue == math.huge or numberValue == -math.huge then
        return nil
    end
    return numberValue
end

local function readBoolean(target, methodName)
    local ok, value = safeCall(target, methodName)
    if not ok or type(value) ~= "boolean" then
        return nil
    end
    return value
end

local function hasTrait(playerObj, traitName)
    if not playerObj or not CharacterTrait or not CharacterTrait[traitName] then
        return false
    end
    local ok, value = safeCall(playerObj, "hasTrait", CharacterTrait[traitName])
    return ok and value == true
end

local function hasNutritionistTrait(playerObj)
    return hasTrait(playerObj, "NUTRITIONIST") or hasTrait(playerObj, "NUTRITIONIST2")
end

local function getFitnessXpBlockReason(playerObj)
    if not playerObj or not PerkFactory or not PerkFactory.Perks or not PerkFactory.Perks.Fitness then
        return nil
    end

    local fitnessLevelOk, fitnessLevelValue = safeCall(playerObj, "getPerkLevel", PerkFactory.Perks.Fitness)
    local fitnessLevel = fitnessLevelOk and tonumber(fitnessLevelValue) or nil
    if not fitnessLevel then
        return nil
    end
    fitnessLevel = math.floor(fitnessLevel)

    local emaciated = hasTrait(playerObj, "EMACIATED")
    local veryUnderweight = hasTrait(playerObj, "VERY_UNDERWEIGHT")
    local obese = hasTrait(playerObj, "OBESE")
    local underweight = hasTrait(playerObj, "UNDERWEIGHT")
    local overweight = hasTrait(playerObj, "OVERWEIGHT")

    if fitnessLevel >= 9 and (emaciated or veryUnderweight or obese or underweight or overweight) then
        return getTextSafe("UI_QoLforSacriel_FitnessXpBlocked", "Fitness XP blocked by current weight trait")
    end
    if fitnessLevel >= 6 and (emaciated or veryUnderweight or obese) then
        return getTextSafe("UI_QoLforSacriel_FitnessXpBlocked", "Fitness XP blocked by current weight trait")
    end
    return nil
end

local function getBalanceState(calories, lossThreshold, gainThreshold)
    if calories >= lossThreshold and calories <= gainThreshold then
        return nil, getTextSafe("UI_QoLforSacriel_FitnessBalance_Maintain", "Maintain")
    end

    if calories < lossThreshold then
        local range = lossThreshold - MIN_CALORIES
        if range <= 0 then
            return nil, getTextSafe("UI_QoLforSacriel_FitnessBalance_Maintain", "Maintain")
        end
        local fraction = (calories - MIN_CALORIES) / range
        local index = math.max(1, math.min(4, math.floor(fraction * 4) + 1))
        return index, getTextSafe("UI_QoLforSacriel_FitnessBalance_Loss", "Loss")
    end

    local range = MAX_CALORIES - gainThreshold
    if range <= 0 then
        return nil, getTextSafe("UI_QoLforSacriel_FitnessBalance_Maintain", "Maintain")
    end
    local fraction = (calories - gainThreshold) / range
    local index = 5 + math.max(1, math.min(5, math.floor(fraction * 5) + 1))
    return index, getTextSafe("UI_QoLforSacriel_FitnessBalance_Gain", "Gain")
end

local function getNutritionistTooltip(model)
    if not model.nutritionist then
        return nil
    end

    local toGain = math.max(0, model.gainThreshold - model.calories)
    local toLoss = math.max(0, model.calories - model.lossThreshold)
    return string.format(
        "%s: %.0f\n%s: %.0f\n%s: %.0f\n%s: %.0f\n%s: %.0f\n%s: %.0f\n%s: x%d",
        getTextSafe("UI_QoLforSacriel_FitnessTooltip_Calories", "Calories"), model.calories,
        getTextSafe("UI_QoLforSacriel_FitnessTooltip_Protein", "Protein"), model.proteins,
        getTextSafe("UI_QoLforSacriel_FitnessTooltip_Lipids", "Lipids"), model.lipids,
        getTextSafe("UI_QoLforSacriel_FitnessTooltip_GainGap", "Calories to gain"), toGain,
        getTextSafe("UI_QoLforSacriel_FitnessTooltip_LossGap", "Calories to loss"), toLoss,
        getTextSafe("UI_QoLforSacriel_FitnessTooltip_GainThreshold", "Gain threshold"), model.gainThreshold,
        getTextSafe("UI_QoLforSacriel_FitnessTooltip_GainMultiplier", "Gain multiplier"), model.gainMultiplier
    )
end

local function getNutritionModel(playerObj)
    local nutritionOk, nutrition = safeCall(playerObj, "getNutrition")
    if not nutritionOk or not nutrition then
        return { available = false }
    end

    local calories = readFiniteNumber(nutrition, "getCalories")
    local weight = readFiniteNumber(nutrition, "getWeight")
    local carbohydrates = readFiniteNumber(nutrition, "getCarbohydrates")
    local lipids = readFiniteNumber(nutrition, "getLipids")
    local proteins = readFiniteNumber(nutrition, "getProteins")
    if not calories or not weight or not carbohydrates or not lipids or not proteins then
        return { available = false }
    end

    local gainBase = 1000
    if weight < 90 and hasTrait(playerObj, "WEIGHT_GAIN") then
        gainBase = 700
    end
    if weight > 70 and hasTrait(playerObj, "WEIGHT_LOSS") then
        gainBase = 1800
    end

    local gainThreshold = gainBase + ((weight - 80) * 40)
    local lossThreshold = math.min((weight - 70) * 30, 0)
    local gainMultiplier = 1
    if carbohydrates > 700 or lipids > 700 then
        gainMultiplier = 3
    elseif carbohydrates > 400 or lipids > 400 then
        gainMultiplier = 2
    end

    local strengthColor = "red"
    local strengthReason = getTextSafe("UI_QoLforSacriel_FitnessStrength_Red", "Protein is not near the Strength XP bonus range")
    if proteins >= 300 then
        strengthColor = "purple"
        strengthReason = getTextSafe("UI_QoLforSacriel_FitnessStrength_Purple", "Protein is above the Strength XP bonus range")
    elseif proteins > 50 then
        strengthColor = "green"
        strengthReason = getTextSafe("UI_QoLforSacriel_FitnessStrength_Green", "Strength XP protein bonus active (+50%)")
    elseif proteins >= STRENGTH_PROTEIN_NEAR_BONUS_MIN then
        strengthColor = "yellow"
        strengthReason = getTextSafe("UI_QoLforSacriel_FitnessStrength_Yellow", "Protein is near the Strength XP bonus range")
    elseif proteins < -300 then
        strengthReason = getTextSafe("UI_QoLforSacriel_FitnessStrength_Penalty", "Strength XP penalty active (-30%)")
    elseif proteins >= -300 then
        strengthColor = "grey"
        strengthReason = getTextSafe("UI_QoLforSacriel_FitnessStrength_Grey", "Protein has no Strength XP modifier")
    end

    local fitnessXpBlockReason = getFitnessXpBlockReason(playerObj)
    local fitnessColor = "green"
    local fitnessReason = getTextSafe("UI_QoLforSacriel_FitnessEndurance_Green", "Fitness XP is allowed at current weight")
    if fitnessXpBlockReason then
        fitnessColor = "red"
        fitnessReason = fitnessXpBlockReason
    end

    local balanceIndex, balanceLabel = getBalanceState(calories, lossThreshold, gainThreshold)
    if balanceIndex and balanceIndex > 5 and gainMultiplier > 1 then
        if gainMultiplier == 3 then
            balanceLabel = getTextSafe("UI_QoLforSacriel_FitnessBalance_GainTriple", "Gain (3x carbohydrates/lipids)")
        else
            balanceLabel = getTextSafe("UI_QoLforSacriel_FitnessBalance_GainDouble", "Gain (2x carbohydrates/lipids)")
        end
    end
    return {
        available = true,
        balanceIndex = balanceIndex,
        balanceLabel = balanceLabel,
        calories = calories,
        carbohydrates = carbohydrates,
        gainMultiplier = gainMultiplier,
        gainThreshold = gainThreshold,
        lossThreshold = lossThreshold,
        nutritionist = hasNutritionistTrait(playerObj),
        proteins = proteins,
        lipids = lipids,
        strengthColor = strengthColor,
        strengthReason = strengthReason,
        fitnessColor = fitnessColor,
        fitnessReason = fitnessReason,
    }
end

local COLORS = {
    red = { r = 0.79, g = 0.21, b = 0.20 },
    yellow = { r = 0.91, g = 0.73, b = 0.18 },
    green = { r = 0.24, g = 0.67, b = 0.34 },
    purple = { r = 0.60, g = 0.33, b = 0.74 },
    grey = { r = 0.48, g = 0.50, b = 0.52 },
    neutral = { r = 0, g = 0, b = 0 },
    cellBorder = { r = 0.48, g = 0.50, b = 0.52 },
}

function FitnessNutritionPanel:refreshModel()
    self.model = getNutritionModel(self.playerObj)
    self.tooltip = self.model.available and getNutritionistTooltip(self.model) or nil
end

function FitnessNutritionPanel:prerender()
    ISPanel.prerender(self)
    if resizeFitnessHost and self.parent and self.parent.parent then
        resizeFitnessHost(self.parent.parent, self)
    end
    self:refreshModel()
end

function FitnessNutritionPanel:drawTrafficLight(x, y, color)
    local swatch = COLORS[color] or COLORS.grey
    self:drawRect(x, y, 14, 14, 1, swatch.r, swatch.g, swatch.b)
    self:drawRectBorder(x, y, 14, 14, 1, 0.1, 0.1, 0.1)
end

function FitnessNutritionPanel:render()
    local model = self.model or { available = false }
    local x = UI_BORDER_SPACING
    local y = UI_BORDER_SPACING
    local labelColor = { r = 0.9, g = 0.9, b = 0.9 }

    self:drawText(getTextSafe("UI_QoLforSacriel_FitnessBalance", "Calorie Balance"), x, y, labelColor.r, labelColor.g, labelColor.b, 1, UIFont.Small)
    y = y + 20
    for index = 1, BALANCE_CELL_COUNT do
        local color = COLORS.neutral
        if model.available and not model.balanceIndex and (index == 5 or index == 6) then
            color = COLORS.grey
        elseif model.available and model.balanceIndex == index then
            color = index <= 4 and COLORS.red or COLORS.green
        end
        local cellX = x + ((index - 1) * (BALANCE_CELL_WIDTH + 2))
        self:drawRect(cellX, y, BALANCE_CELL_WIDTH, BALANCE_CELL_HEIGHT, 1, color.r, color.g, color.b)
        self:drawRectBorder(cellX, y, BALANCE_CELL_WIDTH, BALANCE_CELL_HEIGHT, 1, COLORS.cellBorder.r, COLORS.cellBorder.g, COLORS.cellBorder.b)
        if model.available and model.balanceIndex == index and index > 5 and model.gainMultiplier > 1 then
            local marker = model.gainMultiplier == 3 and "^^" or "^"
            self:drawTextCentre(marker, cellX + (BALANCE_CELL_WIDTH / 2), y + 1, 1, 1, 1, 1, UIFont.Small)
        end
    end
    self:drawLine2(x + (4 * (BALANCE_CELL_WIDTH + 2)) - 1, y - 2, x + (4 * (BALANCE_CELL_WIDTH + 2)) - 1, y + BALANCE_CELL_HEIGHT + 2, 1, 0.9, 0.9, 0.9)
    y = y + BALANCE_CELL_HEIGHT + 6
    self:drawText(model.available and model.balanceLabel or getTextSafe("UI_QoLforSacriel_FitnessUnavailable", "Nutrition unavailable"), x, y, labelColor.r, labelColor.g, labelColor.b, 1, UIFont.Small)

    y = y + 30
    self:drawText(getTextSafe("UI_QoLforSacriel_FitnessStrength", "Strength Training"), x, y, labelColor.r, labelColor.g, labelColor.b, 1, UIFont.Small)
    y = y + 18
    self:drawTrafficLight(x, y, model.available and model.strengthColor or "grey")
    self:drawText(model.available and model.strengthReason or getTextSafe("UI_QoLforSacriel_FitnessUnavailable", "Nutrition unavailable"), x + 22, y, labelColor.r, labelColor.g, labelColor.b, 1, UIFont.Small)

    y = y + 32
    self:drawText(getTextSafe("UI_QoLforSacriel_FitnessEndurance", "Fitness Endurance"), x, y, labelColor.r, labelColor.g, labelColor.b, 1, UIFont.Small)
    y = y + 18
    self:drawTrafficLight(x, y, model.available and model.fitnessColor or "grey")
    self:drawText(model.available and model.fitnessReason or getTextSafe("UI_QoLforSacriel_FitnessUnavailable", "Nutrition unavailable"), x + 22, y, labelColor.r, labelColor.g, labelColor.b, 1, UIFont.Small)
end

function FitnessNutritionPanel:new(playerObj, x, y, width, height)
    local panel = ISPanel.new(self, x, y, width, height)
    setmetatable(panel, self)
    self.__index = self
    panel.playerObj = playerObj
    panel.character = playerObj
    panel.playerNum = playerObj:getPlayerNum()
    panel.backgroundColor = { r = 0.08, g = 0.10, b = 0.11, a = 0.85 }
    return panel
end

resizeFitnessHost = function(window, view)
    local tabPanel = window and window.panel or nil
    if not tabPanel or not view then
        return
    end

    local targetPanelHeight = tabPanel.tabHeight + view:getHeight()
    local targetWindowHeight = window:titleBarHeight() + targetPanelHeight + window:resizeWidgetHeight()
    local needsPanelResize = tabPanel:getHeight() < targetPanelHeight
    local needsWindowResize = window:getHeight() < targetWindowHeight
    if not needsPanelResize and not needsWindowResize then
        return
    end

    if needsPanelResize then
        tabPanel:setHeight(targetPanelHeight)
    end
    if needsWindowResize then
        window:setHeight(math.max(window:getHeight(), targetWindowHeight))
    end
    tabPanel:recalcSize()
    window:recalcSize()
end

local function addFitnessView(window)
    if not window or not window.panel or window.fitnessNutritionView then
        return
    end
    local playerObj = getSpecificPlayer and getSpecificPlayer(window.playerNum) or nil
    if not playerObj then
        return
    end

    local view = FitnessNutritionPanel:new(playerObj, 0, 8, window.panel:getWidth(), FITNESS_PANEL_HEIGHT)
    view:initialise()
    view.anchorLeft = true
    view.anchorRight = false
    view.anchorTop = true
    view.anchorBottom = false
    window.panel:addView(getTextSafe("UI_QoLforSacriel_FitnessTab", "Fitness"), view)

    local button = ISButton:new(UI_BORDER_SPACING, 184, 100, 22, getTextSafe("ContextMenu_Fitness", "Fitness"), view, ISNewHealthPanel.onClick)
    button.internal = "FITNESS"
    button:initialise()
    button:instantiate()
    view:addChild(button)
    view.exerciseButton = button
    window.fitnessNutritionView = view

    if not window.fitnessResizeHooked then
        local originalActivateView = window.panel.activateView
        window.panel.activateView = function(tabPanel, viewName)
            local activated = originalActivateView(tabPanel, viewName)
            if activated and tabPanel:getActiveView() == window.fitnessNutritionView then
                resizeFitnessHost(window, window.fitnessNutritionView)
            end
            return activated
        end
        window.fitnessResizeHooked = true
    end
    logDebug("Fitness tab added")
end

local function removeFitnessView(window)
    if not window or not window.panel or not window.fitnessNutritionView then
        return
    end
    window.panel:removeView(window.fitnessNutritionView)
    window.fitnessNutritionView = nil
    logDebug("Fitness tab removed")
end

function FitnessNutritionIndicator.init(settings, logger)
    if installed then
        return
    end
    if not ISCharacterInfoWindow or not ISCharacterInfoWindow.createChildren then
        if logger and logger.warn then
            logger.warn("UIFixes.FitnessNutritionIndicator could not patch Character Info")
        end
        return
    end

    runtimeSettings = settings
    loggerRef = logger
    originalCreateChildren = ISCharacterInfoWindow.createChildren
    ISCharacterInfoWindow.createChildren = function(self)
        originalCreateChildren(self)
        if isEnabled() then
            addFitnessView(self)
        end
    end

    if Events and Events.OnPlayerUpdate then
        Events.OnPlayerUpdate.Add(function(playerObj)
            local window = getPlayerInfoPanel and getPlayerInfoPanel(playerObj:getPlayerNum()) or nil
            if window then
                if isEnabled() then
                    addFitnessView(window)
                else
                    removeFitnessView(window)
                end
            end
        end)
    end

    installed = true
end

return FitnessNutritionIndicator