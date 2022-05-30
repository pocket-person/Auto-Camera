local addonName, vars = ...
AutoCamera = LibStub("AceAddon-3.0"):NewAddon(addonName)
local addon = AutoCamera
local STAND_BY = false
local IN_PET_BATTLE = false
local IN_ENCOUNTER = false
local IN_RAID = false
local IN_DUNGEON = false
local previousCameraZoom = GetCameraZoom()
local deltaTime = 0.1
local prevSettings = nil
local playerRace = UnitRace("player")
local showOtherRaces = false
local races = set {"Human", "Dwarf", "Night Elf", "Gnome", "Draenei", "Worgen", "Pandaren", "Orc", "Undead", "Tauren", "Troll", "Blood Elf", "Goblin", "Void Elf", "Lightforged Draenei", "Dark Iron Dwarf", "Kul Tiran", "Mechagnome", "Nightborne", "Highmountain Tauren", "Mag'har Orc", "Zandalari Troll", "Vulpera"}
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

local defaults = {
    global = {
        standByOnLoad = false,
        standByBehavior = "view",
        manualStandByView = 5,
        petBattleView = 5,
        instanceEncounterView = 5,
        ridingDistance = 8.5,
        speedMultiplier = 0.2,
        normalEnemyDistance = 4,
        eliteEnemyDistance = 4,
        raidEnemyDistance = 8,
        bossEnemyDistance = maxZoomDistance
    }
}

function standingArgKey(race)
    return camelCase(race) .. 'Distance'
end

function enemyArgKey(unit)
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

local playerStandingArgKey = standingArgKey(playerRace)

for race in pairs(set {"Worgen"}) do
    defaults.global[standingArgKey(race)] =  4.6
end

for race in pairs(set {"Night Elf", "Nightborne"}) do
    defaults.global[standingArgKey(race)] =  4
end

for race in pairs(set {"Draenei", "Pandaren" ,"Orc", "Troll", "Mag'har Orc", "Zandalari Troll", "Lightforged Draenei"}) do
    defaults.global[standingArgKey(race)] =  4.5
end

for race in pairs(set {"Human", "Dwarf", "Undead", "Blood Elf" ,"Void Elf", "Dark Iron Dwarf"}) do
    defaults.global[standingArgKey(race)] = 3.5
end

for race in pairs(set {"Gnome", "Goblin", "Mechagnome", "Vulpera"}) do
    defaults.global[standingArgKey(race)] = 2
end

for race in pairs(set {"Tauren", "Kul Tiran", "Highmountain Tauren"}) do
    defaults.global[standingArgKey(race)] = 5.2
end

local settings = defaults.global
local units = {}
units[1] = 'target'
for i = 1, 10 do
    units[i + 1] = 'nameplate' .. i
end

BINDING_HEADER_AUTO_CAMERA = "Auto-Camera"
BINDING_NAME_TOGGLE_STAND_BY = "Toggle Stand-By Mode"

function addon:isRunning() 
    return 
        not STAND_BY and
        not IN_ENCOUNTER and
        not IN_PET_BATTLE
end

function addon:loadSettings()
    settings = addon.db.global
    for key, value in pairs(defaults.global) do
        if settings[key] == nil then
            settings[key] = deepCopy(value)
        end
    end
end

-- addon hook callback functions
function addon:OnInitialize()
    local options = addon:options()
    addon.db = LibStub("AceDB-3.0"):New("AutoCameraDB", defaultSettings, true)
    addon:loadSettings()
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, addonName)
    STAND_BY = settings.standByOnLoad
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
end

function addon:autoZoom()
    local targetZoom
    local currentCameraZoom = GetCameraZoom()
    local unit
    local enemyCount = 0
    local currentSpeed, runSpeed, flightSpeed, swimSpeed = GetUnitSpeed("player")

    targetZoom = settings[playerStandingArgKey]
    if (playerRace == "Worgen" and not isWorgenForm()) then
        targetZoom = settings.humanDistance
    end
    
    if (
        AuraUtil.FindAuraByName("Running Wild", "player") == nil and
        (IsMounted("player") or (UnitInVehicle and UnitInVehicle("player")))
    ) then
        targetZoom = settings.ridingDistance
    end

    targetZoom = targetZoom + currentSpeed * settings.speedMultiplier

    local enemyPackDistance = targetZoom
    for i, unit in ipairs(units) do
        local unitClassification = UnitClassification(unit)
        local unitLevel = UnitLevel(unit)
        if (
            not UnitIsDead(unit) and
            UnitCanAttack("player", unit) and
            CheckInteractDistance(unit, 1) and
            (unit == 'target' or UnitGUID('target') ~= UnitGUID(unit)) -- if unit is target or a unit with nameplate that isn't the target (avoids counting target twice)
        ) then
            enemyPackDistance = enemyPackDistance + settings[enemyArgKey(unit)]
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

    if (addon:isRunning()) then
        C_Timer.After(deltaTime, function() addon:autoZoom() end)
    else
        MoveViewInStop()
        MoveViewOutStop()
        if STAND_BY then
            if (settings.standByBehavior == "view") then
                SetView(settings.manualStandByView)
            elseif (settings.standByBehavior == "maxDistance") then
                CameraZoomOut(maxZoomDistance)
            end
        elseif IN_ENCOUNTER then
            if (settings.standByBehavior == "view") then
                SetView(settings.instanceEncounterView)
            elseif (settings.standByBehavior == "maxDistance") then
                CameraZoomOut(maxZoomDistance)
            end
        elseif IN_PET_BATTLE then
            if (settings.standByBehavior == "view") then
                SetView(settings.petBattleView)
            elseif (settings.standByBehavior == "maxDistance") then
                CameraZoomOut(maxZoomDistance)
            end
        end
    end

    previousCameraZoom = currentCameraZoom
