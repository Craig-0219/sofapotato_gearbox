fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'sofapotato_gearbox'
author      'SofaPotato'
description '擬真變速箱系統 (AT / AT-MT / MT)'
version     '0.1.0'

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/styles.css',
    'ui/app.js',
}

shared_scripts {
    'shared/locales/*.lua',
    'shared/constants.lua',
    'shared/config.lua',
}

client_scripts {
    'client/modules/state.lua',
    'client/modules/input.lua',
    'client/modules/clutch.lua',
    'client/modules/physics.lua',
    'client/modules/stall.lua',
    'client/modules/damage.lua',
    'client/modules/gearbox.lua',
    'client/modules/hud.lua',
    'client/modules/menu.lua',
    'client/modules/drift.lua',
    'client/modules/launch.lua',
    'client/modules/sounds.lua',
    'client/modules/upgrade.lua',
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bootstrap.lua',
    'server/modules/persistence.lua',
    'server/modules/upgrade.lua',
    'server/main.lua',
}

dependencies {
    'sp_bridge',
    'oxmysql',
}
