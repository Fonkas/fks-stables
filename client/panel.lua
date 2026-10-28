-- Small menus outside the stable (feed, wagon storage, wild horse, training), drawn by fks-core.
--   Panel.Open({ eyebrow, title, desc?, items = { item, ... } })                       -- one page
--   Panel.Open({ eyebrow, title, page = 'home', pages = { home = { title?, desc?, items }, ... } })
-- item = { title, sub?, tag?, icon?, disabled?, go?, confirm?, prompt?, stay?, onSelect = fn(values) }
--   disabled: shown locked · go: opens another page · confirm / prompt: asked by the NUI first
--   (the prompt answers arrive as `values`) · stay: the panel stays open after onSelect
-- The panel closes before onSelect runs, so onSelect can open another panel, animate, etc.

Panel = { open = false }

local items = {}

local function Page(id, p)
    local rows = {}
    for i, it in ipairs(p.items or {}) do
        local key = id .. ':' .. i
        items[key] = it
        local row = { value = key, title = it.title, sub = it.sub, tag = it.tag, icon = it.icon }
        if it.disabled then
            row.variant = 'locked'
        else
            row.go, row.confirm, row.prompt = it.go, it.confirm, it.prompt
            if it.onSelect then row.action = 'panel' end
        end
        rows[#rows + 1] = row
    end
    if #rows == 0 then rows[1] = { variant = 'empty', title = p.empty or '-' } end
    return {
        title = p.title, desc = p.desc,
        body = { { type = 'list', items = rows, selected = '', expand = 'none' } },
        hints = { { 'ESC', _LU('close') } },
    }
end

function Panel.Open(o)
    if Stable.open then return false end -- the stable menu is this script's panel
    items = {}
    local pages = {}
    if o.pages then
        for id, p in pairs(o.pages) do pages[id] = Page(id, p) end
    else
        pages.home = Page('home', o)
    end
    Panel.open = true
    if not UI.Open({ eyebrow = o.eyebrow, title = o.title, page = o.page or 'home', pages = pages }) then
        Panel.open = false -- another FKS screen is open
        return false
    end
    return true
end

function Panel.Close()
    if not Panel.open then return end
    Panel.open = false
    UI.Close()
end

-- called by the close handler of client/menu.lua (ESC, death...)
function Panel.Closed()
    Panel.open = false
    items = {}
end

UI.On('panel', function(d)
    local it = Panel.open and items[d.value]
    if not it then return end
    if not it.stay then Panel.Close() end
    it.onSelect(d.values or {})
end)
