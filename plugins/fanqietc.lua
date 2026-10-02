-- ══ source part: part1_header.lua ══════════════════════════════
-- ═══════════════════════════════════════════════════════════════════════════
-- FanqieTC source plugin for NoveLA
-- Version 1.0.0 (2026-09-30)
--
-- Site: https://fanqietc.com ("番閱" / FanqieTC) — an open-source, zero-ad web
-- reader for 番茄小說 (Fanqie Novel) with a Simplified-Chinese library of
-- millions of titles (https://github.com/denniemok/fanqie-novel-reader).
--
-- HOW THIS PLUGIN WORKS (architecture, verified live 2026-09-30):
--   fanqietc.com itself is a static React SPA (Cloudflare Pages). It has NO
--   server-rendered HTML — every list/book/chapter datum comes from the site's
--   JSON backend at https://api.fanqietc.com, which fronts a pool of Fanqie
--   API mirrors (hk-1..6, cn-1..2, sg-1..2) and requires three browser-ish
--   headers (X-API-Token + Origin + Referer) to pass Cloudflare.
--   This plugin therefore talks to that same backend directly:
--     GET /recommend?section=realtime|guess         → {data:{books:[…]}}
--     GET /rank?board=recommend|finished|new|…      → {data:{books:[…]}}
--     GET /search?query=…                           → {data:{books:[…]}}
--     GET /proxy?api=<mirror>&action=detail&book_id=…       → book metadata
--     GET /proxy?api=<mirror>&action=directory&book_id=…    → all chapters
--     GET /proxy?api=<mirror>&action=content&item_id=…      → chapter text
--     GET /status                                   → per-mirror health
--   All requests are sent with the exact header set the official web client
--   sends (X-API-Token / Origin / Referer / browser UA), so Cloudflare passes
--   them on real devices exactly as it passes the site itself.
--
--   Mirror failover: the /status endpoint reports each mirror's health
--   (checked by the backend every 15 min). With the default "auto" setting
--   the plugin reads /status once per session (10-min TTL), prefers healthy
--   mirrors in the site's canonical order, and on a failed request advances
--   to the next healthy mirror (max 3 attempts, re-checking /status when the
--   healthy list is exhausted). hk-* mirrors were all down on 2026-09-30
--   while cn-1/cn-2/sg-1/sg-2 were 4/4 healthy — auto adapts as that changes.
--
-- URL SCHEME (synthetic, resolved by this plugin only):
--   Book page:    https://fanqietc.com/book/{bookId}
--   Chapter page: https://fanqietc.com/book/{bookId}/{itemId}
--   The app's chapter downloader fetches the chapter URL itself (fanqietc.com
--   serves the static SPA shell to ANY user agent — never Cloudflare-
--   challenged), then getChapterText() extracts the item id from the URL and
--   pulls the real text from api.fanqietc.com. Book-URL ids are also accepted
--   from the ORIGINAL sites the reader supports: pasting a fanqienovel.com/
--   page/{id} or tomatomtl.com/book/{id} URL into NoveLA search works too.
--
-- VERSION NOTE (IMPORTANT for NoveLA's extension manager):
--   `version` below is a LITERAL string. The app's ExtensionsManager parses
--   this line statically with a regex that only matches quoted values:
--       Regex("^\\s*version\\s*=\\s*[\"']([^\"']+)[\"']")
--   Writing `version = VERSION` (a variable) makes that regex fall back to
--   "1.0.0" while the runtime reports the real value — the mismatch confuses
--   update detection ("Extension already exists" / phantom updates). Never
--   use a variable here in ANY plugin.
--
-- FEATURES:
--   • Rankings browse: 7 boards (推荐榜 Recommended / 完本榜 Finished /
--     新书榜 New / 追更榜 Chasing / 黑马榜 Dark Horse / 巅峰榜 Peak /
--     阅读榜 Reading) — 30-100 books each.
--   • Recommendations browse: 实时热度 Realtime / 猜你喜欢 Guess.
--   • Search across the full Fanqie catalog (single result page, ~50 hits).
--   • Full chapter directories (4000+ chapter books verified) + instant
--     updates via a detail-based change hash.
--   • Translator mode (copied from the Novel543 plugin): Google dict endpoint
--     batch translation with a 6-step request chain (POST/GET × 2 hosts →
--     MyMemory → per-item gtx), a session cache, a 3-failure circuit breaker,
--     pcall armor on every entry point, and translated search queries.
--   • ⚡ Self-Test diagnostics page under Browse filters: mirror health,
--     API probes with latency, translator engine probes, and a verdict.
--
-- 1.0.0 (2026-09-30) — initial release.
--   Endpoints, header requirements, mirror pool, /status health shape,
--   creation_status semantics ('0' = 已完结 Finished, other truthy = 连载中
--   Ongoing), score/sub_info/word_number formats, directory ordering
--   (oldest → newest, extras 番外 at the end), and single-\n paragraph
--   content — all verified live against api.fanqietc.com on 2026-09-30.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Metadata ────────────────────────────────────────────────────────────────
-- NOTE: version is a LITERAL STRING on purpose — see the VERSION NOTE above.
id       = "fanqietc"
name     = "FanqieTC"
version  = "1.0.0"
baseUrl  = "https://fanqietc.com/"
language = "zh"
icon     = "https://fanqietc.com/icon_192.png"

-- ── Settings preference keys ─────────────────────────────────────────────────
local PREF_MODE    = "fanqietc_mode"        -- "raw" | "translate"
local PREF_TLANG   = "fanqietc_tlang"       -- target language code, default "en"
local PREF_TR_CH   = "fanqietc_tr_chapters" -- "1" | "0" (translate chapter titles)
local PREF_MIRROR  = "fanqietc_mirror"      -- "auto" | "default" | mirror id

local SITE = "https://fanqietc.com"
local API  = "https://api.fanqietc.com"

-- The official web client's token, extracted from the deployed bundle
-- (assets/index-*.js: BACKEND_URL / API_TOKEN constants). Public by design —
-- the whole site is an open-source client for the same backend.
local API_TOKEN = "fqtc_7nKp2mQ8xR4vL6wT1yZ3bC5dF0hJ8aE9uI3kM7"

-- Mirror pool in the site's canonical order (API_OPTIONS in the reader's
-- constants.js). "default" = let the backend pick server-side (also a valid
-- value for the api= proxy parameter).
local MIRRORS = {
  "hk-1", "hk-2", "hk-3", "hk-4", "hk-5", "hk-6",
  "cn-1", "cn-2", "sg-1", "sg-2"
}

