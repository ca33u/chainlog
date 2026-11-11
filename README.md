English · [Русский](README.ru.md)

# Chainlog

A dungeon quest checklist for **World of Warcraft: Forever** (Interface 16001). Made by **addicted** ([addicted.sh](https://addicted.sh)), MIT license.

## Features

- **Every dungeon with quests** for your faction, race, class and professions (Alliance-only quest givers are hidden for the Horde and the other way round; profession quests only if you have that profession): level ranges and how many quests you've already done ("3/7"). By default it shows dungeons around your level; the "Show all levels" checkbox shows all of them, raids included.
- **Whole chains**: a dungeon quest together with all its prerequisites (earlier steps, optional lead-ins) and follow-ups, in the order you do them.
- **Where to get it**: for each quest, who gives it, the zone and coordinates; if the quest starts from an item, what the item is and what drops it.
- **Map waypoint**: click a quest to set a waypoint to the quest giver (or to the turn-in, if you already have the quest). With TomTom you get the TomTom arrow, without it a regular in-game map pin. Click the "Entrance" row to set a waypoint to the dungeon entrance.
- **Statuses**: ✓ done · ? in your quest log (yellow: ready to turn in) · ! available (grey: needs a higher level) · lock: finish the previous step first.
- **Chain guidance**: press "Lead" on any chain and the TomTom arrow (without TomTom, the game's map pin) walks you through the steps by itself: to the quest giver → to the nearest place where the objective is done (the mob you need, what drops the item, the object, the area) → to the turn-in → to the next quest. The chain is remembered between sessions. Objectives inside a dungeon lead to its entrance.
- **Inside the dungeon**: each dungeon has an "Inside" section: which bosses and mobs to kill, what to loot and from whom, who to talk to for your quests. When you enter the dungeon, a small checklist with these objectives appears; they get checked off as you complete them (based on your quest log lines). There's no arrow inside: the game doesn't give addons coordinates in dungeons.
- **"My quests" tab**: quests from your quest log that are part of a chain, with the step number and the whole chain around them.
- **Abandon warning**: if you abandon a chain quest or a dungeon quest, a panel pops up next to it: which step it is, which steps will be locked, and where to pick the quest up again.

## Where the data comes from

Chainlog doesn't ship its own quest database: it reads it in game from **QuestieDB** (built for Forever) through its public API. QuestieDB must be installed and enabled. Questie itself is not required.

## Commands

| Command | What it does |
|---|---|
| `/chainlog` (or `/chains`) | open / close the window |
| `/chainlog log` | go straight to the "My quests" tab |
| `/chainlog next` | show the next step of the chain being led |
| `/chainlog stop` | stop leading |
| `/chainlog tracker` | dungeon checklist on/off |
| `/chainlog warn` | abandon warning on/off |
| `/chainlog minimap` | minimap button on/off |

Minimap button: left-click opens the window, right-click opens "My quests", drag to move it.

## Installation

Put the `Chainlog` folder into `World of Warcraft/_forever_/Interface/AddOns`; `QuestieDB` must be there next to it.

© 2026 addicted · [addicted.sh](https://addicted.sh). MIT license, see `LICENSE`.
