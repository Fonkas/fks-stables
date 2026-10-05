-- Native prompts (replace ox_target).
--  * Horse: our prompts join the horse's own group (they show when looking at it).
--  * Wagon and stable hand: own group, shown when you are close.

local K = Config.Prompts

local function Var(text) return CreateVarString(10, 'LITERAL_STRING', text) end
local function Notify(msg, kind) lib.notify({ title = _L('stable'), description = msg, type = kind or 'inform' }) end

local function Make(group, key, text, hold, tab)
    local p = PromptRegisterBegin()
    PromptSetControlAction(p, key)
    PromptSetText(p, Var(text))
    PromptSetEnabled(p, true)
    PromptSetVisible(p, true)
    if hold then PromptSetHoldMode(p, true) else PromptSetStandardMode(p, true) end
    PromptSetGroup(p, group, tab or 0)
    PromptRegisterEnd(p)
    return p
end

local function Show(p, on)
    PromptSetVisible(p, on)
    PromptSetEnabled(p, on)
end

local function Done(p, hold)
    if hold then return PromptHasHoldModeCompleted(p) end
    return PromptHasStandardModeCompleted(p)
end

local function OnFoot()
    local ped = PlayerPedId()
    return not IsPedOnMount(ped) and not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) and not Stable.open
end

---------------------------------------------------------------------------
-- Horses
---------------------------------------------------------------------------
local targets = {} -- [entity] = { own = bool, p = { ... } }

local function Detach(ent)
    local t = targets[ent]
    if t then for _, p in pairs(t.p) do PromptDelete(p) end end
    targets[ent] = nil
end

local function Attach(ent, own)
    local group = PromptGetGroupIdForTargetEntity(ent)
    local t = { own = own, p = {}, follow = nil, hasBags = Look.HasComponent(ent, 'saddlebags') }
    local tab = K.horseTab or 0
    -- creation order is the on-screen order (bottom to top)
    if own then
        t.p.flee = Make(group, K.flee, _L('t_flee'), false, tab)
        t.p.pat = Make(group, K.pat, _L('t_pat'), false, tab)
        t.p.lead = Make(group, K.lead, _L('t_lead'), false, tab)
    end
    t.p.bags = Make(group, K.bags, _L('t_bags'), false, tab)
    if own then
        t.p.info = Make(group, K.showInfo, _L('t_info'), false, tab)
        t.p.give = Make(group, Config.Give.key, _L('t_give'), true, tab)  -- give the horse to another player (hold)
        t.p.revive = Make(group, K.care, _L('t_revive'), true, tab) -- only shows with the horse dead
        t.p.follow = Make(group, K.follow, _L('t_follow'), false, tab)
        t.p.stand = Make(group, K.standUp, _L('t_stand_up'), false, tab)
    end
    targets[ent] = t
end

