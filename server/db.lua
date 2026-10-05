-- Tables are created automatically on start (no SQL import needed).

DB = {}

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `fks_horses` (
            `id`         INT(11) NOT NULL AUTO_INCREMENT,
            `citizenid`  VARCHAR(50) NOT NULL,
            `name`       VARCHAR(40) NOT NULL,
            `coat_id`    VARCHAR(80) NOT NULL,
            `gender`     ENUM('male','female') NOT NULL DEFAULT 'male',
            `stable`     VARCHAR(50) NOT NULL,
            `active`     TINYINT(1) NOT NULL DEFAULT 0,
            `spawned`    TINYINT(1) NOT NULL DEFAULT 0,
            `components` LONGTEXT NULL,
            `coat`       LONGTEXT NULL,
            `xp`         INT(11) NOT NULL DEFAULT 0,
            `bond`       INT(11) NOT NULL DEFAULT 0,
            `health`     TINYINT(3) UNSIGNED NOT NULL DEFAULT 100,
            `stamina`    TINYINT(3) UNSIGNED NOT NULL DEFAULT 100,
            `hunger`     FLOAT NOT NULL DEFAULT 100,
            `thirst`     FLOAT NOT NULL DEFAULT 100,
            `dirt`       FLOAT NOT NULL DEFAULT 0,
            `hoof`       FLOAT NOT NULL DEFAULT 100,
            `dead`       TINYINT(1) NOT NULL DEFAULT 0,
            `born`       INT(11) NOT NULL,
            `position`   VARCHAR(120) NULL,
            `meta`       LONGTEXT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_owner` (`citizenid`),
            KEY `idx_active` (`citizenid`, `active`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `fks_wagons` (
            `id`         INT(11) NOT NULL AUTO_INCREMENT,
            `citizenid`  VARCHAR(50) NOT NULL,
            `name`       VARCHAR(40) NOT NULL,
            `model`      VARCHAR(60) NOT NULL,
            `stable`     VARCHAR(50) NOT NULL,
            `active`     TINYINT(1) NOT NULL DEFAULT 0,
            `spawned`    TINYINT(1) NOT NULL DEFAULT 0,
            `custom`     LONGTEXT NULL,
            `health`     SMALLINT(5) NOT NULL DEFAULT 1000,
            `position`   VARCHAR(120) NULL,
            `meta`       LONGTEXT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_owner` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    -- migrations for tables created by previous versions
    local function AddColumn(tbl, col, def)
        local exists = MySQL.scalar.await(
            'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?', { tbl, col })
        if (exists or 0) == 0 then
            MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tbl, col, def))
            print(('[fks-stables] column %s.%s added'):format(tbl, col))
        end
    end
    AddColumn('fks_horses', 'hoof', 'FLOAT NOT NULL DEFAULT 100 AFTER `dirt`')
    AddColumn('fks_horses', 'courage', 'FLOAT NOT NULL DEFAULT 0 AFTER `bond`')
    AddColumn('fks_horses', 'affinity', 'FLOAT NOT NULL DEFAULT 0 AFTER `courage`')

    -- breedings in progress (the foal is created when ready_at is reached, even with the owner offline)
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `fks_breeding` (
            `id`        INT(11) NOT NULL AUTO_INCREMENT,
            `citizenid` VARCHAR(50) NOT NULL,
            `mother`    INT(11) NOT NULL,
            `father`    INT(11) NOT NULL,
            `stable`    VARCHAR(50) NOT NULL,
            `coat_id`   VARCHAR(80) NOT NULL,
            `gender`    ENUM('male','female') NOT NULL DEFAULT 'male',
            `ready_at`  INT(11) NOT NULL,
            `done`      TINYINT(1) NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_owner` (`citizenid`),
            KEY `idx_ready` (`done`, `ready_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    DB.ready = true
end)

-- Breeding ----------------------------------------------------------------------------
function DB.Breedings(cid)
    return MySQL.query.await('SELECT * FROM fks_breeding WHERE citizenid = ? AND done = 0 ORDER BY ready_at', { cid }) or {}
end

