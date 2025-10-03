-- server/main.lua
local resourceName = GetCurrentResourceName()

local tableCache = {}

local function getPrimaryIdentifier(src)
  if src <= 0 then
    return 'console'
  end

  if GetNumPlayerIdentifiers and GetPlayerIdentifier then
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
      local identifier = GetPlayerIdentifier(src, i)
      if identifier and identifier ~= '' then
        if identifier:find('license:', 1, true) then
          return identifier
        end
        if identifier:find('steam:', 1, true) then
          return identifier
        end
      end
    end
  end

  return ('src:%d'):format(src)
end

local function toBoolean(value)
  if value == nil then
    return false
  end

  if type(value) == 'boolean' then
    return value
  end

  if type(value) == 'number' then
    return value ~= 0
  end

  if type(value) == 'string' then
    local lower = value:lower()
    return lower == '1' or lower == 'true' or lower == 'yes'
  end

  return false
end

local function log(msg)
  print(('^2[OutlawJobCreator]^7 %s'):format(msg))
end

local function warn(msg)
  print(('^3[OutlawJobCreator]^7 %s'):format(msg))
end

local function errorLog(msg)
  print(('^1[OutlawJobCreator]^7 %s'):format(msg))
end

local function checksum(str)
  if not str or str == '' then
    return '0'
  end
  return ('%08x'):format(GetHashKey(str))
end

local function tableExists(name)
  if not Config.UseOxmysql then
    return false
  end

  if tableCache[name] ~= nil then
    return tableCache[name]
  end

  local ok, result = pcall(function()
    return MySQL.query.await('SHOW TABLES LIKE ?', { name })
  end)

  local exists = ok and result and #result > 0 or false
  tableCache[name] = exists
  return exists
end

