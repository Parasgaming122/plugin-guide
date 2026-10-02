-- ═══════════════════════════════════════════════════════════════════════════
-- OOP 小說網 (oop.tw) source plugin for NoveLA
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
--
-- Site: https://www.oop.tw/ — 短篇小說 (branded "OOPr18 工口短篇" for its
-- R18 wing; the main site hosts everything from 1k-word short stories to
-- 28000-page-long web novels). UTF-8, Traditional Chinese, behind an
-- aggressive Cloudflare "managed challenge" (verified from datacenter IPs:
-- every path 403s with cf-mitigated: challenge).
--
-- CLOUDFLARE NOTE — this site is why NoveLA's CF bypass must stay ENABLED:
--   do NOT add `cf_options = { whitelist = true }`. The engine's
--   CloudfareVerificationInterceptor auto-solves the challenge via the
--   integrated WebView on real devices; whitelisting would disable that.
--   Posters: image URLs (.jpg) are EXEMPT from the bypass (engine's
--   STATIC_EXTENSIONS), so covers go through the wsrv.nl proxy by default
--   (the established poster fix).
--
-- WHAT'S IN v1.0.0:
--   • Browse: 书库 /sort/{page}/ (all books, 10/page) with a 15-category
--     picker → /sort/{cat}/{page}/ (玄幻魔法 1 … 男频都市 14 + all).
--     hasNext from the pager's >> (next) link.
--   • Search: GET /search/?searchkey={q}&searchtype=all — up to 100
--     results on ONE page (verified live: "重生" → 100 条结果, no pager).
--     Same card markup as /sort/ (.result-item).
--   • Book pages /abooka/a{id}a/: title h1.novel-title, cover .novel-cover
--     img, meta-tags (category / word count / 全本|连载 status / rating),
--     关键字 tags as genres, latest-chapter .update-time as last update.
--   • Chapter catalogs are PAGINATED 30/page via ?p=N (the .chap-pager
--     select options enumerate every page — getChapterList walks them all).
--   • Chapter text from article#article <p> paragraphs only (the site
--     interleaves ad DIVs inside the article — selecting just the <p>
--     elements skips them all). Chapter 1 of TXT-imported books is often
--     just the TXT header (書名 / 作者: / 簡介:) — stripped when real
--     content follows, KEPT when it is the chapter's only content (an
--     empty chapter would show as a reader error).
--   • Translator mode (the battle-tested novel543 engine): Google free
--     dict endpoint + MyMemory + gtx fallbacks, translation cache,
--     circuit breaker, pass-through on any error. Search queries typed in
--     a non-Chinese language are translated to Traditional Chinese first
--     (the site indexes zh-TW titles).
--   • Chrome Mobile UA preset.
--
-- Site facts (live-verified 2026-09-19 via the Google-Translate proxy —
-- direct datacenter access is CF-challenged):
--   • Browse:         /sort/ (page 1), /sort/{N}/ (all books, page N),
--                     /sort/{cat}/{N}/ — 10 books/page; "all" has 28,192
--                     pages. Pagination: .pagination with <strong>N</strong>
--                     current page, page links, >> next, last-page link.
--   • Categories:     1 玄幻魔法 2 武俠 3 都市言情 4 曆史軍事 5 科幻
--                     6 遊戲競技 7 女生耽美 8 修仙仙俠 9 其他類型
--                     10 短篇 11 懸疑推理 12 肉文小說 13 古代言情
--                     14 男頻都市 (12 = R18 novels)
--   • Cards:          .book-card / .result-item → .book-cover a + img,
--                     .book-status ("男頻/ 連載" / "短篇/ 全本"),
--                     .book-title a, .book-intro, .book-author,
--                     .book-stats (.stat-item.words "246萬字", .update)
--   • Search:         GET /search/?searchkey=…&searchtype=all →
--                     .search-section .search-count "N 條結果",
--                     .search-results .result-item (≤100, one page)
--   • Book page:      .novel-cover img, h1.novel-title, .novel-meta
--                     .meta-tag (category, 萬字, 全本/連載, 4.3分),
--                     2nd .novel-meta (關鍵字 tags = genres),
--                     .latest-chapter .update-time (YYYY-MM-DD),
--                     #catalog-content .chap-pager select option (?p=N),
--                     ul#ul_all_chapters li.chapter-item a
--   • Chapters:       /areada/a{book}a/a{chap}a.html →
--                     .chapter-header h1 ("001"), article#article <p>,
--                     .reading-nav #prev_url/#info_url/#next_url
--   • Author pages:   /author/{urlencoded name}/ (not used by the plugin)
--   • R18 sister:    https://www.oopr18.tw/ (separate site — not included)
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Metadata ────────────────────────────────────────────────────────────────
local VERSION = "1.1.0"
id       = "oop"
name     = "OOP 小說網"
version  = "1.1.0"  -- literal: the extension manager's regex only parses quoted values
baseUrl  = "https://www.oop.tw/"
language = "zh"
icon     = "https://www.oop.tw/favicon.ico"

