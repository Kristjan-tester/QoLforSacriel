-- ff-assisted
local OrganizedInventory = {}

require "ISUI/InventoryWindow/ISInventoryWindowContainerControls"
require "ISUI/InventoryWindow/ISInventoryWindowControlHandler"
require "ISUI/LootWindow/ISLootWindowContainerControls"
require "ISUI/LootWindow/ISLootWindowObjectControlHandler"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISTickBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISInventoryTransferUtil"

local MODULE_SETTING = "QoLforSacriel_EnableOrganizedInventory"
local TAGS_KEY = "QoLforSacriel.OrganizedInventory.tags"
local POPUP_WIDTH = 720
local POPUP_COMPACT_HEIGHT = 220
local POPUP_EXPANDED_HEIGHT = 700
local TAG_COLUMNS = 3
local TAG_ROW_HEIGHT = 14
local POPUP_SECTION_SPACING = 10
local POPUP_BUTTON_HEIGHT = 25
local POPUP_BOTTOM_MARGIN = 10
local EVERYTHING_ELSE_TAG = "EverythingElse"

local BASIC_TAG_LIST = {
    "Accessory", "Clothing", "Cooking", "Electronics", EVERYTHING_ELSE_TAG, "FirstAid", "Fishing", "Food",
    "Gardening", "Literature", "Material", "ProtectiveGear", "RecipeResource", "SkillBook", "Sports", "Tool",
    "Water", "WaterContainer", "Weapon",
}

local CATEGORY_TAGS = {
    Accessory = { "Accessory" }, Ammo = { "Ammo" }, Animal = { "Animal" }, AnimalPart = { "AnimalPart" },
    AnimalPartWeapon = { "AnimalPart", "Weapon" }, Appearance = { "Appearance" }, Badger = { "Badger" },
    Bag = { "Bag" }, Bandage = { "Bandage" }, Bear = { "Bear" }, Beaver = { "Beaver" },
    BrokenWeapon = { "Weapon" }, Bug = { "Bug" }, Bunny = { "Bunny" }, Camping = { "Camping" },
    Cartography = { "Cartography" }, Clothing = { "Clothing" }, Communications = { "Communications" },
    Container = { "Container" }, Cooking = { "Cooking" }, CookingWeapon = { "Cooking", "Weapon" },
    Corpse = { "Corpse" }, Dog = { "Dog" }, Duck = { "Duck" }, Ears = { "Ears" }, Electronics = { "Electronics" },
    Entertainment = { "Entertainment" }, Explosives = { "Explosives" }, Eye = { "Eye" }, FireSource = { "FireSource" },
    FirstAid = { "FirstAid" }, FirstAidWeapon = { "FirstAid", "Weapon" }, Fishing = { "Fishing" },
    FishingWeapon = { "Fishing", "Weapon" }, Food = { "Food" }, Fox = { "Fox" }, Frog = { "Frog" },
    Furniture = { "Furniture" }, Gardening = { "Gardening" }, GardeningWeapon = { "Gardening", "Weapon" },
    Generic = { "Generic" }, Goblin = { "Goblin" }, Hedgehog = { "Hedgehog" }, Hidden = { "Hidden" },
    Household = { "Household" }, HouseholdWeapon = { "Household", "Weapon" }, Instrument = { "Instrument" },
    InstrumentWeapon = { "Instrument", "Weapon" }, Junk = { "Junk" }, JunkWeapon = { "Junk", "Weapon" },
    LightSource = { "LightSource" }, Literature = { "Literature" }, MaleBody = { "MaleBody" }, Material = { "Material" },
    MaterialWeapon = { "Material", "Weapon" }, Memento = { "Memento" }, Mole = { "Mole" }, Paint = { "Paint" },
    ProtectiveGear = { "ProtectiveGear" }, Raccoon = { "Raccoon" }, RecipeResource = { "RecipeResource" },
    Security = { "Security" }, SkillBook = { "SkillBook" }, Spider = { "Spider" }, Sports = { "Sports" },
    SportsWeapon = { "Sports", "Weapon" }, Squirrel = { "Squirrel" }, Tail = { "Tail" }, ["Teddy Bear"] = { "Teddy Bear" },
    Tool = { "Tool" }, ToolWeapon = { "Tool", "Weapon" }, Trapping = { "Trapping" },
    VehicleMaintenance = { "VehicleMaintenance" }, VehicleMaintenanceWeapon = { "VehicleMaintenance", "Weapon" },
    Water = { "Water" }, WaterContainer = { "WaterContainer" }, Weapon = { "Weapon" },
    WeaponCrafted = { "Weapon" }, WeaponImprovised = { "Weapon" }, WeaponPart = { "WeaponPart" }, Wound = { "Wound" },
    ZedDmg = { "ZedDmg" },
}

