#!/usr/bin/env python3
"""WuxiaBox v2.1.0 -> v2.2.0 splice.

Changes:
 1. Covers via wsrv.nl image proxy (posters fix — site covers are CF-challenged
    for the app's image loader, and .jpg URLs are exempt from the CF bypass).
    New setting: wuxiabox_covers = proxy (default) | direct.
 2. Tag system: 6,723-entry index -> 755 curated tags; popular_tags checkbox +
    tag_search text -> ONE searchable tag_input filter (native search UI).
 3. getUserAgentPreset() = "Chrome Mobile" (uniform modern UA incl. image host).
 4. listTotal() newline bug fix (total-based hasNext fallback was dead).
 5. Search pagination hardening + per-query next-page link extraction.
 6. show_error() adoption on hard failures (both sites unreachable, tag
    resolution dead-ends).
 7. Version/metadata bump + header changelog.

Idempotent: re-running on an already-spliced file is a no-op.
"""
import re, sys, json

PLUGIN = "/home/z/my-project/download/wuxiabox.lua"
CURATED = "/home/z/my-project/research/wuxiabox/curated_tags.json"

src = open(PLUGIN, encoding="utf-8").read()
changed = []

def sub1(pattern, repl, s, flags=0, count=1, tag=""):
    nonlocal_count = [0]
    def do_replace(m):
        nonlocal_count[0] += 1
        return m.expand(repl) if isinstance(repl, str) else repl(m)
    out = re.sub(pattern, repl, s, flags=flags, count=count)
    return out

def replace_once(s, old, new, tag):
    global src
    if new in s and old not in s:
        print(f"  [skip] {tag} (already applied)")
        return s
    if old not in s:
        print(f"  [MISS] {tag} — anchor not found!")
        sys.exit(1)
    assert s.count(old) == 1, f"{tag}: anchor not unique ({s.count(old)})"
    print(f"  [ok] {tag}")
    return s.replace(old, new, 1)

# ── 0. already applied? ────────────────────────────────────────────────────
if 'Version 2.2.0' in src:
    print("Already spliced (v2.2.0 marker present). No-op.")
    sys.exit(0)

# ── 1. metadata + header changelog ─────────────────────────────────────────
src = replace_once(
    src,
    '-- File: en/wuxiabox.lua — Version 2.1.0 (2026-09-16)',
    '-- File: en/wuxiabox.lua — Version 2.2.0 (2026-09-18)',
    "metadata version")

src = replace_once(
    src,
    'version  = "2.1.0"',
    'version  = "2.2.0",',
    "version field")

HEADER_NEW = '''--
-- 2.2.0 (2026-09-18) — POSTER FIX, SEARCH PAGINATION, TAG CURATION.
--
--   • POSTERS FIXED — the site's cover images are served behind the
--     same Cloudflare shield as the pages, but image URLs (.jpg) are
--     EXEMPT from NoveLA's Cloudflare bypass (STATIC_EXTENSIONS), so a
--     challenged cover request returned the challenge page to the
--     image loader and the poster silently failed. All cover URLs are
--     now routed through the wsrv.nl image proxy (the same
--     images.weserv.nl service other NoveLA sources use for exactly
--     this problem — the engine whitelists it). Direct-from-site
--     covers remain available via the new "Cover images" setting.
--   • SEARCH now paginates continuously: the total count fallback
--     (was dead — the Lua pattern could not cross the newline between
--     <ul class="pagination"> and the 总数 marker) and the next-page
--     link detection both work again, and each result page re-extracts
--     the searchid from its own pager so pagination survives engine
--     restarts mid-scroll.
--   • TAGS CURATED — the 6,723-entry tag index (148 KB of the file!)
--     is replaced by 755 genuinely-used tags (the wtr-lab taxonomy
--     cross-reference plus every Popular Tag and the whole Honghuang
--     family). Browsing them is now a native SEARCHABLE picker: the
--     "Tags" filter is a tag_input — type a few letters and matching
--     tags appear as suggestions; picked tags become chips. This
--     replaces both the old free-text "Tag Search" box and the
--     "Popular Tags" chip group.
--   • CLOUDFLARE: getUserAgentPreset() registers a modern Chrome
--     Mobile UA for every request of this source AND its image host,
--     so the cf_clearance cookie the WebView bakes stays valid for
--     cover loads too (it is bound to the User-Agent).
--   • show_error() (new NoveLA API) surfaces actionable dialogs when
--     both sites are unreachable or a tag pick cannot be resolved.
--
-- 2.1.0 (2026-09-16) — SEARCH FIX, POPULAR TAGS, MIRROR SITE.
'''
src = replace_once(
    src,
    '''--
-- 2.1.0 (2026-09-16) — SEARCH FIX, POPULAR TAGS, MIRROR SITE.''',
    HEADER_NEW,
    "header changelog")

