#!/usr/bin/env python3
"""
wtrlab.lua v1.1.9 -> v1.2.0 splice. Applies:

 1. Paragraph bulletproofing (user report: "mashing everything into one
    mashup paragraph or two"):
      - every body array element is split on embedded newlines (\n, \r\n, \r)
        so each source line becomes its own \n\n-joined paragraph (matches the
        site's own reader: plain-string bodies are split on \n);
      - plain-string bodies get \r normalization before the \n split;
      - all gsub glossary/patch replacements are pattern-escaped and
        pcall-armored (a term containing % ( ) . etc. previously aborted the
        whole chapter with a Lua error).
 2. Web+ mode (parity with upstream 1.1.8's setting, but glossary is applied
    per-paragraph with escaped patterns instead of gsub over the raw JSON).
 3. Multiple tags from the same category: the 11 tag_pick selects become
    multi-select checkbox chip groups (filters[key.."_included"] arrays);
    legacy single-value state still honored.
 4. Tag Search: substring keywords now include EVERY matching tag (no more
    ambiguity error — "shows everything as search result"); exact name, id,
    and 'x*' wildcard semantics kept; only a zero-match keyword errors.
 5. Tag discovery in the catalog search bar: matching tags are listed first
    as tappable results ("🏷 <Tag> — <Category>"); opening one browses the
    tag's novels as a "book" (chapters = top 100 novels by readers, each
    opens the novel's first chapter as a preview).

Idempotent: detects the v1.2.0 markers and skips applied sections.
"""
import re, sys

PLUG = "/home/z/my-project/download/wtrlab.lua"
src = open(PLUG, encoding="utf-8").read()
orig_len = len(src)
n_edits = 0

def sub_once(pattern, repl, text, flags=0, count=1, label=""):
    global n_edits
    new, n = re.subn(pattern, repl, text, count=count, flags=flags)
    if n == 0:
        print(f"  !! MISS: {label or pattern[:60]}")
        sys.exit(1)
    n_edits += n
    return new

def replace_once(old, new, text, label=""):
    global n_edits
    if old not in text:
        print(f"  !! MISS: {label or old[:60]}")
        sys.exit(1)
    n_edits += 1
    return text.replace(old, new, 1)

if "v1.2.0 paragraph-safety helpers" in src:
    print("already spliced — nothing to do")
    sys.exit(0)

# ── 1. version + header ────────────────────────────────────────────────────
src = replace_once('version = "1.1.9"', 'version = "1.2.0"', src, "version")

hdr_old = """--   • cleanParagraph: line-anchored, word-bounded watermark/credit patterns"""
hdr_new = """--   • cleanParagraph: line-anchored, word-bounded watermark/credit patterns
--
-- 1.2.0 (2026-09-10) — user-driven update:
--   • Paragraph safety: body elements that embed newlines are split so every
--     source line becomes its own paragraph (the reader merges text that only
--     carries single \\n breaks); \\r/\\r\\n normalized; all glossary/patch gsub
--     replacements are pattern-escaped + pcall-armored (terms with % or ()
--     used to kill the whole chapter with a Lua error).
--   • Multiple tags per category: the 11 tag category dropdowns are now
--     multi-select chip groups — tap several tags in one category.
--   • Tag Search now behaves like a real search: a partial keyword includes
--     EVERY tag whose name contains it (no more "ambiguous" error). Exact
--     names, raw ids and 'x*' wildcards still work.
--   • Tag discovery: the catalog search bar lists matching tags as tappable
--     results — open one to browse that tag's novels (most-read first, up to
--     100) and preview any novel's first chapter.
--   • Web+ mode (matches upstream 1.1.8): raw Chinese + book glossary terms
--     applied per paragraph (escaped), for use with the app translator.
--   • cleanParagraph: line-anchored, word-bounded watermark/credit patterns"""
src = replace_once(hdr_old, hdr_new, src, "header changelog")

