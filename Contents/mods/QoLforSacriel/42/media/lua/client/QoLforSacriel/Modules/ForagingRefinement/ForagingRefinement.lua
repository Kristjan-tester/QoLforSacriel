local ForagingRefinement = {}

require "Foraging/ISSearchManager"
require "Foraging/ISSearchWindow"
require "ISUI/ISTickBox"

local coreModOptions = require "QoLforSacriel/CoreModOptions"

local MODULE_SETTING = "QoLforSacriel_EnableForagingRefinement"
local CHECKBOX_LABEL = "Only on foraging items"
local UI_BORDER_SPACING = 10

local installed = false
local settingsRef = nil
local loggerRef = nil
local originalSearchWindowInitialise = nil
local originalWorldItemTest = nil
local onlyForagingByPlayer = {}

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

local function getOnlyForaging(window)
    return onlyForagingByPlayer[window.player] == true
end

local function getCheckboxLabel()
    return getTextOrNull("UI_QoLforSacriel_ForagingRefinement_OnlyForagingItems") or CHECKBOX_LABEL
end

local function updateWindowLayout(window)
    local checkbox = window.qolForagingRefinementCheckbox
    if not checkbox or not window.searchFocus or not window.toggleSearchMode then
        return
    end

    local enabled = isModuleEnabled()
    checkbox:setVisible(enabled)
    checkbox.enable = enabled

    if enabled then
        checkbox:setY(window.searchFocus:getBottom() + UI_BORDER_SPACING)
        window.toggleSearchMode:setY(checkbox:getBottom() + UI_BORDER_SPACING)
    else
        window.toggleSearchMode:setY(window.searchFocus:getBottom() + UI_BORDER_SPACING)
    end

    window:setHeight(window.toggleSearchMode:getBottom() + UI_BORDER_SPACING + 1)
end

local function onCheckboxChanged(window, _, selected)
    onlyForagingByPlayer[window.player] = selected == true
    if selected == true then
        clearWorldItemIcons(window.manager)
    end
end

local function ensureCheckbox(window)
    if not window or not window.searchFocus or not window.toggleSearchMode then
        return
    end

    local checkbox = window.qolForagingRefinementCheckbox
    if not checkbox then
        checkbox = ISTickBox:new(
            UI_BORDER_SPACING + 1,
            window.searchFocus:getBottom() + UI_BORDER_SPACING,
            window.width - (UI_BORDER_SPACING + 1) * 2,
            window.toggleSearchMode:getHeight(),
            "QoLforSacriel.ForagingRefinement",
            window,
            onCheckboxChanged
        )
        checkbox:initialise()
        checkbox:addOption(getCheckboxLabel())
        checkbox:setSelected(1, getOnlyForaging(window))
        window:addChild(checkbox)
        window.qolForagingRefinementCheckbox = checkbox
    end

    updateWindowLayout(window)
end

local function refreshSearchWindows()
    if not ISSearchWindow or not ISSearchWindow.players then
        return
    end

    for _, window in pairs(ISSearchWindow.players) do
        ensureCheckbox(window)
    end
end

local function patchSearchWindow()
    if not ISSearchWindow or not ISSearchWindow.initialise then
        return false
    end

    originalSearchWindowInitialise = ISSearchWindow.initialise
    ISSearchWindow.initialise = function(window)
        originalSearchWindowInitialise(window)
        ensureCheckbox(window)
    end
    return true
end

local function patchWorldItemFilter()
    if not ISSearchManager or not ISSearchManager.worldItemTest then
        return false
    end

    originalWorldItemTest = ISSearchManager.worldItemTest
    ISSearchManager.worldItemTest = function(manager, itemObj)
        if isModuleEnabled() and onlyForagingByPlayer[manager.player] == true then
            return false
        end
        return originalWorldItemTest(manager, itemObj)
    end
    return true
end

function ForagingRefinement.init(settings, logger)
    if installed then
        return
    end

    settingsRef = settings
    loggerRef = logger

    if not patchSearchWindow() or not patchWorldItemFilter() then
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