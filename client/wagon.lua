Wagon = {
    veh = nil,
    id = nil,
    data = nil,
    blip = nil,
    lastCall = 0,
    spawning = false,
}

local function Notify(msg, kind)
    lib.notify({ title = Wagon.data and Wagon.data.name or _L('stable'), description = msg, type = kind or 'inform' })
end

local function Exists() return Wagon.veh and DoesEntityExist(Wagon.veh) end

local W = Config.Wagon
local function B(v) return v == true or v == 1 end
local broken = {} -- [veh] = true after the wheels came off

-- durability 0-100 (%) of any wagon
function Wagon.Durability(veh)
    if broken[veh] then return 0 end
    return math.floor(FKS.Clamp(GetEntityHealth(veh), 0, 1000) / 10)
end

function Wagon.IsBroken(veh)
    return broken[veh] == true or GetEntityHealth(veh) <= W.brokenAt
end

-- the wagon breaks: the wheels come off and it stops moving
-- silent = when recreating a wagon that was already broken (no notice)
function Wagon.Break(veh, silent)
    if not DoesEntityExist(veh) or broken[veh] then return end
    broken[veh] = true
    -- in game it keeps 1 (at 0 the game may consider the wagon destroyed); in the database it is brokenAt
    SetEntityHealth(veh, math.max(W.brokenAt, 1), 0)
    for _, wheel in ipairs((W.durability or {}).breakWheels or { 0, 1, 2, 3 }) do
        Citizen.InvokeNative(0xD4F5EFB55769D272, veh, wheel) -- BreakOffVehicleWheel
    end
    SetVehicleUndriveable(veh, true)
    if veh == Wagon.veh then
        local c = GetEntityCoords(veh)
        TriggerServerEvent('fks-stables:server:wagonState', W.brokenAt, { c.x, c.y, c.z, GetEntityHeading(veh) })
    end
    if not silent then
        local me = PlayerPedId()
        if veh == Wagon.veh or GetVehiclePedIsIn(me, false) == veh then
            lib.notify({ title = (veh == Wagon.veh and Wagon.data and Wagon.data.name) or _L('stable'), description = _L('wagon_broke'), type = 'error' })
        end
    end
end

function Wagon.Near(maxd)
    return Exists() and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(Wagon.veh)) <= (maxd or 4.0)
end

local function RoadPointNear(big)
    local p = GetEntityCoords(PlayerPedId())
    local found, node, heading = GetClosestVehicleNodeWithHeading(p.x, p.y, p.z, 1, 3.0, 0)
    if found and #(node - p) < 80.0 then return vector4(node.x, node.y, node.z, heading) end
    local off = GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, big and 8.0 or 5.0, 0.0)
    return vector4(off.x, off.y, off.z, GetEntityHeading(PlayerPedId()) + 90.0)
end

-- quick = recreate in the same place (after repairing): no wait nor notice
function Wagon.Spawn(data, at, quick)
    if Wagon.spawning then return end
    Wagon.spawning = true
    if Exists() then Wagon.Despawn(false) end

    if not quick and Config.Wagon.spawnDelay > 0 then
        lib.progressCircle({ duration = Config.Wagon.spawnDelay * 1000, label = _L('wagon_preparing'), position = 'bottom', canCancel = false })
    end

    local hash = Look.LoadModel(data.model)
    if not hash then Wagon.spawning = false return end
    at = at or RoadPointNear(data.big)

    local veh = CreateVehicle(hash, at.x, at.y, at.z, at.w, true, true, false, false)
    local t = GetGameTimer() + 3000
    while not DoesEntityExist(veh) and GetGameTimer() < t do Wait(10) end
    Wagon.spawning = false
    if not DoesEntityExist(veh) then return end

    SetModelAsNoLongerNeeded(hash)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleOnGroundProperly(veh)
    Look.ApplyWagon(veh, data.model, data.custom)
    SetEntityHealth(veh, math.max(data.health, 1), 0)

    Wagon.veh, Wagon.id, Wagon.data = veh, data.id, data
    if data.health <= W.brokenAt then Wagon.Break(veh, true) end
    Wagon.blip = Citizen.InvokeNative(0x23F74C2FDA6E7C61, -1749618580, veh)
    SetBlipSprite(Wagon.blip, joaat('blip_player_coach'), true)
    Citizen.InvokeNative(0x9CB1A1623062F402, Wagon.blip, data.name)

    -- wait for network registration (without it the netId is invalid and the server cannot find the wagon)
    local nt = GetGameTimer() + 3000
    while not NetworkGetEntityIsNetworked(veh) and GetGameTimer() < nt do
        NetworkRegisterEntityAsNetworked(veh)
        Wait(50)
    end
    local netId = NetworkGetNetworkIdFromEntity(veh)
    SetNetworkIdExistsOnAllMachines(netId, true)
    Entity(veh).state:set('fksWagon', data.id, true)
    TriggerServerEvent('fks-stables:server:spawned', 'wagon', data.id, netId)
    if not quick then Notify(_L('wagon_ready', data.name), 'success') end
