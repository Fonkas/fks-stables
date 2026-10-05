Config = Config or {}

Config.Debug = false                -- true: extra info in the F8 console and debug commands (/fks_wildspawn, /fks_animal...)

-- Language: 'en' | 'pt' | 'br' | 'es' | 'fr' | 'de' | 'it' (files in locales/; missing keys fall back to English)
Config.Locale = 'en'

-- Framework: 'auto' | 'rsg' | 'vorp'
Config.Framework = 'auto'
-- RSG only: money account used as "gold" (rsg-core has no gold account by default; set nil to disable gold on RSG)
Config.RSGGoldAccount = 'gold'
-- Inventory: 'auto' | 'ox_inventory' | 'rsg-inventory' | 'vorp_inventory'
-- ('auto' picks in this order: ox_inventory > rsg-inventory > vorp_inventory, depending on what is running)
Config.Inventory = 'auto'

---------------------------------------------------------------------------
-- Stables
---------------------------------------------------------------------------
Config.KeepAtStable = false         -- true: a horse/wagon can only be taken out at the stable where it was stored
Config.TransferPrice = 50           -- price to move a horse/wagon to another stable (0 = free)
Config.NpcDistance = 40.0           -- distance at which the stable hand spawns
Config.InteractDistance = 3.0       -- distance to the stable hand for the prompt to show
Config.Blip = { sprite = 1938782895, label = 'Stable' }

---------------------------------------------------------------------------
-- Limits per job (jobs not listed use "default")
---------------------------------------------------------------------------
Config.Limits = {
    default     = { horses = 5,  wagons = 3 },
    treinador   = { horses = 20, wagons = 5 },   -- example: the trainer job (Config.Trainer) can own more horses
}

---------------------------------------------------------------------------
-- Horse: calling / whistling
---------------------------------------------------------------------------
Config.Horse = {
    callFromStableOnly = false,     -- true: horses are only taken out at the stable (the whistle only calls one already out)
    whistleCooldown = 5,            -- seconds between whistles
    comeDistance = 100.0,           -- if the horse is closer than this, it trots over to you
    spawnDistance = { 30, 45 },     -- otherwise it spawns this far away (never closer) and runs over to you
    comeSpeed = 3.0,                -- speed when coming from far away (1 walk · 2 trot · 3 gallop)
    despawnDistance = 250.0,        -- if you go further than this the horse is stored (0 = never)
    followDistance = 6.0,           -- whistling near the horse -> it follows you
    respawnAfterLogin = true,       -- comes back where it was after a relog / crash
    allowTwoRiders = true,
    blockNativePrompts = true,      -- hides the game prompts (Lead, Pat, Flee) and uses the script's, in your language
}

-- Pat: game interaction used (tried in order; with Config.Debug each click uses the next one
-- and prints which one it was in the F8 console — keep only the one that works)
Config.Pat = {
    interactions = { 'Interaction_Pat', 'Interaction_Pat_Horse', 'Interaction_Reward', 'Interaction_Comfort' },
    bond = 1,           -- bond gained
    cooldown = 15,      -- seconds between pats that give bond
}

Config.Gender = { femaleChance = 50 }  -- for tamed / born horses (when buying, the player picks)

---------------------------------------------------------------------------
-- Keys (RedM control hashes)
---------------------------------------------------------------------------
Config.Keys = {
    whistle   = 0x24978A28,   -- H   whistle / call horse
    wagonCall = 0xF3830D8E,   -- J   call the active wagon (if callFromStableOnly = false)
}

