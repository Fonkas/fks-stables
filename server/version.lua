---------------------------------------------------------------------------
-- Server console: fks-core (required) missing -> warning with the download link;
-- otherwise "up to date" / "OUTDATED" compared with GitHub (Config.VersionCheck).
---------------------------------------------------------------------------
local cfg = Config.VersionCheck or {}
local resource = GetCurrentResourceName()
local state = GetResourceState('fks-core')

if not Bridge or (state ~= 'started' and state ~= 'starting') then
    print('^1================================================================^0')
    print(('^1[%s] MISSING REQUIRED DEPENDENCY: fks-core^0 (%s)'):format(resource, state))
    print(('^1[%s]^0 download: %s'):format(resource, cfg.coreUrl or 'https://github.com/Fonkas/fks-core'))
    print(('^1[%s]^0 then add ^3ensure fks-core^0 before ^3ensure %s^0 in server.cfg'):format(resource, resource))
    print('^1================================================================^0')
    return
end

if cfg.enabled then
    Bridge.CheckVersion(cfg.repo, { branch = cfg.branch, interval = cfg.interval })
end
