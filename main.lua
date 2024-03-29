local addonName, T = ...
AutoCamera = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceTimer-3.0")
local addon = AutoCamera
local STAND_BY = false
local IN_PET_BATTLE = false
local IN_ENCOUNTER = false
local IN_BARBER_SHOP = false
local IN_RAID = false
local IN_DUNGEON = false
local STAND_BY_BEHAVIOR_HANDLED = true
local previousCameraZoom = GetCameraZoom()
local deltaTime = 0.1
local previousSettings = {general = nil, actionCam = nil, actionCamGroups = {}} -- stores the previous settings when defaults are applied by the user
local playerRace = UnitRace("player")
local showOtherRaces = false
local races = T.set {"Human", "Dwarf", "Night Elf", "Gnome", "Draenei", "Worgen", "Pandaren", "Orc", "Undead", "Tauren", "Troll", "Blood Elf", "Goblin", "Void Elf", "Lightforged Draenei", "Dark Iron Dwarf", "Kul Tiran", "Mechagnome", "Nightborne", "Highmountain Tauren", "Mag'har Orc", "Zandalari Troll", "Vulpera", "Dracthyr"}
local bodyType = {neutral=1, masc=2, fem=3}
local humanShapeShifters = T.set {"Human 2", "Human 1", "Visage 2"}
local bloodElfShapeShifters = T.set {"Visage 1"}
races[playerRace] = true -- adds player race if it's missing from race set
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

local function enemyArgKey(unit)
    local enemyType
	if (
		(unitClassification == "worldboss" or
		(unitClassification == "elite" and UnitLevel(unit) == -1))
	) then
        enemyType = "boss"
    elseif (IN_RAID or IN_DUNGEON) then
        enemyType = "raid"
	elseif (
		unitClassification == "elite"
	) then
		enemyType = "elite"
	else
		enemyType = "normal"
    end
    
    return enemyType .. "EnemyDistance"
end

local playerStandingArgKey = T.standingArgKey(playerRace)

local settings = T.defaultSettings()
local units = {}
units[1] = 'target'
for i = 1, 10 do
    units[i + 1] = 'nameplate' .. i
end

BINDING_HEADER_AUTO_CAMERA = "Auto-Camera"
BINDING_NAME_TOGGLE_STAND_BY = "Toggle Stand-By Mode"

function addon:OnEnable()
    self:ScheduleRepeatingTimer("autoZoom", 0.1)
end

function addon:isRunning() 
    return
        not STAND_BY and
        not IN_ENCOUNTER and
        not IN_PET_BATTLE and
        not IN_BARBER_SHOP
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

    if (not STAND_BY) then
        addon:autoZoom()
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
    STAND_BY = true
end

