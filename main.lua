local addonName, T = ...
AutoCamera = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceTimer-3.0")
local addon = AutoCamera
local baseZoomDistance = 0.5
local modelZoomMultiplier = 1.7
local AUTO_ZOOM_PAUSED = false
local IN_PET_BATTLE = false
local HAS_CLIMBING_GEAR = false
local IN_ENCOUNTER = false
local IN_BARBER_SHOP = false
local IN_HUD_EDIT_MODE = false
local IN_RAID = false
local IN_DUNGEON = false
local PAUSE_BEHAVIOR_HANDLED = true
local IS_ADJUSTING = false
local adjustmentFrame = nil
local scrollDebounceTimer = nil
local scrollHandlerFrame
local zoomInKeys = {}
local zoomOutKeys = {}
local viewNextKeys = {}
local viewPrevKeys = {}
local viewSetKeys = {} -- key -> view number (1-5)
local previousCameraZoom = GetCameraZoom()
local previousPosition = nil
local previousTime = nil
local previousSpeed = 0
local deltaTime = 0.1
local playerRace = UnitRace("player")
local maxZoomDistance = 50
local xpac = tonumber(string.match(GetBuildInfo(), "([0-9]+)\..*"))
local xpacs = {
    classic = 1,
    bcc = 2,
    wolc = 3,
    cata = 4,
    mop = 5,
    wod = 6,
    leg = 7,
    boa = 8,
    sl = 9
}
local unitClassificationMaxDistance = {
    trivial = {
        min = 0,
        max = 5
    },
    minus = {
        min = 0,
        max = 2
    }
}
-- Fallback distances used when SetUnit fails on restricted maps (dungeons/raids/delves)
-- because enemy unit identities are classified (RequiresDeclassifiedUnitIdentity).
local unitClassificationFallbackDistance = {
    worldboss  = nil, -- handled separately via settings.general.bossEnemyDistance
    rareelite  = 10,
    elite      = 8,
    rare       = 6,
}

-- debug flags
local SHOW_MOUNT_FRAME = false
local SHOW_CHARACTER_FRAME = false

local function logFrameCamPosZToWorldZoom(z)
    return ((math.log(z - 0.2)/math.log(10)) * 4) + 5.5
end

local function logFrameCamPosWorldZoom(x, y, z)
    return ((math.log(math.sqrt((x*x) + (y*y) + (z*z)) - 0.2)/math.log(10)) * 4) + 5.5
end

local function linearFrameCamPosToWorldZoom(x, y, z)
    return math.sqrt((x*x) + (y*y) + (z*z)) * modelZoomMultiplier + baseZoomDistance
end

-- uses the player model frame displaying the current player model to create a default zoom distance
-- todo> investigate ZMobDB which provides model dimensions https://www.wowinterface.com/forums/showthread.php?t=34898
local function getCharacterZoomDefault()
    -- use best-fit curve function to estimate zoom distance based on model frame default camera position
    T.playerModelFrame:Show()
    local distance = linearFrameCamPosToWorldZoom(T.playerModelFrame:GetCameraPosition())
    if not SHOW_CHARACTER_FRAME then
        T.playerModelFrame:Hide()
    end
    -- if frame camera distance is 0
    if (distance == baseZoomDistance) then distance = distance + 10 end

    return distance
end

local function GetCurrentMountId()
    local mountIDs = C_MountJournal.GetMountIDs()
    for _, mountID in ipairs(mountIDs) do
        local _, _, _, isActive = C_MountJournal.GetMountInfoByID(mountID)
        if isActive then
            return mountID
        end
    end
    return nil
end

