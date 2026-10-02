-- ═══════════════════════════════════════════════════════════════════════════
-- Bixiange (笔仙阁) source plugin for NoveLA
-- Version 1.0.1 (2026-09-30)
--
-- Site: https://www.bixiange.top/ — 笔仙阁, a free Chinese novel site
-- (GB2312-encoded EmpireCMS). Mirror: https://bxg123.cc (verified live
-- copy of the SAME database — identical book ids AND identical search
-- searchids, so every path is portable between the two hosts).
--
-- WHAT'S IN v1.0.1 (site URL-scheme change, re-verified live 2026-09-30):
--   • The site RETIRED the /cat/{id}/ and /cat/{id}.html book URLs (both
--     404 now). Books live at CATEGORY-prefixed URLs:
--       – new-style books:  /{cat}/{id}        e.g. /xhqh/23552
--       – old-style books:  /{cat}/{id}.html   e.g. /khjj/20819.html
--     and chapters moved to  /{cat}/{id}/index/{n}.html (was
--     /cat/id/index/N.html). The mirror bxg123.cc switched to the SAME
--     scheme on the same day, so failover keeps working.
--   • NO parser changes were needed: the plugin takes every book/chapter
--     URL from the site's own hrefs (search cards, sort cards, catalog
--     anchors) and never constructs /cat/ paths itself — the new scheme
--     flows through transparently. All selectors re-verified live:
--     .hd .list ul li cards, .catalog ul li a, div#mycontent, descInfo/
--     descTip, the 总数 search counter, index_N.html pagers.
--
-- WHAT'S IN v1.0.0:
--   • Full GBK support: the plugin declares `charset = "GBK"` in its
--     metadata, so the ENGINE decodes every chapter/book page it downloads
--     itself (DownloaderRepository uses source.charset). Plugin-side
--     fetches pass { charset = "GBK" } to http_get/http_post.
--   • Search with a GBK-encoded keyword: EmpireCMS expects the `keyboard`
--     form field percent-encoded as GBK bytes. The engine's
--     url_encode_charset(str, "GBK") does exactly that (available since
--     the Aug-2026 builds; pcall-guarded with a clear error message on
--     older builds).
--   • Result pagination: EmpireCMS search results are 20/page, 0-based
--     (`page=1` is the SECOND page); total count is embedded as
--     `<a title="总数"><b>N</b></a>` — used for exact hasNext, with the
--     pager's 下一页 link as a fallback signal.
--   • Browse surfaces (filter sheet):
--       – 最新更新 Latest Updates   /newest/          (10 pages)
--       – 总排行榜 Overall Rankings /sort/            (18 pages)
--       – 分类浏览 By Category      /{cat}/           (12 categories)
--       – 分类排行榜 Category Rank  /sort_{cat}/
--     All list pages share the same `.hd .list ul li` card markup and
--     the `index_N.html` pager (page 1 = the bare directory URL).
--   • Books keep EXACTLY the URL the site links to (never normalized):
--     v1.0.0 era /cat/{id}/ and /cat/{id}.html — both DEAD since the
--     2026-09 site change; current shapes are /{cat}/{id} and
--     /{cat}/{id}.html (see the v1.0.1 notes above).
--   • Chapters: the full catalog is on the book page (`.catalog ul li a`,
--     one page, titles “第N节”). Chapter URLs: /{cat}/id/index/N.html
--     (current) and legacy /cat/id/N.html redirects — both serve
--     `div#mycontent` paragraphs. Chapter 1 embeds a TXT
--     header (book title / 作者：… / 简介：… / synopsis block) that is
--     stripped before the first real 第X章 heading.
--   • Mirror failover: every fetch transparently retries on
--     https://bxg123.cc when www.bixiange.top fails (site preference
--     setting: Auto / bixiange.top only / bxg123.cc first). Book and
--     chapter URLs stay canonical www.bixiange.top so libraries never
--     fragment.
--   • Translator mode (copied from the battle-tested novel543 plugin):
--     machine translation of catalog titles, book info and chapter
--     titles via Google's free dict endpoint with MyMemory + gtx
--     fallbacks, a translation cache, a failure circuit breaker, and
--     pass-through on any error — browsing never breaks. Search queries
--     typed in a non-Chinese language are translated to Simplified
--     Chinese first (the site indexes zh-CN text).
--   • Posters through the wsrv.nl image proxy by default (the engine
--     exempts image URLs from the Cloudflare WebView bypass, so a
--     challenged image host breaks posters — the established fix).
--   • Chrome Mobile UA preset (engine applies it to plugin requests AND
--     image loads for this host).
--
-- Site facts (all live-verified 2026-09-19):
--   • Encoding:      GB2312/GBK everywhere (meta + Content-Type).
--   • Categories:    /dsyq/ /wxxz/ /xhqh/ /cyjk/ /khjj/ /ghxy/ /jsls/
--                    /guanchang/ /xtfq/ /dmtr/ /trxs/ /jqxs/
--   • List pages:    15 items/page, pager `index_N.html`, 下一页/尾页
--                    links (尾页 is unreliable beyond the pager window —
--                    hasNext uses 下一页 only).
--   • Search:        POST /e/search/indexpage.php
--                    (keyboard=<GBK-quoted>&show=title&classid=0)
--                    → 302 → /e/search/result/?searchid=S (Location is
--                    RELATIVE to /e/search/). Results 20/page.
--   • Zero results:  200 interstitial titled 信息提示 (≈1.4 KB).
--   • Book page:     .detail h1 (title with “(1-N)” count suffix),
--                    .cover img, .descTip spans (分类/大小/作者/时间),
--                    .descInfo p (description), .catalog ul li a (ALL
--                    chapters on one page).
--   • Chapter page:  div.content#mycontent with <p> paragraphs; nav in
--                    .mPage (首节/1-300/下一节/尾节/目录).
--   • Anti-bot:      a client-side JS redirect to /404.html for
--                    mainland-China + Windows-PC visitors — pure JS,
--                    irrelevant for the app. No Cloudflare challenge
--                    observed from datacenter IPs (server: cloudflare,
--                    but pages serve directly).
--
-- IMPORTANT — do NOT add `cf_options = { whitelist = true }`:
--   The engine's CloudflareVerificationInterceptor auto-detects CF
--   challenges and solves them via the integrated WebView; whitelisting
--   would DISABLE that recovery path for this host.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Metadata ────────────────────────────────────────────────────────────────
local VERSION = "1.0.1"
id       = "bixiange"
name     = "Bixiange 笔仙阁"
version  = "1.0.1"  -- literal: the extension manager's regex only parses quoted values
baseUrl  = "https://www.bixiange.top/"
language = "zh"
charset  = "GBK"   -- engine decodes its own downloads (chapters/books) as GBK
icon     = "https://www.bixiange.top/images/logo.png"