# ── 2. paragraph-safety helpers + applyGlossaryAndPatches + buildParagraphs ─
helpers = r"""
-- ── v1.2.0 paragraph-safety helpers ─────────────────────────────────────────
-- The reader's paragraph boundary is a blank line (\n\s*\n). A single \n
-- INSIDE a chunk renders as a soft line break, so a chapter whose elements
-- embed single newlines displays as visually merged blocks. normalizeNewlines
-- + splitLines guarantee every source line becomes its own \n\n-joined
-- paragraph — the same rule the site's own reader uses for string bodies.
local function normalizeNewlines(s)
    s = string.gsub(s, "\r\n", "\n")
    s = string.gsub(s, "\r", "\n")
    return s
end

local function splitLines(s)
    local lines = {}
    for line in string.gmatch(normalizeNewlines(s) .. "\n", "(.-)\n") do
        lines[#lines + 1] = line
    end
    return lines
end

-- Lua pattern / replacement escaping. Glossary terms and patches are raw
-- site data: a term containing % ( ) . + - etc. would otherwise throw
-- "malformed pattern" / "invalid use of '%' in replacement" and abort the
-- whole chapter. safeGsub never raises — a bad term is skipped.
local function escLuaPattern(s)
    return (string.gsub(s, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function escLuaReplacement(s)
    return (string.gsub(s, "%%", "%%%%"))
end

local function safeGsub(text, pattern, replacement)
    if pattern == "" or replacement == nil then return text end
    local ok, res = pcall(string.gsub, text, escLuaPattern(pattern),
        escLuaReplacement(tostring(replacement)))
    if ok and type(res) == "string" then return res end
    return text
end
"""

anchor = "local function applyGlossaryAndPatches(text, glossary, patches)"
src = replace_once(anchor, helpers + "\n" + anchor, src, "helpers insert")

# applyGlossaryAndPatches rewrite
agap_old = """local function applyGlossaryAndPatches(text, glossary, patches)
    if glossary then
        for idx, term in pairs(glossary) do
            local marker1 = "※" .. tostring(idx) .. "⛬"
            local marker2 = "※" .. tostring(idx) .. "〓"
            text = text:gsub(marker1, term)
            text = text:gsub(marker2, term)
        end
    end
    if patches then
        for _, patch in ipairs(patches) do
            if patch.zh and patch.en then
                text = text:gsub(patch.zh, patch.en)
            end
        end
    end
    return text
end"""
agap_new = """local function applyGlossaryAndPatches(text, glossary, patches, webplusTerms)
    if glossary then
        for idx, term in pairs(glossary) do
            local marker1 = "※" .. tostring(idx) .. "⛬"
            local marker2 = "※" .. tostring(idx) .. "〓"
            text = safeGsub(text, marker1, term)
            text = safeGsub(text, marker2, term)
        end
    end
    if patches then
        for _, patch in ipairs(patches) do
            if patch.zh and patch.en then
                text = safeGsub(text, patch.zh, patch.en)
            end
        end
    end
    -- Web+ mode: book-level glossary applied directly to the (Chinese) text,
    -- per paragraph with escaped patterns — unlike upstream 1.1.8, which
    -- gsubs the whole encrypted-JSON string with raw patterns.
    if webplusTerms then
        for original, translation in pairs(webplusTerms) do
            if original ~= "" and translation ~= "" then
                text = safeGsub(text, original, translation)
            end
        end
    end
    return text
end"""
src = replace_once(agap_old, agap_new, src, "applyGlossaryAndPatches")

