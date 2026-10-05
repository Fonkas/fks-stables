-- Wild horses (Config.Wild)
--  Zones: the server knows who is in each zone and picks a "host" (one of the players inside).
--         The host creates the horses (when the server says so) and keeps them inside the zone.
--  Taming: mounting a zone wild horse opens the mini-game (letters falling down the screen: press the letter
--         or click it before it reaches the bottom). If one gets away, the horse throws you off.
--         Lasting Config.Wild.duration seconds, the horse is tamed (by you only).
--  Sell / keep: mounted on the tamed horse, at one of the Config.Wild.points (map blip).

Wild = { horse = nil, netId = nil, taming = false }

local C = Config.Wild
local Z = C.zones or {}
local retry = {}         -- [entity] = GetGameTimer() from which you can try again
local tameResult = nil   -- mini-game answer (NUI)

local function Notify(msg, kind) lib.notify({ title = _L('wild_title'), description = msg, type = kind or 'inform' }) end
local function B(v) return v == true or v == 1 end
local function Var(text) return CreateVarString(10, 'LITERAL_STRING', text) end
local function Me() return PlayerPedId() end

local function NetOf(ent)
    local t = GetGameTimer() + 2000
    while not NetworkGetEntityIsNetworked(ent) and GetGameTimer() < t do
        NetworkRegisterEntityAsNetworked(ent)
        Wait(50)
    end
    return NetworkGetNetworkIdFromEntity(ent)
end

local function Control(ent)
    local t = GetGameTimer() + 1500
    NetworkRequestControlOfEntity(ent)
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < t do Wait(50) NetworkRequestControlOfEntity(ent) end
    return NetworkHasControlOfEntity(ent)
end

local function Dbg(msg, ...) if Config.Debug then print(('[fks-stables] wild: ' .. msg):format(...)) end end

-- natives that may not exist in every RedM build: protected (an error does not break the rest)
local function SafeNative(hash, ...)
    local ok, r = pcall(Citizen.InvokeNative, hash, ...)
    if not ok then Dbg('native 0x%X failed: %s', hash, tostring(r)) return nil end
    return r
end

-- who is riding the horse (0 = nobody)
local function RiderOf(ent)
    local r = SafeNative(0xB676EFDA03DADA52, ent, Citizen.ResultAsInteger()) -- GetRiderOfMount
    if r == nil then return GetMount(Me()) == ent and Me() or 0 end
    return r
end

local function GroundAt(x, y, z)
    for i = 0, 10 do
        local ok, gz = GetGroundZFor_3dCoord(x, y, z + 30.0 - i * 6.0, false)
        if B(ok) then return gz end
    end
    return z
end

---------------------------------------------------------------------------
-- Zones: blips, entry notice, creating and keeping the horses (host)
---------------------------------------------------------------------------
local blips = {}
local hosting = {}       -- [zone] = { [netId] = true } zones this player hosts
local returning = {}     -- [entity] = true while coming back into the zone

