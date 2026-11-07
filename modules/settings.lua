local addonName, T = ...

function T.standingArgKey(race)
    return T.camelCase(race) .. 'Distance'
end

function T.defaultSettings()
  local defaultSettings = {
    general = {
      pauseOnLoad = false,
      pauseBehavior = "view",
      manualPauseView = 5,
      petBattleView = 5,
      instanceEncounterView = 5,
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

local migrations = {
  {
    version = "0.2.0",
    apply = function(settings)
      if settings.general then return end
      local general = T.deepCopy(settings)
      for key in pairs(settings) do settings[key] = nil end
      settings.general = general
    end
  },
  {
    version = "0.3.1",
    apply = function(settings)
      local general = settings.general
      if not general then return end
      local renames = {
        standByOnLoad = "pauseOnLoad",
        standByBehavior = "pauseBehavior",
        manualStandByView = "manualPauseView"
      }
      for oldKey, newKey in pairs(renames) do
        if rawget(general, newKey) == nil then
          general[newKey] = rawget(general, oldKey)
        end
        general[oldKey] = nil
      end
    end
  }
}

local function versionParts(version)
  assert(type(version) == "string", "Auto-Camera: saved settings version must be a string")
  local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)$")
  assert(major, "Auto-Camera: invalid saved settings version: " .. tostring(version))
  return {tonumber(major), tonumber(minor), tonumber(patch)}
end

local function versionBefore(left, right)
  left, right = versionParts(left), versionParts(right)
  for index = 1, 3 do
    if left[index] ~= right[index] then return left[index] < right[index] end
  end
  return false
end

function T.migrateSettings(settings)
  local version = settings.version or "0.0.0"
  for _, migration in ipairs(migrations) do
    if versionBefore(version, migration.version) then
      migration.apply(settings)
      version = migration.version
      settings.version = version
    end
  end
  if versionBefore(version, T.version) then version = T.version end
  settings.version = version
  return settings
end

local function validateSettings(settings)
  assert(type(settings) == "table", "Auto-Camera: saved global settings must be a table")
  local defaults = T.defaultSettings()
  if settings.general ~= nil then
    assert(type(settings.general) == "table", "Auto-Camera: saved general settings must be a table")
    for key in pairs(defaults.general) do
      assert(settings[key] == nil, "Auto-Camera: mixed flat and nested settings: " .. key)
    end
    for _, key in ipairs({"standByOnLoad", "standByBehavior", "manualStandByView"}) do
      assert(settings[key] == nil, "Auto-Camera: mixed flat and nested settings: " .. key)
    end
  end
end

local function validateMigratedSettings(settings)
  validateSettings(settings)
  assert(type(settings.general) == "table", "Auto-Camera: migrated settings have no general table")
  local defaults = T.defaultSettings()
  for key, default in pairs(defaults.general) do
    local value = settings.general[key]
    if value ~= nil then
      assert(type(value) == type(default), "Auto-Camera: invalid saved setting: general." .. key)
      if type(value) == "number" then
        assert(value == value and math.abs(value) < math.huge, "Auto-Camera: nonfinite setting: general." .. key)
      end
    end
  end
  local behavior = settings.general.pauseBehavior
  assert(behavior == nil or behavior == "view" or behavior == "doNothing" or behavior == "maxDistance",
    "Auto-Camera: invalid saved pause behavior")
  for _, key in ipairs({"manualPauseView", "instanceEncounterView", "petBattleView"}) do
    local value = settings.general[key]
    assert(value == nil or (value >= 1 and value <= 5 and value == math.floor(value)),
      "Auto-Camera: invalid saved camera view: " .. key)
  end
  for id, value in pairs(settings.general.adjustments or {}) do
    assert(type(id) == "number" and id > 0 and id < math.huge and id == math.floor(id) and
      type(value) == "number" and value == value and math.abs(value) < math.huge,
      "Auto-Camera: invalid saved model adjustment")
  end
  if settings.actionCam ~= nil then
    assert(type(settings.actionCam) == "table", "Auto-Camera: saved Action Camera settings must be a table")
    local suppress = settings.actionCam.suppressExperimentalCVarPrompt
    assert(suppress == nil or type(suppress) == "boolean", "Auto-Camera: invalid experimental warning setting")
    for _, cvar in ipairs(T.actionCamCVars) do
      local value = settings.actionCam[cvar]
      if value ~= nil then
        assert(type(value) == "string" or type(value) == "number", "Auto-Camera: invalid saved CVar: " .. cvar)
        if tonumber(C_CVar.GetCVarDefault(cvar)) then
          local number = tonumber(value)
          assert(number and number == number and math.abs(number) < math.huge,
            "Auto-Camera: invalid numeric CVar: " .. cvar)
        end
      end
    end
  end
end

function T.prepareSavedSettings(saved)
  -- Work on a copy so even a later migration failure leaves the original save intact.
  return pcall(function()
    assert(saved == nil or type(saved) == "table", "Auto-Camera: saved database must be a table")
    local candidate = T.deepCopy(saved or {})
    if candidate.global == nil then candidate.global = {} end
    validateSettings(candidate.global)
    assert(not versionBefore(T.version, candidate.global.version or "0.0.0"),
      "Auto-Camera: saved config is from a newer addon version")
    T.migrateSettings(candidate.global)
    -- AceDB removes empty default-only sections at logout.
    if candidate.global.general == nil then candidate.global.general = {} end
    validateMigratedSettings(candidate.global)
    return candidate
  end)
end

function T.setupMigrationRecovery(addon, reason)
  addon.settingsMigrationFailed = true
  addon:SetEnabledState(false)
  print("Auto-Camera: config migration failed. Saved config has not been changed. " ..
    tostring(reason) .. " Use /ac recovery to reopen the recovery dialog.")

  local recoveryFrame = CreateFrame("Frame")
  local pendingAction
  local function performAction(action)
    if InCombatLockdown() then
      pendingAction = action
      recoveryFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
      print("Auto-Camera: recovery will complete after combat ends; saved config is unchanged until then.")
      return
    end
    if action == "reset" then
      AutoCameraDB = {global = {version = T.version}}
    else
      C_AddOns.DisableAddOn(addonName, UnitName("player"))
      C_AddOns.SaveAddOns()
    end
    ReloadUI()
  end

  StaticPopupDialogs["AUTO_CAMERA_MIGRATION_FAILED"] = {
    text = "Auto-Camera failed to migrate your saved config to the latest version. What would you like to do?",
    button1 = "Reset Config",
    button2 = "Disable Auto-Camera",
    OnAccept = function()
      if not StaticPopup_Show("AUTO_CAMERA_CONFIRM_CONFIG_RESET") then
        print("Auto-Camera: reset confirmation could not be shown. Config is unchanged. Use /ac recovery to try again.")
      end
    end,
    OnCancel = function(_, _, reason)
      if reason == "clicked" then performAction("disable") end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true
  }
  StaticPopupDialogs["AUTO_CAMERA_CONFIRM_CONFIG_RESET"] = {
    text = "Reset Auto-Camera's saved config to defaults? This deletes your saved camera settings and model adjustments, then reloads the interface.",
    button1 = "Reset Config",
    button2 = CANCEL,
    OnAccept = function() performAction("reset") end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true
  }

  function addon:showMigrationRecovery()
    if pendingAction then
      print("Auto-Camera: recovery is waiting for combat to end.")
      return
    end
    if not StaticPopup_Visible("AUTO_CAMERA_MIGRATION_FAILED") and
        not StaticPopup_Visible("AUTO_CAMERA_CONFIRM_CONFIG_RESET") then
      if not StaticPopup_Show("AUTO_CAMERA_MIGRATION_FAILED") then
        print("Auto-Camera: recovery dialog could not be shown. Config is unchanged. Use /ac recovery to try again.")
      end
    end
  end

  recoveryFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
      recoveryFrame:UnregisterEvent(event)
      C_Timer.After(0, function() addon:showMigrationRecovery() end)
    elseif event == "PLAYER_REGEN_ENABLED" then
      recoveryFrame:UnregisterEvent(event)
      local action = pendingAction
      pendingAction = nil
      performAction(action)
    end
  end)
  if IsLoggedIn() then
    C_Timer.After(0, function() addon:showMigrationRecovery() end)
  else
    recoveryFrame:RegisterEvent("PLAYER_LOGIN")
  end
end