-- Prompts (no ox_target). On the horse they show next to the native ones (Show Info, Lead, Pat, Flee)
-- when you look at it; on the wagon and the stable hand they show when you are close.
-- The native "Flee" (F) sends the horse to the stable.
-- The horse's native prompts (Lead, Pat, Flee, Show Info, Brush, Feed...) are hidden (hideNative) and
-- replaced by the script's, so everything shows in your language and with the same keys.
Config.Prompts = {
    -- Horse: uses "InteractionLockOn" controls (normal ones, like R to reload, do not work while looking at the horse)
    bags        = 0x0D55A0F0, -- R   saddlebags (INPUT_INTERACT_HORSE_FEED)
    -- Replace the native prompts — see hideNative
    showInfo    = 0x31219490, -- Q   horse sheet (panel)
    lead        = 0x17D3BFF5, -- E   lead by the reins
    pat         = 0xA1ABB953, -- G   pat (calms it and gives bond)
    flee        = 0x4216AF06, -- F   send to the stable
    stopLead    = 0x26A18F47, -- F   drop the reins (lead menu · INPUT_INTERACT_LOCKON_NEG, active on foot)
    care        = 0x63A38F2C, -- B   (hold) revive, with the horse dead (brushing is in the lead menu)
    follow      = 0x8CC9CD42, -- X   follow me / stay
    -- While leading the horse (Lead)
    careFeed    = 0xE30CD707, -- R   feed (opens the list of food you have)
    careDrink   = 0x26E9DC00, -- Z   drink (only in a river or next to a trough with water)
    careHay     = 0xDE794E3E, -- Q   eat hay (only next to hay / a feeder)
    -- (G — INPUT_INTERACT_OPTION1 — is not active while leading the horse: do not use it here)
    careBrush   = 0x4CC0E2FE, -- B   (hold) brush — only while leading
    careHoof    = 0x9959A6F0, -- C   (hold) clean hooves — only while leading
    careRest    = 0x8CC9CD42, -- X   rest (lies down)
    careSleep   = 0xD8F73058, -- U   sleep
    standUp     = 0x8CC9CD42, -- X   stand up (looking at the horse lying down)
    -- Wagon and stable hand (own group, normal controls)
    wagonBags   = 0xE30CD707, -- R   storage (open / give access / manage access)
    wagonAnimal = 0x760A9C6F, -- G   store the animal you are carrying (hunting wagons)
    wagonAnimals= 0xCEFD9220, -- E   manage animals (at the back of the wagon)
    talk        = 0xCEFD9220, -- E   talk to the stable hand
    wagonReturn = 0x8CC9CD42, -- X   (hold) store the wagon near a stable / send it away (Config.Wagon.sendAway)
    wagonRepair = 0x26E9DC00, -- Z   (hold) repair the wagon
    wagonDistance = 1.6,      -- distance to the wagon's "box" to show the prompts
    wagonRear = 1.2,          -- how far behind the wagon the "manage animals" area is
    horseTab = 0,             -- page of the horse menu where the prompts go (0 = first)
    -- Hidden native game prompts. Numbers from the ePromptType enum:
    --   11 = HORSELEADING (Lead / Stop Leading) · 27 = HORSE_CALM · 33 = HORSE_FLEE · 35 = TARGET_INFO (Show Info)
    --   49 = HORSE_BRUSH · 50 = HORSE_FEED
    -- Do NOT add 5 (HORSEINTERACT) nor 52 (ANIMAL_INTERACT): they disable the G control and "Drink" disappears.
    -- The native Pat / Lead / Flee are already hidden by horse flag 412 (Config.Horse.blockNativePrompts).
    hideNative = { 11, 27, 33, 35, 49, 50 },
    -- the same, applied straight to your horse when it spawns (this is what hides the generic "Show Info")
    --   28 = HORSE_ITEMS · 45/46 = HORSE_WEAPONS
    hideForHorse = { 11, 27, 28, 33, 35, 45, 46, 49, 50 },
}

---------------------------------------------------------------------------
-- Service prices
---------------------------------------------------------------------------
Config.Prices = {
    healPercent = 30,           -- treating an injured/dead horse costs x% of its original price
    healMin = 15,               -- minimum
    rename = 5,                 -- rename
    coloring = 25,              -- change the coat (per saved change)
    components = {              -- price per equipped piece (cash)
        blankets = 5,  saddles = 25, horns = 3,  saddlebags = 12, stirrups = 4, bedrolls = 3,
        manes = 2,     tails = 2,    masks = 3,  mustaches = 1,   holsters = 6,
    },
    wagon = {
        livery = 15, tint = 10, extra = 3, propset = 20, lantern = 8,
    },
}

