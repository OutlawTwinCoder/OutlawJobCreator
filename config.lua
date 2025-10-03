-- config.lua
Config = Config or {}

Config.UseOxmysql = true
Config.MigrationAutoApply = true
Config.Locale = 'fr' -- default fr/en

-- Permission settings
Config.Permission = {
  requiredAce = 'outlawjob.manage',
  allowedIdentifiers = {
    -- 'license:1234567890abcdef'
  },
  allowConsole = true
}

function Config.CanManageCreator(src)
  if not IsDuplicityVersion or not IsDuplicityVersion() then
    return false
  end
  if src <= 0 then
    return Config.Permission.allowConsole
  end

  if Config.Permission.requiredAce and IsPlayerAceAllowed(src, Config.Permission.requiredAce) then
    return true
  end

  if Config.Permission.allowedIdentifiers then
    for _, identifier in ipairs(Config.Permission.allowedIdentifiers) do
      for _, playerIdentifier in ipairs(GetPlayerIdentifiers(src)) do
        if identifier == playerIdentifier then
          return true
        end
      end
    end
  end

  return false
end

Config.PointValidation = {
  minRadius = 0.5,
  maxRadius = 50.0,
  minDistance = 1.5,
  groundSnapTolerance = 1.5,
  rejectWater = true,
  waterTolerance = 0.75
}

Config.Migration = {
  manifestFile = 'migrations/_manifest.json'
}

-- Command to open UI: /outlawjob
