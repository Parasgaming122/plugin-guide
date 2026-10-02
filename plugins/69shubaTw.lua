-- ═══════════════════════════════════════════════════════════════════════════
-- 69書吧 (69shuba.tw) source plugin for NoveLA
-- Version 1.3.0 (2026-09-26)
--
-- NOT the same site as the existing "69shuba" plugin (www.69shuba.com —
-- Simplified, GBK, /book/{id}.htm URLs, different library): 69shuba.tw is
-- the Traditional-Chinese portal of the family — UTF-8, its own URL scheme
-- (/book/{id}/, /indexlist/{id}/, /read/{bid}/{cid}) and a DIFFERENT book
-- database (book 342441 exists here, 404s on .com). Hence a separate
-- plugin id: "69shubaTw".
--
-- ANTI-BOT — Tencent EdgeOne "aegis" captcha, NOT Cloudflare:
--   Server: Edge/1.1.28. Challenges serve a custom human-verification page
--   (reCAPTCHA v3 checkbox + Turnstile script; the token POSTs to
--   /aegis_captcha_verify?rule_uuid=…; cookies __ct_ac_cpg + __ct_cya_ckt
--   follow — the pass cookie lasts only 5 MINUTES, so re-challenges were
--   the norm on the old lowercase catalog path).
--   THE v1.3.0 FIX: EdgeOne's rule matches lowercase /indexlist/* ONLY
--   (verified: /indexlist/342441/ → 403 challenge even from Google's clean
--   translate-proxy IPs, /Indexlist/342441/ → 200 real page from the same
--   IPs, same session, seconds apart). The plugin fetches every catalog
--   page through the capital form — no challenge, no solver, from any IP
--   reputation the site otherwise tolerates. /book/*, /read/*, /search/*,
--   /fenlei/*, /quanben/* have no such rule (verified from clean IPs).
--   cf_options.trigger_markers stays registered (a documented field on
--   current builds) so that IF another surface ever challenges, the app's
--   WebView ladder still engages; the plugin also detects the challenge
--   body itself and fails with a guided message instead of parsing it.
--
-- COVERS: served by the open CDN p.69shuba.tw (no challenge, verified) —
--   DIRECT image URLs, no wsrv.nl proxy (deliberately, per user request —
--   and unlike wuxiabox/wtrlab/novel543/oop whose CDNs sit behind WAFs).
--   Deterministic pattern: https://p.69shuba.tw/{id÷1000}/{id}/{id}s.jpg
--   (verified on 342441/337296/338557/400577) — synthesized when the book
--   page cannot be fetched.
--
-- WHAT'S NEW IN v1.3.0 (the "solver storm + chapters never loaded" fix):
--   • WAF DISCOVERY: EdgeOne's path rule challenges lowercase /indexlist/*
--     from EVERY IP (clean or not; the __ct pass cookie lasts 5 minutes) —
--     that is why the solver kept opening and chapters never loaded. The
--     rule is case-sensitive, the router is not: ALL catalog fetches now go
--     to /Indexlist/{id}/{N}/ (capital I) — WAF-free, zero solver.
--   • THE REAL MARKUP (captured live 2026-09-26 via the clean-IP translate
--     proxy, book 342441 = 450 chapters on 5 pages): chapters live in
--     div#alllist as <li><a href=/read/{bid}/{cid}> … AND as anti-scrape
--     <li><span class=protected-chapter-link data-cid-url=…> (~2 per page —
--     both forms are collected now; the old parser silently dropped the
--     spans). Pager = select#indexselect-top with ALL page URLs as option
--     values ("/indexlist/{id}/", "/indexlist/{id}/2/" … "401 - 450章") +
--     下一页/上一页 anchors + a "没有了" disabled span on the last page.
--   • ZERO SPECULATIVE REQUESTS: the v1.2.0 batch prefetch (pages 2..8 in
--     parallel), the blind page-2 probe, the window chase and the
--     /book/-seed + per-chapter #pb_next walk are ALL removed — each was
--     another solver ladder when the WAF bit. Page 1 = ONE fetch; page N =
--     ONE fetch each, engine-driven and lazy; a ≤100-chapter novel costs
--     exactly one catalog request.
--   • TOC cache format v3 (drops the walk fields; v1/v2 entries discarded).
--     Interior pages serve offline; the last page re-fetches for growth.
--   • Early-stop safe: the engine keeps every page collected before a
--     failure (verified in DownloaderRepository: "FAILED page N, stopping
--     early") — a failed page 4/5 still leaves 300 readable chapters.
--
-- WHAT'S IN THE PLUGIN:
--   • Browse: 全部小說 ranking /quanben/fenlei/{N}/ (1-based) with a
--     9-option picker: 完結全部 + 8 categories → /fenlei/{slug}/{N}/
--     (玄幻 xuanhuan 仙俠 wuxia 都市 dushi 歷史 lishi 遊戲 youxi
--      科幻 kehu 言情 yanqing 同人 tongren). 30 books/page.
--   • Search: GET /search/?searchkey={q}&searchtype=all (page 1) and
--     /search/{N}?searchkey={q} (page N — both live-verified); the same
--     table.list-item cards as the listings, with .highlight spans inside
--     titles (text concatenation merges them). hasNext from the pager's
--     下一页 link.
--   • Book pages /book/{id}/: title td.info h1, cover img, author /
--     category / 狀態+字數 / 更新 timestamp / latest chapter
--     (p#lastchapter-row), description div.intro p.
--   • Chapter catalog /Indexlist/{id}/{N}/ (capital I — WAF-exempt; the
--     lowercase path is EdgeOne-challenged from every IP). 100 chapters
--     per page (user-verified; live-captured: 450 ch = 5 pages). The list
--     (div#alllist) mixes normal <a> chapter anchors with anti-scrape
--     <span class=protected-chapter-link data-cid-url=…> entries (~2 per
--     page) — BOTH are collected. Pager: select#indexselect-top option
--     values = every page URL; 下一页/上一页 anchors; "没有了" disabled
--     span on the last page. Pages load LAZILY, one request each — a
--     ≤100-chapter novel costs exactly ONE catalog request (no batch
--     prefetch, no probes). Soft-serve guard: a wrong page-N URL that
--     re-serves page 1 is detected (first-chapter comparison) and never
--     pollutes the TOC.
--   • Chapter text /read/{bid}/{cid}: div#nr1 <p> paragraphs ONLY (ad
--     divs — .reader-ad with loadAdv() — are interleaved BETWEEN the <p>s
--     inside the content div; p-only selection skips them all). Titles
--     carry a "(cur / total)" sub-page suffix — when total > 1 the plugin
--     fetches /read/{bid}/{cid}/{n} sub-pages and concatenates them.
--     Domain-watermark lines (69shuba.tw etc.) and (本章完) are stripped.
--   • Translator mode (the novel543 engine, source zh-TW): Google free
--     dict endpoint + MyMemory + gtx fallbacks, translation cache,
--     circuit breaker, pass-through on any error. Non-Chinese search
--     queries are translated to Traditional Chinese first (zh-TW variant,
--     zh-CN retry when the first finds nothing — user titles may be either).
--   • Chrome Mobile UA preset (mobile-first site).
--
-- Site facts (live-verified 2026-09-20 via the Google-Translate proxy —
-- direct datacenter access is EdgeOne-challenged on every path):
--   • Encoding:       UTF-8 (NOT GBK like 69shuba.com). Content mostly
--                     Traditional; nav/pager literals Simplified
--                     (上一页 下一页 第N页) — both are matched.
--   • Listings:       /quanben/fenlei/{N}/ (titled 全部小說小說排行榜,
--                     nav link 完結), /fenlei/{slug}/{N}/ (排行榜).
--   • Cards:          table.list-item → td img (cover), div.article a
--                     (title; .highlight spans in search), p.fs12.gray
--                     span.mr15 ("作者:X[　N萬字]"), synopsis in a
--                     span.fs12.gray.
--   • Pager:          div.index-container → span.disabled-btn (prev on
--                     p1) + select#indexselect (option value = page path,
--                     10-option window) + a.index-container-btn (下一页 =
--                     next). hasNext = a 下一页 link exists.
--   • Book page:      div.bookinfo table → td img + td.info (h1 title,
--                     作者：/類別：/狀態：…/更新：/最新： p#lastchapter-row),
--                     table.book-op (章節目錄 → /indexlist/{id}/,
--                     #startread → ch1), div.intro p, ul.last9 (latest).
--   • TOC:            /Indexlist/{id}/ + /{N}/ pages (capital I — the
--                     WAF-exempt form; 100 chapters per page, user-verified;
--                     markup live-captured: div#alllist list, protected
--                     chapter spans, select#indexselect-top page options).
--   • Sibling proof:   wcshuba.com = the same new-CMS family, NOT WAF'd —
--                     its /chapterlist/{id} pages were captured live and
--                     drove the v1.2.0 pager engine (see research/wc_*.html).
--   • Chapter page:   h1#nr_title "第N章 …(cur / total)", div#nr1 <p>,
--                     #pb_prev/#pb_mulu/#pb_next (上一章/目錄/下一章),
--                     #startread ch1 = /read/342441/890315.
--   • Covers:         //p.69shuba.tw/{id÷1000}/{id}/{id}s.jpg — open CDN.
--   • Author pages:   /author/{urlencoded name}/ (not used by the plugin).
--   • No JSON API:    classic PHP/Jieqi-style rendering (addbookcase,
--                     bookcase, recentread are cookie features — skipped).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Metadata ────────────────────────────────────────────────────────────────
local VERSION = "1.3.0"
id       = "69shubaTw"
name     = "69書吧 (69shuba.tw)"
version  = "1.3.0"  -- literal: the extension manager's regex only parses quoted values
baseUrl  = "https://69shuba.tw/"
language = "zh"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/69shuba.png"

-- Anti-bot: the site's EdgeOne "aegis" captcha is invisible to the engine's
-- stock Cloudflare detector (Server: Edge). These markers make the engine's
-- interceptor run its WebView bypass ladder whenever the challenge page is
-- served (any status code) — solve the checkbox once, cookies carry over.
cf_options = {
  trigger_markers = {
    "aegis_captcha_verify",              -- the challenge's POST endpoint
    "recaptcha-v3-container",            -- the checkbox widget markup
    "Please complete human verification",-- the challenge page <title>
    "challenges.cloudflare.com/turnstile"-- the challenge's Turnstile script
  }
}

-- ── Constants ────────────────────────────────────────────────────────────────
local SITE = "https://69shuba.tw"

-- Settings preference keys
local PREF_MODE   = "s69tw_mode"      -- raw | translate
local PREF_TLANG  = "s69tw_tlang"     -- target language code, default "en"
local PREF_TR_CH  = "s69tw_tr_chapters" -- "1" | "0" (translate chapter titles)

-- ── Site taxonomy (live-verified 2026-09-20) ────────────────────────────────
-- value = the /fenlei/ slug. "quanben" = the all/completed ranking surface.
local CATEGORIES = {
  { value = "xuanhuan", en = "Fantasy (玄幻)",    zh = "玄幻" },
  { value = "wuxia",    en = "Immortal (仙俠)",   zh = "仙俠" },
  { value = "dushi",    en = "Urban (都市)",      zh = "都市" },
  { value = "lishi",    en = "History (歷史)",    zh = "歷史" },
  { value = "youxi",    en = "Games (遊戲)",      zh = "遊戲" },
  { value = "kehu",     en = "Sci-Fi (科幻)",     zh = "科幻" },
  { value = "yanqing",  en = "Romance (言情)",    zh = "言情" },
  { value = "tongren",  en = "Fanfic (同人)",     zh = "同人" }
}

-- Static English lookups for fixed site vocabulary (English target only).
local STATIC_EN = {
  ["玄幻"] = "Fantasy",   ["仙俠"] = "Immortal Heroes",
  ["都市"] = "Urban",     ["歷史"] = "History",
  ["历史"] = "History",   ["遊戲"] = "Games",
  ["游戏"] = "Games",     ["科幻"] = "Sci-Fi",
  ["言情"] = "Romance",   ["同人"] = "Fanfic",
  ["連載"] = "Ongoing",   ["连载"] = "Ongoing",
  ["完結"] = "Completed", ["完结"] = "Completed",
  ["完本"] = "Completed"
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

-- Book id from ANY book-URL shape the user may paste or the engine may
-- store: /book/{id}/ (canonical), /indexlist/{id}/ (the catalog — the
-- browser's 章節目錄 target; users paste it straight from the address bar)
-- or /read/{bid}/{cid} (a chapter link).
local function bookIdFromUrl(bookUrl)
  local u = string.lower(bookUrl or "")
  local n = tonumber(string.match(u, "/book/(%d+)"))
  if n then return n end
  n = tonumber(string.match(u, "/indexlist/(%d+)"))
  if n then return n end
  return tonumber(string.match(u, "/read/(%d+)/%d+"))
end

-- The canonical book-page URL for details fetches — whatever URL shape the
-- book was added with, metadata comes from /book/{id}/ (the only page with
-- title/cover/description; /indexlist/ holds the catalog, /read/ a chapter).
local function canonicalBookUrl(bookUrl)
  local id = bookIdFromUrl(bookUrl)
  if id then return SITE .. "/book/" .. id .. "/" end
  return bookUrl
end

-- ── Covers — DIRECT from the open CDN p.69shuba.tw ──────────────────────────
-- No wsrv.nl proxy on this site (the CDN is not WAF-protected). The URL is
-- also synthesizable from the book id alone:
--   https://p.69shuba.tw/{floor(id/1000)}/{id}/{id}s.jpg
local function synthCover(bookId)
  if not bookId then return nil end
  local folder = math.floor(bookId / 1000)
  return string.format("https://p.69shuba.tw/%d/%d/%ds.jpg", folder, bookId, bookId)
end

local function coverFromImg(img, bookId)
  local u = absUrl(img)
  if u ~= "" then return u end
  return synthCover(bookId)
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
-- UTF-8 site, pages served directly (200). EdgeOne challenges surface as
-- {success=false} AFTER the engine's interceptor runs its WebView ladder
-- (trigger_markers above) — the plugin just makes normal requests and
-- handles failures with show_error.

local function httpGetPage(pathOrUrl)
  local url = pathOrUrl
  if not string_starts_with(url, "http") then url = SITE .. url end
  return http_get(url, {
    headers = {
      ["Referer"] = SITE .. "/",
      ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      ["Accept-Language"] = "zh-TW,zh;q=0.9,en-US;q=0.8"
    }
  })
end

-- ── Short-lived page cache ───────────────────────────────────────────────────
-- Opening a book fires getBookTitle / Cover / Description / Genres / Status /
-- LastUpdate / ChapterListHash separately — the cache collapses them into
-- one fetch. 60s TTL, 12 pages. Chapter text NEVER cached.
local pageCache, pageCacheOrder = {}, {}
local PAGE_TTL_MS    = 60000
local PAGE_CACHE_MAX = 12

local function pageCachePut(path, r)
  local now = nowMs()
  if not now then return end
  if pageCache[path] == nil then
    pageCacheOrder[#pageCacheOrder + 1] = path
    if #pageCacheOrder > PAGE_CACHE_MAX then
      pageCache[table.remove(pageCacheOrder, 1)] = nil
    end
  end
  pageCache[path] = { r = r, t = now }
end

local function pageCacheFresh(path)
  local now = nowMs()
  local e = pageCache[path]
  if e and now and (now - e.t) < PAGE_TTL_MS then return e.r end
  return nil
end

local function fetchPageCached(bookUrl)
  local path = string.match(bookUrl, "^https?://[^/]+(/.*)$") or bookUrl
  local hit = pageCacheFresh(path)
  if hit then return hit end
  local r = httpGetPage(path)
  if r and r.success then pageCachePut(path, r) end
  return r
end


-- ═══════════════════════════════════════════════════════════════════════════
-- Translator core (copied from novel543.lua — battle-tested through 197
-- harness checks on novel543 and the oop/bixiange deployments).
-- Source language: zh-TW (69shuba.tw indexes Traditional Chinese; some
-- synopses are Simplified — Google's dict endpoint handles both from a
-- zh-TW source tag).
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
          log_info("69shubaTw: translator disabled for 10 min (3 failed batches)")
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
  if not ok then log_info("69shubaTw: translator error: " .. tostring(res)) end
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

-- Reverse direction for search: user-language query → Chinese. The site
-- indexes Traditional titles, so zh-TW is the primary variant; the zh-CN
-- variant is retried by the caller when the first finds nothing (user
-- titles on this site may be either script).
local function translateQueryToZh(query, tlZh)
  if not trActive() then return nil end
  local ok, res = pcall(trRequestGoogle, { query }, "auto", tlZh)
  if ok and type(res) == "table" and res[1] and res[1] ~= query then return res[1] end
  return nil
end


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
-- Chapter catalog helpers
-- ═══════════════════════════════════════════════════════════════════════════
-- (The v1.1.0/v1.2.0 seed + #pb_next walk layers are GONE: on a WAF'd site
-- a per-chapter walk is a solver-storm machine — one ladder per chapter.
-- v1.3.0 fetches only the real /Indexlist/ pages, lazily, one each. The
-- v1.0.0 lesson stays: parsePage(1) NEVER returns nil — worst case an
-- empty table after show_error, never the bare "parsePage returned
-- non-table" error.)

local function cidFromUrl(u)
  return tonumber(string.match(u or "", "/read/%d+/(%d+)"))
end

-- Canonical chapter URL: strips queries/fragments/trailing slashes,
-- requires the same-book /read/{bookId}/{cid} path shape, returns a
-- SITE-absolute URL or nil. CANONICAL FORM = SITE.."/read/{bid}/{cid}"
-- (no trailing slash) — parseTocChapters, the seed and the walk all
-- produce it, so URL-set membership (walk termination, soft-serve
-- detection, cross-page dedupe) is always string-exact.
local function normalizeReadUrl(u, bookId)
  if type(u) ~= "string" then return nil end
  local idStr = tostring(bookId)
  -- path only (strip query/fragment), then strip trailing slashes
  local path = string.match(u, "^https?://[^/]+(/[^?#]*)")
    or string.match(u, "^(/[^?#]*)")
  if not path then return nil end
  path = string.gsub(path, "/+$", "")
  -- the path must be EXACTLY /read/{bid}/{cid} (rejects sub-page
  -- /read/{bid}/{cid}/{n} shapes and foreign-book links)
  local cidStr = string.match(path, "^/read/" .. idStr .. "/(%d+)$")
  if not cidStr then return nil end
  return SITE .. "/read/" .. idStr .. "/" .. cidStr
end

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
  -- /book/{id}/ carries the title whatever shape the book was added with
  local r = fetchPageCached(canonicalBookUrl(bookUrl))
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
  local r = fetchPageCached(canonicalBookUrl(bookUrl))
  if r and r.success then
    local src = html_attr(r.body, "div.bookinfo img", "src")
    local u = coverFromImg(src, bookId)
    if u then return u end
  end
  return synthCover(bookId)
end

function getBookDescription(bookUrl)
  local r = fetchPageCached(canonicalBookUrl(bookUrl))
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
  local r = fetchPageCached(canonicalBookUrl(bookUrl))
  if not (r and r.success) then return {} end
  local info = parseBookInfo(r.body)
  local out = {}
  if info.category and info.category ~= "" then
    out[#out + 1] = translateVocab(info.category)
  end
  return out
end

function getBookStatus(bookUrl)
  local r = fetchPageCached(canonicalBookUrl(bookUrl))
  if not (r and r.success) then return nil end
  local info = parseBookInfo(r.body)
  if info.status and info.status ~= "" then
    return translateVocab(info.status)
  end
  return nil
end

function getBookLastUpdate(bookUrl)
  local r = fetchPageCached(canonicalBookUrl(bookUrl))
  if not (r and r.success) then return nil end
  local info = parseBookInfo(r.body)
  if info.updated then
    local d = string.match(info.updated, "(%d%d%d%d%-%d%d%-%d%d)")
    if d then return d end
  end
  return nil
end

function getChapterListHash(bookUrl)
  local r = fetchPageCached(canonicalBookUrl(bookUrl))
  if not (r and r.success) then return nil end
  local info = parseBookInfo(r.body)
  if info.updated or info.latest then
    return tostring(info.updated or "") .. "|" .. tostring(info.latest or "")
  end
  return nil
end


-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter text — /read/{bid}/{cid}
-- ═══════════════════════════════════════════════════════════════════════════
-- Content lives in div#nr1 as <p> paragraphs. The site interleaves ad DIVs
-- (.reader-ad carrying loadAdv() scripts) BETWEEN the <p>s INSIDE the
-- content div — selecting only the <p> elements skips every one of them.
-- The h1#nr_title carries a "(cur / total)" sub-page suffix; when total > 1
-- the remaining sub-pages live at /read/{bid}/{cid}/{n} and are fetched and
-- concatenated (defensive — every chapter sampled live was (1 / 1), the
-- sub-page URL shape follows the site's family pattern; a failed sub-page
-- fetch just ends the concatenation with what was gathered).
-- Watermark lines (site domains, (本章完)) are stripped.

local SUBPAGE_CAP = 30

-- "(1 / 2)" → 1, 2 ; also tolerates "(1/2)".
local function parsePageSuffix(title)
  local cur, total = string.match(title or "", "%((%d+)%s*/%s*(%d+)%)%s*$")
  return tonumber(cur), tonumber(total)