function addon:exitStandBy()
    STAND_BY = false
    if addon:isRunning() then
        addon:autoZoom()
    end
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
            elseif IN_ENCOUNTER then
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
    local currentSpeed, runSpeed, flightSpeed, swimSpeed = GetUnitSpeed("player")

    STAND_BY_BEHAVIOR_HANDLED = false

    targetZoom = settings.general[playerStandingArgKey]

    -- Worgen and Drakthyr Human override
    if (humanShapeShifters[getPlayerModelName()] ~= nil) then
        targetZoom = settings.humanDistance
    end

    -- Drakthyr Blood Elf override
    if (bloodElfShapeShifters[getPlayerModelName()] ~= nil) then
        targetZoom = settings.humanDistance
    end
    
    if (
        AuraUtil.FindAuraByName("Running Wild", "player") == nil and
        (IsMounted("player") or (UnitInVehicle and UnitInVehicle("player"))) and
        settings.general.ridingDistance > targetZoom
    ) then
        targetZoom = settings.general.ridingDistance
    end

    targetZoom = targetZoom + currentSpeed * settings.general.speedMultiplier

    local enemyPackDistance = targetZoom
    for i, unit in ipairs(units) do
        local unitClassification = UnitClassification(unit)
        local unitLevel = UnitLevel(unit)
        if (
            not UnitIsDead(unit) and
            UnitCanAttack("player", unit) and
            -- CheckInteractDistance(unit, 1) and -- todo> replace this since it no longer works in combat
            (unit == 'target' or UnitGUID('target') ~= UnitGUID(unit)) -- if unit is target or a unit with nameplate that isn't the target (avoids counting target twice)
        ) then
            enemyPackDistance = enemyPackDistance + settings.general[enemyArgKey(unit)]
        end
    end

    if (targetZoom < enemyPackDistance) then targetZoom = enemyPackDistance end

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
                    standingDistances = {
                        type = "group",
                        inline = true,
                        order = 2,
                        name = "Minimum Camera Distances by Race",
                        args = {
                            toggleHidden = {
                                type = "execute",
                                name = function()
                                    if showOtherRaces then
                                        return "Show Fewer Races"
                                    else
                                        return "Show More Races"
                                    end
                                end,
                                func = function() showOtherRaces = not showOtherRaces end,
                                order = 99
                            }
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
                                step = 0.1,
                                order = 2
                            },
                            normalEnemyDistance = T.merge(distanceOption(), {
                                name = 'Per Normal Enemy',
                                desc = 'Distance to add per normal enemy on screen near the player character',
                                order = 3
                            }),
                            eliteEnemyDistance = T.merge(distanceOption(), {
                                name = 'Per Elite Enemy',
                                desc = 'Distance to add per elite enemy on screen near the player character',
                                order = 4
                            }),
                            raidEnemyDistance = T.merge(distanceOption(), {
                                name = 'Per Raid Enemy',
                                desc = 'Distance to add per raid enemy on screen near the player character',
                                order = 5,
                            }),
                            bossEnemyDistance = T.merge(distanceOption(), {
                                name = 'Per Boss Enemy',
                                desc = 'Distance to add per boss enemy on screen near the player character',
                                order = 6
                            })
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

    -- standing distances
    local standingDistances = options.args.general.args.standingDistances
    for race in pairs(races) do
        standingDistances.args[T.standingArgKey(race)] = T.merge(distanceOption(), {
            name = race,
            hidden = function()
                -- show all when Show Other Races is selected
                if (showOtherRaces) then return false end

                -- show current race
                if (playerRace == race) then return false end

                -- show Human if player is Worgen or Femanin Dracthry
                if (race == "Human" and (playerRace == "Worgen" or (playerRace == "Dracthyr" and UnitSex("player") == bodyType.fem))) then return false end

                -- show Blood Elf if player is Masculine Dracthry
                if (race == "Blood Elf" and (playerRace == "Dracthyr" and UnitSex("player") == bodyType.masc)) then return false end

                -- otherwise hide
                return true
            end
        })
    end
    local playerStandingArgKey = playerRace:gsub("^.", string.lower):gsub(" ", "") .. 'Distance'
    standingDistances.args[playerStandingArgKey].order = 1

    -- prioritize alternate forms
    if (playerRace == "Worgen" or (playerRace == "Dracthyr" and UnitSex("player") == bodyType.fem)) then
        standingDistances.args.humanDistance.order = 2
    end

    if (playerRace == "Dracthyr" and UnitSex("player") == bodyType.masc) then
        standingDistances.args.bloodElfDistance.order = 2
    end

    -- stand by behavior
    if (xpac >= xpacs.sl) then
        options.args.general.args.standBy.args.standByBehavior.values.maxDistance = "Zoom to max distance"
    end

    return options
end

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
    elseif (arg == "settings") then
        InterfaceOptionsFrame_Show()
        InterfaceOptionsFrame_OpenToCategory("Auto-Camera")
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

local f = CreateFrame("Frame")

local classicEvents = T.set {"PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE", "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_ENTERING_WORLD", "VARIABLES_LOADED"}
local wrathEvents = T.set {"BARBER_SHOP_OPEN", "BARBER_SHOP_CLOSE"}

for event in pairs(classicEvents) do
    f:RegisterEvent(event)
end

if (xpac >= xpacs.wolc) then
    for event in pairs(wrathEvents) do
        f:RegisterEvent(event)
    end
end

f:SetScript("OnEvent", OnEvent)
