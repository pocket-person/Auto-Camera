local addonName, T = ...
AutoCamera = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceTimer-3.0")
local addon = AutoCamera
local baseZoomDistance = 0.5
local modelZoomMultiplier = 1.7
local STAND_BY = false
local IN_PET_BATTLE = false
local HAS_CLIMBING_GEAR = false
local IN_ENCOUNTER = false
local IN_BARBER_SHOP = false
local IN_RAID = false
local IN_DUNGEON = false
local STAND_BY_BEHAVIOR_HANDLED = true
local IS_ADJUSTING = false
local scrollDebounceTimer = nil
local scrollHandlerFrame
local zoomInKeys = {}
local zoomOutKeys = {}
local previousCameraZoom = GetCameraZoom()
local previousPosition = nil
local previousTime = nil
local previousSpeed = 0
local deltaTime = 0.1
local previousSettings = {general = nil, actionCam = nil, actionCamGroups = {}} -- stores the previous settings when defaults are applied by the user
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

-- Returns derived speed using map coordinates and time
local function GetDerivedSpeed()
    local mapId = C_Map.GetBestMapForUnit("player")
    local currentSpeed = 0
    local currentTime = GetTime()
    local currentPosition = nil
    local mapWidth, mapHeight = nil, nil
    if mapId then
        local pos = C_Map.GetPlayerMapPosition(mapId, "player")
        if pos then
            local x, y = pos:GetXY()
            currentPosition = {x = x, y = y}
        end
        -- Get map size in yards
        if C_Map.GetMapWorldSize then
            local size = C_Map.GetMapWorldSize(mapId)
            if type(size) == "number" then
                mapWidth, mapHeight = size, size
            elseif type(size) == "table" then
                mapWidth, mapHeight = size[1], size[2]
            end
        end
    end

    if previousPosition and previousTime and currentPosition and mapWidth and mapHeight then
        local dx = (currentPosition.x - previousPosition.x) * mapWidth
        local dy = (currentPosition.y - previousPosition.y) * mapHeight
        local distance = math.sqrt(dx * dx + dy * dy)
        local elapsed = currentTime - previousTime
        if elapsed > 0 then
            currentSpeed = distance / elapsed -- yards per second
        end
    end

    previousTime = currentTime
    previousPosition = currentPosition
    if (currentSpeed < 50) then
        previousSpeed = currentSpeed

        if (currentSpeed == 0) then
            return GetUnitSpeed("player")
        end
        return currentSpeed
    else
        -- filter out spikes due to things like map changes and teleports
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
    local k1, k2 = GetBindingKey("CAMERAZOOMIN")
    local k3, k4 = GetBindingKey("CAMERAZOOMOUT")
    if k1 then zoomInKeys[k1] = true end
    if k2 then zoomInKeys[k2] = true end
    if k3 then zoomOutKeys[k3] = true end
    if k4 then zoomOutKeys[k4] = true end

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

    -- Enable mouse wheel when scroll is a zoom binding, or as a fallback when nothing is bound.
    scrollHandlerFrame:EnableMouseWheel(hasScrollBinding or not hasAnyBinding)
    -- Enable keyboard capture (with propagation) only when a non-scroll key is bound to zoom.
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
BINDING_NAME_TOGGLE_STAND_BY = "Toggle Auto-Zoom"
-- BINDING_NAME_ENTER_STAND_BY = "Pause Auto-Zoom"

function addon:OnEnable()
    self:ScheduleRepeatingTimer("autoZoom", 0.1)
end

function addon:isRunning() 
    return
        not STAND_BY and
        not IN_ENCOUNTER and
        not IN_PET_BATTLE and
        not IN_BARBER_SHOP and
        not HAS_CLIMBING_GEAR and
        not IS_ADJUSTING
end

function addon:loadSettings()
    settings = addon.db.global

    -- update settings if necessary
    if (settings.version ~= T.version) then
        addon:updateSettings(settings)
    end
end

function addon:updateSettings(settings)
    -- set default version if nil
    settings.version = settings.version or "0.0.0"

    for updateVersion, updateFunction in pairs(settingsUpdateMap) do
        -- run version structure conversion
        if (updateVersion > settings.version) then
            updateFunction(settings)
        end

        -- update version
        settings.version = updateVersion
    end

    T.deepMerge(settings, T.deepMerge(T.defaultSettings(), settings, true))

    settings.version = T.version
    return settings