-- Returns derived speed using map coordinates and time, falling back to GetUnitSpeed in instances
local function GetDerivedSpeed()
    -- GetUnitSpeed works everywhere including raids/dungeons where UnitPosition returns nil.
    -- In combat, the return value is "secret" and can't be compared by tainted code, so use pcall.
    local unitSpeed = 0
    pcall(function()
        local s = GetUnitSpeed("player")
        if s and s > 0 then unitSpeed = s end
    end)
    if unitSpeed > 0 then
        if unitSpeed < 50 then
            previousSpeed = unitSpeed
            return unitSpeed
        else
            return previousSpeed
        end
    end

    local x, y, z = UnitPosition("player")
    local currentTime = GetTime()
    local currentSpeed = 0

    if previousPosition and previousTime and x and y and z then
        local dx = x - previousPosition.x
        local dy = y - previousPosition.y
        local dz = z - previousPosition.z
        local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
        local elapsed = currentTime - previousTime
        if elapsed > 0 then
            currentSpeed = distance / elapsed -- yards per second
        end
    end

    previousTime = currentTime
    if x and y and z then
        previousPosition = {x = x, y = y, z = z}
    end

    if currentSpeed < 50 then
        previousSpeed = currentSpeed
        return currentSpeed
    else
        -- filter spikes from things like teleports
        return previousSpeed
    end
end

-- uses DressUpModel to display the mount and get its camera position
local function getMountZoomDefault()
    local x, y, z = T.playerMountModelFrame:GetCameraPosition()
    local distance = linearFrameCamPosToWorldZoom(x, y, z)
    if (distance == baseZoomDistance) then distance = distance + 10 end
    return distance
end

-- Reads CAMERAZOOMIN/CAMERAZOOMOUT bindings and enables/disables the appropriate
-- input handlers on scrollHandlerFrame so we only intercept genuine zoom inputs.
local function updateZoomKeyBindings()
    wipe(zoomInKeys)
    wipe(zoomOutKeys)
    wipe(viewNextKeys)
    wipe(viewPrevKeys)
    wipe(viewSetKeys)
    local k1, k2 = GetBindingKey("CAMERAZOOMIN")
    local k3, k4 = GetBindingKey("CAMERAZOOMOUT")
    if k1 then zoomInKeys[k1] = true end
    if k2 then zoomInKeys[k2] = true end
    if k3 then zoomOutKeys[k3] = true end
    if k4 then zoomOutKeys[k4] = true end

    local kn1, kn2 = GetBindingKey("NEXTVIEW")
    local kp1, kp2 = GetBindingKey("PREVVIEW")
    if kn1 then viewNextKeys[kn1] = true end
    if kn2 then viewNextKeys[kn2] = true end
    if kp1 then viewPrevKeys[kp1] = true end
    if kp2 then viewPrevKeys[kp2] = true end
    for i = 1, 5 do
        local ks1, ks2 = GetBindingKey("SETVIEW" .. i)
        if ks1 then viewSetKeys[ks1] = i end
        if ks2 then viewSetKeys[ks2] = i end
    end

    if not scrollHandlerFrame then return end

    local hasScrollBinding = false
    local hasKeyboardBinding = false
    local hasAnyBinding = k1 or k2 or k3 or k4
    for key in pairs(zoomInKeys) do
        if T.isScrollKey(key) then hasScrollBinding = true else hasKeyboardBinding = true end
    end
    for key in pairs(zoomOutKeys) do
        if T.isScrollKey(key) then hasScrollBinding = true else hasKeyboardBinding = true end
    end
    for key in pairs(viewNextKeys) do
        if T.isScrollKey(key) then hasScrollBinding = true else hasKeyboardBinding = true end
    end
    for key in pairs(viewPrevKeys) do
        if T.isScrollKey(key) then hasScrollBinding = true else hasKeyboardBinding = true end
    end
    for key in pairs(viewSetKeys) do
        if T.isScrollKey(key) then hasScrollBinding = true else hasKeyboardBinding = true end
    end

    -- Enable mouse wheel when scroll is a zoom/view binding, or as a fallback when nothing is bound.
    scrollHandlerFrame:EnableMouseWheel(hasScrollBinding or not hasAnyBinding)
    -- Enable keyboard capture (with propagation) only when a non-scroll key is bound to zoom/view.
    scrollHandlerFrame:EnableKeyboard(hasKeyboardBinding)
    scrollHandlerFrame:SetPropagateKeyboardInput(hasKeyboardBinding)