local TAG_CATALOG = {}
for category, tags in pairs(CATEGORY_TAGS) do
    for index = 1, #tags do
        TAG_CATALOG[tags[index]] = true
    end
end
TAG_CATALOG[EVERYTHING_ELSE_TAG] = true

local TAG_LIST = {}
for tag in pairs(TAG_CATALOG) do
    table.insert(TAG_LIST, tag)
end
table.sort(TAG_LIST)

local BASIC_TAG_SET = {}
for _, tag in ipairs(BASIC_TAG_LIST) do
    BASIC_TAG_SET[tag] = true
end

local ADVANCED_TAG_LIST = {}
for _, tag in ipairs(TAG_LIST) do
    if not BASIC_TAG_SET[tag] then
        table.insert(ADVANCED_TAG_LIST, tag)
    end
end

local installed = false
local settingsRef = nil
local loggerRef = nil

local function getTextOrFallback(key, fallback)
    if getTextOrNull then
        local translated = getTextOrNull(key)
        if translated and translated ~= "" then
            return translated
        end
    end
    return fallback
end

local function logDebug(message)
    if loggerRef and loggerRef.debug and settingsRef and settingsRef.get
        and settingsRef.get("QoLforSacriel_DebugLogs") == true then
        loggerRef.debug("OrganizedInventory: " .. tostring(message))
    end
end

local function isModuleEnabled()
    return settingsRef and settingsRef.isEnabled and settingsRef.isEnabled(MODULE_SETTING) == true
end

local function callMethod(object, methodName, ...)
    if not object or type(object[methodName]) ~= "function" then
        return nil
    end
    local ok, result = pcall(object[methodName], object, ...)
    if ok then
        return result
    end
    return nil
end

local function getTagOwner(container)
    local parent = callMethod(container, "getParent")
    if parent and type(parent.getModData) == "function" then
        return parent
    end

    local containingItem = callMethod(container, "getContainingItem")
    if containingItem and type(containingItem.getModData) == "function" then
        return containingItem
    end
    return nil
end

local function getTagSet(container)
    local owner = getTagOwner(container)
    local modData = owner and callMethod(owner, "getModData") or nil
    local tags = modData and modData[TAGS_KEY] or nil
    return type(tags) == "table" and tags or nil
end