bp_old = """local function buildParagraphs(resolvedBody, glossary, patches)
    local paragraphs = {}
    local bodyArray = json_parse(resolvedBody)

    if type(bodyArray) == "table" and bodyArray[1] ~= nil then
        for _, item in ipairs(bodyArray) do
            if type(item) == "string" then
                local text = cleanParagraph(item)
                if text ~= "[image]" and text ~= "" then
                    text = applyGlossaryAndPatches(text, glossary, patches)
                    if text ~= "" then
                        table.insert(paragraphs, text)
                    end
                end
            end
        end
    else
        for _, line in ipairs(string_split(resolvedBody, "\\n")) do
            local text = string_trim(line)
            if text ~= "" then
                table.insert(paragraphs, text)
            end
        end
    end

    return paragraphs
end"""
bp_new = """local function buildParagraphs(resolvedBody, glossary, patches, webplusTerms)
    local paragraphs = {}
    local bodyArray = json_parse(resolvedBody)
    local sources = {}

    if type(bodyArray) == "table" and bodyArray[1] ~= nil then
        for _, item in ipairs(bodyArray) do
            if type(item) == "string" then
                sources[#sources + 1] = item
            end
        end
    else
        -- Plain-string body: the site's own reader splits these on \\n.
        sources[#sources + 1] = tostring(resolvedBody)
    end

    -- Each element may itself embed line breaks (the site packs multi-line
    -- content into single array elements). Split EVERY element on newlines
    -- so each source line becomes its own paragraph — never a single \n
    -- (the reader renders that as a merged soft break).
    for _, srcText in ipairs(sources) do
        for _, line in ipairs(splitLines(srcText)) do
            local text = cleanParagraph(line)
            if text ~= "[image]" and text ~= "" then
                text = applyGlossaryAndPatches(text, glossary, patches, webplusTerms)
                if text ~= "" then
                    table.insert(paragraphs, text)
                end
            end
        end
    end

    return paragraphs
end"""
src = replace_once(bp_old, bp_new, src, "buildParagraphs")

# ── 3. getChapterText: webplus mode + new buildParagraphs signature ────────
src = replace_once(
    'local translateParam = (mode == "raw") and "web" or "ai"',
    'local translateParam = (mode == "raw") and "web" or (mode == "webplus") and "webplus" or "ai"',
    src, "translateParam")

src = replace_once(
    "local paragraphs = buildParagraphs(resolvedBody, glossary, patches)",
    "local paragraphs = buildParagraphs(resolvedBody, glossary, patches,\n        (mode == \"webplus\") and termByOriginal or nil)",
    src, "buildParagraphs call")

src = replace_once(
    'local PREF_MODE = "wtrlab_mode"           -- "ai" | "raw"  (key kept from 1.x so existing settings survive)',
    'local PREF_MODE = "wtrlab_mode"           -- "ai" | "raw" | "webplus"  (key kept from 1.x so existing settings survive)',
    src, "PREF_MODE comment")

src = replace_once(
    """        options = {{
            value = "ai",
            label = "AI (Beta)"
        }, {
            value = "raw",
            label = "Raw (Web)"
        }}""",
    """        options = {{
            value = "ai",
            label = "AI (Beta)"
        }, {{
            value = "raw",
            label = "Raw (Web)"
        }}, {{
            value = "webplus",
            label = "Web+ (glossary raw - best with app translator)"
        }}}""",
    src, "mode options")

# ── 4. forgiving resolver ───────────────────────────────────────────────────
doc_old = """-- v1.1.9 semantics (site-autocomplete-like feedback). On problems the
-- resolver RAISES an error whose message shows the matching tag names:
--   • Tokens are split on comma / semicolon / newline / tab; spaces stay
--     INSIDE tokens so multi-word phrases work ("weak to strong").
--   • Per token, resolution order:
--       1. exact label match (case-insensitive) — "system" → the System
--          tag even though other labels contain it;
--       2. numeric token — a verbatim tag id (validated);
--       3. exactly ONE substring match — "vampir" → Vampires (#740);
--       4. several substring matches — AMBIGUOUS: raises an error that
--          LISTS the matching tags (type "sys" → the error shows
--          System (#696), System Misunderstanding (#890)) — the on-site
--          autocomplete equivalent; then type the full name, or
--       5. "keyword*" wildcard — includes ALL substring matches.
--   • A multi-word token with no phrase match falls back to per-word
--     matching; a token with no match at all raises a clear error.
--   • cat: "0"/nil = all categories, else a single category id ("1".."11")
--     — scopes the whole resolution (mirrors the site finder's grouping)."""
doc_new = """-- v1.2.0 semantics — a keyword INCLUDES every matching tag:
--   • Tokens are split on comma / semicolon / newline / tab; spaces stay
--     INSIDE tokens so multi-word phrases work ("weak to strong").
--   • Per token, resolution order:
--       1. exact label match (case-insensitive) — "system" → the System
--          tag even though other labels contain it;
--       2. numeric token — a verbatim tag id (validated);
--       3. "keyword*" wildcard — includes ALL substring matches;
--       4. ANY substring match — "sys" now includes System (#696) AND
--          System Misunderstanding (#890) AND everything else containing
--          it: the search "shows everything as a result" (v1.1.9 raised
--          an ambiguity error here and demanded the exact name).
--   • A multi-word token with no phrase match falls back to per-word
--     matching; a token with no match at all raises a clear error.
--   • cat: "0"/nil = all categories, else a single category id ("1".."11")
--     — scopes the whole resolution (mirrors the site finder's grouping)."""
src = replace_once(doc_old, doc_new, src, "resolver doc")

