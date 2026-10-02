#!/usr/bin/env python3
"""Syntax-check + smoke-test the assembled wtrlab.lua (v1.1.9).

Stubs out NoveLA-specific globals (log_error, log_info, httpRequest,
url_encode, html_select_first, etc.) so we can load the whole plugin in
lupa and exercise:
  • getFilterList() — 28 filters: 17 finder filters + 11 "Tags:"
    dropdown pickers (the tags are VISIBLE again, as compact selects —
    the 882-chip tristate wall stays gone)
  • tagSearchResolve(text, cat) — v1.1.9 site-autocomplete semantics:
    exact match → id → single substring → ambiguous (error listing the
    matching tag names) → "keyword*" wildcard; phrase + word fallback;
    category scoping
  • getCatalogFiltered(0, filters) — with a stubbed http layer that
    captures the request URL; verifies text=/ti=/te= params, tag_pick
    merging, and the v1.1.9 HTML-first single-round-trip fetch
"""
import json
import sys
import lupa.luajit21

PLUGIN = "/home/z/my-project/download/wtrlab.lua"

with open(PLUGIN, encoding="utf-8") as f:
    plugin_src = f.read()

lua = lupa.luajit21.LuaRuntime(unpack_returned_tuples=True)

# Captured requests: list of (method, url) tuples
captured_requests = []
# Scripted responses keyed by URL substring
scripted_responses = {}

stub_globals = {
    "log_error": lambda *a: None,
    "log_info": lambda *a: None,
    "url_encode": lambda s: s and str(s).replace(" ", "+") or "",
    "httpRequest": lambda *a, **kw: None,
    "html_select_first": lambda *a: None,
    "html_select": lambda *a: [],
    "html_text": lambda *a: "",
    "json_encode": lambda o: "{}",
    "string_split": lambda s, sep: str(s).split(sep) if s else [],
    "string_clean": lambda s: " ".join(str(s or "").split()),
    "sha1": lambda s: "stub",
    "sha256": lambda s: "stub",
    "base64": lambda s: "stub",
    "settings_get_string": lambda k, d: d,
    "settings_put_string": lambda k, v: None,
    "sleep_ms": lambda ms: None,
    "get_preference": lambda k: "",
    "set_preference": lambda k, v: None,
}
for k, v in stub_globals.items():
    lua.globals()[k] = v

# http_get / http_post capture URL and return scripted responses
lua.execute("""
function http_get(url, cfg)
    _CAPTURED[#_CAPTURED + 1] = { method = "GET", url = url }
    for pat, resp in pairs(_SCRIPTED) do
        if string.find(url, pat, 1, true) then
            if resp == "__FAIL__" then return { success = false, code = 404, body = "" } end
            return { success = true, code = 200, body = resp, headers = {} }
        end
    end
    return { success = false, code = 404, body = "", headers = {} }
end
function http_post(url, body, cfg)
    _CAPTURED[#_CAPTURED + 1] = { method = "POST", url = url }
    for pat, resp in pairs(_SCRIPTED) do
        if string.find(url, pat, 1, true) then
            if resp == "__FAIL__" then return { success = false, code = 404, body = "" } end
            return { success = true, code = 200, body = resp, headers = {} }
        end
    end
    return { success = false, code = 404, body = "", headers = {} }
end
function os_time() return 1725350000000 end
""")
g = lua.globals()
g._CAPTURED = lua.table()
g._SCRIPTED = lua.table()


try:
    lua.execute(plugin_src)
    print("LOADED: plugin parses successfully as Lua 5.1")
except lupa.luajit21.LuaError as e:
    print(f"FATAL: plugin failed to parse: {e}")
    sys.exit(1)

