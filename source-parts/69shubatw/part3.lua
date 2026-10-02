
-- ═══════════════════════════════════════════════════════════════════════════
-- List-page parsing + catalog browse
-- ═══════════════════════════════════════════════════════════════════════════
-- /quanben/fenlei/, /fenlei/{slug}/ and /search/ share the card markup:
--   table.list-item
--     td a img                     → cover (//p.69shuba.tw/…)
--     td div.article a (1st)       → title + book URL (search pages wrap
--                                    match terms in .highlight spans —
--                                    text concatenation merges them)
--     p.fs12.gray span.mr15        → "作者:X" or "作者:X　N萬字"
--     a span.fs12.gray             → synopsis snippet
-- Pager (div.index-container): prev is a disabled SPAN on page 1 (an <a> on
-- later pages), next is ALWAYS an <a> whose text is 下一页 — hasNext =
-- such a link exists. The select#indexselect options carry page paths.

local function parseListCards(body)
  local items = {}
  if not body then return items end
  for _, card in ipairs(html_select(body, "table.list-item")) do
    local img = html_attr(card.html, "img", "src")
    local titleEl = html_select_first(card.html, "div.article a")
    local href = titleEl and titleEl.href or ""
    if titleEl and href and href ~= "" then
      local title = string_clean(titleEl.text or "")
      if title ~= "" then
        local bid = tonumber(string.match(absUrl(href), "/book/(%d+)"))
        items[#items + 1] = {
          title = title,
          url   = absUrl(href),
          cover = coverFromImg(img, bid)
        }
      end
    end
  end
  return items
end

-- hasNext: an <a> in the pager whose text is 下一页 (Simplified — the
-- site's pager literals are Simplified even on Traditional pages).
local function listHasNext(body)
  if not body then return false end
  for _, a in ipairs(html_select(body, "div.index-container a")) do
    local t = a.text or ""
    if string.find(t, "下一页") or string.find(t, "下一頁") then
      local href = a.href or ""
      if string.find(href, "javascript") == nil then return true end
    end
  end
  return false
end

local function translateCatalogItems(items)
  if not trActive() or #items == 0 then return items end
  local titles = {}
  for i = 1, #items do titles[i] = items[i].title end
  local tr = translateBatch(titles)
  for i = 1, #items do items[i].title = tr[i] end
  return items
end

local function unreachableError(what)
  if type(show_error) == "function" then
    show_error("69shuba.tw unreachable",
      "Could not load " .. what .. " from 69shuba.tw (network issue or the " ..
      "site's human-verification wall).\n\nIf a verification page appears, " ..
      "tick the \"I'm not a robot\" box once — it usually passes on real " ..
      "devices — then retry.")
  end
end

-- ── Catalog ──────────────────────────────────────────────────────────────────
-- Default surface: the 全部小說 ranking /quanben/fenlei/{N}/ (1-based in
-- the URL; the app's index is 0-based). Filtered: /fenlei/{slug}/{N}/.

function getCatalogList(index)
  local path = "/quanben/fenlei/"
  if index > 0 then path = "/quanben/fenlei/" .. tostring(index + 1) .. "/" end
  local r = httpGetPage(path)
  if not (r and r.success) then
    unreachableError("the novel list")
    return { items = {}, hasNext = false }
  end
  local items = parseListCards(r.body)
  translateCatalogItems(items)
  return { items = items, hasNext = listHasNext(r.body) }
end

function getCatalogFiltered(index, filters)
  local cat = filters and filters.category
  local path
  if cat and cat ~= "" and cat ~= "all" then
    if cat == "quanben" then
      path = "/quanben/fenlei/" .. tostring(index + 1) .. "/"
    else
      path = "/fenlei/" .. cat .. "/" .. tostring(index + 1) .. "/"
    end
  else
    path = "/quanben/fenlei/"
    if index > 0 then path = "/quanben/fenlei/" .. tostring(index + 1) .. "/" end
  end
  local r = httpGetPage(path)
  if not (r and r.success) then
    unreachableError("the category")
    return { items = {}, hasNext = false }
  end
  local items = parseListCards(r.body)
  translateCatalogItems(items)
  return { items = items, hasNext = listHasNext(r.body) }
end

function getFilterList()
  local catOptions = {
    { value = "all",     label = flLabel("All Novels (全部小說)", "全部小說") },
    { value = "quanben", label = flLabel("Completed Ranking (完結)", "完結") }
  }
  for _, c in ipairs(CATEGORIES) do
    catOptions[#catOptions + 1] = { value = c.value, label = flLabel(c.en, c.zh) }
  end
  return {
    {
      type = "select",
      key = "category",
      label = "Category (分類)",
      options = catOptions
    }
  }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Search — GET /search/?searchkey={q}&searchtype=all (page 1, live-verified)
-- and /search/{N}?searchkey={q} (page N, from the pager's own URLs).
-- ═══════════════════════════════════════════════════════════════════════════
-- In Translator mode a non-Chinese query is first translated to Traditional
-- Chinese (the site indexes zh-TW titles); when that finds nothing the
-- Simplified variant is tried once — titles on this site may be either.

function getCatalogSearch(index, query)
  if type(query) ~= "string" or query == "" then
    return { items = {}, hasNext = false }
  end

  local q = query
  if not hasCJK(q) then
    local tw = translateQueryToZh(q, "zh-TW")
    if tw then q = tw end
  end

  local function searchUrl(index, keyword)
    if index <= 0 then
      return SITE .. "/search/?searchkey=" .. url_encode(keyword) .. "&searchtype=all"
    end
    -- app index is 0-based; the site's page-N URL is 1-based (/search/2?…)
    return SITE .. "/search/" .. tostring(index + 1) .. "?searchkey=" .. url_encode(keyword)
  end

  local r = http_get(searchUrl(index, q), {
    headers = {
      ["Referer"] = SITE .. "/",
      ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    }
  })
  if not (r and r.success) then
    unreachableError("the search")
    return { items = {}, hasNext = false }
  end

  local items = parseListCards(r.body)

  -- zh-CN retry (translated queries that matched nothing, first page only)
  if index == 0 and q ~= query and #items == 0 then
    local cn = translateQueryToZh(query, "zh-CN")
    if cn and cn ~= q then
      local r2 = http_get(searchUrl(0, cn), {
        headers = { ["Referer"] = SITE .. "/", ["Accept"] = "text/html,*/*;q=0.8" }
      })
      if r2 and r2.success then
        items = parseListCards(r2.body)
        r = r2
      end
    end
  end

  translateCatalogItems(items)
  return { items = items, hasNext = listHasNext(r.body) }
end


-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter catalog — three-layer strategy (v1.1.0)
-- ═══════════════════════════════════════════════════════════════════════════
-- Layer 1 (real): /indexlist/{id}/{N}/ pages — the true TOC. That path is
--   EdgeOne-challenged even from Google's IPs (a path-specific WAF rule;
--   re-verified 2026-09-20: /book/342441/ 200-real vs /indexlist/342441/
--   403-captcha one minute apart). On reader devices it usually passes, and
--   cf_options.trigger_markers route the challenge into the app's WebView
--   ladder when it doesn't (one checkbox solve → cookies carry over).
-- Layer 2 (seed): the book page itself carries 最新章節預覽 (ul.last9 — up to
--   12 latest chapters with real titles) and #startread (chapter 1's URL).
--   The /book/ path is NOT WAF-hard, so a readable TOC exists even on app
--   builds without the WebView ladder.
-- Layer 3 (walk): /read/ pages are NOT WAF-hard either. When /indexlist/ is
--   unreachable the TOC is built by following the chapters' own #pb_next
--   chain from chapter 1 in WALK_CHUNK-sized virtual pages — no captcha
--   needed, works on ANY app build. Virtual page 1 IS the first walk chunk
--   (so positions come out in reading order), and the seed chapters are
--   emitted as the FINAL virtual page once the walk reaches them. Progress
--   persists across calls and app restarts; the walk aborts at the first
--   failed fetch (the oop.tw solver-storm lesson) and resumes where it
--   stopped. When the book grows past the seed window between refreshes,
--   the walk resumes from the last known chapter's #pb_next (one fetch).
-- The v1.0.0 bug this fixes: parsePage returned nil when /indexlist/ was
--   blocked → builds that don't propagate show_error surfaced the bare
--   "parsePage returned non-table" error. parsePage(1) now NEVER returns
--   nil — worst case an empty table after show_error.

local SEED_TOTAL_PAGES = 9999  -- forces a full reparse once the real TOC loads
local WALK_CHUNK       = 40    -- chapters per virtual page while walking
local SEED_TTL_MS      = 10000 -- replay memo: the engine calls parsePage(1) twice

local function cidFromUrl(u)
  return tonumber(string.match(u or "", "/read/%d+/(%d+)"))
end

-- Canonical chapter URL: strips queries/fragments, requires the same-book
-- /read/{bookId}/{cid} path shape, returns a SITE-absolute URL or nil.
local function normalizeReadUrl(u, bookId)
  local path = string.match(u or "", "^https?://[^/]+(/[^?#]*)")
    or string.match(u or "", "^(/[^?#]*)")
  if not path then return nil end
  if not string.match(path, "^/read/" .. tostring(bookId) .. "/%d+/?$") then
    return nil
  end
  return SITE .. path
end

-- Collect chapters from an /indexlist/ page. Returns an array of
-- { cid = n, title = s, url = s } sorted by cid. Layout-agnostic: the only
-- stable shape is the /read/{bookId}/{cid} href itself.
local function parseTocChapters(body, bookId)
  local seen, out = {}, {}
  if not body or not bookId then return out end
  local pat = "/read/" .. tostring(bookId) .. "/(%d+)"
  for _, a in ipairs(html_select(body, "a")) do
    local href = a.href or ""
    local cidStr = string.match(href, pat)
    if cidStr then
      local cid = tonumber(cidStr)
      if cid and not seen[cid] then
        local title = string_clean(a.text or "")
        if title == "" then title = string_clean(a.title or "") end
        if title ~= "" then
          seen[cid] = true
          out[#out + 1] = { cid = cid, title = title, url = absUrl(href) }
        end
      end
    end
  end
  table.sort(out, function(x, y) return x.cid < y.cid end)
  return out
end

-- totalPages from the pager's select options + how many options were seen.
-- Value shapes: "/indexlist/{id}/{N}/", "/search/{N}?searchkey=…", "N".
local function tocTotalPages(body)
  local maxp, count = 1, 0
  for _, opt in ipairs(html_select(body, "select#indexselect option")) do
    local ok, v = pcall(function() return opt.attr("value") end)
    if ok and type(v) == "string" and v ~= "" then
      local n = tonumber(string.match(v, "/(%d+)/?$"))
        or tonumber(string.match(v, "/(%d+)%?"))
        or tonumber(string.match(v, "^(%d+)$"))
      if n then
        count = count + 1
        if n > maxp then maxp = n end
      end
    end
  end
  return maxp, count
end

-- The pager's 下一页 link href (nil when absent / javascript).
local function tocNextLink(body)
  for _, a in ipairs(html_select(body, "div.index-container a")) do
    local t = a.text or ""
    if string.find(t, "下一页") or string.find(t, "下一頁") then
      local href = a.href or ""
      if string.find(href, "javascript") == nil then return href end
    end
  end
  return nil
end

-- The page-N URL template, learned from the pager's 下一页 link:
--   "/indexlist/342441/2/" → base "/indexlist/342441" → page N = base.."/N/"
local function tocPageBase(body)
  local href = tocNextLink(body)
  if href then
    local base = string.match(href, "^(.*)/%d+/?$")
    if base and string.find(base, "/indexlist/", 1, true) then return base end
  end
  return nil
end

-- ── Seed (layer 2) ──────────────────────────────────────────────────────────
-- ul.last9 anchors → latest chapters (real titles); #startread → ch1's URL
-- (its anchor text is 立即閱讀, NOT a title — chapter 1 is discovered with
-- its real title by the walk, which starts exactly at #startread).
-- seedMemo[bookUrl] = { seed = {list, startUrl}, page1 = <returned list>, ts }
local seedMemo = {}
local seedFetchFailed = {} -- [bookUrl] = true: /book/ fetch failed this process

local function seedFromBookPage(bookUrl)
  local bookId = bookIdFromUrl(bookUrl)
  if not bookId then return nil end
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then
    seedFetchFailed[bookUrl] = true
    return nil
  end
  local readPat = "/read/" .. tostring(bookId) .. "/(%d+)"
  local byCid = {}
  for _, a in ipairs(html_select(r.body, "ul.last9 a")) do
    local cid = tonumber(string.match(a.href or "", readPat))
    if cid then
      local title = string_clean(a.text or "")
      if title ~= "" and title ~= "更多章節>>" and title ~= "更多章节>>" then
        byCid[cid] = title
      end
    end
  end
  local startUrl = nil
  local sr = html_select_first(r.body, "#startread")
  if sr then
    startUrl = normalizeReadUrl(absUrl(sr.href or ""), bookId)
  end
  local cids = {}
  for c in pairs(byCid) do cids[#cids + 1] = c end
  if #cids == 0 and not startUrl then return nil end
  table.sort(cids)
  local list = {}
  for _, c in ipairs(cids) do
    list[#list + 1] = { title = byCid[c], url = SITE .. "/read/" .. bookId .. "/" .. c }
  end
  return { list = list, startUrl = startUrl }
end

local function seedFromMemo(bookUrl)
  local m = seedMemo[bookUrl]
  if not m then return nil end
  local now = nowMs()
  if now and (now - m.ts) < SEED_TTL_MS then return m end
  seedMemo[bookUrl] = nil
  return nil
end

-- The walk's termination set: URLs the seed already covers. A fresh seed
-- first (an ongoing book's last9 moved forward); the cached seed page as a
-- fallback when the book page is unreachable (tried once per process).
local function tocSeedUrls(bookUrl, entry)
  local m = seedFromMemo(bookUrl)
  local set = {}
  if m and m.seed then
    for _, ch in ipairs(m.seed.list) do set[ch.url] = true end
    return set
  end
  if not seedFetchFailed[bookUrl] then
    local s = seedFromBookPage(bookUrl)
    if s then
      for _, ch in ipairs(s.list) do set[ch.url] = true end
      return set
    end
  end
  if entry and entry.pages and entry.pages[1] then
    for _, ch in ipairs(entry.pages[1]) do set[ch.url] = true end
  end
  return set
end

-- ── Persistent TOC cache (set_preference) ───────────────────────────────────
-- One preference per book: "s69tw_toc_<id>" =
--   v1: "1|<totalPages>|<urlBase>|<data>"
--   v2: "2|<totalPages>|<urlBase>|<r|w>|<walkNext>|<seedPage>|<data>"
-- data = <page>\031<title>\031<url>\030… \029… ( \029 page sep, \030 chapter
-- sep, \031 field sep )
-- mode "r" (real): /indexlist/ pagination. Interior pages (page < totalPages)
--   are immutable (the site only APPENDS chapters) and served with zero
--   network; the last known page and beyond are always fetched fresh.
-- mode "w" (walk): virtual #pb_next-chain pages. pages[1] is the seed
--   (bookkeeping + termination set + stale-serve fallback); pages[2..N] are
--   walk chunks (virtual page N-1); when the walk reaches the seed, the seed
--   chapters are emitted as the FINAL walk page (index seedPage) so chapter
--   positions come out in reading order. walkNext is the frontier URL (the
--   next chapter to fetch; nil = walk complete). A mode switch in either
--   direction DROPS the other mode's pages: walk pagination and site
--   pagination do not align, keeping both would corrupt the TOC.

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
  local mode
  local tpStr, base, modeCh, walkNext, seedPage, data =
    string.match(v, "^2|(%d+)|([^|]*)|([rw])|([^|]*)|([^|]*)|(.*)$")
  if tpStr then
    mode = (modeCh == "w") and "walk" or "real"
  else
    local ver
    ver, tpStr, base, data = string.match(v, "^(%d+)|(%d+)|([^|]*)|(.*)$")
    if not ver then return nil end
    mode, walkNext, seedPage = "real", nil, nil
  end
  local entry = {
    totalPages = tonumber(tpStr) or 1,
    urlBase    = base or "",
    mode       = mode,
    walkNext   = (walkNext ~= nil and walkNext ~= "") and walkNext or nil,
    seedPage   = tonumber(seedPage) or nil,
    pages      = {}
  }
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

-- Merge one parsed page into the entry. A mode switch drops the other
-- mode's pages. Real mode keeps only pages interior under the NEW page
-- count; walk mode keeps everything (walk pages are append-only).
local function tocMerge(entry, page, totalPages, chapters, urlBase, mode, walkNext)
  mode = mode or "real"
  local old = entry or { totalPages = totalPages, urlBase = urlBase or "",
                         pages = {}, mode = mode, walkNext = nil, seedPage = nil }
  local pages = {}
  if old.mode == mode then
    if mode == "real" then
      local keep = math.min(old.totalPages or 1, totalPages) - 1
      for p, chs in pairs(old.pages or {}) do
        if p <= keep then pages[p] = chs end
      end
    else
      for p, chs in pairs(old.pages or {}) do pages[p] = chs end
    end
  end
  pages[page] = chapters
  return {
    totalPages = totalPages,
    urlBase    = urlBase or old.urlBase or "",
    mode       = mode,
    walkNext   = (mode == "walk") and (walkNext or old.walkNext) or nil,
    seedPage   = (mode == "walk") and old.seedPage or nil,
    pages      = pages
  }
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
  local modeCh = (entry.mode == "walk") and "w" or "r"
  local ok = pcall(set_preference, key,
    "2|" .. tostring(entry.totalPages or 1) .. "|" .. (entry.urlBase or "") ..
    "|" .. modeCh .. "|" .. (entry.walkNext or "") .. "|" ..
    tostring(entry.seedPage or "") .. "|" .. data)
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
      if k == v then kept = true; break end
    end
    if not kept then pcall(set_preference, TOC_PREF_PREFIX .. v, "") end
  end
  pcall(set_preference, TOC_PREF_LRU, table.concat(keep, ","))
end

-- Union two chapter lists by URL, cid-sorted (monotonic — no losses).
local function unionByCid(a, b)
  local seen, out = {}, {}
  for _, list in ipairs({ a, b }) do
    for _, ch in ipairs(list or {}) do
      if not seen[ch.url] then
        seen[ch.url] = true
        out[#out + 1] = ch
      end
    end
  end
  table.sort(out, function(x, y)
    return (cidFromUrl(x.url) or 0) < (cidFromUrl(y.url) or 0)
  end)
  return out
end

-- ── Window-chase: the true page count ───────────────────────────────────────
-- The pager's select is a 10-page WINDOW (observed on every list surface of
-- the site), so page 1 of a 15-page TOC reports only "10". When the window
-- is suspect (capped at >= 10, or no select at all while a next link
-- exists), probe the max-option page: its own window reveals more, and a
-- probed page without a 下一页 link IS the last page. Every probe is a real
-- TOC page the engine's walk needs anyway — it is merged into the cache and
-- served free later. Stops at the first failure. Returns (tp, entry).
local function chaseTotalPages(bookUrl, bookId, tp, optionCount, hasNext, entry, base)
  local probes = 0
  while hasNext and probes < 12 and (optionCount >= 10 or optionCount == 0 or probes > 0) do
    local P = math.max(tp, 2)
    local pu = (base ~= "" and base or SITE .. "/indexlist/" .. tostring(bookId)) .. "/" .. P .. "/"
    local pr = fetchPageCached(pu)
    if not (pr and pr.success) then break end
    local pch = parseTocChapters(pr.body, bookId)
    if #pch == 0 then break end -- soft block / error page
    local ptp, pOptCount = tocTotalPages(pr.body)
    local pNext = tocNextLink(pr.body) ~= nil
    entry = tocMerge(entry, P, math.max(ptp, P), pch, base, "real", nil)
    probes = probes + 1
    if not pNext then return P, entry end -- P is the last page
    optionCount = pOptCount
    if ptp > tp then tp = ptp else tp = P + 1 end
  end
  return tp, entry
end

-- ── Layer 3: the #pb_next walk (virtual pages) ──────────────────────────────
-- Virtual page N lives at entry.pages[N+1]. Fetch chapters sequentially
-- following each page's 下一章 link, starting from the seed's #startread
-- URL. Stops at the first failure (resumable), at the seed's chapters
-- (they are emitted as the FINAL page so positions stay in reading order),
-- at a foreign-book URL, or at the end of the book.
-- Returns the chapter list for the virtual page, or nil (stop/abort).
local function walkEnsure(bookUrl, vpage, entry, seedUrls)
  local bookId = bookIdFromUrl(bookUrl)
  if not bookId or vpage < 1 or not entry or entry.mode ~= "walk" then
    return nil
  end
  local pages = entry.pages or {}
  local idx = vpage + 1

  -- a cached walk page is complete when superseded, final, or full
  if pages[idx] and #pages[idx] > 0 and
     (pages[idx + 1] ~= nil or entry.walkNext == nil or #pages[idx] >= WALK_CHUNK) then
    return pages[idx]
  end

  -- sequential guard: only the frontier page (or the next one) can be built
  local maxP = 1
  for p in pairs(pages) do
    if p >= 2 and pages[p] and #pages[p] > 0 and p > maxP then maxP = p end
  end
  if idx < maxP or idx > maxP + 1 then return nil end

  local cur = pages[idx] or {}
  local frontier = normalizeReadUrl(entry.walkNext, bookId)
  local failed = false
  while #cur < WALK_CHUNK and frontier do
    if seedUrls[frontier] then break end                           -- seed reached
    local r = httpGetPage(frontier)
    if not (r and r.success) then failed = true break end          -- abort (resumable)
    local titleEl = html_select_first(r.body, "#nr_title")
    local title = titleEl and string_clean(titleEl.text or "") or ""
    if title ~= "" then
      title = string.gsub(title, "%s*%(.-%s*/%s*%d+%)%s*$", "")
      cur[#cur + 1] = { title = title, url = frontier }
    end
    local nextA = html_select_first(r.body, "a#pb_next")
    frontier = (nextA and nextA.href and nextA.href ~= "")
      and normalizeReadUrl(absUrl(nextA.href), bookId) or nil
  end

  if failed then
    -- save the partial chunk for resume, report the failure
    if #cur > 0 then
      tocCacheSave(bookUrl, tocMerge(entry, idx, SEED_TOTAL_PAGES, cur, "", "walk", frontier))
    end
    return nil
  end

  if #cur == 0 then
    -- walk done for this page: seed reached, end of book, or never started
    local neverStarted = (entry.walkNext == nil) and maxP <= 1
    local seedReached = frontier ~= nil
    if entry.seedPage == nil and pages[1] and #pages[1] > 0 and (seedReached or neverStarted) then
      local seedPage = pages[1]
      local pages2 = {}
      for p, chs in pairs(pages) do pages2[p] = chs end
      pages2[idx] = seedPage
      tocCacheSave(bookUrl, { totalPages = SEED_TOTAL_PAGES, urlBase = "",
        mode = "walk", walkNext = nil, seedPage = idx, pages = pages2 })
      return seedPage
    end
    return nil
  end

  tocCacheSave(bookUrl, tocMerge(entry, idx, SEED_TOTAL_PAGES, cur, "", "walk", frontier))
  return cur
end

-- ── Layers 1+2: page 1 ──────────────────────────────────────────────────────
-- Returns (chapters, totalPages, urlBase, mode) or (nil, nil, nil, nil).
-- Order: replay memo (identical result for the engine's immediate second
-- call — no second /indexlist/ ladder run) → real /indexlist/ fetch →
-- stale real cache → seed + first walk chunk → stale walk cache.
local function tocFetchPage1(bookUrl)
  local bookId = bookIdFromUrl(bookUrl)
  if not bookId then return nil, nil, nil, nil end

  local m = seedFromMemo(bookUrl)
  if m and m.page1 and #m.page1 > 0 then
    return m.page1, SEED_TOTAL_PAGES, "", "walk"
  end

  -- REAL: /indexlist/{id}/ (60s page cache — the double call is free)
  local r = fetchPageCached(SITE .. "/indexlist/" .. bookId .. "/")
  if r and r.success then
    local chapters = parseTocChapters(r.body, bookId)
    if #chapters > 0 then
      local entry = tocCacheLoad(bookUrl)
      local tp, optionCount = tocTotalPages(r.body)
      local hasNext = tocNextLink(r.body) ~= nil
      local base = tocPageBase(r.body) or (entry and entry.urlBase) or ""
      if base == "" then base = "/indexlist/" .. bookId end
      tp, entry = chaseTotalPages(bookUrl, bookId, tp, optionCount, hasNext, entry, base)
      if tp < 1 then tp = 1 end
      tocCacheSave(bookUrl, tocMerge(entry, 1, tp, chapters, base, "real", nil))
      return chapters, tp, base, "real"
    end
    -- 200 but no chapter anchors: soft block / JS-rendered page → fall through
  end

  -- stale REAL cache: a complete TOC from a previous session beats the seed
  local entry = tocCacheLoad(bookUrl)
  if entry and entry.mode == "real" and entry.pages[1] and #entry.pages[1] > 0 then
    return entry.pages[1], entry.totalPages, entry.urlBase, "real"
  end

  -- SEED + WALK
  local s = seedFromBookPage(bookUrl)
  if s and #s.list > 0 then
    local seedUrls = {}
    for _, ch in ipairs(s.list) do seedUrls[ch.url] = true end
    local e
    if entry and entry.mode == "walk" then
      e = entry
      local freshMin = cidFromUrl(s.list[1].url)
      local oldPage = e.seedPage and e.pages[e.seedPage] or nil
      local oldMax = oldPage and #oldPage > 0 and cidFromUrl(oldPage[#oldPage].url) or nil
      -- book grew past the seed window: resume from the last known chapter
      if e.walkNext == nil and e.seedPage and freshMin and oldMax and freshMin > oldMax then
        local r2 = httpGetPage(oldPage[#oldPage].url)
        if r2 and r2.success then
          local nextA = html_select_first(r2.body, "a#pb_next")
          local nx = (nextA and nextA.href and nextA.href ~= "")
            and normalizeReadUrl(absUrl(nextA.href), bookId) or nil
          if nx and not seedUrls[nx] then
            e.walkNext = nx
            e.seedPage = nil -- the fresh seed will be emitted at a NEW page
          end
        end
      end
      e.pages[1] = s.list
      if e.walkNext == nil and e.seedPage then
        -- walk complete: refresh the seed page (union — monotonic growth)
        e.pages[e.seedPage] = unionByCid(e.pages[e.seedPage], s.list)
      end
    else
      e = { totalPages = SEED_TOTAL_PAGES, urlBase = "", mode = "walk",
            walkNext = s.startUrl, seedPage = nil, pages = { [1] = s.list } }
    end
    tocCacheSave(bookUrl, e)
    local chunk1 = walkEnsure(bookUrl, 1, e, seedUrls)
    local page1 = (chunk1 and #chunk1 > 0) and chunk1 or s.list
    local now = nowMs()
    if now then
      seedMemo[bookUrl] = { seed = s, page1 = page1, ts = now }
    end
    return page1, SEED_TOTAL_PAGES, "", "walk"
  end

  -- stale WALK cache (book page unreachable but walk pages exist)
  if entry and entry.mode == "walk" then
    if entry.pages[2] and #entry.pages[2] > 0 then
      return entry.pages[2], SEED_TOTAL_PAGES, "", "walk"
    end
    if entry.pages[1] and #entry.pages[1] > 0 then
      return entry.pages[1], SEED_TOTAL_PAGES, "", "walk"
    end
  end

  return nil, nil, nil, nil
end

-- ── page N > 1 dispatcher ────────────────────────────────────────────────────
-- Real mode: interior pages from cache, fresh fetch otherwise, stale copy as
-- a last resort. Walk mode: virtual walk pages. No page-1 data at all: nil
-- with ZERO network (a walk without a starting point would only re-run the
-- /indexlist/ ladder — the solver-storm defense).
local function tocFetchPageN(bookUrl, page)
  if page < 2 then return nil, nil, nil, nil end
  local bookId = bookIdFromUrl(bookUrl)
  if not bookId then return nil, nil, nil, nil end
  local entry = tocCacheLoad(bookUrl)

  if entry and entry.mode == "real" then
    -- interior page below the cached watermark: serve without network
    if page < entry.totalPages and entry.pages[page] then
      return entry.pages[page], entry.totalPages, entry.urlBase, "real"
    end
    local body = nil
    -- learned template first, site-pattern guess as fallback
    local base = entry.urlBase and entry.urlBase ~= "" and entry.urlBase or nil
    local guess = "/indexlist/" .. bookId .. "/" .. tostring(page) .. "/"
    local tries = {}
    if base then
      local u = base .. "/" .. tostring(page) .. "/"
      if u ~= guess then tries[#tries + 1] = u end
    end
    tries[#tries + 1] = guess
    for _, u in ipairs(tries) do
      local r = httpGetPage(u)
      if r and r.success and #parseTocChapters(r.body, bookId) > 0 then
        body = r.body
        break
      end
    end
    if body then
      local chapters = parseTocChapters(body, bookId)
      local tp = tocTotalPages(body)
      if tp < page then tp = page end
      local newBase = tocPageBase(body) or entry.urlBase or ""
      tocCacheSave(bookUrl, tocMerge(entry, page, tp, chapters, newBase, "real", nil))
      return chapters, tp, newBase, "real"
    end
    if entry.pages[page] then
      return entry.pages[page], entry.totalPages, entry.urlBase, "real" -- stale beats nothing
    end
    return nil, nil, nil, nil
  end

  if entry and entry.mode == "walk" then
    local seedUrls = tocSeedUrls(bookUrl, entry)
    return walkEnsure(bookUrl, page, entry, seedUrls)
  end

  -- no page-1 data of any kind: unanswerable without network noise
  return nil, nil, nil, nil
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
      "page appears, tick the \"I'm not a robot\" box once — it usually " ..
      "passes on real devices — then retry. Progress is remembered: each " ..
      "retry resumes where the last one stopped.")
  end
end
-- ═══════════════════════════════════════════════════════════════════════════
-- Book details — /book/{id}/
-- ═══════════════════════════════════════════════════════════════════════════
--   div.bookinfo table: td img (cover) + td.info:
--     h1                      title
--     p "作者：<a>作者</a>"
--     p "類別：<a>分類</a>"
--     p "狀態：連載 / 字數：66 萬字"
--     p "更新：2026-05-12 14:49:47"
--     p#lastchapter-row "最新：<a>第N章 …</a>"
--   div.intro p               description
--   #startread                first-chapter link (fallback for nothing here)

-- Label helper: value after "label：" (full-width) or "label:" (half-width).
local function afterLabel(t, label)
  local v = string.match(t, label .. "：(.*)$")
  if v == nil then v = string.match(t, label .. ":(.*)$") end
  return v
end

local function parseBookInfo(body)
  local out = {}
  for _, p in ipairs(html_select(body, "td.info p")) do
    local t = string_clean(p.text or "")
    if t ~= "" then
      if out.author == nil then
        local v = afterLabel(t, "作者")
        if v and v ~= "" then out.author = v end
      end
      if out.category == nil then
        local v = afterLabel(t, "類別")
        if v == nil then v = afterLabel(t, "类别") end
        if v and v ~= "" then out.category = v end
      end
      if out.status == nil then
        local v = afterLabel(t, "狀態")
        if v == nil then v = afterLabel(t, "状态") end
        if v then
          local st = string.match(v, "^(.-)%s*/%s*")
          if st == nil or st == "" then st = v end
          out.status = st
          local words = string.match(v, "字數：(%S+)")
          if words == nil then words = string.match(v, "字数：(%S+)") end
          if words then out.words = words end
        end
      end
      if out.updated == nil then
        local v = afterLabel(t, "更新")
        if v then
          out.updated = string.match(v, "(%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d)")
            or string.match(v, "(%d%d%d%d%-%d%d%-%d%d)")
            or v
        end
      end
      if out.latest == nil then
        local v = afterLabel(t, "最新")
        if v and v ~= "" then out.latest = v end
      end
    end
  end
  return out
end

function getBookTitle(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local el = html_select_first(r.body, "td.info h1")
  if not el then el = html_select_first(r.body, "div.bookinfo h1") end
  if not el then return nil end
  local title = string_clean(el.text)
  if title == "" then return nil end
  if trActive() then
    local tr = translateOne(title)
    if tr ~= title then return tr .. " (" .. title .. ")" end
  end
  return title
end

function getBookCoverImageUrl(bookUrl)
  -- the cover is deterministic from the book id — synthesize first so it
  -- works even when the book page is unreachable, then refine from the page
  local bookId = bookIdFromUrl(bookUrl)
  local r = fetchPageCached(bookUrl)
  if r and r.success then
    local src = html_attr(r.body, "div.bookinfo img", "src")
    local u = coverFromImg(src, bookId)
    if u then return u end
  end
  return synthCover(bookId)
end

function getBookDescription(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local el = html_select_first(r.body, "div.intro")
  local desc = el and string_clean(el.text) or ""
  local info = parseBookInfo(r.body)
  local header = ""
  if info.author and info.author ~= "" then
    header = header .. "作者：" .. info.author .. "\n"
  end
  if info.category and info.category ~= "" then
    header = header .. "分類：" .. info.category .. "\n"
  end
  if info.words then
    header = header .. "字數：" .. info.words .. "字\n"
  end
  if header ~= "" then header = header .. "\n" end
  if desc == "" and header == "" then return nil end
  desc = header .. desc
  if #desc > 4000 then desc = string.sub(desc, 1, 4000) end
  if trActive() then desc = translateOne(desc) end
  return desc
end

function getBookGenres(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return {} end
  local info = parseBookInfo(r.body)
  local out = {}
  if info.category and info.category ~= "" then
    out[#out + 1] = translateVocab(info.category)
  end
  return out
end

function getBookStatus(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local info = parseBookInfo(r.body)
  if info.status and info.status ~= "" then
    return translateVocab(info.status)
  end
  return nil
end

function getBookLastUpdate(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local info = parseBookInfo(r.body)
  if info.updated then
    local d = string.match(info.updated, "(%d%d%d%d%-%d%d%-%d%d)")
    if d then return d end
  end
  return nil
end

function getChapterListHash(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local info = parseBookInfo(r.body)
  if info.updated or info.latest then
    return tostring(info.updated or "") .. "|" .. tostring(info.latest or "")
  end
  return nil
end


-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter list — engine entry points
-- ═══════════════════════════════════════════════════════════════════════════
-- parsePage(bookUrl, page) — the engine's paginated API. Page 1 NEVER
--   returns nil (the v1.0.0 bug: engines without show_error propagation
--   surfaced the bare "parsePage returned non-table" error): worst case it
--   returns an empty table after show_error. Pages > 1 return nil on
--   failure — the engine stops the walk and keeps what it has; progress
--   persists and resumes.
-- getChapterList(bookUrl) — fallback for engines without parsePage. Same
--   three-layer core; drives the walk to completion in one call (bounded);
--   the final list is cid-sorted (cid == reading order, live-verified).

function parsePage(bookUrl, page)
  if page == 1 then
    local raw, tp = tocFetchPage1(bookUrl)
    if raw == nil or #raw == 0 then
      -- everything unreachable: guided error on builds that propagate
      -- show_error; an EMPTY TABLE (never nil!) everywhere else
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
  local p1, tp, _, mode = tocFetchPage1(bookUrl)
  if p1 == nil or #p1 == 0 then
    -- last resort: everything cached (any mode) with no site access
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

  if mode == "walk" then
    -- legacy engines: drive the virtual walk to completion (bounded; each
    -- page aborts at the first failed fetch and resumes on the next call)
    local entry = tocCacheLoad(bookUrl)
    local seedUrls = tocSeedUrls(bookUrl, entry)
    for vpage = 2, 60 do -- ≤ 60 × 40 = 2400 chapters per call
      local raw = walkEnsure(bookUrl, vpage, entry, seedUrls)
      if raw == nil then break end
      entry = tocCacheLoad(bookUrl) -- pick up the saved frontier
      local added = 0
      for _, ch in ipairs(raw) do
        if not seenUrl[ch.url] then
          chapters[#chapters + 1] = ch
          seenUrl[ch.url] = true
          added = added + 1
        end
      end
      if added == 0 then break end
    end
  else
    -- real mode: walk the site's pages, ABORT at the first failure (when
    -- the EdgeOne challenge does not clear, each failed fetch already cost
    -- a full WebView-solver ladder — walking on would launch it per page)
    tp = tp or 1
    for p = 2, tp do
      local raw, tp2 = tocFetchPageN(bookUrl, p)
      if raw == nil then break end -- ABORT at the first failed page
      if tp2 and tp2 > tp then tp = tp2 end
      for _, ch in ipairs(raw) do
        -- cross-page dedupe: a wrong page-N URL that soft-serves page 1
        -- again must not duplicate chapters
        if not seenUrl[ch.url] then
          chapters[#chapters + 1] = ch
          seenUrl[ch.url] = true
        end
      end
    end
  end

  -- cid == reading order (live-verified): the final sort fixes any seed /
  -- walk interleaving and the site's swapped-adjacent quirks
  table.sort(chapters, function(x, y)
    return (cidFromUrl(x.url) or 0) < (cidFromUrl(y.url) or 0)
  end)
  return finalizeToc(chapters)
end
