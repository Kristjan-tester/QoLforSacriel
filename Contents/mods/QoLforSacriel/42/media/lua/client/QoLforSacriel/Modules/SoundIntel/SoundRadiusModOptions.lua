local SoundRadiusModOptions = {}
local MOD_OPTIONS_ID = "QoLforSacriel.SoundRadius"

local function attachApplyRefresh(options, onApplyRefresh)
    if not options or type(onApplyRefresh) ~= "function" or options._qolSoundRadiusApplyRefreshAttached == true then
        return
    end

    local previousApply = options.apply
    options.apply = function(self)
        if previousApply then
            previousApply(self)
        end
        onApplyRefresh()
    end
    options._qolSoundRadiusApplyRefreshAttached = true
end

function SoundRadiusModOptions.register(logger, onApplyRefresh)
    if not PZAPI or not PZAPI.ModOptions or not PZAPI.ModOptions.create then
        return nil
    end
    local options = PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)
    if options then
        attachApplyRefresh(options, onApplyRefresh)
        return options
    end

    options = PZAPI.ModOptions:create(MOD_OPTIONS_ID, "UI_QoLforSacriel_SoundRadius_Title")
    options:addTitle("UI_QoLforSacriel_SoundRadius_Title")
    options:addDescription("UI_QoLforSacriel_SoundRadius_PerformanceNote")
    options:addTickBox("enabled", "UI_QoLforSacriel_SoundRadius_Enable", false, "UI_QoLforSacriel_SoundRadius_Enable_Tooltip")
    options:addSlider("maxActiveRings", "UI_QoLforSacriel_SoundRadius_MaxActiveRings", 1, 24, 1, 6, "UI_QoLforSacriel_SoundRadius_MaxActiveRings_Tooltip")
    options:addSlider("ringDurationMs", "UI_QoLforSacriel_SoundRadius_Duration", 300, 5000, 100, 1400, "UI_QoLforSacriel_SoundRadius_Duration_Tooltip")
    options:addSlider("ringOpacityPercent", "UI_QoLforSacriel_SoundRadius_Opacity", 5, 80, 5, 25, "UI_QoLforSacriel_SoundRadius_Opacity_Tooltip")
    options:addSlider("ringCullingMarginPx", "UI_QoLforSacriel_SoundRadius_CullingMargin", 0, 1024, 32, 128, "UI_QoLforSacriel_SoundRadius_CullingMargin_Tooltip")
    options:addTickBox("showRadiusLabel", "UI_QoLforSacriel_SoundRadius_ShowRadiusLabel", true, "UI_QoLforSacriel_SoundRadius_ShowRadiusLabel_Tooltip")
    local radiusLabelFontOption = options:addComboBox("radiusLabelFont", "UI_QoLforSacriel_SoundRadius_LabelFont", "UI_QoLforSacriel_SoundRadius_LabelFont_Tooltip")
    radiusLabelFontOption:addItem("UI_QoLforSacriel_SoundRadius_LabelFont_Small", true)
    radiusLabelFontOption:addItem("UI_QoLforSacriel_SoundRadius_LabelFont_Medium", false)
    radiusLabelFontOption:addItem("UI_QoLforSacriel_SoundRadius_LabelFont_Large", false)
    attachApplyRefresh(options, onApplyRefresh)
    return options
end

return SoundRadiusModOptions