# ── real json_parse (compact pure-Lua JSON decoder; lupa's Python→Lua
# list conversion isn't ipairs-compatible, so decode inside Lua) ─────────
lua.execute(r"""
local function skipws(s, i)
    while i <= #s and (s:sub(i,i) == ' ' or s:sub(i,i) == '\t' or s:sub(i,i) == '\n' or s:sub(i,i) == '\r') do
        i = i + 1
    end
    return i
end
local function decode(s, i)
    i = skipws(s, i)
    local c = s:sub(i, i)
    if c == '{' then
        local t = {}
        i = skipws(s, i + 1)
        if s:sub(i, i) == '}' then return t, i + 1 end
        while true do
            local k
            k, i = decode(s, i)
            i = skipws(s, i)
            assert(s:sub(i, i) == ':', 'expected : at ' .. i)
            local v
            v, i = decode(s, i + 1)
            t[k] = v
            i = skipws(s, i)
            local d = s:sub(i, i)
            if d == ',' then i = i + 1
            elseif d == '}' then return t, i + 1
            else error('expected , or } at ' .. i) end
        end
    elseif c == '[' then
        local t = {}
        local n = 1
        i = skipws(s, i + 1)
        if s:sub(i, i) == ']' then return t, i + 1 end
        while true do
            local v
            v, i = decode(s, i)
            t[n] = v; n = n + 1
            i = skipws(s, i)
            local d = s:sub(i, i)
            if d == ',' then i = i + 1
            elseif d == ']' then return t, i + 1
            else error('expected , or ] at ' .. i) end
        end
    elseif c == '"' then
        local out = {}
        i = i + 1
        while true do
            local ch = s:sub(i, i)
            if ch == '"' then return table.concat(out), i + 1 end
            if ch == '\\' then
                local e = s:sub(i + 1, i + 1)
                if e == 'n' then out[#out + 1] = '\n'
                elseif e == 't' then out[#out + 1] = '\t'
                elseif e == 'r' then out[#out + 1] = '\r'
                elseif e == 'b' then out[#out + 1] = '\b'
                elseif e == 'f' then out[#out + 1] = '\f'
                elseif e == 'u' then
                    out[#out + 1] = string.char(tonumber(s:sub(i + 2, i + 5), 16) or 63)
                    i = i + 6
                    goto continue
                else out[#out + 1] = e end
                i = i + 2
            else
                out[#out + 1] = ch
                i = i + 1
            end
            ::continue::
        end
    elseif s:sub(i, i + 3) == 'true' then return true, i + 4
    elseif s:sub(i, i + 4) == 'false' then return false, i + 5
    elseif s:sub(i, i + 3) == 'null' then return nil, i + 4
    else
        local j = s:find('[^%-%d%.%deE+]', i)
        if not j then j = #s + 1 end
        local num = s:sub(i, j - 1)
        local n = tonumber(num)
        assert(n, 'bad number at ' .. i .. ': ' .. num)
        return n, j
    end
end
json_parse = function(s)
    if type(s) ~= 'string' or s == '' then return nil end
    local ok, v = pcall(decode, s, 1)
    if ok then return v end
    return nil
end
""")


def captured_urls():
    out = []
    t = g._CAPTURED
    n = len(t)
    for i in range(1, n + 1):
        out.append(str(t[i].url))
    return out

def clear_captured():
    g._CAPTURED = lua.table()

# ── Test 1: getFilterList v1.1.9 structure ─────────────────────────────
fl = g.getFilterList()
assert fl is not None and len(fl) > 0, "getFilterList returned empty/nil"
keys = {}
for i in range(1, len(fl) + 1):
    f = fl[i]
    keys[str(f.key)] = (str(f.type), len(f.options) if f.options is not None else 0)
print(f"getFilterList() returned {len(fl)} filters")

assert len(fl) == 28, f"expected 28 filters (17 finder + 11 tag pickers), got {len(fl)}"
print("PASS: 28 filters (17 finder + 11 'Tags: <category>' pickers)")

assert "title_search" in keys, "title_search filter missing"
assert keys["title_search"][0] == "text", "title_search must be a text filter"
print("PASS: title_search text filter present (novel finder in filters)")

assert "tag_category" in keys, "tag_category filter missing"
assert keys["tag_category"][0] == "select", "tag_category must be a select"
assert keys["tag_category"][1] == 12, f"tag_category should have 12 options, got {keys['tag_category'][1]}"
print("PASS: tag_category select (All + 11 categories) present")