end

local settings = T.defaultSettings()
local units = {}
units[1] = {name = 'target', distance = 0}
for i = 1, 10 do
    units[i + 1] = {name = 'nameplate' .. i, distance = 0}
end

BINDING_HEADER_AUTO_CAMERA = "Auto-Camera"
BINDING_NAME_AUTO_CAMERA_TOGGLE_AUTO_ZOOM = "Pause / Resume Key"

function addon:OnEnable()
    if self.settingsMigrationFailed then return end
    self:ScheduleRepeatingTimer("autoZoom", 0.1)
end

function addon:isRunning() 
    return
        not self.settingsMigrationFailed and
        not AUTO_ZOOM_PAUSED and
        not IN_ENCOUNTER and
        not IN_PET_BATTLE and
        not IN_BARBER_SHOP and
        not IN_HUD_EDIT_MODE and
        not HAS_CLIMBING_GEAR and
        not IS_ADJUSTING
end

function addon:loadSettings()
    settings = addon.db.global
end

-- addon hook callback functions
function addon:OnInitialize()
    -- Migrate raw data before AceDB injects defaults into the old layout.
    local success, reason = pcall(function()
        AutoCameraDB = AutoCameraDB or {}
        AutoCameraDB.global = AutoCameraDB.global or {}
        T.migrateSettings(AutoCameraDB.global)
    end)
    if not success then
        AutoCameraDB = {}
        print("Auto-Camera failed to migrate existing configuration. Defaults have been restored.")
        print("Auto-Camera: " .. tostring(reason))
    end
    addon.db = LibStub("AceDB-3.0"):New("AutoCameraDB", {global = T.defaultSettings()}, true)
    addon:loadSettings()
    T.setupSettingsPanel(addon)

    AUTO_ZOOM_PAUSED = settings.general.pauseOnLoad

    -- setup experimental feature prompt suppression if configured
    if (settings.actionCam.suppressExperimentalCVarPrompt) then
        addon:setupExperimentalPromptSuppression()
    end
end

-- setup frame to suppress the experimental feature warning popup+
function addon:setupExperimentalPromptSuppression()
    if self.experimentalPromptFrame then return end
    local suppressionFrame = CreateFrame("Frame")
    self.experimentalPromptFrame = suppressionFrame
    suppressionFrame:RegisterEvent("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")
    suppressionFrame:SetScript("OnEvent", function(self, event)
        if event == "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED" and settings.actionCam.suppressExperimentalCVarPrompt then
            -- hide the popup immediately when it appears
            StaticPopup_Hide("EXPERIMENTAL_CVAR_WARNING")
        end
    end)
end

-- helper functions
function addon:toggleAutoZoom()
    if self.settingsMigrationFailed then self:showMigrationRecovery(); return end
    if (AUTO_ZOOM_PAUSED) then
        AUTO_ZOOM_PAUSED = false
        addon:autoZoom()
    else
        AUTO_ZOOM_PAUSED = true
    end
end

function addon:pauseAutoZoom()
    if self.settingsMigrationFailed then self:showMigrationRecovery(); return end
    print("Auto-Camera paused")
    AUTO_ZOOM_PAUSED = true
end

function addon:resumeAutoZoom()
    if self.settingsMigrationFailed then self:showMigrationRecovery(); return end
    print("Auto-Camera resumed")
    AUTO_ZOOM_PAUSED = false
    if addon:isRunning() then
        addon:autoZoom()
    end
end

local function getAdjustment(frame)
    frame:Show()
    local id = frame:GetModelFileID()

    if (id == nil) then
        frame:Hide()
        return nil
    end

    local adjustment = settings.general.adjustments[id]
    frame:Hide()
    return adjustment
end

local function setAdjustment(frame, adjustment)
    frame:Show()
    local id = frame:GetModelFileID()

    if (id == nil) then
        frame:Hide()
        return
    end

    settings.general.adjustments[id] = adjustment
    addon:settingsChanged({"model:" .. id})
    frame:Hide()
end

