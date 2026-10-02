-- ═══════════════════════════════════════════════════════════════════════════
-- OOP 小說網 (oop.tw) source plugin for NoveLA
-- Version 1.0.0 (2026-09-19)
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
local VERSION = "1.0.0"
id       = "oop"
name     = "OOP 小說網"
version  = VERSION
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
