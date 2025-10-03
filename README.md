OutlawJobCreator v2
===================

✅ Fixes
- Migrations: bootstrap `outlaw_job_migrations` AVANT tout check (plus d'erreur "table doesn't exist").
- NUI: UI cachée par défaut (plus de blackscreen). Ouvre via `/outlawjob` seulement.
- NUI Callbacks: `requestJobs` implémenté correctement (pas de fetch loop).
- UI: Tabs (Jobs / Points / Settings) au lieu d'un écran unique.

🧩 Contenu
- fxmanifest.lua, config.lua
- server/main.lua (migrations bootstrap + endpoints)
- client/main.lua (commande /outlawjob, NUI handlers, events)
- html/ (index + app.js + style.css) — Tablet-like UI avec onglets
- migrations/01_init_jobs.sql

🛠 Installation
1) Place `OutlawJobCreator_v2` dans `resources/[outlaw]/`.
2) `ensure OutlawJobCreator_v2` dans `server.cfg` (assure `oxmysql` actif et correctement configuré).
3) Ajoute les permissions ACE pour les managers dans `server.cfg` :
   ```
   add_ace group.admin outlawjob.manage allow
   add_principal identifier.steam:XXXXXXXXXXXXXXX group.admin
   ```
   (remplace l'identifiant par celui de ton compte Steam ou utilise ton groupe ACE personnalisé).
4) In-game: `/outlawjob` pour ouvrir la tablette.

### 🔐 Permissions
- Le bouton **Créer Job** n'apparaît que pour les joueurs ayant l'ACE `outlawjob.manage` (ou un groupe fallback défini dans `Config.Permission.fallbackAces`). Les autres peuvent consulter les listes mais pas modifier.
- Tu peux whitelister des joueurs spécifiques en ajoutant leurs identifiants dans `Config.Permission.allowedIdentifiers`.
- Pour un serveur de test, mets `Config.Permission.requiredAce = false` afin d'autoriser temporairement tout le monde.

📦 Intégration base de données
- Les jobs listés proviennent directement de la table ESX `jobs` (configurable dans `config.lua`). Le créateur synchronise automatiquement les entrées avec la table `outlaw_jobs` pour stocker les métadonnées (icône, couleur, compte société, salaire par défaut).
- Les connecteurs affichés (armurerie, data, heures employés, garages, shops, etc.) sont lus dynamiquement si les tables `jobs_*` correspondantes existent (`jobs_armorie`, `jobs_data`, `jobs_employee_hours`, `jobs_garages`, `jobs_shops`). Tu peux ajuster ou ajouter des connecteurs dans `Config.JobIntegrations`.
- Les points se lient aux `job_id` Outlaw générés lors de la synchronisation. Un bouton **Activer Outlaw** dans la liste crée l'entrée si nécessaire.
- Les migrations restent idempotentes et enregistrent leur état dans `outlaw_job_migrations`. Utilise l'onglet **Settings → Console Manager** pour appliquer ou forcer une migration.
- Les valeurs par défaut de l'UI (icônes suggérées, couleurs, préfixe de société, types de points) se pilotent depuis `config.lua` via `Config.JobForm` et `Config.PointOptions`.
- Les légendes dans l'onglet Points expliquent la différence entre « Point unique », « Spawn » ou « Multi-Spawn », et les modes « Point » / « Zone » pour clarifier l'usage.

📌 Notes
- ESX society, permissions manager/admin, éditeur de runs/objectifs, intégration ox_inventory: prêts à être ajoutés.
- Si tu veux la structure "à la jaksam job creator": on peut ajouter des sous-onglets (Job, Runs, Objectifs, Finance, Permissions) + drag&drop Timeline.

Prochaines étapes suggérées
- Ajout onglet **Runs** (création de templates 3/6/10 clients) avec objectifs modulaires.
- Onglet **Finance** (society account, taxes, split joueur/société).
- **GetCoords+Preview** avec marker/blip temporaires côté client pour valider visuellement.
