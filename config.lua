-- config.lua
Config = Config or {}

Config.UseOxmysql = true
Config.MigrationAutoApply = true
Config.Locale = 'fr'

Config.Permission = {
  requiredAce = false,
  fallbackAces = {
    'outlaw.creator',
    'group.admin',
    'group.god'
  },
  allowedIdentifiers = {},
  allowConsole = true
}

function Config.CanManageCreator(src)
  if not IsDuplicityVersion or not IsDuplicityVersion() then
    return false
  end

  if src <= 0 then
    return Config.Permission.allowConsole
  end

  if Config.Permission.requiredAce and Config.Permission.requiredAce ~= '' then
    if IsPlayerAceAllowed(src, Config.Permission.requiredAce) then
      return true
    end
  elseif Config.Permission.requiredAce == false then
    return true
  end

  if Config.Permission.fallbackAces then
    for _, ace in ipairs(Config.Permission.fallbackAces) do
      if ace ~= '' and IsPlayerAceAllowed(src, ace) then
        return true
      end
    end
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
  minRadius = 0.0,
  maxRadius = 50.0,
  rejectWater = false
}

Config.Migration = {
  manifestFile = 'migrations/_manifest.json'
}

Config.JobForm = {
  defaultIcon = 'fa-briefcase',
  defaultColor = '#ff9d0b',
  defaultTag = 'standard',
  defaultSalary = 0,
  defaultSocietyPrefix = 'society_',
  iconOptions = {
    { value = 'fa-briefcase', label = 'Briefcase' },
    { value = 'fa-truck', label = 'Livraison' },
    { value = 'fa-screwdriver-wrench', label = 'Mécano' },
    { value = 'fa-bottle-droplet', label = 'Collecte' },
    { value = 'fa-wand-magic-sparkles', label = 'Craft' }
  },
  colorOptions = {
    { value = '#ff9d0b', label = 'Orange' },
    { value = '#2f80ed', label = 'Bleu' },
    { value = '#6fcf97', label = 'Vert' },
    { value = '#eb5757', label = 'Rouge' },
    { value = '#bb6bd9', label = 'Violet' },
    { value = '#333333', label = 'Gris' }
  }
}

Config.JobIntegrations = {
  baseTable = 'jobs',
  nameField = 'name',
  labelField = 'label',
  whitelistedField = 'whitelisted'
}

Config.PointOptions = {
  types = {
    { value = 'collect', label = 'Collecte' },
    { value = 'deliver', label = 'Livraison' },
    { value = 'craft', label = 'Atelier' },
    { value = 'garage', label = 'Garage' },
    { value = 'spawn', label = 'Spawn' }
  },
  usage = {
    { value = 'point', label = 'Point unique' },
    { value = 'zone', label = 'Zone' }
  }
}

Config.OpenCommand = 'outlawjob'
Config.KeyMapping = { enabled = false, defaultKey = 'F7' }