-- ═══════════════════════════════════════════════════════════════════════════
-- Shared utilities (used by both the Translator core and the API layer)
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Clock (ms) ───────────────────────────────────────────────────────────────
-- NoveLA's os_time() returns MILLISECONDS (System.currentTimeMillis —
-- LuaSourceLoader.kt OsTimeFunction). Be robust: scale seconds up, and
-- survive builds where the function does not exist at all (cache TTLs and
-- the translator breaker then degrade to counter-based fallbacks).
-- Returns a ms clock, or nil when no clock is available.
local function nowMs()
  local ok, v = pcall(os_time)
  if ok and type(v) == "number" and v > 0 then
    if v < 100000000000 then v = v * 1000 end -- seconds → ms
    return v
  end
  return nil
end

-- True when the string contains CJK ideographs (UTF-8 lead bytes E4-E9 cover
-- U+3000–U+9FFF). Used to decide whether a search query needs translating.
local function hasCJK(s)
  return type(s) == "string" and string.find(s, "[\228-\233]") ~= nil
end

-- ══ source part: part3_translator.lua ══════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- Translator core (copied from the Novel543 plugin — engine-agnostic)
-- ═══════════════════════════════════════════════════════════════════════════
-- Engine: Google's free dict endpoint (client=dict-chrome-ex) — POST with
-- repeated q params returns one translation per q, e.g. body "q=玄幻&q=都市"
-- → ["fantasy","city"]. With sl=auto the shape nests the detected source:
-- [["fantasy","zh-CN"]] — both shapes are parsed. No API key, no OAuth.
-- Request chain, each step only on the previous step's failure:
--   1. POST translate.googleapis.com/translate_a/t
--   2. POST clients5.google.com/translate_a/t
--   3. GET  translate.googleapis.com/translate_a/t (q in the URL — same shape;
--      survives middleboxes that mangle POST bodies; skipped for long chunks)
--   4. GET  clients5.google.com/translate_a/t
--   5. MyMemory (api.mymemory.translated.net, anonymous, ~5k chars/day)
--   6. Google gtx single — per item, only the first 6 of a failed chunk
--      (blocked on some datacenter IPs but works from residential/mobile
--      networks, i.e. real devices)
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

