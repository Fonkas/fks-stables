-- Language selection: Config.Locale picks a file from locales/. Any key missing from that language falls back
-- to English, so a partial translation never shows raw keys.
--   Locale   = in-game texts (_L)
--   LocaleUI = stable menu texts (_LU; the menu is drawn by fks-core)

local lang = Config.Locale or 'en'
if not (Locales and Locales[lang]) then
    print(('^3[fks-stables] Locale "%s" not found - using "en".^0'):format(tostring(lang)))
    lang = 'en'
end

local function Merge(section)
    local t = {}
    for k, v in pairs((Locales.en or {})[section] or {}) do t[k] = v end
    for k, v in pairs(Locales[lang][section] or {}) do t[k] = v end
    return t
end

Locale = Merge('game')
LocaleUI = Merge('ui')

function _L(key, ...)
    local s = Locale[key] or key
    if select('#', ...) > 0 then return s:format(...) end
    return s
end

-- stable menu texts (the menu is drawn by fks-core)
function _LU(key, ...)
    local s = LocaleUI[key] or key
    if select('#', ...) > 0 then
        local ok, res = pcall(string.format, s, ...)
        if ok then return res end
    end
    return s
end
