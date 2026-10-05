-- Trainer (server): permissions, training rewards, giving horses to other players, breeding.
-- Uses the functions shared by server/main.lua (SV).

local T = Config.Training
local Active = {}   -- [src] = { kind, horse, start, course | point, dest, lastTick }

local function Notify(src, msg, kind) SV.Notify(src, msg, kind) end

-- gives xp to a horse and notifies when it is fully trained
local function GiveXP(src, horseId, amount)
    local row = DB.Horse(horseId)
    if not row or amount <= 0 then return end
    local tier = (FKS.GetCoat(row.coat_id) or {}).tier
    local max = FKS.MaxXp(tier)
    if row.xp >= max then return end -- already fully trained
    local xp = math.min(row.xp + math.floor(amount), max)
    amount = xp - row.xp
    DB.UpdateHorse(horseId, { xp = xp })
    if xp >= max then Notify(src, _L('horse_trained', row.name), 'success') end
    TriggerClientEvent('fks-stables:client:xpGain', src, horseId, math.floor(amount))
end

lib.callback.register('fks-stables:isTrainer', function(src)
    return SV.IsTrainer(src)
end)

local function MyHorseOut(src)
    local P = SV.GetP(src); if not P then return nil end
    local id = SV.HorseOut[src]
    if not id then return nil end
    return SV.Owned(P, 'horse', id) and id or nil, P
end

local function Near(src, v, maxd)
    return #(GetEntityCoords(GetPlayerPed(src)) - vector3(v.x, v.y, v.z)) <= maxd
end

---------------------------------------------------------------------------
-- Training
---------------------------------------------------------------------------
-- kind: 'obstacles' (arg = course index) | 'lunge' | 'load' (arg = load point index)
lib.callback.register('fks-stables:trainStart', function(src, kind, arg)
    if not SV.IsTrainer(src) then return false, _L('no_permission') end
    local horse = MyHorseOut(src)
    if not horse then return false, _L('no_active_horse') end
    local now = os.time()
    if kind == 'obstacles' then
        local c = T.obstacles.courses[tonumber(arg) or 0]
        if not c or not Near(src, c.start, T.obstacles.startDistance + 20.0) then return false, _L('train_far') end
        Active[src] = { kind = kind, horse = horse, start = now, course = tonumber(arg) }
        return true
    elseif kind == 'lunge' then
        Active[src] = { kind = kind, horse = horse, start = now, lastTick = now }
        return true
    elseif kind == 'load' then
        local p = T.load.points[tonumber(arg) or 0]
        if not p or not Near(src, p.coords, T.load.pointRadius + 10.0) then return false, _L('train_far') end
        local d = math.random(#T.load.destinations)
        Active[src] = { kind = kind, horse = horse, start = now, point = tonumber(arg), dest = d }
        return true, d
    end
    return false
end)

-- lunging: every minute
lib.callback.register('fks-stables:trainTick', function(src)
    local a = Active[src]
    if not a or a.kind ~= 'lunge' then return false end
    local now = os.time()
    if now - a.lastTick < 55 then return false end
    a.lastTick = now
    GiveXP(src, a.horse, T.lunge.xpPerMinute)
    return true
end)

lib.callback.register('fks-stables:trainDone', function(src, kind)
    local a = Active[src]
    if not a or a.kind ~= kind then return false end
    Active[src] = nil
    local elapsed = os.time() - a.start
    if kind == 'obstacles' then
        local c = T.obstacles.courses[a.course]
        if elapsed < (c.minTime or 0) then return false, _L('train_too_fast') end
        if (c.timeLimit or 0) > 0 and elapsed > c.timeLimit + 5 then return false, _L('train_time_up') end
        if not Near(src, c.finish, T.obstacles.pointRadius + 8.0) then return false, _L('train_far') end
        GiveXP(src, a.horse, c.xp or 100)
        return true, _L('train_obstacles_done', c.xp or 100)
    elseif kind == 'load' then
        local d = T.load.destinations[a.dest]
        if elapsed > T.load.timeLimit + 5 then return false, _L('train_time_up') end
        if not Near(src, d.coords, T.load.arriveRadius + 10.0) then return false, _L('train_far') end
        GiveXP(src, a.horse, T.load.xp)
        return true, _L('train_load_done', T.load.xp)
    end
    return false
end)

RegisterNetEvent('fks-stables:server:trainStop', function()
    Active[source] = nil
end)

---------------------------------------------------------------------------
-- Give the horse to another player
---------------------------------------------------------------------------
lib.callback.register('fks-stables:giveHorse', function(src, horseId, target)
    local P = SV.GetP(src); if not P then return false end
    horseId, target = tonumber(horseId), tonumber(target)
    local row = horseId and SV.Owned(P, 'horse', horseId)
    if not row then return false, _L('not_owner') end
    local h = SV.FormatHorse(row)
    if h and not h.canGive then return false, _L('give_special') end
    if not target or target == src or GetPlayerPing(target) <= 0 then return false, _L('access_offline') end
    local TP = SV.GetP(target)
    if not TP then return false, _L('access_offline') end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(target))) > Config.Give.maxDistance then
        return false, _L('give_far')
    end
    local lim = SV.Limits(TP).horses
    if DB.CountHorses(TP.cid) >= lim then return false, _L('give_full', TP.name) end
    if h and h.breedingUntil then return false, _L('horse_breeding') end

    -- removes the horse from the old owner's world
    if SV.HorseOut[src] == horseId then
        SV.HorseOut[src] = nil
        if SV.Spawned[src] then SV.Spawned[src].horse = nil end
        TriggerClientEvent('fks-stables:client:horseGiven', src, horseId)
    end
    DB.UpdateHorse(horseId, { citizenid = TP.cid, active = 0, spawned = 0, position = 'null' })
    if not DB.ActiveHorse(TP.cid) then DB.SetActiveHorse(TP.cid, horseId) end
    Notify(target, _L('give_received', row.name, P.name or GetPlayerName(src)), 'success')
    return true, _L('give_done', row.name, TP.name or GetPlayerName(target))