function addon:getModelAdjustmentInfo(kind)
    local frame = kind == "character" and T.playerModelFrame or T.playerMountModelFrame
    if not frame then return nil, 0 end
    if kind == "mount" and not IsMounted() then return nil, 0 end
    local wasShown = frame:IsShown()
    frame:Show()
    local id = frame:GetModelFileID()
    if not id or id == 0 then
        if not wasShown then frame:Hide() end
        return nil, 0
    end
    local default = kind == "character" and getCharacterZoomDefault() or getMountZoomDefault()
    frame:SetShown(wasShown)
    return id, default
end

function addon:autoZoom()
    if self.settingsMigrationFailed then return end
    if (not addon:isRunning()) then
        if (not PAUSE_BEHAVIOR_HANDLED) then
            MoveViewInStop()
            MoveViewOutStop()
            if AUTO_ZOOM_PAUSED then
                if (settings.general.pauseBehavior == "view") then
                    SetView(settings.general.manualPauseView)
                elseif (settings.general.pauseBehavior == "maxDistance") then
                    CameraZoomOut(maxZoomDistance)
                end
            elseif IN_ENCOUNTER or HAS_CLIMBING_GEAR then
                if (settings.general.pauseBehavior == "view") then
                    SetView(settings.general.instanceEncounterView)
                elseif (settings.general.pauseBehavior == "maxDistance") then
                    CameraZoomOut(maxZoomDistance)
                end
            elseif IN_PET_BATTLE then
                if (settings.general.pauseBehavior == "view") then
                    SetView(settings.general.petBattleView)
                elseif (settings.general.pauseBehavior == "maxDistance") then
                    CameraZoomOut(maxZoomDistance)
                end
            end
    
            PAUSE_BEHAVIOR_HANDLED = true
        end

        return
    end

    local targetZoom
    local currentCameraZoom = GetCameraZoom()
    local unit
    local enemyCount = 0

    PAUSE_BEHAVIOR_HANDLED = false

    local prevTargetZoom = targetZoom
    
    if (T.findAuraByName("Running Wild", "player") == nil and IsMounted("player")) then
        targetZoom = getAdjustment(T.playerMountModelFrame) or getMountZoomDefault()
    else
        targetZoom = getAdjustment(T.playerModelFrame) or getCharacterZoomDefault()
    end

    if (settings.general.speedMultiplier > 0) then
        targetZoom = targetZoom + GetDerivedSpeed() * settings.general.speedMultiplier
    end

    for _, unit in pairs(units) do
        local unitClassification = UnitClassification(unit.name)
        local unitClassificationDistanceRange = unitClassificationMaxDistance[unitClassification]
        
        if (
            not UnitIsDead(unit.name) and
            UnitCanAttack("player", unit.name) and
            (InCombatLockdown() or CheckInteractDistance(unit.name, 1)) and
            (unit.name == 'target' or not UnitIsUnit('target', unit.name)) -- if unit is target or a unit with nameplate that isn't the target (avoids counting target twice)
        ) then
            if (unitClassification == "worldboss") then
                unit.distance = settings.general.bossEnemyDistance
            else
                unit.frame:Show()
                unit.frame:ClearModel()
                local setUnitSuccess = unit.frame:SetUnit(unit.name)
                if setUnitSuccess then
                    unit.distance = linearFrameCamPosToWorldZoom(unit.frame:GetCameraPosition())
                else
                    -- SetUnit returns nil on restricted maps (dungeons/raids/delves) because
                    -- enemy unit identities are classified (RequiresDeclassifiedUnitIdentity).
                    -- Fall back to a classification-based estimate.
                    unit.distance = unitClassificationFallbackDistance[unitClassification] or 5
                end
                unit.frame:Hide()

                -- clamp distance to unit classification range
                if (unitClassificationDistanceRange ~= nil) then
                    if (unitClassificationDistanceRange.min > unit.distance) then
                        unit.distance = unitClassificationDistanceRange.min
                    end
                    if (unitClassificationDistanceRange.max < unit.distance) then
                        unit.distance = unitClassificationDistanceRange.max
                    end
                end
            end
        else
            unit.distance = 0
        end
    end

    table.sort(units, function(a, b)
        return a.distance > b.distance
    end)

    targetZoom = targetZoom + units[1].distance

    local distanceDiff = targetZoom - currentCameraZoom
    
    -- todo fix over-zoom bug
    if (abs(distanceDiff) > 0.1) then
        local cameraZoomSpeed = distanceDiff / tonumber(GetCVar("cameraZoomSpeed"))
        if (cameraZoomSpeed < 0) then cameraZoomSpeed = cameraZoomSpeed * -1 end
        if (distanceDiff > 0) then
            MoveViewInStart(0)
            MoveViewOutStart(cameraZoomSpeed)
        else
            MoveViewOutStart(0)
            MoveViewInStart(cameraZoomSpeed)
        end
    else
        MoveViewInStop()
        MoveViewOutStop()
    end

    previousCameraZoom = currentCameraZoom
