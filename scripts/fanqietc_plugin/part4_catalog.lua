
-- ═══════════════════════════════════════════════════════════════════════════
-- Catalog — rankings, recommendations, search, filters, self-test
-- ═══════════════════════════════════════════════════════════════════════════

-- The site's Discover taxonomy (components/discover/constants.js, verified
-- live 2026-09-30). Rank boards return 30 books (100 for darkhorse/reading);
-- recommend sections return 11-16 books. All are single-page.
local RANK_BOARDS = {
  { value = "recommend", en = "Recommended",     zh = "推薦榜" },
  { value = "finished",  en = "Finished",        zh = "完本榜" },
  { value = "new",       en = "New Books",       zh = "新書榜" },
  { value = "chasing",   en = "Chasing Updates", zh = "追更榜" },
  { value = "darkhorse", en = "Dark Horse",      zh = "黑馬榜" },
  { value = "peak",      en = "Peak",            zh = "巔峰榜" },
  { value = "reading",   en = "Most Read",       zh = "閱讀榜" }
}

local RECOMMEND_SECTIONS = {
  { value = "realtime", en = "Realtime Hot",   zh = "即時熱度" },
  { value = "guess",    en = "Guess You Like", zh = "猜你喜歡" }
}

-- ── Page-scoped filters ─────────────────────────────────────────────────────
-- Like the Novel543 plugin: the app's filter sheet cannot show/hide sections
-- dynamically, so getFilterList() returns ONLY the current page's filters and
-- getCatalogFiltered/getCatalogList record the page being browsed here.
--   rank      → Board picker (7 boards)
--   recommend → Section picker (realtime / guess)
--   selftest  → no filters of its own
local currentSurface = "rank"

-- Visible failure page for the direct (non-proxied) list endpoints. The
-- backend's /rank /recommend /search go through the backend's OWN upstream
-- pick — no mirror failover exists for them — and when that upstream flaps
-- they 503 for minutes. A blank catalog is indistinguishable from "no
-- results"; this makes the state explicit and tells the user what works
-- (chapter reading keeps working through the mirror pool) and what to do.
local function directFailedPage(what, code)
  local c = tostring(code or "?")
  return { items = {{
    title = "⚠ FanqieTC: " .. what .. " temporarily unavailable (HTTP " .. c ..
            ") — the site's " .. what .. " upstream is down right now. " ..
            "Pull-to-refresh to retry. Books already on your shelf and " ..
            "chapter reading (mirror pool) keep working. Live health: " ..
            "Browse → Page → ⚡ Self-Test.",
    url   = SITE .. "/",
    cover = ""
  }}, hasNext = false }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ⚡ Self-Test — turns the catalog into a live diagnostics report
