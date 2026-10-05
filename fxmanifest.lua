-- fks-stables · Copyright (C) 2026 FKS · Licensed under the GNU GPL v3 or later (see LICENSE)
fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'fks-stables'
author 'FKS'
description 'Stables, horses, wagons, wild horse taming, training and breeding for RedM (VORP / RSG)'
version '1.0.0'
license 'GPL-3.0-or-later'

shared_scripts {
    '@ox_lib/init.lua',
    'config/main.lua',
    'config/horses.lua',
    'config/wagons.lua',
    'config/components.lua',
    'config/stables.lua',
    'config/animals.lua',
    'config/trainer.lua',
    'locales/*.lua',
    'shared/locale.lua',
    'shared/utils.lua',
}

client_scripts {
    'client/appearance.lua',
    'client/stable.lua',
    'client/horse.lua',
    'client/wagon.lua',
    'client/care.lua',
    'client/prompts.lua',
    'client/wild.lua',
    'client/training.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bridge.lua',
    'server/db.lua',
    'server/main.lua',
    'server/trainer.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/panel.png',
    'html/horseicon.png',
    'html/horseicon2.png',
    'html/wagonicon.png',
    'html/wagonicon2.png',
    'html/fonts/*.woff2',
}

-- + a framework (rsg-core or vorp_core) and an inventory (ox_inventory, rsg-inventory or vorp_inventory)
dependencies {
    'ox_lib',
    'oxmysql',
}