end

function addon:applyActionCamSettings() 
    for index, CVar in pairs(T.actionCamCVars) do
        C_CVar.SetCVar(CVar, settings.actionCam[CVar])
    end
end

function addon:storeActionCamSettings() 
    for index, CVar in pairs(T.actionCamCVars) do
        settings.actionCam[CVar] = C_CVar.GetCVar(CVar, settings.actionCam[CVar])
    end
end

function addon:cameraCharacterCenteringEnabled()
    return C_CVar.GetCVar("CameraKeepCharacterCentered") == "1"
end

function addon:cameraCharacterCenteringDisabled()
    return not self:cameraCharacterCenteringEnabled()
end

-- -- data
-- local data = {
--     x = '',
--     z = '',
--     y = '',
--     mag = '',
--     xyz = '',
-- }

-- local position = -600

-- for name, _ in pairs(data) do
--     local box = CreateFrame("ScrollFrame", nil, 
--     UIParent, "InputScrollFrameTemplate")
--     data[name] = box
--     box:SetSize(280,300)
--     box:SetPoint("CENTER", UIParent, "CENTER", position, 0)
--     box.EditBox:SetFontObject("ChatFontNormal")
--     box.EditBox:SetMaxLetters(999999999)
--     box.EditBox:SetAutoFocus(false)
--     box.EditBox:SetWidth(200);
--     box.CharCount:Hide()
--     box.EditBox:SetScript("OnEscapePressed", function()
--         for name, box in pairs(data) do
--             box:Hide()
--         end
--     end)
--     box:Hide()
--     position = position + 300
-- end

-- commands
local yellow = "cffffff00"
local colorStart = "\124"
local colorEnd = "\124r"
SLASH_AC1 = "/ac"
SlashCmdList["AC"] = function(arg)
    if addon.settingsMigrationFailed then
        addon:showMigrationRecovery()
        return
    end
    if arg == "toggle" then
        addon:toggleAutoZoom()
    elseif (arg == "pause" or arg == "standby" or arg == "stand-by") then
        addon:pauseAutoZoom()
    elseif (arg == "resume") then
        addon:resumeAutoZoom()
    elseif (arg == "settings" or arg == "options") then
        Settings.OpenToCategory(addon.settingsCategory:GetID())
    elseif (arg == "debug") then
        print(T.findAuraByName("Rock Climbing Gear", "player"))
    -- print(T.playerMountModelFrame:GetModelFileID())

        -- local x, y, z = T.targetModelFrame:GetCameraPosition()
        -- local x, y, z = T.targetModelFrame:GetCameraPosition()

        -- print("target class", UnitClassification("target"))
        -- print("target pos", x,y,z)
        -- local x, y, z = T.playerModelFrame:GetCameraPosition()
        -- print("player pos", x,y,z)

        -- local data2d = {x = x, z = z, y = y, mag = mag}

        -- for name, box in pairs(data) do
        --     box:Show()
        --     local text = box.EditBox:GetText()
        --     print(strlen(text) ~= 0)
        --     if (strlen(text) ~= 0) then text = text .. ',' end
        --     if (name == 'xyz') then
        --         box.EditBox:SetText(text .. "(" .. x .. ", " .. y .. ", " .. z .. ", " .. cameraZoom .. ")")
        --     else
        --         box.EditBox:SetText(text .. "(" .. data2d[name] .. ", " .. cameraZoom .. ")")
        --     end
        -- end
    else
        print(colorStart .. yellow .. "Auto-Camera console commands:" .. colorEnd)
        print("/ac toggle       " .. colorStart .. yellow .. "toggles pause on/off" .. colorEnd)
        print("/ac pause        " .. colorStart .. yellow .. "pauses auto-zoom (aliases: standby, stand-by)" .. colorEnd)
        print("/ac resume       " .. colorStart .. yellow .. "resumes auto-zoom" .. colorEnd)
        print("/ac settings    " .. colorStart .. yellow .. "opens Auto-Camera settings" .. colorEnd)
    end