# ── 2. getUserAgentPreset ──────────────────────────────────────────────────
src = replace_once(
    src,
    '''-- ── Small helpers ───────────────────────────────────────────────────────────
''',
    '''-- ── User-Agent preset ────────────────────────────────────────────────────────
-- Registered with the engine (LuaSourceAdapter.registerUAPreset): applies to
-- EVERY request of this source (tagged source:wuxiabox) and every untagged
-- request to the wuxiabox.com host — including the image loader's cover
-- fetches. One uniform, modern browser UA keeps the cf_clearance cookie the
-- Cloudflare WebView bypass bakes valid for pages AND images (clearance is
-- bound to User-Agent + IP; a mismatched image request gets challenged, and
-- .jpg URLs are exempt from the bypass ladder → broken posters).
function getUserAgentPreset()
    return "Chrome Mobile"
end

-- ── Small helpers ───────────────────────────────────────────────────────────
''',
    "getUserAgentPreset")

# ── 3. cover proxy helper + setting ────────────────────────────────────────
src = replace_once(
    src,
    '''local PREF_SITE  = "wuxiabox_site_preference"
''',
    '''local PREF_SITE  = "wuxiabox_site_preference"
local PREF_COVERS = "wuxiabox_covers"
''',
    "PREF_COVERS const")

src = replace_once(
    src,
    '''local function siteBases()''',
    '''-- ── Cover image proxy ────────────────────────────────────────────────────────
-- The site's covers (https://wuxiabox.com/d/file/…) sit behind the same
-- Cloudflare shield as the pages. NoveLA's image loader shares the engine's
-- OkHttp stack but .jpg URLs are EXEMPT from the Cloudflare bypass
-- (STATIC_EXTENSIONS in CloudfareVerificationInterceptor), so any challenge
-- on a cover request is handed to the image decoder as-is → broken poster.
-- wsrv.nl (images.weserv.nl) fetches server-side and is whitelisted by the
-- engine for exactly this pattern; w=450 keeps the payload small.
local COVER_PROXY = "https://wsrv.nl/?url="

local function coversViaProxy()
    local pref = get_preference(PREF_COVERS)
    return pref ~= "direct"
end

-- Wrap a site cover URL for the image loader. Non-site URLs pass through
-- untouched (already-absolute third-party covers, empty strings).
local function coverUrl(u)
    if not u or u == "" then return u end
    local site = absUrl(u)  -- canonicalize (mirror paths -> wuxiabox.com)
    if site == "" then return u end
    if not coversViaProxy() then return site end
    if not string_starts_with(site, SITE) then return site end
    return COVER_PROXY .. url_encode(site) .. "&w=450&we&output=jpg&q=80"
end

local function siteBases()''',
    "cover proxy helper")

# ── 4. apply coverUrl at the two cover emission points ────────────────────
src = replace_once(
    src,
    '''                local cover = html_attr(card.html, "img[data-src]", "data-src")
                if cover == "" then cover = html_attr(card.html, "img[src]", "src") end
                items[#items + 1] = { title = title, url = url, cover = absUrl(cover) }''',
    '''                local cover = html_attr(card.html, "img[data-src]", "data-src")
                if cover == "" then cover = html_attr(card.html, "img[src]", "src") end
                items[#items + 1] = { title = title, url = url, cover = coverUrl(cover) }''',
    "parseNovelCards cover")