-- Fixed site vocabulary (Fanqie categories & statuses): free for English,
-- API (cached) for other languages.
local STATIC_EN = {
  ["已完结"] = "Completed",  ["完结"] = "Completed",
  ["连载中"] = "Ongoing",    ["连载"] = "Ongoing",
  ["东方仙侠"] = "Eastern Xianxia", ["仙侠"] = "Xianxia",
  ["奇幻仙侠"] = "Fantasy Xianxia", ["玄幻"] = "Xuanhuan (Eastern Fantasy)",
  ["东方玄幻"] = "Eastern Fantasy", ["都市"] = "Urban",
  ["都市日常"] = "Urban Slice of Life", ["都市高武"] = "Urban Martial Arts",
  ["历史"] = "Historical",  ["古代言情"] = "Historical Romance",
  ["现代言情"] = "Modern Romance", ["科幻"] = "Sci-Fi",
  ["悬疑"] = "Mystery",     ["灵异"] = "Supernatural",
  ["游戏"] = "Games",       ["体育"] = "Sports",
  ["军事"] = "Military",    ["轻小说"] = "Light Novel",
  ["现实"] = "Realistic",   ["成功励志"] = "Success & Inspirational",
  ["悬疑灵异"] = "Mystery & Supernatural", ["衍生同人"] = "Fanfiction",
  ["武侠"] = "Wuxia (Martial Heroes)", ["奇幻"] = "Western Fantasy",
  ["穿越"] = "Transmigration", ["重生"] = "Rebirth",
  ["系统"] = "System",      ["种田"] = "Farming",
  ["架空"] = "Alternate World", ["脑洞"] = "High Concept",
  ["末世"] = "Post-Apocalyptic", ["无限流"] = "Infinite Flow",
  ["克苏鲁"] = "Cthulhu",   ["诸天无限"] = "Multiverse"
}

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

-- Filter label builder. Labels follow the Mode setting — they rebuild when
-- the source screen is (re)opened (the ViewModel fetches getFilterList() once
-- per catalog-screen session; the adapter itself has no cache):
--   raw mode       → "English (中文)"   (bilingual — keeps the site flavor)
--   translate mode → "English"          (English only, no Chinese counterpart)
-- Latin-only zh values collapse to the English name in both modes.
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
  if trCacheCount > 4000 then return end -- hard cap; a session never gets near it
  if trCache[k] == nil then trCacheCount = trCacheCount + 1 end
  trCache[k] = v
end

-- Parse the /t endpoint response. Accepted shapes (Lua 1-based):
--   {"t1","t2"}                (explicit sl)
--   {{"t1","src"},"t2","src"}} (sl=auto)
--   {"t1"}                     (single q, either sl)
-- Empty strings are VALID (Google returns "" for an empty q) — the caller
-- maps them back to the original text. Returns an array of exactly `want`
-- strings, or nil when the response is too short / malformed.
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

-- GET variant of the /t endpoint with q params in the URL — same response
-- shape as POST. Splits the chunk into groups that keep the URL under
-- ~1400 chars (an 18-title Chinese page encodes to ~2k chars, over both
-- conservative URL limits and the old hard cap — splitting keeps the GET
-- fallback usable for real pages instead of silently skipping it).
-- Returns a full-length array (originals for empty slots), or nil on failure.
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

