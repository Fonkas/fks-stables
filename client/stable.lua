Stable = {
    open = false,
    current = nil,      -- config of the open stable
    data = nil,         -- player data (horses, wagons, shop, money)
    cam = nil,
    fov = 45.0,
    preview = nil,      -- entity on display
    previewKind = nil,  -- 'horse' | 'wagon'
    previewModel = nil,
    previewLook = nil,  -- current look (horse) / custom (wagon)
    token = 0,
}

local npcs, blips = {}, {}
Stable.npcs = npcs

-- foals on display / at the breeding spot: the game resets the size when the look updates, so it is
-- reapplied all the time (like county-ranch)
local scaled = {} -- [ped] = scale
function Stable.KeepScale(ped, scale)
    scaled[ped] = (scale and scale < 0.999) and scale or nil
    SetPedScale(ped, (scale or 1.0) + 0.0)
end
CreateThread(function()
    while true do
        local any = false
        for ped, sc in pairs(scaled) do
            if DoesEntityExist(ped) then any = true SetPedScale(ped, sc + 0.0) else scaled[ped] = nil end
        end
        Wait(any and 250 or 1000)
    end
end)

local function Notify(msg, kind)
    lib.notify({ title = _L('stable'), description = msg, type = kind or 'inform' })
end

---------------------------------------------------------------------------
-- Stable hands and blips
---------------------------------------------------------------------------
local function IsOpenNow(s)
    if not s.hours then return true end
    local h = GetClockHours()
    local o, c = s.hours[1], s.hours[2]
    if o < c then return h >= o and h < c end
    return h >= o or h < c
end

CreateThread(function()
    for _, s in ipairs(Config.Stables) do
        if s.blip then
            local c = s.npc.coords
            local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, c[1], c[2], c[3]) -- BlipAddForCoords
            SetBlipSprite(blip, Config.Blip.sprite, true)
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, s.label)                             -- SetBlipName
            blips[#blips + 1] = blip
        end
    end

    while true do
        local pos = GetEntityCoords(PlayerPedId())
        for _, s in ipairs(Config.Stables) do
            local c = s.npc.coords
            local near = #(pos - vector3(c[1], c[2], c[3])) < Config.NpcDistance
            if near and not npcs[s.id] then
                local hash = Look.LoadModel(s.npc.model)
                if hash then
                    local ped = CreatePed(hash, c[1], c[2], c[3], c[4] or 0.0, false, false, false, false)
                    Citizen.InvokeNative(0x283978A15512B2FE, ped, true) -- SetRandomOutfitVariation
                    SetEntityInvincible(ped, true)
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    FreezeEntityPosition(ped, true)
                    SetModelAsNoLongerNeeded(hash)
                    npcs[s.id] = ped
                end
            elseif not near and npcs[s.id] then
                DeleteEntity(npcs[s.id])
                npcs[s.id] = nil
            end
        end
        Wait(1500)
    end
end)

function Stable.Nearest(maxDist)
    local pos = GetEntityCoords(PlayerPedId())
    local best, bestD
    for _, s in ipairs(Config.Stables) do
        local c = s.npc.coords
        local d = #(pos - vector3(c[1], c[2], c[3]))
        if not bestD or d < bestD then best, bestD = s, d end
    end
    if maxDist and (not bestD or bestD > maxDist) then return nil end
    return best, bestD
end

---------------------------------------------------------------------------
-- Camera and showroom
---------------------------------------------------------------------------
local function PreviewPoint(kind)
    local s = Stable.current
    local p = (kind == 'wagon' and s.wagonPreview) or s.preview
    return vector3(p[1], p[2], p[3]), p[4]
end

-- Camera direction: from the display point to the configured camera (or by heading if they overlap)
local function CameraDir()
    local s = Stable.current
    local p = vector3(s.preview[1], s.preview[2], s.preview[3])
    local c = vector3(s.camera[1], s.camera[2], s.camera[3])
    local flat = vector3(c.x - p.x, c.y - p.y, 0.0)
    if #flat < 2.5 then
        local h = math.rad(s.camera[4] or 0.0)
        flat = vector3(math.sin(h), -math.cos(h), 0.0) -- behind the camera heading
    end
    return flat / #flat
