local SkillFilter = {}

local patched = false
local originalLoadPerk = nil
local originalCreateChildren = nil
local originalRender = nil
local showOnlyLeveledEnabled = false

require "ISUI/ISTickBox"

local UI_BORDER_SPACING = 10
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = FONT_HGT_SMALL + 6
local SCROLL_BAR_WIDTH = 13

local function getShowOnlyLeveledLabel()
    return getTextOrNull("UI_QoLforSacriel_ShowOnlyLeveled") or "show only leveled"
end

local function shouldIncludePerk(self, perk, includePartialXP)
    if not self or not self.char or not perk then
        return true
    end

    local level = self.char:getPerkLevel(perk:getType())
    if level > 0 then
        return true
    end

    if includePartialXP then
        local xp = self.char:getXp():getXP(perk:getType())
        return xp > 0
    end

    return false
end

local function sortParentPerks(a, b)
    if a:isPassiv() and not b:isPassiv() then
        return true
    end
    if b:isPassiv() and not a:isPassiv() then
        return false
    end
    return not string.sort(a:getName(), b:getName())
end

local function clearProgressBars(self)
    if not self.progressBars then
        self.progressBars = {}
        self.progressBarLoaded = false
        return
    end

    for i = 1, #self.progressBars do
        self:removeChild(self.progressBars[i])
    end
    self.progressBars = {}
    self.progressBarLoaded = false
end

local function rebuildSkillLayout(self)
    local oldButtons = self.buttonList or {}
    for i = 1, #oldButtons do
        self:removeChild(oldButtons[i])
    end

    self.sorted = {}
    self.nameToPerk = {}
    self.buttonList = {}
    self.collapse = {}
    self.perks = ISCharacterInfo.loadPerk(self) or {}

    for k, _ in pairs(self.perks) do
        local parentPerk = PerkFactory.getPerk(k)
        if parentPerk then
            table.insert(self.sorted, parentPerk)
            self.nameToPerk[parentPerk:getName()] = k
        end
    end

    table.sort(self.sorted, sortParentPerks)

    for i = 1, #self.sorted do
        table.insert(self.collapse, false)
        local collapseButton = ISButton:new(UI_BORDER_SPACING + 1, 0, BUTTON_HGT, BUTTON_HGT, "", self, ISCharacterInfo.collapseSection)
        collapseButton.internal = "COLLAPSE" .. i
        collapseButton:setImage(getTexture("media/ui/inventoryPanes/Button_TreeExpanded.png"))
        collapseButton:initialise()
        self:addChild(collapseButton)
        table.insert(self.buttonList, collapseButton)
    end

    for i = 1, #self.sorted do
        local parentPerk = self.sorted[i]
        local perkList = self.perks[parentPerk:getType()]
        if perkList then
            table.sort(perkList, function(a, b)
                return a:getName() < b:getName()
            end)
        end
    end

    clearProgressBars(self)
    self.reloadSkillBar = true
end

local function updateShowOnlyLeveledCheckboxPosition(self)
    if not self.qolShowOnlyLeveledCheckbox then
        return
    end

    local label = getShowOnlyLeveledLabel()
    local width = BUTTON_HGT + getTextManager():MeasureStringX(UIFont.Small, label) + 24
    local rightX = self.width - width - SCROLL_BAR_WIDTH - UI_BORDER_SPACING - 1
    local x = math.max(UI_BORDER_SPACING + 1, rightX)
    self.qolShowOnlyLeveledCheckbox:setWidth(width)
    self.qolShowOnlyLeveledCheckbox:setX(x)
    self.qolShowOnlyLeveledCheckbox:setY(1)
end

local function onToggleShowOnlyLeveled(self)
    if not self or not self.qolShowOnlyLeveledCheckbox then
        return
    end

    local selected = self.qolShowOnlyLeveledCheckbox:isSelected(1)
    showOnlyLeveledEnabled = selected == true
    self.qolShowOnlyLeveled = showOnlyLeveledEnabled
    rebuildSkillLayout(self)
end

