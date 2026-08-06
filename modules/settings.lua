local addonName, T = ...

function T.standingArgKey(race)
    return T.camelCase(race) .. 'Distance'
end

function T.defaultSettings()
  local defaultSettings = {
    general = {
      standByOnLoad = false,
      standByBehavior = "view",
      manualStandByView = 5,
      petBattleView = 5,
      instanceEncounterView = 5,
      ridingDistance = 8.5,
      speedMultiplier = 0.1,
      normalEnemyDistance = 4,
      eliteEnemyDistance = 4,
      raidEnemyDistance = 8,
      bossEnemyDistance = 50,
      adjustments = {}
    },
    actionCam = {
      suppressExperimentalCVarPrompt = false
    }
  }

  for race in pairs(T.set {"Worgen"}) do
    defaultSettings.general[T.standingArgKey(race)] =  4.6
  end

  for race in pairs(T.set {"Dracthyr"}) do
    defaultSettings.general[T.standingArgKey(race)] =  5.3
  end
  
  for race in pairs(T.set {"Night Elf", "Nightborne"}) do
    defaultSettings.general[T.standingArgKey(race)] =  4
  end
  
  for race in pairs(T.set {"Draenei", "Pandaren" ,"Orc", "Troll", "Mag'har Orc", "Zandalari Troll", "Lightforged Draenei"}) do
    defaultSettings.general[T.standingArgKey(race)] =  4.5
  end
  
  for race in pairs(T.set {"Human", "Dwarf", "Undead", "Blood Elf" ,"Void Elf", "Dark Iron Dwarf"}) do
    defaultSettings.general[T.standingArgKey(race)] = 3.5
  end
  
  for race in pairs(T.set {"Gnome", "Goblin", "Mechagnome", "Vulpera"}) do
    defaultSettings.general[T.standingArgKey(race)] = 2
  end
  
  for race in pairs(T.set {"Tauren", "Kul Tiran", "Highmountain Tauren"}) do
    defaultSettings.general[T.standingArgKey(race)] = 5.2
  end

  for index, CVar in pairs(T.actionCamCVars) do
    defaultSettings.actionCam[CVar] = C_CVar.GetCVarDefault(CVar)
  end

  return defaultSettings
end

settingsUpdateMap = {}

settingsUpdateMap['0.2.0'] = function(settings)
  -- copy root as general
  local general = T.deepCopy(settings)

  -- empty table
  for key in pairs(settings) do
    settings[key] = nil
  end

  settings.general = general
end