Config.Sell = {
    allowOld = true,             -- old horses can be sold (if false, they sell for 0)
}

---------------------------------------------------------------------------
-- Saddlebags / storage: capacity = the horse's/wagon's storage
-- (vorp_inventory only uses an item limit; ox_inventory and rsg-inventory use slots + weight)
---------------------------------------------------------------------------
Config.Stash = {
    -- animation when opening the saddlebags (game interaction; nil = no animation)
    bagsInteraction = 'Interaction_LootSaddleBags',
    bagsDelay = 1000,             -- ms of interaction (the player reaches the saddlebag) before switching to the pose
    bagsPose = 'mech_pickup@loot@horse_saddlebags@live@%s', -- pose while the inventory is open (%s = lt / rt)
    bagsPoseClip = 'base',
    maxSlots = 50,               -- max visible slots (ox / rsg grid)
    gramsPerStorage = 1000,      -- max weight = storage * this (120 -> 120kg)
    ownerOnly = false,           -- true: only the owner opens the saddlebags (false: anyone nearby)
}

---------------------------------------------------------------------------
-- Needs
---------------------------------------------------------------------------
Config.Needs = {
    enabled = true,
    tick = 30,                              -- seconds between updates
    drain = {                               -- { hunger, thirst } lost per tick (0-100)
        idle   = { 0.15, 0.25 },
        walk   = { 0.25, 0.40 },
        run    = { 0.45, 0.70 },
        sprint = { 0.70, 1.00 },
    },
    starving = 10,                          -- below this it loses health and stamina
    starvingLoss = { health = 4, stamina = 6 },
    dirtPerTick = 1.5,                      -- dirt (0-100) gained per tick while riding
}