local function getSelectedTagNames(container)
    local tagSet = getTagSet(container)
    if not tagSet then
        return {}
    end

    local names = {}
    for _, tag in ipairs(TAG_LIST) do
        if tagSet[tag] == true then
            table.insert(names, getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryTag_" .. tag, tag))
        end
    end
    table.sort(names)
    return names
end

local function getTagSummary(container)
    local tagNames = getSelectedTagNames(container)
    if #tagNames == 0 then
        return nil, nil
    end

    local shownCount = math.min(#tagNames, 2)
    local summary = getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryTags", "Tags:")
        .. " " .. table.concat(tagNames, ", ", 1, shownCount)
    if #tagNames > shownCount then
        summary = summary .. "..."
    end

    local tooltip = getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryTagsTooltip", "Selected tags")
        .. ": " .. table.concat(tagNames, ", ")
    return summary, tooltip
end

local function hasTags(container)
    local tags = getTagSet(container)
    if not tags then
        return false
    end
    for _ in pairs(tags) do
        return true
    end
    return false
end

local function isPlayerContainer(container, playerObj)
    return callMethod(container, "isInCharacterInventory", playerObj) == true
end

local function getContainerDebugName(container)
    return tostring(callMethod(container, "getType") or "unknown")
end

local function getContainerCapacityDebugText(container, playerObj)
    local capacity = tonumber(callMethod(container, "getCapacity"))
    local effectiveCapacity = tonumber(callMethod(container, "getEffectiveCapacity", playerObj))
    local contentsWeight = tonumber(callMethod(container, "getContentsWeight"))
    local freeCapacity = tonumber(callMethod(container, "getFreeCapacity", playerObj))
    if not capacity or not effectiveCapacity or not contentsWeight or not freeCapacity then
        return "capacity: unavailable | effective capacity: unavailable | contents weight: unavailable | free capacity: unavailable"
    end
    return "capacity: " .. tostring(capacity) .. " | effective capacity: " .. tostring(effectiveCapacity)
        .. " | contents weight: " .. tostring(contentsWeight) .. " | free capacity: " .. tostring(freeCapacity)
end

local function isDirectSourceItemEligible(item, playerObj)
    if not item or callMethod(item, "isEquipped") == true then
        return false
    end
    if callMethod(item, "isFavorite") == true then
        return false
    end
    if callMethod(item, "isItemType", ItemType and ItemType.KEY_RING) == true or callMethod(item, "hasTag", ItemTag and ItemTag.KEY_RING) == true then
        return false
    end
    if callMethod(item, "getInventory") ~= nil then
        return false
    end
    local playerNum = callMethod(playerObj, "getPlayerNum")
    local hotbar = playerNum ~= nil and getPlayerHotbar and getPlayerHotbar(playerNum) or nil
    if hotbar and hotbar.isInHotbar and hotbar:isInHotbar(item) then
        return false
    end
    return true
end

local function getContainerItems(container)
    local results = {}
    local items = callMethod(container, "getItems")
    if not items or type(items.size) ~= "function" then
        return results
    end
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if item then
            table.insert(results, item)
        end
    end
    return results
end

local function getContainerList(playerObj)
    if not ISInventoryPaneContextMenu or type(ISInventoryPaneContextMenu.getContainers) ~= "function" then
        return {}
    end
    local containers = ISInventoryPaneContextMenu.getContainers(playerObj)
    local results = {}
    if containers and type(containers.size) == "function" then
        for index = 0, containers:size() - 1 do
            table.insert(results, containers:get(index))
        end
    end
    return results
end

local function getItemTags(item)
    local category = callMethod(item, "getDisplayCategory")
    return category and CATEGORY_TAGS[tostring(category)] or nil
end

local function getTagsDebugText(tags)
    if not tags or #tags == 0 then
        return "none"
    end
    return table.concat(tags, ", ")
end

local function getItemDebugName(item)
    return tostring(callMethod(item, "getFullType") or callMethod(item, "getName") or "unknown")
end

local function tagSetContainsAll(tagSet, tags)
    for index = 1, #tags do
        if tagSet[tags[index]] ~= true then
            return false
        end
    end
    return true
end

local function getItemWeight(item)
    local weight = callMethod(item, "getUnequippedWeight") or callMethod(item, "getActualWeight") or 0
    return math.max(0, tonumber(weight) or 0)
end

local function hasPlannedCapacity(container, item, playerObj, reservedWeight)
    if callMethod(container, "isItemAllowed", item) ~= true or callMethod(container, "hasRoomFor", playerObj, item) ~= true then
        return false
    end
    local freeCapacity = tonumber(callMethod(container, "getFreeCapacity", playerObj))
    if freeCapacity == nil then
        return true
    end
    return (reservedWeight[container] or 0) + getItemWeight(item) <= freeCapacity
end

local function collectDestinations(playerObj, source, logCandidates)
    local results = {}
    local seen = {}
    for _, container in ipairs(getContainerList(playerObj)) do
        local exclusionReason = nil
        if not container then
            exclusionReason = "unavailable"
        elseif seen[container] then
            exclusionReason = "duplicate"
        elseif container == source then
            exclusionReason = "source"
        elseif isPlayerContainer(container, playerObj) then
            exclusionReason = "player inventory"
        elseif not hasTags(container) then
            exclusionReason = "no tags"
        end
        if exclusionReason then
            if logCandidates and container then
                logDebug("Container candidate " .. getContainerDebugName(container)
                    .. " | tags: " .. getTagsDebugText(getSelectedTagNames(container))
                    .. " | skipped: " .. exclusionReason)
            end
        else
            seen[container] = true
            table.insert(results, container)
            if logCandidates then
                logDebug("Container candidate " .. getContainerDebugName(container)
                    .. " | tags: " .. getTagsDebugText(getSelectedTagNames(container))
                    .. " | accepted")
            end
        end
    end
    return results
end

local function chooseDestination(item, destinations, playerObj, reservedWeight)
    local tags = getItemTags(item)
    if tags then
        for _, container in ipairs(destinations) do
            if tagSetContainsAll(getTagSet(container), tags) and hasPlannedCapacity(container, item, playerObj, reservedWeight) then
                return container
            end
        end
        for tagIndex = 1, #tags do
            for _, container in ipairs(destinations) do
                local tagSet = getTagSet(container)
                if tagSet[tags[tagIndex]] == true and hasPlannedCapacity(container, item, playerObj, reservedWeight) then
                    return container
                end
            end
        end
    end

    for _, container in ipairs(destinations) do
        local tagSet = getTagSet(container)
        if tagSet[EVERYTHING_ELSE_TAG] == true and hasPlannedCapacity(container, item, playerObj, reservedWeight) then
            return container
        end
    end
    return nil
end

local function queueUnload(playerObj, source)
    if isGamePaused() or not playerObj or not source or not ISInventoryTransferUtil
        or type(ISInventoryTransferUtil.newInventoryTransferAction) ~= "function"
        or not ISTimedActionQueue or type(ISTimedActionQueue.add) ~= "function" then
        return
    end

    local destinations = collectDestinations(playerObj, source, true)
    local reservedWeight = {}
    local queuedCount = 0
    if #destinations == 0 then
        logDebug("Available tagged destinations: none")
    else
        for _, destination in ipairs(destinations) do
            logDebug("Available tagged destination " .. getContainerDebugName(destination)
                .. " | tags: " .. getTagsDebugText(getSelectedTagNames(destination))
                .. " | " .. getContainerCapacityDebugText(destination, playerObj))
        end
    end

    for _, item in ipairs(getContainerItems(source)) do
        if isDirectSourceItemEligible(item, playerObj) and callMethod(item, "getContainer") == source then
            local itemTags = getItemTags(item)
            logDebug("Eligible item " .. getItemDebugName(item)
                .. " | tags: " .. getTagsDebugText(itemTags))
            local destination = chooseDestination(item, destinations, playerObj, reservedWeight)
            if destination then
                reservedWeight[destination] = (reservedWeight[destination] or 0) + getItemWeight(item)
                local action = ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item, source, destination, 50)
                if action then
                    ISTimedActionQueue.add(action)
                    queuedCount = queuedCount + 1
                end
            end
        end
    end
    logDebug("Unload All queued " .. tostring(queuedCount) .. " item(s) from " .. getContainerDebugName(source)
        .. " using " .. tostring(#destinations) .. " tagged destination(s)")
end

local function hasEligibleSourceItems(container, playerObj)
    for _, item in ipairs(getContainerItems(container)) do
        if isDirectSourceItemEligible(item, playerObj) then
            return true
        end
    end
    return false
end

local function hasAvailableDestination(playerObj, source)
    return #collectDestinations(playerObj, source) > 0
end

local function refreshLootWindowFooter(lootWindow)
    local controls = lootWindow and lootWindow.controlsUI
    if not controls or type(controls.arrange) ~= "function" then
        return
    end

    controls:arrange()
    if lootWindow.inventoryPane and lootWindow.resizeWidget then
        lootWindow.inventoryPane:setHeight(lootWindow.height - lootWindow.inventoryPane.y
            - lootWindow.resizeWidget.height - controls.height)
    end
end

local function openTagPopup(container, lootWindow)
    local owner = getTagOwner(container)
    local modData = owner and callMethod(owner, "getModData") or nil
    if not owner or not modData then
        logDebug("Configure unload tags unavailable: no mod-data owner for " .. getContainerDebugName(container))
        return
    end

    logDebug("Opening tag configuration for " .. getContainerDebugName(container))

    local popup = ISCollapsableWindow:new(
        (getCore():getScreenWidth() - POPUP_WIDTH) / 2,
        (getCore():getScreenHeight() - POPUP_COMPACT_HEIGHT) / 2,
        POPUP_WIDTH,
        POPUP_COMPACT_HEIGHT
    )
    popup:initialise()
    popup:setTitle(getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryConfigureTags", "Configure unload tags"))
    popup.resizable = false
    popup:addToUIManager()

    local existingTags = getTagSet(container) or {}
    local basicColumns = {}
    local advancedColumns = {}
    local columnWidth = math.floor((POPUP_WIDTH - 40) / TAG_COLUMNS)
    local function addTagColumns(tags, y, columns)
        for columnIndex = 1, TAG_COLUMNS do
            local tickBox = ISTickBox:new(10 + (columnIndex - 1) * columnWidth, y, columnWidth - 10, TAG_ROW_HEIGHT, "QoLforSacriel.OrganizedInventory", nil, nil)
            tickBox:initialise()
            popup:addChild(tickBox)
            columns[columnIndex] = tickBox
        end
        for index = 1, #tags do
            local tag = tags[index]
            local columnIndex = ((index - 1) % TAG_COLUMNS) + 1
            local optionIndex = columns[columnIndex]:addOption(getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryTag_" .. tag, tag), tag)
            columns[columnIndex]:setSelected(optionIndex, existingTags[tag] == true)
        end
    end

    local function getColumnsHeight(columns)
        local height = 0
        for _, tickBox in ipairs(columns) do
            height = math.max(height, tickBox:getHeight())
        end
        return height
    end

    local tagsY = popup:titleBarHeight() + POPUP_SECTION_SPACING
    addTagColumns(BASIC_TAG_LIST, tagsY, basicColumns)
    local basicTagsHeight = getColumnsHeight(basicColumns)
    local advancedTagsY = tagsY + basicTagsHeight + POPUP_SECTION_SPACING
    addTagColumns(ADVANCED_TAG_LIST, advancedTagsY, advancedColumns)
    local advancedTagsHeight = getColumnsHeight(advancedColumns)
    local compactPopupHeight = tagsY + basicTagsHeight + POPUP_SECTION_SPACING + POPUP_BUTTON_HEIGHT + POPUP_BOTTOM_MARGIN
    local expandedPopupHeight = math.max(
        POPUP_EXPANDED_HEIGHT,
        advancedTagsY + advancedTagsHeight + POPUP_SECTION_SPACING + POPUP_BUTTON_HEIGHT + POPUP_BOTTOM_MARGIN
    )

    local allColumns = {}
    for _, columns in ipairs({ basicColumns, advancedColumns }) do
        for _, tickBox in ipairs(columns) do
            table.insert(allColumns, tickBox)
        end
    end

    local expanded = false
    local toggleButton = nil
    local applyButton = nil
    local cancelButton = nil
    local function updatePopupLayout()
        local popupHeight = expanded and expandedPopupHeight or compactPopupHeight
        popup:setHeight(popupHeight)
        for _, tickBox in ipairs(advancedColumns) do
            tickBox:setVisible(expanded)
        end
        toggleButton.title = getTextOrFallback(
            expanded and "UI_QoLforSacriel_OrganizedInventoryToggleBasicOptions" or "UI_QoLforSacriel_OrganizedInventoryToggleAllOptions",
            expanded and "Toggle basic options" or "Toggle all options"
        )
        local buttonY = popupHeight - POPUP_BUTTON_HEIGHT - POPUP_BOTTOM_MARGIN
        toggleButton:setY(buttonY)
        applyButton:setY(buttonY)
        cancelButton:setY(buttonY)
    end

    local function closePopup()
        popup:removeFromUIManager()
        popup:setVisible(false)
    end

    local function applyTags()
        local selectedTags = {}
        local selectedTagNames = {}
        local hasSelectedTags = false
        for _, tickBox in ipairs(allColumns) do
            for optionIndex = 1, tickBox:getOptionCount() do
                if tickBox:isSelected(optionIndex) then
                    local tag = tickBox:getOptionData(optionIndex)
                    selectedTags[tag] = true
                    table.insert(selectedTagNames, tag)
                    hasSelectedTags = true
                end
            end
        end
        if hasSelectedTags then
            modData[TAGS_KEY] = selectedTags
        else
            modData[TAGS_KEY] = nil
        end
        logDebug("Applied tags for " .. getContainerDebugName(container) .. ": "
            .. (hasSelectedTags and table.concat(selectedTagNames, ", ") or "cleared"))
        refreshLootWindowFooter(lootWindow)
        closePopup()
    end

    local function cancelTags()
        logDebug("Cancelled tag configuration for " .. getContainerDebugName(container))
        closePopup()
    end

    local function toggleOptions()
        expanded = not expanded
        updatePopupLayout()
    end

    local buttonY = POPUP_COMPACT_HEIGHT - POPUP_BUTTON_HEIGHT - POPUP_BOTTOM_MARGIN
    toggleButton = ISButton:new(10, buttonY, 160, POPUP_BUTTON_HEIGHT, "", nil, toggleOptions)
    toggleButton:initialise()
    popup:addChild(toggleButton)
    applyButton = ISButton:new(POPUP_WIDTH - 190, buttonY, 85, POPUP_BUTTON_HEIGHT, getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryApply", "Apply"), nil, applyTags)
    applyButton:initialise()
    popup:addChild(applyButton)
    cancelButton = ISButton:new(POPUP_WIDTH - 95, buttonY, 85, POPUP_BUTTON_HEIGHT, getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryCancel", "Cancel"), nil, cancelTags)
    cancelButton:initialise()
    popup:addChild(cancelButton)
    updatePopupLayout()
end

local UnloadHandler = ISInventoryWindowControlHandler:derive("QoLforSacriel_OrganizedInventoryUnloadHandler")
UnloadHandler.Type = "QoLforSacriel.OrganizedInventory.Unload"

function UnloadHandler:shouldBeVisible()
    return isModuleEnabled() and hasEligibleSourceItems(self.container, self.playerObj)
end

function UnloadHandler:getControl()
    local control = self:getButtonControl(getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryUnloadAll", "Unload All"))
    local enabled = hasAvailableDestination(self.playerObj, self.container)
    control.enable = enabled
    control.tooltip = enabled and nil or getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryNoDestination", "No tagged nearby container is available.")
    return control
end

function UnloadHandler:perform()
    logDebug("Unload All button pressed for " .. getContainerDebugName(self.container))
    queueUnload(self.playerObj, self.container)
end

function UnloadHandler:new()
    return ISInventoryWindowControlHandler.new(self)
end

local ConfigureHandler = ISLootWindowObjectControlHandler:derive("QoLforSacriel_OrganizedInventoryConfigureHandler")
ConfigureHandler.Type = "QoLforSacriel.OrganizedInventory.Configure"

function ConfigureHandler:shouldBeVisible()
    return isModuleEnabled() and self.container ~= nil and not isPlayerContainer(self.container, self.playerObj)
        and getTagOwner(self.container) ~= nil
end

function ConfigureHandler:getControl()
    return self:getButtonControl(getTextOrFallback("UI_QoLforSacriel_OrganizedInventoryConfigureTags", "Configure unload tags"))
end

function ConfigureHandler:perform()
    if not isGamePaused() then
        logDebug("Configure unload tags button pressed for " .. getContainerDebugName(self.container))
        openTagPopup(self.container, self.lootWindow)
    else
        logDebug("Configure unload tags button ignored while game is paused")
    end
end

function ConfigureHandler:new()
    return ISLootWindowObjectControlHandler.new(self)
end

local TagSummaryHandler = ISLootWindowObjectControlHandler:derive("QoLforSacriel_OrganizedInventoryTagSummaryHandler")
TagSummaryHandler.Type = "QoLforSacriel.OrganizedInventory.TagSummary"

local function dismissTooltip(label)
    if label and label.tooltipUI and label.tooltipUI:getIsVisible() then
        label.tooltipUI:setVisible(false)
        label.tooltipUI:removeFromUIManager()
    end
end

function TagSummaryHandler:shouldBeVisible()
    local summary = self.container and getTagSummary(self.container) or nil
    local visible = isModuleEnabled() and summary ~= nil and not isPlayerContainer(self.container, self.playerObj)
        and getTagOwner(self.container) ~= nil
    if not visible then
        dismissTooltip(self.control)
    end
    return visible
end

function TagSummaryHandler:getControl()
    local summary, tooltip = getTagSummary(self.container)
    if not self.control then
        self.control = ISLabel:new(0, 0, 0, "", 0.9, 0.9, 0.9, 1, UIFont.Small, true)
        self.control:initialise()
    end
    self.control:setNameWithoutMoving(summary or "")
    self.control:setTooltip(tooltip)
    return self.control
end

function TagSummaryHandler:new()
    return ISLootWindowObjectControlHandler.new(self)
end

function OrganizedInventory.init(settings, logger)
    if installed then
        return
    end
    settingsRef = settings
    loggerRef = logger

    if not ISInventoryWindowContainerControls or not ISInventoryWindowContainerControls.AddHandler
        or not ISLootWindowContainerControls or not ISLootWindowContainerControls.AddHandler
        or not ISInventoryTransferUtil or not ISInventoryTransferUtil.newInventoryTransferAction then
        if loggerRef and loggerRef.error then
            loggerRef.error("OrganizedInventory unavailable: required Build 42 inventory APIs are missing")
        end
        return
    end

    ISInventoryWindowContainerControls.AddHandler(UnloadHandler)
    ISLootWindowContainerControls.AddHandler(ConfigureHandler)
    ISLootWindowContainerControls.AddHandler(TagSummaryHandler)
    installed = true
    logDebug("installed")
end

return OrganizedInventory