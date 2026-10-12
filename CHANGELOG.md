# Changelog

## 1.0.1

- Fix: donkeys (A_C_Donkey_01) and other adult horses keep the model's original size (the donkey was bigger than a horse).
- Fix: the called horse sometimes vanished right after appearing (spawn point inside the terrain on slopes); if it
  still vanishes in the first seconds it is called again automatically.
- Server console shows whether the resource is up to date or outdated compared with GitHub.
- fks-utils is no longer a hard dependency: without it the resource still starts, the console shows a warning with
  the download link, and notifications / progress bar use ox_lib.

## 1.0.0

First public release.

- Stables: horse and wagon shops, showroom camera, tack, coat colour editor (trainers), wagon customisation,
  transfers between stables, per-job limits.
- Horses: whistle / follow / stay, classes and XP (no levels), needs and care (feed, drink, hay, brush, hooves,
  rest, sleep), courage and affinity, saddlebags, horse sheet, death & revive, transfer to players, name tag item,
  stimulants with a gold boost.
- Wagons: storage with access control, hunting wagons (carcasses and pelts), durability with broken wheels and
  on-the-spot repair, send back to the stable.
- Wild horses: zones with server-side hosts, taming mini-game, sale points (sell or keep), Discord webhook.
- Trainer job: obstacle course, lunging, load training, breeding and foals that grow up.
- Frameworks: VORP and RSG · Inventories: vorp_inventory, rsg-inventory, ox_inventory.
- Languages: English, Português (PT), Português (BR), Español, Français, Deutsch, Italiano.
