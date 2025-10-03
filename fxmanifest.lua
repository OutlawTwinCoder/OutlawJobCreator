fx_version 'cerulean'
game 'gta5'

author 'OutlawTwinCoder (generated)'
description 'OutlawJobCreator - v2 (migrations bootstrap, tabbed UI, stable NUI)'
version '1.1.0'

lua54 'yes'

shared_script 'config.lua'

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/main.lua'
}

client_script 'client/main.lua'

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/app.js',
  'html/style.css',
  'migrations/*.sql',
  'migrations/index.json'
}
