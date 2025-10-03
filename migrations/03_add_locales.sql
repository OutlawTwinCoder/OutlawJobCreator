CREATE TABLE IF NOT EXISTS `outlaw_job_locales` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `key` VARCHAR(128) NOT NULL,
  `lang` VARCHAR(8) NOT NULL,
  `text` TEXT NOT NULL,
  UNIQUE KEY `unq_outlaw_job_locales` (`key`, `lang`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `outlaw_job_locales` (`key`, `lang`, `text`)
SELECT 'ui.get_coords', 'fr', 'Capturer les coordonnées'
WHERE NOT EXISTS (
  SELECT 1 FROM `outlaw_job_locales` WHERE `key` = 'ui.get_coords' AND `lang` = 'fr'
);

INSERT INTO `outlaw_job_locales` (`key`, `lang`, `text`)
SELECT 'ui.get_coords', 'en', 'Capture coordinates'
WHERE NOT EXISTS (
  SELECT 1 FROM `outlaw_job_locales` WHERE `key` = 'ui.get_coords' AND `lang` = 'en'
);

INSERT INTO `outlaw_job_locales` (`key`, `lang`, `text`)
SELECT 'ui.snap_ground', 'fr', 'Ajuster au sol'
WHERE NOT EXISTS (
  SELECT 1 FROM `outlaw_job_locales` WHERE `key` = 'ui.snap_ground' AND `lang` = 'fr'
);

INSERT INTO `outlaw_job_locales` (`key`, `lang`, `text`)
SELECT 'ui.snap_ground', 'en', 'Snap to ground'
WHERE NOT EXISTS (
  SELECT 1 FROM `outlaw_job_locales` WHERE `key` = 'ui.snap_ground' AND `lang` = 'en'
);

INSERT INTO `outlaw_job_locales` (`key`, `lang`, `text`)
SELECT 'notify.validation_failed', 'fr', 'Validation échouée'
WHERE NOT EXISTS (
  SELECT 1 FROM `outlaw_job_locales` WHERE `key` = 'notify.validation_failed' AND `lang` = 'fr'
);

INSERT INTO `outlaw_job_locales` (`key`, `lang`, `text`)
SELECT 'notify.validation_failed', 'en', 'Validation failed'
WHERE NOT EXISTS (
  SELECT 1 FROM `outlaw_job_locales` WHERE `key` = 'notify.validation_failed' AND `lang` = 'en'
);
