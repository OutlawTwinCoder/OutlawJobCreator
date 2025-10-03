CREATE TABLE IF NOT EXISTS `outlaw_job_finance` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `job_id` INT NOT NULL,
  `tx_type` VARCHAR(32) NOT NULL,
  `amount` INT NOT NULL DEFAULT 0,
  `source_identifier` VARCHAR(64),
  `target_account` VARCHAR(64),
  `note` VARCHAR(255),
  `timestamp` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT `fk_outlaw_finance_job` FOREIGN KEY (`job_id`) REFERENCES `outlaw_jobs`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `outlaw_job_finance`
  ADD COLUMN IF NOT EXISTS `source_identifier` VARCHAR(64);

ALTER TABLE `outlaw_job_finance`
  ADD COLUMN IF NOT EXISTS `target_account` VARCHAR(64);

ALTER TABLE `outlaw_job_finance`
  ADD COLUMN IF NOT EXISTS `note` VARCHAR(255);