---------------------------------------------------------------------------
-- Care (while leading the horse — "Lead")
---------------------------------------------------------------------------
Config.Care = {
    mountedFeed = true,                     -- using a food item while mounted feeds the horse (the player leans down to its mouth)

    -- Drink: in a river/lake (horse in the water) or next to a trough
    -- stamina = core (centre of the icon) · staminaBar = % of the current stamina bar (the ring), restored during the animation
    drink = {
        thirst = 45, stamina = 35, health = 10, staminaBar = 50,
        duration = 8000,                    -- ms
        -- horse animation { dictionary, clip }
        anim = { 'amb_creature_mammal@world_horse_drink_ground@base', 'base' },           -- river
        troughAnim = { 'amb_creature_mammal@prop_horse_drink_trough@idle0', 'idle_a' },  -- trough
        -- troughs: model names OR hashes (numbers) — use /fks_props next to one to find them
        troughs = {
            'p_watertrough01x', 'p_watertrough02x', 'p_watertrough03x', 'p_watertrough04x',
            'p_watertroughsml01x', 'p_watertroughsml02x', 'p_watertrough01x_new',
            'p_trough01x', 'p_trough02x', 'p_trough03x', 'p_horsetrough01x', 'p_wateringtrough01x',
        },
        troughDistance = 2.5,
    },

    -- Eat hay: next to hay bales / piles on the map
    hay = {
        hunger = 45, stamina = 30, health = 10, staminaBar = 50,
        duration = 10000,
        anim = { 'amb_creature_mammal@world_horse_grazing@idle', 'idle_a' },
        props = {
            'p_haybale01x', 'p_haybale02x', 'p_haybale03x', 'p_haybale04x', 'p_haybale05x',
            'p_haybalestack01x', 'p_haybalestack02x', 'p_haypile01x', 'p_haypile02x', 'p_haypile03x',
            'p_hay01x', 'p_haytrough01x', 'p_feedtrough01x', 'p_feedtrough02x',
        },
        distance = 2.5,
    },

    -- Rest (lies down) and sleep: recovers every "tick" seconds while on the ground.
    -- Animations { dictionary, clip }: enter = lie down · loop = pose (list: uses the first that exists) · exit = stand up
    rest = {
        tick = 5, stamina = 3, health = 1,
        enter = { 'amb_creature_mammal@world_horse_resting@stand_enter', 'enter' },
        loop = {
            { 'amb_creature_mammal@world_horse_resting@stand_enter', 'base' },
        },
        exit = { 'amb_creature_mammal@world_horse_resting@quick_exit', 'quick_exit' },
    },
    sleep = {
        tick = 5, stamina = 6, health = 3,
        enter = { 'amb_creature_mammal@world_horse_resting@stand_enter', 'enter' },
        loop = {
            { 'amb_creature_mammal@world_horse_sleeping@base', 'base' },
            { 'amb_creature_mammal@world_horse_sleeping@idle', 'idle_a' },
            { 'amb_creature_mammal@world_horse_resting@sleep', 'base' },
            { 'amb_creature_mammal@world_horse_resting@stand_enter', 'base' }, -- fallback: lying down
        },
        exit = { 'amb_creature_mammal@world_horse_resting@quick_exit', 'quick_exit' },
    },

    -- Hooves: get dirty while riding; below "penalty" the horse tires faster
    hoof = {
        item = 'hoof_pick',                 -- required tool (not consumed)
        drain = { walk = 0.3, run = 0.6, sprint = 1.0 },   -- per tick (0-100)
        penalty = 30,
        penaltyStamina = 5,                 -- extra stamina lost per tick below "penalty"
        -- game animation: "stranded rider" scene (script_re@stranded_rider) — the player behind the horse,
        -- holding the hind leg, cleaning the hoof. Player and horse play the same scene from the horse.
        anim = {
            dict = 'script_re@stranded_rider',
            player = 'horseshoe_idle_man',
            horse = 'horseshoe_idle_horse',
        },
        duration = 9000,                    -- ms cleaning
        -- fallback player position {x, y, z, heading} relative to the horse (only if the game does not give the scene position)
        fallback = { -0.6, -0.9, 0.0, 200.0 },
        -- hoof pick in hand (first model that exists in the game; {} = no prop)
        props = { 'p_hoofpick01x', 'p_hoofpick02x', 'p_cs_hoofpick01x', 'w_melee_hoofpick01' },
        propBone = 'SKEL_R_HAND',
        propOffset = { 0.08, 0.02, -0.02, 0.0, 0.0, 0.0 },
        xp = 3, bond = 1,
    },
}

-- Horse food (inventory items). Values 0-100.
--   health / stamina restore the horse's "core" (the health ring / the stamina ring)
--   label: name shown in the food menu · prop: object in hand during the animation (optional)
--   core = true: stimulant animation (the player gives it by the mouth)
--   gold = { stamina = s, health = s }: gold boost — for s seconds the ring turns gold and never drops (infinite),
--          and the horse ends fully recovered (same idea as the gold tonics in fks-hud)
Config.Feed = {
    horse_apple          = { label = 'Apple',          hunger = 30, thirst = 15, health = 15,  stamina = 20,  bond = 3, prop = 'p_apple01x' },
    horse_carrot         = { label = 'Carrot',         hunger = 20, thirst = 5,  health = 10,  stamina = 15,  bond = 3 },
    sugarcube            = { label = 'Sugar cube',     hunger = 30, thirst = 0,  health = 20,  stamina = 15,  bond = 3 },
    haysnack             = { label = 'Hay cube',       hunger = 50, thirst = 25, health = 30,  stamina = 75,  bond = 4 },
    horse_stimulant      = { label = 'Stimulant',      hunger = 50, thirst = 50, health = 0,   stamina = 100, bond = 0, core = true, gold = { stamina = 10 } },
    horsegold_stimulant = { label = 'Gold stimulant', hunger = 50, thirst = 50, health = 100, stamina = 100, bond = 0, core = true, gold = { stamina = 10, health = 10 } },
}

