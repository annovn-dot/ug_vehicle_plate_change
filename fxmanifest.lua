fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author "BOGi"
name "Vehicle plate change system"
description "The Underground - Plate change"
version "4.2.0"

shared_scripts {
    '@ox_lib/init.lua',
    'config/cfg_settings.lua'
}

client_scripts {
    'client/cl_main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_utils.lua',
    'server/sv_main.lua'
}
