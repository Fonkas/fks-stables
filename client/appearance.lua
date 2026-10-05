-- Horse and wagon appearance: outfit preset, tack, coat (palette + tints) and sex.
Look = {}

local N = {
    EquipOutfitPreset = 0x77FF8D35EEC6BBC4,
    ApplyShopItem = 0xD3A7B003ED343FD9,
    RemoveTag = 0xD710A5007C2AC539,
    UpdateVariation = 0xCC8CA3E88256E58F,
    FinalizeVariation = 0x704C908E9C405136,
    ReadyToRender = 0xA0BC8FAED8CFEB3C,
    NumComponents = 0x90403E8107B60E81,
    ComponentCategory = 0x9B90842304C938A7,
    ComponentGuids = 0xA9C28516A6DC9D56,
    ComponentTint = 0xE7998FEC53A33BBE,
    SetMetaPedTag = 0xBC6DF00D7A4A6819,
    ApplyTags = 0xAAB86462966168CE,
    SetExpression = 0x5653AB26C82938CF,
}

local HORSE_PALETTE = joaat('metaped_tint_horse')
local BODY = { [joaat('horse_bodies')] = true, [joaat('horse_heads')] = true }
local MANE = { [0xAA0217AB] = true, [joaat('horse_manes')] = true, [joaat('horse_mane')] = true, [joaat('manes')] = true }
local TAIL = { [0xA63CAE10] = true, [joaat('horse_tails')] = true, [joaat('horse_tail')] = true, [joaat('tails')] = true }

-- Tack categories -> category hash (used to remove a piece)
Look.CategoryHash = {
    blankets = 0x17CEB41A, saddles = 0xBAA7E618, horns = 0x05447332, saddlebags = 0x80451C25,
    stirrups = 0xDA6DADCA, bedrolls = 0xEFB31921, tails = 0xA63CAE10, manes = 0xAA0217AB,
    masks = 0xD3500E5D, mustaches = 0x30DEFDDF, holsters = 0x94B2E3AF,
}
Look.Categories = { 'saddles', 'blankets', 'horns', 'stirrups', 'saddlebags', 'bedrolls', 'holsters', 'manes', 'tails', 'masks', 'mustaches' }

function Look.WaitReady(ped, timeout)
    local t = GetGameTimer() + (timeout or 3000)
    while not Citizen.InvokeNative(N.ReadyToRender, ped) and GetGameTimer() < t do Wait(0) end
end

function Look.Refresh(ped)
    Citizen.InvokeNative(N.ApplyTags, ped, true)
    Citizen.InvokeNative(N.UpdateVariation, ped, false, true, true, true, false)
end

-- index (1..n, 0 = none) <-> hash
function Look.IndexOf(cat, hash)
    if not hash or hash == 0 then return 0 end
    for i, h in ipairs(Config.HorseComponents[cat] or {}) do
        if h == hash then return i end
    end
    return 0
end

function Look.HashAt(cat, index)
    return index and index > 0 and (Config.HorseComponents[cat] or {})[index] or 0
end

