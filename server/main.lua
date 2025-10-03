-- server/main.lua
local ResourceName = GetCurrentResourceName()

local tableExistsCache = {}
local columnExistsCache = {}

local function clearDbCache()
  tableExistsCache = {}
  columnExistsCache = {}
end

local function wrapIdentifier(name)
  return ('`%s`'):format((name or ''):gsub('`', '``'))
end

local function dbTableExists(name)
  if not Config.UseOxmysql then return false end
  if not name or name == '' then return false end
  local cached = tableExistsCache[name]
  if cached ~= nil then return cached end
  local ok, rows = pcall(function()
    return MySQL.query.await('SHOW TABLES LIKE ?', {name})
  end)
  local exists = ok and rows and #rows > 0 or false
  tableExistsCache[name] = exists
  return exists
end

local function dbColumnExists(tableName, columnName)
  if not Config.UseOxmysql then return false end
  if not tableName or tableName == '' or not columnName or columnName == '' then
    return false
  end
  local key = ('%s:%s'):format(tableName, columnName)
  local cached = columnExistsCache[key]
  if cached ~= nil then return cached end
  local ok, rows = pcall(function()
    return MySQL.query.await(('SHOW COLUMNS FROM %s LIKE ?'):format(wrapIdentifier(tableName)), {columnName})
  end)
  local exists = ok and rows and #rows > 0 or false
  columnExistsCache[key] = exists
  return exists
end

local function checksum(str)
  if not str or str == '' then return '0' end
  return ('%08x'):format(GetHashKey(str))
end

local function ensureUniqueIndex(tableName, indexName, columnClause)
  local rows = MySQL.query.await(('SHOW INDEX FROM `%s` WHERE Key_name = ?'):format(tableName), {indexName})
  if rows and #rows > 0 then
    return
  end
  MySQL.query.await(('ALTER TABLE `%s` ADD UNIQUE INDEX `%s` (%s)'):format(tableName, indexName, columnClause))
end