assert "tag_search_inc" in keys and keys["tag_search_inc"][0] == "text"
assert "tag_search_exc" in keys and keys["tag_search_exc"][0] == "text"
print("PASS: tag_search_inc / tag_search_exc text filters present")

grouped_keys = [
    "tags_protagonist", "tags_power_systems", "tags_worldbuilding",
    "tags_socio_political", "tags_relationships", "tags_narrative",
    "tags_beings_factions", "tags_professional", "tags_tone",
    "tags_adaptations", "tags_misc"
]
for k in grouped_keys:
    assert k not in keys, f"grouped filter {k} still present (chip wall must stay gone)"
print("PASS: all 11 grouped tag TRISTATE filters stay removed (no chip wall)")

# v1.2.0: the tags are multi-select checkbox chip groups (several per category)
tag_pick_opts = 0
for i in range(1, 12):
    k = f"tag_pick_{i}"
    assert k in keys, f"{k} picker missing"
    assert keys[k][0] == "checkbox", f"{k} must be a checkbox group, got {keys[k][0]}"
    tag_pick_opts += keys[k][1]
assert tag_pick_opts == 888, f"tag chip groups should carry all 888 site tags (no Any), got {tag_pick_opts}"
print("PASS: 11 'Tags: <category>' multi-select checkbox chip groups (888 site tags, no Any placeholders)")

# the ONLY tristate must be genres (40 options) — no tag chip walls anywhere
tristates = {k: v for k, v in keys.items() if v[0] == "tristate"}
assert set(tristates) == {"genres"}, f"only genres may be a tristate, got {list(tristates)}"
assert tristates["genres"][1] == 40
print("PASS: genres is the only tristate filter (40 options)")

# ── Test 2: tagSearchResolve v1.1.9 semantics ──────────────────────────
lua.execute("""
function _resolve_to_str(text, cat)
    return table.concat(tagSearchResolve(text, cat) or {}, ",")
end
function _resolve_err(text, cat)
    local ok, err = pcall(tagSearchResolve, text, cat)
    if ok then return nil end
    return tostring(err)
end
""")
resolve_str = g._resolve_to_str
resolve_err = g._resolve_err

def ids(text, cat=None):
    return sorted(x for x in str(resolve_str(text, cat) or "").split(",") if x)

# exact match wins even when other labels contain the token
r = ids("system")
assert r == ["696"], f"tagSearchResolve('system') = {r}, expected ['696'] (exact beats substring)"
print(f"PASS: exact match 'system' → {r} (beats the 4 substring candidates)")

r = ids("Honghuang")
assert r == ["801"], f"tagSearchResolve('Honghuang') = {r}, expected ['801']"
print(f"PASS: exact (case-insensitive) 'Honghuang' → {r}")

# v1.2.0: partial keyword includes EVERY matching tag
r = ids("sys")
assert r == ["298", "390", "696", "890"], f"'sys' = {r}, expected all 4 (no ambiguity error)"
print(f"PASS: v1.2.0 all-match 'sys' → {r} (search shows everything)")

r = ids("honkai")
assert r == ["818", "889"], f"'honkai' = {r}, expected both Honkai tags"
print(f"PASS: multi-match 'honkai' → {r} (both included, no error)")

# wildcard includes every substring match at once
r = ids("sys*")
assert r == ["298", "390", "696", "890"], f"'sys*' = {r}"
print(f"PASS: wildcard 'sys*' → {r}")

r = ids("Naruto,Honkai*")
assert r == ["769", "818", "889"], f"'Naruto,Honkai*' = {r}, expected [769,818,889]"
print(f"PASS: 'Naruto,Honkai*' → {r} (mixed exact + wildcard)")

# zero-match keyword still raises (typo protection)
err = str(resolve_err("zzzqqq") or "")
assert err and "no tag name contains" in err.lower(), f"'zzzqqq' should raise a zero-match error, got: {err[:120]}"
print("PASS: zero-match 'zzzqqq' raises a descriptive error")