end

function Wagon.Despawn(stored, stableId)
    if Wagon.blip then RemoveBlip(Wagon.blip) Wagon.blip = nil end
    if Exists() then
        if stored and Config.Wagon.saveHealth then
            TriggerServerEvent('fks-stables:server:wagonState', Wagon.IsBroken(Wagon.veh) and W.brokenAt or GetEntityHealth(Wagon.veh), nil)
        end
        NetworkRequestControlOfEntity(Wagon.veh)
        SetEntityAsMissionEntity(Wagon.veh, true, true)
        DeleteEntity(Wagon.veh)
    end
    if stored and Wagon.id then TriggerServerEvent('fks-stables:server:stored', 'wagon', stableId) end
    Wagon.veh = nil
    if stored then Wagon.id, Wagon.data = nil, nil end
end

function Wagon.Reapply()
    local data = lib.callback.await('fks-stables:getActive', false, 'wagon')
    if data and Exists() and data.id == Wagon.id then
        Wagon.data = data
        Look.ApplyWagon(Wagon.veh, data.model, data.custom)
    end
end

function Wagon.Call()
    if Config.Wagon.callFromStableOnly then return Notify(_L('wagon_in_stable_only'), 'error') end
    if GetGameTimer() - Wagon.lastCall < 5000 then return end
    Wagon.lastCall = GetGameTimer()
    local data, reason = lib.callback.await('fks-stables:getActive', false, 'wagon')
    if not data then return Notify(_L(reason or 'no_active_wagon'), 'error') end
    if data.health <= W.brokenAt then return Notify(_L('wagon_broken'), 'error') end
    Wagon.Spawn(data, nil)
end

function Wagon.Return()
    local s = Stable.Nearest(Config.Wagon.returnDistance)
    if not s then return Notify(_L('wagon_far_stable'), 'error') end
    local name = Wagon.data and Wagon.data.name or ''
    Wagon.Despawn(true, s.id)
    Notify(_L('wagon_stored', name), 'success')
end

-- Broken wagon: nails + hammer (Config.Wagon.brokenRepair), on the spot. The wagon is recreated whole in the same place.
function Wagon.Fix()
    if not Exists() or Wagon.fixing then return end
    local ok, msg = lib.callback.await('fks-stables:wagonFix', false)
    if not ok then return Notify(msg or _L('wagon_broken'), 'error') end
    Wagon.fixing = true
    local R = W.brokenRepair
    local me = PlayerPedId()
    TaskStartScenarioInPlace(me, joaat('WORLD_HUMAN_HAMMER_KNEEL_STAKE'), R.duration or 12000, true, false, false, false)
    Wait(R.duration or 12000)
    ClearPedTasks(me, true, true)
    if Exists() then
        local c, h = GetEntityCoords(Wagon.veh), GetEntityHeading(Wagon.veh)
        local data = Wagon.data
        data.health = R.health or 1000
        Wagon.Despawn(false)
        Wagon.Spawn(data, vector4(c.x, c.y, c.z + 0.3, h), true)
    end
    Wagon.fixing = false
    Notify(_L('wagon_fixed'), 'success')
end

-- Send the wagon to the stable where it was stored, from anywhere (Config.Wagon.sendAway)
function Wagon.SendAway()
    if not Config.Wagon.sendAway or not Exists() then return end
    local veh = Wagon.veh
    if not B(IsVehicleSeatFree(veh, -1)) or GetVehicleNumberOfPassengers(veh) > 0 then
        return Notify(_L('wagon_occupied'), 'error')
    end
    local name = Wagon.data and Wagon.data.name or ''
    local s = Wagon.data and FKS.StableById[Wagon.data.stable]
    Wagon.Despawn(true) -- no new stable: it stays at the one it had
    Notify(_L('wagon_sent', name, s and s.label or _L('stable')), 'success')
end

function Wagon.Repair()
    if Exists() and Wagon.IsBroken(Wagon.veh) then return Wagon.Fix() end -- broken: only with nails and hammer
    local item = Config.Wagon.repairItem
    if not item or not Exists() then return end
    if not lib.callback.await('fks-stables:consume', false, item) then return end
    TaskStartScenarioInPlace(PlayerPedId(), joaat('WORLD_HUMAN_HAMMER_KNEEL_STAKE'), 6000, true, false, false, false)
    Wait(6000)
    ClearPedTasks(PlayerPedId(), true, true)
    SetEntityHealth(Wagon.veh, 1000, 0)
    SetVehicleUndriveable(Wagon.veh, false)
    TriggerServerEvent('fks-stables:server:wagonState', 1000, nil)
    Notify(_L('wagon_repaired'), 'success')
end

-- wagon state
CreateThread(function()
    while true do
        Wait(15000)
        if Exists() and Config.Wagon.saveHealth then
            local h = broken[Wagon.veh] and W.brokenAt or GetEntityHealth(Wagon.veh)
            local c = GetEntityCoords(Wagon.veh)
            TriggerServerEvent('fks-stables:server:wagonState', h, { c.x, c.y, c.z, GetEntityHeading(Wagon.veh) })
            if h <= W.brokenAt and not broken[Wagon.veh] then Wagon.Break(Wagon.veh) end
        end
    end
end)

