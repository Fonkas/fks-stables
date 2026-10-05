FKS = FKS or {}
joaat = joaat or GetHashKey

-- Indexes built from the catalogue -------------------------------------------------
FKS.CoatById = {}       -- id -> { breed = name, coat = table }
FKS.WagonByModel = {}   -- model (lowercase) -> { category = name, wagon = table }
FKS.StableById = {}

for _, b in ipairs(Config.Horses) do
    for _, c in ipairs(b.coats) do
        FKS.CoatById[c.id] = { breed = b.breed, coat = c }
    end
end

for _, cat in ipairs(Config.Wagons) do
    for _, w in ipairs(cat.wagons) do
        FKS.WagonByModel[w.model:lower()] = { category = cat.category, wagon = w }
    end
end

for _, s in ipairs(Config.Stables) do
    FKS.StableById[s.id] = s
end

-- model hash -> config (the game returns models as numbers; normalises signed/unsigned)
function FKS.Hash(n) return n and (math.floor(n) & 0xFFFFFFFF) end

FKS.WagonByHash = {}
for model, e in pairs(FKS.WagonByModel) do
    FKS.WagonByHash[FKS.Hash(joaat(model))] = e.wagon
end

FKS.CarcassByHash = {} -- [hash] = { label, big, pelt }
for model, a in pairs(Config.Animals or {}) do
    FKS.CarcassByHash[FKS.Hash(joaat(model))] = { label = a[1], big = a.big, model = model }
end
if Config.StorePelts then
    for model, a in pairs(Config.Pelts or {}) do
        FKS.CarcassByHash[FKS.Hash(joaat(model))] = { label = a[1], big = a.big, model = model, pelt = true }
    end
end

-- Wild horses: game model -> shop coats with that model
FKS.CoatsByHash = {}     -- [hash] = { { coat, breed }, ... }
for _, b in ipairs(Config.Horses) do
    for _, c in ipairs(b.coats) do
        local h = FKS.Hash(joaat(c.model))
        FKS.CoatsByHash[h] = FKS.CoatsByHash[h] or {}
        table.insert(FKS.CoatsByHash[h], { coat = c, breed = b.breed })
    end
end

-- coat used for a wild horse of this model (the first that can be kept; nil = unknown model)
function FKS.WildCoat(modelHash)
    local list = FKS.CoatsByHash[FKS.Hash(modelHash or 0)]
    if not list then return nil end
    for _, e in ipairs(list) do
        if not e.coat.wild or e.coat.wild.save ~= false then return e.coat, e.breed end
    end
    return list[1].coat, list[1].breed
end

-- breed -> coats (breeding: foal with a random coat of that breed)
FKS.CoatsByBreed = {}
for _, b in ipairs(Config.Horses) do FKS.CoatsByBreed[b.breed] = b.coats end

-- special horse (Config.Special.breeds)?
function FKS.IsSpecialBreed(breed)
    for _, b in ipairs((Config.Special or {}).breeds or {}) do
        if b == breed then return true end
    end
    return false
end

-- xp of a fully trained horse of this class
function FKS.MaxXp(tier)
    local m = Config.Level.maxXpByTier
    return (m and m[tier or 1]) or 1000
end

-- training (0..1) = xp / class max
function FKS.Progress(xp, tier)
    return FKS.Clamp((xp or 0) / FKS.MaxXp(tier), 0, 1)
end

-- health / stamina (% of the game max) for the class and training (0..1): normal -> trained
function FKS.ClassPercent(tier, progress)
    local c = (Config.ClassStats or {})[tier or 1] or (Config.ClassStats or {})[1]
    if not c then return nil end
    return c.base + (c.trained - c.base) * FKS.Clamp(progress or 0, 0, 1)
end

function FKS.GetCoat(id)
    local e = FKS.CoatById[id]
    return e and e.coat, e and e.breed
end

function FKS.GetWagon(model)
    local e = model and FKS.WagonByModel[model:lower()]
    return e and e.wagon, e and e.category
end

function FKS.BreedStats(breed)
    return Config.BreedStats[breed] or Config.BreedStats.default
end

function FKS.BondLevel(bond)
    local lvl = 1
    for i, need in ipairs(Config.Bond.levels) do
        if bond >= need then lvl = i end
    end
    return lvl
end

function FKS.Age(born)
    if not Config.Aging.enabled then return nil end
    local secs = os.time() - (born or os.time())
    return secs / (Config.Aging.hoursPerYear * 3600)
end

function FKS.Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