src = replace_once(
    src,
    '''    if cover ~= "" then return absUrl(cover) end
    return nil
end''',
    '''    if cover ~= "" then return coverUrl(cover) end
    return nil
end''',
    "getBookCoverImageUrl cover")

# ── 5. listTotal newline fix ───────────────────────────────────────────────
src = replace_once(
    src,
    '''local function listTotal(body)
    return tonumber(string.match(body, '<ul class="pagination">.-<b>(%d+)</b>'))
end''',
    '''local function listTotal(body)
    -- v2.1.0 bug: the pattern anchored on <ul class="pagination">, but the
    -- site puts a NEWLINE between it and the 总数 marker, and Lua's `.-`
    -- cannot cross newlines — the total was NEVER extracted, so the
    -- total-based hasNext fallback was dead code. Anchor on the 总数 title
    -- marker itself (the whole marker sits on one line).
    return tonumber(string.match(body, '总数[^<]-<b>(%d+)</b>'))
        or tonumber(string.match(body, '<ul class="pagination">%s*<a[^>]*>[^<]-<b>(%d+)</b>'))
end''',
    "listTotal fix")

# ── 6. search pagination hardening ─────────────────────────────────────────
src = replace_once(
    src,
    '''function getCatalogSearch(index, query)
    if index == 0 then
        local body = runSearch(query)
        if not body then return { items = {}, hasNext = false } end
        _searchIdByQuery[query] = extractSearchId(body)
        local items = parseNovelCards(body, false)
        local hasNext = hasNextByLink(body, "page=1&searchid=")
        local total = listTotal(body)
        if total and 1 * 20 < total then hasNext = true end
        return { items = items, hasNext = hasNext }
    end

    local sid = _searchIdByQuery[query]
    if not sid then
        -- engine asked for a later page without page 0 in this run
        local body = runSearch(query)
        if not body then return { items = {}, hasNext = false } end
        sid = extractSearchId(body)
        _searchIdByQuery[query] = sid
    end
    if not sid then return { items = {}, hasNext = false } end

    local path = "/e/search/result/index.php?page=" .. tostring(index) ..
        "&searchid=" .. sid
    local r = httpGetAny(path)
    if not r or not r.success then return { items = {}, hasNext = false } end
    local items = parseNovelCards(r.body, false)
    local hasNext = hasNextByLink(r.body, "page=" .. tostring(index + 1) .. "&searchid=")
    local total = listTotal(r.body)
    if total and (index + 1) * 20 < total then hasNext = true end
    return { items = items, hasNext = hasNext }
end''',
    '''-- EmpireCMS search pager is 0-BASED: first page has no page= param, the
-- link labelled "2" points at page=1, ">>" (last) at page=last. The app
-- index is also 0-based, so app index N maps to URL page=N directly.
-- Each fetched page re-extracts the searchid from its OWN pager links
-- (self-healing: pagination survives a fresh engine run mid-scroll).
local function searchHasNext(body, nextIndex, sid)
    -- link-based: next page link in either param order
    if hasNextByLink(body, "page=" .. tostring(nextIndex) .. "&searchid=") then
        return true
    end
    if sid and hasNextByLink(body, "searchid=" .. sid .. "&page=" .. tostring(nextIndex)) then
        return true
    end
    -- total-based fallback: 总数 marker x 20 per page
    local total = listTotal(body)
    if total and nextIndex * 20 < total then return true end
    return false
end

function getCatalogSearch(index, query)
    if index == 0 then
        local body = runSearch(query)
        if not body then
            show_error("WuxiaBox search failed",
                "Neither wuxiabox.com nor the wuxiaspot.com mirror could be " ..
                "reached for the search. If a Cloudflare check appeared, solve " ..
                "it and try again.")
            return { items = {}, hasNext = false }
        end
        local sid = extractSearchId(body)
        _searchIdByQuery[query] = sid
        local items = parseNovelCards(body, false)
        local hasNext = searchHasNext(body, 1, sid)
        return { items = items, hasNext = hasNext }
    end

    local sid = _searchIdByQuery[query]
    if not sid then
        -- engine asked for a later page without page 0 in this run
        local body = runSearch(query)
        if not body then return { items = {}, hasNext = false } end
        sid = extractSearchId(body)
        _searchIdByQuery[query] = sid
    end
    if not sid then return { items = {}, hasNext = false } end

    local path = "/e/search/result/index.php?page=" .. tostring(index) ..
        "&searchid=" .. sid
    local r = httpGetAny(path)
    if not r or not r.success then return { items = {}, hasNext = false } end
    -- refresh the cached searchid from THIS page's own pager (self-healing)
    local freshSid = extractSearchId(r.body)
    if freshSid and freshSid ~= sid then
        _searchIdByQuery[query] = freshSid
        sid = freshSid
    end
    local items = parseNovelCards(r.body, false)
    local hasNext = searchHasNext(r.body, index + 1, sid)
    return { items = items, hasNext = hasNext }
end''',
    "search pagination")