-- Wear: whoever drives the wagon (has control of it) wears the durability with the kilometres.
-- Crash damage already lowers the wagon's own health. When it reaches brokenAt, it breaks.
CreateThread(function()
    local lastPos, frac = {}, {}
    while true do
        Wait(1000)
        local wear = (W.durability or {}).wearPerKm or 0
        local me = PlayerPedId()
        local list = {}
        if Exists() then list[Wagon.veh] = true end
        local driving = GetVehiclePedIsIn(me, false)
        if driving ~= 0 and Entity(driving).state.fksWagon then list[driving] = true end

        for veh in pairs(list) do
            if DoesEntityExist(veh) and NetworkHasControlOfEntity(veh) and not broken[veh] then
                local h = GetEntityHealth(veh)
                local pos = GetEntityCoords(veh)
                if wear > 0 and h > W.brokenAt and lastPos[veh] and GetPedInVehicleSeat(veh, -1) ~= 0 then
                    local m = #(pos - lastPos[veh])
                    if m < 60.0 then -- ignore teleports
                        frac[veh] = (frac[veh] or 0.0) + m / 1000.0 * wear
                        local whole = math.floor(frac[veh])
                        if whole > 0 then
                            frac[veh] = frac[veh] - whole
                            h = math.max(W.brokenAt, h - whole)
                            if h > W.brokenAt then SetEntityHealth(veh, h, 0) end -- (at 0 the game could destroy it: it breaks in Break)
                        end
                    end
                end
                lastPos[veh] = pos
                if h <= W.brokenAt then Wagon.Break(veh) end
            end
        end
        for veh in pairs(lastPos) do
            if not list[veh] then lastPos[veh], frac[veh] = nil, nil end
        end
    end
end)

-- call key
CreateThread(function()
    if Config.Wagon.callFromStableOnly or not Config.Keys.wagonCall then return end
    while true do
        Wait(0)
        if not Stable.open and IsControlJustReleased(0, Config.Keys.wagonCall) then
            Wagon.Call()
        end
    end
end)

-- Recreates a stored carcass (or pelt) on the ground next to the wagon
function Wagon.SpawnCarcass(a, at)
    local hash = Look.LoadModel(a.model)
    if not hash then return end
    local z = at.z
    local ok, gz = GetGroundZFor_3dCoord(at.x, at.y, at.z + 2.0, false)
    if ok then z = gz end
    local ent
    if a.pelt then
        ent = CreateObject(hash, at.x, at.y, z, true, true, false)
        PlaceObjectOnGroundProperly(ent)
    else
        ent = CreatePed(hash, at.x, at.y, z, math.random(0, 359) + 0.0, true, true, false, false)
        local t = GetGameTimer() + 2000
        while not DoesEntityExist(ent) and GetGameTimer() < t do Wait(10) end
        Citizen.InvokeNative(0x283978A15512B2FE, ent, true) -- SetRandomOutfitVariation
        if a.quality then Citizen.InvokeNative(0xCE6B874286D640BB, ent, a.quality) end -- SetPedQuality
        SetEntityHealth(ent, 0, 0)
    end
    SetModelAsNoLongerNeeded(hash)
    SetEntityAsNoLongerNeeded(ent)
    return ent
end

-- Test (only with Config.Debug = true): /fks_animal [model] [quality 0-2]
-- e.g.: /fks_animal a_c_deer_01 2   ·   /fks_animal p_cs_pelt_xlarge_bear
RegisterCommand('fks_animal', function(_, args)
    if not Config.Debug then return end
    local model = (args[1] or 'a_c_deer_01'):lower()
    local info = FKS.CarcassByHash[FKS.Hash(joaat(model))]
    if not info then
        return lib.notify({ title = 'fks-stables', description = model .. ' is not in config/animals.lua', type = 'error' })
    end
    local at = GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, 1.5, 0.0)
    Wagon.SpawnCarcass({ model = model, pelt = info.pelt, quality = tonumber(args[2]) or 2 }, at)
    lib.notify({ title = 'fks-stables', description = ('%s spawned in front of you - pick it up and take it to the wagon.'):format(info.label), type = 'success' })
end, false)

function Wagon.RestoreAfterLogin()
    local data = lib.callback.await('fks-stables:getActive', false, 'wagon')
    -- comes back even when broken (no wheels where it was, so you can repair it with nails and hammer)
    if data and data.spawned and data.position then
        local p = data.position
        Wagon.Spawn(data, vector4(p[1], p[2], p[3], p[4] or 0.0))
    end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Wagon.blip then RemoveBlip(Wagon.blip) end
    if Exists() then DeleteEntity(Wagon.veh) end
end)

exports('GetWagon', function() return Wagon.veh end)
exports('FleeWagon', function() Wagon.Despawn(false) end)
