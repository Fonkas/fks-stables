-- Stables. Only one example is included — copy the block below to add your own stables.
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
}
