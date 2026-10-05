-- Compatibility: framework (rsg / vorp) and inventory (ox_inventory / rsg-inventory / vorp_inventory).
-- Everything the rest of the script needs from the server goes through here.

Bridge = {}

local function Started(res) return GetResourceState(res) == 'started' or GetResourceState(res) == 'starting' end

local function Detect()
    local fw = Config.Framework
    if fw == 'auto' then
        fw = Started('rsg-core') and 'rsg' or (Started('vorp_core') and 'vorp') or nil
    end
    local inv = Config.Inventory
    if inv == 'auto' then
        inv = (Started('ox_inventory') and 'ox_inventory')
            or (Started('rsg-inventory') and 'rsg-inventory')
            or (Started('vorp_inventory') and 'vorp_inventory') or nil
    end
    return fw, inv
end

Bridge.framework, Bridge.inventory = Detect()

-- The inventory may start after fks-stables (e.g. inside the same folder, in alphabetical order).
-- So it is searched again for up to 60 s and whenever needed (Bridge.Inv()).
function Bridge.Inv()
    if not Bridge.inventory then
        local _, inv = Detect()
        if inv and (Config.Inventory ~= 'auto' or GetResourceState(inv) == 'started') then Bridge.inventory = inv end
    end
    return Bridge.inventory
end

---------------------------------------------------------------------------
-- Framework
---------------------------------------------------------------------------
local RSG, VORP

-- Connects to the framework (and tries again if it started after fks-stables)
local function EnsureFramework()
    if RSG or VORP then return true end
    if not Bridge.framework then Bridge.framework = Detect() end
    if Bridge.framework == 'rsg' and GetResourceState('rsg-core') == 'started' then
        RSG = exports['rsg-core']:GetCoreObject()
    elseif Bridge.framework == 'vorp' and GetResourceState('vorp_core') == 'started' then
        VORP = exports.vorp_core:GetCore()
    end
    return RSG ~= nil or VORP ~= nil
end
EnsureFramework()

Bridge.ready = false
CreateThread(function()
    local t = GetGameTimer() + 60000
    while GetGameTimer() < t do
        local inv = Bridge.Inv()
        if EnsureFramework() and inv and GetResourceState(inv) == 'started' then break end
        Wait(500)
    end
    if not Bridge.framework then print('^1[fks-stables] No framework found (rsg-core / vorp_core). Set Config.Framework.^0') end
    if not Bridge.inventory then print('^1[fks-stables] No inventory found. Set Config.Inventory.^0') end
    print(('[fks-stables] framework: ^2%s^0 | inventory: ^2%s^0'):format(tostring(Bridge.framework), tostring(Bridge.inventory)))
    Bridge.ready = true
end)

-- Returns a "player" with the same shape in both frameworks:
-- { cid, name, job, money(type), remove(type, n, reason), add(type, n, reason), hasGroup(g) }
-- type: 'cash' | 'gold'
function Bridge.GetPlayer(src)
    EnsureFramework()
    if RSG then
        local P = RSG.Functions.GetPlayer(src)
        if not P then return nil end
        -- rsg-core has no "gold" account by default: Config.RSGGoldAccount maps it (nil = gold disabled on RSG)
        local function acc(t) return t == 'gold' and Config.RSGGoldAccount or 'cash' end
        return {
            cid = P.PlayerData.citizenid,
            name = P.PlayerData.charinfo and ((P.PlayerData.charinfo.firstname or '') .. ' ' .. (P.PlayerData.charinfo.lastname or '')) or GetPlayerName(src),
            job = P.PlayerData.job and P.PlayerData.job.name,
            money = function(t) local a = acc(t) return a and tonumber(P.PlayerData.money[a]) or 0 end,
            remove = function(t, n, reason) local a = acc(t) return a ~= nil and P.Functions.RemoveMoney(a, n, reason) ~= false end,
            add = function(t, n, reason) local a = acc(t) if a then P.Functions.AddMoney(a, n, reason) end end,
            hasGroup = function(g) return RSG.Functions.HasPermission(src, g) end,
        }
    elseif VORP then
        local user = VORP.getUser(src)
        if not user then return nil end
        local char = user.getUsedCharacter
        if not char then return nil end
        local cur = { cash = 0, gold = 1 }
        return {
            cid = tostring(char.charIdentifier),
            name = ((char.firstname or '') .. ' ' .. (char.lastname or '')),
            job = char.job,
            money = function(t) return tonumber(t == 'gold' and char.gold or char.money) or 0 end,
            remove = function(t, n) char.removeCurrency(cur[t] or 0, n) return true end,
            add = function(t, n) char.addCurrency(cur[t] or 0, n) end,
            hasGroup = function(g) return user.getGroup == g or char.group == g end,
        }
    end
end

---------------------------------------------------------------------------
-- Inventory
---------------------------------------------------------------------------

