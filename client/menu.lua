---------------------------------------------------------------------------
-- Stable menu: the screens are described here and drawn by fks-core (`UI`, docs/UI-API.md in fks-core).
-- Stable.lua keeps the camera, the showroom and the server calls; this file builds the pages from
-- Stable.data and answers the clicks.
---------------------------------------------------------------------------
Menu = {}

local T = _LU
local ROMAN = { 'I', 'II', 'III', 'IV' }
local IMG = 'nui://' .. GetCurrentResourceName() .. '/img/'

-- what the player is looking at (1-based indexes)
local st = {}
function Menu.Reset()
    st = {
        shop = { b = 1, c = 1, gender = 'male' },
        wshop = { c = 1, w = 1 },
        mine = { i = 1 }, wmine = { i = 1 },
        breed = { f = 1, m = 1 },
        custom = nil,
        page = 'home',
    }
end
Menu.Reset()

local function fmt(n)
    local x = math.floor((tonumber(n) or 0) + 0.5)
    local s = tostring(math.abs(x)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return (x < 0 and '-' or '') .. s
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function wrap(v, n) return n < 1 and 1 or ((v - 1) % n) + 1 end
local function data() return Stable.data or {} end
local function svc(k) return Stable.current and Stable.current.services and Stable.current.services[k] == true end
local function breeds() return data().shopHorses or {} end
local function wcats() return data().shopWagons or {} end
local function myHorses() return data().horses or {} end
local function myWagons() return data().wagons or {} end
local function priceNote(p) return (tonumber(p) or 0) > 0 and ('$' .. fmt(p)) or T('free') end

local function statsFor(breed, coat)
    local s = {}
    for k, v in pairs(breed.stats or {}) do s[k] = v end
    if coat.fixedStats then
        s.speed, s.accel = coat.fixedStats[1], coat.fixedStats[2]
        s.handling = clamp(math.ceil(coat.fixedStats[3] / 2.5), 1, 4)
    end
    return s
end

local function horseStats(s)
    local h = s.handling or 2
    return {
        type = 'stats', rows = {
            { label = T('speed'), value = s.speed or 0 },
            { label = T('accel'), value = s.accel or 0 },
            { label = T('health'), value = s.health or 0 },
            { label = T('stamina'), value = s.stamina or 0 },
            { label = T('handling'), value = h * 2.5, tone = 'gold', text = T('handling_' .. h) },
        },
    }
end

local function hints(list, home)
    if not home then list[#list + 1] = { 'ESC', T('hint_back') } end
    return list
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local Pages = {}

function Pages.home()
    local d = data()
    local lim = d.limits or {}
    local items = {}
    if svc('buyHorses') then items[#items + 1] = { label = T('home_buy_horse'), icon = 'horse', img = IMG .. 'horseicon.png', go = 'shopHorse' } end
    items[#items + 1] = { label = T('home_my_horses'), icon = 'shoe', img = IMG .. 'horseicon2.png', go = 'myHorses', sub = ('%d / %s'):format(#myHorses(), lim.horses or '∞') }
    if svc('buyWagons') then items[#items + 1] = { label = T('home_buy_wagon'), icon = 'wagon', img = IMG .. 'wagonicon.png', go = 'shopWagon' } end
    items[#items + 1] = { label = T('home_my_wagons'), icon = 'wheel', img = IMG .. 'wagonicon2.png', go = 'myWagons', sub = ('%d / %s'):format(#myWagons(), lim.wagons or '∞') }
    if svc('breeding') and d.isTrainer then
        local n = #(d.breeding or {})
        items[#items + 1] = { label = T('home_breed'), icon = 'heart', go = 'breed', sub = n > 0 and T('breed_pending', n) or nil }
    end
    return { body = { { type = 'medals', size = 'big', items = items } }, hints = { { 'ESC', T('close') } } }
end

function Pages.shopHorse()
    local list = breeds()
    if #list == 0 then return { title = T('home_buy_horse'), body = { { type = 'empty', text = '—' } }, hints = hints({}) } end
    st.shop.b = clamp(st.shop.b, 1, #list)
    local b = list[st.shop.b]
    st.shop.c = clamp(st.shop.c, 1, #b.coats)
    local c = b.coats[st.shop.c]
    local s = statsFor(b, c)
    local seals = {}
    for _, cur in ipairs({ 'cash', 'gold' }) do
        local amount = tonumber(c[cur]) or 0
        if amount > 0 then
            local price = cur == 'gold' and ('%s %s'):format(fmt(amount), T('gold')) or ('$' .. fmt(amount))
            seals[#seals + 1] = {
                cur = cur, amount = amount, value = c.id, label = T(cur),
                prompt = { title = T('name_horse'), ok = T('confirm'), cancel = T('cancel'), note = ('%s · %s · %s'):format(b.breed, c.label, price),
                           fields = { { name = 'name', max = 24, required = true, pattern = '\\S.*\\S' } } },
            }
        end
    end
    return {
        title = T('home_buy_horse'),
        body = {
            { type = 'carousel', id = 'breed', size = 'big', label = b.breed, count = ('%d / %d'):format(st.shop.b, #list), action = 'nav', keys = 'updown', listAction = 'breedList' },
            { type = 'carousel', id = 'coat', size = 'small', label = c.label, count = ('%d / %d'):format(st.shop.c, #b.coats), action = 'nav', keys = 'leftright' },
            { type = 'row', align = 'center', children = {
                { type = 'tier', label = T('tier'), value = ROMAN[c.tier] or tostring(c.tier) },
                { type = 'segmented', style = 'round', value = st.shop.gender, action = 'shopGender',
                  options = { { value = 'male', icon = 'male', label = T('male') }, { value = 'female', icon = 'female', label = T('female') } } },
            } },
            { type = 'facts', items = {
                { icon = 'bag', text = fmt(c.storage) }, { icon = 'pelt', text = fmt(c.pelts) },
                { text = ('%s: %s'):format(T('breeding'), T(c.canBreed and 'yes' or 'no')) },
            } },
            horseStats(s),
            { type = 'text', text = b.info or '' },
            { type = 'seals', action = 'buyHorse', items = seals },
        },
        hints = hints({ { '← →', T('coat') }, { '↑ ↓', T('breed') }, { '⟲', T('hint_rotate') } }),
    }
end

local function horseBadges(h)
    local b = {}
    if h.active and h.spawned then b[#b + 1] = { text = T('active'), tone = 'gold' } end
    if h.dead then b[#b + 1] = { text = T('injured'), tone = 'bad' } end
    if h.old then b[#b + 1] = { text = T('old') } end
    if h.special then b[#b + 1] = { text = T('special'), tone = 'gold' } end
    if h.foal then b[#b + 1] = { text = T('foal') } end
    if h.breedingUntil then b[#b + 1] = { text = T(h.pregnant and 'pregnant' or 'breeding_now'), tone = 'gold' } end
    if not h.here then b[#b + 1] = { text = ('%s · %s'):format(T('elsewhere'), h.stableLabel) } end
    return b
end

local function otherStables(current)
    local opts = {}
    for _, s in ipairs(Config.Stables) do
        if s.id ~= current then opts[#opts + 1] = { value = s.id, label = s.label } end
    end
    return opts
end

-- rename / transfer / sell: same for horses and wagons
local function commonActions(kind, x)
    local list = {}
    if svc('transfer') then
        local price = (tonumber(Config.TransferPrice) or 0) > 0 and (' · $' .. fmt(Config.TransferPrice)) or ''
        list[#list + 1] = { label = T('a_transfer'), icon = 'transfer', action = 'transfer', value = { kind = kind, id = x.id },
            prompt = { title = T('transfer_to') .. price, ok = T('confirm'), cancel = T('cancel'),
                       fields = { { type = 'segmented', style = 'list', cols = 1, name = 'to', required = true, options = otherStables(x.stable) } } } }
    end
    list[#list + 1] = { label = T('a_rename'), icon = 'quill', action = 'rename', value = { kind = kind, id = x.id },
        prompt = { title = T('rename_title'), ok = T('confirm'), cancel = T('cancel'), note = priceNote(x.rename),
                   fields = { { name = 'name', value = x.name, max = 24, required = true, pattern = '\\S.*\\S' } } } }
    list[#list + 1] = { label = T('a_sell'), icon = 'coin', warn = true, action = 'sell', value = { kind = kind, id = x.id },
        confirm = { title = T('a_sell'), text = T('sell_confirm', x.name, fmt(x.sell and x.sell.amount)), danger = true, ok = T('a_sell'), cancel = T('cancel') } }
    return list
end

function Pages.myHorses()
    local list = myHorses()
    if #list == 0 then
        return {
            title = T('home_my_horses'), hints = hints({}),
            body = { { type = 'empty', text = T('none_owned_horse'), button = svc('buyHorses') and { label = T('home_buy_horse'), go = 'shopHorse' } or nil } },
        }
    end
    st.mine.i = clamp(st.mine.i, 1, #list)
    local h = list[st.mine.i]
    local locked = not h.here
    local actions = {
        { label = T('a_take'), icon = 'take', action = 'takeOut', value = { kind = 'horse', id = h.id },
          disabled = locked or h.dead or (h.breedingUntil ~= nil and not h.pregnantOut) },
    }
    if svc('customize') then actions[#actions + 1] = { label = T('a_equip'), icon = 'saddle', action = 'equipStart', value = h.id, disabled = locked } end
    if svc('coloring') and data().canColor then actions[#actions + 1] = { label = T('a_coat'), icon = 'palette', action = 'coatStart', value = h.id, disabled = locked } end
    actions[#actions + 1] = { label = T('a_heal'), icon = 'heal', action = 'heal', value = h.id, disabled = not (h.dead or (h.health or 100) < 100),
        confirm = { title = T('a_heal'), text = T('heal_confirm', h.name, fmt(h.heal)), ok = T('confirm'), cancel = T('cancel') } }
    for _, a in ipairs(commonActions('horse', h)) do actions[#actions + 1] = a end

    local prog = clamp((h.xp or 0) / math.max(1, h.xpMax or 1), 0, 1)
    return {
        title = T('home_my_horses'), count = ('%d / %d'):format(st.mine.i, #list),
        body = {
            { type = 'carousel', id = 'mine', size = 'big', label = h.name, action = 'nav', keys = 'leftright' },
            { type = 'text', style = 'sub', text = ('%s · %s'):format(h.breed, h.coatLabel) },
            { type = 'badges', items = horseBadges(h) },
            { type = 'grid', template = 'auto 1fr', children = {
                { type = 'ring', value = prog, label = T('training') },
                { type = 'kv', items = {
                    { label = 'XP', value = ('%s / %s'):format(fmt(h.xp), fmt(h.xpMax)) },
                    { label = T('gender'), value = T(h.gender == 'female' and 'female' or 'male') },
                    { label = T('age'), value = h.age and ('%s %s'):format(h.age, T('years')) or '—' },
                    { label = T('at_stable'), value = h.stableLabel },
                    { label = T('bond'), rating = h.bond or 0, max = 4, icon = 'shoe' },
                } },
            } },
            { type = 'stats', rows = {
                { label = T('health'), kind = 'bar', value = h.health or 0, tone = 'red', text = h.health or 0 },
                { label = T('stamina'), kind = 'bar', value = h.stamina or 0, tone = 'amber', text = h.stamina or 0 },
                { label = T('hunger'), kind = 'bar', value = h.hunger or 0, text = math.floor((h.hunger or 0) + 0.5) },
                { label = T('thirst'), kind = 'bar', value = h.thirst or 0, tone = 'blue', text = math.floor((h.thirst or 0) + 0.5) },
                { label = T('clean'), kind = 'bar', value = 100 - (h.dirt or 0), text = math.floor(100 - (h.dirt or 0) + 0.5) },
                { label = T('hooves'), kind = 'bar', value = h.hoof or 100, tone = 'amber', text = math.floor((h.hoof or 100) + 0.5) },
                { label = T('courage'), value = math.floor(h.courage or 0), text = h.courage or 0 },
                { label = T('affinity'), value = math.floor(h.affinity or 0), tone = 'gold', text = h.affinity or 0 },
            } },
            { type = 'medals', size = 'small', items = actions },
        },
        hints = hints({ { '← →', T('hint_nav') }, { '⟲', T('hint_rotate') } }),
    }
end

local function breedReason(h)
    if not h then return '' end
    if h.canBreed then return T('breed_ok') end
    if h.special then return T('breed_r_special') end
    if h.foal then return T('breed_r_young') end
    if h.breedingUntil then return T(h.pregnant and 'pregnant' or 'breed_r_busy') end
    if (h.breedWait or 0) > 0 then return T('breed_r_wait', math.ceil(h.breedWait / 60)) end
    if h.dead then return T('injured') end
    return T('breed_r_no')
end

local function breedLists()
    local f, m = {}, {}
    for _, h in ipairs(myHorses()) do
        if h.here then
            if h.gender == 'female' then f[#f + 1] = h else m[#m + 1] = h end
        end
    end
    return f, m
end
Menu.BreedLists = breedLists

local function mmss(s)
    s = math.floor(tonumber(s) or 0)
    return ('%02d:%02d'):format(s // 60, s % 60)
end

function Pages.breed()
    local f, m = breedLists()
    st.breed.f = clamp(st.breed.f, 1, math.max(1, #f))
    st.breed.m = clamp(st.breed.m, 1, math.max(1, #m))
    local a, b = f[st.breed.f], m[st.breed.m]
    local cfg = data().breedCfg or {}
    local ok = a and b and a.canBreed and b.canBreed
    local result = (a and b) and (a.breed == b.breed and T('breed_same', a.breed) or T('breed_mix', a.breed, b.breed)) or '—'

    local function side(h, label)
        return {
            { type = 'section', label = label },
            { type = 'text', style = 'sub', text = h and ('%s · %s'):format(h.breed, h.coatLabel) or '—' },
            { type = 'text', style = 'sub', text = h and ('%s %s · %s / %s XP'):format(h.age or '—', T('years'), fmt(h.xp), fmt(h.xpMax)) or '' },
            { type = 'badges', items = { { text = breedReason(h) ~= '' and breedReason(h) or T('breed_none'), tone = (h and h.canBreed) and 'gold' or 'bad' } } },
        }
    end

    local body = {}
    local function add(list) for _, n in ipairs(list) do body[#body + 1] = n end end
    add({ { type = 'carousel', id = 'bf', size = 'small', label = a and a.name or T('breed_no_female'), count = #f > 0 and ('%d / %d'):format(st.breed.f, #f) or '', action = 'nav', keys = 'leftright', disabled = #f < 2 } })
    add(side(a, T('female')))
    add({ { type = 'carousel', id = 'bm', size = 'small', label = b and b.name or T('breed_no_male'), count = #m > 0 and ('%d / %d'):format(st.breed.m, #m) or '', action = 'nav', keys = 'updown', disabled = #m < 2 } })
    add(side(b, T('male')))
    local kv = { { label = T('breed_result'), value = result }, { label = T('breed_time'), value = mmss(cfg.time) } }
    if (tonumber(cfg.price) or 0) > 0 then kv[#kv + 1] = { label = T('total'), value = '$' .. fmt(cfg.price) } end
    add({
        { type = 'kv', items = kv },
        { type = 'row', align = 'center', children = { {
            type = 'button', label = T('breed_go'), action = 'breed', disabled = not ok,
            value = a and b and { mother = a.id, father = b.id } or nil,
            confirm = a and b and { title = T('home_breed'), text = T('breed_confirm', a.name, b.name), ok = T('breed_go'), cancel = T('cancel') } or nil,
        } } },
    })
    local pending = {}
    for _, p in ipairs(data().breeding or {}) do
        local mo, fa
        for _, x in ipairs(myHorses()) do
            if x.id == p.mother then mo = x end
            if x.id == p.father then fa = x end
        end
        pending[#pending + 1] = { label = ('%s × %s'):format(mo and mo.name or '?', fa and fa.name or '?'), seconds = p.readyIn }
    end
    if #pending > 0 then add({ { type = 'section', label = T('breed_pending_title') }, { type = 'timers', items = pending } }) end

    return { title = T('home_breed'), body = body, hints = hints({ { '← →', T('female') }, { '↑ ↓', T('male') }, { '⟲', T('hint_rotate') } }) }
end

local function wagonTicks(label, value) return { label = label, value = value } end

function Pages.shopWagon()
    local cats = wcats()
    if #cats == 0 then return { title = T('home_buy_wagon'), body = { { type = 'empty', text = '—' } }, hints = hints({}) } end
    st.wshop.c = clamp(st.wshop.c, 1, #cats)
    local cat = cats[st.wshop.c]
    st.wshop.w = clamp(st.wshop.w, 1, #cat.wagons)
    local w = cat.wagons[st.wshop.w]
    local facts = { { icon = 'box', text = fmt(w.storage) } }
    if (w.animals or 0) > 0 then facts[#facts + 1] = { icon = 'pelt', text = fmt(w.animals) } end
    if w.work then facts[#facts + 1] = { text = ('%s · %s'):format(T('work'), T('work_' .. w.work)), badge = true, tone = 'gold' } end
    local seals = {}
    for _, cur in ipairs({ 'cash', 'gold' }) do
        local amount = tonumber(w[cur]) or 0
        if amount > 0 then
            local price = cur == 'gold' and ('%s %s'):format(fmt(amount), T('gold')) or ('$' .. fmt(amount))
            seals[#seals + 1] = {
                cur = cur, amount = amount, value = w.model, label = T(cur),
                prompt = { title = T('name_wagon'), ok = T('confirm'), cancel = T('cancel'), note = price,
                           fields = { { name = 'name', value = w.label, max = 24, required = true, pattern = '\\S.*\\S' } } },
            }
        end
    end
    return {
        title = T('home_buy_wagon'),
        body = {
            { type = 'carousel', id = 'wcat', size = 'big', label = cat.category, count = ('%d / %d'):format(st.wshop.c, #cats), action = 'nav', keys = 'updown', listAction = 'wcatList' },
            { type = 'carousel', id = 'wag', size = 'small', label = w.label, count = ('%d / %d'):format(st.wshop.w, #cat.wagons), action = 'nav', keys = 'leftright' },
            { type = 'facts', items = facts },
            { type = 'stats', rows = {
                wagonTicks(T('storage'), math.ceil(clamp((w.storage or 0) / 200, 1, 10))),
                wagonTicks(T('animals'), math.ceil(clamp((w.animals or 0) / 15, 0, 10))),
            } },
            { type = 'text', text = w.description or '' },
            { type = 'seals', action = 'buyWagon', items = seals },
        },
        hints = hints({ { '← →', T('hint_nav') }, { '↑ ↓', T('storage') }, { '⟲', T('hint_rotate') } }),
    }
end

function Pages.myWagons()
    local list = myWagons()
    if #list == 0 then
        return {
            title = T('home_my_wagons'), hints = hints({}),
            body = { { type = 'empty', text = T('none_owned_wagon'), button = svc('buyWagons') and { label = T('home_buy_wagon'), go = 'shopWagon' } or nil } },
        }
    end
    st.wmine.i = clamp(st.wmine.i, 1, #list)
    local w = list[st.wmine.i]
    local cond = math.floor((w.health or 0) / 10 + 0.5)
    local badges = {}
    if w.active and w.spawned then badges[#badges + 1] = { text = T('active'), tone = 'gold' } end
    if cond < 10 then badges[#badges + 1] = { text = T('a_repair'), tone = 'bad' } end
    if not w.here then badges[#badges + 1] = { text = ('%s · %s'):format(T('elsewhere'), w.stableLabel) } end
    local facts = { { icon = 'box', text = fmt(w.storage) } }
    if (w.animals or 0) > 0 then facts[#facts + 1] = { icon = 'pelt', text = fmt(w.animals) } end
    if w.work then facts[#facts + 1] = { text = T('work_' .. w.work) } end

    local actions = { { label = T('a_take'), icon = 'take', action = 'takeOut', value = { kind = 'wagon', id = w.id }, disabled = not w.here or w.broken } }
    if svc('customizeWagons') then actions[#actions + 1] = { label = T('a_custom'), icon = 'palette', action = 'wagonStart', value = w.id, disabled = not w.here } end
    actions[#actions + 1] = { label = T('a_repair'), icon = 'hammer', action = 'repair', value = w.id, disabled = (w.health or 0) >= 1000,
        confirm = { title = T('a_repair'), text = ('%s · $%s'):format(w.name, fmt(w.repair)), ok = T('confirm'), cancel = T('cancel') } }
    for _, a in ipairs(commonActions('wagon', w)) do actions[#actions + 1] = a end

    return {
        title = T('home_my_wagons'), count = ('%d / %d'):format(st.wmine.i, #list),
        body = {
            { type = 'carousel', id = 'wmine', size = 'big', label = w.name, action = 'nav', keys = 'leftright' },
            { type = 'text', style = 'sub', text = ('%s · %s'):format(w.label, w.category) },
            { type = 'badges', items = badges },
            { type = 'facts', items = facts },
            { type = 'stats', rows = { { label = T('condition'), kind = 'bar', value = cond, tone = 'amber', text = cond .. '%' } } },
            { type = 'kv', items = {
                { label = T('at_stable'), value = w.stableLabel },
                { label = T('a_sell'), value = ((w.sell and w.sell.currency == 'gold') and '' or '$') .. fmt(w.sell and w.sell.amount) },
            } },
            { type = 'medals', size = 'small', items = actions },
        },
        hints = hints({ { '← →', T('hint_nav') }, { '⟲', T('hint_rotate') } }),
    }
end

---------------------------------------------------------------------------
-- Customisation (tack, coat, wagon): same page, three kinds
---------------------------------------------------------------------------
local function customTotal()
    local c, P = st.custom, Config.Prices or {}
    local total = 0
    if c.kind == 'equip' then
        for _, cat in ipairs(c.keys) do
            if c.values[cat] ~= c.orig[cat] and (c.values[cat] or 0) > 0 then total = total + ((P.components or {})[cat] or 0) end
        end
    elseif c.kind == 'coat' then
        for _, k in ipairs(c.keys) do
            if c.values[k] ~= c.orig[k] then total = P.coloring or 0 break end
        end
    elseif c.kind == 'wagon' then
        for _, k in ipairs(c.keys) do
            if c.values[k] ~= c.orig[k] then total = total + ((P.wagon or {})[k] or 0) end
        end
        local was = {}
        for _, e in ipairs(c.origExtras) do was[e] = true end
        for _, e in ipairs(c.extrasOn) do
            if not was[e] then total = total + ((P.wagon or {}).extra or 0) end
        end
    end
    return total
end

local function totalPatch()
    return { total = { items = { { label = T('total'), value = '$' .. fmt(customTotal()) } } } }
end

function Pages.custom()
    local c = st.custom
    if not c then return nil end
    local items = {}
    for _, k in ipairs(c.keys) do
        local t = c.tiles[k]
        items[#items + 1] = { id = k, label = T(k), value = c.values[k], count = t.max, min = 0, none = t.none, noneLabel = T('off'), captions = t.captions }
    end
    local body = { { type = 'dials', action = 'custom', items = items } }
    if c.kind == 'wagon' and #c.extras > 0 then
        local opts = {}
        for _, e in ipairs(c.extras) do opts[#opts + 1] = { value = e, label = ('%s %s'):format(T('extra'), e) } end
        body[#body + 1] = { type = 'section', label = T('extras') }
        body[#body + 1] = { type = 'chips', value = c.extrasOn, action = 'extras', options = opts }
    end
    body[#body + 1] = { type = 'kv', id = 'total', cols = 1, items = totalPatch().total.items }
    return {
        title = c.title, count = c.subtitle, body = body,
        footer = { buttons = {
            { type = 'button', label = T('cancel'), style = 'ghost', small = true, action = 'customCancel' },
            { type = 'button', label = T('confirm'), small = true, action = 'customSave' },
        } },
        hints = hints({ { '⟲', T('hint_rotate') } }),
    }
end

---------------------------------------------------------------------------
-- View
---------------------------------------------------------------------------
function Menu.View()
    local d = data()
    local pages = {}
    for id, build in pairs(Pages) do pages[id] = build() end
    return {
        eyebrow = T('title'), title = Stable.current and Stable.current.label or '',
        page = 'home',
        camera = { drag = true, wheel = true },
        footer = { money = { cash = d.money and d.money.cash or 0, gold = d.money and d.money.gold or 0 } },
        pages = pages,
    }
end

---------------------------------------------------------------------------
-- Preview of what is selected on the current page (showroom)
---------------------------------------------------------------------------
function Menu.Preview(page)
    page = page or st.page
    if page ~= 'breed' and Stable.ClearBreed then Stable.ClearBreed() end
    if page == 'shopHorse' then
        local b = breeds()[st.shop.b]
        local coat = b and b.coats[st.shop.c] and FKS.GetCoat(b.coats[st.shop.c].id)
        if coat then
            Stable.ShowHorse(coat.model, { outfit = coat.outfit, coat = coat.coat, maneTail = coat.maneTail, gender = st.shop.gender })
        end
    elseif page == 'myHorses' then
        local h = myHorses()[st.mine.i]
        if h then Stable.ShowHorse(h.model, Stable.HorseLook(h)) else Stable.ClearPreview() end
    elseif page == 'shopWagon' then
        local cat = wcats()[st.wshop.c]
        local w = cat and cat.wagons[st.wshop.w]
        if w then Stable.ShowWagon(w.model, {}) end
    elseif page == 'myWagons' then
        local w = myWagons()[st.wmine.i]
        if w then Stable.ShowWagon(w.model, w.custom) else Stable.ClearPreview() end
    elseif page == 'breed' then
        local f, m = breedLists()
        Stable.ShowBreed(f[st.breed.f] and f[st.breed.f].id, m[st.breed.m] and m[st.breed.m].id)
    elseif page == 'home' then
        Stable.ClearPreview()
    end
end

local function refresh() return { view = Menu.View() } end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
UI.On('close', function() Stable.Close() end)

UI.On('page', function(d)
    if d.from == 'custom' and st.custom then
        st.custom = nil   -- ESC out of the customisation: nothing saved
    end
    st.page = d.to
    if d.to ~= 'custom' then Menu.Preview(d.to) end
end)

-- arrows of every carousel
local NAV = {
    breed = function(dir) st.shop.b = wrap(st.shop.b + dir, #breeds()); st.shop.c = 1 end,
    coat = function(dir) local b = breeds()[st.shop.b]; if b then st.shop.c = wrap(st.shop.c + dir, #b.coats) end end,
    mine = function(dir) st.mine.i = wrap(st.mine.i + dir, math.max(1, #myHorses())) end,
    wcat = function(dir) st.wshop.c = wrap(st.wshop.c + dir, #wcats()); st.wshop.w = 1 end,
    wag = function(dir) local c = wcats()[st.wshop.c]; if c then st.wshop.w = wrap(st.wshop.w + dir, #c.wagons) end end,
    wmine = function(dir) st.wmine.i = wrap(st.wmine.i + dir, math.max(1, #myWagons())) end,
    bf = function(dir) local f = breedLists(); if #f > 0 then st.breed.f = wrap(st.breed.f + dir, #f) end end,
    bm = function(dir) local _, m = breedLists(); if #m > 0 then st.breed.m = wrap(st.breed.m + dir, #m) end end,
}
UI.On('nav', function(d)
    local fn = NAV[d.id]
    if not fn then return end
    fn((tonumber(d.dir) or 1) < 0 and -1 or 1)
    Menu.Preview()
    return refresh()
end)

UI.On('shopGender', function(d)
    st.shop.gender = d.value == 'female' and 'female' or 'male'
    Menu.Preview()
    return refresh()
end)

-- click on the breed / category name: pick from the full list
local function pickFrom(title, list, current)
    local opts = {}
    for i, x in ipairs(list) do opts[i] = { value = i, label = x } end
    local res = UI.Prompt({ title = title, ok = T('confirm'), cancel = T('cancel'),
        fields = { { type = 'segmented', style = 'list', cols = #opts < 8 and 1 or 2, name = 'pick', value = current, required = true, options = opts } } })
    return res and tonumber(res.pick)
end

UI.On('breedList', function()
    local names = {}
    for i, b in ipairs(breeds()) do names[i] = ('%s (%d)'):format(b.breed, #b.coats) end
    local i = pickFrom(T('breed'), names, st.shop.b)
    if not i then return end
    st.shop.b, st.shop.c = i, 1
    Menu.Preview()
    return refresh()
end)

UI.On('wcatList', function()
    local names = {}
    for i, c in ipairs(wcats()) do names[i] = ('%s (%d)'):format(c.category, #c.wagons) end
    local i = pickFrom(T('storage'), names, st.wshop.c)
    if not i then return end
    st.wshop.c, st.wshop.w = i, 1
    Menu.Preview()
    return refresh()
end)

-- index of the newest horse / wagon (highest id) after a purchase
local function newest(list)
    local best = 1
    for i, x in ipairs(list) do if x.id > list[best].id then best = i end end
    return best
end

UI.On('buyHorse', function(d)
    local name = d.values and d.values.name
    local ok = Stable.Call('buyHorse', d.value, d.cur, st.shop.gender, name)
    if not ok then return end
    st.mine.i = newest(myHorses())
    return { view = Menu.View(), go = 'myHorses' }
end)

UI.On('buyWagon', function(d)
    local name = d.values and d.values.name
    local ok = Stable.Call('buyWagon', d.value, d.cur, name)
    if not ok then return end
    st.wmine.i = newest(myWagons())
    return { view = Menu.View(), go = 'myWagons' }
end)

UI.On('takeOut', function(d)
    local v = type(d.value) == 'table' and d.value or {}
    Stable.TakeOut(v.kind, v.id)
end)

UI.On('heal', function(d)
    Stable.Call('heal', d.value)
    return refresh()
end)

UI.On('repair', function(d)
    Stable.Call('repair', d.value)
    return refresh()
end)

UI.On('rename', function(d)
    local v = type(d.value) == 'table' and d.value or {}
    Stable.Call('rename', v.kind, v.id, d.values and d.values.name)
    return refresh()
end)

UI.On('transfer', function(d)
    local v = type(d.value) == 'table' and d.value or {}
    Stable.Call('transfer', v.kind, v.id, d.values and d.values.to)
    return refresh()
end)

UI.On('sell', function(d)
    local v = type(d.value) == 'table' and d.value or {}
    if Stable.Call('sell', v.kind, v.id) then
        if v.kind == 'wagon' then st.wmine.i = math.max(1, st.wmine.i - 1) else st.mine.i = math.max(1, st.mine.i - 1) end
        Menu.Preview()
    end
    return refresh()
end)

UI.On('breed', function(d)
    local v = type(d.value) == 'table' and d.value or {}
    Stable.Call('breed', v.mother, v.father)
    return refresh()
end)

-- start a customisation: builds the page and goes there
local function startCustom(c)
    st.custom = c
    return { view = Menu.View(), go = 'custom' }
end

UI.On('equipStart', function(d)
    local h = Stable.FindOwned('horse', d.value)
    if not h then return end
    local c = { kind = 'equip', id = h.id, title = T('a_equip'), subtitle = h.name, keys = {}, tiles = {}, values = {}, orig = {} }
    for _, cat in ipairs(Look.Categories) do
        c.keys[#c.keys + 1] = cat
        c.tiles[cat] = { max = #(Config.HorseComponents[cat] or {}), none = true }
        local idx = Look.IndexOf(cat, h.components and h.components[cat]) or 0
        c.values[cat], c.orig[cat] = idx, idx
    end
    return startCustom(c)
end)

local COAT_KEYS = { 'coat_palette', 'coat_tint0', 'coat_tint1', 'coat_tint2', 'mane_palette', 'mane_tint0', 'mane_tint1', 'mane_tint2' }
UI.On('coatStart', function(d)
    local h = Stable.FindOwned('horse', d.value)
    if not h then return end
    local co, mt = h.coat or { 0, 0, 0, 0 }, h.maneTail or { 0, 0, 0, 0 }
    local pal = #Config.ColorPalettes
    local c = { kind = 'coat', id = h.id, title = T('a_coat'), subtitle = h.name, keys = COAT_KEYS, tiles = {}, values = {}, orig = {},
                hadCoat = h.coat ~= nil, hadMane = h.maneTail ~= nil }
    local start = { co[1], co[2], co[3], co[4], mt[1], mt[2], mt[3], mt[4] }
    for i, k in ipairs(COAT_KEYS) do
        local palette = k:find('palette') ~= nil
        c.tiles[k] = { max = palette and pal or 254, none = palette }
        c.values[k], c.orig[k] = start[i] or 0, start[i] or 0
    end
    return startCustom(c)
end)

UI.On('wagonStart', function(d)
    local w = Stable.FindOwned('wagon', d.value)
    if not w then return end
    local m, W = w.model:lower(), Config.WagonCustom
    local max = {
        livery = W.liveries[m] and #W.liveries[m] or 0, tint = W.tints[m] or 0,
        propset = W.propsets[m] and #W.propsets[m] or 0, lantern = W.lanterns[m] and #W.lanterns[m] or 0,
    }
    local cu = w.custom or {}
    local c = { kind = 'wagon', id = w.id, title = T('a_custom'), subtitle = w.name, keys = {}, tiles = {}, values = {}, orig = {},
                extras = W.extras[m] or {}, extrasOn = {}, origExtras = {} }
    for _, k in ipairs({ 'livery', 'tint', 'propset', 'lantern' }) do
        if max[k] > 0 then
            c.keys[#c.keys + 1] = k
            local captions
            if k == 'livery' then
                captions = {}
                for i, n in ipairs(W.liveries[m]) do captions[i] = tostring(n):gsub('^%d+%s*%-%s*', '') end
            end
            c.tiles[k] = { max = max[k], none = true, captions = captions }
            c.values[k], c.orig[k] = cu[k] or 0, cu[k] or 0
        end
    end
    for _, e in ipairs(cu.extras or {}) do c.extrasOn[#c.extrasOn + 1] = e; c.origExtras[#c.origExtras + 1] = e end
    return startCustom(c)
end)

local function coatPayload(c)
    local v, o = c.values, c.orig
    local dirty = function(prefix)
        for _, k in ipairs(COAT_KEYS) do
            if k:sub(1, #prefix) == prefix and v[k] ~= o[k] then return true end
        end
    end
    return
        (dirty('coat') or c.hadCoat) and { v.coat_palette, v.coat_tint0, v.coat_tint1, v.coat_tint2 } or nil,
        (dirty('mane') or c.hadMane) and { v.mane_palette, v.mane_tint0, v.mane_tint1, v.mane_tint2 } or nil
end

local function wagonPayload(c)
    local v = c.values
    return { livery = v.livery or 0, tint = v.tint or 0, propset = v.propset or 0, lantern = v.lantern or 0, extras = c.extrasOn }
end

local function previewCustom(changed)
    local c = st.custom
    if c.kind == 'equip' then
        Stable.PreviewComponent(changed, c.values[changed])
    elseif c.kind == 'coat' then
        local coat, mane = coatPayload(c)
        Stable.PreviewCoat(coat, mane)
    else
        Stable.PreviewWagon(c.id, wagonPayload(c))
    end
end

UI.On('custom', function(d)
    local c = st.custom
    if not c or not c.tiles[d.id] then return end
    c.values[d.id] = math.floor(tonumber(d.value) or 0)
    previewCustom(d.id)
    return { patch = totalPatch() }
end)

UI.On('extras', function(d)
    local c = st.custom
    if not c or c.kind ~= 'wagon' then return end
    c.extrasOn = {}
    for _, e in ipairs(type(d.value) == 'table' and d.value or {}) do c.extrasOn[#c.extrasOn + 1] = tonumber(e) or e end
    previewCustom()
    return { patch = totalPatch() }
end)

UI.On('customSave', function()
    local c = st.custom
    if not c then return end
    local ok
    if c.kind == 'equip' then
        ok = Stable.SaveComponents(c.id, c.values)
    elseif c.kind == 'coat' then
        local coat, mane = coatPayload(c)
        ok = Stable.Call('saveCoat', c.id, coat, mane)
        if ok and Horse.id == c.id then Horse.Reapply() end
    else
        ok = Stable.Call('saveWagonCustom', c.id, wagonPayload(c))
        if ok and Wagon.id == c.id then Wagon.Reapply() end
    end
    if not ok then return end
    st.custom = nil
    return { back = true, view = Menu.View() }
end)

UI.On('customCancel', function()
    st.custom = nil
    return { back = true, view = Menu.View() }
end)

-- drag rotates the animal / wagon on display, the wheel zooms
UI.On('camera', function(d)
    if d.kind == 'drag' then
        Stable.Rotate(tonumber(d.dx) or 0)
    elseif d.kind == 'wheel' then
        Stable.Zoom((tonumber(d.value) or 0) * 100)
    end
end)