resolve_old = """        -- 3) / 4) substring matches
        local matches = substringMatches(token)
        if #matches == 1 then
            addTag(matches[1])
            return
        elseif #matches > 1 then
            error("'" .. token .. "' is ambiguous — it matches " .. #matches
                .. " tags: " .. formatMatches(matches, 10)
                .. ". Type the full tag name, add * to include all of them ('"
                .. token .. "*'), or pick it from the Tags dropdowns.")
        end"""
resolve_new = """        -- 3) / 4) substring matches: INCLUDE EVERY MATCH (v1.2.0) — a
        -- partial keyword behaves like the site's tag search: everything
        -- containing it becomes part of the filter.
        local matches = substringMatches(token)
        for _, t in ipairs(matches) do addTag(t) end
        if #matches > 0 then return end"""
src = replace_once(resolve_old, resolve_new, src, "resolver all-match")

err_old = """        error("no tag matches '" .. token .. "'. Try a shorter keyword (e.g. "
            .. "'reincarnation', 'harem', 'weak to strong'), add * for a wildcard, "
            .. "or pick from the Tags dropdowns.")"""
err_new = """        error("no tag name contains '" .. token .. "'. Try a shorter keyword "
            .. "(e.g. 'reincarnat', 'harem', 'system'), or browse the Tags chip "
            .. "groups in this filter sheet (every tag is visible there).")"""
src = replace_once(err_old, err_new, src, "zero-match error text")

# ── 5. tag_pick selects -> checkbox groups ──────────────────────────────────
def convert_pick(m):
    block = m.group(0)
    block = block.replace('type = "select"', 'type = "checkbox"', 1)
    block = re.sub(r'\n\s*defaultValue = "",', '', block, count=1)
    block = re.sub(r'\n\s*\{value = "", label = "Any"\},', '', block, count=1)
    return block

src, n = re.subn(
    r'\{\s*type = "select",\s*\n\s*key = "tag_pick_\d+",.*?\n\s*\},',
    convert_pick, src, flags=re.S)
if n != 11:
    print(f"  !! tag_pick conversion: expected 11 blocks, converted {n}")
    sys.exit(1)
n_edits += n

# comment above the pickers
src = replace_once("""        -- ── Tag pickers (v1.1.9): one dropdown per site category ──────
        -- The tags now SHOW UP: each picker lists its category's tags
        -- alphabetically (the app sorts options). Pick one tag to
        -- include it; combine with the Tag Search keyword fields and
        -- the category-scoped pickers as needed. (Exclude via the
        -- Tag Search - exclude keyword field.)""",
"""        -- ── Tag chip groups (v1.2.0): multi-select per site category ──
        -- Every tag of the category is shown as a chip (the app sorts
        -- alphabetically): tap several to include them ALL — multiple
        -- tags from the same category. Combine freely with the Tag
        -- Search keyword fields. (Exclude via the Tag Search - exclude
        -- keyword field.)""", src, "picker comment")

# ── 6. getCatalogFiltered: checkbox arrays + legacy strings ─────────────────
collect_old = """    -- Dropdown-picked tags (include side). A stale sheet from an older
    -- plugin version could carry junk values — validate each id against
    -- the index and skip anything unknown.
    local pickedSeen = {}
    for _, id in ipairs(tags_inc) do pickedSeen[id] = true end
    for i = 1, 11 do
        local picked = tostring(filters["tag_pick_" .. i] or "")
        if picked ~= "" then
            local valid = false
            for _, t in ipairs(ALL_TAGS) do
                if t.id == picked then
                    valid = true
                    break
                end
            end
            if valid and not pickedSeen[picked] then
                pickedSeen[picked] = true
                tags_inc[#tags_inc + 1] = picked
            end
        end
    end"""