local function ensureMigrationTable()
  if not Config.UseOxmysql then return end
  MySQL.query.await([[CREATE TABLE IF NOT EXISTS `outlaw_job_migrations` (
      `id` INT AUTO_INCREMENT PRIMARY KEY,
      `filename` VARCHAR(255) NOT NULL,
      `checksum` VARCHAR(64) NOT NULL,
      `applied_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      `applied_by` VARCHAR(64) DEFAULT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])
  MySQL.query.await([[ALTER TABLE `outlaw_job_migrations`
    ADD COLUMN IF NOT EXISTS `applied_by` VARCHAR(64) DEFAULT NULL;]])
  ensureUniqueIndex('outlaw_job_migrations', 'idx_outlaw_job_migrations_filename', '`filename`')
end

local function readMigrationManifest()
  local list = {}
  local manifestFile = Config.Migration and Config.Migration.manifestFile
  if manifestFile then
    local payload = LoadResourceFile(ResourceName, manifestFile)
    if payload then
      local ok, data = pcall(json.decode, payload)
      if ok and data then
        local items = data.migrations or data
        if type(items) == 'table' then
          for _, entry in ipairs(items) do
            if type(entry) == 'string' then
              list[#list+1] = entry
            end
          end
        end
      end
    end
  end

  table.sort(list)
  return list
end

local function loadMigrationSql(name)
  local path = ('migrations/%s'):format(name)
  local sql = LoadResourceFile(ResourceName, path)
  if not sql then
    print(('[OutlawJobCreator] Migration file missing: %s'):format(path))
  end
  return sql
end

local function sanitiseStatement(stmt)
  stmt = stmt:gsub('%/%*.-%*%/', '')
  local cleaned = {}
  for line in stmt:gmatch('[^\n]+') do
    if not line:match('^%s*%-%-') then
      cleaned[#cleaned+1] = line
    end
  end
  return table.concat(cleaned, '\n')
end

local function splitStatements(sql)
  local statements = {}
  local buffer = ''
  for chunk in sql:gmatch('[^;]+;') do
    buffer = buffer .. chunk
    if buffer:find(';', 1, true) then
      local statement = buffer:gsub(';+$', '')
      statement = sanitiseStatement(statement):gsub('^%s+', ''):gsub('%s+$', '')
      if statement ~= '' then
        statements[#statements+1] = statement
      end
      buffer = ''
    end
  end
  buffer = buffer:gsub('%s+', '')
  if buffer ~= '' then
    statements[#statements+1] = sanitiseStatement(buffer)
  end
  return statements
end

local function executeStatements(statements)
  if #statements == 0 then
    return true
  end

  for _, stmt in ipairs(statements) do
    if stmt and stmt ~= '' then
      local ok, result = pcall(function()
        return MySQL.query.await(stmt, {})
      end)
      if not ok then
        return false, result
      end
      if result == nil then
        return false, 'query_failed'
      end
    end
  end

  return true
end

local function getMigrationRows()
  local rows = MySQL.query.await('SELECT id, filename, checksum, applied_at, applied_by FROM outlaw_job_migrations', {})
  local map = {}
  for _, row in ipairs(rows or {}) do
    map[row.filename] = row
  end
  return map
end

local function buildMigrationStatus()
  ensureMigrationTable()
  local manifest = readMigrationManifest()
  local appliedMap = getMigrationRows()
  local list = {}

  for _, name in ipairs(manifest) do
    local sql = loadMigrationSql(name)
    local cs = sql and checksum(sql) or '0'
    local row = appliedMap[name]
    local status = {
      name = name,
      checksum = cs,
      applied = false,
      applied_at = nil,
      applied_by = nil,
      checksumMismatch = false,
      missing = sql == nil
    }

    if row then
      status.applied = row.checksum == cs
      status.applied_at = row.applied_at
      status.applied_by = row.applied_by
      status.checksumMismatch = row.checksum ~= cs
    end

    list[#list+1] = status
  end

  return list
end

local function recordMigration(name, cs, actor)
  actor = actor or 'system'
  local rows = MySQL.query.await('SELECT id FROM outlaw_job_migrations WHERE filename = ?', {name})
  if rows and rows[1] then
    MySQL.update.await('UPDATE outlaw_job_migrations SET checksum = ?, applied_at = CURRENT_TIMESTAMP, applied_by = ? WHERE id = ?', {cs, actor, rows[1].id})
  else
    MySQL.insert.await('INSERT INTO outlaw_job_migrations (filename, checksum, applied_by) VALUES (?,?,?)', {name, cs, actor})
  end
end

local function jobFormConfig()
  local defaults = Config.JobForm or {}
  return {
    defaultIcon = defaults.defaultIcon,
    defaultColor = defaults.defaultColor,
    defaultTag = defaults.defaultTag,
    defaultSalary = defaults.defaultSalary,
    defaultSocietyPrefix = defaults.defaultSocietyPrefix,
    defaultWhitelisted = defaults.defaultWhitelisted,
    iconOptions = defaults.iconOptions or {},
    colorOptions = defaults.colorOptions or {}
  }
end

local function pointOptionsConfig()
  local options = Config.PointOptions or {}
  return {
    types = options.types or {},
    usage = options.usage or {},
    modes = options.modes or {}
  }
end

local function jobConnectorMeta()
  local meta = {}
  local cfg = Config.JobIntegrations and Config.JobIntegrations.connectors or {}
  for key, def in pairs(cfg) do
    meta[key] = { label = def.label or key }
  end
  return meta
end

local function buildBootstrapPayload()
  return {
    jobForm = jobFormConfig(),
    pointOptions = pointOptionsConfig(),
    jobConnectors = jobConnectorMeta()
  }
end

local function normaliseSocietyName(jobName, provided)
  if provided and provided ~= '' then
    return tostring(provided):sub(1, 64)
  end
  local defaults = Config.JobForm or {}
  local prefix = defaults.defaultSocietyPrefix or 'society_'
  local base = tostring(jobName or '')
  return (prefix .. base):sub(1, 64)
end

local function ensureSocietyAccount(accountName)
  if not accountName or accountName == '' then return end
  if Config.JobIntegrations and Config.JobIntegrations.includeAddonAccount == false then return end
  if not dbTableExists('addon_account_data') then return end
  MySQL.insert.await([[INSERT INTO addon_account_data (account_name, money)
    VALUES (?, 0)
    ON DUPLICATE KEY UPDATE account_name = VALUES(account_name)]], {accountName})
end

local function fetchOutlawJobsMap()
  local rows = MySQL.query.await('SELECT id, job_name, label, tag, icon, color, society_name, default_salary FROM outlaw_jobs', {})
  local map = {}
  for _, row in ipairs(rows or {}) do
    map[row.job_name] = row
  end
  return map
end

local function fetchPointCounts()
  local rows = MySQL.query.await('SELECT job_id, COUNT(*) AS total FROM outlaw_job_points GROUP BY job_id', {})
  local map = {}
  for _, row in ipairs(rows or {}) do
    map[row.job_id] = row.total or 0
  end
  return map
end

local function fetchAddonAccountBalances()
  if Config.JobIntegrations and Config.JobIntegrations.includeAddonAccount == false then
    return {}
  end
  if not dbTableExists('addon_account_data') then
    return {}
  end
  local rows = MySQL.query.await('SELECT account_name, money FROM addon_account_data', {})
  local map = {}
  for _, row in ipairs(rows or {}) do
    map[row.account_name] = row.money or 0
  end
  return map
end

local function fetchBillingMap()
  if Config.JobIntegrations and Config.JobIntegrations.includeBilling == false then
    return {}
  end
  if not dbTableExists('billing') then
    return {}
  end
  local rows = MySQL.query.await('SELECT target, COUNT(*) AS total, COALESCE(SUM(amount), 0) AS amount FROM billing GROUP BY target', {})
  local map = {}
  for _, row in ipairs(rows or {}) do
    map[row.target] = {
      count = row.total or 0,
      amount = row.amount or 0
    }
  end
  return map
end

local function fetchEmployeeCounts()
  if Config.JobIntegrations and Config.JobIntegrations.includeUsers == false then
    return {}
  end
  if not dbTableExists('users') or not dbColumnExists('users', 'job') then
    return {}
  end
  local rows = MySQL.query.await('SELECT job AS job, COUNT(*) AS total FROM users GROUP BY job', {})
  local map = {}
  for _, row in ipairs(rows or {}) do
    map[row.job] = row.total or 0
  end
  return map
end

local function fetchConnectorCounts(tableName, jobField)
  if not tableName or tableName == '' or not jobField or jobField == '' then
    return {}
  end
  if not dbTableExists(tableName) or not dbColumnExists(tableName, jobField) then
    return {}
  end
  local sql = ('SELECT %s AS job, COUNT(*) AS total FROM %s GROUP BY %s')
    :format(wrapIdentifier(jobField), wrapIdentifier(tableName), wrapIdentifier(jobField))
  local ok, rows = pcall(function()
    return MySQL.query.await(sql, {})
  end)
  if not ok or not rows then
    return {}
  end
  local map = {}
  for _, row in ipairs(rows) do
    if row.job then
      map[row.job] = row.total or 0
    end
  end
  return map
end

local function fetchBaseJobs()
  local integrations = Config.JobIntegrations or {}
  local baseTable = integrations.baseTable
  local nameField = integrations.nameField or 'name'
  local labelField = integrations.labelField or 'label'
  local whitelistedField = integrations.whitelistedField

  if baseTable and baseTable ~= '' and dbTableExists(baseTable) then
    local whitelistClause = ', 0 AS whitelisted'
    if whitelistedField and dbColumnExists(baseTable, whitelistedField) then
      whitelistClause = (', COALESCE(%s, 0) AS whitelisted'):format(wrapIdentifier(whitelistedField))
    end
    local sql = ('SELECT %s AS name, %s AS label%s FROM %s ORDER BY %s ASC')
      :format(wrapIdentifier(nameField), wrapIdentifier(labelField), whitelistClause, wrapIdentifier(baseTable), wrapIdentifier(labelField))
    local ok, rows = pcall(function()
      return MySQL.query.await(sql, {})
    end)
    if ok and rows then
      return rows
    end
  end

  local fallback = MySQL.query.await('SELECT job_name AS name, label, 0 AS whitelisted FROM outlaw_jobs ORDER BY label ASC', {})
  return fallback or {}
end

local function fetchJobSummaries()
  if not Config.UseOxmysql then
    return {}
  end

  local defaults = Config.JobForm or {}
  local baseJobs = fetchBaseJobs()
  local outlawMap = fetchOutlawJobsMap()
  local pointsMap = fetchPointCounts()
  local accounts = fetchAddonAccountBalances()
  local billing = fetchBillingMap()
  local employees = fetchEmployeeCounts()

  local connectorCounts = {}
  local connectorMeta = Config.JobIntegrations and Config.JobIntegrations.connectors or {}
  for key, def in pairs(connectorMeta) do
    connectorCounts[key] = fetchConnectorCounts(def.table, def.jobField)
  end

  local list = {}
  for _, job in ipairs(baseJobs) do
    local jobName = job.name
    local outlaw = outlawMap[jobName]
    local societyName = normaliseSocietyName(jobName, outlaw and outlaw.society_name)
    local blueprintId = outlaw and outlaw.id or nil
    local billingInfo = billing[societyName]
    local entry = {
      name = jobName,
      label = job.label,
      whitelisted = job.whitelisted == true or job.whitelisted == 1,
      blueprint_id = blueprintId,
      tag = outlaw and outlaw.tag or defaults.defaultTag,
      icon = outlaw and outlaw.icon or defaults.defaultIcon,
      color = outlaw and outlaw.color or defaults.defaultColor,
      society_name = societyName,
      society_balance = accounts[societyName],
      has_society_account = accounts[societyName] ~= nil,
      default_salary = outlaw and outlaw.default_salary or defaults.defaultSalary,
      points = blueprintId and (pointsMap[blueprintId] or 0) or 0,
      employees = employees[jobName] or 0,
      billing = {
        count = billingInfo and billingInfo.count or 0,
        amount = billingInfo and billingInfo.amount or 0
      },
      connectors = {}
    }
    for key, map in pairs(connectorCounts) do
      entry.connectors[key] = map[jobName] or 0
    end
    list[#list+1] = entry
  end

  table.sort(list, function(a, b)
    return tostring(a.label or a.name) < tostring(b.label or b.name)
  end)

  return list
end

local function logAction(actor, action, payload)
  if not Config.UseOxmysql then return end
  payload = payload or {}
  payload.resource = ResourceName
  MySQL.insert.await([[INSERT INTO outlaw_job_logs (actor_identifier, action, details)
    VALUES (?,?,?)]], {actor, action, json.encode(payload)})
end

local function applyMigration(name, sql, actor)
  if not sql then
    return false, 'missing_sql'
  end
  local statements = splitStatements(sql)
  local ok, err = executeStatements(statements)
  if not ok then
    return false, err
  end

  local cs = checksum(sql)
  recordMigration(name, cs, actor)
  logAction(actor, 'migration_apply', {migration = name, checksum = cs})
  clearDbCache()
  return true
end

local function applyPendingMigrations(actor)
  ensureMigrationTable()
  local statuses = buildMigrationStatus()
  local results = {}
  for _, status in ipairs(statuses) do
    if status.missing then
      results[#results+1] = { name = status.name, status = 'missing' }
    elseif status.applied and not status.checksumMismatch then
      results[#results+1] = { name = status.name, status = 'already_applied' }
    else
      local sql = loadMigrationSql(status.name)
      local ok, err = applyMigration(status.name, sql, actor)
      results[#results+1] = { name = status.name, status = ok and 'applied' or 'error', error = err }
    end
  end
  return results
end

local function forceReapplyMigration(name, actor)
  local sql = loadMigrationSql(name)
  if not sql then
    return false, 'missing_sql'
  end
  local ok, err = applyMigration(name, sql, actor)
  if not ok then
    return false, err
  end
  return true
end

local function normaliseHeading(value)
  local h = (tonumber(value) or 0.0) % 360.0
  if h < 0.0 then
    h = h + 360.0
  end
  return h
end

local function round(value, decimals)
  decimals = decimals or 3
  local power = 10 ^ decimals
  return math.floor((value * power) + 0.5) / power
end

local function tryGroundSnap(coords)
  if type(GetGroundZFor_3dCoord) ~= 'function' then
    return false, coords.z
  end
  local ok, found, groundZ = pcall(function()
    return GetGroundZFor_3dCoord(coords.x, coords.y, coords.z, 0.0)
  end)
  if not ok then
    return false, coords.z
  end
  return found, groundZ or coords.z
end

local function tryWaterHeight(coords, probeHeight)
  if type(GetWaterHeight) ~= 'function' then
    return false, coords.z
  end
  local ok, hasWater, waterZ = pcall(function()
    return GetWaterHeight(coords.x, coords.y, coords.z, probeHeight or coords.z)
  end)
  if not ok then
    return false, coords.z
  end
  return hasWater, waterZ or coords.z
end

local AllowedPointTypes = {
  collect = true,
  deliver = true,
  spawn = true,
  multi_spawn = true,
  craft = true,
  depot = true,
  repair = true,
  scan = true,
  generic = true
}

local function primaryIdentifier(src)
  local identifier = GetPlayerIdentifierByType and GetPlayerIdentifierByType(src, 'license')
  if identifier and identifier ~= '' then return identifier end
  local identifiers = GetPlayerIdentifiers(src)
  if identifiers and identifiers[1] then
    return identifiers[1]
  end
  return ('src:%s'):format(src)
end

local function validatePointData(src, data)
  if type(data) ~= 'table' then
    return false, nil, 'invalid_payload'
  end

  local jobId = tonumber(data.job_id)
  if not jobId or jobId <= 0 then
    return false, nil, 'invalid_job'
  end

  local mode = tostring(data.mode or 'point')
  if mode ~= 'point' and mode ~= 'zone' then
    mode = 'point'
  end

  local usage = tostring(data.usage or 'point')
  if usage ~= 'point' and usage ~= 'spawn' and usage ~= 'multi' then
    usage = 'point'
  end

  local pointType = tostring(data.type or 'generic')
  if not AllowedPointTypes[pointType] then
    pointType = 'generic'
  end

  local radius = tonumber(data.radius) or Config.PointValidation.minRadius
  radius = math.max(Config.PointValidation.minRadius, math.min(radius, Config.PointValidation.maxRadius))

  local heading = normaliseHeading(data.heading)

  local x = tonumber(data.x)
  local y = tonumber(data.y)
  local z = tonumber(data.z)

  if not x or not y or not z then
    return false, nil, 'invalid_coords'
  end

  local coords = vector3(x, y, z)
  local groundApplied = false
  if data.snap or data.autoSnap then
    local found, groundZ = tryGroundSnap(coords)
    if found then
      if math.abs(coords.z - groundZ) > Config.PointValidation.groundSnapTolerance then
        coords = vector3(coords.x, coords.y, groundZ)
        groundApplied = true
      end
    end
  end

  if Config.PointValidation.rejectWater then
    local probeHeight = coords.z
    local hasWater, waterZ = tryWaterHeight(coords, probeHeight)
    waterZ = waterZ or probeHeight
    if hasWater and coords.z <= (waterZ + Config.PointValidation.waterTolerance) then
      return false, nil, 'point_in_water'
    end
  end

  local existing
  if Config.UseOxmysql then
    existing = MySQL.query.await('SELECT id, x, y, z FROM outlaw_job_points WHERE job_id = ?', {jobId})
  end
  if existing then
    for _, row in ipairs(existing) do
      local distance = #(vector3(row.x, row.y, row.z) - coords)
      if distance < Config.PointValidation.minDistance then
        return false, nil, ('point_too_close_%d'):format(row.id)
      end
    end
  end

  local offset = data.offset or { x = 0.0, y = 0.0, z = 0.0 }
  offset.x = tonumber(offset.x) or 0.0
  offset.y = tonumber(offset.y) or 0.0
  offset.z = tonumber(offset.z) or 0.0

  local base = data.base or { x = coords.x, y = coords.y, z = coords.z, heading = heading }
  base.x = tonumber(base.x) or coords.x
  base.y = tonumber(base.y) or coords.y
  base.z = tonumber(base.z) or coords.z
  base.heading = normaliseHeading(base.heading)

  local multi = {}
  if type(data.multi) == 'table' then
    for _, entry in ipairs(data.multi) do
      local ex = tonumber(entry.x)
      local ey = tonumber(entry.y)
      local ez = tonumber(entry.z)
      local eh = normaliseHeading(entry.heading)
      if ex and ey and ez then
        multi[#multi+1] = {
          x = round(ex, 3),
          y = round(ey, 3),
          z = round(ez, 3),
          heading = round(eh, 2)
        }
      end
    end
  end

  local sanitized = {
    job_id = jobId,
    x = round(coords.x, 3),
    y = round(coords.y, 3),
    z = round(coords.z, 3),
    heading = round(heading, 2),
    radius = round(radius, 2),
    type = pointType,
    mode = mode,
    usage = usage,
    offset = {
      x = round(offset.x, 3),
      y = round(offset.y, 3),
      z = round(offset.z, 3)
    },
    base = {
      x = round(base.x, 3),
      y = round(base.y, 3),
      z = round(base.z, 3),
      heading = round(base.heading, 2)
    },
    multi = multi,
    snapped = groundApplied
  }

  sanitized.meta = json.encode({
    mode = sanitized.mode,
    usage = sanitized.usage,
    offset = sanitized.offset,
    base = sanitized.base,
    multi = sanitized.multi,
    snapped = sanitized.snapped,
    validatedAt = os.time()
  })

  return true, sanitized
end

local function sendMigrationStatus(src)
  local list = buildMigrationStatus()
  TriggerClientEvent('outlawjob:client:migrationsList', src, list)
end

local function notify(src, message)
  TriggerClientEvent('outlawjob:client:showNotify', src, message)
end

local function canManage(src)
  return Config.CanManageCreator(src)
end

-- Events
RegisterNetEvent('outlawjob:server:requestOpen', function()
  local src = source
  local capabilities = {
    canManage = canManage(src),
    canGetCoords = canManage(src),
    canApplyMigrations = canManage(src)
  }
  local bootstrap = buildBootstrapPayload()
  TriggerClientEvent('outlawjob:client:openUI', src, {
    capabilities = capabilities,
    bootstrap = bootstrap
  })
end)

RegisterNetEvent('outlawjob:requestJobs', function()
  local src = source
  if not Config.UseOxmysql then
    TriggerClientEvent('outlawjob:client:receiveJobs', src, {})
    return
  end
  local rows = fetchJobSummaries()
  TriggerClientEvent('outlawjob:client:receiveJobs', src, rows or {})
end)

RegisterNetEvent('outlawjob:createJob', function(data)
  local src = source
  if not canManage(src) then
    return notify(src, 'Permission refusée.')
  end
  if not Config.UseOxmysql then
    return notify(src, 'Base de données indisponible.')
  end
  if not data or not data.job_name or not data.label then
    return notify(src, 'Champs requis manquants (job_name, label).')
  end

  local defaults = Config.JobForm or {}
  local jobName = tostring(data.job_name or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 64)
  if jobName == '' then
    return notify(src, 'Nom de job invalide.')
  end
  local label = tostring(data.label or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 128)
  if label == '' then
    return notify(src, 'Label invalide.')
  end

  local tag = tostring(data.tag or defaults.defaultTag or ''):sub(1, 32)
  local icon = tostring(data.icon or defaults.defaultIcon or ''):sub(1, 128)
  local color = tostring(data.color or defaults.defaultColor or ''):sub(1, 16)
  local salary = tonumber(data.default_salary or defaults.defaultSalary or 0) or 0
  local society = normaliseSocietyName(jobName, data.society)
  local whitelisted = data.whitelisted and true or false
  local createdBy = primaryIdentifier(src)

  local integrations = Config.JobIntegrations or {}
  local baseTable = integrations.baseTable
  local nameField = integrations.nameField or 'name'
  local labelField = integrations.labelField or 'label'
  local whitelistedField = integrations.whitelistedField

  if baseTable and baseTable ~= '' and dbTableExists(baseTable) then
    local sql
    local params
    if whitelistedField and dbColumnExists(baseTable, whitelistedField) then
      sql = ('INSERT INTO %s (%s, %s, %s) VALUES (?,?,?) ON DUPLICATE KEY UPDATE %s = VALUES(%s), %s = VALUES(%s)')
        :format(wrapIdentifier(baseTable), wrapIdentifier(nameField), wrapIdentifier(labelField), wrapIdentifier(whitelistedField),
          wrapIdentifier(labelField), wrapIdentifier(labelField), wrapIdentifier(whitelistedField), wrapIdentifier(whitelistedField))
      params = {jobName, label, whitelisted and 1 or 0}
    else
      sql = ('INSERT INTO %s (%s, %s) VALUES (?,?) ON DUPLICATE KEY UPDATE %s = VALUES(%s)')
        :format(wrapIdentifier(baseTable), wrapIdentifier(nameField), wrapIdentifier(labelField), wrapIdentifier(labelField), wrapIdentifier(labelField))
      params = {jobName, label}
    end
    MySQL.insert.await(sql, params)
  end

  MySQL.insert.await([[INSERT INTO outlaw_jobs (job_name, label, tag, icon, color, society_name, default_salary, created_by)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      label=VALUES(label), tag=VALUES(tag), icon=VALUES(icon),
      color=VALUES(color), society_name=VALUES(society_name), default_salary=VALUES(default_salary)]],
    {jobName, label, tag, icon, color, society, salary, createdBy})

  local row = MySQL.query.await('SELECT id FROM outlaw_jobs WHERE job_name = ? LIMIT 1', {jobName})
  local jobId = row and row[1] and row[1].id or nil

  ensureSocietyAccount(society)

  notify(src, ('Job %s synchronisé.'):format(label))
  logAction(createdBy, 'create_job', {
    job_name = jobName,
    label = label,
    tag = tag,
    outlaw_job_id = jobId,
    whitelisted = whitelisted,
    default_salary = salary
  })
  TriggerClientEvent('outlawjob:client:requestJobsRefresh', src)
end)

RegisterNetEvent('outlawjob:syncOutlawJob', function(data)
  local src = source
  if not canManage(src) then
    return notify(src, 'Permission refusée.')
  end
  if not Config.UseOxmysql then
    return notify(src, 'Base de données indisponible.')
  end

  local jobName = data
  if type(data) == 'table' then
    jobName = data.job_name
  end
  jobName = tostring(jobName or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 64)
  if jobName == '' then
    return notify(src, 'Job invalide.')
  end

  local defaults = Config.JobForm or {}
  local integrations = Config.JobIntegrations or {}
  local baseTable = integrations.baseTable
  local nameField = integrations.nameField or 'name'
  local labelField = integrations.labelField or 'label'

  local label = jobName
  if baseTable and baseTable ~= '' and dbTableExists(baseTable) then
    local sql = ('SELECT %s AS label FROM %s WHERE %s = ? LIMIT 1')
      :format(wrapIdentifier(labelField), wrapIdentifier(baseTable), wrapIdentifier(nameField))
    local rows = MySQL.query.await(sql, {jobName})
    if rows and rows[1] and rows[1].label and rows[1].label ~= '' then
      label = rows[1].label
    end
  else
    local rows = MySQL.query.await('SELECT label FROM outlaw_jobs WHERE job_name = ? LIMIT 1', {jobName})
    if rows and rows[1] and rows[1].label and rows[1].label ~= '' then
      label = rows[1].label
    end
  end

  local existingRows = MySQL.query.await('SELECT id, label, tag, icon, color, society_name, default_salary FROM outlaw_jobs WHERE job_name = ? LIMIT 1', {jobName})
  local existing = existingRows and existingRows[1] or nil
  local society = normaliseSocietyName(jobName, existing and existing.society_name)
  local jobId

  if existing then
    jobId = existing.id
    MySQL.update.await('UPDATE outlaw_jobs SET label = ?, society_name = ? WHERE id = ?', {label, society, jobId})
  else
    local icon = defaults.defaultIcon or ''
    local color = defaults.defaultColor or ''
    local tag = defaults.defaultTag or ''
    local salary = defaults.defaultSalary or 0
    jobId = MySQL.insert.await([[INSERT INTO outlaw_jobs (job_name, label, tag, icon, color, society_name, default_salary, created_by)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)]],
      {jobName, label, tag, icon, color, society, salary, primaryIdentifier(src)})
  end

  ensureSocietyAccount(society)

  notify(src, ('Métadonnées Outlaw activées pour %s.'):format(label))
  logAction(primaryIdentifier(src), 'sync_job', {
    job_name = jobName,
    outlaw_job_id = jobId,
    society = society
  })
  TriggerClientEvent('outlawjob:client:requestJobsRefresh', src)
end)

RegisterNetEvent('outlawjob:validatePoint', function(requestId, data)
  local src = source
  if not canManage(src) then
    return
  end
  local ok, sanitized, reason = validatePointData(src, data)
  TriggerClientEvent('outlawjob:client:validationResult', src, requestId, ok, sanitized, reason)
end)

RegisterNetEvent('outlawjob:createPoint', function(data)
  local src = source
  if not canManage(src) then
    return notify(src, 'Permission refusée.')
  end

  local ok, sanitized, reason = validatePointData(src, data)
  if not ok then
    return notify(src, ('Validation échouée: %s'):format(reason or 'inconnu'))
  end

  local label = tostring(data.label or ''):sub(1, 128)
  MySQL.insert.await([[INSERT INTO outlaw_job_points (job_id, label, x, y, z, heading, radius, type, meta)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]],
    { sanitized.job_id, label, sanitized.x, sanitized.y, sanitized.z, sanitized.heading, sanitized.radius, sanitized.type, sanitized.meta })

  local actor = primaryIdentifier(src)
  notify(src, ('Point %s enregistré.'):format(label ~= '' and label or '#'))
  logAction(actor, 'create_point', {
    job_id = sanitized.job_id,
    label = label,
    coords = { sanitized.x, sanitized.y, sanitized.z },
    heading = sanitized.heading,
    radius = sanitized.radius,
    type = sanitized.type,
    mode = sanitized.mode,
    usage = sanitized.usage
  })
end)

RegisterNetEvent('outlawjob:getMigrations', function()
  local src = source
  if not canManage(src) then
    return notify(src, 'Permission refusée.')
  end
  sendMigrationStatus(src)
end)

RegisterNetEvent('outlawjob:applyMigrations', function()
  local src = source
  if not canManage(src) then
    return notify(src, 'Permission refusée.')
  end
  local actor = primaryIdentifier(src)
  local results = applyPendingMigrations(actor)
  TriggerClientEvent('outlawjob:client:migrationResult', src, results)
  sendMigrationStatus(src)
end)

RegisterNetEvent('outlawjob:forceMigration', function(name)
  local src = source
  if not canManage(src) then
    return notify(src, 'Permission refusée.')
  end
  if not name or name == '' then
    return notify(src, 'Migration invalide.')
  end
  local actor = primaryIdentifier(src)
  local ok, err = forceReapplyMigration(name, actor)
  if ok then
    notify(src, ('Migration %s ré-appliquée.'):format(name))
  else
    notify(src, ('Erreur migration %s: %s'):format(name, err or 'inconnue'))
  end
  sendMigrationStatus(src)
end)

RegisterNetEvent('outlawjob:requestPoints', function(jobId)
  local src = source
  if not canManage(src) then
    return notify(src, 'Permission refusée.')
  end
  jobId = tonumber(jobId)
  if not jobId then
    return
  end
  local rows = MySQL.query.await('SELECT id, job_id, label, x, y, z, heading, radius, type, meta, created_at FROM outlaw_job_points WHERE job_id = ? ORDER BY id DESC', {jobId})
  local list = {}
  for _, row in ipairs(rows or {}) do
    local mode, usage
    if row.meta and row.meta ~= '' then
      local ok, decoded = pcall(json.decode, row.meta)
      if ok and decoded then
        mode = decoded.mode or mode
        usage = decoded.usage or usage
        row.meta = decoded
      end
    end
    row.mode = row.mode or mode
    row.usage = row.usage or usage
    list[#list+1] = row
  end
  TriggerClientEvent('outlawjob:client:receivePoints', src, list)
end)

AddEventHandler('onResourceStart', function(res)
  if res ~= ResourceName then return end
  if not Config.UseOxmysql then
    print('[OutlawJobCreator] WARNING: Config.UseOxmysql=false; no DB bootstrap.')
    return
  end

  ensureMigrationTable()
  if Config.MigrationAutoApply then
    print('[OutlawJobCreator] Checking migrations...')
    local results = applyPendingMigrations('system')
    for _, result in ipairs(results) do
      if result.status == 'applied' then
        print(('[OutlawJobCreator] Applied migration %s'):format(result.name))
      elseif result.status == 'already_applied' then
        print(('[OutlawJobCreator] Migration already applied %s'):format(result.name))
      elseif result.status == 'missing' then
        print(('[OutlawJobCreator] Migration missing %s'):format(result.name))
      elseif result.status == 'error' then
        print(('[OutlawJobCreator] Migration error %s: %s'):format(result.name, result.error or 'unknown'))
      end
    end
  else
    print('[OutlawJobCreator] Migration auto-apply disabled.')
  end
end)