# phrase matching
r = ids("weak to strong")
assert r == ["750"], f"'weak to strong' = {r}, expected [750]"
print(f"PASS: phrase matching 'weak to strong' → {r}")

# word fallback for a phrase that matches no single tag
r = ids("genius lazy")
assert "306" in r and "387" in r, f"'genius lazy' word-fallback = {r}"
print(f"PASS: word fallback 'genius lazy' → contains 306/387")

# category scoping: exact match 'cultivation' lives in cat 2
r = ids("cultivation", "2")
assert r == ["169"], f"'cultivation' scoped cat 2 = {r}, expected [169]"
err = str(resolve_err("cultivation", "1") or "")
assert err and ("no tag name contains" in err.lower() or "not in the selected tag category" in err.lower()), f"'cultivation' cat 1 should error, got: {err[:80]}"
print("PASS: category scoping (cat2 → 169; cat1 → clear error)")

# numeric ids
r = ids("801")
assert r == ["801"], f"'801' = {r}"
print(f"PASS: numeric id '801' → {r}")

# ── Test 3: getCatalogFiltered param building (stubbed network) ────────
# HTML route returns a shell WITHOUT pageProps → the plugin must fall
# back to the _next/data JSON route (buildId machinery).
lua.execute("""
http_get = function(url, cfg)
    _CAPTURED[#_CAPTURED + 1] = { method = "GET", url = url }
    if string.find(url, "_next/data/", 1, true) then
        return { success = true, code = 200, body = '{"pageProps":{"series":[],"count":"0"}}', headers = {} }
    end
    if string.find(url, "novel-finder", 1, true) and not string.find(url, "_next/data/", 1, true) then
        return { success = true, code = 200, body = '<script id="__NEXT_DATA__">{"buildId":"TESTBUILD","props":{}}</script>', headers = {} }
    end
    return { success = false, code = 404, body = "", headers = {} }
end
""")

# 3a: title search → text= param
clear_captured()
flt = lua.table_from({
    "title_search": "martial peak",
    "orderBy": "update",
})
g.getCatalogFiltered(0, flt)
urls = captured_urls()
data_urls = [u for u in urls if "_next/data/" in u]
assert data_urls, f"no _next/data request captured: {urls}"
u = data_urls[0]
assert "text=martial+peak" in u, f"text= missing from URL: {u}"
print(f"PASS: title_search → text= param ({u.split('?')[-1][:80]}...)")

# 3b: tag search → ti=/te= params
clear_captured()
flt = lua.table_from({
    "tag_search_inc": "Honghuang, Naruto",
    "tag_search_exc": "Loli",
})
g.getCatalogFiltered(0, flt)
urls = captured_urls()
data_urls = [u for u in urls if "_next/data/" in u]
u = data_urls[0]
assert "ti=801,769" in u, f"ti= wrong: {u}"
assert "te=395" in u, f"te= wrong (Loli=395): {u}"
assert "tc=and" in u, "tc= operator missing"
print(f"PASS: tag search include/exclude → ti=801,769 te=395")

# 3b2: tag_pick dropdown merges with keyword ids (dedup; junk skipped)
clear_captured()
flt = lua.table_from({
    "tag_search_inc": "naruto",
    "tag_pick_10": "801",
    "tag_pick_2": "769",    # duplicate of the keyword id — must dedup
    "tag_pick_1": "999999", # unknown id from a stale sheet — must be skipped
})
g.getCatalogFiltered(0, flt)
urls = captured_urls()
data_urls = [u for u in urls if "_next/data/" in u]
u = data_urls[0]
assert "ti=769,801" in u, f"ti= must merge keyword 769 + picked 801 (dedup), got: {u}"
assert "999999" not in u, f"junk id leaked into ti=: {u}"
print("PASS: tag_pick merge → ti=769,801 (dedup + junk skipped)")