collect_new = """    -- Chip-picked tags (include side, v1.2.0 multi-select): each of the
    -- 11 tag_pick_N checkbox groups contributes ALL its selected ids
    -- (marshalled by the app as filters["tag_pick_N_included"] arrays).
    -- A stale sheet from an older plugin version could still carry the
    -- v1.1.9 single-value form (plain string) — honored too. Every id is
    -- validated against the index; junk is skipped.
    local pickedSeen = {}
    for _, id in ipairs(tags_inc) do pickedSeen[id] = true end
    local function addPickedId(pid)
        if pid == "" or pickedSeen[pid] then return end
        for _, t in ipairs(ALL_TAGS) do
            if t.id == pid then
                pickedSeen[pid] = true
                tags_inc[#tags_inc + 1] = pid
                return
            end
        end
    end
    for i = 1, 11 do
        local picks = filters["tag_pick_" .. i .. "_included"]
        if type(picks) == "table" then
            for _, picked in ipairs(picks) do
                addPickedId(tostring(picked))
            end
        end
        addPickedId(tostring(filters["tag_pick_" .. i] or ""))
    end"""
src = replace_once(collect_old, collect_new, src, "tag collection")

# comment in getCatalogFiltered about resolver semantics
src = replace_once("""    -- ── Tags: keywords + category scope + dropdown picks (v1.1.9) ───────
    -- The tag_search_inc / tag_search_exc keyword fields resolve through
    -- tagSearchResolve, scoped to the tag_category picker. The resolver
    -- RAISES with a descriptive message on typos / unknown ids / ambiguous
    -- keywords (the message lists the matching tag names — the closest the
    -- app's static filter sheet can get to the site's autocomplete).
    -- The 11 tag_pick_N dropdowns contribute one picked tag id each; they
    -- merge with the keyword-resolved ids into one deduplicated ti= list.""",
"""    -- ── Tags: keywords + category scope + chip picks (v1.2.0) ──────────
    -- The tag_search_inc / tag_search_exc keyword fields resolve through
    -- tagSearchResolve, scoped to the tag_category picker. A partial
    -- keyword includes EVERY tag whose name contains it (v1.2.0 search
    -- semantics); only a keyword with zero matches raises an error.
    -- The 11 tag_pick_N chip groups contribute all their selected ids;
    -- everything merges into one deduplicated ti= list.""", src, "resolver comment")

