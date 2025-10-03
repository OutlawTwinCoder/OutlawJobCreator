-- server/main.lua
local ResourceName = GetCurrentResourceName()

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

  local transactionQueries = {}
  for _, stmt in ipairs(statements) do
    transactionQueries[#transactionQueries+1] = { query = stmt }
  end

  local ok, err = MySQL.transaction.await(transactionQueries)
  if ok == false or ok == nil then
    return false, err or 'transaction_failed'
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
  TriggerClientEvent('outlawjob:client:openUI', src, capabilities)
end)

RegisterNetEvent('outlawjob:requestJobs', function()
  local src = source
  if not Config.UseOxmysql then
    TriggerClientEvent('outlawjob:client:receiveJobs', src, {})
    return
  end
  local rows = MySQL.query.await('SELECT id, job_name, label, tag, color, icon, society_name, default_salary, created_at FROM outlaw_jobs ORDER BY id DESC', {})
  TriggerClientEvent('outlawjob:client:receiveJobs', src, rows or {})
end)

RegisterNetEvent('outlawjob:createJob', function(data)
  local src = source
  if not canManage(src) then
    return notify(src, 'Permission refusée.')
  end
  if not data or not data.job_name or not data.label then
    return notify(src, 'Champs requis manquants (job_name, label).')
  end
  local job_name  = tostring(data.job_name):sub(1, 64)
  local label     = tostring(data.label):sub(1, 128)
  local tag       = tostring(data.tag or ''):sub(1, 32)
  local icon      = tostring(data.icon or ''):sub(1, 128)
  local color     = tostring(data.color or ''):sub(1, 16)
  local society   = tostring(data.society or ''):sub(1, 64)
  local salary    = tonumber(data.default_salary or 0) or 0
  local created_by = primaryIdentifier(src)

  MySQL.insert.await([[INSERT INTO outlaw_jobs (job_name, label, tag, icon, color, society_name, default_salary, created_by)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
      label=VALUES(label), tag=VALUES(tag), icon=VALUES(icon),
      color=VALUES(color), society_name=VALUES(society_name), default_salary=VALUES(default_salary)]],
    {job_name, label, tag, icon, color, society, salary, created_by})

  notify(src, ('Job %s enregistré.'):format(label))
  logAction(created_by, 'create_job', {
    job_name = job_name,
    label = label,
    tag = tag
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
  local rows = MySQL.query.await('SELECT id, label, x, y, z, heading, radius, type, created_at FROM outlaw_job_points WHERE job_id = ? ORDER BY id DESC', {jobId})
  TriggerClientEvent('outlawjob:client:receivePoints', src, rows or {})
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
