-- ═══════════════════════════════════════════════════════════════════════════
-- 69書吧 (69shuba.tw) source plugin for NoveLA
-- Version 1.0.0 (2026-09-20)
--
-- NOT the same site as the existing "69shuba" plugin (www.69shuba.com —
-- Simplified, GBK, /book/{id}.htm URLs, different library): 69shuba.tw is
-- the Traditional-Chinese portal of the family — UTF-8, its own URL scheme
-- (/book/{id}/, /indexlist/{id}/, /read/{bid}/{cid}) and a DIFFERENT book
-- database (book 342441 exists here, 404s on .com). Hence a separate
-- plugin id: "69shubaTw".
--
-- ANTI-BOT — Tencent EdgeOne "aegis" captcha, NOT Cloudflare:
--   Server: Edge/1.1.28. From datacenter IPs every path answers 403 with a
--   custom human-verification page (reCAPTCHA v3 checkbox + Turnstile
--   script; the token POSTs to /aegis_captcha_verify?rule_uuid=…; verified
--   cookies __ct_ac_cpg + __ct_cya_ckt follow). The engine's stock CF
--   detector does NOT recognize it (Server ≠ cloudflare) — so this plugin
--   registers cf_options.trigger_markers. With those, the app's interceptor
--   runs its WebView bypass ladder on the challenge page: solve the
--   "I'm not a robot" checkbox once in the WebView (it auto-passes on real
--   devices), tap Done, and the retry carries the __ct_* cookies. On
--   residential IPs (typical phones) the site usually serves pages with no
--   challenge at all.
--   Path asymmetry (verified via the Google-Translate proxy): /, /book/*,
--   /read/*, /search/*, /fenlei/*, /quanben/* pass from Google's IPs while
--   /indexlist/* (the chapter catalog) is challenged even there — expect the
--   catalog to be the first surface to need the WebView solve.
--
-- COVERS: served by the open CDN p.69shuba.tw (no challenge, verified) —
--   DIRECT image URLs, no wsrv.nl proxy (deliberately, per user request —
--   and unlike wuxiabox/wtrlab/novel543/oop whose CDNs sit behind WAFs).
--   Deterministic pattern: https://p.69shuba.tw/{id÷1000}/{id}/{id}s.jpg
--   (verified on 342441/337296/338557/400577) — synthesized when the book
--   page cannot be fetched.
--
-- WHAT'S IN v1.0.0:
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
--   • Chapter catalog /indexlist/{id}/ — WAF-hard path. The parser is
--     layout-agnostic: it collects EVERY anchor whose href matches
--     /read/{bookId}/{cid}, dedupes by cid and sorts by cid (verified
--     reading order: ch1 890315 → ch2 890316 → … → ch450 4001259),
--     which survives any ul/table/div markup the page uses. Paginated
--     walks are solver-safe (the oop.tw v1.1.0 lessons):
--       - parsePage(bookUrl, page) — engine paginated API; the engine
--         stops at the first failed page, refreshes are incremental.
--       - getChapterList (older engines) ABORTS at the first failed page.
--       - Persistent per-book page cache (set_preference): interior pages
--         are immutable (the site only appends chapters), so they are
--         served with zero network; the walk resumes where it stopped and
--         a stale copy is served when the site is unreachable.
--       - The page-N URL template is learned from page 1's 下一页 link and
--         persisted (falls back to /indexlist/{id}/{N}/ — the site-wide
--         pager pattern).
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
--   • TOC:            /indexlist/{id}/ (+ /{N}/ pages — inferred; the
--                     path is routed (WAF 403, not 404) and every other
--                     paginated surface on the site uses this shape).
--   • Chapter page:   h1#nr_title "第N章 …(cur / total)", div#nr1 <p>,
--                     #pb_prev/#pb_mulu/#pb_next (上一章/目錄/下一章),
--                     #startread ch1 = /read/342441/890315.
--   • Covers:         //p.69shuba.tw/{id÷1000}/{id}/{id}s.jpg — open CDN.
--   • Author pages:   /author/{urlencoded name}/ (not used by the plugin).
--   • No JSON API:    classic PHP/Jieqi-style rendering (addbookcase,
--                     bookcase, recentread are cookie features — skipped).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Metadata ────────────────────────────────────────────────────────────────
local VERSION = "1.1.0"
id       = "69shubaTw"
name     = "69書吧 (69shuba.tw)"
version  = VERSION
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
    "Please complete human verification" -- the challenge page <title>
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

-- Book id from any /book/{id} URL shape (…/342441/ or …/342441).
local function bookIdFromUrl(bookUrl)
  return tonumber(string.match(bookUrl or "", "/book/(%d+)"))
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
      ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
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