# ── 7. tag-book support + catalog search tag results ───────────────────────
tagbook = r"""
-- ── v1.2.0 Tag books: novel-finder URLs opened as browsable books ───────────
-- The catalog search bar doubles as a tag finder: matching tags are listed
-- as tappable results whose URL is the site's own novel-finder with ti=
-- pre-applied. Opening one renders it as a "book": the chapter list is the
-- tag's novels (most-read first, capped at 100) and opening a chapter
-- previews that novel's first chapter.
local TAG_CATEGORY_NAMES = {
    ["1"] = "Protagonist", ["2"] = "Power Systems", ["3"] = "Worldbuilding",
    ["4"] = "Socio-Political", ["5"] = "Relationships", ["6"] = "Narrative",
    ["7"] = "Beings & Factions", ["8"] = "Professional", ["9"] = "Tone",
    ["10"] = "Adaptations", ["11"] = "Misc"
}

local function parseTagBookUrl(bookUrl)
    if not bookUrl or not string.find(bookUrl, "novel-finder", 1, true) then
        return nil
    end
    local ids = {}
    local seen = {}
    for chunk in string.gmatch(bookUrl, "[?&]ti=([^&#]*)") do
        for v in string.gmatch(chunk, "%d+") do
            if not seen[v] then
                seen[v] = true
                ids[#ids + 1] = v
            end
        end
    end
    if #ids == 0 then return nil end
    return ids
end

local function tagBookLabels(ids)
    local labels, seen = {}, {}
    for _, id in ipairs(ids) do
        for _, t in ipairs(ALL_TAGS) do
            if t.id == id and not seen[id] then
                seen[id] = true
                labels[#labels + 1] = t.label
                break
            end
        end
    end
    return labels
end

local function fetchTagBookPage(ids, page)
    local params = "ti=" .. table.concat(ids, ",") ..
        "&orderBy=reader&page=" .. tostring(page)
    return fetchCatalogPage("en/novel-finder", "/en/novel-finder.json", params)
end

local function tagBookChapterList(ids)
    local out, seen = {}, {}
    for page = 1, 10 do
        local pp = fetchTagBookPage(ids, page)
        if not pp or type(pp.series) ~= "table" or #pp.series == 0 then break end
        for _, novel in ipairs(pp.series) do
            local rawId = tostring(novel.raw_id or "")
            if rawId ~= "" and not seen[rawId] then
                seen[rawId] = true
                local title = (novel.data and novel.data.title) or ""
                out[#out + 1] = {
                    title = string_clean(title),
                    url = baseUrl .. "en/novel/" .. rawId .. "/" ..
                        (novel.slug or "") .. "/chapter-1"
                }
            end
        end
        local countNum = tonumber(pp.count)
        if countNum and #out >= countNum then break end
    end
    return out
end
"""

anchor2 = "-- ── Book details ──"
src = replace_once(anchor2, tagbook + "\n" + anchor2, src, "tagbook helpers insert")

# getBookTitle
src = replace_once("""function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)""",
"""function getBookTitle(bookUrl)
    local tagIds = parseTagBookUrl(bookUrl)
    if tagIds then
        local labels = tagBookLabels(tagIds)
        if #labels > 0 then
            return "🏷 " .. table.concat(labels, " + ") .. " (tag view)"
        end
        return "Tag view"
    end
    local body = fetchPage(bookUrl)""", src, "getBookTitle")

# getBookCoverImageUrl
src = replace_once("""function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)""",
"""function getBookCoverImageUrl(bookUrl)
    if parseTagBookUrl(bookUrl) then return nil end
    local body = fetchPage(bookUrl)""", src, "getBookCoverImageUrl")

# getBookDescription
src = replace_once("""function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)""",
"""function getBookDescription(bookUrl)
    local tagIds = parseTagBookUrl(bookUrl)
    if tagIds then
        local labels = tagBookLabels(tagIds)
        local name = (#labels > 0) and table.concat(labels, " + ") or "this tag"
        local countText = ""
        local pp = fetchTagBookPage(tagIds, 1)
        if pp and pp.count then
            local c = tonumber(pp.count)
            if c then countText = " (" .. tostring(c) .. " novels total)" end
        end
        return "All novels tagged " .. name .. countText .. ".\\n\\n" ..
            "This is a tag browse view: the 'chapters' below are this tag's " ..
            "novels ordered by readers (first 100 shown). Open any entry to " ..
            "preview that novel's first chapter — search its title in the " ..
            "catalog to add the full book. You can also combine tags with the " ..
            "Filter sheet (Tag Search field or the Tags chip groups)."
    end
    local body = fetchPage(bookUrl)""", src, "getBookDescription")

# getBookGenres / getBookRating / getBookStatus / getBookLastUpdate
src = replace_once("""function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)""",
"""function getBookGenres(bookUrl)
    if parseTagBookUrl(bookUrl) then return {} end
    local body = fetchPage(bookUrl)""", src, "getBookGenres")

src = replace_once("""function getBookRating(bookUrl)
    local body = fetchPage(bookUrl)""",
"""function getBookRating(bookUrl)
    if parseTagBookUrl(bookUrl) then return nil end
    local body = fetchPage(bookUrl)""", src, "getBookRating")

src = replace_once("""function getBookStatus(bookUrl)
    local body = fetchPage(bookUrl)""",
"""function getBookStatus(bookUrl)
    if parseTagBookUrl(bookUrl) then return nil end
    local body = fetchPage(bookUrl)""", src, "getBookStatus")