CreateThread(function()
    if not C.enabled or C.zoneBlips == false then return end
    for _, z in ipairs(Z) do
        local b = z.blip
        if b and b.enabled ~= false then
            local c = z.coords
            if C.zoneBlipArea and b.radius ~= false then -- area (radius circle)
                local area = SafeNative(0x45F13B7E0A15C880, b.style or C.zoneBlipAreaStyle or -1282792512, c.x, c.y, c.z, (b.radius or z.radius) + 0.0) -- BlipAddForRadius
                if area then
                    -- circle only: removes the icon (the "ball") the game puts in the centre of an area blip
                    if C.zoneBlipAreaIcon == false then SetBlipSprite(area, 0, true) end
                    blips[#blips + 1] = area
                end
            end
            local sprite = b.sprite or C.zoneBlipSprite
            if sprite then
                local icon = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, c.x, c.y, c.z) -- BlipAddForCoords
                SetBlipSprite(icon, sprite, true)
                Citizen.InvokeNative(0x9CB1A1623062F402, icon, b.name or z.label)                   -- SetBlipName
                blips[#blips + 1] = icon
            end
        end
    end
end)

RegisterNetEvent('fks-stables:client:wildZoneEnter', function(i)
    local z = Z[i]
    if z then Notify(_L('wild_zone_enter', z.label)) end
end)

-- wander inside the zone
local function Wander(ped, z)
    local c = z.coords
    local ok = pcall(Citizen.InvokeNative, 0xE054346CA3A0F315, ped, c.x, c.y, c.z, (z.wanderRadius or z.spawnRadius or z.radius) + 0.0, 4.0, 8.0, 0) -- TaskWanderInArea
    if not ok then TaskWanderStandard(ped, 3.0, 5) end -- fallback: wander (containment brings it back)
end

-- the server made this player the zone host (list = horses already there) or removed them (list = nil)
RegisterNetEvent('fks-stables:client:wildHost', function(i, list)
    local z = Z[i]
    if not z then return end
    Dbg('zone %s: %s', i, list and 'you are the host' or 'you are no longer the host')
    if not list then hosting[i] = nil return end
    hosting[i] = {}
    for _, netId in ipairs(list) do
        hosting[i][netId] = true
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent ~= 0 and DoesEntityExist(ent) and not Entity(ent).state.fksTamed and Control(ent) then Wander(ent, z) end
    end
end)

-- creates a zone wild horse (pick = { coat = shop coat id } or { model = game model })
local function SpawnWild(i, pick)
    local z = Z[i]
    local coat = pick.coat and FKS.GetCoat(pick.coat)
    local model = coat and coat.model or pick.model
    local hash = model and Look.LoadModel(model)
    if not hash then return print(('[fks-stables] wild horse: invalid model %s'):format(tostring(pick.coat or pick.model))) end

    -- random point inside the spawn radius
    local ang, r = math.random() * math.pi * 2, math.sqrt(math.random()) * (z.spawnRadius or z.radius * 0.5)
    local x, y = z.coords.x + math.cos(ang) * r, z.coords.y + math.sin(ang) * r
    local ped = CreatePed(hash, x, y, GroundAt(x, y, z.coords.z), math.random(0, 359) + 0.0, true, true, false, false)
    local t = GetGameTimer() + 3000
    while not DoesEntityExist(ped) and GetGameTimer() < t do Wait(10) end
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(ped) then return end
    SetEntityAsMissionEntity(ped, true, true)

    local gender = math.random(100) <= (Config.Gender.femaleChance or 50) and 'female' or 'male'
    local okLook, err = pcall(function()
        if coat then
            Look.ApplyHorse(ped, { outfit = coat.outfit, coat = coat.coat, maneTail = coat.maneTail, components = {}, gender = gender })
        else
            Citizen.InvokeNative(0x283978A15512B2FE, ped, true)                 -- SetRandomOutfitVariation
            Look.WaitReady(ped)
            Citizen.InvokeNative(0x5653AB26C82938CF, ped, 41611, gender == 'female' and 1.0 or 0.0) -- sex
            Look.Refresh(ped)
        end
    end)
    if not okLook then Dbg('look failed: %s', tostring(err)) end
    -- mark and register right away (if anything after this fails, the horse still belongs to the zone: tameable and cleaned up)
    local netId = NetOf(ped)
    local st = Entity(ped).state
    st:set('fksWild', i, true)
    if pick.coat then st:set('fksWildCoat', pick.coat, true) end
    TriggerServerEvent('fks-stables:server:wildSpawned', i, netId, pick.coat, GetEntityModel(ped))

    SafeNative(0x9F7794730795E019, ped, 17, true)                           -- flees from danger
    SafeNative(0xAEB97D84CDF3C00B, ped, true)                               -- SetAnimalIsWild
    SetBlockingOfNonTemporaryEvents(ped, false)
    Wander(ped, z)
    Dbg('zone %s: spawned %s (netId %s)', i, tostring(pick.coat or pick.model), netId)
    return netId
end

RegisterNetEvent('fks-stables:client:wildSpawn', function(i, picks)
    Dbg('server asked for %s horse(s) in zone %s (host: %s)', #(picks or {}), i, tostring(hosting[i] ~= nil))
    if not hosting[i] then return end
    for _, pick in ipairs(picks or {}) do
        local netId = SpawnWild(i, pick)
        if netId and hosting[i] then hosting[i][netId] = true end
    end
end)

-- containment: the host brings back horses that leave the zone
CreateThread(function()
    while true do
        Wait(3000)
        for i, list in pairs(hosting) do
            local z = Z[i]
            local center = z.coords
            for netId in pairs(list) do
                local ent = NetworkGetEntityFromNetworkId(netId)
                if ent == 0 or not DoesEntityExist(ent) or Entity(ent).state.fksTamed then
                    list[netId] = nil
                elseif not B(IsEntityDead(ent)) and RiderOf(ent) == 0 then -- nobody is riding it
                    local d = #(GetEntityCoords(ent) - center)
                    if d > z.radius * (C.containAt or 0.85) and not returning[ent] then
                        if Control(ent) then
                            returning[ent] = true
                            TaskGoStraightToCoord(ent, center.x, center.y, center.z, 1.5, -1, 0.0, 0.0)
                        end
                    elseif returning[ent] and d < (z.wanderRadius or z.spawnRadius or z.radius) * 0.6 then
                        returning[ent] = nil
                        if Control(ent) then Wander(ent, z) end
                    end
                end
            end
        end
    end
end)

-- Config.Wild.clearAmbient: the host removes the game's own wild horses from the zones (they cannot be tamed by the
-- script and confused players). Never touches mounted, owned, mission/script or zone horses.
CreateThread(function()
    while true do
        Wait(5000)
        if C.clearAmbient and next(hosting) then
            for _, ped in ipairs(GetGamePool('CPed')) do
                if DoesEntityExist(ped) and not B(IsPedHuman(ped)) and B(SafeNative(0x772A1969F649E902, GetEntityModel(ped))) -- IsThisModelAHorse
                    and not B(IsEntityAMissionEntity(ped)) and RiderOf(ped) == 0 then
                    local st = Entity(ped).state
                    local owner = SafeNative(0xF103823FFE72BB49, ped, Citizen.ResultAsInteger()) or 0 -- GetActiveAnimalOwner
                    if not st.fksWild and not st.fksHorse and not st.fksTamed and owner == 0 then
                        local pos = GetEntityCoords(ped)
                        for i in pairs(hosting) do
                            if #(pos - Z[i].coords) <= Z[i].radius then
                                if Control(ped) then
                                    SetEntityAsMissionEntity(ped, true, true)
                                    DeleteEntity(ped)
                                    Dbg('zone %s: removed a game wild horse', i)
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- Diagnostics: /fks_wild (F8 console)
RegisterCommand('fks_wild', function()
    local me = GetEntityCoords(Me())
    print(('[fks-stables] wild: enabled=%s · hosting zones: %s'):format(tostring(C.enabled), json.encode((function()
        local l = {} for i in pairs(hosting) do l[#l + 1] = i end return l end)())))
    for i, z in ipairs(Z) do
        print(('  zone %s "%s": distance %.0fm (radius %.0f)'):format(i, z.label, #(me - z.coords), z.radius))
    end
    local mount = GetMount(Me())
    if mount ~= 0 then
        local st = Entity(mount).state
        print(('  mounted: model %s · fksWild=%s coat=%s fksTamed=%s fksHorse=%s'):format(GetEntityModel(mount),
            tostring(st.fksWild), tostring(st.fksWildCoat), tostring(st.fksTamed), tostring(st.fksHorse)))
    end
    local n = 0
    for _, ped in ipairs(GetGamePool('CPed')) do
        if Entity(ped).state.fksWild and #(me - GetEntityCoords(ped)) < 300.0 then n = n + 1 end
    end
    print(('  script wild horses within 300m: %s'):format(n))
    for i, list in pairs(hosting) do
        local total, alive = 0, 0
        for netId in pairs(list) do
            total = total + 1
            local ent = NetworkGetEntityFromNetworkId(netId)
            if ent ~= 0 and DoesEntityExist(ent) then alive = alive + 1 end
        end
        print(('  zone %s (host): %s horse(s) listed, %s exist here'):format(i, total, alive))
    end
    for _, z in ipairs(lib.callback.await('fks-stables:wildDebug', false) or {}) do
        print(('  server · zone %s: host=%s players=%s horses=%s · next roll in %ss · cooldown %ss'):format(
            z.zone, tostring(z.host), z.players, z.horses, z.nextRoll, z.cooldown))
    end
    print(('  Config.Debug=%s (with true the F8 console shows every step: server request, horse spawned, errors)'):format(tostring(Config.Debug)))
end, false)

---------------------------------------------------------------------------
-- Taming: letters mini-game
---------------------------------------------------------------------------
-- is it a zone wild horse that can be tamed?
local function IsCandidate(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return false end
    if ent == Horse.ped or ent == Wild.horse or B(IsEntityDead(ent)) then return false end
    local st = Entity(ent).state
    if not st.fksWild or st.fksTamed or st.fksHorse then return false end -- only zone wild horses (not NPC horses)
    if retry[ent] and GetGameTimer() < retry[ent] then return false end
    if C.knownOnly and not st.fksWildCoat and not FKS.WildCoat(GetEntityModel(ent)) then return false end
    return true
end

-- the horse throws the player off and flees
local function Throw(horse)
    local me = Me()
    if GetMount(me) == horse then ClearPedTasksImmediately(me) end
    SetPedToRagdoll(me, 2500, 3500, 0, false, false, false)
    if DoesEntityExist(horse) then
        Control(horse)
        TaskAnimalFlee(horse, me, -1)
    end
end

RegisterNUICallback('tameResult', function(d, cb)
    cb({})
    tameResult = d.ok == true
end)

local function StartTaming(horse)
    Wild.taming = true
    local me = Me()
    local netId = NetOf(horse)
    TriggerServerEvent('fks-stables:server:wildStart', netId, GetEntityModel(horse))

    tameResult = nil
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'tame', show = true,
        duration = C.duration * 1000, spawnEvery = C.spawnEvery, spawnEveryEnd = C.spawnEveryEnd,
        fallTime = C.fallTime, letters = C.letters,
    })
    Notify(_L('wild_hint'))
    while tameResult == nil do
        Wait(100)
        -- fell off (the game itself may throw them), died or the horse disappeared: failed
        if GetMount(me) ~= horse or B(IsEntityDead(me)) or not DoesEntityExist(horse) then
            tameResult = false
            SendNUIMessage({ action = 'tame', show = false })
        end
    end
    SetNuiFocus(false, false)

    if tameResult and lib.callback.await('fks-stables:wildTamed', false, netId) then
        Control(horse)
        SetEntityAsMissionEntity(horse, true, true)
        ClearPedTasks(horse, true, true)
        Citizen.InvokeNative(0xAEB97D84CDF3C00B, horse, false)                 -- SetAnimalIsWild
        Citizen.InvokeNative(0xA691C10054275290, me, horse, 0)                 -- animal owner
        Citizen.InvokeNative(0xB8B6430EAD2D2437, horse, joaat('PLAYER_HORSE')) -- personality
        local st = Entity(horse).state
        st:set('fksTamed', GetPlayerServerId(PlayerId()), true)
        st:set('fksWild', nil, true)
        Wild.horse, Wild.netId = horse, netId
        Notify(_L('wild_tamed'), 'success')
    else
        if not tameResult then TriggerServerEvent('fks-stables:server:wildFailed', netId) end
        retry[horse] = GetGameTimer() + (C.retryDelay or 5) * 1000
        if tameResult then
            Notify(_L('wild_tame_failed'), 'error')
        else
            Throw(horse)
            Notify(_L('wild_thrown'), 'error')
        end
    end
    Wild.taming = false
end

-- detects when the player mounts a wild horse
CreateThread(function()
    while true do
        Wait(300)
        if C.enabled and not Wild.taming and not Stable.open then
            local mount = GetMount(Me())
            if mount ~= 0 and IsCandidate(mount) then StartTaming(mount) end
        end
    end
end)

---------------------------------------------------------------------------
-- Sale points: blip + menu (sell / keep) mounted on the tamed horse
---------------------------------------------------------------------------
CreateThread(function()
    if not C.enabled then return end
    for _, p in ipairs(C.points) do
        local b = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, p.coords.x, p.coords.y, p.coords.z) -- BlipAddForCoords
        SetBlipSprite(b, C.blip.sprite, true)
        Citizen.InvokeNative(0x9CB1A1623062F402, b, C.blip.name)                                          -- SetBlipName
        blips[#blips + 1] = b
    end
end)

-- removes the tamed horse from the world (after being sold / stored at the stable)
local function RemoveTamed()
    local h = Wild.horse
    Wild.horse, Wild.netId = nil, nil
    if not h or not DoesEntityExist(h) then return end
    local me = Me()
    if GetMount(me) == h then
        TaskDismountAnimal(me, 0, 0, 0, 0, 0)
        local t = GetGameTimer() + 3000
        while GetMount(me) == h and GetGameTimer() < t do Wait(100) end
        if GetMount(me) == h then ClearPedTasksImmediately(me) end
    end
    Control(h)
    SetEntityAsMissionEntity(h, true, true)
    DeleteEntity(h)
end

local function Money(v)
    local parts = {}
    if (v.cash or 0) > 0 then parts[#parts + 1] = '$' .. v.cash end
    if (v.gold or 0) > 0 then parts[#parts + 1] = v.gold .. ' ' .. _L('gold_short') end
    return #parts > 0 and table.concat(parts, ' + ') or '$0'
end

local function Sell(idx)
    local ok, msg = lib.callback.await('fks-stables:wildSell', false, Wild.netId, idx)
    if msg then Notify(msg, ok and 'success' or 'error') end
    if ok then RemoveTamed() end
end

local function Keep(idx)
    local input = lib.inputDialog(_L('wild_name_title'), {
        { type = 'input', label = _L('wild_name'), required = true, min = 2, max = 24 },
    })
    if not input or not input[1] then return end
    local ok, msg = lib.callback.await('fks-stables:wildKeep', false, Wild.netId, idx, input[1])
    if msg then Notify(msg, ok and 'success' or 'error') end
    if ok then RemoveTamed() end
end

local function OpenMenu(idx)
    local q = lib.callback.await('fks-stables:wildQuote', false, Wild.netId)
    if not q then return Notify(_L('wild_not_tamed'), 'error') end
    local p = C.points[idx]
    local s = FKS.StableById[p.stable]
    lib.registerContext({
        id = 'fks_wild', title = q.label,
        options = {
            {
                title = _L('wild_sell', Money(q.sell)), icon = 'dollar-sign', disabled = not q.canSell or q.cooldown > 0,
                description = (not q.canSell and _L('wild_cant_sell')) or (q.cooldown > 0 and _L('wild_cooldown', q.cooldown)) or nil,
                onSelect = function() Sell(idx) end,
            },
            {
                title = _L('wild_keep', Money(q.keep)), icon = 'horse', disabled = not q.canKeep,
                description = q.canKeep and _L('wild_keep_desc', s and s.label or p.label, q.age[1], q.age[2]) or _L('wild_cant_keep'),
                onSelect = function() Keep(idx) end,
            },
        },
    })
    lib.showContext('fks_wild')
end

local G = GetRandomIntInRange(0, 0xffffff)
local pOpen

CreateThread(function()
    if not C.enabled then return end
    Wait(1000)
    pOpen = PromptRegisterBegin()
    PromptSetControlAction(pOpen, C.key)
    PromptSetText(pOpen, Var(_L('wild_open')))
    PromptSetEnabled(pOpen, true)
    PromptSetVisible(pOpen, true)
    PromptSetStandardMode(pOpen, true)
    PromptSetGroup(pOpen, G, 0)
    PromptRegisterEnd(pOpen)

    while true do
        local idx
        local h = Wild.horse
        if h and DoesEntityExist(h) and GetMount(Me()) == h then
            local me = GetEntityCoords(Me())
            for i, p in ipairs(C.points) do
                if #(me - vector3(p.coords.x, p.coords.y, p.coords.z)) <= C.radius then idx = i break end
            end
        end
        if idx then
            Wait(0)
            PromptSetActiveGroupThisFrame(G, Var(C.points[idx].label))
            if B(PromptHasStandardModeCompleted(pOpen)) then
                OpenMenu(idx)
                Wait(500)
            end
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, b in ipairs(blips) do RemoveBlip(b) end
    if pOpen then PromptDelete(pOpen) end
    if Wild.taming then SetNuiFocus(false, false) end
end)