Config.Items = {
    brush = 'horse_brush',
    brushProp = 'p_brushhorse02x',   -- brush shown in hand while brushing
    reviver = 'horse_reviver',
    renameTag = 'horse_nametag',     -- on use: renames the active horse (consumes 1)
}

-- Dead horse: stays where it fell until revived with the item (Config.Items.reviver) or treated at a stable.
-- Using the item shows a white dot on the body of every dead horse nearby; click the one you want to
-- revive (ESC / right click cancels).
Config.Revive = {
    radius = 20.0,              -- distance at which dead horses show up to pick from
    bodyTime = 900,             -- seconds the body stays in place (then goes to the stable, dead) · 0 = forever
    duration = 4000,            -- ms of the revive animation
    health = 50,                -- health (0-100) the horse gets up with
    timeout = 30,               -- seconds to pick (then it cancels by itself)
    callNear = 10.0,            -- whistling with the horse dead: if the body is further than this, it appears next to you
    -- where the dot goes: the first of these bones the horse has (middle of the spine = centre of the body)
    bones = { 'skel_spine3', 'skel_spine2', 'skel_spine1', 'skel_spine_root', 'skel_pelvis' },
    offsetZ = 0.3,              -- if no bone exists: entity centre + this (metres)
}

-- Brush: the game's own interaction with the brush in hand (Config.Items.brushProp)
Config.Brush = {
    interaction = 'Interaction_Brush',        -- hash 554992710
    duration = 8000,                          -- ms until the brushing counts as done
}

