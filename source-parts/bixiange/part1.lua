-- ═══════════════════════════════════════════════════════════════════════════
-- Bixiange (笔仙阁) source plugin for NoveLA
-- Version 1.0.0 (2026-09-19)
--
-- Site: https://www.bixiange.top/ — 笔仙阁, a free Chinese novel site
-- (GB2312-encoded EmpireCMS). Mirror: https://bxg123.cc (verified live
-- copy of the SAME database — identical book ids AND identical search
-- searchids, so every path is portable between the two hosts).
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
--   • Books keep EXACTLY the URL the site links to: newer books live at
--     `/cat/{id}/` (trailing slash) while older books live at
--     `/cat/{id}.html` — and the /cat/{id}/ form 403s for the .html
--     books (live-verified), so URLs are never normalized.
--   • Chapters: the full catalog is on the book page (`.catalog ul li a`,
--     one page, titles “第N节”). Two chapter URL generations:
--     new books `/cat/id/index/N.html`, old books `/cat/id/N.html` —
--     both serve `div#mycontent` paragraphs. Chapter 1 embeds a TXT
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
local VERSION = "1.0.0"
id       = "bixiange"
name     = "Bixiange 笔仙阁"
version  = VERSION
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
