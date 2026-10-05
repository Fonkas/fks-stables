-- Horse care: only while leading (Lead).
--   Feed (items) · Drink (river / trough) · Eat hay (map props) · Brush · Clean hooves

Care = { busy = false, inWater = false, trough = false, hay = false }

local K, C = Config.Prompts, Config.Care

local function Me() return PlayerPedId() end
local function Var(text) return CreateVarString(10, 'LITERAL_STRING', text) end
local function Notify(msg, kind)
    lib.notify({ title = Horse.data and Horse.data.name or _L('stable'), description = msg, type = kind or 'inform' })
end

local function Make(group, key, text, hold)
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

local function Show(p, on) PromptSetVisible(p, on) PromptSetEnabled(p, on) end
local function Done(p, hold)
    if hold then return PromptHasHoldModeCompleted(p) end
    return PromptHasStandardModeCompleted(p)
end

local function HorseOk()
    return Horse.ped and DoesEntityExist(Horse.ped) and not Horse.IsDown(Horse.ped)
end

-- Is the player leading their horse by the reins?
local function Leading()
    if not HorseOk() then return false end
    local led = Citizen.InvokeNative(0xED1F514AF4732258, Me()) -- GetLedHorseFromPed
    if led and led ~= 0 then return led == Horse.ped end
    return Citizen.InvokeNative(0xEFC4303DDC6E60D3, Me()) -- IsPedLeadingHorse
        and #(GetEntityCoords(Me()) - GetEntityCoords(Horse.ped)) < 4.0
end


