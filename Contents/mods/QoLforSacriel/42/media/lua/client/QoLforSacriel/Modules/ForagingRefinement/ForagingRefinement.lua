-- ff-assisted
local ForagingRefinement = {}

require "Foraging/ISSearchManager"
require "Foraging/ISSearchWindow"
require "Foraging/ISBaseIcon"
require "ISUI/ISComboBox"

local coreModOptions = require "QoLforSacriel/CoreModOptions"

local MODULE_SETTING = "QoLforSacriel_EnableForagingRefinement"
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
local originalRenderPinIcon = nil
local modeByPlayer = {}

local function isModuleEnabled()
    return settingsRef
        and settingsRef.isEnabled()
        and settingsRef.isEnabled(MODULE_SETTING) == true
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

function ForagingRefinement.init(settings, logger)
    if installed then
        return
    end

    settingsRef = settings
    loggerRef = logger

    if not patchSearchWindow() or not patchWorldItemFilter() or not patchPhysicalPinRenderer() then
        if loggerRef and loggerRef.error then
            loggerRef.error("ForagingRefinement unavailable: expected vanilla Search Mode APIs are missing")
        end
        return
    end

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