src = replace_once("""function getBookLastUpdate(bookUrl)
    local body = fetchPage(bookUrl)""",
"""function getBookLastUpdate(bookUrl)
    if parseTagBookUrl(bookUrl) then return nil end
    local body = fetchPage(bookUrl)""", src, "getBookLastUpdate")

# getChapterListHash
src = replace_once("""function getChapterListHash(bookUrl)
    local novelId = string.match(bookUrl, "/novel/(%d+)/")
    if not novelId then
        return nil
    end""",
"""function getChapterListHash(bookUrl)
    local tagIds = parseTagBookUrl(bookUrl)
    if tagIds then
        local count = "?"
        local pp = fetchTagBookPage(tagIds, 1)
        if pp and pp.count then count = tostring(pp.count) end
        return "tags:" .. table.concat(tagIds, ",") .. "|" .. count
    end
    local novelId = string.match(bookUrl, "/novel/(%d+)/")
    if not novelId then
        return nil
    end""", src, "getChapterListHash")

# getChapterList
src = replace_once("""function getChapterList(bookUrl)
    local novelId = string.match(bookUrl, "/novel/(%d+)/")
    if not novelId then
        log_error("wtrlab: cannot extract novelId from " .. bookUrl)
        return {}
    end""",
"""function getChapterList(bookUrl)
    local tagIds = parseTagBookUrl(bookUrl)
    if tagIds then
        local novels = tagBookChapterList(tagIds)
        log_info("wtrlab: tag book: " .. tostring(#novels) .. " novels")
        if #novels == 0 then
            return {}
        end
        return novels
    end
    local novelId = string.match(bookUrl, "/novel/(%d+)/")
    if not novelId then
        log_error("wtrlab: cannot extract novelId from " .. bookUrl)
        return {}
    end""", src, "getChapterList")

# getCatalogSearch: prepend tag matches
src = replace_once("""function getCatalogSearch(index, query)
    local page = index + 1
    local params = "text=" .. url_encode(query) .. "&page=" .. tostring(page)
    local pp = fetchCatalogPage("en/novel-finder", "/en/novel-finder.json", params)
    if not pp then
        log_error("wtrlab: getCatalogSearch failed")
        return { items = {}, hasNext = false }
    end
    return pagePropsToResult(pp, page)
end""",
"""function getCatalogSearch(index, query)
    local page = index + 1
    local params = "text=" .. url_encode(query) .. "&page=" .. tostring(page)
    local pp = fetchCatalogPage("en/novel-finder", "/en/novel-finder.json", params)
    if not pp then
        log_error("wtrlab: getCatalogSearch failed")
        return { items = {}, hasNext = false }
    end
    local result = pagePropsToResult(pp, page)

    -- v1.2.0 tag finder: the search bar also finds TAGS — every tag whose
    -- name contains the query is listed first as a tappable result (page 1
    -- only). Opening it browses the tag's novels (see the tag-book helpers).
    if page == 1 and query and query ~= "" then
        local lower = tostring(query):lower()
        local tagItems, seen = {}, {}
        for _, t in ipairs(ALL_TAGS) do
            if not seen[t.id] and t.lower:find(lower, 1, true) then
                seen[t.id] = true
                tagItems[#tagItems + 1] = {
                    title = "🏷 " .. t.label .. " — " ..
                        (TAG_CATEGORY_NAMES[t.cat] or "Tag"),
                    url = baseUrl .. "en/novel-finder?ti=" .. t.id
                }
                if #tagItems >= 8 then break end
            end
        end
        if #tagItems > 0 then
            local merged = {}
            for _, it in ipairs(tagItems) do merged[#merged + 1] = it end
            for _, it in ipairs(result.items or {}) do merged[#merged + 1] = it end
            result.items = merged
            log_info("wtrlab: search: +" .. tostring(#tagItems) .. " tag results")
        end
    end
    return result
end""", src, "getCatalogSearch")

open(PLUG, "w", encoding="utf-8").write(src)
print(f"OK: {n_edits} edits applied, {orig_len} -> {len(src)} bytes ({len(src.splitlines())} lines)")