-- ── Constants ────────────────────────────────────────────────────────────────
local SITE   = "https://www.bixiange.top"
local MIRROR = "https://bxg123.cc"

-- Settings preference keys
local PREF_SITE   = "bixiange_site"     -- auto | top | mirror
local PREF_MODE   = "bixiange_mode"     -- raw | translate
local PREF_TLANG  = "bixiange_tlang"    -- target language code, default "en"
local PREF_TR_CH  = "bixiange_tr_chapters" -- "1" | "0" (translate chapter titles)
local PREF_COVERS = "bixiange_covers"   -- proxy (default) | direct

-- ── Site taxonomy (verified live 2026-09-19) ────────────────────────────────
-- Path segments double as filter values; en/zh feed flLabel().
local CATEGORIES = {
  { value = "dsyq",      en = "Urban Romance",        zh = "都市言情" },
  { value = "wxxz",      en = "Wuxia & Cultivation",  zh = "武侠修真" },
  { value = "xhqh",      en = "Xuanhuan & Fantasy",   zh = "玄幻奇幻" },
  { value = "cyjk",      en = "Transmigration",       zh = "穿越架空" },
  { value = "khjj",      en = "Sci-Fi & Sports",      zh = "科幻竞技" },
  { value = "ghxy",      en = "Horror & Mystery",     zh = "鬼话悬疑" },
  { value = "jsls",      en = "Military & History",    zh = "军事历史" },
  { value = "guanchang", en = "Officialdom & Business", zh = "官场商战" },
  { value = "xtfq",      en = "Rural Life",           zh = "乡土风情" },
  { value = "dmtr",      en = "Danmei (BL)",          zh = "耽美小说" },
  { value = "trxs",      en = "Fanfiction",           zh = "同人小说" },
  { value = "jqxs",      en = "Premium Selection",    zh = "精品小说" }
}