---------------------------------------------------------------------------
-- Wild horses
--  Zones: when there are players in a zone, the server picks one of them as "host" and, every rollEvery
--  seconds, there is a chance% of horses spawning (up to maxHorses), with a cooldown between spawns. The horses
--  wander inside the zone and come back if they leave. Zone empty for cleanupAfter seconds = horses deleted.
--  Only zone horses can be tamed (NPC horses cannot).
--  Taming: mounting opens the mini-game (letters falling down the screen: press the letter or click it before it
--  reaches the bottom). If one gets away, the horse throws you off. Once tamed, ride it to one of the sale points.
---------------------------------------------------------------------------
Config.Wild = {
    enabled = true,
    -- mini-game
    duration = 20,              -- seconds without letting any letter get away
    spawnEvery = 900,           -- ms between letters at the start...
    spawnEveryEnd = 550,        -- ...and at the end (gets harder)
    fallTime = 3200,            -- ms a letter takes to reach the bottom of the screen
    letters = 'ASDQWEZXC',      -- letters that can fall
    retryDelay = 5,             -- seconds until you can try the same horse again
    knownOnly = false,          -- true: only horses with a shop coat / model (Config.Horses) can be tamed

    -- values: base = coat price (the zone's coat, or the shop coat with the same model)
    sellPercent = 20,           -- sell: you get % of the cash price...
    sellGoldPercent = 0,        -- ...and % of the gold price (coats sold for gold)
    keepPercent = 30,           -- keep: you pay % of the cash price...
    keepGoldPercent = 30,       -- ...and % of the gold price
    unknownValue = 150,         -- base value of a model that is not in the shop (can only be sold)
    sellCooldown = 0,           -- seconds between sales (per character)
    keepAge = { 5, 20 },        -- age (years) of a horse you keep (each zone can have its own: age = { min, max })
    webhook = { url = '', name = 'fks-stables', color = 11027200 }, -- Discord: sale / adoption logs ('' = off)

    -- sale points
    radius = 6.0,               -- distance to the point for the option to show
    key = 0xCEFD9220,           -- E   open the menu (sell / keep) at the point, mounted on the tamed horse
    blip = { sprite = -44909892, name = 'Wild horse trader' },

    -- zones
    zoneBlips = true,           -- show the zones on the map (each zone can turn its own off: blip.enabled = false)
    zoneBlipSprite = 600220762, -- zone icon on the map (each zone can have its own: blip.sprite)
    zoneBlipArea = true,        -- shows the zone area (radius circle) under the icon
    zoneBlipAreaIcon = false,   -- false: circle only, without the "ball" in the centre of the area blip
    zoneBlipAreaStyle = 693035517, -- area blip style (alternative: -1282792512)
    cleanupAfter = 120,         -- seconds with the zone empty until untamed horses are deleted
    containAt = 0.85,           -- a horse further than radius * this from the centre comes back in
    clearAmbient = true,        -- removes the game's own wild horses from the zones (those cannot be tamed by the script)
    --[[
        Each zone:
          label        name (entry notice and blip)
          coords       centre (vector3)
          radius       zone radius (enter / leave / containment)
          spawnRadius  radius where horses spawn (around the centre)
          wanderRadius radius where they wander (optional; = spawnRadius)
          maxHorses    max horses at the same time · perSpawn = max per spawn
          chance       % of spawning every rollEvery seconds · cooldown = seconds between spawns
          notify       notice when entering the zone
          age          { min, max } age when keeping a horse from this zone (optional; = keepAge)
          blip         { enabled, name, sprite (icon; = zoneBlipSprite), radius (blip radius; false = no area) }
          horses       { coat = 'coat id in Config.Horses', weight = n }  (look, price and rules of that coat)
                       { model = 'game model', weight = n }               (random game look)
    ]]
    -- EXAMPLES: replace the coordinates with your own zones
    zones = {
        {
            label = 'Heartlands Plains', coords = vector3(450.0, 500.0, 110.0),
            radius = 180.0, spawnRadius = 70.0, maxHorses = 4, perSpawn = 2,
            chance = 60, rollEvery = 30, cooldown = 300, notify = true,
            blip = { enabled = true, name = 'Wild horses', radius = 180.0 },
            horses = {
                { coat = 'A_C_Horse_Mustang_GoldenDun', weight = 2 },
                { coat = 'A_C_Horse_Nokota_BlueRoan', weight = 3 },
                { coat = 'A_C_Horse_Morgan_Bay', weight = 5 },
            },
        },
        {
            label = 'New Austin Desert', coords = vector3(-4800.0, -2900.0, 0.0),
            radius = 200.0, spawnRadius = 80.0, maxHorses = 3, perSpawn = 1,
            chance = 40, rollEvery = 45, cooldown = 600, notify = true, age = { 6, 18 },
            blip = { enabled = true, name = 'Wild horses', radius = 200.0 },
            horses = {
                { coat = 'A_C_Horse_Arabian_White', weight = 1 },
                { coat = 'A_C_Horse_Mustang_GoldenDun', weight = 4 },
            },
        },
    },

    -- sale points · stable = stable id (config/stables.lua) where the horse stays if you keep it
    points = {
        { label = 'Annesburg',  stable = 'blackwater', coords = vector4(2982.38, 1418.6, 44.81, 152.77) },
        { label = 'Rhodes',     stable = 'blackwater', coords = vector4(1447.16, -1384.36, 79.65, 255.59) },
        { label = 'Valentine',  stable = 'blackwater', coords = vector4(-391.6, 790.64, 115.98, 196.0) },
        { label = 'Blackwater', stable = 'blackwater', coords = vector4(-876.85, -1378.92, 43.59, 140.75) },
        { label = 'Tumbleweed', stable = 'blackwater', coords = vector4(-5521.6, -3017.44, -2.2, 144.72) },
    },
}

---------------------------------------------------------------------------
-- Training XP and bond
---------------------------------------------------------------------------
-- No levels: every horse only has a class and xp (0 up to the class max = fully trained).
-- Attributes and the health / stamina rings grow with the xp percentage.
Config.Level = {
    maxXpByTier = { [1] = 1000, [2] = 2000, [3] = 3000, [4] = 4000 },  -- xp of a fully trained horse, per class
    attributeMax = 450,         -- agility / speed / acceleration points with xp at the max
    xpPerMinuteRiding = 2,      -- riding
    xpPerMinuteSprint = 3,
    xpFeed = 2,
    xpBrush = 3,
}

Config.Bond = {
    levels = { 0, 50, 150, 300 },   -- bond xp for level 1..4
    perMinuteRiding = 0.5,
}

---------------------------------------------------------------------------
-- Age
---------------------------------------------------------------------------
Config.Aging = {
    enabled = true,
    hoursPerYear = 24,          -- real hours for the horse to age one year
    startAge = { 5, 5 },        -- age of a bought horse (min, max)
    oldAge = 25,                -- "old" from this age on
    maxAge = 30,                -- (reserved)
}

---------------------------------------------------------------------------
-- Wagons
---------------------------------------------------------------------------
Config.Wagon = {
    callFromStableOnly = true,  -- true: wagons are only taken out at the stable
    spawnDelay = 3,             -- seconds preparing the wagon
    returnDistance = 30.0,      -- distance to the stable to store it
    sendAway = true,            -- true: away from a stable, the same prompt (X) sends the wagon to the stable where it was stored
    saveHealth = true,
    brokenAt = 0,               -- durability (0-1000) at which the wagon breaks: the wheels come off and it stops
    repairItem = 'wagon_repair_kit', -- item to repair a worn (still whole) wagon away from the stable (nil = stable only)
    repairPrice = 40,
    -- Durability: 1000 = 100%. Wears with the kilometres driven and with crashes (the game's own damage).
    -- Shown next to the wagon name, in the prompts when you get close to it.
    durability = {
        wearPerKm = 15,                 -- points (out of 1000) worn per km driven · 0 = only crashes wear it
        breakWheels = { 0, 1, 2, 3 },   -- wheels that come off when it breaks (indexes; 2-wheel carts use 0 and 1)
    },
    -- Repair a broken wagon (durability 0), on the spot
    brokenRepair = {
        items = {
            { name = 'nails',  label = 'Nails',  count = 5 },
            { name = 'hammer', label = 'Hammer', count = 1, keep = true },  -- keep = not consumed
        },
        duration = 12000,               -- ms repairing
        health = 1000,                  -- durability it ends up with
    },
    disableDefaultGreen = true, -- avoids the default green tint
    restrictStorage = true,     -- only the owner and whoever they allow open the storage / manage the animals
    maxAccess = 10,             -- max players with access per wagon
}

---------------------------------------------------------------------------
-- Stats per breed (1-10) shown in the shop. Handling: 1 Heavy, 2 Standard, 3 Race, 4 Elite
---------------------------------------------------------------------------
Config.BreedStats = {
    default                  = { speed = 4, accel = 4, health = 5, stamina = 5, handling = 2 },
    ['Friesian']             = { speed = 5, accel = 5, health = 6, stamina = 6, handling = 2 },
    ['Akhal Teke']           = { speed = 7, accel = 6, health = 4, stamina = 6, handling = 3 },
    ['Anglo-Arabian']        = { speed = 6, accel = 7, health = 4, stamina = 5, handling = 4 },
    ['American Paint horse'] = { speed = 4, accel = 5, health = 4, stamina = 4, handling = 2 },
    ['Clydesdale']           = { speed = 3, accel = 2, health = 9, stamina = 8, handling = 1 },
    ['Vladimir Heavy Draft'] = { speed = 3, accel = 3, health = 9, stamina = 8, handling = 1 },
    ['Gypsy cob']            = { speed = 4, accel = 4, health = 6, stamina = 6, handling = 2 },
    ['American standard']    = { speed = 4, accel = 4, health = 5, stamina = 5, handling = 3 },
    ['Andalusian']           = { speed = 4, accel = 3, health = 6, stamina = 6, handling = 2 },
    ['Lusitano']            = { speed = 5, accel = 5, health = 6, stamina = 6, handling = 3 },
    ['Appaloosa']            = { speed = 4, accel = 5, health = 5, stamina = 5, handling = 2 },
    ['Arabian']              = { speed = 6, accel = 7, health = 4, stamina = 5, handling = 4 },
    ['Ardennes']             = { speed = 3, accel = 3, health = 8, stamina = 7, handling = 1 },
    ['Belgian']              = { speed = 3, accel = 2, health = 8, stamina = 8, handling = 1 },
    ['Dutch Warm Blood']     = { speed = 4, accel = 4, health = 5, stamina = 5, handling = 2 },
    ['Hungarian']            = { speed = 4, accel = 4, health = 5, stamina = 5, handling = 2 },
    ['Kentucky Saddle']      = { speed = 4, accel = 4, health = 4, stamina = 4, handling = 2 },
    ['Missouri Fox Trotter'] = { speed = 7, accel = 5, health = 6, stamina = 7, handling = 3 },
    ['Morgan']               = { speed = 3, accel = 4, health = 4, stamina = 4, handling = 2 },
    ['Mangy']                = { speed = 2, accel = 2, health = 3, stamina = 3, handling = 1 },
    ['Mustang']              = { speed = 5, accel = 5, health = 6, stamina = 6, handling = 2 },
    ['Nokota']               = { speed = 5, accel = 5, health = 5, stamina = 6, handling = 2 },
    ['Shire']                = { speed = 3, accel = 2, health = 9, stamina = 8, handling = 1 },
    ['Suffolk punch']        = { speed = 3, accel = 3, health = 8, stamina = 7, handling = 1 },
    ['Tennessee Walker']     = { speed = 4, accel = 4, health = 4, stamina = 5, handling = 3 },
    ['Thoroughbred']         = { speed = 6, accel = 6, health = 4, stamina = 5, handling = 3 },
    ['Turkoman']             = { speed = 6, accel = 6, health = 6, stamina = 6, handling = 3 },
    ['Criollo']              = { speed = 5, accel = 5, health = 5, stamina = 5, handling = 2 },
    ['Kladruber']            = { speed = 4, accel = 4, health = 6, stamina = 6, handling = 2 },
    ['Breton']               = { speed = 4, accel = 4, health = 7, stamina = 7, handling = 2 },
    ['Norfolkroadster']      = { speed = 5, accel = 5, health = 5, stamina = 6, handling = 3 },
    ['Historia']             = { speed = 6, accel = 6, health = 6, stamina = 6, handling = 3 },
    ['Tinker']               = { speed = 4, accel = 4, health = 6, stamina = 6, handling = 2 },
    ['Knabstrupper']         = { speed = 5, accel = 5, health = 5, stamina = 5, handling = 2 },
    ['Special Horses']    = { speed = 7, accel = 7, health = 7, stamina = 7, handling = 4 },
    ['Mustang Longstride']   = { speed = 6, accel = 5, health = 6, stamina = 6, handling = 2 },
    ['Vip - Appaloosa']      = { speed = 7, accel = 7, health = 7, stamina = 7, handling = 4 },
    ['Highland Cob']         = { speed = 4, accel = 4, health = 7, stamina = 7, handling = 2 },
}

-- Description per breed (optional). Shown in the shop.
Config.BreedInfo = {
    ['Arabian'] = 'One of the oldest breeds in the world. Light, fast and very agile, but with little stamina.',
    ['Missouri Fox Trotter'] = 'Smooth gait and great top speed. One of the fastest horses in the territory.',
    ['Shire'] = 'An English draft giant. Slow, but it can take anything — ideal for pulling wagons.',
    ['Turkoman'] = 'A war horse of the steppes: fast, tough and brave.',
    ['Mustang'] = 'Wild by nature, hardy and reliable on any terrain.',
    ['Thoroughbred'] = 'A racing thoroughbred. Strong start and good speed.',
    ['Friesian'] = 'Black, elegant and with a full mane. A horse with presence.',
}
