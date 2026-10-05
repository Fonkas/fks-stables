-- Trainer: job, training, courage / affinity, classes, special horses, breeding and foals.

---------------------------------------------------------------------------
-- Who is a trainer: the jobs below OR an admin (framework groups or the "fks-stables.admin" ace)
-- Only they get: training, breeding and changing the coat colour at the stable.
---------------------------------------------------------------------------
Config.Trainer = {
    jobs = { 'treinador' },
    adminGroups = { 'admin', 'superadmin' },  -- framework groups (vorp: getGroup · rsg: permissions)
    adminAce = 'fks-stables.admin',           -- or: add_ace group.admin fks-stables.admin allow
}

---------------------------------------------------------------------------
-- Training ("Training" option in the lead menu, holding the reins)
---------------------------------------------------------------------------
Config.Training = {
    key = 0xCEFD9220,               -- E   "Training" in the lead menu (holding the reins)

    -- 1. Obstacles: ride through every point, in order (ground markers / markers on top of the fences)
    obstacles = {
        startDistance = 60.0,       -- distance to the starting point to be able to start the training
        pointRadius = 2.5,          -- radius of each point
        heightTolerance = 3.5,      -- accepted height difference (jumps over the fences)
        marker = 0x94FDAE17,        -- ground marker (cylinder)
        color = { 240, 200, 90, 160 },     -- next point
        colorNext = { 255, 255, 255, 60 }, -- the one after
        courses = {
            {
                label = 'Valentine Paddock',
                xp = 100,               -- xp per lap
                minTime = 15,           -- minimum seconds (anti-cheat)
                timeLimit = 300,        -- seconds to finish (0 = no limit)
                start = vector3(-386.12, 765.68, 115.89),
                points = {
                    vector3(-387.22, 777.78, 115.77),
                    vector3(-387.9, 786.8, 115.86),
                    vector3(-387.21, 792.33, 117.24),   -- on top of the fence
                    vector3(-398.85, 791.34, 117.11),   -- on top of the fence
                    vector3(-398.63, 784.78, 115.86),
                    vector3(-398.37, 778.35, 115.79),
                    vector3(-398.2, 770.61, 115.85),
                    vector3(-392.71, 768.8, 115.81),
                },
                finish = vector3(-385.95, 765.95, 115.9),
            },
        },
    },

    -- 2. Lunging: the horse runs in circles around the trainer (on foot); automatic xp
    lunge = {
        xpPerMinute = 50,
        radius = 7.0,               -- circle radius
        speeds = {                  -- gaits (name = locale key train_speed_<name>)
            { name = 'walk', speed = 1.0 },
            { name = 'trot', speed = 2.0 },
            { name = 'gallop', speed = 3.0 },
        },
        startSpeed = 2,             -- index of the starting gait
        keys = {
            faster = 0x6319DB71,    -- arrow up
            slower = 0x05CA7C52,    -- arrow down
            jump = 0xD9D0E1C0,      -- Space
            stop = 0x156F7119,      -- Backspace
        },
    },

    -- 3. Load and strength: mounted at the point, start the training; drive the loaded wagon to the destination in time
    load = {
        key = 0xCEFD9220,           -- E   (mounted at the point)
        xp = 1000,
        timeLimit = 1800,           -- seconds (30 min)
        arriveRadius = 15.0,        -- distance to the destination to count as delivered
        pointRadius = 4.0,
        destBlip = 54149631,        -- destination icon on the map
        marker = 0x94FDAE17,
        color = { 240, 200, 90, 160 },
        points = {
            {
                label = 'Valentine Load Yard',
                coords = vector3(-393.77, 801.12, 115.93),
                wagon = { model = 'cart06', spawn = vector4(-401.56, 815.88, 115.53, 358.98), propset = nil },
            },
        },
        destinations = {            -- one is picked at random
            { label = 'Emerald Ranch', coords = vector3(1346.88, 336.67, 87.9) },
            { label = "Beecher's Hope", coords = vector3(-1614.76, -1407.23, 82.0) },
        },
    },
}

---------------------------------------------------------------------------
-- Courage and affinity (0 to 10): they rise over time
---------------------------------------------------------------------------
Config.Courage = {
    perMinuteRiding = 0.02,         -- mounted and moving (10 in ~8 h)
    perMinuteNear = 0.005,          -- near the owner, not mounted
    fearless = 10,                  -- from here on it is no longer afraid of gunshots and wild animals
}
Config.Affinity = {
    perMinuteRiding = 0.02,
    perMinuteNear = 0.01,
    perFeed = 0.05,                 -- when feeding / brushing / patting
}

---------------------------------------------------------------------------
-- Health and stamina per class (percentage of the game max): normal (0 xp) -> trained (max xp)
---------------------------------------------------------------------------
Config.ClassStats = {
    [1] = { base = 25, trained = 45 },
    [2] = { base = 35, trained = 60 },
    [3] = { base = 50, trained = 75 },
    [4] = { base = 60, trained = 100 },
}

---------------------------------------------------------------------------
-- Special horses (breeds below): come fully trained; can be blocked from breeding and from being given away
---------------------------------------------------------------------------
Config.Special = {
    breeds = { 'Special Horses' },
    trainedOnBuy = true,            -- xp, bond, courage and affinity at the max when bought
    canBreed = false,
    canGive = false,                -- "Transfer" to another player
}

---------------------------------------------------------------------------
-- Give the horse to another player ("Transfer", when looking at your horse)
---------------------------------------------------------------------------
Config.Give = {
    key = 0x9959A6F0,               -- C   (hold)
    maxDistance = 10.0,             -- the other player has to be close
}

---------------------------------------------------------------------------
-- Breeding (trainer only, at stables with services.breeding and breed = { camera, left, right })
---------------------------------------------------------------------------
Config.Breeding = {
    time = 120,                     -- seconds until the foal is born
    cooldown = 43200,               -- seconds (12 h) after the foal is born until the parents can breed again
    minAge = 5,                     -- minimum age of the parents
    price = 0,                      -- cost (cash)
    foalName = 'Foal',              -- foal name (rename it at the stable)
}

Config.Foal = {
    adultAge = 5,                   -- adult age (full size)
    minScale = 0.5,                 -- size of a newborn (1.0 = adult)
    rideAge = 5,                    -- minimum age to ride
}
