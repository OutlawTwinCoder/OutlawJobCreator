-- 01_init_core.sql
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
  `run_name` VARCHAR(128) NOT NULL,
  `difficulty` VARCHAR(32),
  `client_count` INT DEFAULT 1,
  `total_time_limit` INT DEFAULT 0,
  `reward_base` INT DEFAULT 0,
  `seed_data` JSON,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT `fk_runs_job` FOREIGN KEY (`job_id`) REFERENCES `outlaw_jobs` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `outlaw_job_points` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `job_id` INT NOT NULL,
  `label` VARCHAR(128),
  `x` DOUBLE NOT NULL,
  `y` DOUBLE NOT NULL,
  `z` DOUBLE NOT NULL,
  `heading` DOUBLE DEFAULT 0,
  `radius` DOUBLE DEFAULT 2.0,
  `type` VARCHAR(32) DEFAULT 'generic',
  `meta` JSON,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT `fk_points_job` FOREIGN KEY (`job_id`) REFERENCES `outlaw_jobs` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `outlaw_job_objectives` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `run_id` INT NOT NULL,
  `sequence_index` INT NOT NULL DEFAULT 0,
  `type` VARCHAR(32) NOT NULL,
  `params` JSON,
  `location_ref` INT,
  `time_limit` INT DEFAULT 0,
  `reward` INT DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT `fk_objectives_run` FOREIGN KEY (`run_id`) REFERENCES `outlaw_job_runs` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_objectives_point` FOREIGN KEY (`location_ref`) REFERENCES `outlaw_job_points` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `outlaw_job_progress` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `player_identifier` VARCHAR(64) NOT NULL,
  `run_instance_id` VARCHAR(64) NOT NULL,
  `current_step` INT DEFAULT 0,
  `counters` JSON,
  `started_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `last_update` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `status` VARCHAR(32) DEFAULT 'running'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