end

-- events
local function OnEvent(self, event, ...)
    if addon.settingsMigrationFailed then return end
    addon[event](self, event, ...)
end

function addon:VARIABLES_LOADED()
    -- apply action cam settings
    if (addon:cameraCharacterCenteringDisabled()) then
        addon:applyActionCamSettings()
    end

    -- Saved bindings are now loaded; refresh zoom key detection.
    updateZoomKeyBindings()
end

function addon:PET_BATTLE_OPENING_START()
    IN_PET_BATTLE = true
end

function addon:PET_BATTLE_CLOSE()
    IN_PET_BATTLE = false
    if addon:isRunning() then
        addon:autoZoom()
    end
end

function addon:ENCOUNTER_START()
    IN_ENCOUNTER = true
end

function addon:ENCOUNTER_END()
    IN_ENCOUNTER = false
    if addon:isRunning() then
        addon:autoZoom()
    end
end

function addon:LFG_COMPLETION_REWARD()
    addon:ENCOUNTER_END()
end

function addon:PLAYER_ENTERING_WORLD()
    local mapId = C_Map.GetBestMapForUnit("player")
    if (mapId == nil) then return end -- TODO what do when this happens?
    local x, y = C_Map.GetPlayerMapPosition(mapId, "player")
    if x == nil and y == nil then -- if in an instance
        local _, instanceType = GetInstanceInfo()
        IN_RAID = instanceType == "raid"
        IN_DUNGEON = instanceType == "raid"
    end
end

function addon:BARBER_SHOP_OPEN()
    IN_BARBER_SHOP = true
end

function addon:AURA_DATA_PROVIDER_SWITCH(_, realData)
    IN_HUD_EDIT_MODE = not realData
end

function addon:BARBER_SHOP_CLOSE()
    IN_BARBER_SHOP = false

    if (addon:isRunning()) then
        addon:autoZoom()
    end
end

