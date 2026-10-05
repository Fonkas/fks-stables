-- Horse training (trainer / admin only) — Config.Training
--  Obstacles: holding the reins, "Training" -> obstacles; mount and ride through the points in order.
--  Lunging:   holding the reins, "Training" -> lunging; the horse runs in circles around you (xp per minute).
--  Load:      mounted at the load point (ground marker), "Load training"; drive the loaded wagon to
--              the destination before time runs out.

Training = { isTrainer = false, active = nil }

local T = Config.Training
local function Notify(msg, kind) lib.notify({ title = _L('train_title'), description = msg, type = kind or 'inform' }) end
local function B(v) return v == true or v == 1 end
local function Var(text) return CreateVarString(10, 'LITERAL_STRING', text) end
local function Me() return PlayerPedId() end

local function MakePrompt(group, key, text, hold)
    local p = PromptRegisterBegin()
    PromptSetControlAction(p, key)
    PromptSetText(p, Var(text))
    PromptSetEnabled(p, true)
    PromptSetVisible(p, true)
    if hold then PromptSetHoldMode(p, true) else PromptSetStandardMode(p, true) end
    PromptSetGroup(p, group, 0)
    PromptRegisterEnd(p)
    return p
end
local function Done(p) return B(PromptHasStandardModeCompleted(p)) end

local function Marker(m, v, r, col)
    Citizen.InvokeNative(0x2A32FAA57B937173, m, v.x, v.y, v.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        r * 2.0, r * 2.0, 0.7, col[1], col[2], col[3], col[4], false, false, 2, false, nil, nil, false) -- DrawMarker
end