-- Static English lookups for fixed site vocabulary (English target only;
-- other languages go through the API and get cached).
local STATIC_EN = {
  ["都市言情"] = "Urban Romance",   ["武侠修真"] = "Wuxia & Cultivation",
  ["玄幻奇幻"] = "Xuanhuan & Fantasy", ["穿越架空"] = "Transmigration",
  ["科幻竞技"] = "Sci-Fi & Sports", ["鬼话悬疑"] = "Horror & Mystery",
  ["军事历史"] = "Military & History", ["官场商战"] = "Officialdom & Business",
  ["乡土风情"] = "Rural Life",     ["耽美小说"] = "Danmei (BL)",
  ["同人小说"] = "Fanfiction",     ["精品小说"] = "Premium Selection",
  ["连载"] = "Ongoing",            ["完結"] = "Completed",
  ["完结"] = "Completed"
}

-- ── Generic helpers ──────────────────────────────────────────────────────────

local function absUrl(href)
  if not href or href == "" then return "" end
  if string_starts_with(href, "http") then return href end
  if string_starts_with(href, "//") then return "https:" .. href end
  return url_resolve(baseUrl, href)
end

-- True when the string contains CJK ideographs (UTF-8 lead bytes E4-E9).
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
  return COVER_PROXY .. url_encode(u) .. "&w=450&we&output=jpg&q=80"
end