-- finds script horses (mine + others', for shared saddlebags)
CreateThread(function()
    while true do
        Wait(1000)
        local me = GetEntityCoords(PlayerPedId())
        for ent, t in pairs(targets) do
            local own = Horse.ped == ent
            if not DoesEntityExist(ent) or own ~= t.own or #(me - GetEntityCoords(ent)) > 40.0 then Detach(ent)
            else
                t.hasBags = Look.HasComponent(ent, 'saddlebags') -- the saddlebag only shows with a bag equipped
                -- another player's horse: shows the same title the owner sees (name · xp · age)
                local lbl = not own and (Entity(ent).state.fksLabel or Entity(ent).state.fksName)
                if lbl and lbl ~= t.label then t.label = lbl SetPedPromptName(ent, lbl) end
            end
        end
        if Horse.ped and DoesEntityExist(Horse.ped) and not targets[Horse.ped] then Attach(Horse.ped, true) end
        if not Config.Stash.ownerOnly then
            for _, ent in ipairs(GetGamePool('CPed')) do
                if ent ~= Horse.ped and not targets[ent] and Entity(ent).state.fksHorse
                    and #(me - GetEntityCoords(ent)) < 25.0 then
                    Attach(ent, false)
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        if next(targets) then
            Wait(0)
            -- hides the native "Brush" (B) and "Feed" (R) prompts: they were greyed out and stole the R key from the saddlebag
            for _, pt in ipairs(K.hideNative or {}) do Citizen.InvokeNative(0xFC094EF26DD153FA, pt) end
            local onFoot = OnFoot()
            for ent, t in pairs(targets) do
                if DoesEntityExist(ent) then
                    local dead = Horse.IsDown(ent)
                    Show(t.p.bags, onFoot and not dead and t.hasBags)
                    if t.own then
                        local leading = Care and Care.Leading and Care.Leading()
                        local resting = Care and Care.resting
                        Show(t.p.stand, onFoot and not dead and resting ~= nil)
                        Show(t.p.follow, onFoot and not dead and not resting)
                        Show(t.p.revive, onFoot and dead)
                        Show(t.p.info, onFoot)
                        Show(t.p.give, onFoot and not dead and Horse.data ~= nil and Horse.data.canGive ~= false)
                        Show(t.p.lead, onFoot and not dead and not leading)
                        Show(t.p.pat, onFoot and not dead)
                        Show(t.p.flee, onFoot and not dead)
                        if t.follow ~= Horse.following then
                            t.follow = Horse.following
                            PromptSetText(t.p.follow, Var(Horse.following and _L('t_stay') or _L('t_follow')))
                        end
                    end

                    if t.hasBags and Done(t.p.bags) then
                        local e, own = ent, t.own
                        CreateThread(function() Horse.OpenBags(e, own and 'horse' or nil, own and Horse.id or nil) end)
                        Wait(300)
                    elseif t.own and Done(t.p.follow) then
                        if Horse.following then Horse.Stay() else Horse.Follow() end
                        Wait(300)
                    elseif t.own and dead and Done(t.p.revive, true) then
                        local e = ent
                        CreateThread(function() Horse.ReviveAt(e) end)
                        Wait(300)
                    elseif t.own and Done(t.p.give, true) then
                        CreateThread(Horse.GiveMenu)
                        Wait(300)
                    elseif t.own and not Horse.cardOpen and Done(t.p.info) then
                        Horse.Card()
                        Wait(300)
                    elseif t.own and Care.resting and Done(t.p.stand) then
                        Care.StandUp()
                        Wait(300)
                    elseif t.own and not dead and Done(t.p.lead) then
                        CreateThread(Horse.Lead)
                        Wait(300)
                    elseif t.own and not dead and Done(t.p.pat) then
                        Horse.Pat()
                        Wait(300)
                    elseif t.own and not dead and Done(t.p.flee) then
                        Horse.Flee()
                        Wait(300)
                    end
                end
            end
        else
            Wait(500)
        end
    end
end)

---------------------------------------------------------------------------
-- Wagons (own group when you are right next to the wagon)
---------------------------------------------------------------------------
local WG = GetRandomIntInRange(0, 0xffffff)
local wp = {}
local fixMode = nil -- current text of the repair prompt (broken / worn)
local retMode = nil -- current text of the store prompt (at the stable / send away)
local near = nil -- { veh, rear = bool }

local function WagonConfig(veh)
    return FKS.WagonByHash[FKS.Hash(GetEntityModel(veh))]
end

-- distance from the player to the wagon's "box" (not the centre, which is far on a big wagon)
local function BoxDistance(veh, pos)
    local min, max = GetModelDimensions(GetEntityModel(veh))
    local o = GetOffsetFromEntityGivenWorldCoords(veh, pos.x, pos.y, pos.z)
    local dx = math.max(min.x - o.x, 0.0, o.x - max.x)
    local dy = math.max(min.y - o.y, 0.0, o.y - max.y)
    return math.sqrt(dx * dx + dy * dy), o.y < min.y + K.wagonRear and math.abs(o.x) < max.x + 0.5
end

CreateThread(function()
    while true do
        Wait(400)
        near = nil
        if OnFoot() then
            local me = GetEntityCoords(PlayerPedId())
            local best = K.wagonDistance
            local function Check(veh)
                if veh and DoesEntityExist(veh) and #(me - GetEntityCoords(veh)) < 15.0 then
                    local d, rear = BoxDistance(veh, me)
                    if d < best then best, near = d, { veh = veh, rear = rear } end
                end
            end
            Check(Wagon.veh)
            for _, veh in ipairs(GetGamePool('CVehicle')) do
                if veh ~= Wagon.veh and Entity(veh).state.fksWagon then Check(veh) end
            end
        end
    end
end)

local function Ids(veh)
    local own = veh == Wagon.veh
    return NetworkGetNetworkIdFromEntity(veh), own and Wagon.id or nil
end

local function Carrying()
    local e = Citizen.InvokeNative(0xD806CD2A4F2C2996, PlayerPedId()) -- GetFirstEntityPedIsCarrying
    if e and e ~= 0 and DoesEntityExist(e) then
        local info = FKS.CarcassByHash[FKS.Hash(GetEntityModel(e))]
        if info then return e, info end
    end
end

-- "Storage" menu: open / give access / manage access
local function AccessMenu(veh, info)
    local netId, ownId = Ids(veh)
    local opts = {}
    for _, a in ipairs(info.access or {}) do
        opts[#opts + 1] = {
            title = a.name, icon = 'user', description = _L('access_remove_hint'),
            onSelect = function()
                local ok = lib.alertDialog({ header = _L('access_remove_title'), content = _L('access_remove_confirm', a.name), centered = true, cancel = true })
                if ok == 'confirm' then
                    local res, msg = lib.callback.await('fks-stables:wagonAccess', false, netId, ownId, 'remove', a.cid)
                    if msg then Notify(msg, res and 'success' or 'error') end
                end
            end,
        }
    end
    if #opts == 0 then opts[1] = { title = _L('access_none'), readOnly = true } end
    lib.registerContext({ id = 'fks_wagon_access', title = _L('access_manage'), menu = 'fks_wagon_menu', options = opts })
    lib.showContext('fks_wagon_access')
end

local function OpenWagonMenu(veh)
    local netId, ownId = Ids(veh)
    local info = lib.callback.await('fks-stables:wagonInfo', false, netId, ownId)
    if not info then return end
    if not info.canUse then return Notify(_L('no_access_storage'), 'error') end

    local opts = {
        { title = _L('w_open_storage'), icon = 'box-open', disabled = info.storage <= 0,
          onSelect = function() TriggerServerEvent('fks-stables:server:openStash', netId, ownId and 'wagon' or nil, ownId) end },
    }
    if info.isOwner then
        opts[#opts + 1] = {
            title = _L('w_give_access'), icon = 'user-plus',
            onSelect = function()
                local input = lib.inputDialog(_L('w_give_access'), {
                    { type = 'number', label = _L('access_player_id'), required = true, min = 1 },
                })
                if not input or not input[1] then return end
                local res, msg = lib.callback.await('fks-stables:wagonAccess', false, netId, ownId, 'add', input[1])
                if msg then Notify(msg, res and 'success' or 'error') end
            end,
        }
        opts[#opts + 1] = {
            title = _L('access_manage'), icon = 'users', description = _L('access_count', #(info.access or {})),
            onSelect = function() AccessMenu(veh, info) end,
        }
    end
    lib.registerContext({ id = 'fks_wagon_menu', title = info.name, options = opts })
    lib.showContext('fks_wagon_menu')
end

-- Store the animal / pelt the player is carrying
local function StoreCarried(veh)
    local ent, a = Carrying()
    if not ent then return end
    local netId, ownId = Ids(veh)
    local info = lib.callback.await('fks-stables:wagonInfo', false, netId, ownId)
    if not info then return end
    if not info.canUse then return Notify(_L('no_access_storage'), 'error') end
    if info.cap <= 0 then return Notify(_L('wagon_no_animals'), 'error') end
    if info.load + (a.big and 2 or 1) > info.cap then return Notify(_L('wagon_full'), 'error') end

    local model = GetEntityModel(ent)
    local quality = IsEntityAPed(ent) and Citizen.InvokeNative(0x7BCC6087D130312A, ent) or nil -- GetPedQuality

    -- animation: puts the animal down at the back of the wagon
    local min = GetModelDimensions(GetEntityModel(veh))
    local spot = GetOffsetFromEntityInWorldCoords(veh, 0.0, min.y + 0.3, 0.6)
    Citizen.InvokeNative(0x6D3D87C57B3D52C7, PlayerPedId(), ent, spot.x, spot.y, spot.z, 1.0, 5) -- TaskPlaceCarriedEntityAtCoord
    local t = GetGameTimer() + 3000
    while GetGameTimer() < t and Citizen.InvokeNative(0xD806CD2A4F2C2996, PlayerPedId()) == ent do Wait(100) end

    -- removes the animal from the world (first) and only then stores it: never duplicated
    NetworkRequestControlOfEntity(ent)
    local c = GetGameTimer() + 1500
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < c do Wait(50) NetworkRequestControlOfEntity(ent) end
    DetachEntity(ent, true, true)
    SetEntityAsMissionEntity(ent, true, true)
    DeleteEntity(ent)
    if DoesEntityExist(ent) then return Notify(_L('animal_store_failed'), 'error') end
    ClearPedTasks(PlayerPedId(), true, true)

    local ok, msg = lib.callback.await('fks-stables:storeAnimal', false, netId, ownId, model, quality)
    if msg then Notify(msg, ok and 'success' or 'error') end
    if not ok then -- puts the animal back on the ground if the server refused
        Wagon.SpawnCarcass({ model = a.model, quality = quality, pelt = a.pelt }, spot)
    end
end

-- List of stored animals (click = take it out next to the wagon)
local function ManageAnimals(veh)
    local netId, ownId = Ids(veh)
    local list = lib.callback.await('fks-stables:listAnimals', false, netId, ownId)
    if not list then return Notify(_L('no_access_storage'), 'error') end
    local opts = {}
    for i, a in ipairs(list) do
        local stars = a.quality and (' · ' .. string.rep('★', a.quality + 1)) or ''
        opts[#opts + 1] = {
            title = a.label .. stars, icon = a.pelt and 'scroll' or 'paw',
            description = a.big and _L('animal_big') or nil,
            onSelect = function()
                local got = lib.callback.await('fks-stables:takeAnimal', false, netId, ownId, i, a.model)
                if not got then return Notify(_L('animal_list_changed'), 'error') end
                local min = GetModelDimensions(GetEntityModel(veh))
                local spot = GetOffsetFromEntityInWorldCoords(veh, 0.0, min.y - 1.3, 0.0)
                Wagon.SpawnCarcass(got, spot)
                Notify(_L('animal_taken', got.label), 'success')
                ManageAnimals(veh)
            end,
        }
    end
    if #opts == 0 then opts[1] = { title = _L('animals_empty'), readOnly = true } end
    local w = WagonConfig(veh)
    lib.registerContext({ id = 'fks_wagon_animals', title = _L('animals_title', w and w.label or ''), options = opts })
    lib.showContext('fks_wagon_animals')
end

CreateThread(function()
    Wait(1000)
    wp.store = Make(WG, K.wagonBags or K.bags, _L('t_wagon_store'))
    wp.animal = Make(WG, K.wagonAnimal, _L('w_store_animal'))
    wp.animals = Make(WG, K.wagonAnimals, _L('w_manage_animals'))
    wp.ret = Make(WG, K.wagonReturn, _L('t_wagon_return'), true)
    wp.repair = Make(WG, K.wagonRepair, _L('t_wagon_repair'), true)
    while true do
        local n = near
        if n and DoesEntityExist(n.veh) and OnFoot() then
            Wait(0)
            local veh = n.veh
            local own = veh == Wagon.veh
            local cfg = WagonConfig(veh)
            local hunting = cfg and (cfg.animals or 0) > 0
            local carrying = hunting and Carrying() ~= nil

            Show(wp.store, not carrying)
            Show(wp.animal, carrying)
            Show(wp.animals, hunting and n.rear and not carrying)
            -- near a stable: "Store wagon" (stays at that stable) · far: "Send to stable" (its own)
            local atStable = Stable.Nearest(Config.Wagon.returnDistance) ~= nil
            if atStable ~= retMode then
                retMode = atStable
                PromptSetText(wp.ret, Var(atStable and _L('t_wagon_return') or _L('t_wagon_send')))
            end
            Show(wp.ret, own and not carrying and (atStable or Config.Wagon.sendAway == true))
            -- broken: "Repair wheels" (nails + hammer) · worn: "Repair" (Config.Wagon.repairItem)
            local isBroken = Wagon.IsBroken(veh)
            if isBroken ~= fixMode then
                fixMode = isBroken
                PromptSetText(wp.repair, Var(isBroken and _L('t_wagon_fix') or _L('t_wagon_repair')))
            end
            Show(wp.repair, own and not carrying and (isBroken or (Config.Wagon.repairItem ~= nil and GetEntityHealth(veh) < 1000)))
            -- title: "Name - Durability 64%" (or "Broken")
            local name = (own and Wagon.data and Wagon.data.name) or (cfg and cfg.label) or _L('t_wagon_store')
            local state = isBroken and _L('label_broken') or _L('label_durability', Wagon.Durability(veh))
            PromptSetActiveGroupThisFrame(WG, Var(name .. '  -  ' .. state))

            if not carrying and Done(wp.store) then
                OpenWagonMenu(veh); Wait(300)
            elseif carrying and Done(wp.animal) then
                StoreCarried(veh); Wait(300)
            elseif hunting and n.rear and Done(wp.animals) then
                ManageAnimals(veh); Wait(300)
            elseif own and Done(wp.ret, true) then
                if atStable then Wagon.Return() else Wagon.SendAway() end
                Wait(300)
            elseif own and Done(wp.repair, true) then
                Wagon.Repair(); Wait(300)
            end
        else
            Wait(250)
        end
    end
end)

---------------------------------------------------------------------------
-- Stable hand
---------------------------------------------------------------------------
local SG = GetRandomIntInRange(0, 0xffffff)
local talk

CreateThread(function()
    Wait(1000)
    talk = Make(SG, K.talk, _L('open_stable'))
    while true do
        local near
        if OnFoot() then
            local me = GetEntityCoords(PlayerPedId())
            for id, ped in pairs(Stable.npcs) do
                if DoesEntityExist(ped) and #(me - GetEntityCoords(ped)) <= Config.InteractDistance then near = id break end
            end
        end
        if near then
            Wait(0)
            PromptSetActiveGroupThisFrame(SG, Var(FKS.StableById[near].label))
            if Done(talk) then
                Stable.Open(near)
                Wait(500)
            end
        else
            Wait(400)
        end
    end
end)

-- Diagnostics: /fks_prompts (result in the F8 console)
RegisterCommand('fks_prompts', function()
    print(('[fks-stables] Horse.ped=%s exists=%s'):format(tostring(Horse.ped), tostring(Horse.ped and DoesEntityExist(Horse.ped))))
    local n = 0
    for ent, t in pairs(targets) do
        n = n + 1
        print(('  target %s own=%s group=%s prompts=%s'):format(ent, tostring(t.own), tostring(PromptGetGroupIdForTargetEntity(ent)), json.encode(t.p)))
    end
    print(('  %d target(s) registered | stable hands loaded: %s | stable hand prompt: %s'):format(n, tostring(next(Stable.npcs) ~= nil), tostring(talk)))
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for ent in pairs(targets) do Detach(ent) end
    for _, p in pairs(wp) do PromptDelete(p) end
    if talk then PromptDelete(talk) end
end)
