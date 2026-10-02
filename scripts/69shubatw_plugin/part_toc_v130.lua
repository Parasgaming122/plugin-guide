-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter catalog — /Indexlist/{id}/{N}/  (v1.3.0, fully rewritten)
-- ═══════════════════════════════════════════════════════════════════════════
-- THE WAF DISCOVERY (live-verified 2026-09-26, book 342441 = 450 chapters on
-- 5 pages): the site sits behind Tencent EdgeOne whose PATH rule challenges
-- lowercase /indexlist/* from every IP — even Google Translate's clean
-- egress and (on real phones) after solving, because the __ct_ac_cpg pass
-- cookie lives only 5 minutes. That rule made every catalog request open
-- the WebView solver (the "5+ solver openings, chapters never loaded" bug).
-- The rule is CASE-SENSITIVE and the site router is NOT:
--     https://69shuba.tw/Indexlist/342441/   → 200, real page, WAF-free
--     https://69shuba.tw/indexlist/342441/   → 403 challenge (any IP)
-- All catalog fetches therefore use the capital form. /book/* and /read/*
-- carry no such rule (lowercase is fine and stays canonical).

-- The catalog page URL (capital I — see above). Page 1 is unnumbered.
local function tocPageUrl(bookId, page)
  if page <= 1 then
    return SITE .. "/Indexlist/" .. tostring(bookId) .. "/"
  end
  return SITE .. "/Indexlist/" .. tostring(bookId) .. "/" .. tostring(page) .. "/"
end

-- The EdgeOne "aegis" challenge body (served with 403 or 200): a
-- reCAPTCHA-styled checkbox page that POSTs to /aegis_captcha_verify.
-- Any of these markers identifies it (all absent from real pages —
-- live-verified on the 5 captured catalog pages + 2 chapters).
local function isChallengeBody(body)
  if type(body) ~= "string" then return false end
  if string.find(body, "aegis_captcha_verify", 1, true) then return true end
  if string.find(body, "recaptcha-v3-container", 1, true) then return true end
  if string.find(body, "Please complete human verification", 1, true) then return true end
  if string.find(body, "challenges.cloudflare.com/turnstile", 1, true) then return true end
  return false
end

-- Collect chapter items from one HTML scope. TWO entry shapes live on the
-- catalog pages (book 342441: ~2 of every 100 are the span form — missing
-- them silently drops chapters from the TOC):
--   <li><a href="/read/{bid}/{cid}" title="…">第N章 …</a></li>
--   <li><span class="protected-chapter-link" data-cid-url="/read/{bid}/{cid}"
--         data-title="…">第N章 …</span></li>      ← anti-scrape form
local function collectChapterItems(scopeHtml, bookId, seen, out)
  local pat = "/read/" .. tostring(bookId) .. "/(%d+)"
  for _, a in ipairs(html_select(scopeHtml, "a")) do
    local href = a.href or ""
    local cidStr = string.match(href, pat)
    if cidStr then
      local cid = tonumber(cidStr)
      if cid and not seen[cid] then
        local title = string_clean(a.text or "")
        if title == "" then title = string_clean(a.title or "") end
        if title ~= "" then
          seen[cid] = true
          out[#out + 1] = { cid = cid, title = title,
                            url = SITE .. "/read/" .. tostring(bookId) .. "/" .. cidStr }
        end
      end
    end
  end
  for _, sp in ipairs(html_select(scopeHtml, "[data-cid-url]")) do
    local ok, u = pcall(function() return sp.attr("data-cid-url") end)
    local href = (ok and type(u) == "string") and u or ""
    local cidStr = string.match(href, pat)
    if cidStr then
      local cid = tonumber(cidStr)
      if cid and not seen[cid] then
        local title = string_clean(sp.text or "")
        if title == "" then
          local ok2, dt = pcall(function() return sp.attr("data-title") end)
          if ok2 and type(dt) == "string" then title = string_clean(dt) end
        end
        if title ~= "" then
          seen[cid] = true
          out[#out + 1] = { cid = cid, title = title,
                            url = SITE .. "/read/" .. tostring(bookId) .. "/" .. cidStr }
        end
      end
    end
  end
end

-- Chapters of ONE catalog page, cid-sorted (= reading order within a page,
-- live-verified monotonic). Scoped to div#alllist (the catalog container —
-- keeps future sidebars out) with a whole-page fallback for template drift.
local function parseTocChapters(body, bookId)
  local out = {}
  if not body or not bookId then return out end
  local seen = {}
  local scope = html_select_first(body, "div#alllist")
  if scope then collectChapterItems(scope.html, bookId, seen, out) end
  if #out == 0 then collectChapterItems(body, bookId, seen, out) end
  table.sort(out, function(x, y) return x.cid < y.cid end)
  return out
end

-- The pager's 下一页 link href (nil when absent / javascript) — GLOBAL
-- scan: wrapper classes vary across the site's surfaces.
local function tocNextLink(body)
  if not body then return nil end
  for _, a in ipairs(html_select(body, "a")) do
    local t = a.text or ""
    if string.find(t, "下一页", 1, true) or string.find(t, "下一頁", 1, true) then
      local href = a.href or ""
      if href ~= "" and string.find(href, "javascript", 1, true) == nil then
        return href
      end
    end
  end
  return nil
end

-- Total catalog pages from the pager (live-verified on book 342441):
--   select#indexselect-top (aria-label 章節目錄選擇) whose option VALUES are
--   the page paths "/indexlist/{id}/{N}/" — page 1 unnumbered, ALL pages
--   listed (5 options for the 450-chapter book: "1 - 100章" … "401 - 450章").
--   The 下一页 anchor is the cross-check (select-less pagers, and windows
--   on very long books — each fetched page re-reveals the true count).
-- REJECTS the page number == book id (page-1's unnumbered option value
-- "/indexlist/{id}/" — the v1.1.0 trap) and absurd counts (> 2000).
local function tocTotalPages(body, bookId)
  local maxp = 1
  if not body then return maxp end
  local idStr = tostring(bookId or "")
  local sels = html_select(body, "select[id*=indexselect]")
  if #sels == 0 then sels = html_select(body, "select") end
  for _, sel in ipairs(sels) do
    for _, opt in ipairs(html_select(sel.html, "option")) do
      local ok, v = pcall(function() return opt.attr("value") end)
      if ok and type(v) == "string" and v ~= "" then
        local n = tonumber(string.match(v, "/[Ii]ndexlist/" .. idStr .. "/(%d+)"))
          or tonumber(string.match(v, "/[Ii]ndexlist/" .. idStr .. "[_%-](%d+)"))
        if n and n ~= bookId and n > maxp and n <= 2000 then maxp = n end
      end
    end
  end
  local nextHref = tocNextLink(body)
  if nextHref then
    local nn = tonumber(string.match(nextHref, "/[Ii]ndexlist/" .. idStr .. "/(%d+)"))
    if nn and nn > maxp and nn <= 2000 then maxp = nn end
    if maxp < 2 then maxp = 2 end
  end
  return maxp
end

-- ── Persistent TOC cache (set_preference) ───────────────────────────────────
-- One preference per book: "s69tw_toc_<id>" =
--   v3: "3|<totalPages>|<data>"
-- data = <page>\031<title>\031<url>\030… \029… ( \029 page sep, \030 chapter
-- sep, \031 field sep )
-- v3 drops the v2 walk/urlBase fields (the walk layer is gone); v1/v2
-- entries fail the format match → discarded → fresh fetch. Interior pages
-- (page < totalPages) are immutable (the site only APPENDS chapters) and
-- served with zero network; the last known page always re-fetches fresh
-- (the book may have grown — its own select reveals new totalPages).

local TOC_PREF_PREFIX = "s69tw_toc_"
local TOC_PREF_LRU    = "s69tw_toc_lru"
local TOC_MAX_BOOKS   = 5      -- LRU cap (cached books)
local TOC_MAX_BYTES   = 150000 -- per-book serialization cap

local function tocPrefKey(bookUrl)
  local id = bookIdFromUrl(bookUrl)
  return id and (TOC_PREF_PREFIX .. id) or nil
end

local function tocCacheLoad(bookUrl)
  local key = tocPrefKey(bookUrl)
  if not key then return nil end
  local ok, v = pcall(get_preference, key)
  if not (ok and type(v) == "string" and v ~= "") then return nil end
  local tpStr, data = string.match(v, "^3|(%d+)|(.*)$")
  if not tpStr then return nil end -- v1/v2 (walk era) → discard
  local entry = { totalPages = tonumber(tpStr) or 1, pages = {} }
  for block in string.gmatch(data, "[^\029]+") do
    local pStr, recs = string.match(block, "^(%d+)\031(.*)$")
    local p = tonumber(pStr)
    if p then
      local chs = {}
      for rec in string.gmatch(recs, "[^\030]+") do
        local t, u = string.match(rec, "^(.*)\031(.*)$")
        if t and u and t ~= "" and u ~= "" then
          chs[#chs + 1] = { title = t, url = u }
        end
      end
      entry.pages[p] = chs
    end
  end
  return entry
end

-- Merge one parsed page into the entry: keeps cached pages at or below the
-- new page count, replaces the merged page.
local function tocMerge(entry, page, totalPages, chapters)
  local old = entry or { totalPages = totalPages, pages = {} }
  local pages = {}
  local keep = math.min(old.totalPages or 1, totalPages)
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
      recs[#recs + 1] = ch.title .. "\031" .. ch.url
    end
    blocks[#blocks + 1] = tostring(p) .. "\031" .. table.concat(recs, "\030")
  end
  local data = table.concat(blocks, "\029")
  if #data > TOC_MAX_BYTES then return end -- oversized: skip persisting
  local ok = pcall(set_preference, key,
    "3|" .. tostring(entry.totalPages or 1) .. "|" .. data)
  if not ok then return end
  -- LRU bookkeeping: evict least-recently-used books beyond the cap
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
      if v == k then kept = true; break end
    end
    if not kept then pcall(set_preference, TOC_PREF_PREFIX .. v, "") end
  end
  pcall(set_preference, TOC_PREF_LRU, table.concat(keep, ","))
end

-- ── page 1: ONE fetch, capital-I path ───────────────────────────────────────
-- No probes, no seed, no batch: every speculative request on this site
-- costs a full WebView-solver ladder when the WAF bites (the v1.2.0
-- storm). If page 1 is unreachable the STALE cache serves the last full
-- TOC (books stay readable offline), else a guided error.
local function tocFetchPage1(bookUrl)
  local bookId = bookIdFromUrl(bookUrl)
  if not bookId then return nil, nil end

  local r = fetchPageCached(tocPageUrl(bookId, 1))
  if r and r.success and not isChallengeBody(r.body) then
    local chapters = parseTocChapters(r.body, bookId)
    if #chapters > 0 then
      local tp = tocTotalPages(r.body, bookId)
      tocCacheSave(bookUrl, tocMerge(tocCacheLoad(bookUrl), 1, tp, chapters))
      return chapters, tp
    end
  end

  -- unreachable: a full TOC from a previous session beats nothing
  local entry = tocCacheLoad(bookUrl)
  if entry and entry.pages[1] and #entry.pages[1] > 0 then
    return entry.pages[1], entry.totalPages
  end
  return nil, nil
end

-- ── page N > 1: lazy, one deterministic URL, cache-first ────────────────────
-- Interior pages below the watermark serve from the persistent cache with
-- ZERO network; the last page re-fetches fresh (growth check — its own
-- select reveals the new totalPages, the engine extends the walk).
-- Soft-serve guard: a wrong page-N URL re-serving page 1 (a real page N
-- never starts at chapter 1) stops the walk instead of polluting the TOC.
local function tocFetchPageN(bookUrl, page)
  if page < 2 then return nil, nil end
  local bookId = bookIdFromUrl(bookUrl)
  if not bookId then return nil, nil end
  local entry = tocCacheLoad(bookUrl)

  if entry and page < entry.totalPages and entry.pages[page]
     and #entry.pages[page] > 0 then
    return entry.pages[page], entry.totalPages
  end

  local r = fetchPageCached(tocPageUrl(bookId, page))
  if r and r.success and not isChallengeBody(r.body) then
    local chapters = parseTocChapters(r.body, bookId)
    if #chapters > 0 then
      local p1 = entry and entry.pages[1]
      if p1 and #p1 > 0 and p1[1].url == chapters[1].url then
        return nil, nil -- soft-served page 1: stop the walk
      end
      local tp = tocTotalPages(r.body, bookId)
      if tp < page then tp = page end
      tocCacheSave(bookUrl, tocMerge(entry, page, tp, chapters))
      return chapters, tp
    end
  end

  -- stale beats nothing (transient failure on the live page)
  if entry and entry.pages[page] and #entry.pages[page] > 0 then
    return entry.pages[page], entry.totalPages
  end
  return nil, nil
end

-- Chapter-title translation on COPIES (the cache stores raw titles) — a
-- fresh list is returned whenever translating is active.
local function finalizeToc(chapters)
  if trActive() and trChaptersEnabled() and #chapters > 0 then
    local titles = {}
    for i = 1, #chapters do titles[i] = chapters[i].title end
    local tr = translateBatch(titles)
    local out = {}
    for i = 1, #chapters do out[i] = { title = tr[i], url = chapters[i].url } end
    return out
  end
  return chapters
end

local function tocShowUnreachable()
  if type(show_error) == "function" then
    show_error("Chapter list unreachable",
      "The chapter list could not be loaded from 69shuba.tw (the site's " ..
      "human-verification wall or a network issue).\n\nIf a verification " ..
      "page appears, complete it once and retry — the catalog now loads " ..
      "through a verification-exempt path, so this should be rare. " ..
      "Progress is remembered: each retry resumes where the last one stopped.")
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter list — engine entry points
-- ═══════════════════════════════════════════════════════════════════════════
-- parsePage(bookUrl, page) — the engine's paginated API (the engine walks
--   pages 1..totalPages sequentially and KEEPS what it has when a page
--   fails — early-stop is safe). Page 1 NEVER returns nil (the v1.0.0
--   "parsePage returned non-table" bug): worst case an empty table after
--   show_error. Pages > 1 return nil on failure — the engine stops there.
-- getChapterList(bookUrl) — fallback for engines without parsePage: the
--   same lazy pages driven to completion in one call. Pages are disjoint
--   and each is cid-sorted; the concatenation is NOT re-sorted (page order
--   IS reading order — re-sorting globally by cid would scramble books
--   whose later chapters carry re-uploaded ids).

function parsePage(bookUrl, page)
  if page == 1 then
    local raw, tp = tocFetchPage1(bookUrl)
    if raw == nil or #raw == 0 then
      tocShowUnreachable()
      return { chapters = {}, totalPages = 1 }
    end
    return { chapters = finalizeToc(raw), totalPages = tp or 1 }
  end

  local raw, tp = tocFetchPageN(bookUrl, page)
  if raw == nil or #raw == 0 then return nil end -- engine stops the walk
  return { chapters = finalizeToc(raw), totalPages = tp or page }
end

function getChapterList(bookUrl)
  local p1, tp = tocFetchPage1(bookUrl)
  if p1 == nil or #p1 == 0 then
    -- last resort: any cached pages (offline reading)
    local entry = tocCacheLoad(bookUrl)
    if entry then
      local all = {}
      local pnums = {}
      for p in pairs(entry.pages or {}) do pnums[#pnums + 1] = p end
      table.sort(pnums)
      for _, p in ipairs(pnums) do
        for _, ch in ipairs(entry.pages[p]) do all[#all + 1] = ch end
      end
      if #all > 0 then return finalizeToc(all) end
    end
    tocShowUnreachable()
    return {}
  end

  local chapters, seenUrl = {}, {}
  for _, ch in ipairs(p1) do
    chapters[#chapters + 1] = ch
    seenUrl[ch.url] = true
  end
  tp = tp or 1
  for p = 2, tp do
    local raw, tp2 = tocFetchPageN(bookUrl, p)
    if raw == nil then break end -- ABORT at the first failed page
    if tp2 and tp2 > tp then tp = tp2 end
    for _, ch in ipairs(raw) do
      if not seenUrl[ch.url] then
        chapters[#chapters + 1] = ch
        seenUrl[ch.url] = true
      end
    end
  end
  return finalizeToc(chapters)
end

