-- Ensure the usage_mode column exists on outlaw_job_points for legacy installs
SET @col := (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'outlaw_job_points'
    AND COLUMN_NAME = 'usage_mode'
);

SET @query := IF(
  @col = 0,
  'ALTER TABLE `outlaw_job_points` ADD COLUMN `usage_mode` VARCHAR(16) NOT NULL DEFAULT ''point'' AFTER `type`',
  'SELECT 1'
);

PREPARE stmt FROM @query;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Backfill any NULL or empty values created by previous patches
UPDATE `outlaw_job_points`
SET `usage_mode` = 'point'
WHERE `usage_mode` IS NULL OR `usage_mode` = '';