local function Clock(ms)
    local s = math.max(0, math.floor(ms / 1000))
    return ('%02d:%02d'):format(s // 60, s % 60)
end

---------------------------------------------------------------------------
-- Trainer?
---------------------------------------------------------------------------
local function RefreshTrainer()
    Training.isTrainer = lib.callback.await('fks-stables:isTrainer', false) == true
end

CreateThread(function()
    Wait(3000)
    while true do
        RefreshTrainer()
        Wait(60000)
    end
end)
RegisterNetEvent('RSGCore:Client:OnJobUpdate', function() SetTimeout(1000, RefreshTrainer) end)
RegisterNetEvent('vorp:setjob', function() SetTimeout(1000, RefreshTrainer) end)

-- ends the training in progress (msg = notice)
function Training.Stop(msg, kind)
    if not Training.active then return end
    Training.active = nil
    lib.hideTextUI()
    TriggerServerEvent('fks-stables:server:trainStop')
    if msg then Notify(msg, kind or 'error') end
end

RegisterCommand('canceltraining', function() Training.Stop(_L('train_cancelled'), 'inform') end, false)

---------------------------------------------------------------------------
-- 1. Obstacles
---------------------------------------------------------------------------
local function NearestCourse()
    local me = GetEntityCoords(Me())
    local best, bestD
    for i, c in ipairs(T.obstacles.courses) do
        local d = #(me - c.start)
        if not bestD or d < bestD then best, bestD = i, d end
    end
    return best, bestD
end

function Training.StartObstacles(ci)
    local ok, msg = lib.callback.await('fks-stables:trainStart', false, 'obstacles', ci)
    if not ok then return Notify(msg or _L('no_permission'), 'error') end
    if Care and Care.Leading and Care.Leading() then Horse.StopLead() end
    local O, c = T.obstacles, T.obstacles.courses[ci]
    local route = { c.start }
    for _, p in ipairs(c.points) do route[#route + 1] = p end
    route[#route + 1] = c.finish
    Training.active = { kind = 'obstacles', course = ci }
    Notify(_L('train_obstacles_go', c.label))

    CreateThread(function()
        local idx, t0, shown = 1, nil, nil
        while Training.active and Training.active.kind == 'obstacles' do
            Wait(0)
            local horse = Horse.ped
            if not horse or not DoesEntityExist(horse) or Horse.IsDown(horse) then Training.Stop(_L('train_no_horse')) break end
            local target = route[idx]
            Marker(O.marker, target, O.pointRadius, O.color)
            if route[idx + 1] then Marker(O.marker, route[idx + 1], O.pointRadius, O.colorNext) end

            local hp = GetEntityCoords(horse)
            if #(hp - c.start) > 200.0 then Training.Stop(_L('train_left_area')) break end
            if GetMount(Me()) == horse then
                local dx, dy = hp.x - target.x, hp.y - target.y
                if dx * dx + dy * dy <= O.pointRadius * O.pointRadius and math.abs(hp.z - target.z) <= O.heightTolerance then
                    if idx == 1 then t0 = GetGameTimer() end
                    idx = idx + 1
                    if idx > #route then
                        lib.hideTextUI()
                        local okDone, m = lib.callback.await('fks-stables:trainDone', false, 'obstacles')
                        Training.active = nil
                        Notify(m or _L('train_failed'), okDone and 'success' or 'error')
                        break
                    end
                end
            end
            -- time
            if t0 then
                local left = (c.timeLimit or 0) > 0 and (c.timeLimit * 1000 - (GetGameTimer() - t0)) or nil
                if left and left <= 0 then Training.Stop(_L('train_time_up')) break end
                local text = _L('train_obstacles_hud', idx - 1, #route - 1, left and Clock(left) or Clock(GetGameTimer() - t0))
                if text ~= shown then shown = text lib.showTextUI(text) end
            end
        end
    end)
end

---------------------------------------------------------------------------
-- 2. Lunging
---------------------------------------------------------------------------
local LG = GetRandomIntInRange(0, 0xffffff)
local LP

function Training.StartLunge()
    local ok, msg = lib.callback.await('fks-stables:trainStart', false, 'lunge')
    if not ok then return Notify(msg or _L('no_permission'), 'error') end
    if Care and Care.Leading and Care.Leading() then Horse.StopLead() Wait(600) end
    local L = T.lunge
    if not LP then
        LP = {
            stop = MakePrompt(LG, L.keys.stop, _L('train_lunge_stop')),
            jump = MakePrompt(LG, L.keys.jump, _L('train_lunge_jump')),
            slower = MakePrompt(LG, L.keys.slower, _L('train_lunge_slower')),
            faster = MakePrompt(LG, L.keys.faster, _L('train_lunge_faster')),
        }
    end
    Training.active = { kind = 'lunge' }
    Notify(_L('train_lunge_go', L.xpPerMinute))

    CreateThread(function()
        local sp = L.startSpeed or 1
        local nextMove, nextTick, dir = 0, GetGameTimer() + 60000, 1
        local horse = Horse.ped
        while Training.active and Training.active.kind == 'lunge' do
            Wait(0)
            local me = Me()
            if not horse or not DoesEntityExist(horse) or horse ~= Horse.ped or Horse.IsDown(horse) then Training.Stop(_L('train_no_horse')) break end
            if B(IsPedOnMount(me)) or B(IsEntityDead(me)) or Stable.open then Training.Stop(_L('train_cancelled'), 'inform') break end
            local c, h = GetEntityCoords(me), GetEntityCoords(horse)
            if #(c - h) > L.radius * 4 then Training.Stop(_L('train_left_area')) break end

            PromptSetActiveGroupThisFrame(LG, Var(_L('train_lunge_title', L.speeds[sp].label or _L('train_speed_' .. (L.speeds[sp].name or '')))))
            if Done(LP.stop) then Training.Stop(_L('train_lunge_end'), 'inform') break end
            if Done(LP.faster) and sp < #L.speeds then sp = sp + 1 nextMove = 0 end
            if Done(LP.slower) and sp > 1 then sp = sp - 1 nextMove = 0 end
            if Done(LP.jump) then
                if not pcall(TaskJump, horse, true) then pcall(Citizen.InvokeNative, 0x0AE4086104E067B1, horse, true) end
                nextMove = GetGameTimer() + 1200
            end

            -- runs in a circle: always aims at a point ahead on the circle around the trainer
            if GetGameTimer() > nextMove then
                nextMove = GetGameTimer() + 350
                local ang = math.atan(h.y - c.y, h.x - c.x) + dir * (0.45 + 0.12 * sp)
                local tx, ty = c.x + math.cos(ang) * L.radius, c.y + math.sin(ang) * L.radius
                TaskGoStraightToCoord(horse, tx, ty, c.z, L.speeds[sp].speed + 0.0, -1, 0.0, 0.0)
            end
            -- xp every minute (the server checks the time)
            if GetGameTimer() > nextTick then
                nextTick = GetGameTimer() + 60000
                CreateThread(function()
                    if lib.callback.await('fks-stables:trainTick', false) then Notify(_L('train_xp', L.xpPerMinute), 'success') end
                end)
            end
        end
        if horse and DoesEntityExist(horse) then ClearPedTasks(horse, true, true) end
    end)
end

---------------------------------------------------------------------------
-- 3. Load and strength
---------------------------------------------------------------------------
local function GpsTo(v)
    pcall(ClearGpsMultiRoute)
    pcall(StartGpsMultiRoute, joaat('COLOR_YELLOW'), true, true)
    pcall(AddPointToGpsMultiRoute, v.x, v.y, v.z)
    pcall(SetGpsMultiRouteRender, true)
end

local function GpsClear()
    pcall(SetGpsMultiRouteRender, false)
    pcall(ClearGpsMultiRoute)
end

function Training.StartLoad(pi)
    local p = T.load.points[pi]
    local ok, dest = lib.callback.await('fks-stables:trainStart', false, 'load', pi)
    if not ok then return Notify(dest or _L('no_permission'), 'error') end
    local d = T.load.destinations[dest]
    Training.active = { kind = 'load', point = pi, dest = dest }

    -- the horse is stored during the training (comes back next to you at the end)
    local me = Me()
    if GetMount(me) ~= 0 then
        TaskDismountAnimal(me, 0, 0, 0, 0, 0)
        local t = GetGameTimer() + 3000
        while GetMount(me) ~= 0 and GetGameTimer() < t do Wait(100) end
    end
    Horse.Despawn(false)

    local w = p.wagon
    local hash = Look.LoadModel(w.model)
    if not hash then Training.Stop(_L('train_failed')) return end
    local veh = CreateVehicle(hash, w.spawn.x, w.spawn.y, w.spawn.z, w.spawn.w, true, true, false, false)
    local t = GetGameTimer() + 3000
    while not DoesEntityExist(veh) and GetGameTimer() < t do Wait(10) end
    SetModelAsNoLongerNeeded(hash)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleOnGroundProperly(veh)
    local propset = w.propset or ((Config.WagonCustom.propsets or {})[w.model:lower()] or {})[1]
    if propset then Look.AddPropSet(veh, propset, false) end
    SetPedIntoVehicle(me, veh, -1)

    local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, d.coords.x, d.coords.y, d.coords.z) -- BlipAddForCoords
    SetBlipSprite(blip, T.load.destBlip or 54149631, true)
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, d.label)                                            -- SetBlipName
    GpsTo(d.coords)
    Notify(_L('train_load_go', d.label, Clock(T.load.timeLimit * 1000)))

    CreateThread(function()
        local endAt = GetGameTimer() + T.load.timeLimit * 1000
        local away, shown = 0, nil
        local success = false
        while Training.active and Training.active.kind == 'load' do
            Wait(500)
            if not DoesEntityExist(veh) then Training.Stop(_L('train_failed')) break end
            local left = endAt - GetGameTimer()
            if left <= 0 then Training.Stop(_L('train_time_up')) break end
            local text = _L('train_load_hud', d.label, Clock(left))
            if text ~= shown then shown = text lib.showTextUI(text) end
            if #(GetEntityCoords(veh) - d.coords) <= T.load.arriveRadius then
                lib.hideTextUI()
                local okDone, m = lib.callback.await('fks-stables:trainDone', false, 'load')
                Training.active = nil
                success = okDone
                Notify(m or _L('train_failed'), okDone and 'success' or 'error')
                break
            end
            -- abandoned the wagon
            if GetVehiclePedIsIn(Me(), false) ~= veh and #(GetEntityCoords(Me()) - GetEntityCoords(veh)) > 60.0 then
                away = away + 500
                if away > 30000 then Training.Stop(_L('train_left_area')) break end
            else
                away = 0
            end
        end
        -- cleanup: wagon removed, the horse comes back next to you
        lib.hideTextUI()
        GpsClear()
        RemoveBlip(blip)
        local me2 = Me()
        if GetVehiclePedIsIn(me2, false) == veh then TaskLeaveVehicle(me2, veh, 0) Wait(2000) end
        if DoesEntityExist(veh) then SetEntityAsMissionEntity(veh, true, true) DeleteEntity(veh) end
        local data = lib.callback.await('fks-stables:getActive', false, 'horse')
        if data and not data.dead then
            local at = GetOffsetFromEntityInWorldCoords(me2, 2.5, 1.0, 0.0)
            Horse.Spawn(data, vector4(at.x, at.y, at.z, GetEntityHeading(me2) + 90.0), true)
        end
        if not success then Training.active = nil end
    end)
end

-- load points: ground marker and, mounted on your horse, the "Load training" prompt
local CG = GetRandomIntInRange(0, 0xffffff)
local pLoad

CreateThread(function()
    Wait(1500)
    pLoad = MakePrompt(CG, T.load.key, _L('train_load'))
    while true do
        local near
        if Training.isTrainer and not Training.active then
            local me = GetEntityCoords(Me())
            for i, p in ipairs(T.load.points) do
                local dist = #(me - p.coords)
                if dist < 40.0 then
                    near = near or { i = i, d = dist }
                    Marker(T.load.marker, p.coords, T.load.pointRadius, T.load.color)
                end
            end
        end
        if near then
            Wait(0)
            local mounted = Horse.ped and GetMount(Me()) == Horse.ped
            if mounted and near.d <= T.load.pointRadius then
                PromptSetActiveGroupThisFrame(CG, Var(T.load.points[near.i].label))
                if Done(pLoad) then Training.StartLoad(near.i) Wait(500) end
            end
        else
            Wait(500)
        end
    end
end)

---------------------------------------------------------------------------
-- "Training" menu (in the lead menu, holding the reins)
---------------------------------------------------------------------------
function Training.Menu()
    if not Training.isTrainer then return end
    if Training.active then return Notify(_L('train_busy'), 'error') end
    local ci, cd = NearestCourse()
    local course = ci and T.obstacles.courses[ci]
    local nearCourse = course and cd <= T.obstacles.startDistance
    lib.registerContext({
        id = 'fks_train', title = _L('train_title'),
        options = {
            {
                title = _L('train_obstacles'), icon = 'flag-checkered', disabled = not nearCourse,
                description = nearCourse and _L('train_obstacles_desc', course.label, course.xp or 100)
                    or _L('train_obstacles_far', course and course.label or '-', cd and math.floor(cd) or 0),
                onSelect = function() Training.StartObstacles(ci) end,
            },
            {
                title = _L('train_lunge'), icon = 'rotate', description = _L('train_lunge_desc', T.lunge.xpPerMinute),
                onSelect = function() Training.StartLunge() end,
            },
            {
                title = _L('train_load'), icon = 'weight-hanging', disabled = true,
                description = _L('train_load_desc', T.load.xp),
            },
        },
    })
    lib.showContext('fks_train')
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    lib.hideTextUI()
    GpsClear()
    if LP then for _, p in pairs(LP) do PromptDelete(p) end end
    if pLoad then PromptDelete(pLoad) end
end)
