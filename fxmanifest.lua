fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

version '1.1.0'
author 'Nubetastic'
description 'Server-authoritative multiplayer Blackjack for RSG and VORP'

shared_scripts {
    'shared/config.lua',
    'shared/configProps.lua',
    'shared/cards.lua',
}

client_scripts {
    'client/props.lua',
    'client/dealer.lua',
    'client/npc.lua',
    'client/nui.lua',
    'client/client.lua',
}

server_scripts {
    'server/framework.lua',
    'server/server.lua',
    'server/runtime.lua',
}

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/img/*.png',
}

ui_page 'ui/index.html'