-- ── Clock (NoveLA's os_time returns MILLISECONDS — verified in Kotlin) ──────
local function nowMs()
  local ok, v = pcall(os_time)
  if ok and type(v) == "number" and v > 0 then
    if v < 100000000000 then v = v * 1000 end -- seconds → ms
    return v
  end
  return nil
end

-- ── Site ordering (mirror preference) ────────────────────────────────────────
local function orderedBases()
  local pref = get_preference(PREF_SITE)
  if pref == "top" then
    return { SITE }
  elseif pref == "mirror" then
    return { MIRROR, SITE }
  end
  return { SITE, MIRROR } -- auto (default): primary first, mirror backup
end

-- ── HTTP with GBK decoding, redirect following and mirror failover ──────────
-- NoveLA's http_get does NOT follow redirects (NetworkClient default), and
-- the site 301-redirects the no-slash book URLs (/jsls/23825 → /jsls/23825/).
-- Every fetch decodes the GBK body; a failing base transparently retries on
-- the next base (mirror). Book/chapter URLs are NOT rewritten — absUrl()
-- keeps them canonical to www.bixiange.top.
local function readHeader(r, name)
  if type(r) ~= "table" or type(r.headers) ~= "table" then return nil end
  local t = r.headers[string.lower(name)]
  if type(t) ~= "table" then return nil end
  return t[1]
end

local function httpGetRaw(base, url)
  return http_get(url, {
    headers = {
      ["Referer"] = base .. "/",
      ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    },
    charset = "GBK"
  })
end

-- Follow up to 4 redirects manually, resolving Location against the fetched
-- URL's context (absolute / root-relative / EmpireCMS search-relative all
-- handled by the engine's RFC-3986 url_resolve).
local function followRedirects(r, fetchedUrl)
  local current = fetchedUrl
  for _ = 1, 4 do
    if type(r) ~= "table" or r.success then return r end
    local code = tonumber(r.code) or 0
    if code ~= 301 and code ~= 302 and code ~= 303 and code ~= 307 and code ~= 308 then
      return r
    end
    local loc = readHeader(r, "location")
    if type(loc) ~= "string" or loc == "" then return r end
    local next_
    if string_starts_with(loc, "http") then
      next_ = loc
    else
      next_ = url_resolve(current, loc)
    end
    if next_ == loc and not string_starts_with(loc, "http") then
      -- url_resolve failed (engine fallback returns the argument) — last
      -- resort: resolve against the site root.
      local origin = string.match(current, "^https?://[^/]+") or SITE
      next_ = origin .. (string_starts_with(loc, "/") and loc or "/" .. loc)
    end
    current = next_
    local base = string.match(next_, "^https?://[^/]+") or SITE
    r = httpGetRaw(base, next_)
  end
  return r
end

-- GET a PATH (e.g. "/jsls/23825/") or an absolute URL, trying every base by
-- HOST SUBSTITUTION (absolute URLs get their host swapped to the mirror on
-- failure — book/chapter URLs are absolute, and failover must still work).
-- Returns the first successful response table, or the last failure.
local function httpGetAny(pathOrUrl)
  local last = nil
  local path = pathOrUrl
  if string_starts_with(pathOrUrl, "http") then
    path = string.match(pathOrUrl, "^https?://[^/]+(/.*)$") or "/"
  end
  for _, base in ipairs(orderedBases()) do
    local url = base .. path
    local r = followRedirects(httpGetRaw(base, url), url)
    if r and r.success then return r end
    last = r
  end
  return last
end

-- ── Short-lived page cache ───────────────────────────────────────────────────
-- Opening a book triggers getBookTitle / Cover / Description / Genres /
-- LastUpdate / ChapterListHash separately — without this cache each of them
-- re-downloads the SAME page (6+ round-trips per book open). 60s TTL,
-- 12 pages. Chapter text is NEVER served from here.
local pageCache, pageCacheOrder = {}, {}
local PAGE_TTL_MS    = 60000
local PAGE_CACHE_MAX = 12

local function fetchPageCached(bookUrl)
  local now = nowMs()
  if not now then return httpGetAny(bookUrl) end -- no clock → bypass cache
  local e = pageCache[bookUrl]
  if e and (now - e.t) < PAGE_TTL_MS then return e.r end
  local r = httpGetAny(bookUrl)
  if r and r.success then
    if pageCache[bookUrl] == nil then
      pageCacheOrder[#pageCacheOrder + 1] = bookUrl
      if #pageCacheOrder > PAGE_CACHE_MAX then
        pageCache[table.remove(pageCacheOrder, 1)] = nil
      end
    end
    pageCache[bookUrl] = { r = r, t = now }
  end
  return r
end


-- ═══════════════════════════════════════════════════════════════════════════
-- Translator core (copied from novel543.lua v1.0.5 — battle-tested)
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
    local res = trRequestGoogle(chunk, "zh-CN", tl)
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
          log_info("bixiange: translator disabled for 10 min (3 failed batches)")
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
  if not ok then log_info("bixiange: translator error: " .. tostring(res)) end
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

-- Reverse direction for search: user-language query → Simplified Chinese
-- (the site indexes zh-CN text — queries must be Chinese to match).
local function translateQueryToZh(query, srcLang)
  if not trActive() then return nil end
  local ok, res = pcall(trRequestGoogle, { query }, srcLang or "auto", "zh-CN")
  if ok and type(res) == "table" and res[1] and res[1] ~= query then return res[1] end
  return nil
end


-- ═══════════════════════════════════════════════════════════════════════════
-- List-page parsing + catalog browse
-- ═══════════════════════════════════════════════════════════════════════════

-- Every site list surface (category /sort/ /newest/ /sort_{cat}/ search
-- results) uses the same card markup:
--   .hd .list ul > li
--     .cover a            → href (book URL — EXACT site form) + img (cover)
--     .info .title strong a → title
--     .info .title .tips span → 作者：… / size / date
--     .descript a         → description snippet
-- Pagination widget: .page — <b>N</b> is the CURRENT page, plus links to
-- index_K.html pages, a 下一页 (next) link and a 尾页 (last) link. The 尾页
-- target is unreliable beyond the pager's window (live-verified: /jsls/
-- claims 尾页=30 while pages up to ~45 exist) — hasNext uses 下一页 only.
local function parseListCards(body)
  local items = {}
  if not body then return items end
  for _, li in ipairs(html_select(body, ".hd .list ul li")) do
    local href = html_attr(li.html, ".cover a", "href")
    local img  = html_attr(li.html, ".cover img", "src")
    local titleEl = html_select_first(li.html, ".title strong a")
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

-- hasNext from the pager's 下一页 link (exact; never trusts 尾页).
local function listHasNext(body)
  if not body then return false end
  for _, a in ipairs(html_select(body, ".page a")) do
    if a.text and string.find(a.text, "下一页") then return true end
  end
  return false
end

-- Batch-translate catalog item titles in place.
local function translateCatalogItems(items)
  if not trActive() or #items == 0 then return items end
  local titles = {}
  for i = 1, #items do titles[i] = items[i].title end
  local tr = translateBatch(titles)
  for i = 1, #items do items[i].title = tr[i] end
  return items
end

-- Build a list-page URL for a directory path ("" = site root of surface):
--   index 0 → /{path}/            (page 1 = bare directory)
--   index N → /{path}/index_{N+1}.html
local function listPagePath(path, index)
  if index <= 0 then return "/" .. path .. "/" end
  return "/" .. path .. "/index_" .. tostring(index + 1) .. ".html"
end

-- ── Filter state ─────────────────────────────────────────────────────────────
-- The app's filter UI cannot show/hide sections dynamically, so the Category
-- picker is always present and simply ignored by surfaces that don't use it.
local currentSurface = "newest"
local currentCategory = "dsyq"

local function surfacePath(surface, cat)
  if surface == "rank" then return "sort" end
  if surface == "catrank" then return "sort_" .. cat end
  if surface == "category" then return cat end
  return "newest"
end

function getCatalogList(index)
  currentSurface = "newest"
  local path = listPagePath("newest", index)
  local r = httpGetAny(path)
  if not (r and r.success) then
    if type(show_error) == "function" then
      show_error("Bixiange unreachable",
        "Could not load the latest list from www.bixiange.top or the bxg123.cc mirror. " ..
        "Check your connection and retry.")
    end
    return { items = {}, hasNext = false }
  end
  local items = parseListCards(r.body)
  translateCatalogItems(items)
  return { items = items, hasNext = listHasNext(r.body) }
end

function getCatalogFiltered(index, filters)
  local surface = (filters and filters.surface) or currentSurface or "newest"
  local cat     = (filters and filters.category) or currentCategory or "dsyq"
  currentSurface, currentCategory = surface, cat

  local path = listPagePath(surfacePath(surface, cat), index)
  local r = httpGetAny(path)
  if not (r and r.success) then
    if type(show_error) == "function" then
      show_error("Bixiange unreachable",
        "Could not load the list page from www.bixiange.top or the bxg123.cc mirror. " ..
        "Check your connection and retry.")
    end
    return { items = {}, hasNext = false }
  end
  local items = parseListCards(r.body)
  translateCatalogItems(items)
  return { items = items, hasNext = listHasNext(r.body) }
end

function getFilterList()
  local surfaces = {
    { value = "newest",   label = flLabel("Latest Updates", "最新更新") },
    { value = "rank",     label = flLabel("Overall Rankings", "总排行榜") },
    { value = "category", label = flLabel("By Category", "分类浏览") },
    { value = "catrank",  label = flLabel("Category Rankings", "分类排行榜") }
  }
  local catOptions = {}
  for _, c in ipairs(CATEGORIES) do
    catOptions[#catOptions + 1] = { value = c.value, label = flLabel(c.en, c.zh) }
  end
  return {
    {
      type = "select",
      key = "surface",
      label = "Browse",
      options = surfaces
    },
    {
      type = "select",
      key = "category",
      label = "Category (分类)",
      options = catOptions
    }
  }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Search (EmpireCMS GBK POST + searchid pagination)
-- ═══════════════════════════════════════════════════════════════════════════
-- POST /e/search/indexpage.php with keyboard percent-encoded as GBK bytes
-- → 302 Location: result/?searchid=S (RELATIVE to /e/search/)
-- → GET /e/search/result/?searchid=S          (page 1, 20 items)
--   GET /e/search/result/index.php?page=K&searchid=S  (0-based: K=1 → page 2)
-- Total count: <a title="总数"><b>N</b></a>. Zero results: a 200 page titled
-- 信息提示 with no cards. The mirror shares the SAME searchids (live-verified:
-- both hosts return searchid 7735027 for the same query) — pagination may use
-- any base.

-- searchid cache per query for the lifetime of one engine run
local _searchIdByQuery = {}
local SEARCH_PAGE_SIZE = 20

-- GBK-percent-encode a query for the EmpireCMS form. url_encode_charset is
-- pcall-guarded: on builds where it is missing, fall back to UTF-8 url_encode
-- (the search will not match, but the caller surfaces a readable error).
local function gbkEncodeQuery(query)
  local ok, enc = pcall(url_encode_charset, query, "GBK")
  if ok and type(enc) == "string" and enc ~= "" then return enc, true end
  return url_encode(query), false
end

-- POST the search form on one base; returns response table (302 included).
local function postSearch(base, query)
  local enc = gbkEncodeQuery(query)
  local form = "keyboard=" .. enc .. "&show=title&classid=0"
  return http_post(base .. "/e/search/indexpage.php", form, {
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
      ["Referer"] = base .. "/",
      ["Accept"]   = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    },
    charset = "GBK"
  })
end

local function extractSearchId(body)
  if type(body) ~= "string" then return nil end
  return string.match(body, "searchid=(%d+)")
end

-- Zero-result interstitial detection: the 信息提示 page has no cards and no
-- searchid; a real result page has cards or a searchid in its pager.
local function hasSearchResults(body)
  if type(body) ~= "string" then return false end
  if #html_select(body, ".hd .list ul li") > 0 then return true end
  return extractSearchId(body) ~= nil
end

-- Total results from `<a title="总数">&nbsp;<b>N</b></a>` (the &nbsp; between
-- the anchor text and the <b> defeats %s-based patterns — use a lazy match on
-- a single line; nil when absent).
local function searchTotal(body)
  if type(body) ~= "string" then return nil end
  return tonumber(string.match(body, 'title="总数".-<b>(%d+)</b>'))
end

function getCatalogSearch(index, query)
  if type(query) ~= "string" or query == "" then
    return { items = {}, hasNext = false }
  end

  -- Translate non-Chinese queries to Simplified Chinese (the site's index
  -- is zh-CN; a raw English query returns nothing).
  local q = query
  if not hasCJK(q) then
    local tq = translateQueryToZh(q, "auto")
    if tq then q = tq end
  end

  -- Page 1: run the search (POST → 302 → result page).
  -- NOTE: NoveLA marks 3xx responses success=false (isSuccessful), so the
  -- redirect branch must check r.code WITHOUT requiring r.success.
  if index <= 0 then
    local body = nil
    for _, base in ipairs(orderedBases()) do
      local r = postSearch(base, q)
      if r then
        local code = tonumber(r.code) or 0
        if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
          local loc = readHeader(r, "location")
          if type(loc) == "string" and loc ~= "" then
            local next_
            if string_starts_with(loc, "http") then
              next_ = loc
            elseif string_starts_with(loc, "/") then
              next_ = base .. loc
            else
              -- EmpireCMS Location "result/?searchid=S" is relative to /e/search/
              next_ = base .. "/e/search/" .. loc
            end
            local rr = followRedirects(httpGetRaw(base, next_), next_)
            if rr and rr.success then body = rr.body end
          end
        elseif r.success then
          -- 200 = result page served directly, or the 信息提示 zero-result page
          body = r.body
        end
      end
      if body then break end
    end

    if not body then
      if type(show_error) == "function" then
        show_error("Bixiange search unreachable",
          "The search could not run on www.bixiange.top or the bxg123.cc mirror. " ..
          "Check your connection and retry.")
      end
      return { items = {}, hasNext = false }
    end

    local sid = extractSearchId(body)
    if sid then _searchIdByQuery[q] = sid end

    if not hasSearchResults(body) then
      return { items = {}, hasNext = false } -- definitive zero results
    end

    local items = parseListCards(body)
    translateCatalogItems(items)
    local total = searchTotal(body)
    local hasNext = false
    if total then
      hasNext = total > SEARCH_PAGE_SIZE
    else
      hasNext = listHasNext(body)
    end
    return { items = items, hasNext = hasNext }
  end

  -- Pages 2+: paginate the stored searchid (0-based page param).
  local sid = _searchIdByQuery[q]
  if not sid then
    return { items = {}, hasNext = false } -- no search session → stop
  end
  local path = "/e/search/result/index.php?page=" .. tostring(index) .. "&searchid=" .. sid
  local r = httpGetAny(path)
  if not (r and r.success) then
    return { items = {}, hasNext = false }
  end
  local items = parseListCards(r.body)
  translateCatalogItems(items)
  local total = searchTotal(r.body)
  local hasNext = false
  if total then
    hasNext = total > (index + 1) * SEARCH_PAGE_SIZE
  else
    hasNext = listHasNext(r.body)
  end
  return { items = items, hasNext = hasNext }
end


-- ═══════════════════════════════════════════════════════════════════════════
-- Book details
-- ═══════════════════════════════════════════════════════════════════════════
-- Book page layout (same template for /cat/id/ and /cat/id.html books):
--   .detail .info
--     .cover img                  → cover (relative /d/file/... URL)
--     .desc h1                    → "书名(1-301)" (count suffix stripped)
--     .descTip p span             → 分类：X / 大小：Y MB / 作者：Z / 时间：DATE
--     .descInfo p                 → description (with <br/> line breaks)
--     .catalog ul li a            → ALL chapters (one page), titles “第N节”

-- Split the .descTip spans into named fields (labels are Chinese).
-- NOTE: Lua patterns are byte-based — a character CLASS like [:：] breaks on
-- the 3-byte fullwidth colon (it matches only its FIRST byte, leaving mojibake
-- in the capture). Both colon variants are matched as LITERAL alternatives.
local function matchLabel(t, label)
  local v = string.match(t, "^" .. label .. "：(.+)$")
  if not v then v = string.match(t, "^" .. label .. ":(.+)$") end
  if v then v = string.gsub(v, "^%s+", "") end
  return v
end

local function parseDescTip(body)
  local out = {}
  for _, p in ipairs(html_select(body, ".descTip p")) do
    for _, span in ipairs(html_select(p.html, "span")) do
      local t = string_clean(span.text or "")
      local v
      v = matchLabel(t, "分类"); if v then out.category = v end
      v = matchLabel(t, "作者"); if v then out.author   = v end
      v = matchLabel(t, "时间"); if v then out.date     = v end
      v = matchLabel(t, "大小"); if v then out.size     = v end
    end
  end
  return out
end

-- Strip the trailing "(1-301)" chapter-count suffix from the h1 title.
local function cleanBookTitle(t)
  if type(t) ~= "string" then return t end
  local cleaned = string.gsub(t, "%s*%(%d+%s*-%s*%d+%)%s*$", "")
  if cleaned == "" then return t end
  return cleaned
end

function getBookTitle(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local el = html_select_first(r.body, ".desc h1")
  if not el then el = html_select_first(r.body, "h1") end
  if not el then return nil end
  local title = cleanBookTitle(string_clean(el.text))
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
  local src = html_attr(r.body, ".cover img", "src")
  if not src or src == "" then return nil end
  return coverUrl(absUrl(src))
end

function getBookDescription(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local meta = parseDescTip(r.body)
  local el = html_select_first(r.body, ".descInfo p")
  if not el then return nil end
  local desc = string_clean(el.text)
  if desc == "" then return nil end

  -- Prefix the author line (the app has no dedicated author field).
  local header = ""
  if meta.author and meta.author ~= "" then
    header = "作者：" .. meta.author .. "\n\n"
  end
  desc = header .. desc

  if #desc > 4000 then desc = string.sub(desc, 1, 4000) end
  if trActive() then desc = translateOne(desc) end
  return desc
end

function getBookGenres(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return {} end
  local meta = parseDescTip(r.body)
  if meta.category and meta.category ~= "" then
    return { translateVocab(meta.category) }
  end
  return {}
end

-- The site does not expose an ongoing/completed status anywhere on the book
-- page — return nil rather than guessing.
function getBookStatus(bookUrl)
  return nil
end

function getBookLastUpdate(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local meta = parseDescTip(r.body)
  if meta.date then
    local d = string.match(meta.date, "(%d%d%d%d%-%d%d%-%d%d)")
    if d then return d end
    return meta.date
  end
  return nil
end

-- Update hash: last-update date + chapter count + last chapter URL tail.
-- Catches both new chapters and whole-book replacements.
function getChapterListHash(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local meta = parseDescTip(r.body)
  local chapters = html_select(r.body, ".catalog ul li a")
  local lastHref = ""
  if #chapters > 0 then
    lastHref = chapters[#chapters].href or ""
  end
  if meta.date or #chapters > 0 then
    return (meta.date or "") .. "|" .. tostring(#chapters) .. "|" .. lastHref
  end
  return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter list
-- ═══════════════════════════════════════════════════════════════════════════

function getChapterList(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return {} end

  local chapters = {}
  for _, a in ipairs(html_select(r.body, ".catalog ul li a")) do
    local chUrl = absUrl(a.href)
    if chUrl ~= "" then
      local title = string_clean(a.text)
      if title == "" then title = "第" .. tostring(#chapters + 1) .. "节" end
      chapters[#chapters + 1] = { title = title, url = chUrl }
    end
  end

  if trActive() and trChaptersEnabled() and #chapters > 0 then
    local titles = {}
    for i = 1, #chapters do titles[i] = chapters[i].title end
    local tr = translateBatch(titles)
    for i = 1, #chapters do chapters[i].title = tr[i] end
  end

  return chapters
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter text
-- ═══════════════════════════════════════════════════════════════════════════
-- Content lives in div.content#mycontent as <p> paragraphs (both URL
-- generations). Chapter 1 embeds a TXT header before the real content:
--     书名 / 作者：X / 简介： / …synopsis paragraphs… / 第1章 …
-- The header is stripped: if a 第X章-style heading is found at paragraph
-- index ≥ 4 within the first 30 paragraphs, everything before it is dropped;
-- otherwise only title/作者/简介 marker lines are dropped.

local function isChapterHeading(p)
  return string.match(p, "^第[%d一二三四五六七八九十百千零两]+%s*[章节回卷部]") ~= nil
    or string.match(p, "^[Cc]hapter%s+%d+") ~= nil
end

local function stripTxtHeader(paras, pageTitle)
  local n = #paras
  if n == 0 then return paras end

  -- Tier 1: a real chapter heading deeper in the paragraph stream marks the
  -- true content start (TXT header is always ≥ 4 paragraphs: title+author+
  -- 简介+synopsis).
  local limit = n
  if limit > 30 then limit = 30 end
  for i = 5, limit do
    if paras[i] ~= "" and isChapterHeading(paras[i]) then
      local out = {}
      for k = i, n do out[#out + 1] = paras[k] end
      return out
    end
  end

  -- Tier 2: strip known marker lines off the top (title / 作者： / 简介：).
  local start = 1
  local titleCore = pageTitle and string.gsub(pageTitle, "%s", "") or ""
  while start <= n do
    local p = paras[start]
    local isMarker = (p == "")
      or (p and titleCore ~= "" and string.gsub(p, "%s", "") == titleCore)
      or (p and string.match(p, "^作者："))
      or (p and string.match(p, "^作者:"))
      or (p and string.match(p, "^简介：?$"))
      or (p and string.match(p, "^简介:?$"))
    if not isMarker then break end
    start = start + 1
  end
  if start > n then return paras end -- everything matched (shouldn't happen)
  local out = {}
  for k = start, n do out[#out + 1] = paras[k] end
  return out
end

function getChapterText(html, url)
  if type(html) ~= "string" or html == "" then return "" end

  local el = html_select_first(html, "#mycontent")
  if not el then el = html_select_first(html, "div.content") end
  if not el then return "" end

  -- Remove ad/script scaffolding inside the content block, if any.
  local cleaned = html_remove(el.html, "script", "ins", "div.adBlock", "div.gadBlock")
  local paras = {}
  for _, p in ipairs(html_select("<div>" .. cleaned .. "</div>", "p")) do
    local t = string_clean(p.text or "")
    paras[#paras + 1] = t
  end
  if #paras == 0 then
    local raw = string_clean(html_text("<div>" .. cleaned .. "</div>"))
    if raw == "" then return "" end
    paras = { raw }
  end

  -- Chapter title from the page (used only for TXT-header stripping).
  local h1 = html_select_first(html, ".article h1")
  local pageTitle = h1 and string_clean(h1.text) or ""

  paras = stripTxtHeader(paras, pageTitle)

  local out = {}
  for _, p in ipairs(paras) do
    if p ~= "" then out[#out + 1] = p end
  end
  return table.concat(out, "\n\n")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Engine hooks + settings
-- ═══════════════════════════════════════════════════════════════════════════

-- Chrome Mobile UA preset: the engine applies it to this plugin's requests
-- AND to untagged image loads for the baseUrl host.
function getUserAgentPreset()
  return "Chrome Mobile"
end

function getSettingsSchema()
  local sitePref = get_preference(PREF_SITE)
  if sitePref ~= "top" and sitePref ~= "mirror" then sitePref = "auto" end
  local coverPref = get_preference(PREF_COVERS)
  if coverPref ~= "direct" then coverPref = "proxy" end
  return {
    {
      key = PREF_SITE,
      type = "select",
      label = "Site (站点)",
      current = sitePref,
      options = {
        { value = "auto",   label = "Auto — bixiange.top first, bxg123.cc mirror fallback (recommended)" },
        { value = "top",    label = "bixiange.top only" },
        { value = "mirror", label = "bxg123.cc mirror first — bixiange.top backup" }
      }
    },
    {
      key = PREF_COVERS,
      type = "select",
      label = "Cover Images",
      current = coverPref,
      options = {
        { value = "proxy",  label = "Via wsrv.nl image proxy (recommended — fixes posters)" },
        { value = "direct", label = "Direct from bixiange.top" }
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