function DB.InsertBreeding(b)
    return MySQL.insert.await('INSERT INTO fks_breeding (citizenid, mother, father, stable, coat_id, gender, ready_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { b.citizenid, b.mother, b.father, b.stable, b.coat_id, b.gender, b.ready_at })
end

function DB.ReadyBreedings(now)
    return MySQL.query.await('SELECT * FROM fks_breeding WHERE done = 0 AND ready_at <= ?', { now }) or {}
end

function DB.FinishBreeding(id)
    return MySQL.update.await('UPDATE fks_breeding SET done = 1 WHERE id = ? AND done = 0', { id })
end

-- Horses ---------------------------------------------------------------------------------
function DB.Horses(cid)
    return MySQL.query.await('SELECT * FROM fks_horses WHERE citizenid = ? ORDER BY id', { cid }) or {}
end

function DB.Horse(id)
    return MySQL.single.await('SELECT * FROM fks_horses WHERE id = ?', { id })
end

function DB.ActiveHorse(cid)
    return MySQL.single.await('SELECT * FROM fks_horses WHERE citizenid = ? AND active = 1 LIMIT 1', { cid })
end

function DB.CountHorses(cid)
    return MySQL.scalar.await('SELECT COUNT(*) FROM fks_horses WHERE citizenid = ?', { cid }) or 0
end

function DB.InsertHorse(h)
    return MySQL.insert.await(
        'INSERT INTO fks_horses (citizenid, name, coat_id, gender, stable, born, components, coat, xp, bond, courage, affinity) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { h.citizenid, h.name, h.coat_id, h.gender, h.stable, h.born, '{}', nil, h.xp or 0, h.bond or 0, h.courage or 0, h.affinity or 0 })
end

function DB.SetActiveHorse(cid, id)
    MySQL.update.await('UPDATE fks_horses SET active = (id = ?) WHERE citizenid = ?', { id, cid })
end

function DB.UpdateHorse(id, fields)
    local sets, vals = {}, {}
    for k, v in pairs(fields) do
        sets[#sets + 1] = ('`%s` = ?'):format(k)
        vals[#vals + 1] = v
    end
    vals[#vals + 1] = id
    return MySQL.update.await(('UPDATE fks_horses SET %s WHERE id = ?'):format(table.concat(sets, ', ')), vals)
end

function DB.DeleteHorse(id)
    return MySQL.update.await('DELETE FROM fks_horses WHERE id = ?', { id })
end

-- Wagons --------------------------------------------------------------------------------
function DB.Wagons(cid)
    return MySQL.query.await('SELECT * FROM fks_wagons WHERE citizenid = ? ORDER BY id', { cid }) or {}
end

function DB.Wagon(id)
    return MySQL.single.await('SELECT * FROM fks_wagons WHERE id = ?', { id })
end

function DB.ActiveWagon(cid)
    return MySQL.single.await('SELECT * FROM fks_wagons WHERE citizenid = ? AND active = 1 LIMIT 1', { cid })
end

function DB.CountWagons(cid)
    return MySQL.scalar.await('SELECT COUNT(*) FROM fks_wagons WHERE citizenid = ?', { cid }) or 0
end

function DB.InsertWagon(w)
    return MySQL.insert.await(
        'INSERT INTO fks_wagons (citizenid, name, model, stable, custom) VALUES (?, ?, ?, ?, ?)',
        { w.citizenid, w.name, w.model, w.stable, '{}' })
end

function DB.SetActiveWagon(cid, id)
    MySQL.update.await('UPDATE fks_wagons SET active = (id = ?) WHERE citizenid = ?', { id, cid })
end

function DB.UpdateWagon(id, fields)
    local sets, vals = {}, {}
    for k, v in pairs(fields) do
        sets[#sets + 1] = ('`%s` = ?'):format(k)
        vals[#vals + 1] = v
    end
    vals[#vals + 1] = id
    return MySQL.update.await(('UPDATE fks_wagons SET %s WHERE id = ?'):format(table.concat(sets, ', ')), vals)
end

function DB.DeleteWagon(id)
    return MySQL.update.await('DELETE FROM fks_wagons WHERE id = ?', { id })
end
