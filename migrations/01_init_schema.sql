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
  `whitelisted` TINYINT(1) NOT NULL DEFAULT 0,
  `created_by` VARCHAR(64),
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `outlaw_job_points` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `job_id` INT NOT NULL,
  `label` VARCHAR(128) NOT NULL,
  `type` VARCHAR(32) NOT NULL DEFAULT 'collect',
  `usage_mode` VARCHAR(16) NOT NULL DEFAULT 'point',
  `x` DOUBLE NOT NULL,
  `y` DOUBLE NOT NULL,
  `z` DOUBLE NOT NULL,
  `heading` DOUBLE NOT NULL DEFAULT 0,
  `radius` DOUBLE NOT NULL DEFAULT 0,
  `meta` LONGTEXT,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT `fk_outlaw_points_job` FOREIGN KEY (`job_id`) REFERENCES `outlaw_jobs`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `outlaw_job_logs` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `actor_identifier` VARCHAR(64) NOT NULL,
  `action` VARCHAR(64) NOT NULL,
  `details` LONGTEXT,
  `timestamp` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