local function ensureShowOnlyLeveledCheckbox(self)
    if self.qolShowOnlyLeveled == nil then
        self.qolShowOnlyLeveled = showOnlyLeveledEnabled
    end

    local label = getShowOnlyLeveledLabel()
    if not self.qolShowOnlyLeveledCheckbox then
        local tickBox = ISTickBox:new(0, UI_BORDER_SPACING, 100, BUTTON_HGT, "", self, onToggleShowOnlyLeveled)
        tickBox:initialise()
        tickBox:addOption(label)
        tickBox:setSelected(1, self.qolShowOnlyLeveled == true)
        tickBox.choicesColor = { r = 1, g = 1, b = 1, a = 1 }
        pcall(function()
            tickBox:setScrollWithParent(false)
        end)
        self.qolShowOnlyLeveledCheckbox = tickBox
        self:addChild(tickBox)
    else
        self.qolShowOnlyLeveledCheckbox:clearOptions()
        self.qolShowOnlyLeveledCheckbox:addOption(label)
        self.qolShowOnlyLeveledCheckbox:setSelected(1, self.qolShowOnlyLeveled == true)
    end

    updateShowOnlyLeveledCheckboxPosition(self)
end

function SkillFilter.init(settings, logger)
    if patched then
        logger.debug("UIFixes.SkillFilter already patched")
        return
    end

    if not ISCharacterInfo or not ISCharacterInfo.loadPerk or not ISCharacterInfo.createChildren or not ISCharacterInfo.render then
        logger.warn("UIFixes.SkillFilter could not patch ISCharacterInfo.loadPerk")
        return
    end

    originalLoadPerk = ISCharacterInfo.loadPerk
    originalCreateChildren = ISCharacterInfo.createChildren
    originalRender = ISCharacterInfo.render

    ISCharacterInfo.loadPerk = function(self)
        local allPerks = originalLoadPerk(self)
        if allPerks == nil then
            return allPerks
        end

        if settings.isEnabled("QoLforSacriel_EnableUIFixes") ~= true or settings.get("QoLforSacriel_UIFixes_EnableSkillFilter") ~= true then
            return allPerks
        end

        if self.qolShowOnlyLeveled == nil then
            self.qolShowOnlyLeveled = showOnlyLeveledEnabled
        end

        if self.qolShowOnlyLeveled ~= true then
            return allPerks
        end

        local includePartialXP = settings.get("QoLforSacriel_UIFixes_SkillFilterIncludePartialXP") == true
        local filtered = {}

        for parentPerk, perkList in pairs(allPerks) do
            local keep = {}
            for i = 1, #perkList do
                local perk = perkList[i]
                local ok, include = pcall(function()
                    return shouldIncludePerk(self, perk, includePartialXP)
                end)
                if ok and include then
                    table.insert(keep, perk)
                end
            end

            if #keep > 0 then
                filtered[parentPerk] = keep
            end
        end

        return filtered
    end

    ISCharacterInfo.createChildren = function(self)
        originalCreateChildren(self)
        if settings.isEnabled("QoLforSacriel_EnableUIFixes") == true and settings.get("QoLforSacriel_UIFixes_EnableSkillFilter") == true then
            ensureShowOnlyLeveledCheckbox(self)
        elseif self.qolShowOnlyLeveledCheckbox and self.qolShowOnlyLeveledCheckbox.setVisible then
            self.qolShowOnlyLeveledCheckbox:setVisible(false)
        end
    end

    ISCharacterInfo.render = function(self)
        if settings.isEnabled("QoLforSacriel_EnableUIFixes") == true and settings.get("QoLforSacriel_UIFixes_EnableSkillFilter") == true then
            ensureShowOnlyLeveledCheckbox(self)
            updateShowOnlyLeveledCheckboxPosition(self)
            if self.qolShowOnlyLeveledCheckbox and self.qolShowOnlyLeveledCheckbox.setVisible then
                self.qolShowOnlyLeveledCheckbox:setVisible(true)
            end
        elseif self.qolShowOnlyLeveledCheckbox and self.qolShowOnlyLeveledCheckbox.setVisible then
            self.qolShowOnlyLeveledCheckbox:setVisible(false)
        end
        originalRender(self)
    end

    patched = true
    logger.info("UIFixes.SkillFilter patch active")
end

return SkillFilter
