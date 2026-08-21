-- ff-assisted
local ForagingRefinement = {}

require "Foraging/ISSearchManager"
require "Foraging/ISSearchWindow"
require "Foraging/ISZoneDisplay"
require "Foraging/ISBaseIcon"
require "ISUI/ISComboBox"

local coreModOptions = require "QoLforSacriel/CoreModOptions"

local MODULE_SETTING = "QoLforSacriel_EnableForagingRefinement"
local VISION_TOOLTIP_SETTING = "QoLforSacriel_ForagingRefinement_EnableVisionTooltip"
local PIN_COLOR_SETTING = "QoLforSacriel_ForagingRefinement_PinColorPreset"
local MODE_NO = 1
local MODE_HIDE = 2
local MODE_YELLOW = 3
local UI_BORDER_SPACING = 10

local PIN_COLOR_PRESETS = {
    { r = 1.00, g = 0.90, b = 0.10 },
    { r = 1.00, g = 0.50, b = 0.05 },
    { r = 0.10, g = 0.90, b = 1.00 },
    { r = 0.20, g = 1.00, b = 0.30 },
    { r = 1.00, g = 0.20, b = 0.85 },
}

local installed = false
local settingsRef = nil
local loggerRef = nil
local originalSearchWindowInitialise = nil
local originalWorldItemTest = nil
local originalGetVisionTooltipText = nil
local originalRenderPinIcon = nil
local modeByPlayer = {}
local visionTooltipFailureLogged = false

local function isModuleEnabled()
    return settingsRef
        and settingsRef.isEnabled()
        and settingsRef.isEnabled(MODULE_SETTING) == true
end

local function isVisionTooltipEnabled()
    return isModuleEnabled()
        and settingsRef.isEnabled(VISION_TOOLTIP_SETTING) == true
end

local function clearWorldItemIcons(manager)
    if not manager then
        return
    end

    local icons = {}
    for _, icon in pairs(manager.worldObjectIcons or {}) do
        table.insert(icons, icon)
    end

    for _, icon in ipairs(icons) do
        manager:removeIcon(icon)
    end

    if manager.worldIconStack then
        table.wipe(manager.worldIconStack)
    end
end

local function getPlayerMode(playerNum)
    local mode = tonumber(modeByPlayer[playerNum]) or MODE_NO
    if mode < MODE_NO or mode > MODE_YELLOW then
        return MODE_NO
    end
    return mode
end

local function getPinColorPreset()
    local preset = settingsRef and settingsRef.get and tonumber(settingsRef.get(PIN_COLOR_SETTING)) or MODE_NO
    preset = math.floor(preset or MODE_NO)
    return PIN_COLOR_PRESETS[preset] or PIN_COLOR_PRESETS[MODE_NO]
end

local function logVisionTooltipFailure(reason)
    if visionTooltipFailureLogged then
        return
    end
    visionTooltipFailureLogged = true
    if loggerRef and loggerRef.debug then
        loggerRef.debug("ForagingRefinement vision tooltip unavailable: " .. tostring(reason))
    end
end

local function getVisionTooltipColor(useGoodHighlight)
    local color = useGoodHighlight
        and getCore():getGoodHighlitedColor()
        or getCore():getBadHighlitedColor()
    return " <RGB:" .. color:getR() .. "," .. color:getG() .. "," .. color:getB() .. "> "
end

local function appendVisionTooltipHeader(text)
    return text
        .. " <LINE> "
        .. " <RGB:1,1,1> "
        .. getText("UI_QoLforSacriel_ForagingRefinement_VisionHeader")
        .. " <LINE> "
end

local function appendSkillBaseRow(text, perkLevel)
    local label = getText("UI_QoLforSacriel_ForagingRefinement_VisionSkill")
        .. " "
        .. tostring(math.floor(perkLevel))
        .. ": "
        .. getText("UI_QoLforSacriel_ForagingRefinement_VisionBase")
        .. " "
        .. string.format("%.2f", 3 + 0.7 * perkLevel)
    return text .. " <RGB:1,1,1> " .. label .. " <LINE> "
end

