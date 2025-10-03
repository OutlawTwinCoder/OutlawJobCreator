-- config.lua
Config = Config or {}

Config.UseOxmysql = true
Config.MigrationAutoApply = true
Config.Locale = 'fr' -- default fr/en

-- Permission settings
Config.Permission = {
  requiredAce = 'outlawjob.manage',
  fallbackAces = {
    'group.admin',
    'group.god'
  },
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

Config.JobForm = {
  defaultIcon = 'fa-briefcase',
  defaultColor = '#ff9d0b',
  defaultTag = 'general',
  defaultSalary = 0,
  defaultSocietyPrefix = 'society_',
  defaultWhitelisted = false,
  iconOptions = {
    { value = 'fa-briefcase', label = 'Briefcase (générique)' },
    { value = 'fa-user-tie', label = 'Employé / patron' },
    { value = 'fa-screwdriver-wrench', label = 'Mécanique' },
    { value = 'fa-truck-moving', label = 'Livraison' },
    { value = 'fa-box-open', label = 'Collecte / colis' },
    { value = 'fa-flask', label = 'Craft / laboratoire' },
    { value = 'fa-shield-halved', label = 'Sécurité / police' }
  },
  colorOptions = {
    { value = '#ff9d0b', label = 'Orange Outlaw' },
    { value = '#0099ff', label = 'Bleu mission' },
    { value = '#4caf50', label = 'Vert terrain' },
    { value = '#9c27b0', label = 'Violet spécial' },
    { value = '#f44336', label = 'Rouge alerte' },
    { value = '#607d8b', label = 'Gris industriel' }
  }
}

Config.JobIntegrations = {
  baseTable = 'jobs',
  nameField = 'name',
  labelField = 'label',
  whitelistedField = 'whitelisted',
  connectors = {
    armory = { table = 'jobs_armorie', jobField = 'job_name', label = 'Armurerie' },
    data = { table = 'jobs_data', jobField = 'job_name', label = 'Données' },
    employee_hours = { table = 'jobs_employee_hours', jobField = 'job_name', label = 'Heures employé' },
    garage = { table = 'jobs_garages', jobField = 'job_name', label = 'Garages' },
    shops = { table = 'jobs_shops', jobField = 'job_name', label = 'Shops' }
  },
  includeBilling = true,
  includeAddonAccount = true,
  includeUsers = true
}

Config.PointOptions = {
  types = {
    { value = 'collect', label = 'Collecte', description = 'Ramasser un item ou déclencher un ramassage.' },
    { value = 'deliver', label = 'Livraison', description = 'Déposer un item ou valider une livraison.' },
    { value = 'spawn', label = 'Spawn unique', description = 'Faire apparaître un NPC, un véhicule ou un prop unique.' },
    { value = 'multi_spawn', label = 'Multi spawn', description = 'Faire apparaître plusieurs entités aléatoires.' },
    { value = 'craft', label = 'Atelier / craft', description = 'Point pour lancer un craft ou une fabrication.' },
    { value = 'depot', label = 'Dépôt', description = 'Zone de dépôt ou retour véhicule.' },
    { value = 'repair', label = 'Réparation', description = 'Réparer un véhicule ou un prop.' },
    { value = 'scan', label = 'Scan / inspection', description = 'Scanner une zone, prendre des photos, etc.' },
    { value = 'generic', label = 'Générique', description = 'Point libre pour scripts personnalisés.' }
  },
  usage = {
    { value = 'point', label = 'Point unique', description = 'Un point précis déclenché une fois.' },
    { value = 'spawn', label = 'Spawn', description = 'Un seul spawn de NPC / véhicule.' },
    { value = 'multi', label = 'Multi-Spawn', description = 'Liste de points utilisés en rotation.' }
  },
  modes = {
    { value = 'point', label = 'Mode Point', description = 'Marker simple au sol.' },
    { value = 'zone', label = 'Mode Zone', description = 'Cercle avec radius pour capture ou zone d\'action.' }
  }
}

-- Command to open UI: /outlawjob
