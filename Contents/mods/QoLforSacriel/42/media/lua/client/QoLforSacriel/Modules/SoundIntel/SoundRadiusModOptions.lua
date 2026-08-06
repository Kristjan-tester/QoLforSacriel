local SoundRadiusModOptions = {}
local MOD_OPTIONS_ID = "QoLforSacriel.SoundRadius"

function SoundRadiusModOptions.register(logger)
    if not PZAPI or not PZAPI.ModOptions or not PZAPI.ModOptions.create then
        return nil
    end
    local options = PZAPI.ModOptions:getOptions(MOD_OPTIONS_ID)
    if options then return options end

    options = PZAPI.ModOptions:create(MOD_OPTIONS_ID, "UI_QoLforSacriel_SoundRadius_Title")
    options:addTitle("UI_QoLforSacriel_SoundRadius_Title")
    options:addDescription("UI_QoLforSacriel_SoundRadius_PerformanceNote")
    options:addTickBox("enabled", "UI_QoLforSacriel_SoundRadius_Enable", false, "UI_QoLforSacriel_SoundRadius_Enable_Tooltip")
    options:addSlider("maxActiveRings", "UI_QoLforSacriel_SoundRadius_MaxActiveRings", 1, 24, 1, 6, "UI_QoLforSacriel_SoundRadius_MaxActiveRings_Tooltip")
    options:addSlider("ringDurationMs", "UI_QoLforSacriel_SoundRadius_Duration", 300, 5000, 100, 1400, "UI_QoLforSacriel_SoundRadius_Duration_Tooltip")
    options:addSlider("ringOpacityPercent", "UI_QoLforSacriel_SoundRadius_Opacity", 5, 80, 5, 25, "UI_QoLforSacriel_SoundRadius_Opacity_Tooltip")
    options:addSlider("ringCullingMarginPx", "UI_QoLforSacriel_SoundRadius_CullingMargin", 0, 1024, 32, 128, "UI_QoLforSacriel_SoundRadius_CullingMargin_Tooltip")
    options:addTickBox("showRadiusLabel", "UI_QoLforSacriel_SoundRadius_ShowRadiusLabel", true, "UI_QoLforSacriel_SoundRadius_ShowRadiusLabel_Tooltip")
    return options
end

return SoundRadiusModOptions