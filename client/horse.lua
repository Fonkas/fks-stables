Horse = {
    ped = nil,
    id = nil,
    data = nil,
    blip = nil,
    lastWhistle = 0,
    following = false,
    deadAt = nil,
    needs = { hunger = 100, thirst = 100, dirt = 0, hoof = 100 },
    acc = { xp = 0.0, bond = 0.0 },
    warned = {},
}

local BOND_POINTS = { 1, 817, 1634, 2450 }
local CORE_HEALTH, CORE_STAMINA = 0, 1

local function Notify(msg, kind)
    lib.notify({ title = Horse.data and Horse.data.name or _L('stable'), description = msg, type = kind or 'inform' })
end

local function Me() return PlayerPedId() end

local function Exists()
    return Horse.ped and DoesEntityExist(Horse.ped)
end

-- horse dead OR down and badly hurt (the state where the game asks for a reviver: IsEntityDead returns false)
-- (these natives may return 1/0 instead of true/false — and in Lua 0 counts as true)
local function B(v) return v == true or v == 1 end

function Horse.IsDown(ped)
    if not ped or not DoesEntityExist(ped) then return false end
    return B(IsEntityDead(ped)) or B(IsPedFatallyInjured(ped)) or B(IsPedInjured(ped)) or GetEntityHealth(ped) <= 0
end

local function Core(ped, idx) return Citizen.InvokeNative(0x36731AC041289BB1, ped, idx, Citizen.ResultAsInteger()) or 0 end
local function SetCore(ped, idx, v) Citizen.InvokeNative(0xC6258F41D86676E0, ped, idx, math.floor(FKS.Clamp(v, 0, 100))) end

---------------------------------------------------------------------------
-- Attributes (training and bond)
---------------------------------------------------------------------------
-- natives that may not exist in every RedM build: protected
local function SafeNative(hash, ...)
    local ok, r = pcall(Citizen.InvokeNative, hash, ...)
    if not ok then if Config.Debug then print(('[fks-stables] native 0x%X failed: %s'):format(hash, tostring(r))) end return nil end
    return r
end
Horse.SafeNative = SafeNative

-- max points of an attribute (health 0 / stamina 1 ...) in the game
local function MaxPoints(ped, attr)
    local m = SafeNative(0x223BF310F854871C, ped, attr, Citizen.ResultAsInteger()) -- GetMaxAttributePoints
    return (m and m > 0) and m or 2000
end

