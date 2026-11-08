local addonName, T = ...

local actionSections = {
    {key = "overShoulder", name = "Over the Shoulder", prefix = "test_cameraOverShoulder"},
    {key = "dynamicPitch", name = "Dynamic Pitch", prefix = "test_cameraDynamicPitch"},
    {key = "headMovement", name = "Head Movement", prefix = "test_cameraHeadMovement"},
    {key = "targetFocus", name = "Target Focus", prefix = "test_cameraTargetFocus"},
    {key = "advanced", name = "Advanced Action Camera"}
}

local actionControls = {
    test_cameraOverShoulder = {"Shoulder Offset", "Moves the camera to the left or right of your character.", -2, 2, 0.01},
    test_cameraDynamicPitch = {"Dynamic Pitch", "Adjusts camera pitch as the distance to your character changes.", boolean = true},
    test_cameraDynamicPitchBaseFovPad = {"Base Field of View Padding", "Controls field of view padding for dynamic pitch.", 0.01, 0.99, 0.01},
    test_cameraDynamicPitchBaseFovPadFlying = {"Flying Field of View Padding", "Controls field of view padding while flying.", 0.01, 0.99, 0.01},
    test_cameraDynamicPitchBaseFovPadDownScale = {"Downward Padding Scale", "Scales dynamic pitch padding when looking down.", 0, 1, 0.01},
    test_cameraDynamicPitchSmartPivotCutoffDist = {"Smart Pivot Cutoff Distance", "Camera distance at which dynamic pitch smart pivot stops applying.", 0, 50, 0.01},
    test_cameraHeadMovementStrength = {"Head Movement Strength", "Overall strength of camera head movement.", 0, 4, 0.01},
    test_cameraHeadMovementStandingStrength = {"Standing Head Movement", "Strength of camera head movement while standing.", 0, 4, 0.01},
    test_cameraHeadMovementMovingStrength = {"Moving Head Movement", "Strength of camera head movement while moving.", 0, 4, 0.01},
    test_cameraHeadMovementFirstPersonDampRate = {"First-Person Damping", "Damping rate for head movement in first-person view.", 1, 50, 0.1},
    test_cameraHeadMovementStandingDampRate = {"Standing Damping", "Damping rate for head movement while standing.", 1, 50, 0.1},
    test_cameraHeadMovementMovingDampRate = {"Moving Damping", "Damping rate for head movement while moving.", 1, 50, 0.1},
    test_cameraHeadMovementDeadZone = {"Head Movement Dead Zone", "Head movement dead zone. Mounting or reloading may be required for this change to take effect.", 0, 50, 0.1},
    test_cameraHeadMovementRangeScale = {"Head Movement Range", "Scales the range of camera head movement.", 0, 50, 0.1},
    test_cameraTargetFocusEnemyEnable = {"Focus Enemies", "Allows the camera to focus on your enemy target.", boolean = true},
    test_cameraTargetFocusEnemyStrengthPitch = {"Enemy Focus Pitch", "Vertical strength of camera focus on enemies.", 0, 1, 0.01},
    test_cameraTargetFocusEnemyStrengthYaw = {"Enemy Focus Yaw", "Horizontal strength of camera focus on enemies.", 0, 1, 0.01},
    test_cameraTargetFocusInteractEnable = {"Focus Interactions", "Allows the camera to focus on your interaction target.", boolean = true},
    test_cameraTargetFocusInteractStrengthPitch = {"Interaction Focus Pitch", "Vertical strength of camera focus on interactions.", 0, 1, 0.01},
    test_cameraTargetFocusInteractStrengthYaw = {"Interaction Focus Yaw", "Horizontal strength of camera focus on interactions.", 0, 1, 0.01}
}

local function replaceContents(target, source)
    for key in pairs(target) do target[key] = nil end
    for key, value in pairs(source) do target[key] = T.deepCopy(value) end
end