function addon:ADDON_LOADED(_, loadedAddonName)
    if loadedAddonName ~= addonName then return end
    T.playerModelFrame = CreateFrame("PlayerModel", nil, UIParent)
    T.playerModelFrame:SetUnit("player")
    T.playerModelFrame:SetSize(300, 300)
    T.playerModelFrame:ClearAllPoints()
    T.playerModelFrame:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
    T.playerModelFrame:SetFrameStrata("HIGH")
    if not SHOW_CHARACTER_FRAME then
        T.playerModelFrame:Hide()
    else
        T.playerModelFrame:Show()
    end

    T.playerMountModelFrame = CreateFrame("DressUpModel", nil, UIParent)
    T.playerMountModelFrame:SetSize(300, 300)
    T.playerMountModelFrame:ClearAllPoints()
    T.playerMountModelFrame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    T.playerMountModelFrame:SetFrameStrata("HIGH")
        T.playerMountModelFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
        T.playerMountModelFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        local lastMountID = nil
        T.playerMountModelFrame:SetScript("OnEvent", function(self, event)
            local updateMountFrame = function()
                local mountID = GetCurrentMountId()
                if mountID then
                    if lastMountID ~= mountID then
                        self:ClearModel() -- ensure previous model is cleared if mount changed
                    end
                    self:Show()
                    local displayID
                    local creatureDisplayInfoID = C_MountJournal.GetMountInfoExtraByID(mountID)
                    if creatureDisplayInfoID then
                        displayID = creatureDisplayInfoID
                    end
                    if not displayID then
                        return
                    end
                    self:SetDisplayInfo(displayID)
                    lastMountID = mountID
                    if not SHOW_MOUNT_FRAME then
                        self:Hide()
                    end
                else
                    -- Dismount: clear the frame and ensure no print
                    self:ClearModel()
                    self:Hide()
                    lastMountID = nil
                end
            end

            if event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
                updateMountFrame()
            elseif event == "PLAYER_ENTERING_WORLD" then
                addon:evaluateHasClimbingGear()
                if IsMounted("player") then
                    -- On login while mounted the mount journal may not be populated yet.
                    -- Poll until GetCurrentMountId() returns a value (max 20 attempts, ~1s).
                    local attempts = 0
                    local ticker
                    ticker = C_Timer.NewTicker(0.05, function()
                        attempts = attempts + 1
                        if GetCurrentMountId() then
                            ticker:Cancel()
                            updateMountFrame()
                        elseif attempts >= 20 then
                            ticker:Cancel()
                        end
                    end)
                else
                    updateMountFrame()
                end
            end
        end)
    if not SHOW_MOUNT_FRAME then
        T.playerMountModelFrame:Hide()
    else
        T.playerMountModelFrame:Show()
    end

    for _, unit in pairs(units) do
        unit.frame = CreateFrame("PlayerModel", nil, UIParent)
        unit.frame:Hide()
    end

    -- todo> playerModelFrame:RefreshUnit() -- https://www.wowinterface.com/forums/showthread.php?t=48394
    T.playerModelFrame:SetScript("OnEvent", function(self)
        self:Show()
        self:ClearModel()
        self:SetUnit("player")
        if (not SHOW_CHARACTER_FRAME) then
            self:Hide()
        end
    end)
    T.playerModelFrame:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", "player")

    -- Tracks manual zoom inputs (scroll or bound key) and debounces auto-zoom resumption.
    -- Only intercepts inputs that are actually bound to CAMERAZOOMIN/CAMERAZOOMOUT.
    scrollHandlerFrame = CreateFrame("Frame", nil, UIParent)
    scrollHandlerFrame:SetAllPoints(UIParent)
    scrollHandlerFrame:SetFrameStrata("BACKGROUND")

    -- Shared debounce logic: locks the context frame at the start of an adjustment so
    -- that a mount/dismount during the debounce window doesn't misattribute the adjustment.
    -- Adjustments are not saved when auto-zoom is paused or during encounters.
    local function handleZoomInput(frame)
        if not IS_ADJUSTING then
            IS_ADJUSTING = true
            adjustmentFrame = frame
        end
        if scrollDebounceTimer then
            addon:CancelTimer(scrollDebounceTimer)
        end
        scrollDebounceTimer = addon:ScheduleTimer(function()
            IS_ADJUSTING = false
            scrollDebounceTimer = nil
            if not AUTO_ZOOM_PAUSED and not IN_ENCOUNTER and not IN_PET_BATTLE and not HAS_CLIMBING_GEAR then
                setAdjustment(adjustmentFrame, GetCameraZoom())
            end
            adjustmentFrame = nil
            if addon:isRunning() then
                addon:autoZoom()
            end
        end, 0.5)
    end

    -- Like handleZoomInput but with a 3-second debounce, since camera views can
    -- take longer to finish transitioning to their zoom destination.
    local function handleViewInput(frame)
        if not IS_ADJUSTING then
            IS_ADJUSTING = true
            adjustmentFrame = frame
        end
        if scrollDebounceTimer then
            addon:CancelTimer(scrollDebounceTimer)
        end
        scrollDebounceTimer = addon:ScheduleTimer(function()
            IS_ADJUSTING = false
            scrollDebounceTimer = nil
            if not AUTO_ZOOM_PAUSED and not IN_ENCOUNTER and not IN_PET_BATTLE and not HAS_CLIMBING_GEAR then
                setAdjustment(adjustmentFrame, GetCameraZoom())
            end
            adjustmentFrame = nil
            if addon:isRunning() then
                addon:autoZoom()
            end
        end, 3.0)
    end

    local function currentZoomFrame()
        if T.findAuraByName("Running Wild", "player") == nil and IsMounted("player") then
            return T.playerMountModelFrame
        else
            return T.playerModelFrame
        end
    end

    scrollHandlerFrame:SetScript("OnMouseWheel", function(self, delta)
        local key = T.buildModifiedKey(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
        local noZoomBindings = not next(zoomInKeys) and not next(zoomOutKeys)
        local isZoomIn = zoomInKeys[key]
        local isZoomOut = zoomOutKeys[key]
        local isNextView = viewNextKeys[key]
        local isPrevView = viewPrevKeys[key]
        local setViewNum = viewSetKeys[key]

        -- A frame's OnMouseWheel consumes the scroll event, so WoW's key binding
        -- system will NOT fire for this input. We must invoke the appropriate
        -- action manually for any binding we recognise.
        if isNextView then
            handleViewInput(currentZoomFrame())
            NextView()
        elseif isPrevView then
            handleViewInput(currentZoomFrame())
            PrevView()
        elseif setViewNum then
            handleViewInput(currentZoomFrame())
            SetView(setViewNum)
        elseif isZoomIn then
            handleZoomInput(currentZoomFrame())
            CameraZoomIn(1)
        elseif isZoomOut then
            handleZoomInput(currentZoomFrame())
            CameraZoomOut(1)
        elseif noZoomBindings then
            -- Fallback: no zoom bindings configured; treat any scroll as zoom.
            handleZoomInput(currentZoomFrame())
            if delta > 0 then CameraZoomIn(1) else CameraZoomOut(1) end
        end
        -- else: unrecognised key while bindings exist; event is consumed but no action taken.
    end)

    -- Intercept non-scroll key zoom/view bindings. SetPropagateKeyboardInput ensures
    -- the actual action still fires via the normal binding system.
    scrollHandlerFrame:SetScript("OnKeyDown", function(self, key)
        local fullKey = T.buildModifiedKey(key)
        local isZoom = zoomInKeys[fullKey] or zoomOutKeys[fullKey]
        local isView = viewNextKeys[fullKey] or viewPrevKeys[fullKey] or viewSetKeys[fullKey]
        if not isZoom and not isView then
            return
        end
        if isView then
            handleViewInput(currentZoomFrame())
        else
            handleZoomInput(currentZoomFrame())
        end
    end)

    updateZoomKeyBindings()

    if (not AUTO_ZOOM_PAUSED) then
        addon:autoZoom()
    end
end

function addon:evaluateHasClimbingGear()
    if (T.findAuraByName("Rock Climbing Gear", "player") ~= nil) then
        HAS_CLIMBING_GEAR = true
    else
        HAS_CLIMBING_GEAR = false
    end
end

function addon:UNIT_AURA()
    addon:evaluateHasClimbingGear()
end

function addon:UPDATE_BINDINGS()
    updateZoomKeyBindings()
end

local f = CreateFrame("Frame")

local classicEvents = T.set {"PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE", "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_ENTERING_WORLD", "VARIABLES_LOADED", "ADDON_LOADED", "LFG_COMPLETION_REWARD", "UPDATE_BINDINGS", "AURA_DATA_PROVIDER_SWITCH"}
local wrathEvents = T.set {"BARBER_SHOP_OPEN", "BARBER_SHOP_CLOSE"}

for event in pairs(classicEvents) do
    f:RegisterEvent(event)
end

f:RegisterUnitEvent("UNIT_AURA", "player")

if (xpac >= xpacs.wolc) then
    for event in pairs(wrathEvents) do
        f:RegisterEvent(event)
    end
end

f:SetScript("OnEvent", OnEvent)