-- ── Constants ────────────────────────────────────────────────────────────────
local SITE = "https://www.oop.tw"

-- Settings preference keys
local PREF_MODE   = "oop_mode"     -- raw | translate
local PREF_TLANG  = "oop_tlang"    -- target language code, default "en"
local PREF_TR_CH  = "oop_tr_chapters" -- "1" | "0" (translate chapter titles)
local PREF_COVERS = "oop_covers"   -- proxy (default) | direct

-- ── Site taxonomy (live-verified 2026-09-19) ────────────────────────────────
local CATEGORIES = {
  { value = "1",  en = "Fantasy & Magic",   zh = "玄幻魔法" },
  { value = "2",  en = "Wuxia",             zh = "武俠" },
  { value = "3",  en = "Urban Romance",     zh = "都市言情" },
  { value = "4",  en = "History & Military", zh = "曆史軍事" },
  { value = "5",  en = "Sci-Fi",            zh = "科幻" },
  { value = "6",  en = "Gaming & Sports",   zh = "遊戲競技" },
  { value = "7",  en = "Girls & Danmei",    zh = "女生耽美" },
  { value = "8",  en = "Cultivation",       zh = "修仙仙俠" },
  { value = "9",  en = "Other",             zh = "其他類型" },
  { value = "10", en = "Short Stories",     zh = "短篇" },
  { value = "11", en = "Mystery",           zh = "懸疑推理" },
  { value = "12", en = "R18 Novels (18+)",  zh = "肉文小說" },
  { value = "13", en = "Ancient Romance",   zh = "古代言情" },
  { value = "14", en = "Male Urban",        zh = "男頻都市" }
}

-- Static English lookups for fixed site vocabulary (English target only).
local STATIC_EN = {
  ["玄幻魔法"] = "Fantasy & Magic", ["武俠"] = "Wuxia",
  ["都市言情"] = "Urban Romance",   ["曆史軍事"] = "History & Military",
  ["历史军事"] = "History & Military", ["科幻"] = "Sci-Fi",
  ["遊戲競技"] = "Gaming & Sports", ["游戏竞技"] = "Gaming & Sports",
  ["女生耽美"] = "Girls & Danmei",  ["修仙仙俠"] = "Cultivation",
  ["其他類型"] = "Other",           ["短篇"] = "Short Stories",
  ["懸疑推理"] = "Mystery",         ["肉文小說"] = "R18 Novels",
  ["古代言情"] = "Ancient Romance", ["男頻都市"] = "Male Urban",
  ["全本"] = "Completed",           ["連載"] = "Ongoing",
  ["连载"] = "Ongoing",             ["男頻"] = "Male-oriented",
  ["男频"] = "Male-oriented"
}

-- ── Generic helpers ──────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

local function hasCJK(s)
  return type(s) == "string" and string.find(s, "[\228-\233]") ~= nil
end

-- ── Cover image proxy ────────────────────────────────────────────────────────
local COVER_PROXY = "https://wsrv.nl/?url="

local function coversViaProxy()
  return get_preference(PREF_COVERS) ~= "direct"
end

local function coverUrl(u)
  if not u or u == "" then return u end
  if not coversViaProxy() then return u end
  if not string_starts_with(u, "http") then return u end
  -- nocover placeholder → direct (no point proxying a static asset)
  if string.find(u, "nocover") then return u end
  return COVER_PROXY .. url_encode(u) .. "&w=450&we&output=jpg&q=80"
end