-- ═══════════════════════════════════════════════════════════════════════════
-- Probes, with latency: mirror health from /status, a book-detail request, a
-- directory request, a chapter-content request, and the translation engines.
-- Runs in ANY mode — if the mode is raw the engines are still probed, so a
-- broken setup can be diagnosed without logcat. Tapping a line just opens
-- the site homepage.
local function runSelfTest()
  local items = {}
  local function line(mark, label, detail)
    local d = ""
    if detail ~= nil and detail ~= "" then d = " — " .. detail end
    items[#items + 1] = {
      title = mark .. " " .. label .. d,
      url   = SITE .. "/",
      cover = ""
    }
  end
  local function elapsed(t0)
    local n = nowMs()
    if t0 and n and n >= t0 then return tostring(math.floor(n - t0)) .. "ms" end
    return ""
  end

  -- 0. banner — proves which plugin this catalog is running
  line("⚡", "Plugin", "FanqieTC v1.0.0 — if you can see this line, you are on the RIGHT source")

  -- 1. settings
  local mode = getMode()
  local tl   = getTl()
  local mirrorSetting = getMirrorSetting()
  line("✓", "Settings", "mode=" .. mode .. ", target=" .. tl ..
       ", mirror=" .. mirrorSetting)

  -- 2. environment helpers (the things older app builds can lack)
  local clock = nowMs()
  line(clock and "✓" or "!", "os_time",
       clock and "available (milliseconds)" or
       "MISSING on this app build — caches/breaker degrade to counters")

  local j = json_parse('["a","b"]')
  local jOk = type(j) == "table" and j[1] == "a" and j[2] == "b"
  line(jOk and "✓" or "✗", "json_parse",
       jOk and "array → Lua table OK" or ("unexpected result type: " .. type(j)))

  -- 3. mirror health (live /status)
  local t0 = nowMs()
  statusCache.list = nil -- bypass the TTL cache for a fresh reading
  local healthy = fetchMirrorHealth()
  if #healthy > 0 then
    line("✓", "Mirror health", elapsed(t0) .. " → up: " .. table.concat(healthy, ", "))
  else
    line("✗", "Mirror health",
         elapsed(t0) .. " → none reported up; requests fall back to 'default'")
  end
  for _, id in ipairs(MIRRORS) do
    local up = false
    for _, h in ipairs(healthy) do if h == id then up = true end end
    line(up and "✓" or "✗", "  mirror " .. id, up and "healthy" or "down")
  end

  -- 4. API end-to-end probes (a real book → detail → directory → content)
  local PROBE_ID = "7077516958534470656" -- 凡骨 (used as a stability canary only)
  local t1 = nowMs()
  local detail = fetchBookDetail(PROBE_ID)
  if type(detail) == "table" and type(detail.book_name) == "string" then
    line("✓", "Book detail", elapsed(t1) .. " → " .. detail.book_name ..
         " · " .. tostring(detail.author or "?"))
  else
    line("✗", "Book detail", elapsed(t1) .. " failed — every mirror refused; check the mirror lines above")
  end

  local t2 = nowMs()
  local dir = (type(detail) == "table") and fetchDirectory(PROBE_ID) or nil
  if type(dir) == "table" and #dir > 0 then
    line("✓", "Directory", elapsed(t2) .. " → " .. #dir .. " chapters (first: " ..
         tostring(dir[1] and dir[1].title or "?") .. ")")
  else
    line("✗", "Directory", elapsed(t2) .. " failed")
  end

  local t3 = nowMs()
  local contentOk = false
  if type(dir) == "table" and dir[1] and type(dir[1].item_id) == "string" then
    local c = proxyAction("content", { item_id = dir[1].item_id })
    if type(c) == "table" and type(c.content) == "string" and #c.content > 50 then
      contentOk = true
      line("✓", "Chapter content", elapsed(t3) .. " → " .. #c.content .. " chars")
    end
  end
  if not contentOk then
    line("✗", "Chapter content", elapsed(t3) .. " failed")
  end

  -- 5. translation engines (probed directly, regardless of mode)
  local probe = { "玄幻", "都市" }

  local t4 = nowMs()
  local r1 = trRequestGoogle(probe, "zh-CN", tl)
  line(r1 and "✓" or "✗", "Google batch (POST/GET, 2 hosts)",
       r1 and ((elapsed(t4) .. " → ") .. table.concat(r1, " / ")) or
       (elapsed(t4) .. " unreachable"))

  local t5 = nowMs()
  local r2 = trChunkMyMemory(probe, tl)
  local mmOk = r2 ~= nil and r2[1] ~= probe[1]
  line(mmOk and "✓" or "✗", "MyMemory fallback",
       mmOk and (elapsed(t5) .. " → " .. table.concat(r2, " / ")) or
       (elapsed(t5) .. " unreachable"))

  local t6 = nowMs()
  local r3 = trGtxSingle("玄幻", tl)
  line(r3 and "✓" or "✗", "Google gtx single",
       r3 and (elapsed(t6) .. " → " .. r3) or
       (elapsed(t6) .. " unreachable (fine when the batch engine works)"))

  -- 6. end-to-end through the real pipeline (mode + breaker respected)
  if mode == "translate" then
    local e2e = translateBatch({ "凡骨" })
    local e2eOk = e2e ~= nil and e2e[1] ~= nil and e2e[1] ~= "凡骨"
    line(e2eOk and "✓" or "!", "End-to-end batch",
         e2eOk and ("「凡骨」 → " .. e2e[1]) or
         "returned the original text — see the failing step above")
  end

  -- 7. verdict
  if type(detail) ~= "table" then
    line("→", "Verdict", "API unreachable — all mirrors down AND 'default' failed. Wait for the mirrors to recover (check https://fanqietc.com/status in a browser) or pick a specific mirror in this source's Settings")
  elseif mode ~= "translate" then
    line("→", "Verdict", "site OK — switch Mode to Translator in this source's settings to translate, then pull-to-refresh the catalog")
  elseif r1 or mmOk or r3 then
    line("→", "Verdict", "site + translator OK — if titles still show Chinese: pull-to-refresh the catalog (already-loaded pages are not retranslated)")
  else
    line("→", "Verdict", "site OK but ALL translator engines unreachable — your network/region is blocking Google & MyMemory (VPN, DNS filter, firewall). Try another network or disable the VPN")
  end

  return { items = items, hasNext = false }
end

-- ── Default catalog (no filters) → the Recommended rank board ───────────────
function getCatalogList(index)
  currentSurface = "rank"
  if index > 0 then return { items = {}, hasNext = false } end
  local d, code = apiGetDirect("/rank?board=recommend")
  if type(d) ~= "table" then return directFailedPage("rankings", code) end
  return booksToPagedList(d.books)
end

-- ── Search ───────────────────────────────────────────────────────────────────
-- The backend returns the full result set (~50 books) in one response — no
-- pagination. In Translator mode a non-Chinese query is translated to zh-CN
-- first (the catalog indexes Simplified titles); the original query is also
-- tried when the translated one finds nothing.
function getCatalogSearch(index, query)
  if index > 0 then return { items = {}, hasNext = false } end
  if type(query) ~= "string" or query == "" then
    return { items = {}, hasNext = false }
  end

  local q = query
  if trActive() and not hasCJK(query) then
    local zh = translateQueryToZh(query, "zh-CN")
    if zh then q = zh end
  end

  local d, code = apiGetDirect("/search?query=" .. url_encode(q))
  if type(d) ~= "table" then return directFailedPage("search", code) end
  local res = booksToPagedList(d.books)

  -- translated query found nothing → retry the raw query (pinyin/English
  -- titles, author names and book ids still match server-side)
  if q ~= query and #res.items == 0 then
    d, code = apiGetDirect("/search?query=" .. url_encode(query))
    if type(d) ~= "table" then return directFailedPage("search", code) end
    res = booksToPagedList(d.books)
  end

  return res
end

-- ── Filtered browse ──────────────────────────────────────────────────────────
function getCatalogFiltered(index, filters)
  filters = filters or {}
  local browse = filters["browse"] or "rank"
  if browse ~= "rank" and browse ~= "recommend" and browse ~= "selftest" then
    browse = "rank"
  end
  currentSurface = browse

  if index > 0 then return { items = {}, hasNext = false } end

  -- ── Translator/API self-test (diagnostics as catalog items) ───────────
  if browse == "selftest" then
    local ok, res = pcall(runSelfTest)
    if ok and type(res) == "table" then return res end
    return { items = {{
      title = "Self-test failed: " .. tostring(res),
      url   = SITE .. "/", cover = ""
    }}, hasNext = false }
  end

  if browse == "rank" then
    local board = filters["board"] or "recommend"
    local valid = false
    for _, b in ipairs(RANK_BOARDS) do
      if b.value == board then valid = true; break end
    end
    if not valid then board = "recommend" end
    local d, code = apiGetDirect("/rank?board=" .. url_encode(board))
    if type(d) ~= "table" then return directFailedPage("rankings", code) end
    return booksToPagedList(d.books)
  end

  -- browse == "recommend"
  local section = filters["section"] or "realtime"
  if section ~= "realtime" and section ~= "guess" then section = "realtime" end
  local d, code = apiGetDirect("/recommend?section=" .. url_encode(section))
  if type(d) ~= "table" then return directFailedPage("recommendations", code) end
  return booksToPagedList(d.books)
end

-- ── Filter list (page-scoped) ────────────────────────────────────────────────
function getFilterList()
  local surface = currentSurface
  if surface ~= "rank" and surface ~= "recommend" and surface ~= "selftest" then
    surface = "rank"
  end

  local function opt(en, zh, value)
    return { value = value, label = flLabel(en, zh) }
  end

  local filters = {
    {
      type = "select", key = "browse",
      label = flLabel("Page", "頁面"),
      defaultValue = surface, -- follows the page being browsed
      options = {
        { value = "rank",      label = flLabel("Rankings", "榜單") },
        { value = "recommend", label = flLabel("Recommendations", "推薦") },
        { value = "selftest",  label = flLabel("⚡ Self-Test", "診斷") }
      }
    }
  }

  if surface == "rank" then
    local boardOptions = {}
    for _, b in ipairs(RANK_BOARDS) do
      boardOptions[#boardOptions + 1] = { value = b.value, label = flLabel(b.en, b.zh) }
    end
    filters[#filters + 1] = {
      type = "select", key = "board",
      label = flLabel("Board", "榜單"),
      defaultValue = "recommend",
      options = boardOptions
    }

  elseif surface == "recommend" then
    local sectionOptions = {}
    for _, s in ipairs(RECOMMEND_SECTIONS) do
      sectionOptions[#sectionOptions + 1] = { value = s.value, label = flLabel(s.en, s.zh) }
    end
    filters[#filters + 1] = {
      type = "select", key = "section",
      label = flLabel("Section", "分區"),
      defaultValue = "realtime",
      options = sectionOptions
    }
  end

  -- surface == "selftest": the Page picker alone — the diagnostics page has
  -- no filters of its own.
  return filters
end