local function getBodyConditionContributor(character)
    local stats = character and character.getStats and character:getStats()
    if not stats or not CharacterStat then
        return nil
    end

    local contributors = {
        { stat = CharacterStat.PAIN, scale = 100, label = "UI_QoLforSacriel_ForagingRefinement_VisionBodyPain" },
        { stat = CharacterStat.SICKNESS, scale = 1, label = "UI_QoLforSacriel_ForagingRefinement_VisionBodySickness" },
        { stat = CharacterStat.FOOD_SICKNESS, scale = 100, label = "UI_QoLforSacriel_ForagingRefinement_VisionBodyFoodSickness" },
        { stat = CharacterStat.INTOXICATION, scale = 100, label = "UI_QoLforSacriel_ForagingRefinement_VisionBodyIntoxication" },
    }
    local highestValue = 0
    local highestLabel = nil

    for _, contributor in ipairs(contributors) do
        local value = stats:get(contributor.stat) / contributor.scale
        if value > highestValue then
            highestValue = value
            highestLabel = contributor.label
        end
    end

    return highestLabel and getText(highestLabel) or nil
end

local function appendModifierRow(text, translationKey, multiplier, contributor)
    local percent = (multiplier - 1) * 100
    if percent == 0 then
        return text
    end

    local color = getVisionTooltipColor(multiplier > 1)
    return text
        .. " <RGB:1,1,1> "
        .. getText(translationKey)
        .. ": <SPACE> "
        .. color
        .. string.format("%+.2f", percent)
        .. " \%"
        .. (contributor and " (" .. contributor .. ")" or "")
        .. " <LINE> "
end

local function updateWindowLayout(window)
    local dropdown = window.qolForagingRefinementDropdown
    if not dropdown or not window.searchFocus or not window.toggleSearchMode then
        return
    end

    local enabled = isModuleEnabled()
    dropdown:setVisible(enabled)
    dropdown:setEnabled(enabled)

    if enabled then
        dropdown:setY(window.searchFocus:getBottom() + UI_BORDER_SPACING)
        window.toggleSearchMode:setY(dropdown:getBottom() + UI_BORDER_SPACING)
    else
        window.toggleSearchMode:setY(window.searchFocus:getBottom() + UI_BORDER_SPACING)
    end

    window:setHeight(window.toggleSearchMode:getBottom() + UI_BORDER_SPACING + 1)
end

local function onModeChanged(window, dropdown)
    if not window or not dropdown then
        return
    end
    local mode = tonumber(dropdown.selected) or MODE_NO
    modeByPlayer[window.player] = mode
    if mode == MODE_HIDE then
        clearWorldItemIcons(window.manager)
    end
end

local function ensureDropdown(window)
    if not window or not window.searchFocus or not window.toggleSearchMode then
        return
    end

    local legacyCheckbox = window.qolForagingRefinementCheckbox
    if legacyCheckbox then
        window:removeChild(legacyCheckbox)
        legacyCheckbox:setVisible(false)
        window.qolForagingRefinementCheckbox = nil
    end

    local dropdown = window.qolForagingRefinementDropdown
    if not dropdown then
        dropdown = ISComboBox:new(
            UI_BORDER_SPACING + 1,
            window.searchFocus:getBottom() + UI_BORDER_SPACING,
            window.width - (UI_BORDER_SPACING + 1) * 2,
            window.toggleSearchMode:getHeight(),
            window,
            onModeChanged
        )
        dropdown:initialise()
        dropdown:addOption(getTextOrNull("UI_QoLforSacriel_ForagingRefinement_ModeNo") or "No")
        dropdown:addOption(getTextOrNull("UI_QoLforSacriel_ForagingRefinement_ModeHide") or "Hide")
        dropdown:addOption(getTextOrNull("UI_QoLforSacriel_ForagingRefinement_ModeYellow") or "Yellow")
        window:addChild(dropdown)
        window.qolForagingRefinementDropdown = dropdown
    end

    dropdown.selected = getPlayerMode(window.player)
    updateWindowLayout(window)
end

local function refreshSearchWindows()
    if not ISSearchWindow or not ISSearchWindow.players then
        return
    end

    for _, window in pairs(ISSearchWindow.players) do
        ensureDropdown(window)
    end
end

local function patchSearchWindow()
    if not ISSearchWindow or not ISSearchWindow.initialise then
        return false
    end

    originalSearchWindowInitialise = ISSearchWindow.initialise
    ISSearchWindow.initialise = function(window)
        originalSearchWindowInitialise(window)
        ensureDropdown(window)
    end
    return true
end

