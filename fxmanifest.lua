fx_version 'cerulean'
game 'gta5'

author 'OutlawTwinCoder'
description 'Outlaw Job Creator - simple job & point manager'
version '1.3.0'

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
  'migrations/_manifest.json',
  'migrations/*.sql'
}
