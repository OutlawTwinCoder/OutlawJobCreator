-- server/main.lua
local RESOURCE_NAME = GetCurrentResourceName()
local Config = Config or {}

local allowedIdentifiers = {}
for _, identifier in ipairs(Config.ManagerIdentifiers or {}) do
  if type(identifier) == 'string' then
    allowedIdentifiers[identifier] = true
  end
end

local function trim(str)
  return (str:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function splitStatements(sql)
  local sanitized = sql:gsub('%-%-[^\n]*', '\n')
  local statements = {}
  for statement in sanitized:gmatch('([^;]+);') do
    local cleaned = trim(statement)
    if cleaned ~= '' then
      table.insert(statements, cleaned)
    end
  end
  return statements
end

local function checksum(str)
  local first = GetHashKey(str)
  local second = GetHashKey(str .. tostring(#str))
  return string.format('%08x%08x', first & 0xffffffff, second & 0xffffffff)
end

local function readJsonFile(path)
  local raw = LoadResourceFile(RESOURCE_NAME, path)
  if not raw then return nil end
  local ok, data = pcall(json.decode, raw)
  if not ok then return nil end
  return data
end

local function isWindows()
  return package.config:sub(1, 1) == '\\'
end

local function listMigrationFiles()
  local list = readJsonFile('migrations/index.json')
  if type(list) == 'table' and #list > 0 then
    return list
  end

  local files = {}
  local path = GetResourcePath(RESOURCE_NAME) .. '/migrations'
  local command = isWindows() and ('dir /b "%s"'):format(path) or ('ls -1 "%s"'):format(path)
  local handle = io.popen(command)
  if handle then
    for line in handle:lines() do
      if line:match('%.sql$') then
        table.insert(files, line)
      end
    end
    handle:close()
  end
  table.sort(files)
  return files
end

local function ensureMigrationTable()
  MySQL.rawExecute.await([[ 
    CREATE TABLE IF NOT EXISTS `outlaw_job_migrations` (
      `id` INT AUTO_INCREMENT PRIMARY KEY,
      `filename` VARCHAR(255) NOT NULL,
      `checksum` VARCHAR(64) NOT NULL,
      `applied_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      `applied_by` VARCHAR(64) DEFAULT 'system',
      UNIQUE KEY `uniq_outlaw_migrations` (`filename`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]])
end

local MigrationManager = {
  list = {},
  applied = {}
}

function MigrationManager:refreshList()
  local files = listMigrationFiles()
  local entries = {}
  for _, filename in ipairs(files) do
    local sql = LoadResourceFile(RESOURCE_NAME, ('migrations/%s'):format(filename))
    if sql then
      table.insert(entries, {
        name = filename,
        sql = sql,
        checksum = checksum(sql)
      })
    else
      print(('[OutlawJobCreator] Unable to read migration file %s'):format(filename))
    end
  end
  table.sort(entries, function(a, b) return a.name < b.name end)
  self.list = entries
end

function MigrationManager:refreshApplied()
  ensureMigrationTable()
  local rows = MySQL.query.await('SELECT filename, checksum, applied_at, applied_by FROM outlaw_job_migrations') or {}
  local map = {}
  for _, row in ipairs(rows) do
    map[row.filename] = row
  end
  self.applied = map
  return rows
end

function MigrationManager:getMeta(name)
  for _, entry in ipairs(self.list) do
    if entry.name == name then
      return entry
    end
  end
end

function MigrationManager:getStatus()
  self:refreshList()
  local appliedRows = self:refreshApplied()
  local pending = {}
  for _, entry in ipairs(self.list) do
    local applied = self.applied[entry.name]
    if not applied or not applied.checksum or applied.checksum ~= entry.checksum then
      table.insert(pending, {
        name = entry.name,
        checksum = entry.checksum
      })
    end
  end
  return {
    applied = appliedRows,
    pending = pending
  }
end

function MigrationManager:runStatements(statements)
  for _, statement in ipairs(statements) do
    local ok, err = pcall(function()
      MySQL.rawExecute.await(statement)
    end)
    if not ok then
      return false, err
    end
  end
  return true
end

function MigrationManager:applyMigration(meta, appliedBy)
  ensureMigrationTable()
  local statements = splitStatements(meta.sql)
  local ok, err = self:runStatements(statements)
  if not ok then
    return false, err
  end

  MySQL.insert.await([[INSERT INTO outlaw_job_migrations (filename, checksum, applied_by)
    VALUES (?, ?, ?)
    ON DUPLICATE KEY UPDATE checksum = VALUES(checksum), applied_at = CURRENT_TIMESTAMP, applied_by = VALUES(applied_by)
  ]], { meta.name, meta.checksum, appliedBy or 'system' })

  self.applied[meta.name] = {
    filename = meta.name,
    checksum = meta.checksum,
    applied_by = appliedBy or 'system'
  }
  return true
end

function MigrationManager:applyPending(appliedBy)
  local status = self:getStatus()
  local appliedList = {}
  for _, pending in ipairs(status.pending) do
    local meta = self:getMeta(pending.name)
    if meta then
      local ok, err = self:applyMigration(meta, appliedBy)
      if not ok then
        return false, err, appliedList
      end
      table.insert(appliedList, meta.name)
    end
  end
  return true, appliedList
end

function MigrationManager:forceReapply(name, appliedBy)
  ensureMigrationTable()
  local meta = self:getMeta(name)
  if not meta then
    return false, 'Migration introuvable'
  end
  MySQL.execute.await('DELETE FROM outlaw_job_migrations WHERE filename = ?', { name })
  local ok, err = self:applyMigration(meta, appliedBy)
  if not ok then
    return false, err
  end
  return true
end

function MigrationManager:pushStatus(target)
  local status = self:getStatus()
  TriggerClientEvent('outlawjob:client:migrationsStatus', target, status)
end

local function getPrimaryIdentifier(src)
  if src == 0 then
    return 'console'
  end
  for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
    if identifier:find('license:') then
      return identifier
    end
  end
  for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
    if identifier:find('steam:') then
      return identifier
    end
  end
  return GetPlayerIdentifier(src, 0) or ('src:' .. tostring(src))
end

local function logAction(src, action, details)
  if not Config.EnableActionLogs then return end
  local payload = details or {}
  local ok, err = pcall(function()
    MySQL.insert.await('INSERT INTO outlaw_job_logs (actor_identifier, action, details) VALUES (?, ?, ?)', {
      getPrimaryIdentifier(src),
      action,
      json.encode(payload)
    })
  end)
  if not ok then
    print(('[OutlawJobCreator] Failed to write log for %s: %s'):format(action, err))
  end
end

local function isPlayerManager(src)
  if src == 0 then return true end
  if Config.RequiredAcePermission and Config.RequiredAcePermission ~= '' then
    if IsPlayerAceAllowed(src, Config.RequiredAcePermission) then
      return true
    end
  end
  if next(allowedIdentifiers) then
    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
      if allowedIdentifiers[identifier] then
        return true
      end
    end
  end
  return false
end

local function sendPermissions(src)
  TriggerClientEvent('outlawjob:client:setPermissions', src, {
    canManage = isPlayerManager(src)
  })
end

local function sendJobsList(src)
  local jobs = MySQL.query.await([[SELECT id, job_name, label, tag, color, icon, society_name, default_salary FROM outlaw_jobs ORDER BY id DESC]]) or {}
  TriggerClientEvent('outlawjob:client:receiveJobs', src, jobs)
end

local function notify(src, message)
  TriggerClientEvent('outlawjob:client:showNotify', src, message)
end

local function validateJobData(data)
  if not data then return false, 'Données manquantes' end
  if not data.job_name or trim(data.job_name) == '' then
    return false, 'job_name requis'
  end
  if not data.label or trim(data.label) == '' then
    return false, 'label requis'
  end
  return true
end

local function sanitizeNumber(value, default)
  local num = tonumber(value)
  if not num then return default end
  return num
end

local function sanitizeCoords(data)
  return {
    x = sanitizeNumber(data.x, 0.0),
    y = sanitizeNumber(data.y, 0.0),
    z = sanitizeNumber(data.z, 0.0),
    heading = sanitizeNumber(data.heading or data.h, 0.0),
    radius = sanitizeNumber(data.radius, 2.0)
  }
end

local function isPointInWater(coords)
  local tolerance = Config.WaterTolerance or 0.2
  local success, waterZ = GetWaterHeight(coords.x, coords.y, coords.z + 1.0)
  if success and (coords.z - waterZ) <= tolerance then
    return true, waterZ
  end
  success, waterZ = GetWaterHeightNoWaves(coords.x, coords.y, coords.z + 1.0)
  if success and (coords.z - waterZ) <= tolerance then
    return true, waterZ
  end
  return false
end

local function snapToGround(coords)
  local success, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 10.0, false)
  if success then
    coords.z = groundZ
    return true, groundZ
  end
  return false
end

local function validateRadius(radius)
  local limits = Config.RadiusLimits or { min = 0.5, max = 100.0 }
  if radius < limits.min then
    return false, ('Radius trop petit (min %.1f)'):format(limits.min)
  end
  if radius > limits.max then
    return false, ('Radius trop grand (max %.1f)'):format(limits.max)
  end
  return true
end

local function checkInterior(coords)
  local interior = GetInteriorAtCoords(coords.x, coords.y, coords.z)
  if interior ~= 0 and Config.RestrictedInteriors and Config.RestrictedInteriors[interior] then
    return false, 'Intérieur non autorisé'
  end
  return true
end

local function checkPointDistance(jobId, coords)
  local rows = MySQL.query.await('SELECT id, x, y, z FROM outlaw_job_points WHERE job_id = ?', { jobId }) or {}
  for _, row in ipairs(rows) do
    local dx = row.x - coords.x
    local dy = row.y - coords.y
    local dz = row.z - coords.z
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist < (Config.PointMinDistance or 1.0) then
      return false, ('Trop proche du point #%d (%.2fm)'):format(row.id, dist)
    end
  end
  return true
end

local function validateAndPersistPoint(src, requestId, payload)
  if not payload then
    TriggerClientEvent('outlawjob:client:validationResult', src, requestId, { ok = false, error = 'Payload vide' })
    return
  end

  local canManage = isPlayerManager(src)
  if not canManage then
    TriggerClientEvent('outlawjob:client:validationResult', src, requestId, { ok = false, error = 'Permissions insuffisantes' })
    return
  end

  local jobId = tonumber(payload.job_id)
  if not jobId or jobId <= 0 then
    TriggerClientEvent('outlawjob:client:validationResult', src, requestId, { ok = false, error = 'job_id invalide' })
    return
  end

  local jobExists = MySQL.scalar.await('SELECT COUNT(1) FROM outlaw_jobs WHERE id = ?', { jobId }) or 0
  if jobExists <= 0 then
    TriggerClientEvent('outlawjob:client:validationResult', src, requestId, { ok = false, error = 'Job introuvable' })
    return
  end

  local coords = sanitizeCoords(payload)
  local warnings = {}

  if Config.AutoSnapToGround then
    local snapped, groundZ = snapToGround(coords)
    if snapped then
      table.insert(warnings, ('Coordonnée ajustée au sol (%.2f)'):format(groundZ))
    end
  end

  local radiusOk, radiusError = validateRadius(coords.radius)
  if not radiusOk then
    TriggerClientEvent('outlawjob:client:validationResult', src, requestId, { ok = false, error = radiusError })
    return
  end

  local water, waterZ = isPointInWater(coords)
  if water then
    TriggerClientEvent('outlawjob:client:validationResult', src, requestId, { ok = false, error = 'Point dans l\'eau', waterZ = waterZ })
    return
  end

  local interiorOk, interiorError = checkInterior(coords)
  if not interiorOk then
    TriggerClientEvent('outlawjob:client:validationResult', src, requestId, { ok = false, error = interiorError })
    return
  end

  local distanceOk, distanceError = checkPointDistance(jobId, coords)
  if not distanceOk then
    TriggerClientEvent('outlawjob:client:validationResult', src, requestId, { ok = false, error = distanceError })
    return
  end

  local meta = payload.meta
  if type(meta) ~= 'table' then meta = {} end
  local success, metaJson = pcall(json.encode, meta)
  if not success then
    metaJson = '{}'
  end

  local insertedId = MySQL.insert.await([[INSERT INTO outlaw_job_points (job_id, label, x, y, z, heading, radius, type, meta)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], {
    jobId,
    payload.label or '',
    coords.x,
    coords.y,
    coords.z,
    coords.heading,
    coords.radius,
    payload.type or 'generic',
    metaJson
  })

  if not insertedId then
    TriggerClientEvent('outlawjob:client:validationResult', src, requestId, { ok = false, error = 'Erreur SQL lors de l\'insertion' })
    return
  end

  logAction(src, 'create_point', {
    job_id = jobId,
    point_id = insertedId,
    coords = coords,
    type = payload.type or 'generic'
  })

  TriggerClientEvent('outlawjob:client:validationResult', src, requestId, {
    ok = true,
    pointId = insertedId,
    coords = coords,
    warnings = warnings
  })
end

RegisterNetEvent('outlawjob:requestJobs', function()
  local src = source
  sendPermissions(src)
  sendJobsList(src)
end)

RegisterNetEvent('outlawjob:createJob', function(data)
  local src = source
  if not isPlayerManager(src) then
    notify(src, 'Permissions insuffisantes pour créer un job.')
    return
  end

  local ok, errorMessage = validateJobData(data)
  if not ok then
    notify(src, errorMessage)
    return
  end

  local job_name = trim(data.job_name)
  local label = trim(data.label)
  local tag = data.tag and trim(data.tag) or ''
  local icon = data.icon and trim(data.icon) or ''
  local color = data.color and trim(data.color) or ''
  local society = data.society and trim(data.society) or ''
  local salary = sanitizeNumber(data.default_salary, 0)

  local resultId = MySQL.insert.await([[INSERT INTO outlaw_jobs (job_name, label, tag, icon, color, society_name, default_salary, created_by)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE label = VALUES(label), tag = VALUES(tag), icon = VALUES(icon), color = VALUES(color), society_name = VALUES(society_name), default_salary = VALUES(default_salary)
  ]], {
    job_name,
    label,
    tag,
    icon,
    color,
    society,
    salary,
    getPrimaryIdentifier(src)
  })

  if resultId then
    notify(src, ('Job "%s" enregistré.'):format(label))
    logAction(src, 'create_job', { job_name = job_name, label = label })
  else
    notify(src, 'Erreur SQL lors de la création du job.')
  end

  sendJobsList(src)
end)

RegisterNetEvent('outlawjob:savePoint', function(requestId, payload)
  validateAndPersistPoint(source, requestId, payload)
end)

-- Backwards compatibility
RegisterNetEvent('outlawjob:createPoint', function(payload)
  validateAndPersistPoint(source, 0, payload)
end)

RegisterNetEvent('outlawjob:requestMigrations', function()
  local src = source
  if not isPlayerManager(src) then
    notify(src, 'Permissions insuffisantes pour les migrations.')
    return
  end
  MigrationManager:pushStatus(src)
end)

RegisterNetEvent('outlawjob:applyMigrations', function()
  local src = source
  if not isPlayerManager(src) then
    notify(src, 'Permissions insuffisantes pour appliquer les migrations.')
    return
  end
  local identifier = getPrimaryIdentifier(src)
  local ok, result = MigrationManager:applyPending(identifier)
  if not ok then
    notify(src, ('Erreur migration: %s'):format(result))
  else
    local appliedCount = #result
    if appliedCount > 0 then
      notify(src, ('%d migration(s) appliquées.'):format(appliedCount))
      logAction(src, 'apply_migrations', { applied = result })
    else
      notify(src, 'Aucune migration en attente.')
    end
  end
  MigrationManager:pushStatus(src)
end)

RegisterNetEvent('outlawjob:forceReapplyMigration', function(name)
  local src = source
  if not isPlayerManager(src) then
    notify(src, 'Permissions insuffisantes pour forcer une migration.')
    return
  end
  if type(name) ~= 'string' or name == '' then
    notify(src, 'Nom de migration invalide.')
    return
  end
  local identifier = getPrimaryIdentifier(src)
  local ok, err = MigrationManager:forceReapply(name, identifier)
  if not ok then
    notify(src, ('Erreur reapply: %s'):format(err))
  else
    notify(src, ('Migration %s ré-appliquée.'):format(name))
    logAction(src, 'force_migration', { name = name })
  end
  MigrationManager:pushStatus(src)
end)

AddEventHandler('onResourceStart', function(resource)
  if resource ~= RESOURCE_NAME then return end
  MigrationManager:refreshList()
  ensureMigrationTable()
  if Config.MigrationAutoApply then
    local ok, result = MigrationManager:applyPending('system')
    if not ok then
      print(('[OutlawJobCreator] Migration error: %s'):format(result))
    elseif result and #result > 0 then
      print(('[OutlawJobCreator] Applied migrations: %s'):format(table.concat(result, ', ')))
    else
      print('[OutlawJobCreator] No pending migrations.')
    end
  else
    print('[OutlawJobCreator] Migration auto-apply disabled.')
  end
end)
