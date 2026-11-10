# Changelog

## 1.5.1

- **Breeding parents no longer stack:** each breeding in progress at a stable gets its own spot. Set
  `breed.slots = { { left, right }, ... }` on a stable, or the pairs line up beside `breed.left` / `breed.right`
  (`Config.Breeding.worldSlots`, `slotSpacing`). Extra breedings are not shown.
- `Config.Breeding.showParentsInWorld` / `showFoalInWorld` (default `true`) hide the parents during the pregnancy
  and the newborn foal at the breeding spot.
- **Fixed a ped leak in the breeding menu:** switching horses quickly or closing the menu while a horse was loading
  left a frozen horse behind. The menu now drops stale loads and removes any leftover showroom horse on close.
- **Safer wagon spawn:** the point snaps to the ground and, if a vehicle or ped is in the way, small offsets are
  tried (`Config.Wagon.safeSpawn`).
- `Config.MaxAgeAction` = `'none'` (default, unchanged) | `'retire'` | `'die'`: what happens at `Config.Aging.maxAge`.
  Worked out from the age only, nothing is deleted. Aging is in real time (comment added to the config).
- **Fixed outlier horse prices** (`config/horses.lua`, brought in line with the other coats of the breed):
  Norfolk Roadster Speckled Grey 2500, Breton Grullo Dun 3000, Breton Steel Black / Steel Bay 3500,
  Shire Buckskin / Bay 3000, Shire "Gigante" 3500, Mustang Black Dun / BrownNuts 3000,
  Missouri Fox Trotter Dapple Pinto Bay / Red 4500, Appaloosa Leopard 1300.
- Saint Denis spawn and Valentine showroom camera marked `-- TODO: rever in-game` in `config/stables.lua`.
- No database changes.

## 1.5.0

- **Job-only horses:** `Config.HorseShopAccess` (end of `config/horses.lua`) restricts horses in the shop to jobs
  and/or groups by **breed**, **single coat** or **class (tier)** — e.g. a breed only the `emeraldbreeder` job can buy.
  The most specific rule wins (coat's own `jobs`/`groups` > `coats` > `breeds` > `tiers`); `false` opens one coat to
  everyone inside a restricted breed. Checked on the server when buying too.
- No database changes.

## 1.4.0

- **No more ox_lib.** fks-core and oxmysql are the only dependencies: remove `ensure ox_lib` if no other script uses it.
  Server callbacks have their own small layer (`shared/callback.lua`).
- **Every menu is drawn by fks-core** in the FKS look: horse feed list, wagon storage (open / give access / manage
  access), stored animals, wild horse sale point (sell / keep with name), training menu, name tag and transfer dialogs.
  The training timer shows as an fks-core caption.
- **Pat your horse:** the "Pat" prompt now shows when looking at your horse (it was on **G**, which never appeared;
  now **B**, `Config.Prompts.pat`). The player drops the reins, walks to the horse's neck and plays the game's patting
  clips (`mech_animal_interaction@horse@left|right@patting@short|long`, `Config.Pat.style`).
- No database changes.

## 1.3.0

- **The stable menu is now drawn by fks-core** (shared FKS UI). fks-stables no longer ships its own HTML, CSS, JS or
  fonts, so the server runs one NUI for every FKS script and the look follows `Config.Theme` in fks-core.
  The horse sheet, the revive dot picker and the taming letters are drawn by fks-core too.
- **Requires fks-core 2.1.0+.**
- Same screens and flow as before (home, horse / wagon shop, my horses / wagons, breeding, tack, coat and wagon
  customisation). The menu icons moved from `html/` to `img/`.

## 1.2.0

- **New stables:** Valentine, Rhodes, Saint Denis, Strawberry and Tumbleweed (6 in total). *(sathishkumar2611)*
- **Stash slots** separate from the weight: `Config.Stash.horseSlots` (8), `Config.Stash.wagonSlots` (50) and `slots`
  per wagon in `config/wagons.lua`. *(sathishkumar2611)*
- **Wild horses:** 9 zones across the map, sale points linked to the new stables, sell value by class
  (`Config.Wild.sellPrice`) and `Config.Wild.allowKeep` to only allow selling. *(sathishkumar2611)*
- **Horse shop:** every coat on sale and able to breed. *(sathishkumar2611)*
- **Pregnant mares:** after breeding only the mare waits for the birth (the stallion is free right away) and she can be
  taken out and ridden (`Config.Breeding.pregnancy.canLeave`). Optional belly look with
  `Config.Breeding.pregnancy.expressions` (find them with `/fks_expr`, `Config.Debug`).
- **Fix:** you can aim at / shoot your own horse like any other (`Config.Horse.canShootOwn`).
- **Saddlebags** open from both sides of the horse (`Config.Stash.bagsSide` can limit it to `'right'` or `'left'`).
- **Cleaning hooves:** the horse and the player stay still for the whole scene.
- **Fix:** the gold stimulant item is `horse_gold_stimulant` in the config too (it was `horsegold_stimulant`, so the
  item from the README / SQL did nothing). `install/items_vorp.sql` with every item for VORP.
- No database changes.

## 1.1.0

- **fks-utils 1.1.0 is now required.** The VORP / RSG bridge (players, money, items, storages) moved into fks-utils,
  shared by all the FKS scripts: `ensure fks-utils` before `ensure fks-stables`. Without it the server console shows
  the download link.
- Notifications and progress bar always use fks-utils (no ox_lib fallback).
- No config or database changes.

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
