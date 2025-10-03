-- 05_seed_locales.sql
INSERT INTO `outlaw_job_locales` (`job_id`, `key`, `lang`, `text`)
SELECT 0, seed.key_name, seed.lang, seed.label
FROM (
  SELECT 'ui.button.get_coords' AS key_name, 'fr' AS lang, 'Récupérer coords' AS label UNION ALL
  SELECT 'ui.button.get_coords' AS key_name, 'en' AS lang, 'Get coords' AS label UNION ALL
  SELECT 'ui.toast.point_created' AS key_name, 'fr' AS lang, 'Point enregistré' AS label UNION ALL
  SELECT 'ui.toast.point_created' AS key_name, 'en' AS lang, 'Point saved' AS label
) AS seed
ON DUPLICATE KEY UPDATE `text` = VALUES(`text`);