end

-- addon hook callback functions
function addon:OnInitialize()
    local options = addon:options()
    addon.db = LibStub("AceDB-3.0"):New("AutoCameraDB", {global = T.defaultSettings()}, true)
    addon:loadSettings()
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, addonName)

    STAND_BY = settings.general.standByOnLoad

    -- disable experimental feature prompt if configured
    if (settings.actionCam.suppressExperimentalCVarPrompt) then
        UIParent:UnregisterEvent("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")
    end
end

-- helper functions
function addon:toggleStandBy()
    if (STAND_BY) then
        STAND_BY = false
        addon:autoZoom()
    else
        STAND_BY = true
    end
    LibStub("AceConfigRegistry-3.0"):NotifyChange("Auto-Camera")
end

function addon:enterStandBy()
    print("Entering Stand-By Mode")
    STAND_BY = true
end

function addon:exitStandBy()
    print("Exiting Stand-By Mode")
    STAND_BY = false
    if addon:isRunning() then
        addon:autoZoom()
    end
end

function getAdjustment(frame) 
    frame:Show()
    local id = frame:GetModelFileID()

    if (id == nil) then
        return nil
    end

    local adjustment = settings.general.adjustments[id]
    frame:Hide()
    return adjustment
end

function setAdjustment(frame, adjustment) 
    frame:Show()
    local id = frame:GetModelFileID()

    if (id == nil) then
        frame:Hide()
        return
    end

    settings.general.adjustments[id] = adjustment
    frame:Hide()
end

function addon:autoZoom()
    if (not addon:isRunning()) then
        if (not STAND_BY_BEHAVIOR_HANDLED) then
            MoveViewInStop()
            MoveViewOutStop()
            if STAND_BY then
                if (settings.general.standByBehavior == "view") then
                    SetView(settings.general.manualStandByView)
                elseif (settings.general.standByBehavior == "maxDistance") then
                    CameraZoomOut(maxZoomDistance)
                end
            elseif IN_ENCOUNTER or HAS_CLIMBING_GEAR then
                if (settings.general.standByBehavior == "view") then
                    SetView(settings.general.instanceEncounterView)
                elseif (settings.general.standByBehavior == "maxDistance") then
                    CameraZoomOut(maxZoomDistance)
                end
            elseif IN_PET_BATTLE then
                if (settings.general.standByBehavior == "view") then
                    SetView(settings.general.petBattleView)
                elseif (settings.general.standByBehavior == "maxDistance") then
                    CameraZoomOut(maxZoomDistance)
                end
            end
    
            STAND_BY_BEHAVIOR_HANDLED = true
        end

        return
    end

    local targetZoom
    local currentCameraZoom = GetCameraZoom()
    local unit
    local enemyCount = 0

    STAND_BY_BEHAVIOR_HANDLED = false

    local prevTargetZoom = targetZoom
    
    if (AuraUtil.FindAuraByName("Running Wild", "player") == nil and IsMounted("player")) then
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
                unit.frame:SetUnit(unit.name)
                unit.distance = linearFrameCamPosToWorldZoom(unit.frame:GetCameraPosition())
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

local function viewOption()
    return {
        type = 'range',
        min = 1,
        max = 5,
        step = 1
    }
end

local function distanceOption()
    return {
        type = 'range',
        min = 0,
        max = maxZoomDistance,
        step = 0.1,
        order = 3
    }
end

local function toggleGroupDefaultsOption(group)
    return {
        type = "execute",
        name = function()
            if (previousSettings.actionCamGroups[group] == nil) then
                return "Defaults"
            else
                return "Undo"
            end
        end,
        func = function()
            addon:toggleActionCamGroupDefaults(group)
        end,
        order = 99,
        desc = "Apply Blizzard defaults for this group"
    }
end

function addon:toggleGeneralDefaults()
    if (previousSettings.general == nil) then
        previousSettings.general = T.deepCopy(settings.general)
        T.deepMerge(settings.general, T.defaultSettings().general)
    else
        T.deepMerge(settings.general, previousSettings.general)
        previousSettings.general = nil
    end
