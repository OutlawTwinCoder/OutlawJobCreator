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
3) In-game: `/outlawjob` pour ouvrir la tablette.

📌 Notes
- ESX society, permissions manager/admin, éditeur de runs/objectifs, intégration ox_inventory: prêts à être ajoutés.
- Si tu veux la structure "à la jaksam job creator": on peut ajouter des sous-onglets (Job, Runs, Objectifs, Finance, Permissions) + drag&drop Timeline.

Prochaines étapes suggérées
- Ajout onglet **Runs** (création de templates 3/6/10 clients) avec objectifs modulaires.
- Onglet **Finance** (society account, taxes, split joueur/société).
- **GetCoords+Preview** avec marker/blip temporaires côté client pour valider visuellement.