end

local function PlaceCamera(kind)
    local p = PreviewPoint(kind)
    local dir = CameraDir()
    local dist, height, look = 5.2, 1.3, 0.9
    if kind == 'wagon' then dist, height, look = 9.5, 2.6, 1.2 end
    local pos = p + dir * dist + vector3(0.0, 0.0, height)

    if not Stable.cam then
        Stable.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        SetCamFov(Stable.cam, Stable.fov)
        SetCamCoord(Stable.cam, pos.x, pos.y, pos.z)
        PointCamAtCoord(Stable.cam, p.x, p.y, p.z + look)
        SetCamActive(Stable.cam, true)
        RenderScriptCams(true, true, 700, true, true)
    else
        SetCamCoord(Stable.cam, pos.x, pos.y, pos.z)
        PointCamAtCoord(Stable.cam, p.x, p.y, p.z + look)
    end
end

-- The animal stands sideways to the camera
local function SideHeading()
    local d = CameraDir()
    return (GetHeadingFromVector_2d(d.x, d.y) + 90.0) % 360.0
end

local function ClearPreview()
    if Stable.preview and DoesEntityExist(Stable.preview) then DeleteEntity(Stable.preview) end
    Stable.preview, Stable.previewKind, Stable.previewModel, Stable.previewLook = nil, nil, nil, nil
end

function Stable.ShowHorse(model, look)
    Stable.token = Stable.token + 1
    local my = Stable.token
    local hash = Look.LoadModel(model)
    if not hash or my ~= Stable.token or not Stable.open then return end

    local ped = Stable.preview
    if not (ped and Stable.previewKind == 'horse' and Stable.previewModel == hash and DoesEntityExist(ped)) then
        ClearPreview()
        local p = PreviewPoint('horse')
        ped = CreatePed(hash, p.x, p.y, p.z, SideHeading(), false, false, false, false)
        SetEntityAlpha(ped, 0, false)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        FreezeEntityPosition(ped, true)
        SetModelAsNoLongerNeeded(hash)
        Stable.preview, Stable.previewKind, Stable.previewModel = ped, 'horse', hash
    end
    PlaceCamera('horse')
    Look.ApplyHorse(ped, look)
    Stable.KeepScale(ped, look.scale) -- foals are smaller
    if my ~= Stable.token then return end
    Stable.previewLook = look
    ResetEntityAlpha(ped)
end

function Stable.ShowWagon(model, custom)
    Stable.token = Stable.token + 1
    local my = Stable.token
    local hash = Look.LoadModel(model)
    if not hash or my ~= Stable.token or not Stable.open then return end

    ClearPreview()
    local p = PreviewPoint('wagon')
    local veh = CreateVehicle(hash, p.x, p.y, p.z, SideHeading(), false, false, false, false)
    SetEntityInvincible(veh, true)
    FreezeEntityPosition(veh, true)
    SetModelAsNoLongerNeeded(hash)
    Stable.preview, Stable.previewKind, Stable.previewModel = veh, 'wagon', hash
    PlaceCamera('wagon')
    Look.ApplyWagon(veh, model, custom)
    Stable.previewLook = custom
end

-- studio light while the menu is open
local function LightThread()
    CreateThread(function()
        while Stable.open do
            if Stable.preview and DoesEntityExist(Stable.preview) then
                local c = GetEntityCoords(Stable.preview)
                local d = CameraDir()
                DrawLightWithRange(c.x + d.x * 3.0, c.y + d.y * 3.0, c.z + 2.0, 255, 236, 205, 9.0, 18.0)
            end
            DisableAllControlActions(0)
            Wait(0)
        end
    end)
end

