#!/usr/bin/env python3
"""oop.lua v1.0.0 → v1.1.0 — the TOC Cloudflare-solver-storm fix.

User report: "OOP plugin isn't working novels arent loading, it keeps
launching cloudflare solver I think its trying to get content of each page
in table of contents, each page has 30 chapters."

Root cause (verified against the engine source):
1. oop.tw challenges requests aggressively; when the WebView-baked
   cf_clearance does not validate for the OkHttp retry, EVERY http_get
   re-runs the full interceptor dance (15 s hidden WebView + up to 2 x 35 s
   manual WebViewActivity).
2. v1.0.0 getChapterList walked every ?p=N catalog page and, when a page
   failed ({success=false} from the interceptor's exception), just SKIPPED
   it and fetched the next one => one solver launch per 30-chapter page.
3. Every TOC open re-walked all pages (only a 60 s in-memory cache existed).

Fix (v1.1.0):
- parsePage(bookUrl, page): the engine's paginated chapter-list API
  (present in BOTH the Aug-25 and Sep-18 engine builds). New engines walk
  pages via parsePage and STOP at the first failure; TOC refreshes become
  incremental (re-read the last page + new pages only).
- getChapterList (old-engine fallback): ABORT at the first failed page.
- Persistent per-book page cache (set_preference): interior pages
  (below the known page count — oop.tw only appends chapters, so pages
  1..N-1 are immutable) are served without network; the last known page is
  always fetched fresh; stale copies are served when a fetch fails, and
  progress accumulates across retries.
- getChapterListHash: now includes totalPages + last chapter number (from
  the pager's option labels) so library updates detect new chapters even
  when the update-time string does not change.
- show_error with actionable CF guidance when page 1 is unreachable and no
  cached copy exists.

This script splices the changes into download/oop.lua with exact-string
anchors (iterate in place — do not regenerate).
"""
import re
import sys

PATH = "/home/z/my-project/download/oop.lua"

with open(PATH, encoding="utf-8") as f:
    s = f.read()

orig_len = len(s)

# ─── 1. version + header ────────────────────────────────────────────────────
old = 'local VERSION = "1.0.0"'
assert s.count(old) == 1, "version anchor"
s = s.replace(old, 'local VERSION = "1.1.0"')

old = "-- OOP 小說網 (oop.tw) source plugin for NoveLA\n-- Version 1.0.0 (2026-09-19)\n"
assert s.count(old) == 1, "header version anchor"
s = s.replace(old, """-- OOP 小說網 (oop.tw) source plugin for NoveLA
-- Version 1.1.0 (2026-09-19)
--
-- v1.1.0 — CHAPTER-LIST CLOUDFLARE FIX ("solver storm"):
--   Opening a novel used to launch the Cloudflare solver once per catalog
--   page (30 chapters each). Cause: when oop.tw's challenge does not clear
--   for the app's HTTP client, EVERY request re-runs the WebView solver,
--   and v1.0.0 kept fetching the next ?p=N page after each failure. Fixes:
--   • parsePage(bookUrl, page) — the engine's paginated chapter-list API.
--     Engines walk catalog pages through it and STOP at the first failed
--     page; TOC refreshes become incremental (last page + new pages only).
--   • getChapterList (older-engine fallback) aborts at the first failed
--     page — never launches consecutive solvers.
--   • Persistent per-book page cache: interior pages are immutable on this
--     site (chapters are only appended), so they are served without any
--     network request; the walk resumes where the last attempt stopped and
--     a stale copy is served when the site is unreachable.
""")

# ─── 2. shared catalog helpers + persistent cache (before Book details) ─────
anchor = """-- ═══════════════════════════════════════════════════════════════════════════
-- Book details
-- ═══════════════════════════════════════════════════════════════════════════"""
assert s.count(anchor) == 1, "book details anchor"

