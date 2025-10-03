-- 04_add_logs.sql
CREATE TABLE IF NOT EXISTS `outlaw_job_logs` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `actor_identifier` VARCHAR(64) NOT NULL,
  `action` VARCHAR(64) NOT NULL,
  `details` JSON,
  `timestamp` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