local function patchWorldItemFilter()
    if not ISSearchManager or not ISSearchManager.worldItemTest then
        return false
    end

    originalWorldItemTest = ISSearchManager.worldItemTest
    ISSearchManager.worldItemTest = function(manager, itemObj)
        if isModuleEnabled() and getPlayerMode(manager.player) == MODE_HIDE then
            return false
        end
        return originalWorldItemTest(manager, itemObj)
    end
    return true
end

local function patchVisionTooltip()
    if not ISZoneDisplay or not ISZoneDisplay.getVisionTooltipText then
        return false
    end

    originalGetVisionTooltipText = ISZoneDisplay.getVisionTooltipText
    ISZoneDisplay.getVisionTooltipText = function(display)
        local text = originalGetVisionTooltipText(display)
        if not isVisionTooltipEnabled() then
            return text
        end

        local manager = display and display.manager
        local modifiers = manager and manager.modifiers
        if type(text) ~= "string" or type(manager) ~= "table" or type(modifiers) ~= "table" then
            logVisionTooltipFailure("manager or modifiers are unavailable")
            return text
        end

        local perkLevel = manager.perkLevel
        local panicPenalty = modifiers.panicPenalty
        local bodyPenalty = modifiers.bodyPenalty
        local exhaustionPenalty = modifiers.exhaustionPenalty
        if type(perkLevel) ~= "number"
            or type(panicPenalty) ~= "number"
            or type(bodyPenalty) ~= "number"
            or type(exhaustionPenalty) ~= "number" then
            logVisionTooltipFailure("expected numeric Foraging modifiers")
            return text
        end

        text = appendVisionTooltipHeader(text)
        text = appendSkillBaseRow(text, perkLevel)
        text = appendModifierRow(text, "UI_QoLforSacriel_ForagingRefinement_VisionPanicStress", panicPenalty)
        text = appendModifierRow(
            text,
            "UI_QoLforSacriel_ForagingRefinement_VisionBodyCondition",
            bodyPenalty,
            getBodyConditionContributor(display.character)
        )
        return appendModifierRow(text, "UI_QoLforSacriel_ForagingRefinement_VisionEnduranceFatigue", exhaustionPenalty)
    end
    return true
end

local function patchPhysicalPinRenderer()
    if not ISBaseIcon or not ISBaseIcon.renderPinIcon then
        return false
    end

    originalRenderPinIcon = ISBaseIcon.renderPinIcon
    ISBaseIcon.renderPinIcon = function(icon)
        local manager = icon and icon.manager
        local shouldTint = isModuleEnabled()
            and manager ~= nil
            and getPlayerMode(manager.player) == MODE_YELLOW
            and icon.iconClass == "worldObject"
            and type(icon.textureColor) == "table"
        if not shouldTint then
            return originalRenderPinIcon(icon)
        end

        local color = icon.textureColor
        local originalRed, originalGreen, originalBlue = color.r, color.g, color.b
        local tint = getPinColorPreset()
        color.r, color.g, color.b = tint.r, tint.g, tint.b
        local ok, result = pcall(originalRenderPinIcon, icon)
        color.r, color.g, color.b = originalRed, originalGreen, originalBlue
        if not ok then
            if loggerRef and loggerRef.error then
                loggerRef.error("ForagingRefinement yellow-pin render failed: " .. tostring(result))
            end
            return nil
        end
        return result
    end
    return true
end

local function hasRequiredVanillaApis()
    return ISSearchWindow
        and ISSearchWindow.initialise
        and ISSearchManager
        and ISSearchManager.worldItemTest
        and ISZoneDisplay
        and ISZoneDisplay.getVisionTooltipText
        and ISBaseIcon
        and ISBaseIcon.renderPinIcon
end

function ForagingRefinement.init(settings, logger)
    if installed then
        return
    end

    settingsRef = settings
    loggerRef = logger

    if not hasRequiredVanillaApis() then
        if loggerRef and loggerRef.error then
            loggerRef.error("ForagingRefinement unavailable: expected vanilla Search Mode APIs are missing")
        end
        return
    end

    patchSearchWindow()
    patchWorldItemFilter()
    patchVisionTooltip()
    patchPhysicalPinRenderer()

    coreModOptions.addApplyListener(function()
        refreshSearchWindows()
    end)

    refreshSearchWindows()
    installed = true

    if loggerRef and loggerRef.info then
        loggerRef.info("ForagingRefinement installed")
    end
end

return ForagingRefinement