# 3c: zero-match keyword raises a clear error
lua.execute("""
function _try_bad_tag()
    local flt = { tag_search_inc = "zzzqqqxxx" }
    local ok, err = pcall(getCatalogFiltered, 0, flt)
    if ok then return "NO_ERROR" end
    return tostring(err)
end
""")
err = str(g._try_bad_tag())
assert "no tag name contains" in err.lower(), f"expected clear error, got: {err}"
print(f"PASS: zero-match keyword raises clear error ({err[:70]}...)")

# 3c2: ambiguous keyword through the filter field surfaces the resolver error
lua.execute("""
function _try_amb_tag()
    local flt = { tag_search_inc = "sys" }
    local ok, err = pcall(getCatalogFiltered, 0, flt)
    if ok then return "NO_ERROR" end
    return tostring(err)
end
""")
err = str(g._try_amb_tag())
# v1.2.0: 'sys' is no longer an error — it resolves to all 4 matching tags
# and the catalog call succeeds (items may be empty offline, that's fine).
assert err == "NO_ERROR", f"'sys' should resolve all matches without error, got: {err[:120]}"
print("PASS: partial keyword 'sys' in filters resolves all matches (no error)")

# 3d: buildId persistence — after a successful data fetch the plugin
# should have called set_preference to persist the build id
lua.execute("""
function _get_prefs()
    return _SAVED_PREFS
end
_prefs_tbl = {}
_SAVED_PREFS = _prefs_tbl
set_preference = function(k, v) _SAVED_PREFS[k] = v end
""")
clear_captured()
flt = lua.table_from({"orderBy": "update"})
g.getCatalogFiltered(0, flt)
saved = g._SAVED_PREFS
saved_id = saved["wtrlab_buildid"] if "wtrlab_buildid" in [str(k) for k in saved.keys()] else None
assert saved_id is not None, f"buildId not persisted via set_preference: {dict(saved)}"
print(f"PASS: buildId persisted via set_preference on the fallback path ({saved_id})")

# 3e: v1.1.9 HTML-first — when the HTML route carries pageProps in the
# REAL nested __NEXT_DATA__ shape ({"props":{"pageProps":{...}}}), the
# catalog comes from the HTML route in ONE request and _next/data is
# never touched.
lua.execute("""
http_get = function(url, cfg)
    _CAPTURED[#_CAPTURED + 1] = { method = "GET", url = url }
    if string.find(url, "novel-finder", 1, true) and not string.find(url, "_next/data/", 1, true) then
        return { success = true, code = 200, body = '<script id="__NEXT_DATA__" type="application/json">'
            .. '{"buildId":"HTMLBUILD","props":{"pageProps":{"count":"12","series":['
            .. '{"raw_id":101,"slug":"ga","data":{"title":"HTML Alpha"},"rating":4.2},'
            .. '{"raw_id":102,"slug":"gb","data":{"title":"HTML Beta"}}'
            .. ']}}}</script>', headers = {} }
    end
    if string.find(url, "_next/data/", 1, true) then
        return { success = true, code = 200, body = '{"pageProps":{"series":[{"raw_id":999,"slug":"wrong","data":{"title":"WRONG-ROUTE"}}],"count":"12"}}', headers = {} }
    end
    return { success = false, code = 404, body = "", headers = {} }
end
""")
clear_captured()
lua.execute("""
function _filtered_html_first()
    local res = getCatalogFiltered(0, {})
    local titles = {}
    for i = 1, #res.items do titles[#titles + 1] = res.items[i].title end
    return table.concat(titles, "|")
end
""")
titles = str(g._filtered_html_first())
urls = captured_urls()
data_urls = [u for u in urls if "_next/data/" in u]
assert not data_urls, f"HTML-first failed, fell back to _next/data: {urls}"
assert len(urls) == 1, f"expected exactly ONE request (the HTML route), got: {urls}"
assert titles == "HTML Alpha|HTML Beta", f"expected the 2 items from HTML props, got: {titles}"
print(f"PASS: HTML-first single round-trip (nested props.pageProps form, items: {titles})")

print("\n=== All wtrlab v1.1.9 plugin integration tests passed ===")