function Horse.ApplyAttributes()
    if not Exists() or not Horse.data then return end
    local d = Horse.data
    local progress = FKS.Progress(d.xp, d.tier)   -- training 0..1 (xp / class max)
    local pts = math.floor(progress * (Config.Level.attributeMax or 450))
    for _, attr in ipairs({ 4, 5, 6 }) do
        SetAttributePoints(Horse.ped, attr, pts)
    end
    -- health (0) and stamina (1): percentage of the max according to class and training (Config.ClassStats)
    local pct = FKS.ClassPercent(d.tier, progress)
    for _, attr in ipairs({ 0, 1 }) do
        if pct then
            SafeNative(0x5DA12E025D47D4E5, Horse.ped, attr, math.floor(pct / 10))   -- SetAttributeBaseRank (ring size)
            SetAttributePoints(Horse.ped, attr, math.floor(MaxPoints(Horse.ped, attr) * pct / 100))
        else
            SetAttributePoints(Horse.ped, attr, pts)
        end
    end
    -- game bond: the highest between the bond level and affinity (0-10)
    local bondPts = BOND_POINTS[d.bond] or 1
    local affPts = math.floor((d.affinity or 0) / 10 * BOND_POINTS[#BOND_POINTS])
    Citizen.InvokeNative(0x09A59688C26D88DF, Horse.ped, 7, math.max(bondPts, affPts))
    Horse.ApplyCourage()
end

-- max courage: no longer afraid of gunshots and wild animals
function Horse.ApplyCourage()
    if not Exists() or not Horse.data then return end
    local fearless = (Horse.data.courage or 0) >= ((Config.Courage or {}).fearless or 10)
    if fearless == Horse.fearless then return end
    Horse.fearless = fearless
    SafeNative(0x9F7794730795E019, Horse.ped, 17, not fearless)   -- flee from danger
    SafeNative(0x70A2D1137C8ED7C9, Horse.ped, 0, not fearless)    -- SetPedFleeAttributes
    if fearless then SafeNative(0x1913FE4CBF41C463, Horse.ped, 208, true) end -- (calm mount flag)
end

-- foal: size according to age (Config.Foal)
-- (only for foals born from breeding: d.bred)
function Horse.ApplyScale()
    if not Exists() or not Horse.data then return end
    local d, F = Horse.data, Config.Foal or {}
    local adult = F.adultAge or 5
    local foal = d.bred == true and d.age ~= nil and d.age < adult
    local scale = foal and FKS.Clamp((F.minScale or 0.5) + (1 - (F.minScale or 0.5)) * (d.age / adult), F.minScale or 0.5, 1.0) or 1.0
    d.scale = scale
    SetPedScale(Horse.ped, scale + 0.0)
    d.foal = foal
    d.rideable = not d.bred or d.age == nil or d.age >= (F.rideAge or adult)
    local st = Entity(Horse.ped).state
    if st.fksFoal ~= (not d.rideable) then st:set('fksFoal', not d.rideable, true) end
end

-- the game may reset the size when the horse's look updates: foals get theirs back every few seconds
CreateThread(function()
    while true do
        Wait(3000)
        if Exists() and Horse.data and Horse.data.foal and Horse.data.scale then
            SetPedScale(Horse.ped, Horse.data.scale + 0.0)
        end
    end
end)

---------------------------------------------------------------------------
-- Spawn / despawn
---------------------------------------------------------------------------
local function GroundZ(x, y, z)
    for i = 0, 20 do
        local ok, gz = GetGroundZFor_3dCoord(x, y, z + 50.0 - i * 5.0, false)
        if ok then return gz end
    end
    return z
end

-- Spot for the horse to appear when called (nearby road or ground ~40m away)
-- (the road node must be at least spawnDistance[1] away: on / near a road the closest node to the random point
-- could be right next to the player, and the horse "teleported" instead of running over)
local function SpawnPointNear()
    local p = GetEntityCoords(Me())
    local minD, maxD = Config.Horse.spawnDistance[1], Config.Horse.spawnDistance[2]
    local tx, ty
    for _ = 1, 6 do
        local r = math.random(minD, maxD)
        local ang = math.random() * math.pi * 2
        tx, ty = p.x + math.cos(ang) * r, p.y + math.sin(ang) * r
        local found, node = GetClosestVehicleNode(tx, ty, p.z, 1, 3.0, 0.0)
        if (found == true or found == 1) and node then
            local d = #(vector3(node.x, node.y, p.z) - vector3(p.x, p.y, p.z))
            if d >= minD * 0.8 and d <= maxD + 30.0 then
                return vector4(node.x, node.y, node.z, GetHeadingFromVector_2d(p.x - node.x, p.y - node.y))
            end
        end
    end
    -- no suitable road: open ground at that distance
    return vector4(tx, ty, GroundZ(tx, ty, p.z), GetHeadingFromVector_2d(p.x - tx, p.y - ty))
end

-- owner, mount, personality and flags of the horse — applied on spawn and again on revive
-- (ResurrectPed clears this and the horse could no longer be mounted)
local function Setup(ped)
    local flags = { [6] = true, [113] = false, [136] = false, [208] = true, [209] = true, [211] = true, [277] = true,
        [297] = true, [300] = false, [301] = false, [312] = false, [319] = true, [400] = true, [412] = false,
        [419] = false, [438] = false, [439] = false, [440] = false, [561] = true }
    if Config.Horse.blockNativePrompts then
        flags[412] = true -- PCF_BlockHorsePromptsForTargetPed: hides the native Lead / Pat / Flee
        flags[442] = true -- hides the native Flee
    end
    for flag, v in pairs(flags) do Citizen.InvokeNative(0x1913FE4CBF41C463, ped, flag, v) end

    local player = PlayerId()
    Citizen.InvokeNative(0xAEB97D84CDF3C00B, ped, false)                 -- SetAnimalIsWild
    Citizen.InvokeNative(0xA691C10054275290, Me(), ped, 0)               -- animal owner
    Citizen.InvokeNative(0x931B241409216C1F, Me(), ped, false)           -- active mount
    Citizen.InvokeNative(0xED1C764997A86D5A, Me(), ped)                  -- last mount
    Citizen.InvokeNative(0xB8B6430EAD2D2437, ped, joaat('PLAYER_HORSE')) -- personality
    Citizen.InvokeNative(0xDF93973251FB2CA5, player, true)
    if not Config.Horse.allowTwoRiders then Citizen.InvokeNative(0xE6D4E435B56D5BD0, player, ped) end
    Citizen.InvokeNative(0x6734F0A6A52C371C, player, 431)
    Citizen.InvokeNative(0x024EC9B649111915, ped, true)
    Citizen.InvokeNative(0xCC97B29285B1DC3B, ped, 1)
    -- hides the native item/weapon/brush/feed prompts (handled by this script)
    -- _MODIFY_PLAYER_UI_PROMPT_FOR_PED(player, horse, type, mode, active) · mode 1 = hide
    -- hides the game prompts for this horse (Show Info, Lead, Pat, Flee, items, weapons, brush, feed)
    for _, pr in ipairs(Config.Prompts.hideForHorse or { 28, 45, 49, 50 }) do
        Citizen.InvokeNative(0xA3DB37EDF9A74635, player, ped, pr, 1, true)
    end
end

-- dead = true: spawns dead, lying on the ground (dead horse called with the whistle)
function Horse.Spawn(data, at, fromStable, dead)
    if Exists() then Horse.Despawn(false) end
    local hash = Look.LoadModel(data.model)
    if not hash then return end
    at = at or SpawnPointNear()

    local ped = CreatePed(hash, at.x, at.y, at.z, at.w, true, true, false, false)
    local t = GetGameTimer() + 3000
    while not DoesEntityExist(ped) and GetGameTimer() < t do Wait(10) end
    if not DoesEntityExist(ped) then return end
    SetModelAsNoLongerNeeded(hash)
    SetEntityAsMissionEntity(ped, true, true)

    Horse.ped, Horse.id, Horse.data = ped, data.id, data
    Horse.needs = { hunger = data.hunger, thirst = data.thirst, dirt = data.dirt, hoof = data.hoof or 100 }
    Horse.acc = { xp = 0.0, bond = 0.0, courage = 0.0, affinity = 0.0 }
    Horse.deadAt, Horse.following, Horse.warned, Horse.fleeing = nil, false, {}, false

    Setup(ped)

    Look.ApplyHorse(ped, { outfit = data.outfit, coat = data.coat, maneTail = data.maneTail, components = data.components, gender = data.gender })
    Horse.fearless = nil
    Horse.ApplyAttributes()
    SetTimeout(300, Horse.ApplyScale) -- after the look is applied (like county-ranch)
    SetCore(ped, CORE_HEALTH, data.health)
    SetCore(ped, CORE_STAMINA, data.stamina)
    Horse.label = nil
    Horse.UpdateLabel()

    Horse.AddBlip(ped, data.name)

    -- wait until the horse is registered on the network: before that the netId is invalid and the server
    -- never finds it (it stayed without the fksHorse mark and could not be revived / have its saddlebags opened by others)
    local nt = GetGameTimer() + 3000
    while not NetworkGetEntityIsNetworked(ped) and GetGameTimer() < nt do
        NetworkRegisterEntityAsNetworked(ped)
        Wait(50)
    end
    local netId = NetworkGetNetworkIdFromEntity(ped)
    SetNetworkIdExistsOnAllMachines(netId, true)
    -- also mark the horse from here (the server sets it again once the entity gets there)
    local st = Entity(ped).state
    st:set('fksHorse', data.id, true)
    st:set('fksOwner', GetPlayerServerId(PlayerId()), true)
    st:set('fksName', data.name, true)
    TriggerServerEvent('fks-stables:server:spawned', 'horse', data.id, netId)

    if dead then
        Horse.deadAt = GetGameTimer() -- already dead in the database: do not warn "died" again
        SetEntityHealth(ped, 0, 0)
        return
    end
    if not fromStable then Horse.Come() end
    Notify(_L('horse_selected', data.name), 'success')
end

-- spot on the ground next to the player (for the dead horse to appear next to them)
local function SpawnPointBeside()
    local me = Me()
    local p = GetOffsetFromEntityInWorldCoords(me, 2.5, 1.0, 0.0)
    return vector4(p.x, p.y, GroundZ(p.x, p.y, p.z), GetEntityHeading(me) + 90.0)
end

-- Horse prompt title: "Name - 520/3000 XP - 7 years"
-- (plain characters only: the prompt font has no "·" and shows a square)
-- (also goes into the fksLabel mark, so whoever looks at your horse sees the same)
function Horse.UpdateLabel()
    if not Exists() or not Horse.data then return end
    local d = Horse.data
    local parts = { d.name }
    local max = FKS.MaxXp(d.tier)
    parts[#parts + 1] = _L('label_xp', math.min(math.floor(d.xp or 0), max), max)
    if d.age then parts[#parts + 1] = _L('label_age', math.floor(d.age)) end
    local label = table.concat(parts, '  -  ')
    if label ~= Horse.label then
        Horse.label = label
        SetPedPromptName(Horse.ped, label)
        Entity(Horse.ped).state:set('fksLabel', label, true)
    end
end

-- horse map icon (also recreated on revive: the game removes it when the horse dies)
function Horse.AddBlip(ped, name)
    if Horse.blip then RemoveBlip(Horse.blip) end
    Horse.blip = Citizen.InvokeNative(0x23F74C2FDA6E7C61, -1230993421, ped) -- BlipAddForEntity
    Citizen.InvokeNative(0x9CB1A1623062F402, Horse.blip, name)              -- SetBlipName
end

local SendState -- (defined further below)

function Horse.Despawn(stored, stableId)
    -- saves the current state before removing it from the world (otherwise what changed since the last tick was lost: food, hay, stamina...)
    if Exists() and Horse.data and not Horse.IsDown(Horse.ped) then SendState(true, stored) end
    if Horse.blip then RemoveBlip(Horse.blip) Horse.blip = nil end
    if Exists() then
        NetworkRequestControlOfEntity(Horse.ped)
        SetEntityAsMissionEntity(Horse.ped, true, true)
        DeleteEntity(Horse.ped)
    end
    if stored and Horse.id then TriggerServerEvent('fks-stables:server:stored', 'horse', stableId) end
    Horse.ped, Horse.following = nil, false
    if stored then Horse.id, Horse.data = nil, nil end
end

function Horse.Reapply()
    local data = lib.callback.await('fks-stables:getActive', false, 'horse')
    if data and Exists() and data.id == Horse.id then
        Horse.data = data
        Look.ApplyHorse(Horse.ped, { outfit = data.outfit, coat = data.coat, maneTail = data.maneTail, components = data.components, gender = data.gender })
        Horse.ApplyAttributes()
        Horse.UpdateLabel()
    end
end

---------------------------------------------------------------------------
-- Orders
---------------------------------------------------------------------------
function Horse.Come()
    if not Exists() then return end
    if Care and Care.resting then Care.StandUp(true) end
    ClearPedTasks(Horse.ped, true, true)
    -- far away: gallops over; close: trots
    local far = #(GetEntityCoords(Horse.ped) - GetEntityCoords(Me())) > 20.0
    TaskGoToEntity(Horse.ped, Me(), -1, 3.0, far and (Config.Horse.comeSpeed or 3.0) or 2.0, 0, 0)
    Horse.following = false
end

function Horse.Follow()
    if not Exists() then return end
    if Care and Care.resting then Care.StandUp(true) end
    ClearPedTasks(Horse.ped, true, true)
    TaskFollowToOffsetOfEntity(Horse.ped, Me(), 0.0, -2.5, 0.0, 1.5, -1, 1.5, true, false, false, false, false, false)
    Horse.following = true
    Notify(_L('horse_follow', Horse.data.name))
end

function Horse.Stay()
    if not Exists() then return end
    ClearPedTasks(Horse.ped, true, true)
    Horse.following = false
end

-- Open the saddlebags:
--  1. the game interaction walks the player to the saddlebag and puts the hand inside;
--  2. switches to the "hand in the saddlebag" pose (mech_pickup@loot@horse_saddlebags@live@lt/rt · base) looped
--     — this also stops the game from opening its own saddlebag menu, which would close the inventory;
--  3. opens the inventory and keeps the pose until the player closes it.
local BAG_CLOSE_KEYS = { 0x156F7119, 0x4A903C11 } -- Backspace, ESC

-- Inventory state given by the inventory itself (events). nil = not known yet.
-- vorp_inventory: "syn:closeinv" fires the moment it closes; OnInvStateChange reports open/close.
local invState = nil
AddEventHandler('vorp_inventory:Client:OnInvStateChange', function(open) invState = open == true end)
AddEventHandler('syn:closeinv', function() invState = false end)
AddEventHandler('vorp_stables:setClosedInv', function() invState = false end)
AddEventHandler('ox_inventory:closedInventory', function() invState = false end)

local function InventoryOpen()
    if invState ~= nil then return invState end
    local st = LocalPlayer.state
    return st.IsInvActive == true or st.invOpen == true or st.inv_busy == true or B(IsNuiFocused())   -- vorp · ox · rsg
end

local function LoadAnimDict(dict)
    if not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(10) end
    return HasAnimDictLoaded(dict)
end

function Horse.OpenBags(ent, ownKind, ownId)
    local me = Me()
    local S = Config.Stash
    local dict, clip
    if DoesEntityExist(ent) and not Horse.IsDown(ent) then
        if S.bagsInteraction then
            TaskAnimalInteraction(me, ent, joaat(S.bagsInteraction), 0, 0)
            Wait(S.bagsDelay or 1000)
        end
        if S.bagsPose then
            local pos = GetEntityCoords(me)
            local side = GetOffsetFromEntityGivenWorldCoords(ent, pos.x, pos.y, pos.z).x < 0 and 'lt' or 'rt'
            local d = S.bagsPose:format(side)
            if LoadAnimDict(d) then
                dict, clip = d, S.bagsPoseClip or 'base'
                TaskPlayAnim(me, dict, clip, 4.0, -4.0, -1, 1, 0, false, false, false)
            end
        end
        if not dict then ClearPedTasksImmediately(me) end
    end

    -- do not open with a game menu active or the player "busy" (the inventory would close right away)
    local t = GetGameTimer() + 3000
    while GetGameTimer() < t and (B(IsPauseMenuActive()) or LocalPlayer.state.inv_busy) do Wait(100) end
    invState = nil -- wait for the inventory to say it opened
    TriggerServerEvent('fks-stables:server:openStash', NetworkGetNetworkIdFromEntity(ent), ownKind, ownId)

    if not dict then return end
    -- keep the pose while the inventory is open. ALWAYS ends when:
    --  * the inventory closes (after opening) or does not open within 2.5 s;
    --  * the player presses ESC / Backspace;
    --  * the player walks away from the horse, the horse disappears or 10 min pass.
    local opened, start, why = false, GetGameTimer(), '10 min limit'
    local limit, nextAnim = start + 600000, 0
    local function dbg(msg) if Config.Debug then print('[fks-stables] saddlebags: ' .. msg) end end
    while GetGameTimer() < limit do
        Wait(0)
        if InventoryOpen() then
            if not opened then dbg('inventory opened') end
            opened = true
        elseif opened then
            why = 'inventory closed' break
        elseif GetGameTimer() - start > 2500 then
            why = 'inventory did not open within 2.5 s' break
        end
        -- (key natives return 0/1: without B() the 0 counted as "pressed" and ended right away)
        local esc = false
        for _, k in ipairs(BAG_CLOSE_KEYS) do
            if B(IsControlJustPressed(0, k)) or B(IsDisabledControlJustPressed(0, k)) then esc = true end
        end
        if esc and opened then why = 'ESC / Backspace' break end
        if not DoesEntityExist(ent) or #(GetEntityCoords(me) - GetEntityCoords(ent)) > 4.0 then why = 'walked away' break end
        if GetGameTimer() > nextAnim then
            nextAnim = GetGameTimer() + 250
            if not B(IsEntityPlayingAnim(me, dict, clip, 3)) then TaskPlayAnim(me, dict, clip, 4.0, -4.0, -1, 1, 0, false, false, false) end
        end
    end
    dbg('ended (' .. why .. ')')
    -- end now: the pose AND the native saddlebag interaction (the normal ClearPedTasks does not cancel it)
    StopAnimTask(me, dict, clip, 8.0)
    ClearPedTasksImmediately(me)
    -- watch for 2 s: if the game puts the player back on the saddlebag, cut it again
    local stop = GetGameTimer() + 2000
    while GetGameTimer() < stop do
        Wait(100)
        if B(IsEntityPlayingAnim(me, dict, clip, 3)) or B(IsPedUsingAnyScenario(me)) then
            dbg('pose came back - clearing again')
            ClearPedTasksImmediately(me)
        end
    end
    RemoveAnimDict(dict)
end

function Horse.Lead()
    if not Exists() or Horse.IsDown(Horse.ped) then return end
    if Care and Care.resting then Care.StandUp(true) Wait(2500) end
    Horse.following = false
    if TaskLeadHorse then
        TaskLeadHorse(Me(), Horse.ped)
    else
        print('[fks-stables] TaskLeadHorse does not exist in this RedM build - remove 11 from Config.Prompts.hideNative')
    end
end

function Horse.StopLead()
    if TaskStopLeadingHorse then TaskStopLeadingHorse(Me()) end
    ClearPedTasks(Me(), true, true)
end

local patTry, lastPat = 1, 0
function Horse.Pat()
    if not Exists() or Horse.IsDown(Horse.ped) then return end
    local list = Config.Pat.interactions
    local name = list[Config.Debug and patTry or 1]
    if Config.Debug then
        print(('[fks-stables] pat: trying "%s" (%s/%s)'):format(name, patTry, #list))
        patTry = patTry % #list + 1
    end
    TaskAnimalInteraction(Me(), Horse.ped, joaat(name), 0, 0)
    if GetGameTimer() - lastPat > Config.Pat.cooldown * 1000 then
        lastPat = GetGameTimer()
        Horse.acc.bond = Horse.acc.bond + (Config.Pat.bond or 0)
        Horse.acc.affinity = (Horse.acc.affinity or 0) + ((Config.Affinity or {}).perFeed or 0)
    end
end

function Horse.Flee()
    if not Exists() then return end
    if Care and Care.resting then Care.StandUp(true) end
    local ped, name = Horse.ped, Horse.data.name
    Horse.fleeing = true
    TaskAnimalFlee(ped, Me(), -1)
    Notify(_L('horse_fled', name))
    local s = Stable.Nearest(150.0)
    SetTimeout(8000, function()
        if Horse.ped == ped then Horse.Despawn(true, Config.KeepAtStable and s and s.id or nil) end
    end)
end

function Horse.Whistle()
    if GetGameTimer() - Horse.lastWhistle < Config.Horse.whistleCooldown * 1000 then
        return Notify(_L('whistle_cooldown'), 'error')
    end
    Horse.lastWhistle = GetGameTimer()

    -- load training: the horse is "stored" until the training ends
    if Training and Training.active and Training.active.kind == 'load' then return Notify(_L('train_horse_busy'), 'error') end

    -- dead: the body appears on the ground next to the player (to revive it with the item)
    -- (only when the death was actually detected: deadAt)
    if Exists() and Horse.deadAt and Horse.IsDown(Horse.ped) then
        if #(GetEntityCoords(Me()) - GetEntityCoords(Horse.ped)) <= (Config.Revive.callNear or 10.0) then
            return Notify(_L('horse_dead_here', Horse.data.name), 'error')
        end
        local data = Horse.data
        Horse.Despawn(false)
        Horse.Spawn(data, SpawnPointBeside(), true, true)
        return Notify(_L('horse_dead_here', data.name), 'error')
    end

    if Exists() then
        local d = #(GetEntityCoords(Me()) - GetEntityCoords(Horse.ped))
        if d <= Config.Horse.followDistance then
            if Horse.following then Horse.Stay() else Horse.Follow() end
            return
        end
        if d <= Config.Horse.comeDistance then
            Horse.Come()
            return Notify(_L('horse_coming', Horse.data.name))
        end
        Horse.Despawn(false)
    end

    local data, reason = lib.callback.await('fks-stables:getActive', false, 'horse')
    if not data then return Notify(_L(reason or 'no_active_horse'), 'error') end
    if Config.Horse.callFromStableOnly and not data.spawned then return Notify(_L('horse_in_stable_only'), 'error') end
    if data.dead then
        Horse.Spawn(data, SpawnPointBeside(), true, true)
        return Notify(_L('horse_dead_here', data.name), 'error')
    end
    Horse.Spawn(data, nil, false)
    Notify(_L('horse_coming', data.name))
end

---------------------------------------------------------------------------
-- State: hunger, thirst, dirt, xp, bond, death
---------------------------------------------------------------------------
local function Pace(ped)
    local v = GetEntitySpeed(ped)
    if v < 0.5 then return 'idle' elseif v < 3.0 then return 'walk' elseif v < 7.0 then return 'run' end
    return 'sprint'
end

-- final = save when storing / reviving (the server accepts it even right after another one)
-- noPos = do not save the position (the horse goes to the stable)
function SendState(final, noPos)
    if not Exists() then return end
    local ped = Horse.ped
    local xp, bond = math.floor(Horse.acc.xp), math.floor(Horse.acc.bond)
    Horse.acc.xp, Horse.acc.bond = Horse.acc.xp - xp, Horse.acc.bond - bond
    if Horse.data and xp > 0 then
        Horse.data.xp = math.min((Horse.data.xp or 0) + math.min(xp, 25), FKS.MaxXp(Horse.data.tier))
        Horse.UpdateLabel()
        Horse.ApplyAttributes()
    end
    local courage, affinity = Horse.acc.courage or 0.0, Horse.acc.affinity or 0.0
    Horse.acc.courage, Horse.acc.affinity = 0.0, 0.0
    if Horse.data then
        Horse.data.courage = FKS.Clamp((Horse.data.courage or 0) + math.min(courage, 0.5), 0, 10)
        Horse.data.affinity = FKS.Clamp((Horse.data.affinity or 0) + math.min(affinity, 0.5), 0, 10)
        Horse.ApplyCourage()
    end
    local c = GetEntityCoords(ped)
    TriggerServerEvent('fks-stables:server:horseState', {
        health = Core(ped, CORE_HEALTH), stamina = Core(ped, CORE_STAMINA),
        hunger = Horse.needs.hunger, thirst = Horse.needs.thirst, dirt = Horse.needs.dirt, hoof = Horse.needs.hoof,
        xp = xp, bond = bond, courage = courage, affinity = affinity, final = final or nil,
        pos = not noPos and { c.x, c.y, c.z, GetEntityHeading(ped) } or nil,
    })
end

-- Death: tells the server right away (the horse becomes unavailable) and leaves the body in place.
-- The body goes to the stable (dead) after Config.Revive.bodyTime or if you go too far away.
CreateThread(function()
    while true do
        Wait(1000)
        if Exists() and Horse.data then
            local ped = Horse.ped
            if Horse.IsDown(ped) then
                if not Horse.deadAt then
                    Horse.deadAt = GetGameTimer()
                    Horse.following = false
                    local c = GetEntityCoords(ped)
                    TriggerServerEvent('fks-stables:server:horseDied', Horse.id, { c.x, c.y, c.z, GetEntityHeading(ped) })
                    Notify(_L('horse_died', Horse.data.name), 'error')
                else
                    local bodyTime = (Config.Revive.bodyTime or 0) * 1000
                    local far = Config.Horse.despawnDistance > 0 and #(GetEntityCoords(Me()) - GetEntityCoords(ped)) > Config.Horse.despawnDistance
                    if far or (bodyTime > 0 and GetGameTimer() - Horse.deadAt > bodyTime) then
                        local name = Horse.data.name
                        Horse.Despawn(true)
                        Notify(_L('horse_body_gone', name), 'error')
                    end
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(Config.Needs.tick * 1000)
        if Exists() and Horse.data then
            local ped = Horse.ped
            if not Horse.IsDown(ped) and not Horse.deadAt then
                local mounted = GetMount(Me()) == ped
                local pace = Pace(ped)
                local mins = Config.Needs.tick / 60

                if Config.Needs.enabled then
                    local dr = Config.Needs.drain[pace]
                    local n = Horse.needs
                    n.hunger = FKS.Clamp(n.hunger - dr[1], 0, 100)
                    n.thirst = FKS.Clamp(n.thirst - dr[2], 0, 100)
                    if mounted and pace ~= 'idle' then
                        n.dirt = FKS.Clamp(n.dirt + Config.Needs.dirtPerTick, 0, 100)
                        n.hoof = FKS.Clamp(n.hoof - (Config.Care.hoof.drain[pace] or 0), 0, 100)
                    end
                    if n.hoof < Config.Care.hoof.penalty then
                        SetCore(ped, CORE_STAMINA, Core(ped, CORE_STAMINA) - Config.Care.hoof.penaltyStamina)
                        if not Horse.warned.hoof then Horse.warned.hoof = true Notify(_L('horse_hooves_dirty', Horse.data.name), 'warning') end
                    else
                        Horse.warned.hoof = nil
                    end

                    if n.hunger <= Config.Needs.starving or n.thirst <= Config.Needs.starving then
                        SetCore(ped, CORE_HEALTH, Core(ped, CORE_HEALTH) - Config.Needs.starvingLoss.health)
                        SetCore(ped, CORE_STAMINA, Core(ped, CORE_STAMINA) - Config.Needs.starvingLoss.stamina)
                    end
                    if n.hunger < 20 and not Horse.warned.hunger then Horse.warned.hunger = true Notify(_L('horse_hungry', Horse.data.name), 'warning') end
                    if n.thirst < 20 and not Horse.warned.thirst then Horse.warned.thirst = true Notify(_L('horse_thirsty', Horse.data.name), 'warning') end
                    if n.hunger > 40 then Horse.warned.hunger = nil end
                    if n.thirst > 40 then Horse.warned.thirst = nil end
                end

                if mounted and pace ~= 'idle' then
                    local rate = pace == 'sprint' and Config.Level.xpPerMinuteSprint or Config.Level.xpPerMinuteRiding
                    Horse.acc.xp = Horse.acc.xp + rate * mins
                    Horse.acc.bond = Horse.acc.bond + Config.Bond.perMinuteRiding * mins
                end
                -- courage and affinity: rise over time (mounted and moving, or near the owner)
                local CO, AF = Config.Courage or {}, Config.Affinity or {}
                if mounted and pace ~= 'idle' then
                    Horse.acc.courage = Horse.acc.courage + (CO.perMinuteRiding or 0) * mins
                    Horse.acc.affinity = Horse.acc.affinity + (AF.perMinuteRiding or 0) * mins
                elseif #(GetEntityCoords(Me()) - GetEntityCoords(ped)) < 15.0 then
                    Horse.acc.courage = Horse.acc.courage + (CO.perMinuteNear or 0) * mins
                    Horse.acc.affinity = Horse.acc.affinity + (AF.perMinuteNear or 0) * mins
                end
                -- foal age (grows until adult)
                if Horse.data.age and Horse.data.agePerSec and Horse.data.agePerSec > 0 then
                    Horse.data.age = Horse.data.age + Config.Needs.tick * Horse.data.agePerSec
                    if Horse.data.foal then Horse.ApplyScale() end
                end

                SendState()

                local far = #(GetEntityCoords(Me()) - GetEntityCoords(ped))
                if Config.Horse.despawnDistance > 0 and far > Config.Horse.despawnDistance and not mounted then
                    Horse.Despawn(false)
                end
            end
        end
    end
end)

-- xp given by the server (training): updates the title
RegisterNetEvent('fks-stables:client:xpGain', function(id, amount)
    if Horse.data and Horse.id == id then
        Horse.data.xp = math.min((Horse.data.xp or 0) + (tonumber(amount) or 0), FKS.MaxXp(Horse.data.tier))
        Horse.UpdateLabel()
        Horse.ApplyAttributes()
    end
end)

-- the horse was given to another player: it leaves the world
RegisterNetEvent('fks-stables:client:horseGiven', function(id)
    if Horse.id ~= id then return end
    Horse.Despawn(false)
    Horse.id, Horse.data = nil, nil
end)

-- nobody rides a foal (Config.Foal.rideAge): dismount and warn
CreateThread(function()
    while true do
        Wait(500)
        local me = Me()
        local mount = GetMount(me)
        if mount ~= 0 and Entity(mount).state.fksFoal then
            TaskDismountAnimal(me, 0, 0, 0, 0, 0)
            Wait(1200)
            if GetMount(me) == mount then ClearPedTasksImmediately(me) end
            Notify(_L('foal_ride', (Config.Foal or {}).rideAge or 5), 'error')
        end
    end
end)

-- Name tag (Config.Items.renameTag): renames the active horse
function Horse.TagRename()
    local data = Horse.data or lib.callback.await('fks-stables:getActive', false, 'horse')
    if not data then return Notify(_L('no_active_horse'), 'error') end
    local input = lib.inputDialog(_L('tag_title', data.name), {
        { type = 'input', label = _L('wild_name'), default = data.name, required = true, min = 2, max = 24 },
    })
    if not input or not input[1] then return end
    local ok, msg, id, name = lib.callback.await('fks-stables:tagRename', false, input[1])
    if msg then Notify(msg, ok and 'success' or 'error') end
    if ok and Horse.data and Horse.id == id then
        Horse.data.name = name
        Horse.label = nil
        Horse.UpdateLabel()
        if Horse.blip then Citizen.InvokeNative(0x9CB1A1623062F402, Horse.blip, name) end -- SetBlipName
    end
end

-- Give the horse to another player ("Transfer" prompt when looking at your horse)
function Horse.GiveMenu()
    if not Horse.data then return end
    local input = lib.inputDialog(_L('give_title', Horse.data.name), {
        { type = 'number', label = _L('access_player_id'), required = true, min = 1 },
    })
    if not input or not input[1] then return end
    local ok, msg = lib.callback.await('fks-stables:giveHorse', false, Horse.id, input[1])
    if msg then Notify(msg, ok and 'success' or 'error') end
end


RegisterNetEvent('fks-stables:client:bondUp', function(lvl)
    if Horse.data then Horse.data.bond = lvl Horse.ApplyAttributes() end
end)

---------------------------------------------------------------------------
-- Items: food, brush, reviver
---------------------------------------------------------------------------
local function NearOwnHorse(maxd)
    return Exists() and not IsPedOnMount(Me()) and #(GetEntityCoords(Me()) - GetEntityCoords(Horse.ped)) <= (maxd or 2.5)
end

local function MountedOnOwn()
    return Exists() and GetMount(Me()) == Horse.ped
end

Horse.NearOwn, Horse.MountedOnOwn, Horse.Core, Horse.SetCore = NearOwnHorse, MountedOnOwn, Core, SetCore
Horse.CORE_HEALTH, Horse.CORE_STAMINA = CORE_HEALTH, CORE_STAMINA

-- applies gains (0-100) to the horse's needs and cores
function Horse.Gain(g)
    if not Exists() then return end
    local n, ped = Horse.needs, Horse.ped
    if g.hunger then n.hunger = FKS.Clamp(n.hunger + g.hunger, 0, 100) end
    if g.thirst then n.thirst = FKS.Clamp(n.thirst + g.thirst, 0, 100) end
    -- the core only takes integers: accumulate the fractions (gains spread over seconds) until they add up to 1
    Horse.frac = Horse.frac or { h = 0.0, s = 0.0 }
    if g.health and g.health ~= 0 then
        Horse.frac.h = Horse.frac.h + g.health
        local whole = Horse.frac.h >= 0 and math.floor(Horse.frac.h) or math.ceil(Horse.frac.h)
        if whole ~= 0 then Horse.frac.h = Horse.frac.h - whole SetCore(ped, CORE_HEALTH, Core(ped, CORE_HEALTH) + whole) end
    end
    if g.stamina and g.stamina ~= 0 then
        Horse.frac.s = Horse.frac.s + g.stamina
        local whole = Horse.frac.s >= 0 and math.floor(Horse.frac.s) or math.ceil(Horse.frac.s)
        if whole ~= 0 then Horse.frac.s = Horse.frac.s - whole SetCore(ped, CORE_STAMINA, Core(ped, CORE_STAMINA) + whole) end
    end
    if g.xp then Horse.acc.xp = Horse.acc.xp + g.xp end
    if g.bond then Horse.acc.bond = Horse.acc.bond + g.bond end
    if g.affinity then Horse.acc.affinity = (Horse.acc.affinity or 0) + g.affinity end
end

function Horse.Feed(item)
    local f = Config.Feed[item]
    local mounted = MountedOnOwn()
    if mounted and not Config.Care.mountedFeed then return end
    if not f or not (NearOwnHorse() or mounted) or Horse.IsDown(Horse.ped) then return Notify(_L('horse_too_far'), 'error') end
    if Horse.busy then return end
    if not lib.callback.await('fks-stables:consume', false, item) then return end
    Horse.busy = true
    local ped = Horse.ped
    -- the same interaction works on foot and mounted (the game picks the animation of leaning down to the horse's mouth)
    local prop = f.prop and joaat(f.prop) or 0
    if f.core then
        TaskAnimalInteraction(Me(), ped, -1355254781, prop ~= 0 and prop or joaat('consumable_horse_stimulant'), 0)
        Wait(3500)
    else
        Citizen.InvokeNative(0xCD181A959CFDD7F4, Me(), ped, f.interaction and joaat(f.interaction) or -224471938, prop, 0)
        Wait(mounted and 3500 or 5000)
    end
    Horse.busy = false
    if not Exists() then return end
    Horse.Gain({ hunger = f.hunger, thirst = f.thirst, health = f.health, stamina = f.stamina, xp = Config.Level.xpFeed, bond = f.bond,
        affinity = (Config.Affinity or {}).perFeed })
    if f.gold then Horse.Gold(f.gold) end
    PlaySoundFrontend('Core_Fill_Up', 'Consumption_Sounds', true, 0)
    Notify(_L('horse_fed', Horse.data.name), 'success')
end

-- Gold boost (stimulants, Config.Feed[item].gold): like the player's gold tonics in fks-hud.
-- For X seconds the ring turns gold (game "overpower") and the stamina / health never drop;
-- when it ends the horse is left fully recovered.
local goldUntil = { health = 0, stamina = 0 }
local goldRunning = false

local function FillStamina(ped)
    local cur = Citizen.InvokeNative(0x775A1CA7893AA8B5, ped, Citizen.ResultAsFloat()) or 0.0 -- GetPedStamina
    local max = Citizen.InvokeNative(0xCB42AFE2B613EE55, ped, Citizen.ResultAsFloat()) or 0.0 -- GetPedMaxStamina
    if max > 0 and cur < max then
        Citizen.InvokeNative(0xC3D4B754C0E86B9E, ped, max - cur)   -- ChangePedStamina
        SafeNative(0x675680D089BFA21F, ped, max + 0.0)              -- RestorePedStamina (mounts)
    end
end

local function FillHealth(ped)
    local max = GetEntityMaxHealth(ped)
    if GetEntityHealth(ped) < max then SetEntityHealth(ped, max, 0) end
end

function Horse.Gold(g)
    if not Exists() then return end
    local ped = Horse.ped
    for which, secs in pairs(g) do
        secs = tonumber(secs) or 0
        if secs > 0 and (which == 'health' or which == 'stamina') then
            local idx = which == 'health' and CORE_HEALTH or CORE_STAMINA
            SetCore(ped, idx, 100)
            SafeNative(0x4AF5A4C7B9157D14, ped, idx, secs + 0.0, true) -- EnableAttributeCoreOverpower (gold core)
            SafeNative(0xF6A7C08DF2E28B28, ped, idx, secs + 0.0, true) -- EnableAttributeOverpower (gold ring)
            goldUntil[which] = math.max(goldUntil[which], GetGameTimer() + secs * 1000)
            -- HUD (fks-hud or any HUD listening): lock the ring and show the timer
            TriggerEvent('fks-hud:client:horseGold', ped, which, secs)
        end
    end
    if goldRunning then return end
    goldRunning = true
    CreateThread(function()
        local boosted = { health = false, stamina = false }
        while true do
            local now = GetGameTimer()
            local h, s = goldUntil.health > now, goldUntil.stamina > now
            if not h and not s then break end
            local p = Horse.ped
            if p and DoesEntityExist(p) and not Horse.IsDown(p) then
                if h then boosted.health = true FillHealth(p) if Core(p, CORE_HEALTH) < 100 then SetCore(p, CORE_HEALTH, 100) end end
                if s then boosted.stamina = true FillStamina(p) if Core(p, CORE_STAMINA) < 100 then SetCore(p, CORE_STAMINA, 100) end end
            end
            Wait(0) -- every frame, so the ring does not move at all (infinite while it lasts)
        end
        -- end of the boost: fully recovered
        local p = Horse.ped
        if p and DoesEntityExist(p) and not Horse.IsDown(p) then
            if boosted.stamina then SetCore(p, CORE_STAMINA, 100) FillStamina(p) end
            if boosted.health then SetCore(p, CORE_HEALTH, 100) FillHealth(p) end
        end
        goldRunning = false
    end)
end

function Horse.Brush()
    if not NearOwnHorse() or Horse.IsDown(Horse.ped) then return Notify(_L('horse_too_far'), 'error') end
    if not lib.callback.await('fks-stables:consume', false, Config.Items.brush) then return end -- has a brush?
    local ped = Horse.ped
    -- the game's brushing animation, with the brush in hand (client/care.lua)
    if Care and Care.PlayBrush then
        if Care.Leading and Care.Leading() then Horse.StopLead() Wait(300) end
        Care.PlayBrush(ped)
    end
    if not Exists() then return end
    Citizen.InvokeNative(0xE3144B932DFDFF65, ped, 0.0, -1, 1, 1)
    ClearPedEnvDirt(ped)
    ClearPedDamageDecalByZone(ped, 10, 'ALL')
    ClearPedBloodDamage(ped)
    Citizen.InvokeNative(0xD8544F6260F5F01E, ped, 10)
    Horse.needs.dirt = 0
    Horse.acc.xp = Horse.acc.xp + Config.Level.xpBrush
    Horse.acc.bond = Horse.acc.bond + 1
    Horse.acc.affinity = (Horse.acc.affinity or 0) + ((Config.Affinity or {}).perFeed or 0)
    Notify(_L('horse_brushed', Horse.data.name), 'success')
end

---------------------------------------------------------------------------
-- Revive (Config.Items.reviver)
--  1. using the item shows a white dot on the body of every dead horse nearby (yours or others');
--  2. the player clicks the dot of the horse to revive (ESC / right click cancels);
--  3. walks to the horse, the server consumes the item and the horse's owner stands it up.
---------------------------------------------------------------------------
local RV = Config.Revive
local picking = nil -- { done, chosen }
Horse.selecting, Horse.reviving = false, false

local function HorseName(ent)
    return Entity(ent).state.fksName or (ent == Horse.ped and Horse.data and Horse.data.name) or nil
end

-- script horses dead nearby
local function DeadHorses()
    local me, list = GetEntityCoords(Me()), {}
    -- your own horse is always included (does not depend on the server mark nor the ped pool)
    if Exists() and Horse.IsDown(Horse.ped) and #(me - GetEntityCoords(Horse.ped)) <= RV.radius then
        list[1] = Horse.ped
    end
    for _, ent in ipairs(GetGamePool('CPed')) do
        if ent ~= Horse.ped and Entity(ent).state.fksHorse and Horse.IsDown(ent)
            and #(me - GetEntityCoords(ent)) <= RV.radius then
            list[#list + 1] = ent
        end
    end
    return list
end

-- point on the horse's body (spine bone; if missing, the entity centre)
local function BodyPos(ent)
    for _, bone in ipairs(RV.bones or {}) do
        local i = GetEntityBoneIndexByName(ent, bone)
        if i and i ~= -1 then return GetWorldPositionOfEntityBone(ent, i) end
    end
    return GetEntityCoords(ent) + vector3(0.0, 0.0, RV.offsetZ or 0.3)
end

RegisterNUICallback('pickHorse', function(d, cb)
    cb({})
    if not picking then return end
    picking.chosen = not d.cancel and tonumber(d.id) or nil
    picking.done = true
end)

function Horse.ReviveSelect()
    if Horse.selecting or Horse.reviving or Stable.open or Horse.cardOpen then return end
    local me = Me()
    if IsPedOnMount(me) or IsPedInAnyVehicle(me, false) then return end
    if #DeadHorses() == 0 then return Notify(_L('no_dead_horse'), 'error') end

    Horse.selecting = true
    local pick = { done = false }
    picking = pick
    SetNuiFocus(true, true)
    CreateThread(function()
        local limit, list = GetGameTimer() + (RV.timeout or 30) * 1000, {}
        while not pick.done do
            list = DeadHorses()
            me = Me()
            if #list == 0 or GetGameTimer() > limit or B(IsEntityDead(me)) or Stable.open then break end
            local dots = {}
            for _, ent in ipairs(list) do
                local p = BodyPos(ent)
                local on, sx, sy = GetScreenCoordFromWorldCoord(p.x, p.y, p.z)
                if on then dots[#dots + 1] = { id = ent, x = sx, y = sy, name = HorseName(ent) } end
            end
            SendNUIMessage({ action = 'pick', show = true, dots = dots, hint = _L('revive_choose') })
            Wait(100)
        end
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'pick', show = false })
        picking, Horse.selecting = nil, false

        local chosen
        for _, ent in ipairs(list) do if ent == pick.chosen then chosen = ent end end
        if chosen and DoesEntityExist(chosen) then
            Horse.ReviveAt(chosen)
        else
            Notify(_L('revive_cancelled'))
        end
    end)
end

-- walks to the chosen horse and revives it (the server validates and consumes the item)
function Horse.ReviveAt(ent)
    if Horse.reviving or not DoesEntityExist(ent) or not Horse.IsDown(ent) then return end
    Horse.reviving = true
    local me = Me()
    if #(GetEntityCoords(me) - GetEntityCoords(ent)) > 2.5 then
        TaskGoToEntity(me, ent, 15000, 1.5, 2.0, 0, 0)
        local t = GetGameTimer() + 15000
        while GetGameTimer() < t and DoesEntityExist(ent) and #(GetEntityCoords(me) - GetEntityCoords(ent)) > 2.0 do Wait(100) end
        ClearPedTasks(me, true, true)
    end
    if not DoesEntityExist(ent) or #(GetEntityCoords(me) - GetEntityCoords(ent)) > 3.0 then
        Horse.reviving = false
        return Notify(_L('horse_too_far'), 'error')
    end
    local name = HorseName(ent)
    local ok, msg = lib.callback.await('fks-stables:reviveHorse', false, NetworkGetNetworkIdFromEntity(ent),
        ent == Horse.ped and Horse.id or nil)
    if not ok then
        Horse.reviving = false
        return Notify(msg or _L('no_reviver'), 'error')
    end
    TaskAnimalInteraction(me, ent, -1355254781, joaat('consumable_horse_reviver'), 0)
    Wait(RV.duration or 4000)
    Horse.reviving = false
    -- the owner gets the notice in the event below; whoever revived someone else's horse is notified too
    if ent ~= Horse.ped and name then Notify(_L('horse_revived', name), 'success') end
end

-- the server confirmed the revive: whoever has the horse (the owner) stands it up
RegisterNetEvent('fks-stables:client:horseRevived', function(id, by)
    if Horse.id ~= id or not Exists() then return end
    local ped = Horse.ped
    NetworkRequestControlOfEntity(ped)
    local t = GetGameTimer() + 1500
    while not NetworkHasControlOfEntity(ped) and GetGameTimer() < t do Wait(50) NetworkRequestControlOfEntity(ped) end
    ResurrectPed(ped)
    ReviveInjuredPed(ped)
    SetEntityHealth(ped, GetEntityMaxHealth(ped), 0)
    ClearPedTasksImmediately(ped)
    Wait(200)
    if Horse.IsDown(ped) then return end -- did not stand up: still dead (also in the database)
    Setup(ped) -- becomes your horse again (mount, prompts, personality)
    Horse.label = nil
    Horse.UpdateLabel()
    Horse.AddBlip(ped, Horse.data.name)
    SetCore(ped, CORE_HEALTH, RV.health or 50)
    TriggerServerEvent('fks-stables:server:horseAlive', id)
    Horse.deadAt = nil
    Horse.ApplyAttributes()
    SendState(true)
    if by == GetPlayerServerId(PlayerId()) then
        Notify(_L('horse_revived', Horse.data.name), 'success')
    else
        Notify(_L('horse_revived_by', Horse.data.name), 'success')
    end
end)

RegisterNetEvent('fks-stables:client:useItem', function(kind, item)
    if kind == 'feed' then Horse.Feed(item)
    elseif kind == 'brush' then Horse.Brush()
    elseif kind == 'revive' then Horse.ReviveSelect()
    elseif kind == 'rename' then CreateThread(Horse.TagRename)
    elseif kind == 'repair' and Wagon then Wagon.Repair() end
end)

---------------------------------------------------------------------------
-- Horse sheet (NUI panel, opened by the native "Show Info" — Q)
---------------------------------------------------------------------------
Horse.cardOpen = false

local function CardData()
    local d, n, ped = Horse.data, Horse.needs, Horse.ped
    local st = {}
    for k, v in pairs(d.stats or {}) do st[k] = v end
    if d.fixedStats then
        st.speed, st.accel = d.fixedStats[1], d.fixedStats[2]
        st.handling = math.min(4, math.max(1, math.ceil(d.fixedStats[3] / 2.5)))
    end
    return {
        name = d.name, breed = d.breed, coat = d.coatLabel, tier = d.tier, gender = d.gender,
        age = d.age, old = d.old, xp = math.min(d.xp or 0, FKS.MaxXp(d.tier)), xpMax = FKS.MaxXp(d.tier), bond = d.bond,
        storage = d.storage, pelts = d.pelts, stats = st,
        courage = math.floor((d.courage or 0) * 10) / 10, affinity = math.floor((d.affinity or 0) * 10) / 10,
        live = {
            health = Exists() and Core(ped, CORE_HEALTH) or 0,
            stamina = Exists() and Core(ped, CORE_STAMINA) or 0,
            hunger = math.floor(n.hunger), thirst = math.floor(n.thirst),
            clean = math.floor(100 - n.dirt), hoof = math.floor(n.hoof or 100),
        },
    }
end

function Horse.CloseCard()
    if not Horse.cardOpen then return end
    Horse.cardOpen = false
    SendNUIMessage({ action = 'card', show = false })
end

local CLOSE_KEYS = { 0x31219490, 0xDE794E3E, 0x156F7119, 0x4A903C11 } -- Q (focused), Q (on foot), Backspace, ESC

function Horse.Card()
    if not Horse.data or not Exists() or Horse.cardOpen then return end
    Horse.cardOpen = true
    SendNUIMessage({ action = 'card', show = true, horse = CardData(), locale = LocaleUI })
    CreateThread(function()
        Wait(400) -- ignore the Q that opened the sheet
        local limit, nextUpdate = GetGameTimer() + 30000, 0
        while Horse.cardOpen do
            Wait(0)
            for _, k in ipairs(CLOSE_KEYS) do
                if IsControlJustReleased(0, k) or IsDisabledControlJustReleased(0, k) then Horse.CloseCard() break end
            end
            if Horse.cardOpen and GetGameTimer() > nextUpdate then
                nextUpdate = GetGameTimer() + 1000
                -- closes when you walk away, open the stable or after 30 s
                if not Exists() or Stable.open or GetGameTimer() > limit
                    or #(GetEntityCoords(Me()) - GetEntityCoords(Horse.ped)) > 8.0 then
                    Horse.CloseCard()
                else
                    SendNUIMessage({ action = 'card', show = true, horse = CardData(), locale = LocaleUI })
                end
            end
        end
    end)
end
Horse.Sheet = Horse.Card

---------------------------------------------------------------------------
-- Keys
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(0)
        if not Stable.open and IsControlJustReleased(0, Config.Keys.whistle) and not IsPedInAnyVehicle(Me(), false) then
            local mount = GetMount(Me())
            if mount == 0 or mount ~= Horse.ped then Horse.Whistle() end
        end
    end
end)

-- Native "Flee" (F when looking at the horse): the game only fires EVENT_PLAYER_PROMPT_TRIGGERED
-- (type 33 = flee, with the target entity in the 3rd field). We catch it and send the horse to the stable.
local EVENT_PROMPT = joaat('EVENT_PLAYER_PROMPT_TRIGGERED')
local PROMPT_FLEE = 33

CreateThread(function()
    while true do
        if Exists() and not Horse.fleeing then
            Wait(0)
            local n = GetNumberOfEvents(0)
            for i = 0, n - 1 do
                if GetEventAtIndex(0, i) == EVENT_PROMPT then
                    local blob = string.rep('\0', 8 * 10)
                    if Citizen.InvokeNative(0x57EC5FA4D4D6AFCA, 0, i, blob, 10) then -- GetEventData
                        local kind = string.unpack('<i4', blob, 1)
                        local target = string.unpack('<i4', blob, 17)
                        if kind == PROMPT_FLEE and target == Horse.ped then Horse.Flee() end
                    end
                end
            end
        else
            Wait(500)
        end
    end
end)

-- fallback: if the horse flees for another reason (e.g. spooked) while not mounted, it is stored too
CreateThread(function()
    while true do
        Wait(1000)
        if Exists() and not Horse.fleeing and not Horse.IsDown(Horse.ped)
            and GetMount(Me()) ~= Horse.ped and IsPedFleeing(Horse.ped)
            and #(GetEntityCoords(Me()) - GetEntityCoords(Horse.ped)) > 40.0 then
            Horse.Flee()
        end
    end
end)

---------------------------------------------------------------------------
-- Relog / crash: the horse comes back where it was
---------------------------------------------------------------------------
local function RestoreAfterLogin()
    if not Config.Horse.respawnAfterLogin then return end
    local data = lib.callback.await('fks-stables:getActive', false, 'horse')
    if data and data.spawned and not data.dead and data.position then
        local p = data.position
        Horse.Spawn(data, vector4(p[1], p[2], p[3], p[4] or 0.0), true)
    end
end

local function OnLoaded()
    Wait(5000)
    RestoreAfterLogin()
    if Wagon then Wagon.RestoreAfterLogin() end
end

-- rsg-core / vorp_core
RegisterNetEvent('RSGCore:Client:OnPlayerLoaded', OnLoaded)
RegisterNetEvent('vorp:SelectedCharacter', OnLoaded)

-- resource restart with the player already in game (the server returns nothing if there is no character)
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    Wait(3000)
    RestoreAfterLogin()
    if Wagon then Wagon.RestoreAfterLogin() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if Horse.blip then RemoveBlip(Horse.blip) end
    if Exists() then DeleteEntity(Horse.ped) end
end)

-- Diagnostics: /fks_horse (result in the F8 console) — your horse state for death / revive
RegisterCommand('fks_horse', function()
    local ped = Horse.ped
    if not ped or not DoesEntityExist(ped) then return print('[fks-stables] you have no horse out') end
    print(('[fks-stables] horse %s · dead=%s fatally=%s injured=%s health=%s/%s core=%s · IsDown=%s · deadAt=%s · dist=%.1f · statebag=%s'):format(
        tostring(Horse.id), tostring(IsEntityDead(ped)), tostring(IsPedFatallyInjured(ped)), tostring(IsPedInjured(ped)),
        GetEntityHealth(ped), GetEntityMaxHealth(ped), Core(ped, CORE_HEALTH), tostring(Horse.IsDown(ped)),
        tostring(Horse.deadAt), #(GetEntityCoords(Me()) - GetEntityCoords(ped)), tostring(Entity(ped).state.fksHorse)))
end, false)

exports('GetHorse', function() return Horse.ped end)
exports('GetHorseData', function() return Horse.data end)
exports('FleeHorse', function() Horse.Despawn(false) end)
