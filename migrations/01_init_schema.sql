CREATE TABLE IF NOT EXISTS `outlaw_job_migrations` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `filename` VARCHAR(255) NOT NULL,
  `checksum` VARCHAR(64) NOT NULL,
  `applied_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `applied_by` VARCHAR(64) DEFAULT NULL,
  UNIQUE KEY `unq_outlaw_job_migrations_filename` (`filename`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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
  `seed_data` LONGTEXT,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT `fk_outlaw_runs_job` FOREIGN KEY (`job_id`) REFERENCES `outlaw_jobs`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `outlaw_job_points` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `job_id` INT NOT NULL,
  `label` VARCHAR(128),
  `x` DOUBLE,
  `y` DOUBLE,
  `z` DOUBLE,
  `heading` DOUBLE DEFAULT 0,
  `radius` DOUBLE DEFAULT 2.0,
  `type` VARCHAR(32),
  `meta` LONGTEXT,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT `fk_outlaw_points_job` FOREIGN KEY (`job_id`) REFERENCES `outlaw_jobs`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `outlaw_job_objectives` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `run_id` INT,
  `sequence_index` INT,
  `type` VARCHAR(32),
  `params` LONGTEXT,
  `location_ref` INT,
  `time_limit` INT DEFAULT 0,
  `reward` INT DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT `fk_outlaw_objectives_run` FOREIGN KEY (`run_id`) REFERENCES `outlaw_job_runs`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `outlaw_job_progress` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `player_identifier` VARCHAR(64),
  `run_instance_id` VARCHAR(64),
  `current_step` INT DEFAULT 0,
  `counters` LONGTEXT,
  `started_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `last_update` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `status` VARCHAR(32) DEFAULT 'running'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `outlaw_job_logs` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `actor_identifier` VARCHAR(64),
  `action` VARCHAR(64) NOT NULL,
  `details` LONGTEXT,
  `timestamp` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `outlaw_job_migrations`
  ADD COLUMN IF NOT EXISTS `applied_by` VARCHAR(64) DEFAULT NULL;

ALTER TABLE `outlaw_job_points`
  ADD COLUMN IF NOT EXISTS `meta` LONGTEXT;

ALTER TABLE `outlaw_job_points`
  MODIFY COLUMN `meta` LONGTEXT;

ALTER TABLE `outlaw_job_runs`
  ADD COLUMN IF NOT EXISTS `seed_data` LONGTEXT;

ALTER TABLE `outlaw_job_runs`
  MODIFY COLUMN `seed_data` LONGTEXT;

ALTER TABLE `outlaw_job_objectives`
  ADD COLUMN IF NOT EXISTS `params` LONGTEXT;

ALTER TABLE `outlaw_job_objectives`
  MODIFY COLUMN `params` LONGTEXT;

ALTER TABLE `outlaw_job_progress`
  ADD COLUMN IF NOT EXISTS `counters` LONGTEXT;

ALTER TABLE `outlaw_job_progress`
  MODIFY COLUMN `counters` LONGTEXT;
