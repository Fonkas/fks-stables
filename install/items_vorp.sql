-- fks-stables - items for VORP (vorp_inventory)
-- Import this into your database, then restart the server.
-- Item names must match config/main.lua (Config.Feed, Config.Items, Config.Care.hoof.item,
-- Config.Wagon.repairItem, Config.Wagon.brokenRepair). Images go in vorp_inventory/html/img/items/

INSERT IGNORE INTO `items` (`item`, `label`, `limit`, `can_remove`, `type`, `usable`, `desc`) VALUES
    ('horse_apple',          'Apple',                20, 1, 'item_standard', 1, 'A treat for your horse.'),
    ('horse_carrot',         'Carrot',               20, 1, 'item_standard', 1, 'A treat for your horse.'),
    ('sugarcube',            'Sugar cube',           20, 1, 'item_standard', 1, 'A sweet treat for your horse.'),
    ('haysnack',             'Hay cube',             20, 1, 'item_standard', 1, 'Compressed hay for your horse.'),
    ('horse_stimulant',      'Horse stimulant',      10, 1, 'item_standard', 1, 'Refills your horse''s stamina.'),
    ('horse_gold_stimulant', 'Gold horse stimulant', 10, 1, 'item_standard', 1, 'Refills your horse''s health and stamina.'),
    ('horse_brush',          'Horse brush',           1, 1, 'item_standard', 1, 'Keeps your horse clean.'),
    ('hoof_pick',            'Hoof pick',             1, 1, 'item_standard', 0, 'Cleans your horse''s hooves.'),
    ('horse_reviver',        'Horse reviver',         5, 1, 'item_standard', 1, 'Revives a dead horse.'),
    ('horse_nametag',        'Horse name tag',        5, 1, 'item_standard', 1, 'Renames your active horse.'),
    ('wagon_repair_kit',     'Wagon repair kit',      5, 1, 'item_standard', 1, 'Repairs a worn wagon.'),
    ('nails',                'Nails',                50, 1, 'item_standard', 0, 'Used to repair a broken wagon.'),
    ('hammer',               'Hammer',                1, 1, 'item_standard', 0, 'Used to repair a broken wagon.');