-- Steps 1-4 of the request chain: Google dict endpoint, POST then GET, on
-- both hosts. Returns an array of #texts strings, or nil.
local function trRequestGoogle(texts, sl, tl)
  local qs = {}
  for _, t in ipairs(texts) do qs[#qs + 1] = "q=" .. url_encode(t) end
  local qstr = table.concat(qs, "&")
  for _, host in ipairs(TR_HOSTS) do
    local url = host .. "/translate_a/t?client=dict-chrome-ex&sl=" .. sl .. "&tl=" .. url_encode(tl)
    -- POST (q params in the body)
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
    -- GET (q params in the URL, auto-split for length)
    local res = trGetChunk(host, texts, sl, tl)
    if res then return res end
  end
  return nil
end

-- Step 6: classic gtx single endpoint — one text per request. Blocked from
-- some datacenter IPs but works from residential/mobile networks (i.e. real
-- devices), so it is the last Google resort before giving up on an item.
-- Response: [[["translation","original",...],...],...] — take j[1][1][1].
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

-- MyMemory fallback — per-item GET, short texts only (anonymous daily quota).
-- Returns an array of #texts entries (originals where an item failed), or
-- NIL when nothing at all was translated — the caller treats nil as a real
-- failure (circuit-breaker tick + gtx rescue). Returning a full array of
-- originals here would make every batch look "successful" and the breaker
-- would never trip.
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

-- Translate an array of strings; ALWAYS returns an array of the same length
-- (failed/uncached items pass through unchanged). pcall-armored: a Lua error
-- anywhere inside (old app build, changed API shape, anything) degrades to
-- the original texts instead of failing the page.
local function translateBatchImpl(texts)
  local n = #texts
  if n == 0 then return texts end
  if not trActive() then
    trProbeCount = trProbeCount + 1 -- breaker tick (also the no-clock probe)
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
      if not usedFallback then trFailStreak = 0 end -- full success resets the breaker
      for k = 1, #chunk do
        local v = res[k]
        if v == nil or v == "" then v = chunk[k] end -- empty result → original
        out[pIdx[base + k - 1]] = v
        trCachePut(chunk[k], v)
      end
    else
      -- Last resort: per-item gtx single for the first items of the chunk
      -- (covers 1-item calls fully; caps the worst-case latency for pages).
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
          out[pIdx[base + k - 1]] = chunk[k] -- pass-through on failure
        end
      end
      for k = cap + 1, #chunk do
        out[pIdx[base + k - 1]] = chunk[k]
      end
      if not anyOk then
        trFailStreak = trFailStreak + 1
        if trFailStreak >= TR_FAIL_LIMIT then
          trDisabledAt = nowMs() or 0
          log_info("fanqietc: translator disabled for 10 min (3 failed batches)")
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
  if not ok then log_info("fanqietc: translator error: " .. tostring(res)) end
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

-- Reverse direction for search: user-language query → Chinese.
-- sl=auto → response nests detected source, parseTrArray handles it.
local function translateQueryToZh(query, tl)
  if not trActive() then return nil end
  local ok, res = pcall(trRequestGoogle, { query }, "auto", tl)
  if ok and type(res) == "table" and res[1] and res[1] ~= query then return res[1] end
  return nil
end

-- ══ source part: part2_api.lua ══════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- API layer — auth headers, mirror selection with /status health, failover
-- ═══════════════════════════════════════════════════════════════════════════

-- Header set the official web client sends on every backend call. All three
-- extra headers are REQUIRED: without them Cloudflare answers the challenge
-- page (verified live — dropping any one of UA/Origin/Referer → 403).
local API_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

local function apiHeaders()
  return {
    ["X-API-Token"] = API_TOKEN,
    ["Origin"]      = "https://fanqietc.com",
    ["Referer"]     = "https://fanqietc.com/",
    ["User-Agent"]  = API_UA,
    ["Accept"]      = "application/json"
  }
end

-- ── Mirror health (/status) ──────────────────────────────────────────────────
-- GET /status → {data:{apis:[{id,overall:"up"|"down",endpoints:{…}}]}}
-- TTL-cached (10 min, mirroring the backend's own 15-min recheck interval).
local statusCache = { at = 0, list = nil } -- list = array of healthy mirror ids

local function fetchMirrorHealth()
  local now = nowMs()
  if statusCache.list and now and (now - statusCache.at) < 600000 then
    return statusCache.list
  end
  local r = http_get(API .. "/status", { headers = apiHeaders() })
  local healthy = {}
  if r and r.success and type(r.body) == "string"
     and string.sub(r.body, 1, 1) == "{" then
    local j = json_parse(r.body)
    if type(j) == "table" and type(j.data) == "table"
       and type(j.data.apis) == "table" then
      -- order the healthy set by the canonical MIRRORS order
      local up = {}
      for _, a in ipairs(j.data.apis) do
        if type(a) == "table" and a.overall == "up" and type(a.id) == "string" then
          up[a.id] = true
        end
      end
      for _, id in ipairs(MIRRORS) do
        if up[id] then healthy[#healthy + 1] = id end
      end
    end
  end
  statusCache.at = now or 0
  statusCache.list = healthy
  return healthy
end

-- ── Preferred mirror (setting) ───────────────────────────────────────────────
local function getMirrorSetting()
  local ok, v = pcall(get_preference, PREF_MIRROR)
  if ok and type(v) == "string" and v ~= "" and v ~= "auto" then
    return v -- "default" or a specific mirror id
  end
  return "auto"
end

-- ── Request plumbing ─────────────────────────────────────────────────────────
-- GET a full backend URL (no failover — the failover wrapper lives below).
-- Returns the response's `data` field, or nil on any non-JSON/failed answer
-- (Cloudflare challenge pages and the backend's plain-text "error code: 502"
-- bodies both land in the nil path, which is exactly what triggers failover).
local function apiGetUrl(url)
  local r = http_get(url, { headers = apiHeaders() })
  if not (r and r.success and type(r.body) == "string") then return nil end
  if string.sub(r.body, 1, 1) ~= "{" and string.sub(r.body, 1, 1) ~= "[" then
    return nil
  end
  local j = json_parse(r.body)
  if type(j) ~= "table" then return nil end
  return j.data
end

-- Build a proxy URL for a given mirror.
local function proxyUrl(mirror, action, params)
  local qs = "api=" .. url_encode(mirror) .. "&action=" .. url_encode(action)
  for k, v in pairs(params or {}) do
    if v ~= nil and v ~= "" then
      qs = qs .. "&" .. url_encode(k) .. "=" .. url_encode(tostring(v))
    end
  end
  return API .. "/proxy?" .. qs
end

-- Session state for the failover chain.
local mirrorSession = {
  chain    = nil,  -- array of candidate mirrors for this session
  idx      = 0,    -- current position in the chain
  builtAt  = 0,    -- when the chain was (re)built (ms) — rebuilds on exhaustion
  lastGood = nil   -- stick to a mirror that works until it fails
}

-- Build the candidate chain: the user's fixed mirror alone, or the healthy
-- mirrors (canonical order) followed by "default" as the server-side gamble.
local function buildMirrorChain(force)
  local now = nowMs() or 0
  if not force and mirrorSession.chain
     and (now - mirrorSession.builtAt) < 600000 then
    return
  end
  local setting = getMirrorSetting()
  if setting ~= "auto" then
    mirrorSession.chain   = { setting }
    mirrorSession.lastGood = nil
  else
    local healthy = fetchMirrorHealth()
    local chain = {}
    if mirrorSession.lastGood then chain[#chain + 1] = mirrorSession.lastGood end
    for _, id in ipairs(healthy) do
      if id ~= mirrorSession.lastGood then chain[#chain + 1] = id end
    end
    chain[#chain + 1] = "default" -- backend-side pick when everything else fails
    if #chain == 1 and chain[1] == "default" then
      -- /status unreachable and nothing cached: try the canonical order raw
      for _, id in ipairs(MIRRORS) do chain[#chain + 1] = id end
    end
    mirrorSession.chain = chain
  end
  mirrorSession.idx     = 1
  mirrorSession.builtAt = now
end

-- GET a proxy action with mirror failover. Returns the `data` table or nil.
-- Walks the candidate chain (healthy mirrors first); a failed request
-- advances to the next mirror. Budget-capped at 6 total attempts across both
-- rounds (a fully-dead pool of 7s-timeout mirrors must not stall a chapter
-- read for minutes); on exhaustion re-checks /status once (force rebuild).
local function proxyAction(action, params)
  local attempts = 0
  for round = 1, 2 do
    buildMirrorChain(round == 2)
    while mirrorSession.idx <= #mirrorSession.chain and attempts < 6 do
      local mirror = mirrorSession.chain[mirrorSession.idx]
      attempts = attempts + 1
      local data = apiGetUrl(proxyUrl(mirror, action, params))
      if data ~= nil then
        mirrorSession.lastGood = mirror
        return data
      end
      mirrorSession.idx = mirrorSession.idx + 1
    end
    if attempts >= 6 then break end
  end
  return nil
end

-- GET a DIRECT backend path (/rank, /recommend, /search) with retries.
-- These endpoints have NO api= mirror parameter — the backend picks their
-- upstream itself, and when that upstream is flapping they answer
-- 503 {"error":"Upstream temporarily unavailable"} for minutes at a time
-- (the official web client shows its 搜尋失敗/獲取榜單失敗 errors in exactly
-- these windows). The plugin rides out short blips with spaced retries —
-- a real user hitting refresh behaves the same way — and reports failure
-- so the catalog can show an actionable message instead of a blank page.
-- Returns the `data` table, or nil + lastHttpCode.
local DIRECT_RETRIES   = 3
local DIRECT_RETRY_MS  = 1500

local function apiGetDirect(path)
  local lastCode = 0
  for attempt = 1, DIRECT_RETRIES do
    if attempt > 1 then pcall(sleep, DIRECT_RETRY_MS) end
    local r = http_get(API .. path, { headers = apiHeaders() })
    if r and r.success and type(r.body) == "string"
       and (string.sub(r.body, 1, 1) == "{" or string.sub(r.body, 1, 1) == "[") then
      local j = json_parse(r.body)
      if type(j) == "table" then
        if type(j.data) == "table" then return j.data, 200 end
        return nil, 200 -- 200 but no data field — treat as failure, no point retrying
      end
    end
    if r and type(r.code) == "number" then lastCode = r.code end
  end
  return nil, lastCode
end

-- ── Object caches (session-scoped) ──────────────────────────────────────────
-- Opening a book fires 6-8 separate Lua calls (title, cover, description,
-- genres, status, last update, rating, chapter-list hash) — all answered by
-- ONE detail request through this cache. Same for the directory (chapter
-- list + first chapter read). 5-min TTL, LRU-capped at 12 entries, bypassed
-- entirely when no clock is available.
local DETAIL_TTL_MS   = 300000
local DIRECTORY_TTL_MS = 300000
local CACHE_MAX       = 12

local detailCache, detailOrder     = {}, {}
local dirCache, dirOrder           = {}, {}

local function cacheGet(cache, order, key, ttl)
  local now = nowMs()
  if not now then return nil end
  local e = cache[key]
  if e and (now - e.t) < ttl then return e.v end
  return nil
end

local function cachePut(cache, order, key, value)
  local now = nowMs()
  if not now then return end
  if cache[key] == nil then
    order[#order + 1] = key
    if #order > CACHE_MAX then cache[table.remove(order, 1)] = nil end
  end
  cache[key] = { v = value, t = now }
end

-- Book id from a book or chapter URL (also accepts the original-site shapes
-- fanqienovel.com/page/{id} and tomatomtl.com/book/{id}).
local function bookIdFromUrl(url)
  return string.match(url or "", "/book/(%d+)")
      or string.match(url or "", "/page/(%d+)")
end

local function fetchBookDetail(bookId)
  local c = cacheGet(detailCache, detailOrder, bookId, DETAIL_TTL_MS)
  if c ~= nil then return c end
  local d = proxyAction("detail", { book_id = bookId })
  if type(d) == "table" then cachePut(detailCache, detailOrder, bookId, d) end
  return d
end

local function fetchDirectory(bookId)
  local c = cacheGet(dirCache, dirOrder, bookId, DIRECTORY_TTL_MS)
  if c ~= nil then return c end
  local d = proxyAction("directory", { book_id = bookId })
  local items = (type(d) == "table" and type(d.item_data_list) == "table")
                and d.item_data_list or nil
  if items then cachePut(dirCache, dirOrder, bookId, items) end
  return items
end

-- ── Pure-Lua epoch → "YYYY-MM-DD" (no os.date in the sandbox) ───────────────
-- Howard Hinnant's civil-from-days algorithm; input = unix seconds (string or
-- number, UTC — dates only, timezone shifts would only move the day boundary).
local function epochToDate(sec)
  local s = tonumber(sec)
  if not s or s <= 0 then return nil end
  local days = math.floor(s / 86400)
  local z = days + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524)
                          - math.floor(doe / 146096)) / 365)
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local d = doy - math.floor((153 * mp + 2) / 5) + 1
  local m = mp + (mp < 10 and 3 or -9)
  if m <= 2 then y = y + 1 end
  return string.format("%04d-%02d-%02d", y, m, d)
end

-- Normalize a backend list item into NoveLA's BookResult row.
-- rating: "9.3" → shown as-is (score is a 0-10 scale like novel543's /10).
local function toCatalogItem(b)
  if type(b) ~= "table" then return nil end
  local id = tostring(b.book_id or "")
  if id == "" then return nil end
  local title = tostring(b.book_name or b.original_book_name or id)
  local sub = ""
  if type(b.sub_info) == "string" and b.sub_info ~= "" then
    sub = " · " .. b.sub_info
  elseif type(b.author) == "string" and b.author ~= "" then
    sub = " · " .. b.author
  end
  local rating = nil
  if b.score and tostring(b.score) ~= "0" and tostring(b.score) ~= "" then
    rating = tostring(b.score)
  end
  return {
    title  = title .. sub,
    url    = SITE .. "/book/" .. id,
    cover  = tostring(b.thumb_url or ""),
    rating = rating
  }
end

local function translateCatalogItems(items)
  if not (trActive() and type(items) == "table" and #items > 0) then return items end
  local titles = {}
  for i = 1, #items do titles[i] = items[i].title end
  local tr = translateBatch(titles)
  for i = 1, #items do items[i].title = tr[i] end
  return items
end

local function booksToPagedList(books)
  local items = {}
  if type(books) == "table" then
    for i = 1, #books do
      local it = toCatalogItem(books[i])
      if it then items[#items + 1] = it end
    end
  end
  translateCatalogItems(items)
  return { items = items, hasNext = false }
end

-- ══ source part: part4_catalog.lua ══════════════════════════════

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

-- ══ source part: part5_book.lua ══════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- Book details (one cached /proxy?action=detail request answers them all)
-- ═══════════════════════════════════════════════════════════════════════════

function getBookTitle(bookUrl)
  local d = fetchBookDetail(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return nil end
  local title = tostring(d.book_name or d.original_book_name or "")
  if title == "" then return nil end
  if trActive() then
    local tr = translateOne(title)
    if tr and tr ~= title then return tr .. " (" .. title .. ")" end
  end
  return title
end

function getBookCoverImageUrl(bookUrl)
  local d = fetchBookDetail(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return nil end
  -- Signed CDN URL (fqnovelpic.com, x-expires months out) — used DIRECTLY:
  -- the image loader is exempt from the WebView bypass, and these signed
  -- hosts have never been observed challenging image requests.
  local u = tostring(d.thumb_url or d.audio_thumb_uri or "")
  if u == "" then return nil end
  return u
end

function getBookDescription(bookUrl)
  local d = fetchBookDetail(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return nil end
  local desc = tostring(d.abstract or "")
  if desc == "" then return nil end
  if trActive() then
    if #desc > 4000 then desc = string.sub(desc, 1, 4000) end
    desc = translateOne(desc)
  end
  return desc
end

-- tags = comma-separated Chinese category names ("东方仙侠,玄幻,仙侠").
function getBookGenres(bookUrl)
  local d = fetchBookDetail(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return {} end
  local genres = {}
  local tags = tostring(d.tags or d.category or "")
  for _, t in ipairs(string_split(tags, ",")) do
    t = string_trim(t)
    if t ~= "" then genres[#genres + 1] = translateVocab(t) end
  end
  if #genres == 0 then
    local cat = tostring(d.category or "")
    if cat ~= "" then genres[1] = translateVocab(cat) end
  end
  return genres
end

-- Score: 0-10 scale string ("9.3"); "0" = unscored → nil.
function getBookRating(bookUrl)
  local d = fetchBookDetail(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return nil end
  local s = tostring(d.score or "")
  if s == "" or s == "0" then return nil end
  return s
end

-- creation_status: '0' = 已完结 Finished, any other truthy value = 连载中
-- Ongoing (verified against the reader's bookInfo.js normalization).
function getBookStatus(bookUrl)
  local d = fetchBookDetail(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return nil end
  local s = tostring(d.creation_status or "")
  if s == "" then return nil end
  if s == "0" then return translateVocab("已完结") end
  return translateVocab("连载中")
end

-- last_publish_time = unix seconds (string) → "YYYY-MM-DD".
function getBookLastUpdate(bookUrl)
  local d = fetchBookDetail(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return nil end
  return epochToDate(d.last_publish_time)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter list (directory action — ALL chapters in one response)
-- ═══════════════════════════════════════════════════════════════════════════

function getChapterList(bookUrl)
  local bookId = bookIdFromUrl(bookUrl)
  if not bookId then return {} end
  local items = fetchDirectory(bookId)
  if type(items) ~= "table" then return {} end

  local chapters = {}
  for i = 1, #items do
    local it = items[i]
    if type(it) == "table" and type(it.item_id) == "string" then
      chapters[#chapters + 1] = {
        title = tostring(it.title or it.item_id),
        url   = SITE .. "/book/" .. bookId .. "/" .. it.item_id
      }
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

-- Change hash from the (cached) detail: chapter count + last publish time.
-- Both move whenever a new chapter or 番外 drops — enough for the app's
-- "this book has updates" check without re-downloading the whole directory.
function getChapterListHash(bookUrl)
  local bookId = bookIdFromUrl(bookUrl)
  if not bookId then return nil end
  local d = fetchBookDetail(bookId)
  if type(d) ~= "table" then return nil end
  local h = tostring(d.content_chapter_number or "") .. "|" ..
            tostring(d.last_publish_time or "")
  if h == "|" then return nil end
  return h
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter text
-- ═══════════════════════════════════════════════════════════════════════════
-- The app downloads the chapter URL first (fanqietc.com → static SPA shell,
-- never Cloudflare-challenged) and hands the HTML + URL to this function.
-- The REAL text lives at api.fanqietc.com (content action), keyed by the
-- item id embedded in the URL — fetched here with the auth header set.
-- Content arrives as one paragraph per "\n", which is exactly how NoveLA's
-- reader splits chapter bodies (TextToItemsConverter: split("\n")) — only
-- blank-line noise and stray spaces are cleaned.

function getChapterText(html, url)
  local itemId = string.match(url or "", "/book/%d+/(%d+)")
  if not itemId then return nil end

  local c = proxyAction("content", { item_id = itemId })
  if type(c) ~= "table" or type(c.content) ~= "string" then
    -- surface a readable error instead of a silent empty chapter: every
    -- mirror (incl. the backend's own 'default' pick) refused the request.
    show_error("FanqieTC: chapter unavailable",
               "The backend and all its mirrors refused this chapter request.\n\n" ..
               "Try again in a minute, or open this source's Settings and pick " ..
               "a different API mirror (cn-1 / cn-2 / sg-1 / sg-2 were healthy " ..
               "at release time). The ⚡ Self-Test page (Browse → Page → " ..
               "Self-Test) shows live mirror health.")
    return nil
  end

  -- Re-flow: strip blank lines, trim each paragraph, drop the leading space
  -- some mirrors prepend to the first line.
  local lines = string_split(c.content, "\n")
  local out = {}
  for _, ln in ipairs(lines) do
    ln = string_trim(ln)
    if ln ~= "" then out[#out + 1] = ln end
  end
  if #out == 0 then return nil end
  return table.concat(out, "\n")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Settings schema
-- ═══════════════════════════════════════════════════════════════════════════

function getSettingsSchema()
  local mirrorOptions = {
    { value = "auto",    label = "Auto — health-checked (recommended)" },
    { value = "default", label = "default — let the backend pick" }
  }
  for _, id in ipairs(MIRRORS) do
    mirrorOptions[#mirrorOptions + 1] = { value = id, label = id }
  end

  return {
    {
      key = PREF_MIRROR,
      type = "select",
      label = "API Mirror (API 鏡像)",
      current = getMirrorSetting(),
      options = mirrorOptions
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