# ── 7. tag index: 6,723 -> 755 curated ─────────────────────────────────────
curated = json.load(open(CURATED))
assert len(curated) == 755, f"curated size {len(curated)} != 755"
lines = [f"{t['id']}|{t['label']}|{t['letter']}" for t in curated]
NEW_INDEX = "-- BEGIN_TAG_INDEX (auto-generated — do not edit)\n" + "\n".join(lines) + "\n-- END_TAG_INDEX"

m = re.search(r"-- BEGIN_TAG_INDEX \(auto-generated — do not edit\)\n.*?\n-- END_TAG_INDEX", src, re.S)
assert m, "tag index block not found"
old_block = m.group(0)
print(f"  [ok] tag index: {old_block.count(chr(10))} -> {len(lines)} lines")
src = src.replace(old_block, NEW_INDEX, 1)

# ── 8. tag_search comment + resolver: keep, but note curation ──────────────
src = replace_once(
    src,
    '''-- Resolve a free-text Tag Search field into a deduplicated list of tag ids.
-- Semantics (mirrors the site's own tag browsing + the wtrlab tag search):''',
    '''-- Resolve tag picks / free text into a deduplicated list of tag ids.
-- Since 2.2.0 the index is the CURATED 755-tag set (wtr-lab taxonomy
-- cross-reference + Popular Tags + the Honghuang family) — everything a
-- novel on this site is actually tagged with; the 6,723-entry dump is gone.
-- Semantics (mirrors the site's own tag browsing + the wtrlab tag search):''',
    "resolver comment")

# ── 9. filters: popular_tags + tag_search -> tag_input ─────────────────────
src = replace_once(
    src,
    '''        {
            type         = "checkbox",
            key          = "popular_tags",
            label        = "Popular Tags",
            options      = POPULAR_TAGS,
        },
        {
            type         = "text",
            key          = "tag_search",
            label        = "Tag Search (keyword — shows every matching tag)",
            defaultValue = "",
        },''',
    '''        {
            type        = "tag_input",
            key         = "tags",
            label       = "Tags (type to search — 755 curated tags)",
            allowCustom = false,
            options     = TAG_FILTER_OPTIONS,
        },''',
    "filters tag_input")

# TAG_FILTER_OPTIONS table: value = id (or "honghuang" family keyword), label
pop_names = {  # id -> label for the popular subset (nicer labels with hints)
}
opt_lines = []
for t in curated:
    opt_lines.append(f'    {{ value = "{t["id"]}", label = "{t["label"]}" }},')
# the Honghuang family keyword option (resolves to the whole family)
opt_lines.append('    { value = "honghuang", label = "Honghuang (all Honghuang* tags)" },')
OPTS = ("local TAG_FILTER_OPTIONS = {\n" + "\n".join(opt_lines) + "\n}")

