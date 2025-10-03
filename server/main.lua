-- server/main.lua (v2)
local oxmysql = exports['oxmysql']

local function checksum(s)
  return tostring(#s) -- simple len-based checksum to keep deps light
end

local MIGRATION_01 = [[
CREATE TABLE IF NOT EXISTS `outlaw_jobs` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `job_name` VARCHAR(64) NOT NULL UNIQUE,
  `label` VARCHAR(128) NOT NULL,
  `tag` VARCHAR(32),
  `icon` VARCHAR(128),
  `color` VARCHAR(16),
  `society_name` VARCHAR(64),
  `default_salary` INT DEFAULT 0,
  `created_by` VARCHAR(64),
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `outlaw_job_runs` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `job_id` INT NOT NULL,
  `run_name` VARCHAR(128),
  `difficulty` VARCHAR(32),
  `client_count` INT DEFAULT 1,
  `total_time_limit` INT DEFAULT 0,
  `reward_base` INT DEFAULT 0,
  `seed_data` JSON,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (job_id) REFERENCES outlaw_jobs(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `outlaw_job_points` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `job_id` INT,
  `label` VARCHAR(128),
  `x` DOUBLE,
  `y` DOUBLE,
  `z` DOUBLE,
  `heading` DOUBLE DEFAULT 0,
  `radius` DOUBLE DEFAULT 2.0,
  `type` VARCHAR(32),
  `meta` JSON,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (job_id) REFERENCES outlaw_jobs(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `outlaw_job_objectives` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `run_id` INT,
  `sequence_index` INT,
  `type` VARCHAR(32),
  `params` JSON,
  `location_ref` INT,
  `time_limit` INT DEFAULT 0,
  `reward` INT DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (run_id) REFERENCES outlaw_job_runs(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `outlaw_job_progress` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `player_identifier` VARCHAR(64),
  `run_instance_id` VARCHAR(64),
  `current_step` INT DEFAULT 0,
  `counters` JSON,
  `started_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `last_update` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `status` VARCHAR(32) DEFAULT 'running'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `outlaw_job_migrations` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `filename` VARCHAR(255),
  `checksum` VARCHAR(64),
  `applied_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]]

local migrations = {
  { name = '01_init_jobs.sql', sql = MIGRATION_01 }
}

local function ensure_migration_table(cb)
  oxmysql:execute([[
    CREATE TABLE IF NOT EXISTS `outlaw_job_migrations` (
      `id` INT AUTO_INCREMENT PRIMARY KEY,
      `filename` VARCHAR(255),
      `checksum` VARCHAR(64),
      `applied_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  ]], {}, function()
    if cb then cb() end
  end)
end

local function apply_migrations()
  if not Config.MigrationAutoApply then return end
  print('[OutlawJobCreator] Checking migrations...')

  ensure_migration_table(function()
    for idx, m in ipairs(migrations) do
      local cs = checksum(m.sql)
      oxmysql:execute('SELECT COUNT(1) as cnt FROM outlaw_job_migrations WHERE checksum = ?', {cs}, function(result)
        local applied = (result and result[1] and tonumber(result[1].cnt) or 0) > 0
        if not applied then
          print(('[OutlawJobCreator] Applying migration: %s'):format(m.name))
          oxmysql:execute(m.sql, {}, function()
            oxmysql:insert('INSERT INTO outlaw_job_migrations (filename, checksum) VALUES (?,?)', {m.name, cs}, function()
              print(('[OutlawJobCreator] Migration applied: %s'):format(m.name))
            end)
          end)
        else
          print(('[OutlawJobCreator] Already applied: %s'):format(m.name))
        end
      end)
    end
  end)
end

AddEventHandler('onResourceStart', function(res)
  if res ~= GetCurrentResourceName() then return end
  if Config.UseOxmysql then
    apply_migrations()
  else
    print('[OutlawJobCreator] WARNING: Config.UseOxmysql=false; no DB bootstrap.')
  end
end)

-- ========== JOBS API ==========

RegisterNetEvent('outlawjob:requestJobs', function()
  local src = source
  oxmysql:execute('SELECT id, job_name, label, tag, color, icon, society_name FROM outlaw_jobs ORDER BY id DESC', {}, function(rows)
    TriggerClientEvent('outlawjob:client:receiveJobs', src, rows or {})
  end)
end)

RegisterNetEvent('outlawjob:createJob', function(data)
  local src = source
  if not data or not data.job_name or not data.label then
    return TriggerClientEvent('outlawjob:client:showNotify', src, 'Champs requis manquants (job_name, label).')
  end
  local job_name  = tostring(data.job_name)
  local label     = tostring(data.label)
  local tag       = tostring(data.tag or '')
  local icon      = tostring(data.icon or '')
  local color     = tostring(data.color or '')
  local society   = tostring(data.society or '')
  local salary    = tonumber(data.default_salary or 0) or 0

  local sql = [[
  INSERT INTO outlaw_jobs (job_name, label, tag, icon, color, society_name, default_salary, created_by)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  ON DUPLICATE KEY UPDATE
    label=VALUES(label), tag=VALUES(tag), icon=VALUES(icon),
    color=VALUES(color), society_name=VALUES(society_name), default_salary=VALUES(default_salary)
  ]]

  local created_by = ('src:%s'):format(src)
  oxmysql:insert(sql, {job_name, label, tag, icon, color, society, salary, created_by}, function(id)
    if id then
      TriggerClientEvent('outlawjob:client:showNotify', src, ('Job %s enregistré.'):format(label))
    else
      TriggerClientEvent('outlawjob:client:showNotify', src, 'Erreur SQL lors de la création du job.')
    end
    -- Refresh for caller
    TriggerClientEvent('outlawjob:client:requestJobsRefresh', src)
  end)
end)

RegisterNetEvent('outlawjob:createPoint', function(data)
  local src = source
  if not data or not tonumber(data.job_id) or not data.x then
    return TriggerClientEvent('outlawjob:client:showNotify', src, 'Données incomplètes pour le point.')
  end
  local meta = json.encode(data.meta or {})
  oxmysql:insert([[
    INSERT INTO outlaw_job_points (job_id, label, x, y, z, heading, radius, type, meta)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  ]], { data.job_id, data.label or '', data.x, data.y, data.z, data.heading or 0.0, data.radius or 2.0, data.type or 'generic', meta }, function(id)
    if id then
      TriggerClientEvent('outlawjob:client:showNotify', src, ('Point créé (#%d).'):format(id))
    else
      TriggerClientEvent('outlawjob:client:showNotify', src, 'Erreur SQL lors de la création du point.')
    end
  end)
end)