---------------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------------
local function UIConfig()
    local max = {}
    for cat, list in pairs(Config.HorseComponents) do max[cat] = #list end
    return {
        componentMax = max,
        categories = Look.Categories,
        palettes = #Config.ColorPalettes,
        prices = Config.Prices,
        transferPrice = Config.TransferPrice,
        keepAtStable = Config.KeepAtStable,
        stables = (function()
            local t = {}
            for _, s in ipairs(Config.Stables) do t[#t + 1] = { id = s.id, label = s.label } end
            return t
        end)(),
    }
end

function Stable.Open(id)
    if Stable.open then return end
    local s = FKS.StableById[id]
    if not s then return end
    if not IsOpenNow(s) then return Notify(_L('closed', s.hours[1]), 'error') end

    local data = lib.callback.await('fks-stables:getData', false, id, true)
    if not data then return end
    if data.denied then return Notify(_L('no_access'), 'error') end

    Stable.open, Stable.current, Stable.data = true, s, data
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    DisplayRadar(false)
    LightThread()

    SendNUIMessage({
        action = 'open',
        stable = { id = s.id, label = s.label, services = s.services, hours = s.hours },
        data = data,
        locale = LocaleUI,
        config = UIConfig(),
    })
    SetNuiFocus(true, true)
end

function Stable.Close()
    if not Stable.open then return end
    Stable.open = false
    Stable.token = Stable.token + 1
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    ClearPreview()
    if Stable.ClearBreed then pcall(Stable.ClearBreed) end -- (defined further below: an error here left the camera stuck)
    if Stable.cam then
        RenderScriptCams(false, true, 600, true, true)
        DestroyCam(Stable.cam, false)
        Stable.cam = nil
    end
    Stable.fov = 45.0
    FreezeEntityPosition(PlayerPedId(), false)
    DisplayRadar(true)
end

local function Refresh()
    local data = lib.callback.await('fks-stables:getData', false, Stable.current.id, false)
    if data and not data.denied then
        data.shopHorses, data.shopWagons = Stable.data.shopHorses, Stable.data.shopWagons
        Stable.data = data
    end
    return Stable.data
end

local function FindOwned(kind, id)
    for _, x in ipairs(kind == 'wagon' and Stable.data.wagons or Stable.data.horses) do
        if x.id == id then return x end
    end
end

local function HorseLook(h)
    return { outfit = h.outfit, coat = h.coat, maneTail = h.maneTail, components = h.components, gender = h.gender, scale = h.scale }
end

---------------------------------------------------------------------------
-- Breeding: showroom with the female (left) and the male (right) at the stable's "breed" spot
---------------------------------------------------------------------------
local breedPeds = {}   -- [slot] = { ped, id }

local function ClearBreed()
    for slot, e in pairs(breedPeds) do
        if DoesEntityExist(e.ped) then DeleteEntity(e.ped) end
        breedPeds[slot] = nil
    end
end
Stable.ClearBreed = ClearBreed

-- creates a "showroom" horse (this client only) at a position {x, y, z, heading}
local function ShowcasePed(model, look, pos)
    local hash = Look.LoadModel(model)
    if not hash then return nil end
    local ped = CreatePed(hash, pos[1], pos[2], pos[3], pos[4] or 0.0, false, false, false, false)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetModelAsNoLongerNeeded(hash)
    Look.ApplyHorse(ped, look)
    Stable.KeepScale(ped, look.scale)
    return ped
end
Stable.ShowcasePed = ShowcasePed

function Stable.ShowBreed(femaleId, maleId)
    local b = Stable.current and Stable.current.breed
    if not b then return end
    Stable.token = Stable.token + 1
    ClearPreview()
    -- breeding camera, looking at the middle of the two
    local mid = vector3((b.left[1] + b.right[1]) / 2, (b.left[2] + b.right[2]) / 2, (b.left[3] + b.right[3]) / 2)
    if not Stable.cam then
        Stable.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
        SetCamFov(Stable.cam, Stable.fov)
        SetCamActive(Stable.cam, true)
        RenderScriptCams(true, true, 700, true, true)
    end
    SetCamCoord(Stable.cam, b.camera[1], b.camera[2], b.camera[3])
    PointCamAtCoord(Stable.cam, mid.x, mid.y, mid.z + 0.8)

    for slot, id in pairs({ left = femaleId, right = maleId }) do
        local cur = breedPeds[slot]
        if not id then
            if cur and DoesEntityExist(cur.ped) then DeleteEntity(cur.ped) end
            breedPeds[slot] = nil
        elseif not cur or cur.id ~= id or not DoesEntityExist(cur.ped) then
            if cur and DoesEntityExist(cur.ped) then DeleteEntity(cur.ped) end
            local h = FindOwned('horse', id)
            local ped = h and ShowcasePed(h.model, HorseLook(h), b[slot])
            breedPeds[slot] = ped and { ped = ped, id = id } or nil
        end
    end
end

-- Default response after a server action
local function Result(cb, ok, msg)
    if msg then Notify(msg, ok and 'success' or 'error') end
    cb({ ok = ok and true or false, data = ok and Refresh() or nil })
end

---------------------------------------------------------------------------
-- NUI callbacks
---------------------------------------------------------------------------
RegisterNUICallback('close', function(_, cb)
    Stable.Close()
    cb({})
end)

RegisterNUICallback('preview', function(d, cb)
    cb({})
    if d.type ~= 'breed' and next(breedPeds) then ClearBreed() end
    if d.type == 'breed' then
        Stable.ShowBreed(tonumber(d.female), tonumber(d.male))
    elseif d.type == 'shopHorse' then
        local coat = FKS.GetCoat(d.id)
        if coat then
            Stable.ShowHorse(coat.model, { outfit = coat.outfit, coat = coat.coat, maneTail = coat.maneTail, gender = d.gender })
        end
    elseif d.type == 'horse' then
        local h = FindOwned('horse', d.id)
        if h then Stable.ShowHorse(h.model, HorseLook(h)) end
    elseif d.type == 'shopWagon' then
        Stable.ShowWagon(d.model, {})
    elseif d.type == 'wagon' then
        local w = FindOwned('wagon', d.id)
        if w then Stable.ShowWagon(w.model, w.custom) end
    elseif d.type == 'none' then
        Stable.token = Stable.token + 1
        ClearPreview()
    end
end)

RegisterNUICallback('rotate', function(d, cb)
    cb({})
    if Stable.preview and DoesEntityExist(Stable.preview) then
        SetEntityHeading(Stable.preview, (GetEntityHeading(Stable.preview) + (tonumber(d.dx) or 0) * 0.45) % 360.0)
    end
end)

RegisterNUICallback('zoom', function(d, cb)
    cb({})
    if Stable.cam then
        Stable.fov = FKS.Clamp(Stable.fov + (tonumber(d.dy) or 0) * 0.02, 22.0, 70.0)
        SetCamFov(Stable.cam, Stable.fov)
    end
end)

RegisterNUICallback('buyHorse', function(d, cb)
    local ok, msg = lib.callback.await('fks-stables:buyHorse', false, Stable.current.id, d.coatId, d.currency, d.gender, d.name)
    Result(cb, ok, msg)
end)

RegisterNUICallback('buyWagon', function(d, cb)
    local ok, msg = lib.callback.await('fks-stables:buyWagon', false, Stable.current.id, d.model, d.currency, d.name)
    Result(cb, ok, msg)
end)

RegisterNUICallback('sell', function(d, cb)
    if d.kind == 'horse' and Horse.id == d.id then Horse.Despawn(false) end
    if d.kind == 'wagon' and Wagon.id == d.id then Wagon.Despawn(false) end
    local ok, msg = lib.callback.await('fks-stables:sell', false, d.kind, d.id)
    Result(cb, ok, msg)
end)

RegisterNUICallback('heal', function(d, cb)
    local ok, msg = lib.callback.await('fks-stables:heal', false, d.id, Stable.current.id)
    -- the body of the dead horse still in the world disappears: the horse is healed at this stable
    if ok and Horse.id == d.id and Horse.ped and DoesEntityExist(Horse.ped) and Horse.IsDown(Horse.ped) then
        Horse.Despawn(true, Stable.current.id)
    end
    Result(cb, ok, msg)
end)

RegisterNUICallback('breed', function(d, cb)
    local ok, msg = lib.callback.await('fks-stables:breed', false, Stable.current.id, d.mother, d.father)
    if ok and Breeding then Breeding.Refresh() end
    Result(cb, ok, msg)
end)

RegisterNUICallback('repair', function(d, cb)
    local ok, msg = lib.callback.await('fks-stables:repair', false, d.id)
    Result(cb, ok, msg)
end)

RegisterNUICallback('rename', function(d, cb)
    local ok, msg = lib.callback.await('fks-stables:rename', false, d.kind, d.id, d.name)
    Result(cb, ok, msg)
end)

RegisterNUICallback('transfer', function(d, cb)
    local ok, msg = lib.callback.await('fks-stables:transfer', false, d.kind, d.id, d.to)
    Result(cb, ok, msg)
end)

RegisterNUICallback('takeOut', function(d, cb)
    local ok, res = lib.callback.await('fks-stables:takeOut', false, d.kind, d.id, Stable.current.id)
    if not ok then
        if res then Notify(res, 'error') end
        return cb({ ok = false })
    end
    cb({ ok = true })
    local sp = Stable.current.spawn
    Stable.Close()
    if d.kind == 'wagon' then
        Wagon.Spawn(res, vector4(sp[1], sp[2], sp[3], sp[4]))
    else
        Horse.Spawn(res, vector4(sp[1], sp[2], sp[3], sp[4]), true)
    end
end)

-- Tack ----------------------------------------------------------------------------
RegisterNUICallback('customStart', function(d, cb)
    local h = FindOwned('horse', d.id)
    if not h then return cb({}) end
    local values = {}
    for _, cat in ipairs(Look.Categories) do values[cat] = Look.IndexOf(cat, h.components[cat]) end
    cb({ values = values })
end)

RegisterNUICallback('customPreview', function(d, cb)
    cb({})
    local ped = Stable.preview
    if not ped or Stable.previewKind ~= 'horse' then return end
    Look.SetComponent(ped, d.cat, Look.HashAt(d.cat, tonumber(d.index)))
    if (d.cat == 'manes' or d.cat == 'tails') and Stable.previewLook then
        Look.ApplyCoat(ped, nil, Stable.previewLook.maneTail)
    end
end)

RegisterNUICallback('customSave', function(d, cb)
    local comps = {}
    for cat, idx in pairs(d.values or {}) do
        local h = Look.HashAt(cat, tonumber(idx))
        if h ~= 0 then comps[cat] = h end
    end
    local ok, msg = lib.callback.await('fks-stables:saveComponents', false, d.id, comps)
    if ok and Horse.id == d.id then Horse.Reapply() end
    Result(cb, ok, msg)
end)

-- Coat ---------------------------------------------------------------------------------
RegisterNUICallback('coatPreview', function(d, cb)
    cb({})
    local ped = Stable.preview
    if not ped or Stable.previewKind ~= 'horse' or not Stable.previewLook then return end
    local look = {}
    for k, v in pairs(Stable.previewLook) do look[k] = v end
    look.coat, look.maneTail = d.coat, d.maneTail
    Look.ApplyHorse(ped, look)
end)

RegisterNUICallback('coatSave', function(d, cb)
    local ok, msg = lib.callback.await('fks-stables:saveCoat', false, d.id, d.coat, d.maneTail)
    if ok and Horse.id == d.id then Horse.Reapply() end
    Result(cb, ok, msg)
end)

-- Wagons --------------------------------------------------------------------------------
RegisterNUICallback('wagonCustomStart', function(d, cb)
    local w = FindOwned('wagon', d.id)
    if not w then return cb({}) end
    local m, W = w.model:lower(), Config.WagonCustom
    cb({
        values = { livery = w.custom.livery or 0, tint = w.custom.tint or 0, propset = w.custom.propset or 0, lantern = w.custom.lantern or 0, extras = w.custom.extras or {} },
        max = { livery = W.liveries[m] and #W.liveries[m] or 0, tint = W.tints[m] or 0, propset = W.propsets[m] and #W.propsets[m] or 0, lantern = W.lanterns[m] and #W.lanterns[m] or 0 },
        liveryNames = W.liveries[m] or {},
        extras = W.extras[m] or {},
    })
end)

RegisterNUICallback('wagonCustomPreview', function(d, cb)
    cb({})
    if Stable.previewKind == 'wagon' and Stable.preview then
        local w = FindOwned('wagon', d.id)
        if w then Look.ApplyWagon(Stable.preview, w.model, d.custom) end
    end
end)

RegisterNUICallback('wagonCustomSave', function(d, cb)
    local ok, msg = lib.callback.await('fks-stables:saveWagonCustom', false, d.id, d.custom)
    if ok and Wagon.id == d.id then Wagon.Reapply() end
    Result(cb, ok, msg)
end)

---------------------------------------------------------------------------
-- Breedings in progress: the parents stay at the breeding spot until the foal is born; the foal appears there
---------------------------------------------------------------------------
Breeding = { pending = {} }
local shown = {}     -- [key] = { peds }

local function Unshow(key)
    for k, ped in pairs(shown[key] or {}) do if type(k) == 'number' and DoesEntityExist(ped) then DeleteEntity(ped) end end
    shown[key] = nil
end

function Breeding.Refresh()
    local list = lib.callback.await('fks-stables:myBreedings', false) or {}
    local now = GetGameTimer()
    for _, b in ipairs(list) do b.readyAt = now + b.readyIn * 1000 end
    Breeding.pending = list
end

CreateThread(function()
    Wait(5000)
    Breeding.Refresh()
    local lastRefresh = GetGameTimer()
    while true do
        Wait(2000)
        if GetGameTimer() - lastRefresh > 60000 then Breeding.Refresh() lastRefresh = GetGameTimer() end
        local pos = GetEntityCoords(PlayerPedId())
        local want = {}
        if not Stable.open then
            for _, b in ipairs(Breeding.pending) do
                local s = FKS.StableById[b.stable]
                local key = 'b' .. b.id
                if s and s.breed and GetGameTimer() < b.readyAt and #(pos - vector3(s.breed.left[1], s.breed.left[2], s.breed.left[3])) < 60.0 then
                    want[key] = true
                    if not shown[key] then
                        local m = b.mother and ShowcasePed(b.mother.model, b.mother, s.breed.left)
                        local f = b.father and ShowcasePed(b.father.model, b.father, s.breed.right)
                        shown[key] = { m, f }
                    end
                end
            end
        end
        for key, v in pairs(shown) do
            if key:sub(1, 1) == 'b' and not want[key] then Unshow(key) end
            if key:sub(1, 1) == 'f' and (GetGameTimer() > (v.expires or 0) or Stable.open) then Unshow(key) end
        end
    end
end)

-- a foal was born: if you are near the stable, it shows at the breeding spot for a few minutes
RegisterNetEvent('fks-stables:client:foalBorn', function(stableId, horseId)
    Breeding.Refresh()
    local s = FKS.StableById[stableId]
    if not s or not s.breed then return end
    local b = s.breed
    if #(GetEntityCoords(PlayerPedId()) - vector3(b.left[1], b.left[2], b.left[3])) > 80.0 then return end
    local look = lib.callback.await('fks-stables:horseLook', false, horseId)
    if not look then return end
    local pos = { (b.left[1] + b.right[1]) / 2, (b.left[2] + b.right[2]) / 2, (b.left[3] + b.right[3]) / 2, b.left[4] or 0.0 }
    local ped = ShowcasePed(look.model, look, pos)
    if ped then shown['f' .. horseId] = { ped, expires = GetGameTimer() + 180000 } end
end)

---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    Stable.Close()
    for key in pairs(shown) do Unshow(key) end
    for _, ped in pairs(npcs) do DeleteEntity(ped) end
    for _, b in ipairs(blips) do RemoveBlip(b) end
end)