local function append(target, source)
    for _, value in ipairs(source) do target[#target + 1] = value end
end

StaticPopupDialogs["AUTO_CAMERA_EDIT_SETTING"] = {
    text = "%s",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(dialog, data)
        local editBox = dialog:GetEditBox()
        editBox:SetText(data.setting:GetValue())
        editBox:HighlightText()
        editBox:SetFocus()
    end,
    OnAccept = function(dialog, data)
        data.setting:SetValue(dialog:GetEditBox():GetText())
    end
}

function T.setupSettingsPanel(addon)
    local category = Settings.RegisterVerticalLayoutCategory(addonName)
    local zoomCategory, layout = Settings.RegisterVerticalLayoutSubcategory(category, "Auto Zoom")
    local actionCategory, actionLayout = Settings.RegisterVerticalLayoutSubcategory(category, "Action Camera")
    addon.settingsCategory = category
    local variables, owned, watchedCVars, watchedByName = {}, {}, {}, {}
    local zoomEntries, actionEntries = {}, {}
    -- Initializer sets used to refresh only the frames affected by a change.
    local resetButtons, centeringDependents, modelControls = {}, {}, {}
    local modelVariables = {}
    local defaults = T.defaultSettings()
    local reset

    local function refreshFrames(filter)
        if not SettingsPanel:IsShown() then return end
        SettingsPanel:GetSettingsList().ScrollBox:ForEachFrame(function(frame)
            local initializer = frame:GetElementData()
            if owned[initializer] and (not filter or filter(initializer)) then
                if frame.EvaluateState then frame:EvaluateState() end
                if frame.EvaluateName and frame.Button then
                    frame.Button:SetText(frame:EvaluateName())
                end
            end
        end)
    end

    -- Refreshes reset buttons when Undo snapshots were discarded, plus any dependent controls.
    local function refreshAffected(undoChanged, dependents)
        if not undoChanged and not dependents then return end
        refreshFrames(function(initializer)
            return (undoChanged and resetButtons[initializer]) or (dependents and dependents[initializer])
        end)
    end

    -- Model IDs and default distances require showing model frames, so cache them until the model changes.
    local modelInfoCache = {}
    local function modelInfo(kind)
        local info = modelInfoCache[kind]
        if info then return info.id, info.default end
        local id, default = addon:getModelAdjustmentInfo(kind)
        if id then modelInfoCache[kind] = {id = id, default = default} end
        return id, default
    end

    local function refreshModels()
        wipe(modelInfoCache)
        for _, variable in ipairs(modelVariables) do Settings.NotifyUpdate(variable) end
        refreshFrames(function(initializer) return modelControls[initializer] end)
    end

    function addon:refreshSettings()
        wipe(modelInfoCache)
        for cvar, watch in pairs(watchedCVars) do watch.value = C_CVar.GetCVar(cvar) end
        for _, variable in ipairs(variables) do Settings.NotifyUpdate(variable) end
        refreshFrames()
    end

    reset = T.createSettingsResetManager(function() addon:refreshSettings() end)
    function addon:settingsChanged(keys)
        local undoChanged = reset:invalidate(keys)
        for _, key in ipairs(keys) do
            if key:sub(1, 6) ~= "model:" then return self:refreshSettings() end
        end
        for _, variable in ipairs(modelVariables) do Settings.NotifyUpdate(variable) end
        refreshAffected(undoChanged)
    end

    -- CVAR_UPDATE fires synchronously, so suppress it for our own writes.
    local writingCVar = false
    local function writeCVar(cvar, value)
        writingCVar = true
        local ok, err = pcall(C_CVar.SetCVar, cvar, value)
        writingCVar = false
        if not ok then error(err, 0) end
        local watch = watchedCVars[cvar]
        if watch then watch.value = C_CVar.GetCVar(cvar) end
    end

    local function watchCVar(cvar, variable, key, dependents)
        local watch = {cvar = cvar, value = C_CVar.GetCVar(cvar), variable = variable, key = key, dependents = dependents}
        watchedCVars[cvar] = watch
        watchedByName[cvar:lower()] = watch
    end

    local function own(initializer, ...)
        owned[initializer] = true
        initializer:AddSearchTags("Auto-Camera", "camera", ...)
        return initializer
    end

    local function header(targetLayout, name)
        targetLayout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
    end

    local function proxy(targetCategory, key, name, variableType, default, get, set, scope, dependents)
        local variable = "AUTO_CAMERA_" .. key
        local setting = Settings.RegisterProxySetting(targetCategory, variable, variableType, name, default, get, function(value)
            -- Blizzard notifies this setting after the write; only refresh what depends on it.
            local undoChanged = scope and reset:invalidate({type(scope) == "function" and scope() or scope})
            set(value)
            refreshAffected(undoChanged, dependents)
        end)
        variables[#variables + 1] = variable
        return setting, variable
    end

    local function slider(targetCategory, setting, tooltip, min, max, step)
        local options = Settings.CreateSliderOptions(min, max, step)
        local precision = 0
        while precision < 8 and math.abs(step * 10 ^ precision - math.floor(step * 10 ^ precision + 0.5)) > 0.000001 do
            precision = precision + 1
        end
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
            return string.format("%." .. precision .. "f", value)
        end)
        return own(Settings.CreateSlider(targetCategory, setting, options, tooltip), tooltip)
    end

    local function resetButton(targetLayout, name, scope, getEntries, canModify)
        local function currentScope()
            return type(scope) == "function" and scope() or scope
        end
        local initializer = CreateSettingsButtonInitializer(name, function()
            return reset:canUndo(currentScope()) and "Undo" or "Defaults"
        end, function()
            reset:toggle(currentScope(), getEntries())
        end, "Reset " .. name .. " settings to defaults. Undo is available until an affected setting changes or you reload or log out.", false)
        own(initializer, name, "defaults", "reset", "undo")
        if canModify then initializer:AddModifyPredicate(canModify) end
        targetLayout:AddInitializer(initializer)
        resetButtons[initializer] = true
        return initializer
    end

    local function zoomSetting(key, name, variableType)
        local scope = "general:" .. key
        local function get() return addon.db.global.general[key] end
        local function set(value) addon.db.global.general[key] = value end
        zoomEntries[#zoomEntries + 1] = {
            key = scope, get = get, set = set,
            reset = function() set(defaults.general[key]) end
        }
        return proxy(zoomCategory, key:upper(), name, variableType, defaults.general[key], get, set, scope)
    end

    header(layout, "General")
    slider(zoomCategory, zoomSetting("speedMultiplier", "Speed Multiplier", Settings.VarType.Number),
        "Additional zoom distance per unit of player speed.", 0, 0.5, 0.01)
    slider(zoomCategory, zoomSetting("bossEnemyDistance", "Distance Per Boss", Settings.VarType.Number),
        "Zoom distance used for nearby boss enemies.", 0, 50, 0.1)

    header(layout, "Pause / Resume")
    local bindingIndex = C_KeyBindings.GetBindingIndex("AUTO_CAMERA_TOGGLE_AUTO_ZOOM")
    assert(bindingIndex, "Auto-Camera: Toggle Auto-Zoom binding is unavailable")
    local binding = CreateKeybindingEntryInitializer(bindingIndex, true)
    own(binding, "Pause / Resume Key", "Toggle Auto-Zoom", "pause", "resume", "keybinding")
    layout:AddInitializer(binding)
    own(Settings.CreateCheckbox(zoomCategory, zoomSetting("pauseOnLoad", "Start Paused", Settings.VarType.Boolean),
        "Pause automatic camera zooming when you log in or reload."), "pause")
    local behavior = zoomSetting("pauseBehavior", "When Auto-Zoom Is Paused", Settings.VarType.String)
    local function behaviorOptions()
        local container = Settings.CreateControlTextContainer()
        container:Add("view", "Zoom to View")
        container:Add("doNothing", "Do Nothing")
        if tonumber(GetBuildInfo():match("^(%d+)")) >= 9 then
            container:Add("maxDistance", "Zoom to Maximum Distance")
        end
        return container:GetData()
    end
    local behaviorControl = own(Settings.CreateDropdown(zoomCategory, behavior, behaviorOptions,
        "Camera behavior while paused, including encounters and pet battles."), "pause")
    for _, view in ipairs({
        {"manualPauseView", "Manual Pause View", "Camera view to use when you pause automatic zooming."},
        {"instanceEncounterView", "Encounter View", "Camera view to use during an instance encounter."},
        {"petBattleView", "Pet Battle View", "Camera view to use during a pet battle."}
    }) do
        local control = slider(zoomCategory, zoomSetting(view[1], view[2], Settings.VarType.Number), view[3], 1, 5, 1)
        control:SetParentInitializer(behaviorControl, function() return addon.db.global.general.pauseBehavior == "view" end)
        control:AddSearchTags("pause")
    end

    header(layout, "Model Adjustments")
    zoomEntries[#zoomEntries + 1] = {
        key = "models",
        get = function() return addon.db.global.general.adjustments end,
        set = function(value) replaceContents(addon.db.global.general.adjustments, value) end,
        reset = function() replaceContents(addon.db.global.general.adjustments, {}) end
    }
    for _, kind in ipairs({"character", "mount"}) do
        local label = kind == "character" and "Current Character" or "Current Mount"
        local function modelDefault()
            local _, value = modelInfo(kind)
            return value
        end
        local function available() return modelInfo(kind) ~= nil end
        local function modelScope()
            local id = modelInfo(kind)
            return "model:" .. tostring(id)
        end
        local setting, variable = proxy(zoomCategory, kind:upper() .. "_DISTANCE", label .. " Distance", Settings.VarType.Number,
            modelDefault, function()
                local id, default = modelInfo(kind)
                return (id and addon.db.global.general.adjustments[id]) or default
            end, function(value)
                local id, default = modelInfo(kind)
                if id then
                    addon.db.global.general.adjustments[id] = value ~= default and value or nil
                end
            end, modelScope)
        modelVariables[#modelVariables + 1] = variable
        local control = slider(zoomCategory, setting,
            "Zoom distance for the current model. Available once the model is loaded; mount distance requires a mount. Defaults removes the saved override.", 0, 50, 0.1)
        control:AddModifyPredicate(available)
        modelControls[control] = true
        modelControls[resetButton(layout, label .. " Distance", modelScope, function()
            local id = modelInfo(kind)
            return {{
                key = modelScope(),
                get = function() return addon.db.global.general.adjustments[id] end,
                set = function(value) addon.db.global.general.adjustments[id] = value end,
                reset = function() addon.db.global.general.adjustments[id] = nil end
            }}
        end, available)] = true
    end
    resetButton(layout, "Auto Zoom", "zoom", function() return zoomEntries end)

    header(actionLayout, "Requirements")
    for _, info in ipairs({
        {"CameraKeepCharacterCentered", "Keep Character Centered", "Disables Action Camera effects while checked. This is independent of Reduce Camera Motion; Blizzard's Motion Sickness checkbox changes both."},
        {"CameraReduceUnexpectedMovement", "Reduce Camera Motion", "Reduces unexpected camera movement independently of character centering. Blizzard's Motion Sickness checkbox changes both."}
    }) do
        local cvar = info[1]
        if C_CVar.GetCVarDefault(cvar) ~= nil then
            local function get() return C_CVar.GetCVar(cvar) == "1" end
            -- Accessibility preferences are shared with Blizzard and are not reset here.
            local dependents = cvar == "CameraKeepCharacterCentered" and centeringDependents or nil
            local setting, variable = proxy(actionCategory, cvar:upper(), info[2], Settings.VarType.Boolean, get, get,
                function(value) writeCVar(cvar, value and "1" or "0") end, nil, dependents)
            own(Settings.CreateCheckbox(actionCategory, setting, info[3]), info[3], "motion sickness", "accessibility")
            watchCVar(cvar, variable, nil, dependents)
        end
    end
    local promptKey = "action:suppressExperimentalCVarPrompt"
    local function getPrompt() return addon.db.global.actionCam.suppressExperimentalCVarPrompt end
    local function setPrompt(value)
        addon.db.global.actionCam.suppressExperimentalCVarPrompt = value
        if value then addon:setupExperimentalPromptSuppression() end
    end
    local prompt = proxy(actionCategory, "SUPPRESS_EXPERIMENTAL_PROMPT", "Suppress Experimental Warning", Settings.VarType.Boolean,
        false, getPrompt, setPrompt, promptKey)
    own(Settings.CreateCheckbox(actionCategory, prompt, "Hide the game's experimental Action Camera warning."), "warning", "experimental")
    actionEntries[#actionEntries + 1] = {key = promptKey, get = getPrompt, set = setPrompt, reset = function() setPrompt(false) end}

    local cvars = {}
    for _, cvar in ipairs(T.actionCamCVars) do cvars[#cvars + 1] = cvar end
    table.sort(cvars)
    for _, section in ipairs(actionSections) do
        local entries = {}
        local sectionStarted = false
        for _, cvar in ipairs(cvars) do
            local group = "advanced"
            for _, candidate in ipairs(actionSections) do
                if candidate.prefix and cvar:sub(1, #candidate.prefix) == candidate.prefix then
                    group = candidate.key
                    break
                end
            end
            local default = C_CVar.GetCVarDefault(cvar)
            if group == section.key and default ~= nil then
                if not sectionStarted then header(actionLayout, section.name); sectionStarted = true end
                local metadata = actionControls[cvar]
                local name = metadata and metadata[1] or T.capitalize(T.splitCamelCase(cvar:gsub("^test_camera", "")))
                local tooltip = (metadata and metadata[2] or "Advanced experimental camera control.") ..
                    " CVar: " .. cvar .. ". Requires Keep Character Centered to be unchecked."
                local isBoolean = metadata and metadata.boolean
                local variableType = isBoolean and Settings.VarType.Boolean or
                    (tonumber(default) and Settings.VarType.Number or Settings.VarType.String)
                local function convert(value)
                    if isBoolean then return tonumber(value) == 1 end
                    if variableType == Settings.VarType.Number then return assert(tonumber(value), "Auto-Camera: nonnumeric CVar " .. cvar) end
                    return value
                end
                local function get() return convert(C_CVar.GetCVar(cvar)) end
                local function set(value)
                    local stored = type(value) == "boolean" and (value and "1" or "0") or tostring(value)
                    addon.db.global.actionCam[cvar] = stored
                    writeCVar(cvar, stored)
                end
                local scope = "cvar:" .. cvar
                local setting, variable = proxy(actionCategory, cvar:upper(), name, variableType, convert(default), get, set, scope)
                local control
                if isBoolean then
                    control = own(Settings.CreateCheckbox(actionCategory, setting, tooltip), tooltip)
                elseif variableType == Settings.VarType.Number then
                    local min = metadata and metadata[3] or 0
                    local max = metadata and metadata[4] or T.getOrderOfMagnitude(tonumber(default) ~= 0 and math.abs(tonumber(default)) or 0.1) * 10
                    min, max = math.min(min, get(), tonumber(default)), math.max(max, get(), tonumber(default))
                    control = slider(actionCategory, setting, tooltip, min, max, metadata and metadata[5] or (max - min) / 100)
                else
                    control = CreateSettingsButtonInitializer(name, "Edit Value", function()
                        StaticPopup_Show("AUTO_CAMERA_EDIT_SETTING", name, nil, {setting = setting})
                    end, tooltip, false)
                    own(control, name, tooltip)
                    actionLayout:AddInitializer(control)
                end
                control:AddSearchTags("actioncam", "action cam", "Action Camera", section.name, cvar, tooltip)
                control:AddModifyPredicate(function() return addon:cameraCharacterCenteringDisabled() end)
                control:AddEvaluateStateCVar("CameraKeepCharacterCentered")
                centeringDependents[control] = true
                entries[#entries + 1] = {
                    key = scope,
                    get = function()
                        return {live = get(), saved = rawget(addon.db.global.actionCam, cvar)}
                    end,
                    set = function(value)
                        set(value.live)
                        addon.db.global.actionCam[cvar] = value.saved
                    end,
                    reset = function() set(convert(C_CVar.GetCVarDefault(cvar))) end
                }
                watchCVar(cvar, variable, scope)
            end
        end
        if #entries > 0 then
            append(actionEntries, entries)
            centeringDependents[resetButton(actionLayout, section.name, "action:" .. section.key, function() return entries end,
                function() return addon:cameraCharacterCenteringDisabled() end)] = true
        end
    end
    centeringDependents[resetButton(actionLayout, "Action Camera", "action", function() return actionEntries end,
        function() return addon:cameraCharacterCenteringDisabled() end)] = true

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("CVAR_UPDATE")
    frame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
    frame:SetScript("OnEvent", function(_, event, name)
        if reset.applying then return end
        if event == "CVAR_UPDATE" then
            if writingCVar then return end
            local watch = type(name) == "string" and watchedByName[name:lower()]
            if not watch then return end
            local value = C_CVar.GetCVar(watch.cvar)
            if value == watch.value then return end
            watch.value = value
            local undoChanged = watch.key and reset:invalidate({watch.key})
            Settings.NotifyUpdate(watch.variable)
            refreshAffected(undoChanged, watch.dependents)
        else
            wipe(modelInfoCache)
            -- Model owners update their frames during these same events.
            C_Timer.After(0, refreshModels)
        end
    end)
    SettingsPanel:HookScript("OnShow", function() wipe(modelInfoCache) end)
    EventRegistry:RegisterCallback("Settings.CategoryDefaulted", function(_, defaultedCategory)
        local entries = defaultedCategory == zoomCategory and zoomEntries or
            (defaultedCategory == actionCategory and actionEntries)
        if entries then
            for _, entry in ipairs(entries) do reset:invalidate({entry.key}) end
            if defaultedCategory == zoomCategory then replaceContents(addon.db.global.general.adjustments, {}) end
            addon:refreshSettings()
        end
    end, addon)
    EventRegistry:RegisterCallback("Settings.Defaulted", function()
        for _, entries in ipairs({zoomEntries, actionEntries}) do
            for _, entry in ipairs(entries) do reset:invalidate({entry.key}) end
        end
        replaceContents(addon.db.global.general.adjustments, {})
        addon:refreshSettings()
    end, addon)
    Settings.RegisterAddOnCategory(category)
end