end

function addon:toggleActionCamDefaults()
    -- todo> motion sickness
    if (previousSettings.actionCam == nil) then
        previousSettings.actionCam = T.deepCopy(settings.actionCam)
        T.deepMerge(settings.actionCam, T.defaultSettings().actionCam)
    else
        T.deepMerge(settings.actionCam, previousSettings.actionCam)
        previousSettings.actionCam = nil
    end
    addon:applyActionCamSettings()
end

function addon:toggleActionCamGroupDefaults(group)
    -- create list of CVar relevant to provided group
    local actionCamGroupCVars = {}
    for index, CVar in pairs(T.actionCamCVars) do
        if (CVar:find(T.capitalize(group))) then
            table.insert(actionCamGroupCVars, CVar)
        end
    end

    if (previousSettings.actionCamGroups[group] == nil) then
        -- store current group settings and apply defaults
        previousSettings.actionCamGroups[group] = {}
        for index, CVar in pairs(actionCamGroupCVars) do
            previousSettings.actionCamGroups[group][CVar] = C_CVar.GetCVar(CVar)
            settings.actionCam[CVar] = C_CVar.GetCVarDefault(CVar)
        end
    else
        -- apply previous group settings and clear previous group settings storage
        for index, CVar in pairs(actionCamGroupCVars) do
            settings.actionCam[CVar] = previousSettings.actionCamGroups[group][CVar]
        end
        previousSettings.actionCamGroups[group] = nil
    end
    addon:applyActionCamSettings()
end

function addon:cameraCharacterCenteringEnabled()
    return C_CVar.GetCVar("CameraKeepCharacterCentered") == "1"
end

function addon:cameraCharacterCenteringDisabled()
    return not addon:cameraCharacterCenteringEnabled()
end