CATALOG_BLOCK = """-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter catalog: shared parsing + persistent page cache (v1.1.0)
-- ═══════════════════════════════════════════════════════════════════════════
-- Every catalog page carries the full page list in its .chap-pager select
-- (live-verified on pages 1 and 2), so ANY page yields totalPages.
-- Chapter URLs use global article ids (/areada/a{book}a/a{article}a.html) —
-- they cannot be synthesized, pages must be enumerated.

local function parseCatalogChapters(body)
  local out = {}
  for _, a in ipairs(html_select(body, "#ul_all_chapters li.chapter-item a")) do
    local chUrl = absUrl(a.href)
    if chUrl ~= "" then
      local title = string_clean(a.text)
      if title == "" then title = (a.title or "") end
      if title ~= "" then out[#out + 1] = { title = title, url = chUrl } end
    end
  end
  return out
end

local function catalogTotalPages(body)
  local maxp = 1
  for _, sel in ipairs(html_select(body, ".chap-pager select option")) do
    local ok, v = pcall(function() return sel.attr("value") end)
    if ok and v and v ~= "" then
      local n = tonumber(v)
      if n and n > maxp then maxp = n end
    end
  end
  return maxp
end

-- The site occasionally swaps adjacent chapters (live-verified:
-- 003,005,004,006…). When EVERY title carries an unambiguous chapter
-- number, sort by it; otherwise keep the site's order.
local function chapterSortKey(title)
  local n = tonumber(string.match(title, "^(%d+)$"))
  if not n then n = tonumber(string.match(title, "^第(%d+)%s*[章节回]")) end
  if not n then n = tonumber(string.match(title, "^[Cc]hapter%s+(%d+)")) end
  return n
end

local function sortNumericChapters(chapters)
  if #chapters < 2 then return chapters end
  local keyed = {}
  for i, ch in ipairs(chapters) do
    local k = chapterSortKey(ch.title)
    if not k then return chapters end
    keyed[i] = { k = k, ch = ch }
  end
  table.sort(keyed, function(a, b) return a.k < b.k end)
  local out = {}
  for i, e in ipairs(keyed) do out[i] = e.ch end
  return out
end

-- ── Persistent TOC page cache (set_preference) ─────────────────────────────
-- One preference per book: "oop_toc_<id>" =
--   "1|<totalPages>|<page>\031<title>\031<url>\030… \029<page>\031…"
-- (\029 group sep = page, \030 record sep = chapter, \031 unit sep = field)
-- Interior pages (page < totalPages) are immutable — oop.tw only APPENDS
-- chapters — so they are served without network. The last known page and
-- anything beyond it is always fetched fresh. On fetch failure the stale
-- cached copy is served rather than failing (a readable stale TOC beats an
-- error screen), and progress accumulates across retries.

local TOC_PREF_PREFIX = "oop_toc_"
local TOC_PREF_LRU    = "oop_toc_lru"
local TOC_MAX_BOOKS   = 5      -- LRU cap (cached books)
local TOC_MAX_BYTES   = 100000 -- per-book serialization cap

local function tocPrefKey(bookUrl)
  local id = string.match(bookUrl, "/abooka/a(%d+)a")
  if not id then id = string.match(bookUrl, "a(%d+)a") end
  return id and (TOC_PREF_PREFIX .. id) or nil
end

local function tocCacheLoad(bookUrl)
  local key = tocPrefKey(bookUrl)
  if not key then return nil end
  local ok, v = pcall(get_preference, key)
  if not (ok and type(v) == "string" and v ~= "") then return nil end
  local ver, tpStr, data = string.match(v, "^(%d+)|(%d+)|(.*)$")
  if not ver then return nil end
  local entry = { totalPages = tonumber(tpStr) or 1, pages = {} }
  for block in string.gmatch(data, "[^\\029]+") do
    local pStr, recs = string.match(block, "^(%d+)\\031(.*)$")
    local p = tonumber(pStr)
    if p then
      local chs = {}
      for rec in string.gmatch(recs, "[^\\030]+") do
        local t, u = string.match(rec, "^(.*)\\031(.*)$")
        if t and u and t ~= "" and u ~= "" then
          chs[#chs + 1] = { title = t, url = u }
        end
      end
      entry.pages[p] = chs
    end
  end
  return entry
end

-- Keep only pages that stay interior under the NEW page count: the
-- previous last page can keep filling up before spilling onto a new page,
-- so it (and anything beyond) is dropped when totalPages changes.
local function tocMerge(entry, page, totalPages, chapters)
  local old = entry or { totalPages = totalPages, pages = {} }
  local keep = math.min(old.totalPages or 1, totalPages) - 1
  local pages = {}
  for p, chs in pairs(old.pages or {}) do
    if p <= keep then pages[p] = chs end
  end
  pages[page] = chapters
  return { totalPages = totalPages, pages = pages }
end

local function tocCacheSave(bookUrl, entry)
  local key = tocPrefKey(bookUrl)
  if not key then return end
  local pnums = {}
  for p in pairs(entry.pages or {}) do pnums[#pnums + 1] = p end
  table.sort(pnums)
  local blocks = {}
  for _, p in ipairs(pnums) do
    local recs = {}
    for _, ch in ipairs(entry.pages[p]) do
      recs[#recs + 1] = ch.title .. "\\031" .. ch.url
    end
    blocks[#blocks + 1] = tostring(p) .. "\\031" .. table.concat(recs, "\\030")
  end
  local data = table.concat(blocks, "\\029")
  if #data > TOC_MAX_BYTES then return end -- oversized book: skip persisting
  local ok = pcall(set_preference, key,
    "1|" .. tostring(entry.totalPages or 1) .. "|" .. data)
  if not ok then return end
  -- LRU bookkeeping: evict the least-recently-used books beyond the cap
  local id = string.sub(key, #TOC_PREF_PREFIX + 1)
  local okL, lru = pcall(get_preference, TOC_PREF_LRU)
  local order = {}
  if okL and type(lru) == "string" and lru ~= "" then
    for v in string.gmatch(lru, "[^,]+") do order[#order + 1] = v end
  end
  local keep = { id }
  for _, v in ipairs(order) do
    if v ~= id and #keep < TOC_MAX_BOOKS then keep[#keep + 1] = v end
  end
  for _, v in ipairs(order) do
    local kept = false
    for _, k in ipairs(keep) do
      if k == v then kept = true; break end
    end
    if not kept then pcall(set_preference, TOC_PREF_PREFIX .. v, "") end
  end
  pcall(set_preference, TOC_PREF_LRU, table.concat(keep, ","))
end

-- Fetch one catalog page: persistent-cache fast path for immutable interior
-- pages, fresh fetch otherwise, stale cached copy as a last resort.
-- Returns (chapters, totalPages) or (nil, nil).
local function tocFetchPage(bookUrl, page)
  local entry = tocCacheLoad(bookUrl)

  -- interior page below the cached watermark: serve without network
  if page > 1 and entry and page < entry.totalPages and entry.pages[page] then
    return entry.pages[page], entry.totalPages
  end

  local body = nil
  if page == 1 then
    local r = fetchPageCached(bookUrl)
    if r and r.success then body = r.body end
  else
    local path = string.match(bookUrl, "^https?://[^/]+(/.*)$") or "/"
    local r = httpGetPage(path .. "?p=" .. tostring(page))
    if r and r.success then body = r.body end
  end

  if not body then
    if entry and entry.pages[page] then
      return entry.pages[page], entry.totalPages -- stale beats nothing
    end
    return nil, nil
  end

  local chapters = parseCatalogChapters(body)
  if #chapters == 0 and page > 1 then
    -- a body without the catalog list is a soft block / error page
    if entry and entry.pages[page] then
      return entry.pages[page], entry.totalPages
    end
    return nil, nil
  end
  chapters = sortNumericChapters(chapters)
  local totalPages = catalogTotalPages(body)
  if totalPages < page then totalPages = page end
  tocCacheSave(bookUrl, tocMerge(entry, page, totalPages, chapters))
  return chapters, totalPages
end

-- Global numeric re-sort + chapter-title translation. Always returns a
-- fresh list when translating — cached tables must never be mutated.
local function finalizeToc(chapters)
  local sorted = sortNumericChapters(chapters)
  if trActive() and trChaptersEnabled() and #sorted > 0 then
    local titles = {}
    for i = 1, #sorted do titles[i] = sorted[i].title end
    local tr = translateBatch(titles)
    local out = {}
    for i = 1, #sorted do out[i] = { title = tr[i], url = sorted[i].url } end
    return out
  end
  return sorted
end

local function tocShowUnreachable()
  show_error("Cloudflare / network unreachable",
    "The chapter list could not be loaded from www.oop.tw (Cloudflare " ..
    "challenge or network issue).\\n\\nIf the Cloudflare solver keeps " ..
    "reappearing: let it finish once, or open www.oop.tw once in a browser " ..
    "on this device, then retry here. Progress is remembered — each retry " ..
    "resumes where the last one stopped.")
end

"""
s = s.replace(anchor, CATALOG_BLOCK + anchor)