-- does the horse have a piece of this category equipped? (reads the metaped, also works on other players' horses)
function Look.HasComponent(ped, cat)
    local catHash = Look.CategoryHash[cat]
    if not catHash or not DoesEntityExist(ped) then return false end
    local r = Citizen.InvokeNative(0xFB4891BD7578CDC1, ped, catHash) -- IsMetaPedUsingComponent
    return r == true or r == 1
end

function Look.SetComponent(ped, cat, hash)
    local catHash = Look.CategoryHash[cat]
    if catHash then Citizen.InvokeNative(N.RemoveTag, ped, catHash, 0) end
    if hash and hash ~= 0 then
        Citizen.InvokeNative(N.ApplyShopItem, ped, hash, true, true, true)
    end
    Citizen.InvokeNative(N.UpdateVariation, ped, false, true, true, true, false)
end

-- Applies {palette, t0, t1, t2} to every metaped piece whose group passes the filter
local function TintWhere(ped, tint, filter)
    if type(tint) ~= 'table' then return end
    local num = Citizen.InvokeNative(N.NumComponents, ped) or 0
    for i = 0, num - 1 do
        local cat = Citizen.InvokeNative(N.ComponentCategory, ped, i, 6, Citizen.ResultAsInteger())
        local drawable, albedo, normal, material = Citizen.InvokeNative(N.ComponentGuids, ped, i,
            Citizen.PointerValueInt(), Citizen.PointerValueInt(), Citizen.PointerValueInt(), Citizen.PointerValueInt())
        if drawable and drawable ~= 0 then
            local palette = Citizen.InvokeNative(N.ComponentTint, ped, i,
                Citizen.PointerValueInt(), Citizen.PointerValueInt(), Citizen.PointerValueInt(), Citizen.PointerValueInt())
            if filter(cat, palette) then
                local p = tint[1] or 0
                local pal = p > 0 and Config.ColorPalettes[p] or (palette ~= 0 and palette or HORSE_PALETTE)
                Citizen.InvokeNative(N.SetMetaPedTag, ped, drawable, albedo, normal, material, pal, tint[2] or 0, tint[3] or 0, tint[4] or 0)
            end
        end
    end
end

function Look.ApplyCoat(ped, coat, maneTail)
    if coat then
        TintWhere(ped, coat, function(cat) return BODY[cat] end)
    end
    if maneTail then
        TintWhere(ped, maneTail, function(cat, palette)
            return MANE[cat] or TAIL[cat] or (not BODY[cat] and palette == HORSE_PALETTE)
        end)
    end
    Look.Refresh(ped)
end

-- look = { outfit, coat, maneTail, components = { cat = hash }, gender }
function Look.ApplyHorse(ped, look)
    if not DoesEntityExist(ped) then return end
    Citizen.InvokeNative(N.EquipOutfitPreset, ped, look.outfit or 0, false)
    Citizen.InvokeNative(N.FinalizeVariation, ped)
    Citizen.InvokeNative(N.UpdateVariation, ped, false, true, true, true, false)
    Look.WaitReady(ped)

    for cat, hash in pairs(look.components or {}) do
        if hash and hash ~= 0 then Citizen.InvokeNative(N.ApplyShopItem, ped, hash, true, true, true) end
    end
    Citizen.InvokeNative(N.UpdateVariation, ped, false, true, true, true, false)
    Look.WaitReady(ped)

    Look.ApplyCoat(ped, look.coat, look.maneTail)
    Citizen.InvokeNative(N.SetExpression, ped, 41611, look.gender == 'female' and 1.0 or 0.0)
    Look.Refresh(ped)
end

-- Wagons --------------------------------------------------------------------------------
-- custom = { livery = n, tint = n, propset = n, lantern = n, extras = { ... } }
function Look.ApplyWagon(veh, model, custom)
    if not DoesEntityExist(veh) then return end
    model = model:lower()
    custom = custom or {}
    local W = Config.WagonCustom

    if Config.Wagon.disableDefaultGreen and (custom.tint or 0) == 0 and W.tints[model] then
        Citizen.InvokeNative(0x8268B098F6FCA4E2, veh, 1) -- SetVehicleTint
    end
    if custom.tint and custom.tint > 0 then Citizen.InvokeNative(0x8268B098F6FCA4E2, veh, custom.tint) end
    if custom.livery and custom.livery > 0 then Citizen.InvokeNative(0xF89D82A0582E46ED, veh, custom.livery - 1) end -- SetVehicleLivery

    for _, e in ipairs(W.extras[model] or {}) do
        SetVehicleExtra(veh, e, true) -- true = disabled
    end
    for _, e in ipairs(custom.extras or {}) do
        SetVehicleExtra(veh, e, false)
    end

    Citizen.InvokeNative(0x3BCF32FF37EA9F1D, veh) -- RemoveVehiclePropSets
    Citizen.InvokeNative(0xE31C0CB1C3186D40, veh) -- RemoveVehicleLightPropSets
    local ps = custom.propset and custom.propset > 0 and (W.propsets[model] or {})[custom.propset]
    if ps then Look.AddPropSet(veh, ps, false) end
    local ls = custom.lantern and custom.lantern > 0 and (W.lanterns[model] or {})[custom.lantern]
    if ls then Look.AddPropSet(veh, ls, true) end
end

function Look.AddPropSet(veh, name, isLight)
    local hash = joaat(name)
    if not Citizen.InvokeNative(0x48A88FC684C55FDC, hash) then -- HasPropSetLoaded
        Citizen.InvokeNative(0xF3DE57A46D5585E9, hash)         -- RequestPropSet
        local t = GetGameTimer() + 2000
        while not Citizen.InvokeNative(0x48A88FC684C55FDC, hash) and GetGameTimer() < t do Wait(0) end
    end
    if isLight then
        Citizen.InvokeNative(0xC0F0417A90402742, veh, hash)         -- AddLightPropSetToVehicle
    else
        Citizen.InvokeNative(0x75F90E4051CC084C, veh, hash)         -- AddPropSetForVehicle
    end
end

-- Load a model with a timeout
function Look.LoadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    if not IsModelValid(hash) then return nil end
    RequestModel(hash, false)
    local t = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(10) end
    return HasModelLoaded(hash) and hash or nil
end