-- options
function addon:options()
    local options = {
        type = 'group',
        name = 'Auto-Camera',
        childGroups = "tab",
        args = {
            general = {
                type = 'group',
                name = 'Zoom',
                order = 1,
                set = function(info, value)
                    previousSettings.general = nil
                    settings.general[info[#info]] = value
                end,
                get = function(info) return settings.general[info[#info]] end,
                args = {
                    standBy = {
                        type = "group",
                        inline = true,
                        order = 1,
                        name = "Stand-By Mode",
                        args = {
                            toggleStandBy = {
                                type = "execute",
                                name = function()
                                    if (STAND_BY) then
                                        return "Exit Stand-By"
                                    else
                                        return "Enter Stand-By"
                                    end
                                end,
                                func = function() addon:toggleStandBy() end,
                                order = 1
                            },
                            standByOnLoad = {
                                type = "toggle",
                                name = "Load In Stand-By",
                                desc = "Controls if automatic camera zooming should be on stand-by on load",
                                order = 2
                            },
                            standByKeybinding = {
                                type = "keybinding",
                                name = "Toggle Key Binding",
                                desc = "Keybinding to toggle Stand-By Mode",
                                get = function()
                                    return GetBindingKey("TOGGLE_STAND_BY")
                                end,
                                set = function(info, value)
                                    local toggleStandByKey = GetBindingKey("TOGGLE_STAND_BY")
                                    if (toggleStandByKey) then
                                        SetBinding(toggleStandByKey) -- unbind current key
                                    end
                                    SetBinding(value, "TOGGLE_STAND_BY") -- bind toggle to entered key
                                    SaveBindings(2)
                                end,
                                order = 3
                            },
                            standByBehavior = {
                                type = "select",
                                name = "When Stand-By Is Activated",
                                order = 4,
                                values = {
                                    view = "Zoom to view",
                                    doNothing = "Do Nothing"
                                },
                                desc = "What the camera should do when Stand-By is activated"
                            },
                            spacer = {
                                type = "header",
                                name = "Stand-By Views",
                                order = 5,
                                hidden = function() return settings.general.standByBehavior ~= "view" end
                            },
                            manualStandByView = T.merge(viewOption(), {
                                name = 'Manual Stand-By View',
                                desc = 'The camera view to go to when toggling Auto-Camera off',
                                order = 6,
                                hidden = function() return settings.general.standByBehavior ~= "view" end
                            }),
                            instanceEncounterView = T.merge(viewOption(), {
                                name = 'Instance Encounter View',
                                desc = 'The camera view to go to during an encounter (e.g. boss battle)',
                                order = 7,
                                hidden = function() return settings.general.standByBehavior ~= "view" end
                            }),
                            petBattleView = T.merge(viewOption(), {
                                name = 'Pet Battle View',
                                desc = 'The camera view to go to during a pet battle.',
                                order = 8,
                                hidden = function() return settings.general.standByBehavior ~= "view" end
                            })
                        }
                    },
                    contextualDistances = {
                        type = "group",
                        inline = true,
                        order = 3,
                        name = "Contextual Camera Distances",
                        args = {
                            ridingDistance = T.merge(distanceOption(), {
                                name = 'Riding',
                                desc = 'Camera distance when riding on a mount or in a vehicle',
                                order = 1
                            }),
                            speedMultiplier = {
                                type = 'range',
                                name = 'Speed Multiplier',
                                desc = 'Multiplier for additional zoom distance based on player speed',
                                min = 0,
                                max = 0.5,
                                step = 0.01,
                                order = 2
                            },
                            bossEnemyDistance = T.merge(distanceOption(), {
                                name = 'Per Boss Enemy',
                                desc = 'Distance to add per boss enemy on screen near the player character',
                                order = 3
                            })
                        }
                    },
                    adjustments = {
                        type = "group",
                        inline = true,
                        order = 4,
                        name = "Adjustments",
                        args = {
                            character = {
                                type = "group",
                                name = "Character",
                                args = {
                                    distance = T.merge(distanceOption(), {
                                        name = "Distance",
                                        desc = "The zoom distance that should be used for the current character model.",
                                        width = "double",
                                        get = function()
                                            return getAdjustment(T.playerModelFrame) or getCharacterZoomDefault()
                                        end,
                                        set = function(info, value)
                                            if (value == getCharacterZoomDefault()) then
                                                -- todo> test this case
                                                setAdjustment(T.playerModelFrame, nil)
                                            else
                                                setAdjustment(T.playerModelFrame, value)
                                            end
                                        end,
                                        order = 1
                                    }),
                                    toggle = {
                                        type = "execute",
                                        name = "Default",
                                        func = function() settings.general.adjustments[T.playerModelFrame:GetModelFileID()] = nil end,
                                        order = 2
                                    }
                                }
                            },
                            mount = {
                                type = "group",
                                name = "Mount",
                                args = {
                                    distance = T.merge(distanceOption(), {
                                        name = "Distance",
                                        desc = "The zoom distance that should be used for the current mount.",
                                        width = "double",
                                        get = function()
                                            return getAdjustment(T.playerMountModelFrame) or getMountZoomDefault()
                                        end,
                                        set = function(info, value)
                                            if (value == getMountZoomDefault()) then
                                                setAdjustment(T.playerMountModelFrame, nil)
                                            else
                                                setAdjustment(T.playerMountModelFrame, value)
                                            end
                                        end,
                                        order = 1
                                    }),
                                    toggle = {
                                        type = "execute",
                                        name = "Default",
                                        func = function() settings.general.adjustments[T.playerMountModelFrame:GetModelFileID()] = nil end,
                                        order = 2
                                    }
                                }
                            }
                            -- todo: overrideTargetModel = {}
                            -- todo: overrideMountModel = {}
                        }
                    },
                    toggleDefaults = {
                        type = "execute",
                        name = function()
                            if (previousSettings.general == nil) then
                                return "Defaults"
                            else
                                return "Undo"
                            end
                        end,
                        func = function() addon:toggleGeneralDefaults() end,
                        order = 100
                    }
                }
            },
            actionCam = {
                type = 'group',
                name = 'Action',
                desc = 'Action Cam is an experimental feature included in the base game. This tab simply provides a convenient interface for configuration.',
                order = 2,
                set = function(info, value)
                    previousSettings.actionCam = nil
                    settings.actionCam[info[#info]] = value
                end,
                get = function(info) return settings.actionCam[info[#info]] end,
                args = {
                    general = {
                        type = "group",
                        inline = true,
                        order = 1,
                        name = "Related",
                        args = {
                            cameraKeepCharacterCentered = {
                                name = "Keep Character Centered",
                                type = "toggle",
                                order = 1,
                                width = "full",
                                set = function(info, value)
                                    C_CVar.SetCVar("CameraKeepCharacterCentered", value and "1" or "0")
                                end,
                                get = addon.cameraCharacterCenteringEnabled,
                                desc = "Keep character centered in camera view. When enabled, Action Cam features will be disabled."
                            },
                            cameraReduceUnexpectedMovement = {
                                name = "Reduce Camera Motion",
                                type = "toggle",
                                order = 1,
                                width = "full",
                                set = function(info, value)
                                    C_CVar.SetCVar("CameraReduceUnexpectedMovement", value and "1" or "0")
                                end,
                                get = function() return C_CVar.GetCVar("CameraReduceUnexpectedMovement") == "1" end,
                                desc = "Reduces various unexpted camera motion effects"
                            },
                            suppressExperimentalCVarPrompt = {
                                type = "toggle",
                                order = 2,
                                width = "full",
                                name = "Suppress Expirimental Feature Prompt",
                                desc = "This will remove the warning on load when Action Cam is enabled."
                            },
                        }
                    },
                    overShoulder = {
                        type = "group",
                        name = "Over the Shoulder",
                        order = 2,
                        inline = true,
                        hidden = addon.cameraCharacterCenteringEnabled,
                        args = {
                            [""] = {
                                type = "range",
                                name = "Over the Shoulder",
                                max = 2,
                                softMax = 2,
                                min = -2,
                                softMin = -2,
                                width = "double"
                            },
                            toggleDefaults = toggleGroupDefaultsOption('overShoulder')
                        }
                    },
                    motionSicknessMessage = {
                        type = "group",
                        name = "Action Cam Disabled",
                        order = 3,
                        inline = true,
                        hidden = addon.cameraCharacterCenteringDisabled,
                        args = {
                            message1 = {
                                type = "description",
                                order = 1,
                                name = "To enable Action Cam you must"
                            },
                            message2 = {
                                type = "execute",
                                order = 2,
                                width = "double",
                                name = "Disable Character Centering",
                                func = function()
                                    C_CVar.SetCVar("CameraKeepCharacterCentered", "0")
                                    addon:applyActionCamSettings()
                                end
                            },
                            message3 = {
                                type = "description",
                                order = 3,
                                name = "which is enabled by default to prevent motion sickness in some users. This setting can also be toggled in the General section above or with Options > Game > Accessibility > General > Motion Sickness."
                            }
                        }
                    },
                    dynamicPitch = {
                        type = "group",
                        name = "Dynamic Pitch",
                        hidden = addon.cameraCharacterCenteringEnabled,
                        inline = true,
                        order = 3,
                        args = {
                            [""] = {
                                type = "toggle",
                                name = "Dynamic Pitch",
                                order = 1
                            },
                            baseFovPad = {
                                name = "Base FoV Pad",
                                order = 2,
                                step = 0.01,
                                softMax = 0.99,
                                min = 0.01,
                                softMin = 0.01
                            },
                            baseFovPadFlying = {
                                name = "Flying Base FoV Pad",
                                step = 0.01,
                                softMax = 0.99,
                                min = 0.01,
                                softMin = 0.01
                            },
                            baseFovPadDownScale = {
                                name = "Base FoV Down Scale",
                                step = 0.01,
                                softMax = 0.99
                            },
                            smartPivotCutoffDist = {
                                name = "Smart Pivot Cutoff Distance",
                                step = 0.01,
                                softMax = 50,
                                max = 50,
                            },
                            toggleDefaults = toggleGroupDefaultsOption('dynamicPitch')
                        }
                    },
                    headMovement = {
                        type = "group",
                        name = "Head Movement",
                        hidden = addon.cameraCharacterCenteringEnabled,
                        inline = true,
                        order = 4,
                        args = {
                            strength = {
                                order = 1,
                                softMax = 4
                            },
                            standingStrength = {
                                order = 2,
                                softMax = 4
                            },
                            movingStrength = {
                                order = 3,
                                softMax = 4
                            },
                            firstPersonDampRate = {
                                order = 4,
                                min = 1,
                                softMax = 50
                            },
                            standingDampRate = {
                                order = 5,
                                min = 1,
                                softMax = 50
                            },
                            movingDampRate = {
                                order = 6,
                                min = 1,
                                softMax = 50
                            },
                            deadZone = {
                                order = 7,
                                softMax = 50,
                                desc = "This option doesn't apply immediately (possibly a bug in the base game), but mounting or reloading will trigger application",
                            },
                            rangeScale = {
                                order = 8,
                                softMax = 50,
                            },
                            toggleDefaults = toggleGroupDefaultsOption('headMovement')
                        }
                    },
                    targetFocus = {
                        type = "group",
                        name = "Target Focus",
                        hidden = addon.cameraCharacterCenteringEnabled,
                        inline = true,
                        order = 5,
                        args = {
                            enemyEnable = {
                                order = 1,
                                type = "toggle"
                            },
                            enemyStrengthPitch = {
                                order = 2,
                                softMax = 1,
                            },
                            enemyStrengthYaw = {
                                order = 3,
                                softMax = 1,
                            },
                            interactEnable = {
                                order = 4,
                                type = "toggle"
                            },
                            interactStrengthPitch = {
                                order = 5,
                                softMax = 1,
                            },
                            interactStrengthYaw = {
                                order = 6,
                                softMax = 1,
                            },
                            toggleDefaults = toggleGroupDefaultsOption('targetFocus')
                        }
                    },
                    toggleDefaults = {
                        type = "execute",
                        name = function()
                            if (previousSettings.actionCam == nil) then
                                return "Defaults"
                            else
                                return "Undo"
                            end
                        end,
                        hidden = addon.cameraCharacterCenteringEnabled,
                        func = function() addon:toggleActionCamDefaults() end,
                        order = 99
                    }
                }
            }
        }
    }
    
    local actionCamArgs = options.args.actionCam.args

    -- actionCam CVars
    for index, cVar in pairs(T.actionCamCVars) do
        local groupName = nil
        for group, setting in pairs(actionCamArgs) do
            if (strfind(cVar, T.capitalize(group)) ~= nil) then
                groupName = group
                break
            end
        end

        if (groupName == nil) then
            groupName = "general"
        end

        local var = T.unCapitalize(cVar:gsub("test_camera", ""):gsub(T.capitalize(groupName), ""))
        local name = T.capitalize(T.splitCamelCase(var == "" and groupName or var))
        local CVar = 'test_camera' .. T.capitalize(groupName:gsub("general", "")) .. T.capitalize(var)
        local default = C_CVar.GetCVarDefault(CVar)
        local CVarIsNumeric = tonumber(default) ~= nil
        local optionType = actionCamArgs[groupName].args[var] and actionCamArgs[groupName].args[var].type or CVarIsNumeric and "range" or "input"
        local rangeMin = type == "range" and 0 or nil
        local rangeMax = nil
        if (optionType == "range") then
            rangeMax = T.getOrderOfMagnitude(tonumber(default ~= "0" and default or 0.1)) * 10
        end
        local bigStep = nil
        if (optionType == "range") then
            bigStep = rangeMax / 100
        end

        actionCamArgs[groupName].args[var] = T.deepMerge(
            {
                name = name,
                type = optionType,
                softMin = rangeMin,
                softMax = rangeMax,
                bigStep = bigStep,
                order = 50,
                hidden = addon.cameraCharacterCenteringEnabled,
                get = function(info)
                    local value = C_CVar.GetCVar(CVar)
                    if (info.type == 'toggle') then
                        return value == "1" and true or false
                    elseif (info.type == 'range') then
                        return tonumber(value)
                    else
                    return value
                    end
                end,
                set = function(info, value)
                    local CVar = 'test_camera' .. T.capitalize(groupName:gsub("general", "")) .. T.capitalize(info[#info])
                    
                    if (type(value) == 'boolean') then
                        value = value and 1 or 0 -- convert to string
                    end

                    C_CVar.SetCVar(CVar, value)
                    settings.actionCam[CVar] = value
                    previousSettings.actionCam = nil
                    previousSettings.actionCamGroups[groupName] = nil
                end,
            },
            actionCamArgs[groupName].args[var] or {}
        )
    end

    -- stand by behavior
    if (xpac >= xpacs.sl) then
        options.args.general.args.standBy.args.standByBehavior.values.maxDistance = "Zoom to max distance"
    end

    return options
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
    if arg == "toggle" then
        addon:toggleStandBy()
    elseif (arg == "standby") then
        addon:enterStandBy()
    elseif (arg == "resume") then
        addon:exitStandBy()
    elseif (arg == "settings" or arg == "options") then
        SettingsPanel:Open()
        InterfaceOptionsFrame_OpenToCategory("Auto-Camera")
    elseif (arg == "debug") then
        print(AuraUtil.FindAuraByName("Rock Climbing Gear", "player"))
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
        print("/ac toggle       " .. colorStart .. yellow .. "toggles stand-by mode on/off" .. colorEnd)
        print("/ac standby    " .. colorStart .. yellow .. "enters stand-by mode" .. colorEnd)
        print("/ac resume     " .. colorStart .. yellow .. "exits stand-by mode" .. colorEnd)
        print("/ac settings    " .. colorStart .. yellow .. "opens Auto-Camera settings" .. colorEnd)
    end
end

-- events
local function OnEvent(self, event, ...)
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

    -- Shared debounce logic: captures the correct frame now (before async delay) so
    -- that a mount/dismount during the debounce window doesn't misattribute the adjustment.
    local function handleZoomInput(frame)
        IS_ADJUSTING = true
        if scrollDebounceTimer then
            addon:CancelTimer(scrollDebounceTimer)
        end
        scrollDebounceTimer = addon:ScheduleTimer(function()
            IS_ADJUSTING = false
            scrollDebounceTimer = nil
            setAdjustment(frame, GetCameraZoom())
            if addon:isRunning() then
                addon:autoZoom()
            end
        end, 0.5)
    end

    local function currentZoomFrame()
        if AuraUtil.FindAuraByName("Running Wild", "player") == nil and IsMounted("player") then
            return T.playerMountModelFrame
        else
            return T.playerModelFrame
        end
    end

    scrollHandlerFrame:SetScript("OnMouseWheel", function(self, delta)
        local key = T.buildModifiedKey(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
        local noBindings = not next(zoomInKeys) and not next(zoomOutKeys)
        local isZoomIn = zoomInKeys[key]
        local isZoomOut = zoomOutKeys[key]

        if not isZoomIn and not isZoomOut and not noBindings then
            return
        end

        handleZoomInput(currentZoomFrame())

        -- A frame's OnMouseWheel consumes the scroll event, so WoW's key binding
        -- system will NOT fire for this input. We must call CameraZoomIn/Out here.
        if isZoomIn or (noBindings and delta > 0) then
            CameraZoomIn(1)
        else
            CameraZoomOut(1)
        end
    end)

    -- Intercept non-scroll key zoom bindings. SetPropagateKeyboardInput ensures
    -- the actual zoom still fires via the normal binding system.
    scrollHandlerFrame:SetScript("OnKeyDown", function(self, key)
        local fullKey = T.buildModifiedKey(key)
        if not zoomInKeys[fullKey] and not zoomOutKeys[fullKey] then
            return
        end
        handleZoomInput(currentZoomFrame())
    end)

    updateZoomKeyBindings()

    if (not STAND_BY) then
        addon:autoZoom()
    end
end

function addon:UNIT_MODEL_CHANGED()
    LibStub("AceConfigRegistry-3.0"):NotifyChange("Auto-Camera")
end

function addon:evaluateHasClimbingGear()
    if (AuraUtil.FindAuraByName("Rock Climbing Gear", "player") ~= nil) then
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

local classicEvents = T.set {"PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE", "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_ENTERING_WORLD", "VARIABLES_LOADED", "ADDON_LOADED", "LFG_COMPLETION_REWARD", "UPDATE_BINDINGS"}
local wrathEvents = T.set {"BARBER_SHOP_OPEN", "BARBER_SHOP_CLOSE"}

for event in pairs(classicEvents) do
    f:RegisterEvent(event)
end

f:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
f:RegisterUnitEvent("UNIT_AURA", "player")

if (xpac >= xpacs.wolc) then
    for event in pairs(wrathEvents) do
        f:RegisterEvent(event)
    end
end

f:SetScript("OnEvent", OnEvent)