# ─── 3. getChapterListHash — richer change signal ───────────────────────────
old = """function getChapterListHash(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local el = html_select_first(r.body, ".latest-chapter .update-time")
  local ts = el and string_clean(el.text) or ""
  local chapters = html_select(r.body, "#ul_all_chapters li.chapter-item a")
  if ts ~= "" or #chapters > 0 then
    return ts .. "|" .. tostring(#chapters)
  end
  return nil
end"""
assert s.count(old) == 1, "getChapterListHash anchor"
s = s.replace(old, """function getChapterListHash(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local el = html_select_first(r.body, ".latest-chapter .update-time")
  local ts = el and string_clean(el.text) or ""
  local totalPages = catalogTotalPages(r.body)
  -- last chapter number from the pager's option labels ("第31～44章" → 44)
  local lastNum = 0
  for _, sel in ipairs(html_select(r.body, ".chap-pager select option")) do
    local t = string_clean(sel.text or "")
    local n = tonumber(string.match(t, "(%d+)章$"))
    if n and n > lastNum then lastNum = n end
  end
  if ts ~= "" or totalPages > 1 or lastNum > 0 then
    return ts .. "|" .. tostring(totalPages) .. "|" .. tostring(lastNum)
  end
  return nil
end""")

# ─── 4. replace the chapter-list section with parsePage + hardened walk ─────
i_start = s.index("-- Chapter list (paginated catalog")
i_start = s.rindex("-- ═", 0, i_start)
i_end = s.index("-- Chapter text")
i_end = s.rindex("-- ═", 0, i_end)

