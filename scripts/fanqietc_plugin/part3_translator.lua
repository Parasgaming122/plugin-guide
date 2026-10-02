
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
