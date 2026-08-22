# Nt_BlackJack

## [Showcase](https://www.youtube.com/watch?v=D0u9JJw7kyE)

Server-authoritative multiplayer Blackjack for RedM with RSG Core and VORP cash support.

## Features

- One to four human players against an NPC dealer  
- Sequential shuffled shoe; cards are never randomly selected during a hand  
- Hit, Stand, Double Down, and one Split  
- Dealer peek, configurable soft-17 behavior, 3:2 blackjack payouts, and pushes  
- Server-side cards, action validation, cash debits, and payouts  
- PolyZone pulled NPC players and spectator rendering  
- Full-screen NUI with bundled card styles, camera controls, and UI scaling  
- Additional tables can be added by duplicating a single keyed config entry  

## Requirements

- RSG Core or VORP  

## Setup

1. Set `Config.Framework` in `shared/config.lua` to `RSG` or `Vorp`.  
2. Enable or disable the included Rhodes, Blackwater, and Vanhorn tables as desired.  
3. Adjust bet limits, rules, NPC players, blips, and other options if desired.  
4. Add `ensure Nt_BlackJack` to the server configuration.  

## Adding tables

Duplicate an existing entry in `Config.Tables`, give it a unique key, and replace the table, dealer, seat, and NPC scan-area coordinates. Game state, seats, shoe, timers, and events are isolated by that key.  

## License and Warranty

This project's source code is licensed under the GNU General Public License v3.0 (GPL-3.0). See the LICENSE file for details.  
This software is provided WITHOUT ANY WARRANTY. See the GNU GPLv3 for details.  

Images and screenshots derived from Red Dead Redemption 2 are not covered by this license and remain the property of their respective rights holders. Red Dead Redemption 2 © Rockstar Games / Take-Two Interactive.
