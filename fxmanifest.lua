fx_version 'cerulean'
game 'gta5'

author 'Anxious'
description 'GPU rig Bitcoin mining -- placeable rigs, power/heat management, market-priced sell, theft risk'
version '1.0.0'

lua54 'yes'

ui_page 'web/build/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    '@qbx_core/modules/playerdata.lua',
    'client/main.lua',
    'client/minigame.lua',
    'client/target.lua',
    'client/placement.lua',
    'client/rig_props.lua',
    'client/theft.lua',
    'client/fire.lua',
    'client/dashboard.lua',
    'client/dispatch.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    -- Server-only config (Discord webhook, dispatch wiring, anti-exploit
    -- thresholds) -- kept out of the shared config.lua so clients can't read
    -- it. Must load before any server file that captures Config.Security/
    -- Dispatch/Logs at load time (logs/security/dispatch below).
    'server/config_server.lua',
    'server/init.lua',
    'server/migrations.lua',
    'server/rig_state.lua',
    -- Loaded before the gameplay callbacks so their Log()/Guard*()/SendPoliceAlert()
    -- globals exist as soon as those files register their handlers.
    'server/logs.lua',
    'server/security.lua',
    'server/dispatch.lua',
    'server/skill.lua',
    'server/main.lua',
    'server/btc_market.lua',
    'server/placement.lua',
    'server/theft.lua',
    'server/fire.lua',
    'server/access.lua',
    'server/admin.lua',
    'server/callbacks.lua',
    'server/components.lua',
}

files {
    'locales/*.json',
    'web/build/index.html',
    'web/build/**/*',
}

dependencies {
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'oxmysql',
    'qbx_core',
}