local function ensureMigrationTable()
  if not Config.UseOxmysql then
    return
  end

  MySQL.query.await([[CREATE TABLE IF NOT EXISTS `outlaw_job_migrations` (
      `id` INT AUTO_INCREMENT PRIMARY KEY,
      `filename` VARCHAR(255) NOT NULL,
      `checksum` VARCHAR(64) NOT NULL,
      `applied_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      `applied_by` VARCHAR(64) DEFAULT NULL,
      UNIQUE KEY `unq_outlaw_job_migrations_filename` (`filename`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])
end

local function trim(str)
  return (str or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function splitStatements(sql)
  local statements = {}
  if not sql then
    return statements
  end

  local buffer = ''
  for line in sql:gmatch('[^\n]*\n?') do
    buffer = buffer .. line
    if line:find(';') then
      local parts = buffer:gmatch('([^;]+);')
      for chunk in parts do
        local statement = trim(chunk)
        statement = statement:gsub('%/%*.-%*%/', '')
        statement = statement:gsub('\r', '')
        if statement ~= '' then
          statements[#statements + 1] = statement
        end
      end
      buffer = ''
    end
  end

  buffer = trim(buffer)
  if buffer ~= '' then
    statements[#statements + 1] = buffer
  end

  return statements
end

local function loadMigration(name)
  local sql = LoadResourceFile(resourceName, ('migrations/%s'):format(name))
  if not sql then
    errorLog(('Migration introuvable: %s'):format(name))
  end
  return sql
end

local function migrationApplied(name, digest)
  local row = MySQL.single.await(
    'SELECT id FROM `outlaw_job_migrations` WHERE `filename` = ? AND `checksum` = ? LIMIT 1',
    { name, digest }
  )
  return row ~= nil
end

local function markMigrationApplied(name, digest, src)
  local appliedBy = src and (GetPlayerName(src) or ('src:%d'):format(src)) or 'server'
  MySQL.insert.await(
    'INSERT INTO `outlaw_job_migrations` (`filename`, `checksum`, `applied_by`) VALUES (?, ?, ?)',
    { name, digest, appliedBy }
  )
end

local function applyMigration(name, src)
  local sql = loadMigration(name)
  if not sql or sql == '' then
    return
  end

  local digest = checksum(sql)
  if migrationApplied(name, digest) then
    return
  end

  log(('Application migration: %s'):format(name))
  local statements = splitStatements(sql)
  for _, statement in ipairs(statements) do
    local ok, err = pcall(function()
      MySQL.query.await(statement)
    end)
    if not ok then
      errorLog(('Erreur migration %s: %s'):format(name, err))
      return
    end
  end

  markMigrationApplied(name, digest, src)
  log(('Migration appliquée: %s'):format(name))
end

local function applyPendingMigrations(src)
  if Config.MigrationAutoApply == false then
    return
  end

  if not Config.UseOxmysql then
    warn('Config.UseOxmysql=false - migrations ignorées')
    return
  end

  ensureMigrationTable()

  local manifestPath = Config.Migration and Config.Migration.manifestFile or nil
  local orderedMigrations = {}
  if manifestPath then
    local payload = LoadResourceFile(resourceName, manifestPath)
    if payload then
      local ok, data = pcall(json.decode, payload)
      if ok and data then
        local list = data.migrations or data
        if type(list) == 'table' then
          for _, entry in ipairs(list) do
            if type(entry) == 'string' then
              orderedMigrations[#orderedMigrations + 1] = entry
            end
          end
        end
      end
    end
  end

  table.sort(orderedMigrations)

  for _, name in ipairs(orderedMigrations) do
    applyMigration(name, src)
  end
end

local function canManage(src)
  if Config.CanManageCreator then
    local ok, allowed = pcall(Config.CanManageCreator, src)
    if ok and allowed then
      return true
    end
    return false
  end
  return false
end

local function ensurePermission(src)
  if not canManage(src) then
    TriggerClientEvent('outlawjob:client:notify', src, {
      type = 'error',
      message = 'Permission refusée pour gérer le Job Creator.'
    })
    return false
  end
  return true
end

local function fetchJobs()
  if not Config.UseOxmysql then
    return {}
  end

  local rows = MySQL.query.await([[SELECT id, job_name, label, tag, color, icon, society_name, default_salary, whitelisted, created_at
    FROM `outlaw_jobs`
    ORDER BY id DESC]])
  return rows or {}
end

local function fetchEsxJobs()
  if not tableExists(Config.JobIntegrations.baseTable or 'jobs') then
    return {}
  end

  local query = ('SELECT `%s` AS name, `%s` AS label FROM `%s` ORDER BY `%s` ASC'):format(
    Config.JobIntegrations.nameField,
    Config.JobIntegrations.labelField,
    Config.JobIntegrations.baseTable,
    Config.JobIntegrations.labelField
  )

  local rows = MySQL.query.await(query)
  return rows or {}
end

local function fetchPoints(jobId)
  if not Config.UseOxmysql then
    return {}
  end

  local rows = MySQL.query.await([[SELECT id, job_id, label, type, usage_mode, x, y, z, heading, radius, meta, created_at
    FROM `outlaw_job_points`
    WHERE job_id = ?
    ORDER BY id ASC]], { jobId })

  for _, row in ipairs(rows or {}) do
    if row.meta and row.meta ~= '' then
      local ok, meta = pcall(json.decode, row.meta)
      if ok and meta then
        row.meta = meta
      else
        row.meta = {}
      end
    else
      row.meta = {}
    end
  end

  return rows or {}
end

local function logAction(src, action, details)
  if not Config.UseOxmysql then
    return
  end

  local actor = getPrimaryIdentifier(src)
  MySQL.insert.await('INSERT INTO `outlaw_job_logs` (`actor_identifier`, `action`, `details`) VALUES (?, ?, ?)', {
    actor,
    action,
    json.encode(details or {})
  })
end

local function ensureEsxSync(job, previousName)
  if not job or not job.job_name or job.job_name == '' then
    return
  end

  if not tableExists(Config.JobIntegrations.baseTable or 'jobs') then
    return
  end

  local tableName = Config.JobIntegrations.baseTable
  local nameField = Config.JobIntegrations.nameField
  local labelField = Config.JobIntegrations.labelField
  local whitelistField = Config.JobIntegrations.whitelistedField

  local existing = MySQL.single.await(
    ('SELECT `%s` AS name FROM `%s` WHERE `%s` = ? LIMIT 1'):format(nameField, tableName, nameField),
    { job.job_name }
  )

  if not existing and previousName and previousName ~= '' then
    existing = MySQL.single.await(
      ('SELECT `%s` AS name FROM `%s` WHERE `%s` = ? LIMIT 1'):format(nameField, tableName, nameField),
      { previousName }
    )
    if existing then
      local updateQuery
      local params
      if whitelistField and whitelistField ~= '' then
        updateQuery = ('UPDATE `%s` SET `%s` = ?, `%s` = ?, `%s` = ? WHERE `%s` = ?'):format(
          tableName,
          nameField,
          labelField,
          whitelistField,
          nameField
        )
        params = { job.job_name, job.label, job.whitelisted and 1 or 0, previousName }
      else
        updateQuery = ('UPDATE `%s` SET `%s` = ?, `%s` = ? WHERE `%s` = ?'):format(
          tableName,
          nameField,
          labelField,
          nameField
        )
        params = { job.job_name, job.label, previousName }
      end
      MySQL.update.await(updateQuery, params)
      return
    end
  end

  if existing then
    local query
    local params
    if whitelistField and whitelistField ~= '' then
      query = ('UPDATE `%s` SET `%s` = ?, `%s` = ? WHERE `%s` = ?'):format(
        tableName,
        labelField,
        whitelistField,
        nameField
      )
      params = { job.label, job.whitelisted and 1 or 0, job.job_name }
    else
      query = ('UPDATE `%s` SET `%s` = ? WHERE `%s` = ?'):format(
        tableName,
        labelField,
        nameField
      )
      params = { job.label, job.job_name }
    end
    MySQL.update.await(query, params)
  else
    local fields = { nameField, labelField }
    local values = { job.job_name, job.label }
    if whitelistField and whitelistField ~= '' then
      fields[#fields + 1] = whitelistField
      values[#values + 1] = job.whitelisted and 1 or 0
    end

    local placeholders = {}
    for _ = 1, #fields do
      placeholders[#placeholders + 1] = '?'
    end

    MySQL.insert.await(
      ('INSERT INTO `%s` (`%s`) VALUES (%s)'):format(
        tableName,
        table.concat(fields, '`, `'),
        table.concat(placeholders, ', ')
      ),
      values
    )
  end
end

local function sendState(src)
  local payload = {
    canManage = canManage(src),
    jobs = fetchJobs(),
    esxJobs = fetchEsxJobs(),
    options = {
      icons = Config.JobForm.iconOptions,
      colors = Config.JobForm.colorOptions,
      defaults = {
        icon = Config.JobForm.defaultIcon,
        color = Config.JobForm.defaultColor,
        tag = Config.JobForm.defaultTag,
        salary = Config.JobForm.defaultSalary,
        societyPrefix = Config.JobForm.defaultSocietyPrefix
      },
      pointTypes = Config.PointOptions.types,
      pointUsage = Config.PointOptions.usage
    }
  }
  TriggerClientEvent('outlawjob:client:setState', src, payload)
end

local function sendPoints(src, jobId)
  local rows = fetchPoints(jobId)
  TriggerClientEvent('outlawjob:client:setPoints', src, {
    jobId = jobId,
    points = rows
  })
end

RegisterNetEvent('outlawjob:server:requestState', function()
  local src = source
  if not ensurePermission(src) then
    return
  end
  sendState(src)
end)

RegisterNetEvent('outlawjob:server:requestPoints', function(jobId)
  local src = source
  if not ensurePermission(src) then
    return
  end

  if not jobId then
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'error', message = 'Job invalide.' })
    return
  end

  sendPoints(src, jobId)
end)

RegisterNetEvent('outlawjob:server:createJob', function(data)
  local src = source
  if not ensurePermission(src) then
    return
  end

  data = data or {}
  local jobName = trim(data.job_name)
  local label = trim(data.label)
  if jobName == '' or label == '' then
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'error', message = 'Nom et label requis.' })
    return
  end

  local payload = {
    job_name = jobName,
    label = label,
    tag = trim(data.tag) ~= '' and trim(data.tag) or nil,
    color = data.color or Config.JobForm.defaultColor,
    icon = data.icon or Config.JobForm.defaultIcon,
    society_name = data.society_name or (Config.JobForm.defaultSocietyPrefix .. jobName),
    default_salary = tonumber(data.default_salary) or Config.JobForm.defaultSalary or 0,
    whitelisted = toBoolean(data.whitelisted)
  }

  local insertId = MySQL.insert.await([[INSERT INTO `outlaw_jobs`
      (job_name, label, tag, color, icon, society_name, default_salary, whitelisted, created_by)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON DUPLICATE KEY UPDATE
        label = VALUES(label),
        tag = VALUES(tag),
        color = VALUES(color),
        icon = VALUES(icon),
        society_name = VALUES(society_name),
        default_salary = VALUES(default_salary),
        whitelisted = VALUES(whitelisted)
    ]], {
    payload.job_name,
    payload.label,
    payload.tag,
    payload.color,
    payload.icon,
    payload.society_name,
    payload.default_salary,
    payload.whitelisted and 1 or 0,
    getPrimaryIdentifier(src)
  })

  if insertId ~= nil then
    ensureEsxSync(payload)
    logAction(src, 'create_job', payload)
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'success', message = ('Job %s enregistré.'):format(payload.label) })
    sendState(src)
  else
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'error', message = 'Erreur SQL lors de la création.' })
  end
end)

RegisterNetEvent('outlawjob:server:updateJob', function(data)
  local src = source
  if not ensurePermission(src) then
    return
  end

  data = data or {}
  if not data.id then
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'error', message = 'Identifiant de job manquant.' })
    return
  end

  local jobId = tonumber(data.id)
  local jobName = trim(data.job_name)
  local label = trim(data.label)

  if jobName == '' or label == '' then
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'error', message = 'Nom et label requis.' })
    return
  end

  local existingRow = MySQL.single.await('SELECT job_name FROM `outlaw_jobs` WHERE id = ?', { jobId })
  if not existingRow then
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'error', message = 'Job introuvable.' })
    return
  end

  local payload = {
    job_name = jobName,
    label = label,
    tag = trim(data.tag) ~= '' and trim(data.tag) or nil,
    color = data.color or Config.JobForm.defaultColor,
    icon = data.icon or Config.JobForm.defaultIcon,
    society_name = data.society_name or (Config.JobForm.defaultSocietyPrefix .. jobName),
    default_salary = tonumber(data.default_salary) or Config.JobForm.defaultSalary or 0,
    whitelisted = toBoolean(data.whitelisted)
  }

  local changed = MySQL.update.await([[UPDATE `outlaw_jobs`
      SET job_name = ?,
          label = ?,
          tag = ?,
          color = ?,
          icon = ?,
          society_name = ?,
          default_salary = ?,
          whitelisted = ?
      WHERE id = ?]], {
    payload.job_name,
    payload.label,
    payload.tag,
    payload.color,
    payload.icon,
    payload.society_name,
    payload.default_salary,
    payload.whitelisted and 1 or 0,
    jobId
  })

  if changed and changed > 0 then
    ensureEsxSync(payload, existingRow.job_name)
    logAction(src, 'update_job', { id = jobId, job = payload })
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'success', message = 'Job mis à jour.' })
    sendState(src)
  else
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'error', message = 'Aucune modification appliquée.' })
  end
end)

RegisterNetEvent('outlawjob:server:deleteJob', function(data)
  local src = source
  if not ensurePermission(src) then
    return
  end

  local jobId = tonumber(data and data.id)
  if not jobId then
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'error', message = 'Identifiant job invalide.' })
    return
  end

  local affected = MySQL.update.await('DELETE FROM `outlaw_jobs` WHERE id = ?', { jobId })
  if affected and affected > 0 then
    logAction(src, 'delete_job', { id = jobId })
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'success', message = 'Job supprimé.' })
    sendState(src)
  else
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'error', message = 'Job introuvable.' })
  end
end)

local function validatePoint(data)
  if not data.job_id then
    return false, 'Job invalide.'
  end

  data.job_id = tonumber(data.job_id)
  if not data.job_id then
    return false, 'Job invalide.'
  end

  if not data.type or data.type == '' then
    data.type = 'collect'
  end

  data.label = trim(data.label)
  if data.label == '' then
    data.label = data.type
  end

  data.x = tonumber(data.x)
  data.y = tonumber(data.y)
  data.z = tonumber(data.z)
  data.heading = tonumber(data.heading) or 0.0
  data.radius = tonumber(data.radius) or 0.0
  data.usage_mode = data.usage_mode or 'point'

  if not data.x or not data.y or not data.z then
    return false, 'Coordonnées invalides.'
  end

  local validation = Config.PointValidation or {}
  local minRadius = validation.minRadius or 0.0
  local maxRadius = validation.maxRadius or 50.0

  if data.radius < minRadius then
    data.radius = minRadius
  end

  if data.radius > maxRadius then
    data.radius = maxRadius
  end

  return true
end

RegisterNetEvent('outlawjob:server:createPoint', function(data)
  local src = source
  if not ensurePermission(src) then
    return
  end

  data = data or {}
  local ok, msg = validatePoint(data)
  if not ok then
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'error', message = msg })
    return
  end

  local meta = data.meta or {}
  meta.item = data.item or meta.item
  meta.reward = data.reward or meta.reward

  local insertId = MySQL.insert.await([[INSERT INTO `outlaw_job_points`
      (job_id, label, type, usage_mode, x, y, z, heading, radius, meta)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
    data.job_id,
    data.label,
    data.type,
    data.usage_mode,
    data.x,
    data.y,
    data.z,
    data.heading,
    data.radius,
    json.encode(meta)
  })

  if insertId ~= nil then
    logAction(src, 'create_point', { id = insertId, job_id = data.job_id })
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'success', message = 'Point ajouté.' })
    sendPoints(src, data.job_id)
  else
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'error', message = 'Erreur SQL lors de l\'ajout.' })
  end
end)

RegisterNetEvent('outlawjob:server:updatePoint', function(data)
  local src = source
  if not ensurePermission(src) then
    return
  end

  data = data or {}
  data.id = tonumber(data.id)
  if not data.id then
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'error', message = 'Point invalide.' })
    return
  end

  local ok, msg = validatePoint(data)
  if not ok then
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'error', message = msg })
    return
  end

  local meta = data.meta or {}
  meta.item = data.item or meta.item
  meta.reward = data.reward or meta.reward

  local changed = MySQL.update.await([[UPDATE `outlaw_job_points`
      SET label = ?,
          type = ?,
          usage_mode = ?,
          x = ?,
          y = ?,
          z = ?,
          heading = ?,
          radius = ?,
          meta = ?
      WHERE id = ?]], {
    data.label,
    data.type,
    data.usage_mode,
    data.x,
    data.y,
    data.z,
    data.heading,
    data.radius,
    json.encode(meta),
    data.id
  })

  if changed and changed > 0 then
    logAction(src, 'update_point', { id = data.id })
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'success', message = 'Point mis à jour.' })
    sendPoints(src, data.job_id)
  else
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'error', message = 'Aucun changement appliqué.' })
  end
end)

RegisterNetEvent('outlawjob:server:deletePoint', function(data)
  local src = source
  if not ensurePermission(src) then
    return
  end

  data = data or {}
  local id = tonumber(data.id)
  if not id then
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'error', message = 'Point invalide.' })
    return
  end

  local jobId = tonumber(data.job_id) or 0
  local affected = MySQL.update.await('DELETE FROM `outlaw_job_points` WHERE id = ?', { id })
  if affected and affected > 0 then
    logAction(src, 'delete_point', { id = id })
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'success', message = 'Point supprimé.' })
    if jobId > 0 then
      sendPoints(src, jobId)
    end
  else
    TriggerClientEvent('outlawjob:client:notify', src, { type = 'error', message = 'Point introuvable.' })
  end
end)

AddEventHandler('onResourceStart', function(res)
  if res ~= resourceName then
    return
  end

  if Config.UseOxmysql then
    applyPendingMigrations()
  else
    warn('OxMySQL désactivé, aucune migration appliquée.')
  end
end)
