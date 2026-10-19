-- Stables: Blackwater, Valentine, Rhodes, Saint Denis, Strawberry and Tumbleweed — copy a block to add your own.
-- Coordinates are { x, y, z, heading }. Tip: stand where you want a point and use your coords command
-- (or /fks_coords if you add one) to copy the position.

Config.Stables = {
    {
        id = 'blackwater',                  -- unique id (saved on horses/wagons; used by Config.KeepAtStable,
                                            --   Config.Wild.points[].stable, transfers, breeding...)
        label = 'Blackwater Stable',        -- name shown on the map, in the menu and in notifications
        blip = true,                        -- show a map blip (icon = Config.Blip.sprite)

        -- stable hand NPC: model + position. Talking to him (E) opens the stable menu.
        npc = { model = 'u_m_m_bwmstablehand_01', coords = { -875.67, -1367.19, 42.55, -84.0 } },

        -- showroom camera: where the camera sits while the menu is open (heading = the direction it faces)
        camera = { -874.45, -1366.45, 45.25, -90.01 },

        -- where the horse on display stands (shop / my horses) — the camera looks at this point
        preview = { -866.89, -1366.37, 42.3, 0.0 },
        -- wagonPreview = { x, y, z, heading },  -- optional: own spot for wagons (they are bigger); default = preview

        -- where a horse / wagon taken out of this stable appears
        spawn = { -890.85, -1365.68, 42.49, 355.55 },

        -- breeding (trainer only; needs services.breeding = true)
        breed = {
            camera = { -865.64, -1365.76, 46.21, -0.63 },  -- camera position while picking the pair
            left = { -866.39, -1361.78, 42.46, -177.0 },   -- where the female stands
            right = { -864.4, -1362.0, 42.46, -177.0 },    -- where the male stands (the foal appears between them)
        },

        -- hours = { 6, 22 },               -- optional: { opens, closes } in game hours (nil = always open)
        -- jobs = { 'police' },             -- optional: only these jobs can use this stable (nil = everyone)

        -- what this stable offers (false / missing = not available here)
        services = {
            buyHorses = true,               -- horse shop
            customize = true,               -- tack (saddles, blankets, saddlebags...)
            coloring = true,                -- change the coat colour (trainers only, see Config.Trainer)
            transfer = true,                -- send horses / wagons to another stable
            breeding = true,                -- breeding (trainers only)
            buyWagons = true,               -- wagon shop
            customizeWagons = true,         -- wagon paint, extras, load, lanterns
        },
    },
    {
        id = 'valentine',
        label = 'Valentine Stables',
        blip = true,
        npc = { model = 'u_m_m_bwmstablehand_01', coords = { -366.26, 790.76, 115.2, 187.53 } },
        camera = { -366.0, 788.0, 117.0, 277.88 },
        preview = { -368.52, 786.96, 115.16, 277.88 },
        spawn = { -353.46, 797.47, 116.17, 181.14 },
        breed = {
            camera = { -368.52, 786.96, 118.16, 277.88 },
            left = { -368.52, 788.96, 115.16, 97.88 },
            right = { -366.52, 788.96, 115.16, 97.88 },
        },
        services = { buyHorses = true, customize = true, transfer = true, buyWagons = false, customizeWagons = false, breeding = false },
    },
    {
        id = 'rhodes',
        label = 'Rhodes Stables',
        blip = true,
        npc = { model = 'u_m_m_bwmstablehand_01', coords = { 1211.71, -191.07, 100.47, 118.85 } },
        camera = { 1211.7, -192.6, 101.4, 10.14 },
        preview = { 1209.35, -192.60, 100.38, 10.14 },
        spawn = { 1206.04, -173.15, 101.03, 351.21 },
        breed = {
            camera = { 1209.35, -192.60, 103.38, 10.14 },
            left = { 1207.35, -190.60, 100.38, 190.14 },
            right = { 1211.35, -190.60, 100.38, 190.14 },
        },
        services = { buyHorses = true, customize = true, transfer = true, buyWagons = false, customizeWagons = false, breeding = false },
    },
    {
        id = 'saintdenis',
        label = 'Saint Denis Stables',
        blip = true,
        npc = { model = 'u_m_m_bwmstablehand_01', coords = { 2506.05, -1459.82, 45.32, 96.34 } },
        camera = { 2504.0, -1456.0, 47.0, 179.25 },
        preview = { 2503.22, -1454.04, 45.31, 179.25 },
        spawn = { 2506.05, -1459.82, 46.32, 96.34 },
        breed = {
            camera = { 2503.22, -1454.04, 48.31, 179.25 },
            left = { 2501.22, -1456.04, 45.31, 359.25 },
            right = { 2505.22, -1456.04, 45.31, 359.25 },
        },
        services = { buyHorses = true, customize = true, transfer = true, buyWagons = true, customizeWagons = true, breeding = true },
    },
    {
        id = 'strawberry',
        label = 'Strawberry Stables',
        blip = true,
        npc = { model = 'u_m_m_bwmstablehand_01', coords = { -1819.25, -564.85, 156.06, 347.82 } },
        camera = { -1818.0, -563.0, 156.0, 257.78 },
        preview = { -1819.83, -561.63, 155.06, 257.78 },
        spawn = { -1819.83, -561.63, 155.06, 257.78 },
        breed = {
            camera = { -1819.83, -561.63, 158.06, 257.78 },
            left = { -1819.83, -559.63, 155.06, 77.78 },
            right = { -1817.83, -559.63, 155.06, 77.78 },
        },
        services = { buyHorses = true, customize = true, transfer = true, buyWagons = true, customizeWagons = true, breeding = true },
    },
    {
        id = 'tumbleweed',
        label = 'Tumbleweed Stables',
        blip = true,
        npc = { model = 'u_m_m_bwmstablehand_01', coords = { -5515.22, -3040.04, -3.3, 173.00 } },
        camera = { -5516.31, -3043.94, -2.39, 108.21 },
        preview = { -5520.46, -3044.38, -3.1, 100.52 },
        spawn = { -5497.81, -3058.42, -3.09, 198.97 },
        breed = {
            camera = { -5515.22, -3040.04, 0.61, 173.00 },
            left = { -5517.22, -3040.04, -2.39, 353.00 },
            right = { -5513.22, -3040.04, -2.39, 353.00 },
        },
        services = { buyHorses = true, customize = true, transfer = true, buyWagons = false, customizeWagons = false, breeding = false },
    },
}