src = replace_once(
    src,
    '''local POPULAR_TAGS = {''',
    OPTS + '''
-- (POPULAR_TAGS removed in 2.2.0 — superseded by the searchable tag_input
-- above; every popular tag is part of TAG_FILTER_OPTIONS.)
local POPULAR_TAGS_LEGACY = {''',
    "TAG_FILTER_OPTIONS + legacy rename")

# ── 10. getCatalogFiltered: read tags_included ─────────────────────────────
src = replace_once(
    src,
    '''    local browse    = filters["browse"]    or "catalog"
    local category  = filters["category"]  or "all"
    local status    = filters["status"]    or "all"
    local sort      = filters["sort"]      or "newstime"
    local tagQuery  = filters["tag_search"] or ""
    local picks     = filters["popular_tags_included"] or {}''',
    '''    local browse    = filters["browse"]    or "catalog"
    local category  = filters["category"]  or "all"
    local status    = filters["status"]    or "all"
    local sort      = filters["sort"]      or "newstime"
    local picks     = filters["tags_included"] or {}''',
    "getCatalogFiltered reads tags_included")

src = replace_once(
    src,
    '''    -- ── Tags (2.1.0): Popular Tags chips + free-text Tag Search merge
    -- into ONE resolution, then a union browse. Takes priority (the site
    -- cannot combine a tag listing with category/status/sort — see the
    -- plugin header). Values are numeric tag ids (or the "honghuang"
    -- family keyword); the free text keeps the full keyword semantics.
    local tagSource = nil
    if tagQuery ~= "" and #picks > 0 then
        tagSource = tagQuery .. "," .. table.concat(picks, ",")
    elseif tagQuery ~= "" then
        tagSource = tagQuery
    elseif #picks > 0 then
        tagSource = table.concat(picks, ",")
    end
    if tagSource then
        local ok, tagIds = pcall(tagSearchResolve, tagSource, nil)
        if not ok then error(tostring(tagIds)) end
        if #tagIds == 0 then return { items = {}, hasNext = false } end
        local items, hasNext = browseTagUnion(tagIds, index)
        return { items = items, hasNext = hasNext }
    end''',
    '''    -- ── Tags (2.2.0): the searchable tag_input picker marshals its chips
    -- as filters["tags_included"] = { value, … } — numeric tag ids plus the
    -- "honghuang" family keyword. One union browse. Takes priority (the
    -- site cannot combine a tag listing with category/status/sort).
    if #picks > 0 then
        local ok, tagIds = pcall(tagSearchResolve, table.concat(picks, ","), nil)
        if not ok then
            show_error("WuxiaBox tag error", tostring(tagIds))
            return { items = {}, hasNext = false }
        end
        if #tagIds == 0 then
            show_error("WuxiaBox tags",
                "None of the picked tags could be resolved. This should not " ..
                "happen — please report the tags you picked.")
            return { items = {}, hasNext = false }
        end
        local items, hasNext = browseTagUnion(tagIds, index)
        return { items = items, hasNext = hasNext }
    end''',
    "getCatalogFiltered tag path")

# ── 11. settings schema: covers option ─────────────────────────────────────
src = replace_once(
    src,
    '''        {
            key     = PREF_RETRY,''',
    '''        {
            key     = PREF_COVERS,
            type    = "select",
            label   = "Cover images",
            current = (function()
                local pref = get_preference(PREF_COVERS)
                if pref == "direct" then return "direct" end
                return "proxy"
            end)(),
            options = {
                { value = "proxy",  label = "Via wsrv.nl image proxy (recommended — fixes posters)" },
                { value = "direct", label = "Direct from wuxiabox.com (breaks when Cloudflare challenges images)" },
            }
        },
        {
            key     = PREF_RETRY,''',
    "settings covers")

open(PLUGIN, "w", encoding="utf-8").write(src)
print(f"\nwritten: {PLUGIN} ({len(src)} bytes, {src.count(chr(10))} lines)")