end)

---------------------------------------------------------------------------
-- Breeding
---------------------------------------------------------------------------
local function RandomCoat(breedA, breedB)
    local breed = breedA
    if breedA ~= breedB and math.random(2) == 2 then breed = breedB end
    local coats = FKS.CoatsByBreed[breed] or {}
    local pool = {}
    for _, c in ipairs(coats) do if c.canBreed ~= false then pool[#pool + 1] = c end end
    if #pool == 0 then pool = coats end
    return pool[math.random(#pool)]
end

lib.callback.register('fks-stables:breed', function(src, stableId, motherId, fatherId)
    local P = SV.GetP(src); if not P then return false end
    if not SV.IsTrainer(src, P) then return false, _L('no_permission') end
    local stable = SV.StableAccess(src, P, stableId)
    if not stable or not stable.services.breeding or not stable.breed then return false, _L('no_access') end
    local mRow, fRow = SV.Owned(P, 'horse', tonumber(motherId)), SV.Owned(P, 'horse', tonumber(fatherId))
    if not mRow or not fRow then return false, _L('not_owner') end
    local m, f = SV.FormatHorse(mRow), SV.FormatHorse(fRow)
    if not m or not f or m.gender ~= 'female' or f.gender ~= 'male' then return false, _L('breed_pair') end
    if not m.canBreed then return false, _L('breed_cant', m.name) end
    if not f.canBreed then return false, _L('breed_cant', f.name) end
    if Config.KeepAtStable and (mRow.stable ~= stableId or fRow.stable ~= stableId) then return false, _L('breed_here') end
    if SV.HorseOut[src] == m.id or SV.HorseOut[src] == f.id then return false, _L('breed_out') end
    for _, b in ipairs(DB.Breedings(P.cid)) do
        if b.mother == m.id or b.father == f.id or b.mother == f.id or b.father == m.id then return false, _L('breed_cant', m.name) end
    end
    local lim = SV.Limits(P).horses
    if DB.CountHorses(P.cid) + #DB.Breedings(P.cid) >= lim then return false, _L('limit_horses', lim) end
    local B = Config.Breeding
    local ok, err = SV.Charge(P, 'cash', B.price or 0, 'fks-stables:breed')
    if not ok then return false, err end

    local now = os.time()
    local ready = now + (B.time or 120)
    local coat = RandomCoat(m.breed, f.breed)
    if not coat then return false end
    DB.InsertBreeding({ citizenid = P.cid, mother = m.id, father = f.id, stable = stableId, coat_id = coat.id,
        gender = math.random(100) <= (Config.Gender.femaleChance or 50) and 'female' or 'male', ready_at = ready })
    for _, row in ipairs({ mRow, fRow }) do
        local meta = SV.Decode(row.meta, {})
        meta.breedingUntil, meta.bredAt = ready, ready -- the cooldown (Config.Breeding.cooldown) counts from the birth
        DB.UpdateHorse(row.id, { meta = json.encode(meta) })
    end
    return true, _L('breed_started', m.name, f.name, B.time or 120)
end)

local function LookOf(h)
    return h and { model = h.model, outfit = h.outfit, coat = h.coat, maneTail = h.maneTail, components = h.components,
        gender = h.gender, scale = h.scale } or nil
end

lib.callback.register('fks-stables:myBreedings', function(src)
    local P = SV.GetP(src); if not P then return {} end
    local list, now = {}, os.time()
    for _, b in ipairs(DB.Breedings(P.cid)) do
        local m, f = DB.Horse(b.mother), DB.Horse(b.father)
        list[#list + 1] = { id = b.id, stable = b.stable, readyIn = math.max(0, b.ready_at - now),
            mother = m and LookOf(SV.FormatHorse(m)), father = f and LookOf(SV.FormatHorse(f)) }
    end
    return list
end)

lib.callback.register('fks-stables:horseLook', function(src, id)
    local P = SV.GetP(src); if not P then return nil end
    local row = SV.Owned(P, 'horse', tonumber(id))
    return row and LookOf(SV.FormatHorse(row)) or nil
end)

-- foal births (also with the owner offline)
CreateThread(function()
    while not DB.ready do Wait(500) end
    while true do
        for _, b in ipairs(DB.ReadyBreedings(os.time())) do
            if (tonumber(DB.FinishBreeding(b.id)) or 0) >= 1 then -- only one birth per breeding
                local id = DB.InsertHorse({ citizenid = b.citizenid, name = Config.Breeding.foalName or 'Cria', coat_id = b.coat_id,
                    gender = b.gender, stable = b.stable, born = os.time() })
                DB.UpdateHorse(id, { meta = json.encode({ foal = true, mother = b.mother, father = b.father }) }) -- foal mark (size / riding)
                for _, src in ipairs(GetPlayers()) do
                    local P = SV.GetP(tonumber(src))
                    if P and P.cid == b.citizenid then
                        local coat, breed = FKS.GetCoat(b.coat_id)
                        local st = FKS.StableById[b.stable]
                        Notify(tonumber(src), _L('breed_born', breed or '', st and st.label or b.stable), 'success')
                        TriggerClientEvent('fks-stables:client:foalBorn', tonumber(src), b.stable, id)
                    end
                end
            end
        end
        Wait(5000)
    end
end)

AddEventHandler('playerDropped', function()
    Active[source] = nil
end)