end

function viewOption()
    return {
        type = 'range',
        min = 1,
        max = 5,
        step = 1
    }
end

function distanceOption()
    return {
        type = 'range',
        min = 0,
        max = maxZoomDistance,
        step = 0.1,
        order = 3
    }
end

function addon:toggleDefaults()
    if (prevSettings == nil) then 
        prevSettings = deepCopy(settings)
        assign(settings, defaults.global)
    else
        assign(settings, prevSettings)
        prevSettings = nil
    end
end

-- options
function addon:options()
    local options = {
        type = 'group',
        name = 'Auto-Camera',
        set = function(info, value)
            prevSettings = nil
            settings[info[#info]] = value
        end,
        get = function(info) return settings[info[#info]] end,
        args = {
            control = {
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
                    ridingDistance = merge(distanceOption(), {
                        name = 'Riding',
                        desc = 'Camera distance when riding on a mount or in a vehicle',
                        order = 1
                    }),
                    speedMultiplier = {
                        type = 'range',
                        name = 'Movement Multiplier',
                        min = 0,
                        max = 0.5,
                        step = 0.1,
                        order = 2
                    },
                    normalEnemyDistance = merge(distanceOption(), {
                        name = 'Per Normal Enemy',
                        desc = 'Distance to add per normal enemy on screen near the player character',
                        order = 3
                    }),
                    eliteEnemyDistance = merge(distanceOption(), {
                        name = 'Per Elite Enemy',
                        desc = 'Distance to add per elite enemy on screen near the player character',
                        order = 4
                    }),
                    raidEnemyDistance = merge(distanceOption(), {
                        name = 'Per Raid Enemy',
                        desc = 'Distance to add per raid enemy on screen near the player character',
                        order = 5,
                    }),
                    bossEnemyDistance = merge(distanceOption(), {
                        name = 'Per Boss Enemy',
                        desc = 'Distance to add per boss enemy on screen near the player character',
                        order = 6
                    })
                }
            },
            standByBehavior = {
                type = "group",
                inline = true,
                order = 4,
                name = "Stand-By Camera Distance",
                args = {
                    standByBehavior = {
                        type = "select",
                        name = "When Stand-By is activated",
                        order = 1,
                        values = {
                            view = "Zoom to view",
                            doNothing = "Do Nothing"
                        },
                        desc = "Indicates if the camera should zoom to the max camera distance when Auto-Camera is on stand-by"
                    },
                    spacer = {
                        type = "header",
                        name = "Stand-By Views",
                        order = 2,
                        hidden = function() return settings.standByBehavior ~= "view" end
                    },
                    manualStandByView = merge(viewOption(), {
                        name = 'Manual Stand-By View',
                        desc = 'The camera view to go to when toggling Auto-Camera off',
                        hidden = function() return settings.standByBehavior ~= "view" end
                    }),
                    instanceEncounterView = merge(viewOption(), {
                        name = 'Instance Encounter View',
                        desc = 'The camera view to go to during an encounter (e.g. boss battle)',
                        hidden = function() return settings.standByBehavior ~= "view" end
                    }),
                    petBattleView = merge(viewOption(), {
                        name = 'Pet Battle View',
                        desc = 'The camera view to go to during a pet battle.',
                        hidden = function() return settings.standByBehavior ~= "view" end
                    })
                }
            },
            toggleDefaults = {
                type = "execute",
                name = function()
                    if (prevSettings == nil) then
                        return "Defaults"
                    else
                        return "Undo"
                    end
                end,
                func = function() addon:toggleDefaults() end,
                order = 100
            }
        }
    }

    -- standing distances
    local standingDistances = options.args.standingDistances
    for race in pairs(races) do
        standingDistances.args[standingArgKey(race)] = merge(distanceOption(), {
            name = race,
            hidden = function() return (not showOtherRaces) and ((playerRace ~= race) and (playerRace ~= "Worgen" or race ~= "Human")) end
        })
    end
    local playerStandingArgKey = playerRace:gsub("^.", string.lower):gsub(" ", "") .. 'Distance'
    standingDistances.args[playerStandingArgKey].order = 1
    if (playerRace == "Worgen") then
        options.args.standingDistances.args.humanDistance.order = 2
    end

    -- stand by behavior
    if (xpac >= xpacs.sl) then
        options.args.standByBehavior.args.standByBehavior.values.maxDistance = "Zoom to max distance"
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
    elseif (arg == "settings") then
        InterfaceOptionsFrame_Show()
        InterfaceOptionsFrame_OpenToCategory("Auto-Camera")
    else
        print(colorStart .. yellow .. "Auto-Camera console commands:" .. colorEnd)
        print("/ac toggle    " .. colorStart .. yellow .. "toggles stand-by mode on/off" .. colorEnd)
        print("/ac settings    " .. colorStart .. yellow .. "opens Auto-Camera settings" .. colorEnd)
    end
end

-- events
local function OnEvent(self, event, ...)
    addon[event](self, event, ...)
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

local f = CreateFrame("Frame")
f:RegisterEvent("PET_BATTLE_OPENING_START")
f:RegisterEvent("PET_BATTLE_CLOSE")
f:RegisterEvent("ENCOUNTER_START")
f:RegisterEvent("ENCOUNTER_END")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", OnEvent)