---------------------------------------------------------------------------
-- Detection of water / troughs / hay next to the horse
---------------------------------------------------------------------------
local function ToHash(m) return type(m) == 'number' and m or joaat(m) end
local troughHashes, hayHashes = {}, {}
for _, m in ipairs(C.drink.troughs) do troughHashes[#troughHashes + 1] = ToHash(m) end
for _, m in ipairs(C.hay.props) do hayHashes[#hayHashes + 1] = ToHash(m) end

local function NearAny(pos, hashes, radius)
    for _, h in ipairs(hashes) do
        if GetClosestObjectOfType(pos.x, pos.y, pos.z, radius, h, false, false, false) ~= 0 then return true end
    end
    return false
end

CreateThread(function()
    while true do
        if HorseOk() and Leading() then
            local p = GetEntityCoords(Horse.ped)
            -- the horse's head is in front: search around a point 1m ahead
            local head = GetOffsetFromEntityInWorldCoords(Horse.ped, 0.0, 1.2, 0.0)
            Care.inWater = IsEntityInWater(Horse.ped)
            Care.trough = not Care.inWater and NearAny(head, troughHashes, C.drink.troughDistance)
            Care.hay = NearAny(head, hayHashes, C.hay.distance) or NearAny(p, hayHashes, C.hay.distance)
            Wait(500)
        else
            Care.inWater, Care.trough, Care.hay = false, false, false
            Wait(1000)
        end
    end
end)

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
-- Animation on the horse itself (lowers the head and raises it again at the end).
-- While being led, the horse has the "follow the reins" task, which would cancel the animation:
-- we stop that task and hold it in place during the animation.
-- Current stamina (the icon's ring): raised by a percentage of the max stamina
-- (same natives fks-hud uses: GetPedMaxStamina / ChangePedStamina by hash, returning a float)
local function AddStaminaBar(ped, percent)
    if not percent or percent <= 0 or not DoesEntityExist(ped) then return end
    local max = Citizen.InvokeNative(0xCB42AFE2B613EE55, ped, Citizen.ResultAsFloat()) or 100.0 -- GetPedMaxStamina
    if max <= 0 then max = 100.0 end
    Citizen.InvokeNative(0xC3D4B754C0E86B9E, ped, max * percent / 100.0)                       -- ChangePedStamina
end

local function Animate(ped, a, duration, key, perSecond)
    local dict, clip = a[1], a[2]
    RequestAnimDict(dict)
    local t = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(10) end
    if not HasAnimDictLoaded(dict) then
        print(('[fks-stables] animation %s did not load: %s'):format(key, dict))
        return
    end

    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, true)
    TaskPlayAnim(ped, dict, clip, 1.0, 1.0, duration, 1, 0, 1, 0, 0, 0, 0)
    if Config.Debug then
        Wait(300)
        print(('[fks-stables] %s: %s / %s · playing = %s'):format(key, dict, clip, tostring(IsEntityPlayingAnim(ped, dict, clip, 3))))
    end

    local stop, nextTick = GetGameTimer() + duration, GetGameTimer() + 1000
    while GetGameTimer() < stop and HorseOk() do
        Wait(200)
        if perSecond and GetGameTimer() >= nextTick then
            nextTick = nextTick + 1000
            perSecond()
        end
    end
    if DoesEntityExist(ped) then
        StopAnimTask(ped, dict, clip, 1.0)
        FreezeEntityPosition(ped, false)
    end
    RemoveAnimDict(dict)
end

-- Drop the reins: the player stops leading (the leading task would cancel the horse animations)
Care.Leading = Leading

local function DropReins()
    local me = Me()
    if not Leading() then return end
    Horse.StopLead()
    local t = GetGameTimer() + 1500
    while Leading() and GetGameTimer() < t do Wait(50) end
    if Leading() then ClearPedTasksImmediately(me) Wait(100) end
    if HorseOk() then ClearPedTasks(Horse.ped, true, true) end
end

function Care.FeedMenu()
    if Care.busy then return end
    local items = lib.callback.await('fks-stables:feedItems', false) or {}
    if #items == 0 then return Notify(_L('no_horse_food'), 'error') end
    if #items == 1 then return Horse.Feed(items[1].item) end
    local opts = {}
    for _, it in ipairs(items) do
        local f = Config.Feed[it.item]
        opts[#opts + 1] = {
            title = ('%s  ×%s'):format(it.label, it.count),
            description = _L('feed_desc', f.health or 0, f.stamina or 0, f.hunger or 0),
            icon = 'apple-whole',
            onSelect = function() Horse.Feed(it.item) end,
        }
    end
    lib.registerContext({ id = 'fks_feed', title = _L('feed_title', Horse.data.name), options = opts })
    lib.showContext('fks_feed')
end

function Care.Drink()
    if Care.busy or not HorseOk() then return end
    if not (Care.inWater or Care.trough) then return Notify(_L('not_near_water'), 'error') end
    Care.busy = true
    DropReins()
    Notify(_L('horse_drinking', Horse.data.name))
    local d, secs = C.drink, math.max(1, math.floor(C.drink.duration / 1000))
    Animate(Horse.ped, Care.inWater and d.anim or d.troughAnim, d.duration, 'drink', function()
        Horse.Gain({ thirst = d.thirst / secs, stamina = d.stamina / secs, health = d.health / secs })
        AddStaminaBar(Horse.ped, (d.staminaBar or 0) / secs)
    end)
    Care.busy = false
end

function Care.EatHay()
    if Care.busy or not HorseOk() then return end
    if not Care.hay then return Notify(_L('not_near_hay'), 'error') end
    Care.busy = true
    DropReins()
    Notify(_L('horse_eating', Horse.data.name))
    local h, secs = C.hay, math.max(1, math.floor(C.hay.duration / 1000))
    Animate(Horse.ped, h.anim, h.duration, 'hay', function()
        Horse.Gain({ hunger = h.hunger / secs, stamina = h.stamina / secs, health = h.health / secs })
        AddStaminaBar(Horse.ped, (h.staminaBar or 0) / secs)
    end)
    Care.busy = false
end

-- Rest / sleep: animations played on the horse itself (lie down -> pose -> stand up)
Care.resting = nil -- 'rest' | 'sleep'
local restAnim = nil  -- { dict, clip } of the current pose

local function LoadDict(dict)
    if not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function AnimMs(dict, clip, fallback)
    local ok, d = pcall(GetAnimDuration, dict, clip)
    return (ok and d and d > 0) and math.floor(d * 1000) or fallback
end

function Care.StandUp(silent, instant)
    if not Care.resting then return end
    local kind = Care.resting
    Care.resting = nil
    if not HorseOk() then return end
    local ped, cfg = Horse.ped, kind == 'sleep' and C.sleep or C.rest
    if not instant and cfg.exit and LoadDict(cfg.exit[1]) then
        TaskPlayAnim(ped, cfg.exit[1], cfg.exit[2], 1.0, 1.0, -1, 0, 0, 0, 0, 0, 0, 0)
        Wait(AnimMs(cfg.exit[1], cfg.exit[2], 2500))
    end
    if restAnim then StopAnimTask(ped, restAnim[1], restAnim[2], 1.0) restAnim = nil end
    ClearPedTasks(ped, true, true)
    FreezeEntityPosition(ped, false)
    if not silent then Notify(_L('horse_stood_up', Horse.data.name)) end
end

function Care.Rest(kind)
    if Care.busy or Care.resting or not HorseOk() then return end
    local cfg = kind == 'sleep' and C.sleep or C.rest
    DropReins()
    local ped = Horse.ped

    -- first pose that exists in the game
    local loop
    for _, a in ipairs(cfg.loop) do
        if LoadDict(a[1]) then loop = a break end
    end
    if not loop then return Notify(_L('anim_missing'), 'error') end
    if Config.Debug then print(('[fks-stables] %s: pose %s / %s'):format(kind, loop[1], loop[2])) end

    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, true)
    Care.resting = kind
    Notify(_L(kind == 'sleep' and 'horse_sleeping' or 'horse_resting', Horse.data.name))

    if cfg.enter and LoadDict(cfg.enter[1]) then
        TaskPlayAnim(ped, cfg.enter[1], cfg.enter[2], 1.0, 1.0, -1, 2, 0, 0, 0, 0, 0, 0) -- 2 = hold the last frame
        Wait(AnimMs(cfg.enter[1], cfg.enter[2], 3000))
    end
    if Care.resting ~= kind then return end
    TaskPlayAnim(ped, loop[1], loop[2], 1.0, 1.0, -1, 1, 0, 0, 0, 0, 0, 0) -- 1 = loop
    restAnim = loop

    CreateThread(function()
        local nextGain = GetGameTimer() + cfg.tick * 1000
        while Care.resting == kind and Horse.ped == ped do
            Wait(200)
            if Care.resting ~= kind then break end
            if not HorseOk() then
                Care.resting, restAnim = nil, nil
                if DoesEntityExist(ped) then FreezeEntityPosition(ped, false) end
                break
            end
            -- the player mounted: release the horse right away, no stand-up animation
            local me = Me()
            if GetMount(me) == ped or (IsPedOnMount(me) and #(GetEntityCoords(me) - GetEntityCoords(ped)) < 3.0) then
                Care.StandUp(true, true)
                break
            end
            if GetGameTimer() >= nextGain then
                nextGain = GetGameTimer() + cfg.tick * 1000
                -- if something cut the pose, put it back
                if not (IsEntityPlayingAnim(ped, loop[1], loop[2], 3) == true or IsEntityPlayingAnim(ped, loop[1], loop[2], 3) == 1) then -- (the native may return 0/1)
                    TaskPlayAnim(ped, loop[1], loop[2], 1.0, 1.0, -1, 1, 0, 0, 0, 0, 0, 0)
                end
                Horse.Gain({ stamina = cfg.stamina, health = cfg.health })
            end
        end
    end)
end

-- Prop in hand (brush / hoof pick). models: a name or a list (uses the first that exists)
local function HandProp(models, bone, off)
    if type(models) == 'string' then models = { models } end
    for _, m in ipairs(models or {}) do
        local hash = joaat(m)
        if IsModelValid(hash) then
            RequestModel(hash)
            local t = GetGameTimer() + 2000
            while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(10) end
            if HasModelLoaded(hash) then
                local me = Me()
                local c = GetEntityCoords(me)
                local obj = CreateObject(hash, c.x, c.y, c.z, true, true, false)
                off = off or { 0, 0, 0, 0, 0, 0 }
                AttachEntityToEntity(obj, me, GetEntityBoneIndexByName(me, bone or 'SKEL_R_HAND'),
                    off[1], off[2], off[3], off[4], off[5], off[6], true, true, false, true, 1, true)
                SetModelAsNoLongerNeeded(hash)
                return obj
            end
        end
    end
end

local function DeleteProp(obj)
    if obj and DoesEntityExist(obj) then
        DetachEntity(obj, true, true)
        DeleteEntity(obj)
    end
end

-- Brush: the game's own interaction (Interaction_Brush, hash 554992710 — same as redm-mount and vorp_stables)
-- with the brush in hand. The player drops the reins first (while leading, the interaction does not start well).
function Care.PlayBrush(horse)
    local B = Config.Brush
    Care.busy = true
    if Leading() then Horse.StopLead() Wait(500) end
    ClearPedTasks(horse, true, true)
    Citizen.InvokeNative(0xCD181A959CFDD7F4, Me(), horse, joaat(B.interaction or 'Interaction_Brush'),
        Config.Items.brushProp and joaat(Config.Items.brushProp) or 0, 0) -- TaskAnimalInteraction
    Wait(B.duration or 8000)
    Care.busy = false
end

-- Two-actor scene (horse + player): the game says where each participant starts relative to the scene origin
-- (GetAnimInitialOffsetPosition / Rotation). The horse stays where it is; the origin is computed from it
-- and the player is placed at their starting point — so they end up holding the leg.
local function Rot2D(v, deg)
    local r = math.rad(deg)
    local c, s2 = math.cos(r), math.sin(r)
    return vector3(v.x * c - v.y * s2, v.x * s2 + v.y * c, v.z)
end

local function InitialOffset(dict, clip)
    if not GetAnimInitialOffsetPosition or not GetAnimInitialOffsetRotation then return nil end
    local ok1, p = pcall(GetAnimInitialOffsetPosition, dict, clip, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2)
    local ok2, r = pcall(GetAnimInitialOffsetRotation, dict, clip, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2)
    if ok1 and ok2 and p and r then return p, r end
end

-- returns the position and heading where the player should start
local function PlayerStart(horse, dict, horseClip, playerClip, fallback)
    local hp, hh = GetEntityCoords(horse), GetEntityHeading(horse)
    local offH, rotH = InitialOffset(dict, horseClip)
    local offP, rotP = InitialOffset(dict, playerClip)
    if offH and offP then
        local sceneH = hh - rotH.z
        local origin = hp - Rot2D(offH, sceneH)
        local pos = origin + Rot2D(offP, sceneH)
        if Config.Debug then
            print(('[fks-stables] scene %s: horse %s / %.1f · player %s / %.1f'):format(dict, tostring(offH), rotH.z, tostring(offP), rotP.z))
        end
        return vector3(pos.x, pos.y, hp.z), sceneH + rotP.z
    end
    -- fallback (natives unavailable): fixed position from the config, relative to the horse
    local f = fallback or { -0.6, -0.9, 0.0, 200.0 }
    local pos = GetOffsetFromEntityInWorldCoords(horse, f[1], f[2], f[3])
    if Config.Debug then print('[fks-stables] GetAnimInitialOffset* unavailable - using Config.Care.hoof.fallback') end
    return pos, hh + f[4]
end

-- Clean hooves: "stranded rider" scene — the player behind the horse, holding the hind leg
function Care.CleanHooves()
    if Care.busy or not HorseOk() then return end
    if not lib.callback.await('fks-stables:consume', false, C.hoof.item) then
        return Notify(_L('need_hoof_tool'), 'error')
    end
    local an = C.hoof.anim
    if not LoadDict(an.dict) then return Notify(_L('anim_missing'), 'error') end
    Care.busy = true
    DropReins()
    local me, horse = Me(), Horse.ped

    ClearPedTasksImmediately(horse)
    FreezeEntityPosition(horse, true) -- the horse does not move during the scene
    local pos, hd = PlayerStart(horse, an.dict, an.horse, an.player, C.hoof.fallback)
    ClearPedTasksImmediately(me)
    SetEntityCoordsNoOffset(me, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(me, hd)

    local prop = HandProp(C.hoof.props, C.hoof.propBone, C.hoof.propOffset)
    TaskPlayAnim(horse, an.dict, an.horse, 8.0, -8.0, -1, 1, 0, false, false, false)
    TaskPlayAnim(me, an.dict, an.player, 8.0, -8.0, -1, 1, 0, false, false, false)

    local stop = GetGameTimer() + (C.hoof.duration or 9000)
    while GetGameTimer() < stop and HorseOk() do Wait(200) end

    DeleteProp(prop)
    StopAnimTask(me, an.dict, an.player, 1.0)
    ClearPedTasks(me, true, true)
    if HorseOk() then StopAnimTask(horse, an.dict, an.horse, 1.0) ClearPedTasks(horse, true, true) end
    if DoesEntityExist(horse) then FreezeEntityPosition(horse, false) end
    RemoveAnimDict(an.dict)

    Horse.needs.hoof = 100
    Horse.Gain({ xp = C.hoof.xp, bond = C.hoof.bond })
    Notify(_L('horse_hooves_clean', Horse.data.name), 'success')
    Care.busy = false
end

---------------------------------------------------------------------------
-- Prompts (own group, shown while leading or mounted and stopped)
---------------------------------------------------------------------------
local G = GetRandomIntInRange(0, 0xffffff)
local P = {}

CreateThread(function()
    Wait(1000)
    P.stop = Make(G, K.stopLead, _L('c_stop_lead'))
    P.rest = Make(G, K.careRest, _L('c_rest'))
    P.sleep = Make(G, K.careSleep, _L('c_sleep'))
    P.feed = Make(G, K.careFeed, _L('c_feed'))
    -- Drink and Eat hay: each only works next to its prop (otherwise it warns)
    P.drink = Make(G, K.careDrink, _L('c_drink'))
    P.hay = Make(G, K.careHay, _L('c_hay'))
    P.brush = Make(G, K.careBrush, _L('c_brush'), true)
    P.hoof = Make(G, K.careHoof, _L('c_hoof'), true)
    P.train = Make(G, Config.Training.key, _L('c_train'))   -- trainer / admin only

    while true do
        if not Stable.open and not Care.busy and not Horse.busy and Leading() then
            Wait(0)
            Show(P.train, Training ~= nil and Training.isTrainer and not Training.active)
            PromptSetActiveGroupThisFrame(G, Var(Horse.data and Horse.data.name or ''))
            -- fallback: the raw F (0xB2F377E8) drops the reins even if the prompt does not show
            if Done(P.stop) or IsControlJustReleased(0, 0xB2F377E8) or IsDisabledControlJustReleased(0, 0xB2F377E8) then
                Horse.StopLead(); Wait(300)
            elseif Done(P.rest) then
                CreateThread(function() Care.Rest('rest') end); Wait(300)
            elseif Done(P.sleep) then
                CreateThread(function() Care.Rest('sleep') end); Wait(300)
            elseif Done(P.feed) then
                Care.FeedMenu(); Wait(300)
            elseif Done(P.drink) then
                CreateThread(Care.Drink); Wait(300)   -- warns if not next to water
            elseif Done(P.hay) then
                CreateThread(Care.EatHay); Wait(300)  -- warns if not next to hay
            elseif Done(P.brush, true) then
                CreateThread(Horse.Brush); Wait(300)
            elseif Done(P.hoof, true) then
                CreateThread(Care.CleanHooves); Wait(300)
            elseif Training and Training.isTrainer and Done(P.train) then
                Training.Menu(); Wait(300)
            end
        else
            Wait(250)
        end
    end
end)

-- Diagnostics: /fks_props — lists objects within 4 m (F8 console) and says if they are a trough / hay
RegisterCommand('fks_props', function()
    if not Config.Debug then return end
    local me = GetEntityCoords(Me())
    local known = {}
    for _, m in ipairs(C.drink.troughs) do known[ToHash(m)] = 'trough (' .. tostring(m) .. ')' end
    for _, m in ipairs(C.hay.props) do known[ToHash(m)] = 'hay (' .. tostring(m) .. ')' end
    print('[fks-stables] objects within 4 m:')
    for _, obj in ipairs(GetGamePool('CObject')) do
        local d = #(me - GetEntityCoords(obj))
        if d < 4.0 then
            local h = GetEntityModel(obj)
            print(('  hash %s (0x%08X)  %.1fm  %s'):format(h, h & 0xFFFFFFFF, d, known[h] or '-- unknown: add this hash to Config.Care'))
        end
    end
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, p in pairs(P) do PromptDelete(p) end
end)
