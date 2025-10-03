-- 03_add_locales.sql
CREATE TABLE IF NOT EXISTS `outlaw_job_locales` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `job_id` INT NOT NULL DEFAULT 0,
  `key` VARCHAR(128) NOT NULL,
  `lang` VARCHAR(5) NOT NULL,
  `text` TEXT,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uniq_locale` (`job_id`, `key`, `lang`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
