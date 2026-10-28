-- Server callbacks (no ox_lib): the client asks, the server answers through a net event.
--   server:  Callback.Register('fks-stables:x', function(src, ...) return a, b end)
--   client:  local a, b = Callback.Await('fks-stables:x', ...)   -- yields until the answer (nil after 30 s)

Callback = {}

local REQ = GetCurrentResourceName() .. ':cb:req'
local RES = GetCurrentResourceName() .. ':cb:res'
local TIMEOUT = 30000

if IsDuplicityVersion() then
    local fns = {}

    function Callback.Register(name, fn) fns[name] = fn end

    RegisterNetEvent(REQ, function(name, id, ...)
        local src = source
        local fn = fns[name]
        if not fn then
            print(('^1[fks-stables] unknown callback %s^0'):format(tostring(name)))
            return TriggerClientEvent(RES, src, id)
        end
        local r = table.pack(pcall(fn, src, ...))
        if not r[1] then
            print(('^1[fks-stables] callback %s failed: %s^0'):format(name, tostring(r[2])))
            return TriggerClientEvent(RES, src, id)
        end
        TriggerClientEvent(RES, src, id, table.unpack(r, 2, r.n))
    end)
else
    local pending, nextId = {}, 0

    RegisterNetEvent(RES, function(id, ...)
        local p = pending[id]
        if p then pending[id] = nil p:resolve(table.pack(...)) end
    end)

    function Callback.Await(name, ...)
        nextId = nextId + 1
        local id, p = nextId, promise.new()
        pending[id] = p
        TriggerServerEvent(REQ, name, id, ...)
        SetTimeout(TIMEOUT, function()
            if pending[id] then pending[id] = nil p:resolve({ n = 0 }) end
        end)
        local r = Citizen.Await(p)
        return table.unpack(r, 1, r.n)
    end
end
