-- 01_init_jobs.sql (same as server bootstrap; kept for visibility and manual apply if needed)
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
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
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
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
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
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
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
