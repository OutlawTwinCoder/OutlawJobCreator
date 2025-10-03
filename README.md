# Outlaw Job Creator

Gestionnaire de jobs simple inspiré des outils type *decrypted* : création rapide de jobs ESX, points de collecte/livraison et capture de coordonnées depuis le jeu.

## Fonctionnalités
- 📋 Liste des jobs Outlaw + synchronisation basique avec la table ESX `jobs`.
- 🖊️ Formulaire clair pour créer ou modifier un job (nom, label, tag, couleur, icône, compte society, salaire).
- 📍 Gestion simplifiée des points (collecte, livraison, craft, garage, spawn) avec bouton **Get coords** et formulaire unique.
- 🗃️ Historique léger via `outlaw_job_logs` pour savoir qui a modifié quoi.
- ⚙️ Migrations SQL idempotentes appliquées automatiquement au démarrage.

## Installation
1. Copiez le dossier dans `resources/[outlaw]/OutlawJobCreator`.
2. Assurez-vous d'avoir `oxmysql` configuré puis ajoutez dans votre `server.cfg` :
   ```cfg
   ensure OutlawJobCreator
   ```
3. (Optionnel) Définissez un ACE pour restreindre l'accès :
   ```cfg
   add_ace group.admin outlaw.creator allow
   ```
   Par défaut `Config.Permission.requiredAce = false`, tout staff peut donc accéder directement. Passez-le à une valeur (ex `outlaw.creator`) si vous souhaitez forcer une permission dédiée.
4. En jeu : `/outlawjob` pour ouvrir l'interface.

## Tables utilisées
Les migrations créent automatiquement :
- `outlaw_jobs` : métadonnées des jobs Outlaw (label, icône, couleur, société, salaire).
- `outlaw_job_points` : points associés à un job (coordonnées, type, usage, radius, meta).
- `outlaw_job_logs` : journal simple des modifications (création/suppression job ou point).
- `outlaw_job_finance` et `outlaw_job_locales` sont prêts pour des évolutions futures.

La table ESX `jobs` est détectée automatiquement. Lors d'une création ou mise à jour, une entrée y est ajoutée/ajustée si elle existe (label + whitelisted).

## Utilisation rapide
1. **Créer un job** : bouton *Nouveau job*, remplissez nom/label puis *Enregistrer*.
2. **Ajouter des points** : sélectionnez le job, cliquez sur *Nouveau point*, utilisez *Get coords* pour récupérer votre position actuelle puis renseignez type/usage (point ou zone) et radius si nécessaire.
3. **Modifier / supprimer** : chaque point peut être édité ou supprimé depuis la liste. Les actions sont loguées dans `outlaw_job_logs`.

## Configuration (config.lua)
- `Config.Permission` : ACE principal (`requiredAce`), fallback groupes (`fallbackAces`) et identifiants autorisés.
- `Config.JobForm` : icônes/couleurs proposées par l'UI et valeurs par défaut (icône, couleur, préfixe society, salaire).
- `Config.PointOptions` : liste des types et usages disponibles pour les points.
- `Config.OpenCommand` / `Config.KeyMapping` : commande ou touche pour ouvrir l'interface.

## Conseils
- Ajoutez manuellement les colonnes nécessaires dans vos tables annexes (`jobs_armorie`, `jobs_data`, etc.) si vous souhaitez lier ces systèmes. Ici on expose surtout la gestion des points et des jobs.
- Pensez à définir une permission ACE dédiée en production (`requiredAce = 'outlaw.creator'`) pour limiter la création aux managers.
- Avant de pousser en prod, vérifiez les migrations sur un dump local : `outlaw_job_migrations` garde une trace des scripts appliqués.
