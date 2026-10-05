local Spawned = {}          -- [src] = { horse = netId, wagon = netId }
local HorseOut = {}         -- [src] = horseId the player has out (to validate states)
local WagonOut = {}         -- [src] = wagonId
local LastState = {}        -- [src] = GetGameTimer() of the last state save (anti-spam)
local Reviving = {}         -- [horseId] = true while someone is reviving it
local RevivePending = {}    -- [horseId] = true: item consumed, waiting for the owner to confirm the horse stood up

-- Sets of valid hashes per category (component validation)
local ValidComp = {}
for cat, list in pairs(Config.HorseComponents) do
    ValidComp[cat] = {}
    for _, h in ipairs(list) do ValidComp[cat][h] = true end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function GetP(src) return Bridge.GetPlayer(src) end
-- TINYINT(1) columns: oxmysql returns true/false, other drivers 1/0
local function On(v) return v == true or v == 1 end
local function Cid(P) return P.cid end
local function JobOf(P) return P.job end

local function Notify(src, msg, kind)
    TriggerClientEvent('ox_lib:notify', src, { title = _L('stable'), description = msg, type = kind or 'inform' })
end

local function Limits(P)
    return Config.Limits[JobOf(P)] or Config.Limits.default
end

local function InList(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

local function HasAccess(src, P, jobs, groups)
    if jobs and not InList(jobs, JobOf(P)) then return false end
    if groups then
        for _, g in ipairs(groups) do
            if P.hasGroup(g) then return true end
        end
        return false
    end
    return true
end

-- trainer: job in Config.Trainer.jobs OR admin (framework group / ace)
local function IsTrainer(src, P)
    local T = Config.Trainer or {}
    P = P or GetP(src)
    if not P then return false end
    if T.jobs and InList(T.jobs, JobOf(P)) then return true end
    for _, g in ipairs(T.adminGroups or {}) do
        local ok, has = pcall(P.hasGroup, g)
        if ok and has then return true end
    end
    return T.adminAce ~= nil and IsPlayerAceAllowed(src, T.adminAce)
end

local function StableAccess(src, P, stableId)
    local s = FKS.StableById[stableId]
    if not s then return nil end
    if s.jobs and not InList(s.jobs, JobOf(P)) then return nil end
    return s
end

local function Charge(P, currency, amount, reason)
    amount = math.floor(amount or 0)
    if amount <= 0 then return true end
    local mt = currency == 'gold' and 'gold' or 'cash'
    if P.money(mt) < amount then
        return false, mt == 'gold' and _L('not_enough_gold') or _L('not_enough_cash')
    end
    return P.remove(mt, amount, reason)
end

local function CleanName(name)
    if type(name) ~= 'string' then return nil end
    name = name:gsub('[<>"\'`\\]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if #name < 2 or #name > 24 then return nil end
    return name
end

local function Decode(s, fallback)
    if not s or s == '' then return fallback end
    local ok, v = pcall(json.decode, s)
    return ok and v or fallback
end

local function StashId(kind, id) return ('fks_%s_%s'):format(kind, id) end

-- (avoids Lua's "a and b or c": if b were nil it fell through to the horse)
local function Row(kind, id)
    if kind == 'wagon' then return DB.Wagon(id) end
    return DB.Horse(id)
end

---------------------------------------------------------------------------
-- Formatting for the client / NUI
---------------------------------------------------------------------------
local function HorsePrices(coat, age)
    local base, cur = coat.cash, 'cash'
    if base <= 0 then base, cur = coat.gold, 'gold' end
    local sell = math.floor(base * (coat.resale or 0) / 100)
    if age and age >= Config.Aging.oldAge and not Config.Sell.allowOld then sell = 0 end
    local heal = math.max(Config.Prices.healMin, math.floor((coat.cash > 0 and coat.cash or Config.Prices.healMin) * Config.Prices.healPercent / 100))
    return { amount = sell, currency = cur }, heal
end

local function FormatHorse(r)
    local coat, breed = FKS.GetCoat(r.coat_id)
    if not coat then return nil end
    local age = FKS.Age(r.born)
    local xpMax = FKS.MaxXp(coat.tier)
    local sell, heal = HorsePrices(coat, age)
    local custom = Decode(r.coat, {})
    local s = FKS.StableById[r.stable]
    local meta = Decode(r.meta, {})
    local now = os.time()
    local special = FKS.IsSpecialBreed(breed)
    local F = Config.Foal or {}
    local adult = F.adultAge or 5
    -- foal = only horses born from breeding (meta.foal), until adult age.
    -- Bought / tamed / wild horses are already adults, whatever their age.
    local bred = meta.foal == true
    local foal = bred and age ~= nil and age < adult
    local breedingUntil = (meta.breedingUntil or 0) > now and meta.breedingUntil or nil
    local breedWait = math.max(0, (meta.bredAt or 0) + ((Config.Breeding or {}).cooldown or 0) - now)
    return {
        courage = math.floor((r.courage or 0) * 10) / 10, affinity = math.floor((r.affinity or 0) * 10) / 10,
        special = special, foal = foal,
        bred = bred,
        scale = foal and FKS.Clamp((F.minScale or 0.5) + (1 - (F.minScale or 0.5)) * (age / adult), F.minScale or 0.5, 1.0) or 1.0,
        rideable = not bred or age == nil or age >= (F.rideAge or adult),
        agePerSec = Config.Aging.enabled and 1 / (Config.Aging.hoursPerYear * 3600) or 0,
        breedingUntil = breedingUntil, breedWait = breedWait,
        canBreed = coat.canBreed ~= false and not (special and Config.Special and not Config.Special.canBreed)
            and not foal and (age == nil or age >= ((Config.Breeding or {}).minAge or 5)) and not On(r.dead)
            and not breedingUntil and breedWait == 0,
        canGive = not (special and Config.Special and not Config.Special.canGive),
        id = r.id, name = r.name, breed = breed, coatId = r.coat_id, coatLabel = coat.label,
        model = coat.model, outfit = coat.outfit, tier = coat.tier, storage = coat.storage, pelts = coat.pelts,
        gender = r.gender, xp = math.min(r.xp, xpMax), xpMax = xpMax,
        bond = FKS.BondLevel(r.bond), bondXp = r.bond,
        age = age and math.floor(age * 10) / 10, old = age and age >= Config.Aging.oldAge or false,
        health = r.health, stamina = r.stamina, hunger = r.hunger, thirst = r.thirst, dirt = r.dirt, hoof = r.hoof or 100,
        dead = On(r.dead), active = On(r.active), spawned = On(r.spawned),
        stable = r.stable, stableLabel = s and s.label or r.stable,
        components = Decode(r.components, {}),
        coat = custom.coat or coat.coat, maneTail = custom.maneTail or coat.maneTail,
        fixedStats = coat.fixedStats, stats = FKS.BreedStats(breed),
        position = Decode(r.position, nil),
        sell = sell, heal = heal, rename = Config.Prices.rename,
    }
end

local function FormatWagon(r)
    local w, category = FKS.GetWagon(r.model)
    if not w then return nil end
    local s = FKS.StableById[r.stable]
    local base, cur = w.cash, 'cash'
    if base <= 0 then base, cur = w.gold, 'gold' end
    return {
        id = r.id, name = r.name, model = r.model, label = w.label, category = category,
        storage = w.storage, animals = w.animals, work = w.work, big = w.big,
        health = r.health, broken = r.health <= Config.Wagon.brokenAt, active = On(r.active), spawned = On(r.spawned),
        stable = r.stable, stableLabel = s and s.label or r.stable,
        custom = Decode(r.custom, {}), position = Decode(r.position, nil),
        sell = { amount = math.floor(base * (w.resale or 0) / 100), currency = cur },
        repair = Config.Wagon.repairPrice, rename = Config.Prices.rename,
    }
end

local function BuildShop(src, P)
    local horses = {}
    for _, b in ipairs(Config.Horses) do
        local coats = {}
        for _, c in ipairs(b.coats) do
            if c.enabled and (c.cash > 0 or c.gold > 0) and HasAccess(src, P, c.jobs, c.groups) then
                coats[#coats + 1] = {
                    id = c.id, model = c.model, label = c.label, cash = c.cash, gold = c.gold, tier = c.tier,
                    storage = c.storage, pelts = c.pelts, canBreed = c.canBreed, outfit = c.outfit,
                    coat = c.coat, maneTail = c.maneTail, fixedStats = c.fixedStats,
                }
            end
        end
        if #coats > 0 then
            horses[#horses + 1] = { breed = b.breed, info = Config.BreedInfo[b.breed], stats = FKS.BreedStats(b.breed), coats = coats }
        end
    end

    local wagons = {}
    for _, cat in ipairs(Config.Wagons) do
        local list = {}
        for _, w in ipairs(cat.wagons) do
            if w.enabled and (w.cash > 0 or w.gold > 0) and HasAccess(src, P, w.jobs, w.groups) then
                list[#list + 1] = {
                    model = w.model, label = w.label, cash = w.cash, gold = w.gold, storage = w.storage,
                    animals = w.animals, work = w.work, big = w.big, description = w.description,
                }
            end
        end
        if #list > 0 then
            wagons[#wagons + 1] = { category = cat.category, icon = cat.icon, wagons = list }
        end
    end
    return horses, wagons
end

---------------------------------------------------------------------------
-- Read
---------------------------------------------------------------------------
lib.callback.register('fks-stables:getData', function(src, stableId, withShop)
    local P = GetP(src); if not P then return nil end
    local stable = StableAccess(src, P, stableId)
    if not stable then return { denied = true } end
    local cid = Cid(P)

    local horses, wagons = {}, {}
    for _, r in ipairs(DB.Horses(cid)) do
        local h = FormatHorse(r)
        if h then
            h.here = not Config.KeepAtStable or r.stable == stableId
            horses[#horses + 1] = h
        end
    end
    for _, r in ipairs(DB.Wagons(cid)) do
        local w = FormatWagon(r)
        if w then
            w.here = not Config.KeepAtStable or r.stable == stableId
            wagons[#wagons + 1] = w
        end
    end

    local data = {
        horses = horses, wagons = wagons, limits = Limits(P),
        money = { cash = P.money('cash'), gold = P.money('gold') },
        isTrainer = IsTrainer(src, P),
        canColor = IsTrainer(src, P),
        breeding = (function()
            local list, now = {}, os.time()
            for _, b in ipairs(DB.Breedings(cid)) do
                local st = FKS.StableById[b.stable]
                list[#list + 1] = { id = b.id, mother = b.mother, father = b.father, stable = b.stable,
                    stableLabel = st and st.label or b.stable, readyIn = math.max(0, b.ready_at - now) }
            end
            return list
        end)(),
        breedCfg = { time = (Config.Breeding or {}).time or 0, price = (Config.Breeding or {}).price or 0 },
    }
    if withShop then data.shopHorses, data.shopWagons = BuildShop(src, P) end
    return data
end)

lib.callback.register('fks-stables:getActive', function(src, kind)
    local P = GetP(src); if not P then return nil end
    local row
    if kind == 'wagon' then row = DB.ActiveWagon(Cid(P)) else row = DB.ActiveHorse(Cid(P)) end
    if not row then return nil, kind == 'wagon' and 'no_active_wagon' or 'no_active_horse' end
    if kind == 'wagon' then return FormatWagon(row) end
    return FormatHorse(row)
end)

---------------------------------------------------------------------------
-- Purchases
---------------------------------------------------------------------------
lib.callback.register('fks-stables:buyHorse', function(src, stableId, coatId, currency, gender, name)
    local P = GetP(src); if not P then return false end
    local stable = StableAccess(src, P, stableId)
    if not stable or not stable.services.buyHorses then return false, _L('no_access') end
    local coat = FKS.GetCoat(coatId)
    if not coat or not coat.enabled or not HasAccess(src, P, coat.jobs, coat.groups) then return false, _L('no_permission') end
    local price = currency == 'gold' and coat.gold or coat.cash
    if price <= 0 then return false, _L('no_permission') end
    name = CleanName(name); if not name then return false, _L('invalid_name') end
    gender = gender == 'female' and 'female' or 'male'

    local cid = Cid(P)
    local lim = Limits(P).horses
    if DB.CountHorses(cid) >= lim then return false, _L('limit_horses', lim) end

    local ok, err = Charge(P, currency, price, 'fks-stables:buy-horse')
    if not ok then return false, err end

    local a = Config.Aging.startAge
    local born = os.time() - math.floor(math.random(a[1] * 100, a[2] * 100) / 100 * Config.Aging.hoursPerYear * 3600)
    local h = { citizenid = cid, name = name, coat_id = coatId, gender = gender, stable = stableId, born = born }
    local _, breed = FKS.GetCoat(coatId)
    if FKS.IsSpecialBreed(breed) and Config.Special and Config.Special.trainedOnBuy then
        local coat = FKS.GetCoat(coatId)
        h.xp = FKS.MaxXp(coat and coat.tier)
        h.bond = Config.Bond.levels[#Config.Bond.levels]
        h.courage, h.affinity = 10, 10
    end
    local id = DB.InsertHorse(h)
    if not DB.ActiveHorse(cid) then DB.SetActiveHorse(cid, id) end
    return true, _L('bought_horse', name), id
end)

lib.callback.register('fks-stables:buyWagon', function(src, stableId, model, currency, name)
    local P = GetP(src); if not P then return false end
    local stable = StableAccess(src, P, stableId)
    if not stable or not stable.services.buyWagons then return false, _L('no_access') end
    local w = FKS.GetWagon(model)
    if not w or not w.enabled or not HasAccess(src, P, w.jobs, w.groups) then return false, _L('no_permission') end
    local price = currency == 'gold' and w.gold or w.cash
    if price <= 0 then return false, _L('no_permission') end
    name = CleanName(name); if not name then return false, _L('invalid_name') end

    local cid = Cid(P)
    local lim = Limits(P).wagons
    if DB.CountWagons(cid) >= lim then return false, _L('limit_wagons', lim) end

    local ok, err = Charge(P, currency, price, 'fks-stables:buy-wagon')
    if not ok then return false, err end

    local id = DB.InsertWagon({ citizenid = cid, name = name, model = w.model, stable = stableId })
    if not DB.ActiveWagon(cid) then DB.SetActiveWagon(cid, id) end
    return true, _L('bought_wagon', name), id
end)

---------------------------------------------------------------------------
-- Management
---------------------------------------------------------------------------
local function Owned(P, kind, id)
    local row = Row(kind, id)
    if not row or row.citizenid ~= Cid(P) then return nil end
    return row
end

-- Take out of the stable (becomes active and "out")
lib.callback.register('fks-stables:takeOut', function(src, kind, id, stableId)
    local P = GetP(src); if not P then return false end
    local row = Owned(P, kind, id); if not row then return false, _L('not_owner') end
    if not StableAccess(src, P, stableId) then return false, _L('no_access') end
    if Config.KeepAtStable and row.stable ~= stableId then
        local s = FKS.StableById[row.stable]
        return false, _L('horse_wrong_stable', s and s.label or row.stable)
    end
    if kind == 'wagon' then
        if row.health <= Config.Wagon.brokenAt then return false, _L('wagon_broken') end
        DB.SetActiveWagon(Cid(P), id)
        DB.UpdateWagon(id, { spawned = 1, stable = stableId })
        return true, FormatWagon(DB.Wagon(id))
    end
    if On(row.dead) then return false, _L('horse_dead') end
    if (Decode(row.meta, {}).breedingUntil or 0) > os.time() then return false, _L('horse_breeding') end
    DB.SetActiveHorse(Cid(P), id)
    DB.UpdateHorse(id, { spawned = 1, stable = stableId })
    return true, FormatHorse(DB.Horse(id))
end)

lib.callback.register('fks-stables:sell', function(src, kind, id)
    local P = GetP(src); if not P then return false end
    local row = Owned(P, kind, id); if not row then return false, _L('not_owner') end
    local data
    if kind == 'wagon' then data = FormatWagon(row) else data = FormatHorse(row) end
    if not data then return false end
    if kind == 'wagon' then DB.DeleteWagon(id) else DB.DeleteHorse(id) end
    Bridge.DeleteStash(StashId(kind, id))
    if data.sell.amount > 0 then P.add(data.sell.currency, data.sell.amount, 'fks-stables:sell') end
    return true, _L('sold', row.name, data.sell.amount)
end)

-- Heal at the stable: a dead horse is healed and stored at the stable where it was paid
lib.callback.register('fks-stables:heal', function(src, id, stableId)
    local P = GetP(src); if not P then return false end
    local row = Owned(P, 'horse', id); if not row then return false, _L('not_owner') end
    local h = FormatHorse(row)
    local ok, err = Charge(P, 'cash', h.heal, 'fks-stables:heal')
    if not ok then return false, err end
    local fields = { dead = 0, health = 100, stamina = 100 }
    if On(row.dead) then
        fields.spawned, fields.position = 0, 'null'
        if stableId and StableAccess(src, P, stableId) then fields.stable = stableId end
    end
    DB.UpdateHorse(id, fields)
    return true, _L('healed', row.name)
end)

lib.callback.register('fks-stables:repair', function(src, id)
    local P = GetP(src); if not P then return false end
    local row = Owned(P, 'wagon', id); if not row then return false, _L('not_owner') end
    local ok, err = Charge(P, 'cash', Config.Wagon.repairPrice, 'fks-stables:repair')
    if not ok then return false, err end
    DB.UpdateWagon(id, { health = 1000 })
    return true, _L('wagon_repaired')
end)

-- Repair a broken wagon on the spot: needs all items in Config.Wagon.brokenRepair ("keep" ones are not consumed)
lib.callback.register('fks-stables:wagonFix', function(src)
    local P = GetP(src); if not P then return false end
    local id = WagonOut[src]; if not id then return false, _L('no_active_wagon') end
    local row = Owned(P, 'wagon', id); if not row then return false, _L('not_owner') end
    local R = Config.Wagon.brokenRepair
    for _, it in ipairs(R.items) do
        if Bridge.ItemCount(src, it.name) < (it.count or 1) then
            return false, _L('wagon_fix_missing', it.count or 1, it.label or it.name)
        end
    end
    for _, it in ipairs(R.items) do
        if not it.keep and not Bridge.RemoveItem(src, it.name, it.count or 1) then
            return false, _L('wagon_fix_missing', it.count or 1, it.label or it.name)
        end
    end
    DB.UpdateWagon(id, { health = R.health or 1000 })
    return true
end)

lib.callback.register('fks-stables:rename', function(src, kind, id, name)
    local P = GetP(src); if not P then return false end
    local row = Owned(P, kind, id); if not row then return false, _L('not_owner') end
    name = CleanName(name); if not name then return false, _L('invalid_name') end
    local ok, err = Charge(P, 'cash', Config.Prices.rename, 'fks-stables:rename')
    if not ok then return false, err end
    if kind == 'wagon' then DB.UpdateWagon(id, { name = name }) else DB.UpdateHorse(id, { name = name }) end
    return true, _L('renamed', name)
end)

lib.callback.register('fks-stables:transfer', function(src, kind, id, to)
    local P = GetP(src); if not P then return false end
    local row = Owned(P, kind, id); if not row then return false, _L('not_owner') end
    local dest = StableAccess(src, P, to); if not dest or to == row.stable then return false, _L('no_access') end
    local ok, err = Charge(P, 'cash', Config.TransferPrice, 'fks-stables:transfer')
    if not ok then return false, err end
    if kind == 'wagon' then DB.UpdateWagon(id, { stable = to }) else DB.UpdateHorse(id, { stable = to }) end
    return true, _L('transferred', row.name, dest.label)
end)

-- Tack: price = sum of the changed categories
lib.callback.register('fks-stables:saveComponents', function(src, id, comps)
    local P = GetP(src); if not P then return false end
    local row = Owned(P, 'horse', id); if not row then return false, _L('not_owner') end
    if type(comps) ~= 'table' then return false end
    local old = Decode(row.components, {})
    local clean, price = {}, 0
    for cat, list in pairs(ValidComp) do
        local h = tonumber(comps[cat])
        if h and h ~= 0 and list[h] then clean[cat] = h end
        if clean[cat] and clean[cat] ~= old[cat] then price = price + (Config.Prices.components[cat] or 0) end
    end
    local ok, err = Charge(P, 'cash', price, 'fks-stables:components')
    if not ok then return false, err end
    DB.UpdateHorse(id, { components = json.encode(clean) })
    return true, _L('saved'), clean
end)

local function ValidTint(t)
    if type(t) ~= 'table' then return nil end
    local p = math.floor(tonumber(t[1]) or 0)
    if p < 0 or p > #Config.ColorPalettes then return nil end
    local out = { p }
    for i = 2, 4 do out[i] = FKS.Clamp(math.floor(tonumber(t[i]) or 0), 0, 255) end
    return out
end

lib.callback.register('fks-stables:saveCoat', function(src, id, coat, maneTail)
    local P = GetP(src); if not P then return false end
    if not IsTrainer(src, P) then return false, _L('no_permission') end
    local row = Owned(P, 'horse', id); if not row then return false, _L('not_owner') end
    coat, maneTail = ValidTint(coat), ValidTint(maneTail)
    if not coat and not maneTail then return false end
    local ok, err = Charge(P, 'cash', Config.Prices.coloring, 'fks-stables:coloring')
    if not ok then return false, err end
    DB.UpdateHorse(id, { coat = json.encode({ coat = coat, maneTail = maneTail }) })
    return true, _L('saved')
end)

lib.callback.register('fks-stables:saveWagonCustom', function(src, id, c)
    local P = GetP(src); if not P then return false end
    local row = Owned(P, 'wagon', id); if not row then return false, _L('not_owner') end
    if type(c) ~= 'table' then return false end
    local m = row.model:lower()
    local W, prices = Config.WagonCustom, Config.Prices.wagon
    local old = Decode(row.custom, {})
    local clean, price = {}, 0

    local function pick(key, max)
        local v = math.floor(tonumber(c[key]) or 0)
        if v > 0 and v <= max then clean[key] = v end
        if (clean[key] or 0) ~= (old[key] or 0) then price = price + prices[key] end
    end
    pick('livery', W.liveries[m] and #W.liveries[m] or 0)
    pick('tint', W.tints[m] or 0)
    pick('propset', W.propsets[m] and #W.propsets[m] or 0)
    pick('lantern', W.lanterns[m] and #W.lanterns[m] or 0)

    clean.extras = {}
    local allowed = {}
    for _, e in ipairs(W.extras[m] or {}) do allowed[e] = true end
    local oldExtras = {}
    for _, e in ipairs(old.extras or {}) do oldExtras[e] = true end
    for _, e in ipairs(type(c.extras) == 'table' and c.extras or {}) do
        e = tonumber(e)
        if e and allowed[e] then
            clean.extras[#clean.extras + 1] = e
            if not oldExtras[e] then price = price + prices.extra end
        end
    end

    local ok, err = Charge(P, 'cash', price, 'fks-stables:wagon-custom')
    if not ok then return false, err end
    DB.UpdateWagon(id, { custom = json.encode(clean) })
    return true, _L('saved'), clean
end)

---------------------------------------------------------------------------
-- In-game state (horse / wagon out)
---------------------------------------------------------------------------
RegisterNetEvent('fks-stables:server:spawned', function(kind, id, netId)
    local src = source
    local P = GetP(src); if not P then return end
    local row = Owned(P, kind, id); if not row or not On(row.active) then return end
    Spawned[src] = Spawned[src] or {}
    Spawned[src][kind] = netId
    if kind == 'wagon' then
        WagonOut[src] = id
        DB.UpdateWagon(id, { spawned = 1 })
    else
        HorseOut[src] = id
        DB.UpdateHorse(id, { spawned = 1 })
    end
    -- the entity is created on the client and takes a while to reach the server: wait for it before marking it
    CreateThread(function()
        local ent, tries = 0, 0
        while tries < 50 do
            ent = NetworkGetEntityFromNetworkId(netId)
            if ent and ent ~= 0 and DoesEntityExist(ent) then break end
            tries = tries + 1
            Wait(200)
        end
        if ent and ent ~= 0 and DoesEntityExist(ent) then
            Entity(ent).state:set(kind == 'wagon' and 'fksWagon' or 'fksHorse', id, true)
            Entity(ent).state:set('fksOwner', src, true)
            Entity(ent).state:set('fksName', row.name, true)
        elseif Config.Debug then
            print(('[fks-stables] entity %s (%s %s) never reached the server'):format(netId, kind, id))
        end
    end)
end)

-- The horse/wagon was stored (fled to the stable, handed in, despawned by distance)
RegisterNetEvent('fks-stables:server:stored', function(kind, stableId)
    local src = source
    local P = GetP(src); if not P then return end
    local id
    if kind == 'wagon' then id = WagonOut[src] else id = HorseOut[src] end
    if not id then return end
    local fields = { spawned = 0, position = 'null' }
    if stableId and FKS.StableById[stableId] then fields.stable = stableId end
    if kind == 'wagon' then DB.UpdateWagon(id, fields); WagonOut[src] = nil
    else DB.UpdateHorse(id, fields); HorseOut[src] = nil end
    if Spawned[src] then Spawned[src][kind] = nil end
end)

RegisterNetEvent('fks-stables:server:horseState', function(s)
    local src = source
    local id = HorseOut[src]
    if not id or type(s) ~= 'table' then return end
    local now = GetGameTimer()
    -- anti-spam: 5 s between saves (1 s for the final save when storing / reviving)
    if LastState[src] and now - LastState[src] < (s.final and 1000 or 5000) then return end
    LastState[src] = now

    local row = DB.Horse(id); if not row then return end
    local fields = {
        health = FKS.Clamp(math.floor(tonumber(s.health) or row.health), 0, 100),
        stamina = FKS.Clamp(math.floor(tonumber(s.stamina) or row.stamina), 0, 100),
        hunger = FKS.Clamp(tonumber(s.hunger) or row.hunger, 0, 100),
        thirst = FKS.Clamp(tonumber(s.thirst) or row.thirst, 0, 100),
        dirt = FKS.Clamp(tonumber(s.dirt) or row.dirt, 0, 100),
        hoof = FKS.Clamp(tonumber(s.hoof) or row.hoof or 100, 0, 100),
        xp = math.min(row.xp + FKS.Clamp(math.floor(tonumber(s.xp) or 0), 0, 25), math.max(row.xp, FKS.MaxXp((FKS.GetCoat(row.coat_id) or {}).tier))),
        bond = row.bond + FKS.Clamp(math.floor(tonumber(s.bond) or 0), 0, 6),
        courage = FKS.Clamp((row.courage or 0) + FKS.Clamp(tonumber(s.courage) or 0, 0, 0.5), 0, 10),
        affinity = FKS.Clamp((row.affinity or 0) + FKS.Clamp(tonumber(s.affinity) or 0, 0, 0.5), 0, 10),
    }
    if type(s.pos) == 'table' then fields.position = json.encode({ s.pos[1], s.pos[2], s.pos[3], s.pos[4] }) end
    DB.UpdateHorse(id, fields)

    local tier = (FKS.GetCoat(row.coat_id) or {}).tier
    local max = FKS.MaxXp(tier)
    if row.xp < max and fields.xp >= max then
        Notify(src, _L('horse_trained', row.name), 'success')
    end
    if FKS.BondLevel(fields.bond) > FKS.BondLevel(row.bond) then
        TriggerClientEvent('fks-stables:client:bondUp', src, FKS.BondLevel(fields.bond))
        Notify(src, _L('horse_bond_up', row.name), 'success')
    end
end)

-- The horse died (own event: does not go through the state anti-spam)
RegisterNetEvent('fks-stables:server:horseDied', function(horseId, pos)
    local src = source
    local P = GetP(src); if not P then return end
    -- the id comes from the client but only counts if the horse is theirs (does not depend on HorseOut, lost on restart)
    local id = tonumber(horseId) or HorseOut[src]
    local row = id and Owned(P, 'horse', id); if not row then return end
    RevivePending[id] = nil
    local fields = { dead = 1, health = 0 }
    if type(pos) == 'table' then fields.position = json.encode({ pos[1], pos[2], pos[3], pos[4] }) end
    DB.UpdateHorse(id, fields)
end)

-- Revive a dead horse with the item (your own or another player's)
-- netId -> horseId and owner: by the entity mark; if missing, by the list of horses out (Spawned / HorseOut)
local function HorseByNet(src, netId)
    netId = tonumber(netId) or 0
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent and ent ~= 0 and DoesEntityExist(ent) then
        local st = Entity(ent).state
        if st.fksHorse then return st.fksHorse, st.fksOwner, ent end
    else
        ent = nil
    end
    for s, list in pairs(Spawned) do
        if list.horse == netId and HorseOut[s] then return HorseOut[s], s, ent end
    end
end

lib.callback.register('fks-stables:reviveHorse', function(src, netId, ownId)
    local item = Config.Items.reviver
    if not item then return false end
    local id, owner, ent = HorseByNet(src, netId)
    -- your own horse: it is enough that it is yours (does not depend on the entity having reached the server)
    if not id and tonumber(ownId) then
        local P = GetP(src)
        local r = P and Owned(P, 'horse', tonumber(ownId))
        if r then id, owner = r.id, src end
    end
    if Config.Debug then
        print(('[fks-stables] reviveHorse src=%s netId=%s ownId=%s -> id=%s owner=%s ent=%s'):format(src, tostring(netId), tostring(ownId), tostring(id), tostring(owner), tostring(ent)))
    end
    if not id then return false, _L('revive_unknown') end
    if ent and #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(ent)) > 5.0 then return false, _L('horse_too_far') end
    local row = DB.Horse(id)
    if not row or not On(row.dead) then return false, _L('horse_not_dead') end
    if Reviving[id] then return false, _L('horse_reviving') end
    if not Bridge.RemoveItem(src, item, 1) then return false, _L('no_reviver') end

    Reviving[id] = true
    SetTimeout(Config.Revive.duration or 4000, function()
        Reviving[id] = nil
        -- only becomes alive in the database once the owner confirms the horse stood up (horseAlive)
        RevivePending[id] = true
        if owner and GetP(owner) then TriggerClientEvent('fks-stables:client:horseRevived', owner, id, src) end
    end)
    return true
end)

RegisterNetEvent('fks-stables:server:horseAlive', function(horseId)
    local src = source
    local id = tonumber(horseId)
    if not id or not RevivePending[id] then return end
    local P = GetP(src); if not P or not Owned(P, 'horse', id) then return end
    RevivePending[id] = nil
    DB.UpdateHorse(id, { dead = 0, health = Config.Revive.health or 50 })
end)

RegisterNetEvent('fks-stables:server:wagonState', function(health, pos)
    local src = source
    local id = WagonOut[src]; if not id then return end
    local fields = { health = FKS.Clamp(math.floor(tonumber(health) or 1000), 0, 1000) }
    if type(pos) == 'table' then fields.position = json.encode({ pos[1], pos[2], pos[3], pos[4] }) end
    DB.UpdateWagon(id, fields)
end)

---------------------------------------------------------------------------
-- Script entities (horse / wagon): identification and permissions
---------------------------------------------------------------------------
-- netId identifies the entity; ownKind/ownId come from the owner (their own horse/wagon, in case the mark does not exist yet)
local function Resolve(src, netId, ownKind, ownId)
    local P = GetP(src)
    local ent = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    local valid = ent and ent ~= 0 and DoesEntityExist(ent)
    local kind, id

    if valid then
        local st = Entity(ent).state
        if st.fksWagon then kind, id = 'wagon', st.fksWagon
        elseif st.fksHorse then kind, id = 'horse', st.fksHorse end
    end
    if not kind and P and (ownKind == 'horse' or ownKind == 'wagon') and tonumber(ownId) then
        local out
        if ownKind == 'wagon' then out = WagonOut[src] else out = HorseOut[src] end
        local r = Row(ownKind, tonumber(ownId))
        if r and r.citizenid == Cid(P) and (out == nil or out == r.id) then kind, id = ownKind, r.id end
    end
    if not kind then
        if Config.Debug then print(('[fks-stables] unknown entity (src %s, netId %s)'):format(src, tostring(netId))) end
        return nil
    end
    if valid and #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(ent)) > 8.0 then return nil end
    local row = Row(kind, id)
    if not row then return nil end
    return { kind = kind, id = id, row = row, P = P }
end

local function WagonMeta(row)
    local m = Decode(row.meta, {})
    m.access = m.access or {}
    m.animals = m.animals or {}
    return m
end

local function SaveWagonMeta(id, m)
    DB.UpdateWagon(id, { meta = json.encode(m) })
end

local function CanUseWagon(P, row, meta)
    if not P then return false end
    if row.citizenid == Cid(P) or not Config.Wagon.restrictStorage then return true end
    for _, a in ipairs(meta.access) do
        if a.cid == Cid(P) then return true end
    end
    return false
end

local function AnimalLoad(meta)
    local n = 0
    for _, a in ipairs(meta.animals) do n = n + (a.big and 2 or 1) end
    return n
end

---------------------------------------------------------------------------
-- Saddlebags / storage (configured inventory)
---------------------------------------------------------------------------
RegisterNetEvent('fks-stables:server:openStash', function(netId, ownKind, ownId)
    local src = source
    local e = Resolve(src, netId, ownKind, ownId)
    if not e then return end
    local row, P = e.row, e.P

    local storage
    if e.kind == 'wagon' then
        if not CanUseWagon(P, row, WagonMeta(row)) then return Notify(src, _L('no_access_storage'), 'error') end
        local w = FKS.GetWagon(row.model); storage = w and w.storage or 0
    else
        if Config.Stash.ownerOnly and (not P or row.citizenid ~= Cid(P)) then return Notify(src, _L('not_owner'), 'error') end
        local c = FKS.GetCoat(row.coat_id); storage = c and c.storage or 0
    end
    if storage <= 0 then return Notify(src, _L('no_storage'), 'error') end

    if not Bridge.Inv() then return Notify(src, _L('no_inventory'), 'error') end
    Bridge.OpenStash(src, StashId(e.kind, e.id), row.name, math.min(storage, Config.Stash.maxSlots), storage * Config.Stash.gramsPerStorage, storage)
end)

---------------------------------------------------------------------------
-- Wagons: menu, access and animals
---------------------------------------------------------------------------
local function WagonFor(src, netId, ownId)
    local e = Resolve(src, netId, 'wagon', ownId)
    if not e or e.kind ~= 'wagon' then return nil end
    return e, WagonMeta(e.row)
end

lib.callback.register('fks-stables:wagonInfo', function(src, netId, ownId)
    local e, meta = WagonFor(src, netId, ownId)
    if not e then return nil end
    local w = FKS.GetWagon(e.row.model)
    local isOwner = e.P and e.row.citizenid == Cid(e.P) or false
    return {
        id = e.id, name = e.row.name, isOwner = isOwner, canUse = CanUseWagon(e.P, e.row, meta),
        storage = w and w.storage or 0, cap = w and w.animals or 0, load = AnimalLoad(meta), count = #meta.animals,
        access = isOwner and meta.access or nil,
    }
end)

lib.callback.register('fks-stables:wagonAccess', function(src, netId, ownId, action, value)
    local e, meta = WagonFor(src, netId, ownId)
    if not e or not e.P or e.row.citizenid ~= Cid(e.P) then return false, _L('not_owner') end

    if action == 'add' then
        local target = tonumber(value)
        if not target or target == src then return false, _L('access_invalid') end
        local T = GetP(target)
        if not T then return false, _L('access_offline') end
        for _, a in ipairs(meta.access) do
            if a.cid == T.cid then return false, _L('access_exists', a.name) end
        end
        if #meta.access >= Config.Wagon.maxAccess then return false, _L('access_full', Config.Wagon.maxAccess) end
        meta.access[#meta.access + 1] = { cid = T.cid, name = T.name }
        SaveWagonMeta(e.id, meta)
        Notify(target, _L('access_received', e.row.name), 'inform')
        return true, _L('access_added', T.name)
    elseif action == 'remove' then
        for i, a in ipairs(meta.access) do
            if a.cid == value then
                table.remove(meta.access, i)
                SaveWagonMeta(e.id, meta)
                return true, _L('access_removed', a.name)
            end
        end
    end
    return false
end)

-- stores the animal / pelt the player was carrying (the client deletes it from the world after "ok")
lib.callback.register('fks-stables:storeAnimal', function(src, netId, ownId, model, quality)
    local e, meta = WagonFor(src, netId, ownId)
    if not e then return false end
    if not CanUseWagon(e.P, e.row, meta) then return false, _L('no_access_storage') end
    local w = FKS.GetWagon(e.row.model)
    local info = FKS.CarcassByHash[FKS.Hash(tonumber(model) or 0)]
    if not w or (w.animals or 0) <= 0 then return false, _L('wagon_no_animals') end
    if not info then return false, _L('animal_unknown') end
    if AnimalLoad(meta) + (info.big and 2 or 1) > w.animals then return false, _L('wagon_full') end
    meta.animals[#meta.animals + 1] = {
        model = info.model, label = info.label, big = info.big or nil, pelt = info.pelt or nil,
        quality = tonumber(quality), t = os.time(),
    }
    SaveWagonMeta(e.id, meta)
    return true, _L('animal_stored', info.label)
end)

lib.callback.register('fks-stables:listAnimals', function(src, netId, ownId)
    local e, meta = WagonFor(src, netId, ownId)
    if not e or not CanUseWagon(e.P, e.row, meta) then return nil end
    return meta.animals
end)

lib.callback.register('fks-stables:takeAnimal', function(src, netId, ownId, index, model)
    local e, meta = WagonFor(src, netId, ownId)
    if not e or not CanUseWagon(e.P, e.row, meta) then return nil end
    index = tonumber(index) or 0
    local a = meta.animals[index]
    if not a or a.model ~= model then return nil end -- the list changed in the meantime
    table.remove(meta.animals, index)
    SaveWagonMeta(e.id, meta)
    return a
end)

-- food the player has (for the "Feed" menu)
lib.callback.register('fks-stables:feedItems', function(src)
    local list = {}
    for item, f in pairs(Config.Feed) do
        local n = Bridge.ItemCount(src, item)
        if n > 0 then list[#list + 1] = { item = item, label = f.label or item, count = n } end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end)

---------------------------------------------------------------------------
-- Items (food, brush, reviver)
---------------------------------------------------------------------------
CreateThread(function()
    while not Bridge.ready do Wait(250) end -- wait for the inventory to start
    for item in pairs(Config.Feed) do
        Bridge.RegisterUsable(item, function(src) TriggerClientEvent('fks-stables:client:useItem', src, 'feed', item) end)
    end
    if Config.Items.brush then
        Bridge.RegisterUsable(Config.Items.brush, function(src) TriggerClientEvent('fks-stables:client:useItem', src, 'brush', Config.Items.brush) end)
    end
    if Config.Items.reviver then
        Bridge.RegisterUsable(Config.Items.reviver, function(src) TriggerClientEvent('fks-stables:client:useItem', src, 'revive', Config.Items.reviver) end)
    end
    if Config.Items.renameTag then
        Bridge.RegisterUsable(Config.Items.renameTag, function(src) TriggerClientEvent('fks-stables:client:useItem', src, 'rename', Config.Items.renameTag) end)
    end
    if Config.Wagon.repairItem then
        Bridge.RegisterUsable(Config.Wagon.repairItem, function(src) TriggerClientEvent('fks-stables:client:useItem', src, 'repair', Config.Wagon.repairItem) end)
    end
end)

-- Name tag (Config.Items.renameTag): renames the active horse and consumes the item
lib.callback.register('fks-stables:tagRename', function(src, name)
    local item = Config.Items.renameTag
    local P = GetP(src); if not P or not item then return false end
    local row = DB.ActiveHorse(Cid(P))
    if not row then return false, _L('no_active_horse') end
    name = CleanName(name); if not name then return false, _L('invalid_name') end
    if not Bridge.RemoveItem(src, item, 1) then return false, _L('tag_missing') end
    DB.UpdateHorse(row.id, { name = name })
    if HorseOut[src] == row.id and Spawned[src] and Spawned[src].horse then
        local ent = NetworkGetEntityFromNetworkId(Spawned[src].horse)
        if ent and ent ~= 0 and DoesEntityExist(ent) then Entity(ent).state:set('fksName', name, true) end
    end
    return true, _L('renamed', name), row.id, name
end)

-- The client confirms it is next to the horse; only then the item is consumed
lib.callback.register('fks-stables:consume', function(src, item)
    local isFeed = Config.Feed[item] ~= nil
    local tool = item == Config.Items.brush or item == Config.Care.hoof.item
    if not isFeed and not tool and item ~= Config.Items.reviver and item ~= Config.Wagon.repairItem then return false end
    if tool then return Bridge.ItemCount(src, item) > 0 end -- brush and hoof tool are not consumed
    return Bridge.RemoveItem(src, item, 1)
end)

---------------------------------------------------------------------------
-- Wild horses: zones, taming, selling, keeping
---------------------------------------------------------------------------
local Taming = {}       -- [src] = { netId, model, coat, zone, start } mini-game in progress
local Tamed = {}        -- [src] = { netId, model, coat, zone } horse tamed by this player (one at a time)
local LastWildSell = {} -- [cid] = os.time() of the last sale
local WZ = {}           -- [zone] = { inside = {[src]=true}, host, horses = {[netId] = {coat, model, protect}}, nextRoll, cooldownUntil, emptySince, force }
local WildByNet = {}    -- [netId] = zone

local function WildLog(title, desc)
    local W = Config.Wild.webhook
    if not W or not W.url or W.url == '' then return end
    PerformHttpRequest(W.url, function() end, 'POST', json.encode({
        username = W.name or 'fks-stables',
        embeds = { { title = title, description = desc, color = W.color or 11027200, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ') } },
    }), { ['Content-Type'] = 'application/json' })
end

local function DeleteNet(netId)
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent and ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
end

local function ZoneNetList(s)
    local list = {}
    for netId in pairs(s.horses) do list[#list + 1] = netId end
    return list
end

local function ZoneCount(s)
    local n = 0
    for _ in pairs(s.horses) do n = n + 1 end
    return n
end

-- picks a zone horse (by "weight")
local function PickHorse(z)
    local total = 0
    for _, h in ipairs(z.horses) do total = total + (h.weight or 1) end
    local r = math.random() * total
    for _, h in ipairs(z.horses) do
        r = r - (h.weight or 1)
        if r <= 0 then return { coat = h.coat, model = h.model } end
    end
    local h = z.horses[#z.horses]
    return { coat = h.coat, model = h.model }
end

-- Zone management: who is inside, host, spawning and cleanup of empty zones
CreateThread(function()
    for i in ipairs(Config.Wild.zones or {}) do WZ[i] = { inside = {}, horses = {}, nextRoll = 0, cooldownUntil = 0 } end
    while true do
        Wait(2000)
        if Config.Wild.enabled then
            local players = GetPlayers()
            local now = os.time()
            for i, z in ipairs(Config.Wild.zones or {}) do
                local s = WZ[i]
                local inside = {}
                for _, id in ipairs(players) do
                    local src = tonumber(id)
                    local ped = GetPlayerPed(src)
                    if ped and ped ~= 0 and #(GetEntityCoords(ped) - z.coords) <= z.radius then
                        inside[src] = true
                        if not s.inside[src] and z.notify ~= false then TriggerClientEvent('fks-stables:client:wildZoneEnter', src, i) end
                    end
                end
                s.inside = inside

                -- removes horses that no longer exist from the list
                for netId in pairs(s.horses) do
                    local ent = NetworkGetEntityFromNetworkId(netId)
                    if not ent or ent == 0 or not DoesEntityExist(ent) then s.horses[netId], WildByNet[netId] = nil, nil end
                end

                -- host: if they left the zone (or the server), passes it to another player inside
                if not s.host or not inside[s.host] then
                    local old = s.host
                    s.host = next(inside)
                    -- the zone was empty and someone entered: horses spawn right away (unless in cooldown)
                    if not old and s.host and ZoneCount(s) == 0 and now >= s.cooldownUntil then s.force = true end
                    if old and GetPlayerPing(old) > 0 then TriggerClientEvent('fks-stables:client:wildHost', old, i, nil) end
                    if s.host then TriggerClientEvent('fks-stables:client:wildHost', s.host, i, ZoneNetList(s)) end
                    if Config.Debug then print(('[fks-stables] wild: zone %s host %s -> %s'):format(i, tostring(old), tostring(s.host))) end
                end

                if s.host then
                    s.emptySince = nil
                    if now >= s.nextRoll or s.force then
                        s.nextRoll = now + (z.rollEvery or 30)
                        local free = (z.maxHorses or 3) - ZoneCount(s)
                        local roll = s.force or (now >= s.cooldownUntil and math.random() * 100 < (z.chance or 50))
                        if free > 0 and roll then
                            local picks = {}
                            for k = 1, math.random(1, math.min(free, z.perSpawn or free)) do picks[k] = PickHorse(z) end
                            TriggerClientEvent('fks-stables:client:wildSpawn', s.host, i, picks)
                            if Config.Debug then print(('[fks-stables] wild: zone %s, %s horse(s) for host %s'):format(i, #picks, s.host)) end
                            s.cooldownUntil = now + (z.cooldown or 600)
                        end
                        s.force = nil
                    end
                else
                    -- zone with nobody: after cleanupAfter seconds deletes the horses (except those being tamed)
                    s.emptySince = s.emptySince or now
                    if next(s.horses) and now - s.emptySince >= (Config.Wild.cleanupAfter or 120) then
                        for netId, h in pairs(s.horses) do
                            if not h.protect or h.protect < now then
                                DeleteNet(netId)
                                s.horses[netId], WildByNet[netId] = nil, nil
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- the host created a zone horse
RegisterNetEvent('fks-stables:server:wildSpawned', function(i, netId, coatId, model)
    local src = source
    i, netId = tonumber(i), tonumber(netId)
    local s, z = WZ[i], Config.Wild.zones[i or 0]
    if not s or not z or s.host ~= src or not netId then return end
    local coat
    for _, h in ipairs(z.horses) do
        if coatId and h.coat == coatId then coat = coatId break end -- only coats from this zone
    end
    s.horses[netId] = { coat = coat, model = FKS.Hash(tonumber(model) or 0) }
    WildByNet[netId] = i
    if Config.Debug then print(('[fks-stables] wild: zone %s registered netId %s (%s)'):format(i, netId, tostring(coat or model))) end
    -- the mark is also set from here (the client's may not be accepted, depending on the server config)
    CreateThread(function()
        for _ = 1, 50 do
            local ent = NetworkGetEntityFromNetworkId(netId)
            if ent and ent ~= 0 and DoesEntityExist(ent) then
                Entity(ent).state:set('fksWild', i, true)
                if coat then Entity(ent).state:set('fksWildCoat', coat, true) end
                return
            end
            Wait(200)
        end
        if Config.Debug then print(('[fks-stables] wild: netId %s never reached the server'):format(netId)) end
    end)
end)

-- diagnostics (/fks_wild on the client): zone state on the server
lib.callback.register('fks-stables:wildDebug', function(src)
    local now, out = os.time(), {}
    for i, s in pairs(WZ) do
        local n = 0
        for _ in pairs(s.inside) do n = n + 1 end
        out[#out + 1] = { zone = i, host = s.host, players = n, horses = ZoneCount(s),
            nextRoll = math.max(0, (s.nextRoll or 0) - now), cooldown = math.max(0, (s.cooldownUntil or 0) - now) }
    end
    return out
end)

-- (Config.Debug) /fks_wildspawn: spawns horses right away in the zones you are in
RegisterCommand('fks_wildspawn', function(src)
    if not Config.Debug then return end
    for _, s in pairs(WZ) do
        if src == 0 or s.inside[src] then s.force = true end
    end
end, false)

-- horse model: the entity's on the server (if it is there) or the one the client sent
local function WildModel(netId, clientModel)
    local ent = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if ent and ent ~= 0 and DoesEntityExist(ent) then return FKS.Hash(GetEntityModel(ent)) end
    return FKS.Hash(tonumber(clientModel) or 0)
end

-- tamed horse values: base = coat price (the zone's or the shop's with the same model)
local function WildQuote(t)
    local W = Config.Wild
    local coat, breed
    if t.coat then coat, breed = FKS.GetCoat(t.coat) end
    if not coat then coat, breed = FKS.WildCoat(t.model) end
    local cash = coat and coat.cash or 0
    local gold = coat and coat.gold or 0
    if not coat or (cash <= 0 and gold <= 0) then cash = W.unknownValue or 0 end
    local wild = coat and coat.wild or {}
    local z = Config.Wild.zones[t.zone or 0] or {}
    return {
        coat = coat, label = coat and (breed .. ' · ' .. coat.label) or _L('wild_title'),
        sell = { cash = math.floor(cash * (W.sellPercent or 0) / 100), gold = math.floor(gold * (W.sellGoldPercent or 0) / 100) },
        keep = { cash = math.floor(cash * (W.keepPercent or 0) / 100), gold = math.floor(gold * (W.keepGoldPercent or 0) / 100) },
        canSell = wild.sell ~= false,
        canKeep = coat ~= nil and wild.save ~= false,
        age = z.age or W.keepAge,
    }
end

local function WildPoint(src, idx)
    local p = Config.Wild.points[tonumber(idx) or 0]
    if not p then return nil end
    local c = p.coords
    if #(GetEntityCoords(GetPlayerPed(src)) - vector3(c.x, c.y, c.z)) > Config.Wild.radius + 6.0 then return nil end
    return p
end

local function WildCooldown(P)
    local last = LastWildSell[Cid(P)]
    if not last or (Config.Wild.sellCooldown or 0) <= 0 then return 0 end
    return math.max(0, Config.Wild.sellCooldown - (os.time() - last))
end

local function MoneyText(v)
    local parts = {}
    if v.cash > 0 then parts[#parts + 1] = '$' .. v.cash end
    if v.gold > 0 then parts[#parts + 1] = v.gold .. ' ' .. _L('gold_short') end
    return #parts > 0 and table.concat(parts, ' + ') or '$0'
end

-- the mini-game started: only counts for zone wild horses; protected from cleanup
RegisterNetEvent('fks-stables:server:wildStart', function(netId)
    local src = source
    netId = tonumber(netId)
    local i = netId and WildByNet[netId]
    if not i then Taming[src] = nil return end
    local h = WZ[i].horses[netId]
    h.protect = os.time() + Config.Wild.duration + 30
    Taming[src] = { netId = netId, model = h.model ~= 0 and h.model or WildModel(netId), coat = h.coat, zone = i, start = os.time() }
end)

RegisterNetEvent('fks-stables:server:wildFailed', function(netId)
    local src = source
    local t = Taming[src]
    if t and t.netId == tonumber(netId) then
        local h = WZ[t.zone] and WZ[t.zone].horses[t.netId]
        if h then h.protect = nil end
        Taming[src] = nil
    end
end)

-- the client finished the mini-game: only counts if it lasted the whole time. The horse leaves the zone (captured).
lib.callback.register('fks-stables:wildTamed', function(src, netId)
    local t = Taming[src]
    Taming[src] = nil
    if not t or t.netId ~= tonumber(netId) then return false end
    if os.time() - t.start < Config.Wild.duration - 2 then return false end
    if WZ[t.zone] then WZ[t.zone].horses[t.netId] = nil end
    WildByNet[t.netId] = nil
    Tamed[src] = { netId = t.netId, model = t.model, coat = t.coat, zone = t.zone }
    return true
end)

local function MyTamed(src, netId)
    local t = Tamed[src]
    if not t or t.netId ~= tonumber(netId) then return nil end
    return t
end

lib.callback.register('fks-stables:wildQuote', function(src, netId)
    local P = GetP(src); if not P then return nil end
    local t = MyTamed(src, netId); if not t then return nil end
    local q = WildQuote(t)
    return { label = q.label, sell = q.sell, keep = q.keep, canSell = q.canSell, canKeep = q.canKeep, cooldown = WildCooldown(P), age = q.age }
end)

lib.callback.register('fks-stables:wildSell', function(src, netId, idx)
    local P = GetP(src); if not P then return false end
    local t = MyTamed(src, netId); if not t then return false, _L('wild_not_tamed') end
    local point = WildPoint(src, idx); if not point then return false, _L('wild_too_far') end
    local cd = WildCooldown(P)
    if cd > 0 then return false, _L('wild_cooldown', cd) end
    local q = WildQuote(t)
    if not q.canSell then return false, _L('wild_cant_sell') end
    Tamed[src] = nil
    LastWildSell[Cid(P)] = os.time()
    if q.sell.cash > 0 then P.add('cash', q.sell.cash, 'fks-stables:wild-sell') end
    if q.sell.gold > 0 then P.add('gold', q.sell.gold, 'fks-stables:wild-sell') end
    WildLog(_L('wild_log_sell'), _L('wild_log_body', P.name or GetPlayerName(src), src, q.label, MoneyText(q.sell), point.label))
    return true, _L('wild_sold', MoneyText(q.sell))
end)

lib.callback.register('fks-stables:wildKeep', function(src, netId, idx, name)
    local P = GetP(src); if not P then return false end
    local t = MyTamed(src, netId); if not t then return false, _L('wild_not_tamed') end
    local point = WildPoint(src, idx); if not point then return false, _L('wild_too_far') end
    local q = WildQuote(t)
    if not q.canKeep then return false, _L('wild_cant_keep') end
    name = CleanName(name); if not name then return false, _L('invalid_name') end
    local cid = Cid(P)
    local lim = Limits(P).horses
    if DB.CountHorses(cid) >= lim then return false, _L('limit_horses', lim) end
    if q.keep.gold > 0 and P.money('gold') < q.keep.gold then return false, _L('not_enough_gold') end
    local ok, err = Charge(P, 'cash', q.keep.cash, 'fks-stables:wild-keep')
    if not ok then return false, err end
    if q.keep.gold > 0 then Charge(P, 'gold', q.keep.gold, 'fks-stables:wild-keep') end

    local a = q.age or { 5, 20 }
    local born = os.time() - math.floor(math.random(a[1] * 100, a[2] * 100) / 100 * Config.Aging.hoursPerYear * 3600)
    local gender = math.random(100) <= (Config.Gender.femaleChance or 50) and 'female' or 'male'
    local stable = FKS.StableById[point.stable] and point.stable or Config.Stables[1].id
    local id = DB.InsertHorse({ citizenid = cid, name = name, coat_id = q.coat.id, gender = gender, stable = stable, born = born })
    if not DB.ActiveHorse(cid) then DB.SetActiveHorse(cid, id) end
    Tamed[src] = nil
    local s = FKS.StableById[stable]
    WildLog(_L('wild_log_keep'), _L('wild_log_body', P.name or GetPlayerName(src), src, q.label .. ' (' .. name .. ')', MoneyText(q.keep), point.label))
    return true, _L('wild_kept', name, s and s.label or stable)
end)

-- when the script stops: deletes the zone wild horses
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, s in pairs(WZ) do
        for netId in pairs(s.horses) do DeleteNet(netId) end
    end
end)

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local src = source
    local s = Spawned[src]
    if s then
        for _, netId in pairs(s) do
            local ent = NetworkGetEntityFromNetworkId(netId)
            if ent and ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
        end
    end
    Spawned[src], HorseOut[src], WagonOut[src], LastState[src] = nil, nil, nil, nil
    Taming[src], Tamed[src] = nil, nil
end)

exports('GetActiveHorse', function(src)
    local P = GetP(src); if not P then return nil end
    local row = DB.ActiveHorse(Cid(P))
    return row and FormatHorse(row)
end)

-- shared with server/trainer.lua
SV = {
    GetP = GetP, Cid = Cid, On = On, Notify = Notify, Decode = Decode, CleanName = CleanName, InList = InList,
    Limits = Limits, Charge = Charge, Owned = Owned, Row = Row, FormatHorse = FormatHorse, StableAccess = StableAccess,
    IsTrainer = IsTrainer, HorseOut = HorseOut, Spawned = Spawned, StashId = StashId,
}
