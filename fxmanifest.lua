-- fks-stables · Copyright (C) 2026 FKS · Licensed under the GNU GPL v3 or later (see LICENSE)
fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'fks-stables'
author 'FKS'
description 'Stables, horses, wagons, wild horse taming, training and breeding for RedM (VORP / RSG)'
version '1.3.0'
license 'GPL-3.0-or-later'
fks_core_version '2.1.0' -- minimum fks-core version (VORP / RSG bridge, shared UI, notifications, progress bar)

shared_scripts {
    '@ox_lib/init.lua',
    '@fks-core/import.lua',
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
    'client/menu.lua',        -- stable menu screens (drawn by fks-core)
    'client/horse.lua',
    'client/wagon.lua',
    'client/care.lua',
    'client/prompts.lua',
    'client/wild.lua',
    'client/training.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/version.lua',
    'server/db.lua',
    'server/main.lua',
    'server/trainer.lua',
}

-- the interface is drawn by fks-core (shared FKS UI); only the menu icons live here
files {
    'img/*.png',
}

-- + fks-core 2.1.0+ (required: VORP / RSG bridge, shared UI, notifications, progress bar) - https://github.com/Fonkas/fks-core
--   not listed below so that, when it is missing, the server console shows the download link (server/version.lua)
-- + a framework (rsg-core or vorp_core) and an inventory (ox_inventory, rsg-inventory or vorp_inventory)
dependencies {
    'ox_lib',
    'oxmysql',
}