end

local function isWatermark(p)
  if p == "(本章完)" or p == "（本章完）" then return true end
  if #p > 80 then return false end
  if string.find(p, "69shuba", 1, true) then return true end
  if string.find(p, "69shuba.tw", 1, true) then return true end
  if string.find(p, "cs76.com", 1, true) then return true end
  return false
end

local function chapterParas(html)
  local el = html_select_first(html, "div#nr1")
  if not el then el = html_select_first(html, ".nr_nr") end
  if not el then return nil end
  local paras = {}
  for _, p in ipairs(html_select(el.html, "p")) do
    local t = string_clean(p.text or "")
    paras[#paras + 1] = t
  end
  if #paras == 0 then
    local raw = string_clean(html_text("<div>" .. el.html .. "</div>"))
    if raw == "" then return nil end
    paras = { raw }
  end
  return paras
end

function getChapterText(html, url)
  if type(html) ~= "string" or html == "" then return "" end

  local paras = chapterParas(html)
  if not paras then return "" end

  -- sub-page continuation: title "(cur / total)" with total > 1
  local titleEl = html_select_first(html, "#nr_title")
  local cur, total = parsePageSuffix(titleEl and titleEl.text or "")
  if cur and total and total > 1 and cur < total and cur < SUBPAGE_CAP then
    local bid = string.match(url or "", "/read/(%d+)/%d+")
    local cid = string.match(url or "", "/read/%d+/(%d+)")
    if bid and cid then
      for n = cur + 1, math.min(total, SUBPAGE_CAP) do
        local r = httpGetPage(SITE .. "/read/" .. bid .. "/" .. cid .. "/" .. tostring(n))
        if not (r and r.success) then break end
        local more = chapterParas(r.body)
        if not more or #more == 0 then break end
        for _, t in ipairs(more) do paras[#paras + 1] = t end
      end
    end
  end

  local out = {}
  for _, p in ipairs(paras) do
    if p ~= "" and not isWatermark(p) then out[#out + 1] = p end
  end
  if #out == 0 and #paras > 0 then
    -- never return an empty chapter (a reader error) — fall back to raw
    for _, p in ipairs(paras) do
      if p ~= "" then out[#out + 1] = p end
    end
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
  return {
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