-- ── Clock (NoveLA's os_time returns MILLISECONDS) ───────────────────────────
local function nowMs()
  local ok, v = pcall(os_time)
  if ok and type(v) == "number" and v > 0 then
    if v < 100000000000 then v = v * 1000 end
    return v
  end
  return nil
end

-- ── HTTP ─────────────────────────────────────────────────────────────────────
-- The site is UTF-8 and sits behind Cloudflare. NoveLA's http_get does NOT
-- follow redirects; oop.tw serves pages directly (200) so no manual redirect
-- following is needed. CF challenges are handled by the ENGINE's interceptor
-- (WebView bypass) — the plugin just makes normal requests.

local function httpGetPage(path)
  return http_get(SITE .. path, {
    headers = {
      ["Referer"] = SITE .. "/",
      ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    }
  })
end

-- ── Short-lived page cache ───────────────────────────────────────────────────
-- Opening a book triggers getBookTitle / Cover / Description / Genres /
-- Status / LastUpdate / ChapterListHash separately — the cache collapses
-- them into one fetch. 60s TTL, 12 pages. Chapter text NEVER cached.
local pageCache, pageCacheOrder = {}, {}
local PAGE_TTL_MS    = 60000
local PAGE_CACHE_MAX = 12

local function fetchPageCached(bookUrl)
  local path = string.match(bookUrl, "^https?://[^/]+(/.*)$") or bookUrl
  local now = nowMs()
  if not now then return httpGetPage(path) end
  local e = pageCache[path]
  if e and (now - e.t) < PAGE_TTL_MS then return e.r end
  local r = httpGetPage(path)
  if r and r.success then
    if pageCache[path] == nil then
      pageCacheOrder[#pageCacheOrder + 1] = path
      if #pageCacheOrder > PAGE_CACHE_MAX then
        pageCache[table.remove(pageCacheOrder, 1)] = nil
      end
    end
    pageCache[path] = { r = r, t = now }
  end
  return r
end


-- ═══════════════════════════════════════════════════════════════════════════
-- Translator core (copied from novel543.lua v1.0.5 — battle-tested)
-- Source language: zh-TW (oop.tw indexes Traditional Chinese).
-- ═══════════════════════════════════════════════════════════════════════════
-- Engine: Google's free dict endpoint (client=dict-chrome-ex) — POST with
-- repeated q params returns one translation per q. With sl=auto the shape
-- nests the detected source: [["t1","zh-CN"]] — both shapes are parsed.
-- No API key, no OAuth. Request chain, each step only on failure:
--   1. POST translate.googleapis.com/translate_a/t
--   2. POST clients5.google.com/translate_a/t
--   3. GET  translate.googleapis.com/translate_a/t (q in the URL)
--   4. GET  clients5.google.com/translate_a/t
--   5. MyMemory (api.mymemory.translated.net, anonymous)
--   6. Google gtx single — per item, first 6 of a failed chunk
-- EVERY failure path returns the original text, and every public entry point
-- is pcall-armored — browsing must never break because of the translator.

local TR_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
local TR_HOSTS = {
  "https://translate.googleapis.com",
  "https://clients5.google.com"
}
local TR_FAIL_LIMIT     = 3       -- consecutive failed batches before pass-through
local TR_RETRY_AFTER_MS = 600000  -- breaker half-opens after 10 minutes

local trCache      = {}       -- original → translated (session-lifetime)
local trCacheCount = 0
local trFailStreak = 0
local trDisabledAt = 0
local trProbeCount = 0        -- breaker tick when no clock is available

local function getMode()
  local ok, v = pcall(get_preference, PREF_MODE)
  if ok and v == "translate" then return "translate" end
  return "raw"
end

local function getTl()
  local ok, v = pcall(get_preference, PREF_TLANG)
  if ok and type(v) == "string" and v ~= "" then return v end
  return "en"
end

local function trChaptersEnabled()
  local ok, v = pcall(get_preference, PREF_TR_CH)
  if ok and v == "0" then return false end
  return true -- default on
end

-- Filter label builder:
--   raw mode       → "English (中文)"
--   translate mode → "English"
local function flLabel(en, zh)
  if getMode() == "translate" then return en end
  if zh and zh ~= "" and hasCJK(zh) then return en .. " (" .. zh .. ")" end
  return en
end

local function trActive()
  if getMode() ~= "translate" then return false end
  if trFailStreak < TR_FAIL_LIMIT then return true end
  local now = nowMs()
  if now then
    return (now - trDisabledAt) >= TR_RETRY_AFTER_MS -- half-open after 10 min
  end
  return (trProbeCount % 16) == 0 -- no clock: probe once every 16 batches
end

local function trCachePut(k, v)
  if trCacheCount > 4000 then return end -- hard cap
  if trCache[k] == nil then trCacheCount = trCacheCount + 1 end
  trCache[k] = v
end

-- Parse the /t endpoint response. Accepted shapes (Lua 1-based):
--   {"t1","t2"}                 (explicit sl)
--   {{"t1","src"},{"t2","src"}} (sl=auto)
-- Returns an array of exactly `want` strings, or nil when malformed.
local function parseTrArray(j, want)
  if type(j) ~= "table" then return nil end
  local out = {}
  for i = 1, want do
    local e = j[i]
    local t = nil
    if type(e) == "string" then
      t = e
    elseif type(e) == "table" then
      if type(e[1]) == "string" then t = e[1]
      elseif type(e[1]) == "table" and type(e[1][1]) == "string" then t = e[1][1] end
    end
    if t == nil then return nil end
    out[i] = t
  end
  return out
end

-- GET variant with q params in the URL, split to keep URLs under ~1400 chars.
local function trGetChunk(host, texts, sl, tl)
  local out = {}
  local i = 1
  while i <= #texts do
    local group, encLen = {}, 0
    while i <= #texts do
      local enc = "q=" .. url_encode(texts[i])
      if encLen + #enc + 1 > 1400 and #group > 0 then break end
      group[#group + 1] = texts[i]
      encLen = encLen + #enc + 1
      i = i + 1
    end
    local qs = {}
    for _, t in ipairs(group) do qs[#qs + 1] = "q=" .. url_encode(t) end
    local url = host .. "/translate_a/t?client=dict-chrome-ex&sl=" .. sl
      .. "&tl=" .. url_encode(tl) .. "&" .. table.concat(qs, "&")
    local r = http_get(url, { headers = { ["User-Agent"] = TR_UA } })
    if not (r and r.success and type(r.body) == "string"
            and string.sub(r.body, 1, 1) == "[") then return nil end
    local res = parseTrArray(json_parse(r.body), #group)
    if not res then return nil end
    for k = 1, #group do
      local v = res[k]
      if v == nil or v == "" then v = group[k] end
      out[#out + 1] = v
    end
  end
  return out
end

-- Steps 1-4: Google dict endpoint, POST then GET, on both hosts.
local function trRequestGoogle(texts, sl, tl)
  local qs = {}
  for _, t in ipairs(texts) do qs[#qs + 1] = "q=" .. url_encode(t) end
  local qstr = table.concat(qs, "&")
  for _, host in ipairs(TR_HOSTS) do
    local url = host .. "/translate_a/t?client=dict-chrome-ex&sl=" .. sl .. "&tl=" .. url_encode(tl)
    local r = http_post(url, qstr, {
      headers = {
        ["Content-Type"] = "application/x-www-form-urlencoded",
        ["User-Agent"]   = TR_UA
      }
    })
    if r and r.success and type(r.body) == "string"
       and string.sub(r.body, 1, 1) == "[" then
      local res = parseTrArray(json_parse(r.body), #texts)
      if res then return res end
    end
    local res = trGetChunk(host, texts, sl, tl)
    if res then return res end
  end
  return nil
end

-- Step 6: classic gtx single endpoint — one text per request.
local function trGtxSingle(text, tl)
  local url = "https://translate.googleapis.com/translate_a/single"
    .. "?client=gtx&sl=auto&tl=" .. url_encode(tl)
    .. "&dt=t&q=" .. url_encode(text)
  local r = http_get(url, { headers = { ["User-Agent"] = TR_UA } })
  if r and r.success and type(r.body) == "string"
     and string.sub(r.body, 1, 1) == "[" then
    local j = json_parse(r.body)
    if type(j) == "table" and type(j[1]) == "table" and type(j[1][1]) == "table"
       and type(j[1][1][1]) == "string" then
      return j[1][1][1]
    end
  end
  return nil
end

-- MyMemory fallback — per-item GET, short texts only.
local function trChunkMyMemory(texts, tl)
  local out = {}
  local any = false
  for i, t in ipairs(texts) do
    out[i] = t
    if #t <= 300 then
      local url = "https://api.mymemory.translated.net/get?q=" .. url_encode(t)
                   .. "&langpair=zh|" .. url_encode(tl)
      local r = http_get(url, { headers = { ["User-Agent"] = TR_UA } })
      if r and r.success and type(r.body) == "string"
         and string.sub(r.body, 1, 1) == "{" then
        local j = json_parse(r.body)
        if type(j) == "table" and type(j.responseData) == "table"
           and type(j.responseData.translatedText) == "string" then
          local tr = j.responseData.translatedText
          if tr ~= "" and tr ~= t and string.find(tr, "MYMEMORY WARNING") == nil then
            out[i] = tr
            any = true
          end
        end
      end
    end
  end
  if not any then return nil end
  return out
end

-- Translate an array of strings; ALWAYS returns an array of the same length.
local function translateBatchImpl(texts)
  local n = #texts
  if n == 0 then return texts end
  if not trActive() then
    trProbeCount = trProbeCount + 1
    return texts
  end

  -- cache pass
  local out, pending, pIdx = {}, {}, {}
  for i = 1, n do
    local c = trCache[texts[i]]
    if c ~= nil then out[i] = c
    else pending[#pending + 1] = texts[i]; pIdx[#pIdx + 1] = i end
  end
  if #pending == 0 then return out end

  -- chunked requests: ≤40 items and ≤3000 chars per chunk
  local CHUNK_MAX = 40
  local s = 1
  while s <= #pending do
    local chunk, chars = {}, 0
    while s + #chunk <= #pending and #chunk < CHUNK_MAX do
      local t = pending[s + #chunk]
      if chars + #t > 3000 and #chunk > 0 then break end
      chunk[#chunk + 1] = t
      chars = chars + #t
    end
    local base = s
    s = s + #chunk

    local tl = getTl()
    local res = trRequestGoogle(chunk, "zh-TW", tl)
    local usedFallback = false
    if not res then
      res = trChunkMyMemory(chunk, tl)
      usedFallback = true
    end
    if res and #res == #chunk then
      if not usedFallback then trFailStreak = 0 end
      for k = 1, #chunk do
        local v = res[k]
        if v == nil or v == "" then v = chunk[k] end
        out[pIdx[base + k - 1]] = v
        trCachePut(chunk[k], v)
      end
    else
      local anyOk = false
      local cap = #chunk
      if cap > 6 then cap = 6 end
      for k = 1, cap do
        local v = nil
        if #chunk[k] <= 400 then v = trGtxSingle(chunk[k], tl) end
        if v and v ~= "" then
          out[pIdx[base + k - 1]] = v
          trCachePut(chunk[k], v)
          anyOk = true
        else
          out[pIdx[base + k - 1]] = chunk[k]
        end
      end
      for k = cap + 1, #chunk do
        out[pIdx[base + k - 1]] = chunk[k]
      end
      if not anyOk then
        trFailStreak = trFailStreak + 1
        if trFailStreak >= TR_FAIL_LIMIT then
          trDisabledAt = nowMs() or 0
          log_info("oop: translator disabled for 10 min (3 failed batches)")
        end
      end
    end
  end
  return out
end

local function translateBatch(texts)
  if type(texts) ~= "table" then return texts end
  local ok, res = pcall(translateBatchImpl, texts)
  if ok and type(res) == "table" and #res == #texts then return res end
  if not ok then log_info("oop: translator error: " .. tostring(res)) end
  return texts
end

-- Translate a single string (cached; original on failure).
local function translateOne(text)
  if type(text) ~= "string" or text == "" or not trActive() then return text end
  local c = trCache[text]
  if c ~= nil then return c end
  local r = translateBatch({ text })
  return r[1] or text
end

-- Fixed site vocabulary: free for English, API (cached) for other languages.
local function translateVocab(text)
  if type(text) ~= "string" or text == "" then return text end
  if not trActive() then return text end
  if getTl() == "en" and STATIC_EN[text] then return STATIC_EN[text] end
  return translateOne(text)
end

-- Reverse direction for search: user-language query → Traditional Chinese
-- (oop.tw indexes zh-TW titles — queries must be Chinese to match).
local function translateQueryToZhTw(query, srcLang)
  if not trActive() then return nil end
  local ok, res = pcall(trRequestGoogle, { query }, srcLang or "auto", "zh-TW")
  if ok and type(res) == "table" and res[1] and res[1] ~= query then return res[1] end
  return nil
end


-- ═══════════════════════════════════════════════════════════════════════════
-- List-page parsing + catalog browse
-- ═══════════════════════════════════════════════════════════════════════════
-- /sort/ and /search/ share the card markup:
--   .book-card / .result-item
--     .book-cover a            → book URL + img (src / data-original)
--     .book-status             → "男頻/ 連載" / "短篇/ 全本"
--     .book-info .book-title a → title (search adds .highlight spans — text
--                                concatenation handles them)
--     .book-intro              → description snippet
--     .book-meta .book-author  → author
--     .book-stats              → word count / update time
-- Pagination (.pagination): <strong>N</strong> = current page; the >> link is
-- NEXT (href=/sort/{N+1}/); a javascript:void(0) >> means no next page.

local function parseListCards(body)
  local items = {}
  if not body then return items end
  local cards = html_select(body, ".books-grid .book-card")
  if #cards == 0 then cards = html_select(body, ".search-results .result-item") end
  for _, card in ipairs(cards) do
    local href = html_attr(card.html, ".book-cover a", "href")
    local img  = html_attr(card.html, ".book-cover img", "src")
    local dimg = html_attr(card.html, ".book-cover img", "data-original")
    if dimg and dimg ~= "" then img = dimg end -- lazy-load attribute
    local titleEl = html_select_first(card.html, ".book-title a")
    if titleEl and href and href ~= "" then
      items[#items + 1] = {
        title = string_clean(titleEl.text),
        url   = absUrl(href),
        cover = coverUrl(absUrl(img))
      }
    end
  end
  return items
end

-- hasNext from the pager's >> link (href ≠ javascript:).
local function listHasNext(body)
  if not body then return false end
  for _, a in ipairs(html_select(body, ".pagination a")) do
    local t = a.text or ""
    if string.find(t, ">>") or string.find(t, "&gt;&gt;") then
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

-- ── Catalog ──────────────────────────────────────────────────────────────────
-- Default surface: the full 书库 (all books, newest-updated first):
--   index 0 → /sort/            (page 1)
--   index N → /sort/{N+1}/      (pages are 1-based in the URL)
-- Filtered: /sort/{cat}/{page}/ — same 1-based paging.

function getCatalogList(index)
  local path = "/sort/"
  if index > 0 then path = "/sort/" .. tostring(index + 1) .. "/" end
  local r = httpGetPage(path)
  if not (r and r.success) then
    if type(show_error) == "function" then
      show_error("oop.tw unreachable",
        "Could not load the library from www.oop.tw. The site sits behind " ..
        "Cloudflare — if a challenge appears, solve it once in the WebView " ..
        "and retry.")
    end
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
    path = "/sort/" .. cat .. "/" .. tostring(index + 1) .. "/"
  else
    path = "/sort/"
    if index > 0 then path = "/sort/" .. tostring(index + 1) .. "/" end
  end
  local r = httpGetPage(path)
  if not (r and r.success) then
    if type(show_error) == "function" then
      show_error("oop.tw unreachable",
        "Could not load the category from www.oop.tw. The site sits behind " ..
        "Cloudflare — if a challenge appears, solve it once in the WebView " ..
        "and retry.")
    end
    return { items = {}, hasNext = false }
  end
  local items = parseListCards(r.body)
  translateCatalogItems(items)
  return { items = items, hasNext = listHasNext(r.body) }
end

function getFilterList()
  local catOptions = { { value = "all", label = flLabel("All Books", "全部小說") } }
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
-- Search — GET /search/?searchkey={q}&searchtype=all (one page, ≤100 results)
-- ═══════════════════════════════════════════════════════════════════════════

function getCatalogSearch(index, query)
  if type(query) ~= "string" or query == "" or index > 0 then
    return { items = {}, hasNext = false }
  end

  local q = query
  if not hasCJK(q) then
    local tq = translateQueryToZhTw(q, "auto")
    if tq then q = tq end
  end

  local r = http_get(SITE .. "/search/?searchkey=" .. url_encode(q) .. "&searchtype=all", {
    headers = {
      ["Referer"] = SITE .. "/",
      ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    }
  })
  if not (r and r.success) then
    if type(show_error) == "function" then
      show_error("Search unreachable",
        "The search could not run on www.oop.tw. The site sits behind " ..
        "Cloudflare — if a challenge appears, solve it once in the WebView " ..
        "and retry.")
    end
    return { items = {}, hasNext = false }
  end

  local items = parseListCards(r.body)
  translateCatalogItems(items)
  -- No pager on search pages (≤100 results, single page — verified live).
  return { items = items, hasNext = false }
end

-- ═══════════════════════════════════════════════════════════════════════════
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
--   "1|<totalPages>|<page><title><url>… 9<page>…"
-- (9 group sep = page,  record sep = chapter,  unit sep = field)
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
      recs[#recs + 1] = ch.title .. "\031" .. ch.url
    end
    blocks[#blocks + 1] = tostring(p) .. "\031" .. table.concat(recs, "\030")
  end
  local data = table.concat(blocks, "\029")
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
    "challenge or network issue).\n\nIf the Cloudflare solver keeps " ..
    "reappearing: let it finish once, or open www.oop.tw once in a browser " ..
    "on this device, then retry here. Progress is remembered — each retry " ..
    "resumes where the last one stopped.")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Book details
-- ═══════════════════════════════════════════════════════════════════════════
-- Book page /abooka/a{id}a/:
--   .novel-main .novel-cover img      → cover
--   h1.novel-title                    → title
--   .novel-info .novel-meta (1st)     → .meta-tag: category, word count,
--                                       全本/連載 status (tag.full), rating
--   .novel-info .novel-meta (2nd)     → 關鍵字 tags → genres
--   .latest-chapter .update-time      → last update (YYYY-MM-DD)
--   #info-content .intro p            → description
--   #catalog-content .chap-pager select option → catalog pages (?p=N)
--   #ul_all_chapters li.chapter-item a → chapters (30/page)

local function parseBookMeta(body)
  local out = {}
  local metas = html_select(body, ".novel-info .novel-meta")
  local first = metas[1]
  if first then
    for _, tag in ipairs(html_select(first.html, ".meta-tag")) do
      local t = string_clean(tag.text or "")
      if t ~= "" then out.metaTags = out.metaTags or {}; out.metaTags[#out.metaTags + 1] = t end
      if t == "全本" or t == "完結" then out.status = "全本" end
      if t == "連載" or t == "连载" then out.status = "連載" end
      local rating = string.match(t, "(%d+%.%d)分")
      if rating then out.rating = rating end
    end
  end
  local second = metas[2]
  if second then
    out.genres = {}
    for _, tag in ipairs(html_select(second.html, ".meta-tag")) do
      local t = string_clean(tag.text or "")
      if t ~= "" then out.genres[#out.genres + 1] = t end
    end
  end
  return out
end

function getBookTitle(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local el = html_select_first(r.body, "h1.novel-title")
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
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local src = html_attr(r.body, ".novel-cover img", "src")
  if not src or src == "" then
    src = html_attr(r.body, ".novel-cover img", "data-original")
  end
  if not src or src == "" then return nil end
  return coverUrl(absUrl(src))
end

function getBookDescription(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local el = html_select_first(r.body, ".intro")
  local desc = el and string_clean(el.text) or ""
  local meta = parseBookMeta(r.body)
  local header = ""
  if meta.genres and #meta.genres > 0 then
    header = "关键字：" .. table.concat(meta.genres, " / ") .. "\n\n"
  end
  if desc == "" and header == "" then return nil end
  desc = header .. desc
  if #desc > 4000 then desc = string.sub(desc, 1, 4000) end
  if trActive() then desc = translateOne(desc) end
  return desc
end

function getBookGenres(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return {} end
  local meta = parseBookMeta(r.body)
  local out = {}
  for _, g in ipairs(meta.genres or {}) do
    out[#out + 1] = translateVocab(g)
  end
  -- fall back to the category meta-tag when no keywords exist
  if #out == 0 and meta.metaTags and meta.metaTags[1] then
    out[1] = translateVocab(meta.metaTags[1])
  end
  return out
end

function getBookStatus(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local meta = parseBookMeta(r.body)
  if meta.status then return translateVocab(meta.status) end
  return nil
end

function getBookLastUpdate(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local el = html_select_first(r.body, ".latest-chapter .update-time")
  if el then
    local d = string.match(el.text or "", "(%d%d%d%d%-%d%d%-%d%d)")
    if d then return d end
  end
  return nil
end

function getChapterListHash(bookUrl)
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
end

-- ═══════════════════════════════════════════════════════════════════════════
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


-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter text
-- ═══════════════════════════════════════════════════════════════════════════
-- Content lives in article#article. The site interleaves ad DIVs
-- (.mid-content-ad, #oneadMIRDFPTag00 …) INSIDE the article — selecting only
-- the <p> children skips every one of them.
--
-- Chapter 1 of TXT-imported books is often just the TXT header:
--     [書名（…）] [作者: …] [簡介: …]
-- The header is stripped ONLY when real content follows (a 第X章-style
-- heading, or ≥200 chars of remaining text) — otherwise it IS the chapter
-- (an empty chapter would surface as a reader content error).

local function isChapterHeading(p)
  return string.match(p, "^第[%d一二三四五六七八九十百千零两]+%s*[章节回卷部]") ~= nil
    or string.match(p, "^[Cc]hapter%s+%d+") ~= nil
end

local function stripTxtHeader(paras)
  local n = #paras
  if n == 0 then return paras end

  -- Structural TXT header: [short title-ish line][作者: …][簡介: …]
  -- When paragraph 2 starts with 作者 and paragraph 3 with 簡介/简介, the
  -- header is paragraphs 1..3 (+ any trailing empties).
  if n >= 3 then
    local p2 = paras[2]
    if p2 and (string.match(p2, "^作者[:：]") or string.match(p2, "^作者:")) then
      local stop = 3
      local p3 = paras[3]
      if p3 and (string.match(p3, "^簡介") or string.match(p3, "^简介") or p3 == "") then
        stop = 3
      elseif p3 and string.match(p2, "^作者") then
        stop = 2
      end
      local out = {}
      for k = stop + 1, n do out[#out + 1] = paras[k] end
      -- keep the header when stripping would leave nothing meaningful
      local kept = table.concat(out, "")
      if #string.gsub(kept, "%s", "") >= 200 then
        return out
      end
      return paras
    end
  end

  -- 第X章 heading deeper in the stream marks the true content start.
  local limit = n
  if limit > 30 then limit = 30 end
  for i = 4, limit do
    if paras[i] ~= "" and isChapterHeading(paras[i]) then
      local out = {}
      for k = i, n do out[#out + 1] = paras[k] end
      local kept = table.concat(out, "")
      if #string.gsub(kept, "%s", "") >= 200 then
        return out
      end
      return paras
    end
  end

  return paras
end

function getChapterText(html, url)
  if type(html) ~= "string" or html == "" then return "" end

  local el = html_select_first(html, "article#article")
  if not el then el = html_select_first(html, "#article") end
  if not el then el = html_select_first(html, ".reading-content article") end
  if not el then return "" end

  -- Only <p> elements — skips the ad DIVs nested inside the article.
  local paras = {}
  for _, p in ipairs(html_select(el.html, "p")) do
    local t = string_clean(p.text or "")
    paras[#paras + 1] = t
  end
  if #paras == 0 then
    local raw = string_clean(html_text("<div>" .. el.html .. "</div>"))
    if raw == "" then return "" end
    paras = { raw }
  end

  paras = stripTxtHeader(paras)

  local out = {}
  for _, p in ipairs(paras) do
    if p ~= "" then out[#out + 1] = p end
  end
  return table.concat(out, "\n\n")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Engine hooks + settings
-- ═══════════════════════════════════════════════════════════════════════════

function getUserAgentPreset()
  return "Chrome Mobile"
end

function getSettingsSchema()
  local coverPref = get_preference(PREF_COVERS)
  if coverPref ~= "direct" then coverPref = "proxy" end
  return {
    {
      key = PREF_COVERS,
      type = "select",
      label = "Cover Images",
      current = coverPref,
      options = {
        { value = "proxy",  label = "Via wsrv.nl image proxy (recommended — fixes posters)" },
        { value = "direct", label = "Direct from oop.tw (breaks when Cloudflare challenges images)" }
      }
    },
    {
      key = PREF_MODE,
      type = "select",
      label = "Mode (模式)",
      current = getMode(),
      options = {
        { value = "raw",       label = "Raw (原文) — Chinese UI, no translation" },
        { value = "translate", label = "Translator (翻譯模式) — translate everything except chapter text" }
      }
    },
    {
      key = PREF_TLANG,
      type = "select",
      label = "Translate To (目標語言)",
      current = getTl(),
      options = {
        { value = "en", label = "English" },
        { value = "es", label = "Español" },
        { value = "pt", label = "Português" },
        { value = "ru", label = "Русский" },
        { value = "fr", label = "Français" },
        { value = "de", label = "Deutsch" },
        { value = "tr", label = "Türkçe" },
        { value = "ar", label = "العربية" },
        { value = "id", label = "Bahasa Indonesia" },
        { value = "th", label = "ไทย" },
        { value = "vi", label = "Tiếng Việt" },
        { value = "ja", label = "日本語" },
        { value = "ko", label = "한국어" },
        { value = "hi", label = "हिन्दी" },
        { value = "ur", label = "اردو" }
      }
    },
    {
      key = PREF_TR_CH,
      type = "select",
      label = "Translate Chapter Titles (章節標題)",
      current = trChaptersEnabled() and "1" or "0",
      options = {
        { value = "1", label = "On (開)" },
        { value = "0", label = "Off (關)" }
      }
    }
  }
end