NEW_SECTION = """-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter list — paginated, solver-safe (v1.1.0)
-- ═══════════════════════════════════════════════════════════════════════════
-- Two entry points, same core (tocFetchPage):
--   • parsePage(bookUrl, page) — the engine's paginated API (both the
--     Aug-25 and Sep-18 engine builds support it). The engine walks pages
--     2..totalPages itself and STOPS at the first failure; TOC refreshes
--     are incremental (last known page + new pages only).
--   • getChapterList(bookUrl) — the fallback for engines without parsePage.
--     ABORTS at the first failed page: when oop.tw's Cloudflare challenge
--     does not clear for the app's HTTP client, each failed fetch already
--     cost a full WebView-solver attempt (15 s hidden + up to 2 x 35 s
--     manual) — walking on would launch the solver once per page.
-- Both paths persist every parsed page (see the TOC cache above), so a
-- walk that dies mid-way resumes where it stopped on the next attempt.

function parsePage(bookUrl, page)
  local raw, totalPages = tocFetchPage(bookUrl, page)
  if raw == nil or (page == 1 and #raw == 0) then
    if page == 1 then tocShowUnreachable() end
    return nil -- non-table: the engine stops the walk / surfaces the error
  end
  return { chapters = finalizeToc(raw), totalPages = totalPages or page }
end

function getChapterList(bookUrl)
  local p1, totalPages = tocFetchPage(bookUrl, 1)
  if p1 == nil or #p1 == 0 then
    -- last resort: the last-known TOC from the persistent cache
    local entry = tocCacheLoad(bookUrl)
    if entry then
      local all = {}
      for p = 1, entry.totalPages do
        if entry.pages[p] then
          for _, ch in ipairs(entry.pages[p]) do all[#all + 1] = ch end
        end
      end
      if #all > 0 then return finalizeToc(all) end
    end
    tocShowUnreachable()
    return {}
  end

  local chapters = {}
  for _, ch in ipairs(p1) do chapters[#chapters + 1] = ch end
  totalPages = totalPages or 1
  for p = 2, totalPages do
    local raw, tp = tocFetchPage(bookUrl, p)
    if raw == nil then break end -- ABORT at the first failed page
    if tp and tp > totalPages then totalPages = tp end
    for _, ch in ipairs(raw) do chapters[#chapters + 1] = ch end
  end
  return finalizeToc(chapters)
end


"""
s = s[:i_start] + NEW_SECTION + s[i_end:]

# ─── 5. sanity ──────────────────────────────────────────────────────────────
assert s.count("function parsePage") == 1
assert s.count("function getChapterList(bookUrl)") == 1
assert s.count("function getChapterListHash") == 1
assert s.count("tocFetchPage") >= 4
assert s.count('local VERSION = "1.1.0"') == 1
for lit in ("\\029", "\\030", "\\031"):
    assert s.count(lit) >= 2, f"missing Lua-side escape {lit}"

with open(PATH, "w", encoding="utf-8") as f:
    f.write(s)

print(f"OK: oop.lua patched {orig_len} -> {len(s)} chars "
      f"(+{len(s) - orig_len})")
