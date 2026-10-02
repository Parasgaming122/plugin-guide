
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
