# FKS Stables

A complete stable system for **RedM** — horses, wagons, care, death & revive, wild horse taming, a trainer job with
training and breeding, foals that grow up, and a hand-made "ink & wax seal" stable menu.

Works with **VORP** and **RSG**, with **vorp_inventory**, **rsg-inventory** or **ox_inventory**.
No `ox_target`: everything uses native RedM prompts. Available in 7 languages.

> License: **GPL-3.0-or-later** — see [LICENSE](LICENSE).

---

## Table of contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Items](#items)
- [Configuration](#configuration)
- [Trainer job](#trainer-job)
- [Wild horses](#wild-horses)
- [Controls](#controls)
- [Commands](#commands)
- [Exports](#exports)
- [HUD integration](#hud-integration)
- [Database](#database)
- [Languages](#languages)
- [Folder structure](#folder-structure)
- [Troubleshooting](#troubleshooting)
- [Credits](#credits)
- [Contributing](#contributing)
- [License](#license)

---

## Features

### Stables
- Stable menu with a showroom camera: buy horses and wagons, manage, rename, sell, treat, move them to another stable.
- Tack (saddles, blankets, saddlebags, horns, stirrups, bedrolls, holsters, manes, tails, masks, moustaches).
- Coat colour editor (body, mane and tail palettes / tints) — trainers only.
- Wagon customisation: paint, tint, extras, load and lanterns.
- Per-job limits, per-stable services, opening hours and job-restricted stables.

### Horses
- Whistle to call your horse: if it is far away it appears at a distance and gallops over; close by it trots over,
  follows you or stays. It comes back where it was after a relog / crash.
- **Classes and XP** — no levels: each class has a max XP (I 1000 · II 2000 · III 3000 · IV 4000 by default).
  A horse is fully trained at the max; health / stamina rings and attributes grow with the XP percentage.
- Needs: hunger, thirst, dirt and hooves. Feed items, drinking at rivers / troughs, eating hay, brushing,
  cleaning hooves, resting and sleeping.
- **Stimulants with a gold boost**: for a few seconds the stamina (and health) ring turns gold, never drops, and the horse
  ends fully recovered — with a timer on the HUD (see [HUD integration](#hud-integration)).
- **Courage** (0–10, fearless at 10) and **affinity** (0–10) that grow over time.
- Saddlebags (only with a bag equipped) with the "hand in the saddlebag" pose, shareable with other players.
- Horse sheet panel (Q) and a title over the horse with its name, XP and age.
- Death & revive: the body stays in place; revive it with an item (click a dot on the horse you want) or treat it at a
  stable. Whistling for a dead horse brings the body next to you.
- **Transfer** a horse to another player (hold C), and a **name tag** item to rename the active horse.

### Wagons
- Storage with access control, hunting wagons that carry carcasses and pelts.
- **Durability**: wears with kilometres and crashes; at 0 the wheels come off and it needs nails + a hammer.
- Send the wagon back to its stable from anywhere (optional).

### Wild horses
- Configurable zones with their own horses (shop coats or game models), spawn chance, cooldown, radius and blips.
- Server-side zone hosts: one player per zone spawns and keeps the horses inside it; automatic host reassignment and
  cleanup of empty zones. Captured horses are protected from cleanup. NPC horses can never be tamed.
- **Taming mini-game**: letters fall down the screen — press (or click) them before they reach the bottom.
- Sale points (map blip): **sell** the tamed horse (cash and/or gold) or **keep** it (pay a % of the shop price, random age).
- Sale cooldown and optional Discord webhook logs.

### Trainer job
- **Obstacle course**, **lunging** (the horse circles you, XP per minute) and **load training** (deliver a loaded wagon
  against the clock).
- **Breeding** at the stable with a dedicated camera: pick a female and a male, a foal is born after a while.
- **Foals** are born small, grow until 5 years old and cannot be ridden until then.
- Special (gold) horses come fully trained and can be blocked from breeding and from being transferred.

---

## Requirements

| | |
|---|---|
| Server | RedM with **OneSync** enabled |
| Libraries | [ox_lib](https://github.com/overextended/ox_lib), [oxmysql](https://github.com/overextended/oxmysql) |
| Framework | [vorp_core](https://github.com/VORPCORE/vorp-core-lua) **or** [rsg-core](https://github.com/Rexshack-RedM/rsg-core) |
| Inventory | `vorp_inventory`, `rsg-inventory` or `ox_inventory` |

---

## Installation

1. **Download** the latest release and put the `fks-stables` folder in your `resources` folder.
2. **Stop other stable scripts** that use the same keys / items / horse models (e.g. other stables or horse scripts),
   otherwise prompts and items will conflict.
3. **Add it to your server config** after its dependencies:
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure vorp_core        # or rsg-core
   ensure vorp_inventory   # or rsg-inventory / ox_inventory
   ensure fks-stables
   ```
4. **Create the items** in your inventory — see [Items](#items).
5. **Configure** the script — at least:
   - `config/main.lua` → `Config.Locale`, `Config.Framework` / `Config.Inventory` (`'auto'` detects them).
   - `config/stables.lua` → your stables (one example is included: Blackwater).
   - `config/trainer.lua` → the trainer job name and admin groups.
   - `Config.Wild.zones` → your wild horse zones (the included ones are examples).
6. **Start the server.** The database tables are created automatically on the first start — no SQL to import.
   The server console prints what was detected:
   ```
   [fks-stables] framework: vorp | inventory: vorp_inventory
   ```

> When you add new files to the resource, run `refresh` before `ensure fks-stables` (a plain `restart` does not read
> new files from the manifest).

---

## Items

Item names are set in `config/main.lua` (`Config.Feed`, `Config.Items`, `Config.Care.hoof.item`,
`Config.Wagon.repairItem`, `Config.Wagon.brokenRepair`). Defaults:

| Item | Use | Consumed |
|---|---|---|
| `horse_apple` | food | yes |
| `horse_carrot` | food | yes |
| `sugarcube` | food | yes |
| `haysnack` | food (hay cube) | yes |
| `horse_stimulant` | stimulant: 10 s gold stamina ring (infinite stamina), fully recovered after | yes |
| `horse_gold_stimulant` | gold stimulant: 10 s gold health + stamina rings, fully recovered after | yes |
| `horse_brush` | brush the horse (use the item or the lead menu) | no |
| `hoof_pick` | clean the hooves (lead menu) | no |
| `horse_reviver` | revive a dead horse | yes |
| `horse_nametag` | rename the active horse | yes |
| `wagon_repair_kit` | repair a worn wagon | yes |
| `nails` | repair a broken wagon (5 by default) | yes |
| `hammer` | repair a broken wagon | no |

<details>
<summary><b>VORP</b> — SQL for the <code>items</code> table</summary>

```sql
INSERT IGNORE INTO `items` (`item`, `label`, `limit`, `can_remove`, `type`, `usable`, `desc`) VALUES
('horse_apple', 'Apple', 20, 1, 'item_standard', 1, 'A treat for your horse.'),
('horse_carrot', 'Carrot', 20, 1, 'item_standard', 1, 'A treat for your horse.'),
('sugarcube', 'Sugar cube', 20, 1, 'item_standard', 1, 'A sweet treat for your horse.'),
('haysnack', 'Hay cube', 20, 1, 'item_standard', 1, 'Compressed hay for your horse.'),
('horse_stimulant', 'Horse stimulant', 10, 1, 'item_standard', 1, 'Refills your horse''s stamina.'),
('horse_gold_stimulant', 'Gold horse stimulant', 10, 1, 'item_standard', 1, 'Refills your horse''s health and stamina.'),
('horse_brush', 'Horse brush', 1, 1, 'item_standard', 1, 'Keeps your horse clean.'),
('hoof_pick', 'Hoof pick', 1, 1, 'item_standard', 0, 'Cleans your horse''s hooves.'),
('horse_reviver', 'Horse reviver', 5, 1, 'item_standard', 1, 'Revives a dead horse.'),
('horse_nametag', 'Horse name tag', 5, 1, 'item_standard', 1, 'Renames your active horse.'),
('wagon_repair_kit', 'Wagon repair kit', 5, 1, 'item_standard', 1, 'Repairs a worn wagon.'),
('nails', 'Nails', 50, 1, 'item_standard', 0, 'Used to repair a broken wagon.'),
('hammer', 'Hammer', 1, 1, 'item_standard', 0, 'Used to repair a broken wagon.');
```
</details>

<details>
<summary><b>RSG</b> — <code>rsg-core/shared/items.lua</code></summary>

```lua
horse_apple          = { name = 'horse_apple',          label = 'Apple',                weight = 100, type = 'item', image = 'horse_apple.png',          unique = false, useable = true,  shouldClose = true, description = 'A treat for your horse.' },
horse_carrot         = { name = 'horse_carrot',         label = 'Carrot',               weight = 100, type = 'item', image = 'horse_carrot.png',         unique = false, useable = true,  shouldClose = true, description = 'A treat for your horse.' },
sugarcube            = { name = 'sugarcube',            label = 'Sugar cube',           weight = 50,  type = 'item', image = 'sugarcube.png',            unique = false, useable = true,  shouldClose = true, description = 'A sweet treat for your horse.' },
haysnack             = { name = 'haysnack',             label = 'Hay cube',             weight = 200, type = 'item', image = 'haysnack.png',             unique = false, useable = true,  shouldClose = true, description = 'Compressed hay for your horse.' },
horse_stimulant      = { name = 'horse_stimulant',      label = 'Horse stimulant',      weight = 100, type = 'item', image = 'horse_stimulant.png',      unique = false, useable = true,  shouldClose = true, description = "Refills your horse's stamina." },
horse_gold_stimulant = { name = 'horse_gold_stimulant', label = 'Gold horse stimulant', weight = 100, type = 'item', image = 'horse_gold_stimulant.png', unique = false, useable = true,  shouldClose = true, description = "Refills your horse's health and stamina." },
horse_brush          = { name = 'horse_brush',          label = 'Horse brush',          weight = 200, type = 'item', image = 'horse_brush.png',          unique = false, useable = true,  shouldClose = true, description = 'Keeps your horse clean.' },
hoof_pick            = { name = 'hoof_pick',            label = 'Hoof pick',            weight = 100, type = 'item', image = 'hoof_pick.png',            unique = false, useable = false, shouldClose = true, description = "Cleans your horse's hooves." },
horse_reviver        = { name = 'horse_reviver',        label = 'Horse reviver',        weight = 100, type = 'item', image = 'horse_reviver.png',        unique = false, useable = true,  shouldClose = true, description = 'Revives a dead horse.' },
horse_nametag        = { name = 'horse_nametag',        label = 'Horse name tag',       weight = 50,  type = 'item', image = 'horse_nametag.png',        unique = false, useable = true,  shouldClose = true, description = 'Renames your active horse.' },
wagon_repair_kit     = { name = 'wagon_repair_kit',     label = 'Wagon repair kit',     weight = 500, type = 'item', image = 'wagon_repair_kit.png',     unique = false, useable = true,  shouldClose = true, description = 'Repairs a worn wagon.' },
nails                = { name = 'nails',                label = 'Nails',                weight = 10,  type = 'item', image = 'nails.png',                unique = false, useable = false, shouldClose = true, description = 'Used to repair a broken wagon.' },
hammer               = { name = 'hammer',               label = 'Hammer',               weight = 500, type = 'item', image = 'hammer.png',               unique = false, useable = false, shouldClose = true, description = 'Used to repair a broken wagon.' },
```
</details>

<details>
<summary><b>ox_inventory</b> — <code>ox_inventory/data/items.lua</code></summary>

```lua
['horse_apple']          = { label = 'Apple',                weight = 100, consume = 0, description = 'A treat for your horse.' },
['horse_carrot']         = { label = 'Carrot',               weight = 100, consume = 0, description = 'A treat for your horse.' },
['sugarcube']            = { label = 'Sugar cube',           weight = 50,  consume = 0, description = 'A sweet treat for your horse.' },
['haysnack']             = { label = 'Hay cube',             weight = 200, consume = 0, description = 'Compressed hay for your horse.' },
['horse_stimulant']      = { label = 'Horse stimulant',      weight = 100, consume = 0, description = "Refills your horse's stamina." },
['horse_gold_stimulant'] = { label = 'Gold horse stimulant', weight = 100, consume = 0, description = "Refills your horse's health and stamina." },
['horse_brush']          = { label = 'Horse brush',          weight = 200, consume = 0, description = 'Keeps your horse clean.' },
['hoof_pick']            = { label = 'Hoof pick',            weight = 100, description = "Cleans your horse's hooves." },
['horse_reviver']        = { label = 'Horse reviver',        weight = 100, consume = 0, description = 'Revives a dead horse.' },
['horse_nametag']        = { label = 'Horse name tag',       weight = 50,  consume = 0, description = 'Renames your active horse.' },
['wagon_repair_kit']     = { label = 'Wagon repair kit',     weight = 500, consume = 0, description = 'Repairs a worn wagon.' },
['nails']                = { label = 'Nails',                weight = 10,  description = 'Used to repair a broken wagon.' },
['hammer']               = { label = 'Hammer',               weight = 500, description = 'Used to repair a broken wagon.' },
```
`consume = 0`: the script removes the item itself (only when the action actually happens).
</details>

> **RSG + gold:** rsg-core has no gold account by default. `Config.RSGGoldAccount` (default `'gold'`) is the money
> type used as gold; set it to `nil` to disable gold prices on RSG.

---

## Configuration

| File | What |
|---|---|
| `config/main.lua` | language, framework, keys, prices, needs, care, revive, wild horses, XP, aging, wagons |
| `config/trainer.lua` | trainer job, training courses / load points, courage, affinity, class stats, special horses, transfer, breeding, foals |
| `config/stables.lua` | stables (every field explained) |
| `config/horses.lua` | horse shop: breeds and coats (price, class, storage, look) |
| `config/wagons.lua` | wagon shop and per-model customisation |
| `config/components.lua` | tack pieces per category and colour palettes |
| `config/animals.lua` | carcasses and pelts that fit in hunting wagons |
| `locales/*.lua` | texts in every language |

### Adding a stable
Copy the Blackwater block in `config/stables.lua` and change the id, label and coordinates. Every field is commented.

---

## Trainer job

Training, breeding and the coat colour editor are only available to trainers:

```lua
Config.Trainer = {
    jobs = { 'treinador' },                    -- your trainer job name(s)
    adminGroups = { 'admin', 'superadmin' },   -- framework admin groups also get access
    adminAce = 'fks-stables.admin',            -- or give the ace: add_ace group.admin fks-stables.admin allow
}
```

- **Obstacle course** — holding the reins, *Training → Obstacles* near a course start; mount and ride through every
  marker in order. Courses in `Config.Training.obstacles.courses`.
- **Lunging** — holding the reins, *Training → Lunging*; the horse circles you. ↑/↓ speed, Space jump, Backspace stop.
- **Load training** — ride to a load point (ground marker) and press E; drive the wagon to the random destination before
  the timer ends. Points and destinations in `Config.Training.load`.
- **Breeding** — in the stable menu (*Breeding* tile). Both parents must be adults, at that stable and not on cooldown.

> RedM has no reliable way to harness a ridden horse to a wagon, so during load training your horse is stored and you
> drive the training wagon; the XP goes to your horse and it comes back next to you at the end.

---

## Wild horses

Zones live in `Config.Wild.zones` — every field is documented in the config. Each zone can list shop coats
(`{ coat = 'coat id' }`, uses that coat's look and price) or game models (`{ model = 'a_c_horse_...' }`).
Sale points are in `Config.Wild.points`.

With `Config.Debug = true`, `/fks_wildspawn` spawns horses right away in the zone you are in.

---

## Controls

| Where | Key | Action |
|---|---|---|
| Anywhere | **H** | whistle / call your horse |
| Anywhere | **J** | call your wagon (if allowed) |
| Looking at your horse | **R** | saddlebags (only with a bag equipped) |
| | **Q** | horse sheet |
| | **E** | lead by the reins |
| | **G** | pat |
| | **F** | send away (to the stable) |
| | **X** | follow me / stay |
| | **C** (hold) | transfer to another player |
| | **B** (hold) | revive (dead horse) |
| Leading the horse | **R** feed · **Z** drink · **Q** hay · **B** brush · **C** hooves · **X** rest · **U** sleep · **E** training · **F** drop reins | |
| Near your wagon | **R** storage · **G** store animal · **E** animals · **X** store / send away · **Z** repair | |
| Stable hand | **E** | open the stable |

All keys can be changed in `Config.Prompts`, `Config.Keys`, `Config.Training` and `Config.Give`.

---

## Commands

| Command | Who | Description |
|---|---|---|
| `/canceltraining` | everyone | cancels the training in progress |
| `/fks_horse` | everyone | prints your horse state in the F8 console (diagnostics) |
| `/fks_wild` | everyone | prints the wild horse zones state (diagnostics) |
| `/fks_prompts` | everyone | prints the horse prompts state (diagnostics) |
| `/fks_props` | `Config.Debug` | lists nearby props (find trough / hay models) |
| `/fks_animal [model] [quality]` | `Config.Debug` | spawns a carcass to test hunting wagons |
| `fks_wildspawn` | `Config.Debug` | spawns wild horses now in your zone (server / chat) |

---

## Exports

**Client**
```lua
exports['fks-stables']:GetHorse()       -- ped of your horse (or nil)
exports['fks-stables']:GetHorseData()   -- data of your active horse
exports['fks-stables']:FleeHorse()      -- despawn your horse
exports['fks-stables']:GetWagon()       -- vehicle of your wagon (or nil)
exports['fks-stables']:FleeWagon()      -- despawn your wagon
```

**Server**
```lua
exports['fks-stables']:GetActiveHorse(source)  -- data of the player's active horse
```

---

## HUD integration

When a stimulant with a gold boost is used, fks-stables fires a **client** event that any HUD can listen to:

```lua
-- horse = horse ped · which = 'stamina' | 'health' · seconds = boost duration
AddEventHandler('fks-hud:client:horseGold', function(horse, which, seconds)
    -- lock that ring at the max and show a timer for `seconds`
end)
```

fks-hud supports it out of the box (gold ring locked at the max + countdown). The gold colour itself comes from the
game's "overpower" state, so HUDs that read `IsAttributeCoreOverpowered` also show it.

---

## Database

Created automatically on start (and migrated when columns are missing):

| Table | |
|---|---|
| `fks_horses` | horses: owner, coat, tack, XP, bond, courage, affinity, needs, age, state |
| `fks_wagons` | wagons: owner, model, customisation, durability, storage access, stored animals |
| `fks_breeding` | breedings in progress (foals are born even with the owner offline) |

---

## Languages

`Config.Locale` = `'en'` · `'pt'` (Portugal) · `'br'` (Brazil) · `'es'` · `'fr'` · `'de'` · `'it'`.
Any text missing from a language falls back to English. To add a language, copy `locales/en.lua`, change
`Locales['en']` to your code and translate the texts.

---

## Folder structure

```
fks-stables/
├── client/          game logic (horse, wagon, care, prompts, stable menu, wild horses, training)
├── server/          framework/inventory bridge, database, stable logic, trainer logic
├── shared/          catalogue indexes, helpers and the locale loader
├── config/          everything you can change (see Configuration)
├── locales/         en, pt, br, es, fr, de, it
├── html/            stable menu (NUI): page, styles, script, fonts and icons
├── fxmanifest.lua
├── LICENSE
└── README.md
```

---

## Troubleshooting

- **Nothing happens / no prompts** — check the server console line `[fks-stables] framework: ... | inventory: ...`.
  If one is `nil`, set `Config.Framework` / `Config.Inventory`.
- **Items do nothing** — the item has to exist in your inventory with the same name as in the config, and be usable.
- **I added files and they are not loading / the menu icons show empty squares** — run `refresh` then
  `ensure fks-stables` (a plain `restart` does not read new files from the manifest). If it persists on your client,
  reconnect or clear the RedM cache (`RedM.app/data/cache`).
- **The camera got stuck in the stable** — `restart fks-stables` always closes the menu and frees the player.
- **A native does not work on my RedM build** — set `Config.Debug = true`; protected natives print a warning in F8.
- **Horses spawn in weird places** — the wild horse zones in the config are examples; set your own coordinates.

---

## Credits

- Fonts: [Alegreya SC](https://fonts.google.com/specimen/Alegreya+SC), [Alegreya Sans](https://fonts.google.com/specimen/Alegreya+Sans),
  [Alegreya Sans SC](https://fonts.google.com/specimen/Alegreya+Sans+SC) and [Rye](https://fonts.google.com/specimen/Rye) —
  licensed under the [SIL Open Font License 1.1](https://openfontlicense.org).
- Built for the RedM community. Thanks to the Overextended (ox_lib, oxmysql), VORP and RSG teams.

---

## Contributing

Issues and pull requests are welcome. Please keep new texts in `locales/` (English is the base language) and test on
both VORP and RSG when touching `server/bridge.lua`.

---

## License

Copyright (C) 2026 FKS

This program is free software: you can redistribute it and/or modify it under the terms of the
**GNU General Public License** as published by the Free Software Foundation, either **version 3** of the License, or
(at your option) any later version. It is distributed in the hope that it will be useful, but **WITHOUT ANY WARRANTY**.
See [LICENSE](LICENSE) for the full text.
