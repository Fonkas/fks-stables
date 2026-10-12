---------------------------------------------------------------------------
-- Update checker: compares the version in fxmanifest.lua with the one in the
-- fxmanifest.lua of Config.VersionCheck.repo on GitHub (so a push is enough,
-- no release needed) and prints "up to date" / "OUTDATED" in the server console.
-- Also warns when the fks-utils dependency is not running.
---------------------------------------------------------------------------
local cfg = Config.VersionCheck or {}
local resource = GetCurrentResourceName()

-- '1.2.10' -> { 1, 2, 10 }
local function parse(v)
    local parts = {}
    for n in tostring(v):gsub('^[vV]', ''):gmatch('%d+') do parts[#parts + 1] = tonumber(n) end
    return parts
end

local function isNewer(latest, current)
    local a, b = parse(latest), parse(current)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

local function checkVersion()
    local current = GetResourceMetadata(resource, 'version', 0) or '0.0.0'
    local url = ('https://raw.githubusercontent.com/%s/%s/fxmanifest.lua'):format(cfg.repo, cfg.branch or 'main')

    PerformHttpRequest(url, function(status, body)
        local latest = status == 200 and body and body:match("\nversion%s+['\"]([^'\"]+)['\"]")
        if not latest then
            print(('^3[%s] could not check for updates (HTTP %s)^0'):format(resource, tostring(status)))
            return
        end

        if isNewer(latest, current) then
            print('^1================================================================^0')
            print(('^1[%s] OUTDATED^0  installed: ^3%s^0  ->  latest: ^2%s^0'):format(resource, current, latest))
            print(('^1[%s]^0 download: https://github.com/%s'):format(resource, cfg.repo))
            print('^1================================================================^0')
        else
            print(('^2[%s] up to date (v%s)^0'):format(resource, current))
        end
    end, 'GET', '', { ['User-Agent'] = resource })
end

local function checkUtils()
    local state = GetResourceState('fks-utils')
    if state == 'started' or state == 'starting' then return end
    print('^1================================================================^0')
    print(('^1[%s] MISSING DEPENDENCY: fks-utils^0 (%s)'):format(resource, state))
    print(('^1[%s]^0 notifications and progress bar fall back to ox_lib'):format(resource))
    print(('^1[%s]^0 download: %s'):format(resource, cfg.utilsUrl or 'https://github.com/Fonkas/fks-utils'))
    print(('^1[%s]^0 then add ^3ensure fks-utils^0 before ^3ensure %s^0 in server.cfg'):format(resource, resource))
    print('^1================================================================^0')
end

CreateThread(function()
    Wait(5000) -- let the server finish starting
    checkUtils()

    if not cfg.enabled or not cfg.repo or cfg.repo == '' then return end
    checkVersion()

    -- check again from time to time (servers that run for days)
    local hours = tonumber(cfg.interval) or 0
    while hours > 0 do
        Wait(hours * 3600000)
        checkVersion()
    end
end)