-- Usable items: cb(src, itemName)
function Bridge.RegisterUsable(item, cb)
    EnsureFramework()
    local INV = Bridge.Inv()
    if INV == 'vorp_inventory' then
        exports.vorp_inventory:registerUsableItem(item, function(data)
            pcall(function() exports.vorp_inventory:closeInventory(data.source) end)
            cb(data.source, item)
        end, GetCurrentResourceName())
    elseif RSG then
        -- rsg-inventory and ox_inventory (rsg bridge) use rsg-core usable items
        RSG.Functions.CreateUseableItem(item, function(src) cb(src, item) end)
    elseif INV == 'ox_inventory' then
        Bridge._oxUsable = Bridge._oxUsable or {}
        Bridge._oxUsable[item] = cb
    end
end

-- ox_inventory without rsg-core (e.g. vorp + ox): catches the use by event
AddEventHandler('ox_inventory:usedItem', function(src, name)
    if RSG then return end
    local cb = Bridge._oxUsable and Bridge._oxUsable[name]
    if cb then cb(src, name) end
end)

function Bridge.RemoveItem(src, item, n)
    n = n or 1
    local INV = Bridge.Inv()
    if INV == 'ox_inventory' then
        return exports.ox_inventory:RemoveItem(src, item, n) and true or false
    elseif INV == 'rsg-inventory' then
        local ok = exports['rsg-inventory']:RemoveItem(src, item, n, nil, 'fks-stables') and true or false
        if ok and RSG and RSG.Shared and RSG.Shared.Items and RSG.Shared.Items[item] then
            TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSG.Shared.Items[item], 'remove', n) -- item feedback
        end
        return ok
    elseif INV == 'vorp_inventory' then
        if (exports.vorp_inventory:getItemCount(src, nil, item) or 0) < n then return false end
        return exports.vorp_inventory:subItem(src, item, n) ~= false
    end
    return false
end

function Bridge.ItemCount(src, item)
    local INV = Bridge.Inv()
    if INV == 'ox_inventory' then
        return exports.ox_inventory:GetItemCount(src, item) or 0
    elseif INV == 'rsg-inventory' then
        local ok, n = pcall(function() return exports['rsg-inventory']:GetItemCount(src, item) end)
        if ok and n then return tonumber(n) or 0 end
        -- fallback (older rsg-inventory): read it from the rsg-core player
        local P = RSG and RSG.Functions.GetPlayer(src)
        local it = P and P.Functions.GetItemByName(item)
        return it and (it.amount or it.count or 0) or 0
    elseif INV == 'vorp_inventory' then
        return exports.vorp_inventory:getItemCount(src, nil, item) or 0
    end
    return 0
end

-- Opens a storage (saddlebags / wagon)
-- slots = visible slots (ox / rsg grid) · weight = max weight · capacity = total capacity (storage)
function Bridge.OpenStash(src, id, label, slots, weight, capacity)
    local INV = Bridge.Inv()
    if INV == 'ox_inventory' then
        exports.ox_inventory:RegisterStash(id, label, slots, weight)
        exports.ox_inventory:forceOpenInventory(src, 'stash', id)
    elseif INV == 'rsg-inventory' then
        exports['rsg-inventory']:OpenInventory(src, id, { label = label, maxweight = weight, slots = slots })
    elseif INV == 'vorp_inventory' then
        -- in vorp the "limit" is the total amount of items (no grid nor weight): use the whole capacity
        local limit = capacity or slots
        if exports.vorp_inventory:isCustomInventoryRegistered(id) then
            -- already registered (maybe with another limit, e.g. before changing the horse / the config)
            pcall(function() exports.vorp_inventory:updateCustomInventorySlots(id, limit) end)
        else
            exports.vorp_inventory:registerInventory({
                id = id, name = label, limit = limit,
                acceptWeapons = true, shared = true, ignoreItemStackLimit = true,
                whitelistItems = false, UsePermissions = false, UseBlackList = false, whitelistWeapons = false,
            })
        end
        exports.vorp_inventory:openInventory(src, id)
    end
end

-- Deletes the contents of a storage (when selling the horse / wagon)
function Bridge.DeleteStash(id)
    local INV = Bridge.Inv()
    if INV == 'ox_inventory' then
        MySQL.update('DELETE FROM ox_inventory WHERE name = ?', { id })
    elseif INV == 'rsg-inventory' then
        pcall(function() exports['rsg-inventory']:DeleteInventory(id) end)
        pcall(function() MySQL.update('DELETE FROM inventories WHERE identifier = ?', { id }) end) -- rsg-inventory stash table
    elseif INV == 'vorp_inventory' then
        pcall(function() exports.vorp_inventory:removeInventory(id) end)
        MySQL.update('DELETE FROM character_inventories WHERE inventory_type = ?', { id })
    end
end

---------------------------------------------------------------------------
lib.callback.register('fks-stables:hasItem', function(src, item)
    return Bridge.ItemCount(src, item)
end)
