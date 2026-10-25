-- ══ source part: part1_header.lua ══════════════════════════════
-- ═══════════════════════════════════════════════════════════════════════════
-- FanqieNovel source plugin for NoveLA
-- Version 1.0.0 (2026-10-01)
--
-- Site: https://fanqienovel.com — the OFFICIAL 番茄小说 web reader (ByteDance).
-- Simplified-Chinese library of millions of titles, same book-id space as
-- the Fanqie app and every third-party Fanqie reader (fanqietc.com included).
--
-- HOW THIS PLUGIN WORKS (architecture, verified live 2026-10-01):
--   fanqienovel.com is a React site, but the pages this plugin uses are
--   SERVER-RENDERED — every datum ships inside a JSON blob embedded in the
--   HTML:  window.__INITIAL_STATE__ = { ... }
--     GET /page/{bookId}        → state.page: full metadata + the COMPLETE
--                                 chapter list (chapterListWithVolume, ordered
--                                 by volume; verified with a 4051-chapter book)
--     GET /reader/{itemId}      → state.reader.chapterData: the chapter text
--                                 itself, embedded in the page
--     GET /rank                 → state.rank.book_list: top-10 board
--     GET /                     → state.home: editor picks / weekly / boys /
--                                 girls / latest-updates lists (~50 books)
--     GET /api/reader/directory/detail?bookId=… → TOC fallback (pure JSON)
--   The site serves these pages to EVERY user agent (verified: browser,
--   okhttp, curl, and none at all — no Cloudflare challenge, no cookie
--   requirements), so the app's built-in downloader can fetch chapter URLs
--   directly.
--
--   THE ANTI-SCRAPE FONT (the hard part, solved):
--   All user-visible text (titles, abstracts, chapter bodies) is partly
--   written in Private-Use-Area codepoints (U+E3E8–U+E55B, 362 glyphs). The
--   page also loads a custom webfont whose cmap renders those codepoints as
--   the REAL characters — humans see perfect Chinese, scrapers see garbage.
--   The font is a static subset of SourceHanSansSC-Normal and has been the
--   same file across every chapter/book checked (hash dc027189e0ba4cd).
--   This plugin ships the complete 362-entry PUA→char table, derived by
--   rendering each glyph and matching outlines against Noto Sans SC (the
--   same typeface) at weight 350, then verified live: full chapters of
--   multiple books, 4000+ chapter titles, rank/home titles and abstracts
--   all decode to flawless Chinese. At runtime the plugin also checks the
--   font URL embedded in each reader page — if the site ever rotates the
--   font, content automatically falls back to the mirror path (below)
--   instead of returning garbage.
--
--   CHAPTER LOCKS (VIP chapters) + the fanqietc fallback:
--   Popular books lock chapters (verified: 凡骨 locks from ch 11) — the
--   /reader page then embeds only a ~200-char preview. Detection is exact:
--   chapterData.isChapterLock, plus decoded-length vs chapterWordNumber.
--   For locked chapters the plugin falls back to the open-source
--   api.fanqietc.com backend (the fanqie-novel-reader project's proxy of
--   the Fanqie app API), which returns the full plain text (verified: the
--   same locked chapter returns 2197 chars vs the 200-char web preview).
--   The same backend also powers SEARCH, because the official site's
--   search endpoint is client-side-only (blocked without their JS).
--
-- URL SCHEME:
--   Book page:    https://fanqienovel.com/page/{bookId}   (the site's own)
--   Chapter page: https://fanqienovel.com/reader/{itemId} (the site's own)
--   Both are real site URLs the app downloads directly. Search also accepts
--   pasted URLs: fanqienovel.com/page/…, /reader/…, fanqietc.com/book/…,
--   tomatomtl.com/book/… (same id space), or a bare 15-20-digit book id.
--
-- VERSION NOTE (IMPORTANT for NoveLA's extension manager):
--   `version` below is a LITERAL string. The app's ExtensionsManager parses
--   this line statically with a regex that only matches quoted values.
--   Writing `version = VERSION` (a variable) makes update detection break
--   ("Extension already exists" / phantom updates). Never use a variable.
--
-- FEATURES:
--   • Browse: Editor Picks / Weekly Hot / Boys / Girls / Latest Updates
--     (~50 books from the homepage) + the official Top-10 Rank board.
--   • Search across the full Fanqie catalog (~50 hits per query).
--   • Full chapter directories (4051-chapter book verified) straight from
--     the book page — one request answers detail AND the TOC.
--   • Chapter text from the official site with anti-scrape font decoding;
--     locked VIP chapters transparently fetched via the mirror backend.
--   • Translator mode (copied from the Novel543 plugin): Google dict batch
--     translation with a 6-step request chain, session cache, 3-failure
--     circuit breaker, pcall armor, translated search queries.
--   • ⚡ Self-Test diagnostics page: site probes, font-map check, PUA decode
--     verification, mirror-backend probes, translator engines, verdict.
--
-- 1.0.0 (2026-10-01) — initial release.
--   SSR state shapes, PUA font table (362/362 glyphs), lock detection via
--   isChapterLock + chapterWordNumber, directory-API fallback, mirror
--   content fallback, creationStatus semantics ('0' = 已完结 Finished,
--   '1' = 连载中 Ongoing — both verified), UA tolerance (okhttp/curl/none
--   all served), and single-\n paragraph content — verified live against
--   fanqienovel.com + api.fanqietc.com on 2026-10-01.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Metadata ────────────────────────────────────────────────────────────────
-- NOTE: version is a LITERAL STRING on purpose — see the VERSION NOTE above.
id       = "fanqienovel"
name     = "FanqieNovel"
version  = "1.0.0"
baseUrl  = "https://fanqienovel.com/"
language = "zh"
icon     = "https://p1-tt.byteimg.com/origin/novel-static/a3621391ca2e537045168afda6722ee9"

-- ── Settings preference keys ─────────────────────────────────────────────────
local PREF_MODE  = "fanqienovel_mode"         -- "raw" | "translate"
local PREF_TLANG = "fanqienovel_tlang"        -- target language code, default "en"
local PREF_TR_CH = "fanqienovel_tr_chapters"  -- "1" | "0" (translate chapter titles)

local SITE = "https://fanqienovel.com"

-- Mirror backend (fanqie-novel-reader project, open source) used ONLY for
-- search and locked-chapter fallback. Same token the official web client
-- sends (public by design in the site's bundle).
local MIRROR_API   = "https://api.fanqietc.com"
local MIRROR_TOKEN = "fqtc_7nKp2mQ8xR4vL6wT1yZ3bC5dF0hJ8aE9uI3kM7"
-- Mirror attempt order for the content fallback. Verified 2026-10-01:
-- cn-2 fully healthy; cn-1 detail/directory only; hk-1..6 down; the rest
-- flapping. "default" lets the backend pick server-side.
local MIRROR_ORDER = { "cn-2", "default", "cn-1", "sg-2", "sg-1" }

-- The anti-scrape font file this plugin's PUA table was built from.
-- Extracted at runtime from state.common.css of every reader page; if the
-- site rotates the font, chapter text switches to the mirror fallback.
local KNOWN_FONT_HASH = "dc027189e0ba4cd"

-- ═══════════════════════════════════════════════════════════════════════════
-- Shared utilities (used by the Translator core and the site layer)
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Clock (ms) ───────────────────────────────────────────────────────────────
-- NoveLA's os_time() returns MILLISECONDS. Be robust: scale seconds up, and
-- survive builds where the function does not exist (caches then degrade to
-- unbounded, the breaker to counter-based fallbacks).
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

-- urlencode/split/trim are NOT defined here: NoveLA provides url_encode,
-- string_split(s, sep) and string_trim(s) as plugin-API globals (verified
-- against LuaSourceLoader.kt). Using the built-ins keeps behavior identical
-- to the app's other plugins.

-- Unix seconds (string or number) → "YYYY-MM-DD" (display only).
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

-- ── TTL + LRU caches (page states, directory fallbacks) ─────────────────────
local CACHE_MAX    = 6
local PAGE_TTL_MS  = 600000  -- 10 min: a book page opened twice in a session
                             -- is fetched once (it also carries the whole TOC)

local pageCache, pageOrder = {}, {}

local function cacheGet(key, ttl)
  local now = nowMs()
  if not now then return nil end
  local e = pageCache[key]
  if e and (now - e.t) < ttl then return e.v end
  return nil
end

local function cachePut(key, value)
  local now = nowMs()
  if not now then return end
  if pageCache[key] == nil then
    pageOrder[#pageOrder + 1] = key
    if #pageOrder > CACHE_MAX then pageCache[table.remove(pageOrder, 1)] = nil end
  end
  pageCache[key] = { v = value, t = now }
end

-- ══ source part: pua_map.lua ══════════════════════════════
-- PUA → real-character table for the anti-scrape font
-- (dc027189e0ba4cd.woff2 = subset of SourceHanSansSC-Normal). Built by
-- rendering every PUA glyph and matching outlines against Noto Sans SC
-- weight 350 (the same typeface), then verified by decoding live
-- chapters of two different books (十日终焉 ch1, 凡骨 ch6/ch203) and the
-- /rank board titles — all decode to fluent Chinese with zero gaps.
local PUA_MAP = {
  [58344]="D", [58345]="\229\156\168", [58346]="\228\184\187", [58347]="\231\137\185",
  [58348]="\229\174\182", [58349]="\229\134\155", [58350]="\231\132\182", [58351]="\232\161\168",
  [58352]="\229\156\186", [58353]="4", [58354]="\232\166\129", [58355]="\229\143\170",
  [58356]="v", [58357]="\229\146\140", [58359]="6", [58360]="\229\136\171",
  [58361]="\232\191\152", [58362]="g", [58363]="\231\142\176", [58364]="\229\132\191",
  [58365]="\229\178\129", [58368]="\230\173\164", [58369]="\232\177\161", [58370]="\230\156\136",
  [58371]="3", [58372]="\229\135\186", [58373]="\230\136\152", [58374]="\229\183\165",
  [58375]="\231\155\184", [58376]="o", [58377]="\231\148\183", [58378]="\231\155\180",
  [58379]="\229\164\177", [58380]="\228\184\150", [58381]="F", [58382]="\233\131\189",
  [58383]="\229\185\179", [58384]="\230\150\135", [58385]="\228\187\128", [58386]="V",
  [58387]="O", [58388]="\229\176\134", [58389]="\231\156\159", [58390]="T",
  [58391]="\233\130\163", [58392]="\229\189\147", [58394]="\228\188\154", [58395]="\231\171\139",
  [58396]="\228\186\155", [58397]="u", [58398]="\230\152\175", [58399]="\229\141\129",
  [58400]="\229\188\160", [58401]="\229\173\166", [58402]="\230\176\148", [58403]="\229\164\167",
  [58404]="\231\136\177", [58405]="\228\184\164", [58406]="\229\145\189", [58407]="\229\133\168",
  [58408]="\229\144\142", [58409]="\228\184\156", [58410]="\230\128\167", [58411]="\233\128\154",
  [58412]="\232\162\171", [58413]="\239\188\145", [58414]="\229\174\131", [58415]="\228\185\144",
  [58416]="\230\142\165", [58417]="\232\128\140", [58418]="\230\132\159", [58419]="\232\189\166",
  [58420]="\229\177\177", [58421]="\229\133\172", [58422]="\228\186\134", [58423]="\229\184\184",
  [58424]="\228\187\165", [58425]="\228\189\149", [58426]="\229\143\175", [58427]="\232\175\157",
  [58428]="\229\133\136", [58429]="p", [58430]="\239\189\137", [58431]="\229\143\171",
  [58432]="\232\189\187", [58433]="M", [58434]="\229\163\171", [58435]="w",
  [58436]="\231\157\128", [58437]="\229\143\152", [58438]="\229\176\148", [58439]="\229\191\171",
  [58440]="l", [58441]="\228\184\170", [58442]="\232\175\180", [58443]="\229\176\145",
  [58444]="\232\137\178", [58445]="\233\135\140", [58446]="\229\174\137", [58447]="\232\138\177",
  [58448]="\232\191\156", [58449]="7", [58450]="\233\154\190", [58451]="\229\184\136",
  [58452]="\230\148\190", [58453]="t", [58454]="\230\138\165", [58455]="\232\174\164",
  [58456]="\233\157\162", [58457]="\233\129\147", [58458]="S", [58460]="\229\133\139",
  [58461]="\229\156\176", [58462]="\229\186\166", [58463]="\226\148\131", [58464]="\229\165\189",
  [58465]="\230\156\186", [58466]="U", [58467]="\230\176\145", [58468]="\229\134\153",
  [58469]="\230\138\138", [58470]="\228\184\135", [58471]="\229\144\140", [58472]="\230\176\180",
  [58473]="\230\150\176", [58474]="\230\178\161", [58475]="\228\185\166", [58476]="\231\148\181",
  [58477]="\229\144\131", [58478]="\229\131\143", [58479]="\230\150\175", [58480]="5",
  [58481]="\228\184\186", [58482]="y", [58483]="\231\153\189", [58484]="\229\135\160",
  [58485]="\230\151\165", [58486]="\230\149\153", [58487]="\231\156\139", [58488]="\228\189\134",
  [58489]="\231\172\172", [58490]="\229\138\160", [58491]="\229\128\153", [58492]="\228\189\156",
  [58493]="\228\184\138", [58494]="\230\139\137", [58495]="\228\189\143", [58496]="\230\156\137",
  [58497]="\230\179\149", [58498]="r", [58499]="\228\186\139", [58500]="\229\186\148",
  [58501]="\228\189\141", [58502]="\229\136\169", [58503]="\228\189\160", [58504]="\229\163\176",
  [58505]="\232\186\171", [58506]="\229\155\189", [58507]="\233\151\174", [58508]="\233\169\172",
  [58509]="\229\165\179", [58510]="\228\187\150", [58511]="Y", [58512]="\230\175\148",
  [58513]="\231\136\182", [58514]="x", [58515]="A", [58516]="H",
  [58517]="N", [58518]="s", [58519]="X", [58520]="\232\190\185",
  [58521]="\231\190\142", [58522]="\229\175\185", [58523]="\230\137\128", [58524]="\233\135\145",
  [58525]="\230\180\187", [58526]="\229\155\158", [58527]="\230\132\143", [58528]="\229\136\176",
  [58529]="z", [58530]="\228\187\142", [58531]="j", [58532]="\231\159\165",
  [58533]="\229\143\136", [58534]="\229\134\133", [58535]="\229\155\160", [58536]="\231\130\185",
  [58537]="Q", [58538]="\228\184\137", [58539]="\229\174\154", [58540]="8",
  [58541]="R", [58542]="b", [58543]="\230\173\163", [58544]="\230\136\150",
  [58545]="\229\164\171", [58546]="\229\144\145", [58547]="\229\190\183", [58548]="\229\144\172",
  [58549]="\230\155\180", [58551]="\229\190\151", [58552]="\229\145\138", [58553]="\229\185\182",
  [58554]="\230\156\172", [58555]="q", [58556]="\232\191\135", [58557]="\232\174\176",
  [58558]="L", [58559]="\232\174\169", [58560]="\230\137\147", [58561]="f",
  [58562]="\228\186\186", [58563]="\229\176\177", [58564]="\232\128\133", [58565]="\229\142\187",
  [58566]="\229\142\159", [58567]="\230\187\161", [58568]="\228\189\147", [58569]="\229\129\154",
  [58570]="\231\187\143", [58571]="K", [58572]="\232\181\176", [58573]="\229\166\130",
  [58574]="\229\173\169", [58575]="c", [58576]="G", [58577]="\231\187\153",
  [58578]="\228\189\191", [58579]="\231\137\169", [58581]="\230\156\128", [58582]="\231\172\145",
  [58583]="\233\131\168", [58585]="\229\145\152", [58586]="\231\173\137", [58587]="\229\143\151",
  [58588]="k", [58589]="\232\161\140", [58590]="\228\184\128", [58591]="\230\157\161",
  [58592]="\230\158\156", [58593]="\229\138\168", [58594]="\229\133\137", [58595]="\233\151\168",
  [58596]="\229\164\180", [58597]="\232\167\129", [58598]="\229\190\128", [58599]="\232\135\170",
  [58600]="\232\167\163", [58601]="\230\136\144", [58602]="\229\164\132", [58603]="\229\164\169",
  [58604]="\232\131\189", [58605]="\228\186\142", [58606]="\229\144\141", [58607]="\229\133\182",
  [58608]="\229\143\145", [58609]="\230\128\187", [58610]="\230\175\141", [58611]="\231\154\132",
  [58612]="\230\173\187", [58613]="\230\137\139", [58614]="\229\133\165", [58615]="\232\183\175",
  [58616]="\232\191\155", [58617]="\229\191\131", [58618]="\230\157\165", [58619]="h",
  [58620]="\230\151\182", [58621]="\229\138\155", [58622]="\229\164\154", [58623]="\229\188\128",
  [58624]="\229\183\178", [58625]="\232\174\184", [58626]="d", [58627]="\232\135\179",
  [58628]="\231\148\177", [58629]="\229\190\136", [58630]="\231\149\140", [58631]="n",
  [58632]="\229\176\143", [58633]="\228\184\142", [58634]="Z", [58635]="\230\131\179",
  [58636]="\228\187\163", [58637]="\228\185\136", [58638]="\229\136\134", [58639]="\231\148\159",
  [58640]="\229\143\163", [58641]="\229\134\141", [58642]="\229\166\136", [58643]="\230\156\155",
  [58644]="\230\172\161", [58645]="\232\165\191", [58646]="\233\163\142", [58647]="\231\167\141",
  [58648]="\229\184\166", [58649]="J", [58651]="\229\174\158", [58652]="\230\131\133",
  [58653]="\230\137\141", [58654]="\232\191\153", [58656]="E", [58657]="\230\136\145",
  [58658]="\231\165\158", [58659]="\230\160\188", [58660]="\233\149\191", [58661]="\232\167\137",
  [58662]="\233\151\180", [58663]="\229\185\180", [58664]="\231\156\188", [58665]="\230\151\160",
  [58666]="\228\184\141", [58667]="\228\186\178", [58668]="\229\133\179", [58669]="\231\187\147",
  [58670]="0", [58671]="\229\143\139", [58672]="\228\191\161", [58673]="\228\184\139",
  [58674]="\229\141\180", [58675]="\233\135\141", [58676]="\229\183\177", [58677]="\232\128\129",
  [58678]="2", [58679]="\233\159\179", [58680]="\229\173\151", [58681]="m",
  [58682]="\229\145\162", [58683]="\230\152\142", [58684]="\228\185\139", [58685]="\229\137\141",
  [58686]="\233\171\152", [58687]="P", [58688]="B", [58689]="\231\155\174",
  [58690]="\229\164\170", [58691]="e", [58692]="9", [58693]="\232\181\183",
  [58694]="\231\168\156", [58695]="\229\165\185", [58696]="\228\185\159", [58697]="W",
  [58698]="\231\148\168", [58699]="\230\150\185", [58700]="\229\173\144", [58701]="\232\139\177",
  [58702]="\230\175\143", [58703]="\231\144\134", [58704]="\228\190\191", [58705]="\229\155\155",
  [58706]="\230\149\176", [58707]="\230\156\159", [58708]="\228\184\173", [58709]="C",
  [58710]="\229\164\150", [58711]="\230\160\183", [58712]="a", [58713]="\230\181\183",
  [58714]="\228\187\172", [58715]="\228\187\187",
}

-- ══ source part: part2_translator.lua ══════════════════════════════

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

-- ══ source part: part3_official.lua ══════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- Official-site layer — fanqienovel.com SSR state, PUA font decoding,
-- the mirror backend (search + locked-chapter fallback)
-- ═══════════════════════════════════════════════════════════════════════════

local BROWSER_HEADERS = {
  ["User-Agent"]      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " ..
                       "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
  ["Accept"]          = "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
  ["Accept-Language"] = "zh-CN,zh;q=0.9,en;q=0.8"
}

-- ── PUA font decoding ────────────────────────────────────────────────────────
-- PUA codepoints U+E000–U+F8FF encode as UTF-8 lead bytes 0xEE (E000–EFFF)
-- and 0xEF (F000–F8FF, mixed with real chars ≥ F900). Walk the string byte-
-- wise; 3-byte PUA sequences are replaced through PUA_MAP, everything else
-- (ASCII, hanzi, punctuation) is copied verbatim.

local function decodePua(s)
  if type(s) ~= "string" or s == "" then return s end
  -- fast path: nothing in the PUA lead-byte range
  if not string.find(s, "\238") and not string.find(s, "\239") then return s end
  local out, i, n = {}, 1, #s
  while i <= n do
    local b = string.byte(s, i)
    if b == 238 or b == 239 then -- 0xEE / 0xEF
      local b2, b3 = string.byte(s, i + 1), string.byte(s, i + 2)
      if b2 and b3 then
        local cp = (b % 16) * 4096 + (b2 % 64) * 64 + (b3 % 64)
        local rep = PUA_MAP[cp]
        if rep then
          out[#out + 1] = rep
        else
          out[#out + 1] = string.sub(s, i, i + 2) -- unmapped PUA: keep as-is
        end
        i = i + 3
      else -- truncated tail
        out[#out + 1] = string.sub(s, i)
        break
      end
    else
      out[#out + 1] = string.sub(s, i, i) -- non-PUA bytes pass through
      i = i + 1
    end
  end
  return table.concat(out)
end

-- Decode every text field the UI shows (titles, abstracts, authors…).
local function dt(s)
  local d = decodePua(s)
  if d ~= s then return d end
  return s
end

-- ── HTML entities (chapter bodies occasionally carry them) ──────────────────
local function htmlUnescape(s)
  if type(s) ~= "string" or string.find(s, "&", 1, true) == nil then return s end
  s = string.gsub(s, "&amp;", "&")
  s = string.gsub(s, "&lt;", "<")
  s = string.gsub(s, "&gt;", ">")
  s = string.gsub(s, "&quot;", "\"")
  s = string.gsub(s, "&#39;", "'")
  s = string.gsub(s, "&nbsp;", " ")
  return s
end

-- ── __INITIAL_STATE__ extraction ─────────────────────────────────────────────
-- The state is a JSON object assigned in a <script>. A string-aware
-- balanced-brace scanner finds its exact end (img placeholders inside
-- content strings contain braces, so brace-counting alone is NOT safe).
-- Pattern-driven find() calls keep this fast even on 1.7 MB book pages.
local STATE_ANCHOR = "__INITIAL_STATE__="

local function extractStateJson(html)
  if type(html) ~= "string" or html == "" then return nil end
  local anchor = string.find(html, STATE_ANCHOR, 1, true)
  if not anchor then return nil end
  local start = anchor + #STATE_ANCHOR
  if string.sub(html, start, start) ~= "{" then return nil end
  local depth, i, n = 1, start + 1, #html
  while true do
    local s, e, c = string.find(html, "([{}\"])", i)
    if not s then return nil end
    if c == '"' then
      -- scan to the closing quote, honoring backslash escapes
      local j = e + 1
      while true do
        local q, _, qc = string.find(html, "([\"\\])", j)
        if not q then return nil end
        if qc == "\\" then
          j = q + 2
        else -- real closing quote
          i = q + 1
          break
        end
      end
    elseif c == "{" then
      depth = depth + 1
      i = e + 1
    else -- "}"
      depth = depth - 1
      if depth == 0 then
        return string.sub(html, start, e)
      end
      i = e + 1
    end
  end
end

-- Extract + parse a page's state in one step. Some pages embed the JS value
-- `undefined` (not valid JSON) — normalized to null before parsing.
local function parseStateHtml(html)
  local js = extractStateJson(html)
  if not js then return nil end
  if string.find(js, "undefined", 1, true) then
    js = string.gsub(js, "undefined", "null")
  end
  local ok, j = pcall(json_parse, js)
  if ok and type(j) == "table" then return j end
  return nil
end

-- ── Page fetching (cached) ───────────────────────────────────────────────────

local function fetchSitePage(path, noCache)
  local key = "GET " .. path
  if not noCache then
    local c = cacheGet(key, PAGE_TTL_MS)
    if c ~= nil then return c end
  end
  local st
  for attempt = 1, 2 do
    local r = http_get(SITE .. path, { headers = BROWSER_HEADERS })
    if r and r.success and type(r.body) == "string" and r.body ~= "" then
      st = parseStateHtml(r.body)
    else
      st = nil
    end
    if st then break end
    -- failed or unparseable (connection blip, momentary rate limit, truncated
    -- body): one retry after a short pause, then give up with nil
    if attempt == 1 then pcall(sleep, 400) end
  end
  -- cache only valid states (failed fetches retry on the next call)
  if st and not noCache then cachePut(key, st) end
  return st
end

-- Book page state (metadata + full TOC in ONE request).
local function fetchBookState(bookId)
  if type(bookId) ~= "string" or bookId == "" then return nil end
  local st = fetchSitePage("/page/" .. bookId)
  if type(st) == "table" and type(st.page) == "table" then return st.page end
  return nil
end

-- TOC from a book state: flatten chapterListWithVolume (array of volumes,
-- each an array of {itemId, title, …}) preserving order.
local function tocFromBookState(pg)
  if type(pg) ~= "table" or type(pg.chapterListWithVolume) ~= "table" then
    return nil
  end
  local items = {}
  for vi = 1, #pg.chapterListWithVolume do
    local vol = pg.chapterListWithVolume[vi]
    if type(vol) == "table" then
      for ci = 1, #vol do
        local ch = vol[ci]
        if type(ch) == "table" and type(ch.itemId) == "string" then
          items[#items + 1] = {
            itemId = ch.itemId,
            title  = tostring(ch.title or ch.itemId)
          }
        end
      end
    end
  end
  if #items == 0 then return nil end
  return items
end

-- TOC fallback: /api/reader/directory/detail?bookId=… (pure JSON endpoint,
-- same chapterListWithVolume shape). Used when the book page state carries
-- no directory (rare server-side fetch misses).
local function fetchDirectoryApi(bookId)
  local key = "DIR " .. bookId
  local c = cacheGet(key, PAGE_TTL_MS)
  if c ~= nil then return c end
  local r = http_get(SITE .. "/api/reader/directory/detail?bookId=" .. url_encode(bookId),
                     { headers = BROWSER_HEADERS })
  local items
  if r and r.success and type(r.body) == "string"
     and string.sub(r.body, 1, 1) == "{" then
    local ok, j = pcall(json_parse, r.body)
    if ok and type(j) == "table" and type(j.data) == "table" then
      items = tocFromBookState(j.data)
    end
  end
  if items then cachePut(key, items) end
  return items
end

-- Reader page state — chapterData carries the chapter text.
local function chapterDataFromState(st)
  if type(st) ~= "table" then return nil end
  local rd = st.reader
  if type(rd) == "table" and type(rd.chapterData) == "table" then
    return rd.chapterData
  end
  return nil
end

local function fetchReaderChapter(itemId)
  if type(itemId) ~= "string" or itemId == "" then return nil end
  local r = http_get(SITE .. "/reader/" .. itemId, { headers = BROWSER_HEADERS })
  if not (r and r.success and type(r.body) == "string") then return nil end
  return chapterDataFromState(parseStateHtml(r.body))
end

-- Font check: state.common.css embeds the @font-face URL of the current
-- anti-scrape font. Returns the font file hash, or nil when absent.
local function fontHashFromState(st)
  if type(st) ~= "table" then return nil end
  local cm = st.common
  local css = type(cm) == "table" and cm.css
  if type(css) ~= "string" then return nil end
  return string.match(css, "awesome%-font/.-/([%w]+)%.woff2")
end

-- ── Chapter text from a reader chapterData ──────────────────────────────────
-- content is HTML-ish: "<p>…</p><p>…</p>" with occasional
-- "<img src="{{image_domain}}{…json…}"></img>" figures. Produces one
-- paragraph per line, PUA-decoded, entity-cleaned.

local function contentToText(content)
  if type(content) ~= "string" or content == "" then return nil end
  -- drop images (a text reader cannot show them; empty paragraphs follow)
  content = string.gsub(content, "<img[^>]*>%s*</img>", "")
  content = string.gsub(content, "<img[^>]*/?>", "")
  -- paragraph breaks → newlines; strip any remaining tags
  content = string.gsub(content, "</p>", "\n")
  content = string.gsub(content, "<[^>]+>", "")
  content = htmlUnescape(content)
  content = decodePua(content)
  local out = {}
  for _, ln in ipairs(string_split(content, "\n")) do
    ln = string_trim(ln)
    if ln ~= "" then out[#out + 1] = ln end
  end
  if #out == 0 then return nil end
  return table.concat(out, "\n")
end

-- UTF-8 CHARACTER count (Lua's # is bytes; chapterWordNumber counts chars,
-- and Chinese chars are 3 bytes each — comparing raw byte lengths against
-- the server's word count would always scream "locked").
local function utf8Len(s)
  if type(s) ~= "string" then return 0 end
  local n = 0
  for i = 1, #s do
    local b = string.byte(s, i)
    if b < 128 or b >= 192 then n = n + 1 end -- count lead bytes only
  end
  return n
end

-- Locked-preview detection. chapterData.isChapterLock is the server's own
-- flag; the length ratio (decoded chars vs chapterWordNumber) catches the
-- cases where the flag is absent but only a preview was embedded.
local function isLockedPreview(cd, text)
  if type(cd) == "table" and cd.isChapterLock == true then return true end
  if type(text) ~= "string" then return false end
  local wn = tonumber(cd and cd.chapterWordNumber or nil)
  if not wn or wn < 200 then return false end
  return utf8Len(text) < wn * 0.55
end

-- ── Mirror backend (fanqie-novel-reader) — search + locked-chapter text ─────

local function mirrorHeaders()
  return {
    ["X-API-Token"] = MIRROR_TOKEN,
    ["Origin"]      = "https://fanqietc.com",
    ["Referer"]     = "https://fanqietc.com/",
    ["User-Agent"]  = BROWSER_HEADERS["User-Agent"],
    ["Accept"]      = "application/json"
  }
end

-- Search via the mirror backend (the official site's search is client-side
-- JS only — there is no server endpoint to call). Same book-id space.
-- Returns the raw books array ({book_id, book_name, author, category,
-- thumb_url, abstract, creation_status, …} — snake_case), or nil.
local function mirrorSearch(query)
  if type(query) ~= "string" or query == "" then return nil end
  for attempt = 1, 2 do
    local r = http_get(MIRROR_API .. "/search?query=" .. url_encode(query),
                       { headers = mirrorHeaders() })
    if r and r.success and type(r.body) == "string"
       and string.sub(r.body, 1, 1) == "{" then
      local ok, j = pcall(json_parse, r.body)
      if ok and type(j) == "table" and type(j.data) == "table"
         and type(j.data.books) == "table" then
        return j.data.books
      end
    end
  end
  return nil
end

-- Full chapter text via the mirror backend (plain text, one paragraph per
-- \n — same format the FanqieTC plugin consumes). Walks MIRROR_ORDER.
local function mirrorChapterText(itemId)
  for _, mirror in ipairs(MIRROR_ORDER) do
    local url = MIRROR_API .. "/proxy?api=" .. url_encode(mirror) ..
                "&action=content&item_id=" .. url_encode(itemId)
    local r = http_get(url, { headers = mirrorHeaders() })
    if r and r.success and type(r.body) == "string"
       and string.sub(r.body, 1, 1) == "{" then
      local ok, j = pcall(json_parse, r.body)
      if ok and type(j) == "table" and type(j.data) == "table"
         and type(j.data.content) == "string" and #j.data.content > 50 then
        local lines = {}
        for _, ln in ipairs(string_split(j.data.content, "\n")) do
          ln = string_trim(ln)
          if ln ~= "" then lines[#lines + 1] = ln end
        end
        if #lines > 0 then return table.concat(lines, "\n") end
      end
    end
  end
  return nil
end


-- Translate catalog item titles in Translator mode (batched, cache-backed).
local function translateCatalogItems(items)
  if not (trActive() and type(items) == "table" and #items > 0) then return items end
  local titles = {}
  for i = 1, #items do titles[i] = items[i].title end
  local tr = translateBatch(titles)
  for i = 1, #items do items[i].title = tr[i] end
  return items
end

-- ══ source part: part4_catalog.lua ══════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- Catalog — homepage lists, rank board, search, filters, self-test
-- ═══════════════════════════════════════════════════════════════════════════

-- Browse surfaces. The homepage state carries five curated lists; the rank
-- page the official top-10. All single-page (no pagination server-side).
local SURFACES = {
  { value = "editors", list = "editorList", en = "Editors' Picks", zh = "編輯推薦" },
  { value = "weekly",  list = "weekList",   en = "Weekly Hot",     zh = "本周熱讀" },
  { value = "boys",    list = "boyList",    en = "Boys",           zh = "男生" },
  { value = "girls",   list = "girlList",   en = "Girls",          zh = "女生" },
  { value = "latest",  list = "updateList", en = "Latest Updates", zh = "最近更新" },
  { value = "rank",    list = nil,          en = "Top 10 Rank",    zh = "排行榜" },
  { value = "selftest", list = nil,         en = "⚡ Self-Test",   zh = "診斷" }
}

local currentSurface = "editors"

local function surfaceDef(v)
  for _, s in ipairs(SURFACES) do
    if s.value == v then return s end
  end
  return nil
end

-- Visible failure page (mirrors the FanqieTC plugin's pattern: an empty
-- catalog is indistinguishable from "no results" — make the state explicit).
local function failedPage(what)
  return { items = {{
    title = "⚠ FanqieNovel: " .. what .. " unavailable right now — fanqienovel.com " ..
            "did not answer. Pull-to-refresh to retry. Chapter reading keeps " ..
            "working for books already on your shelf. Live health: " ..
            "Browse → Page → ⚡ Self-Test.",
    url   = SITE .. "/",
    cover = ""
  }}, hasNext = false }
end

-- ── camelCase book entry (official site) → catalog item ────────────────────
local function officialBookToItem(b)
  if type(b) ~= "table" then return nil end
  local id = tostring(b.bookId or "")
  if id == "" then return nil end
  local title = dt(tostring(b.bookName or id))
  local sub = ""
  local author = dt(tostring(b.author or ""))
  if author ~= "" then sub = " · " .. author end
  -- Latest Updates entries carry the freshest chapter title — show it.
  if b.title and type(b.title) == "string" then
    local lt = dt(b.title)
    if lt ~= "" then sub = sub .. "  [" .. lt .. "]" end
  end
  return {
    title  = title .. sub,
    url    = SITE .. "/page/" .. id,
    cover  = tostring(b.thumbUri or ""),
    rating = nil -- the official site exposes no per-book score
  }
end

-- ── snake_case book entry (mirror search backend) → catalog item ────────────
local function mirrorBookToItem(b)
  if type(b) ~= "table" then return nil end
  local id = tostring(b.book_id or "")
  if id == "" then return nil end
  local title = dt(tostring(b.book_name or b.original_book_name or id))
  local sub = ""
  local author = dt(tostring(b.author or ""))
  if author ~= "" then sub = " · " .. author end
  local rating = nil
  if b.score and tostring(b.score) ~= "0" and tostring(b.score) ~= "" then
    rating = tostring(b.score)
  end
  return {
    title  = title .. sub,
    url    = SITE .. "/page/" .. id,
    cover  = tostring(b.thumb_url or ""),
    rating = rating
  }
end

local function pagedList(items)
  translateCatalogItems(items)
  return { items = items, hasNext = false }
end

-- ── URL / bare-id paste support ──────────────────────────────────────────────
-- Accepts fanqienovel.com/page/{id}, fanqienovel.com/reader/{id} (resolves
-- the book id through the reader state), fanqietc.com/book/{id},
-- tomatomtl.com/book/{id} (same id space), or a bare 15-20 digit id.
local function tryUrlPaste(query)
  if type(query) ~= "string" then return nil end
  local id = string.match(query, "fanqienovel%.com/page/(%d+)")
      or string.match(query, "fanqietc%.com/book/(%d+)")
      or string.match(query, "tomatomtl%.com/book/(%d+)")
      or string.match(query, "fanqienovel%.com/reader/(%d+)")
  -- bare id: Lua patterns have no {n,m} quantifier — match digits, check length
  if not id then
    local bare = string.match(query, "^%s*(%d+)%s*$")
    if bare and #bare >= 15 and #bare <= 20 then id = bare end
  end
  if not id then return nil end
  -- /reader/{id} → look up the book id via the reader state
  if string.find(query, "/reader/") and not string.match(query, "fanqienovel%.com/page/") then
    local cd = fetchReaderChapter(id)
    if type(cd) == "table" and type(cd.bookId) == "string" then
      id = cd.bookId
    end
  end
  local pg = fetchBookState(id)
  if type(pg) ~= "table" then return nil end
  local item = officialBookToItem({ bookId = id, bookName = pg.bookName, author = pg.author,
                                    thumbUri = pg.thumbUri or pg.thumbUrl })
  if not item then return nil end
  return { items = { item }, hasNext = false }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ⚡ Self-Test — live diagnostics as catalog items
-- ═══════════════════════════════════════════════════════════════════════════
local function runSelfTest()
  local items = {}
  local function line(mark, label, detail)
    local d = ""
    if detail ~= nil and detail ~= "" then d = " — " .. detail end
    items[#items + 1] = { title = mark .. " " .. label .. d, url = SITE .. "/", cover = "" }
  end
  local function elapsed(t0)
    local n = nowMs()
    if t0 and n and n >= t0 then return tostring(math.floor(n - t0)) .. "ms" end
    return ""
  end

  line("⚡", "Plugin", "FanqieNovel v1.0.0 — official 番茄小说 source. If you can see this line, you are on the RIGHT source")

  -- 1. settings
  line("✓", "Settings", "mode=" .. getMode() .. ", target=" .. getTl())

  -- 2. environment helpers
  local clock = nowMs()
  line(clock and "✓" or "!", "os_time",
       clock and "available (milliseconds)" or
       "MISSING on this app build — caches degrade to unbounded")
  local j = json_parse('["a","b"]')
  local jOk = type(j) == "table" and j[1] == "a" and j[2] == "b"
  line(jOk and "✓" or "✗", "json_parse",
       jOk and "array → Lua table OK" or ("unexpected result type: " .. type(j)))

  -- 3. PUA font table sanity (offline — proves the decode table loads)
  local probe = "\238\147\179" -- U+E4F3 → 的
  local decoded = decodePua(probe)
  line(decoded == "的" and "✓" or "✗", "PUA font table",
       decoded == "的" and "362 glyphs loaded; U+E4F3 → 的 OK" or
       ("decode returned " .. tostring(decoded)))

  -- 4. rank page (SSR state parse)
  local t0 = nowMs()
  local rankState = fetchSitePage("/rank", true)
  if type(rankState) == "table" and type(rankState.rank) == "table"
     and type(rankState.rank.book_list) == "table" and #rankState.rank.book_list > 0 then
    local first = rankState.rank.book_list[1]
    line("✓", "Official site (rank)", elapsed(t0) .. " → " .. #rankState.rank.book_list ..
         " books; #" .. tostring(first.currentPos or 1) .. ": " ..
         dt(tostring(first.bookName or "?")))
  else
    line("✗", "Official site (rank)", elapsed(t0) .. " unreachable — fanqienovel.com down or blocked on this network")
  end

  -- 5. book page + TOC (one request answers both)
  local PROBE_ID = "7077516958534470656" -- 凡骨 (4051 ch — stress-tested canary)
  local t1 = nowMs()
  local pg = fetchBookState(PROBE_ID)
  if type(pg) == "table" and type(pg.bookName) == "string" then
    local toc = tocFromBookState(pg)
    line("✓", "Book page + TOC", elapsed(t1) .. " → " .. dt(pg.bookName) .. " · " ..
         tostring(pg.author or "?") .. " · " .. (toc and (#toc .. " chapters") or "TOC missing"))
  else
    line("✗", "Book page", elapsed(t1) .. " failed")
  end

  -- 6. chapter content + font check (official path)
  local contentOk, fontOk = false, nil
  if type(pg) == "table" then
    local toc = tocFromBookState(pg)
    if toc and toc[1] then
      local t2 = nowMs()
      local readerState = fetchSitePage("/reader/" .. toc[1].itemId, true)
      local cd = chapterDataFromState(readerState)
      local fh = fontHashFromState(readerState)
      fontOk = (fh == KNOWN_FONT_HASH)
      if fontOk == false then
        line("!", "Anti-scrape font", "site rotated the font (" .. tostring(fh) ..
             ") — the PUA table no longer matches; chapters fall back to the mirror backend")
      else
        line("✓", "Anti-scrape font", "still " .. KNOWN_FONT_HASH .. " — PUA decode valid")
      end
      local text = cd and contentToText(cd.content)
      if text and not isLockedPreview(cd, text) then
        contentOk = true
        line("✓", "Chapter content (official)", elapsed(t2) .. " → " ..
             #text .. " bytes, " .. tostring(cd and cd.title or "?"))
      elseif text then
        line("!", "Chapter content (official)", elapsed(t2) .. " → locked preview only (VIP chapter); trying mirror fallback…")
      else
        line("✗", "Chapter content (official)", elapsed(t2) .. " failed")
      end
    end
  end

  -- 7. locked-chapter fallback (mirror backend content)
  if type(pg) == "table" then
    local toc = tocFromBookState(pg)
    if toc and toc[200] then
      local t3 = nowMs()
      local full = mirrorChapterText(toc[200].itemId)
      if full then
        line("✓", "Mirror fallback (VIP ch)", elapsed(t3) .. " → " .. #full ..
             " bytes for " .. toc[200].title)
      else
        line(contentOk and "!" or "✗", "Mirror fallback (VIP ch)",
             elapsed(t3) .. " unavailable — mirror backend down; free chapters still work")
      end
    end
  end

  -- 8. mirror search backend
  local t4 = nowMs()
  local books = mirrorSearch("斗罗大陆")
  if type(books) == "table" and #books > 0 then
    line("✓", "Search backend (mirror)", elapsed(t4) .. " → " .. #books ..
         " hits for 斗罗大陆; first: " .. dt(tostring(books[1].book_name or "?")))
  else
    line("!", "Search backend (mirror)", elapsed(t4) ..
         " unavailable — browse and URL-paste still work; retry later")
  end

  -- 9. translation engines (probed directly, regardless of mode)
  local tl = getTl()
  local probeWords = { "玄幻", "都市" }
  local t5 = nowMs()
  local r1 = trRequestGoogle(probeWords, "zh-CN", tl)
  line(r1 and "✓" or "✗", "Google batch (POST/GET, 2 hosts)",
       r1 and ((elapsed(t5) .. " → ") .. table.concat(r1, " / ")) or
       (elapsed(t5) .. " unreachable"))
  local t6 = nowMs()
  local r2 = trChunkMyMemory(probeWords, tl)
  local mmOk = r2 ~= nil and r2[1] ~= probeWords[1]
  line(mmOk and "✓" or "✗", "MyMemory fallback",
       mmOk and (elapsed(t6) .. " → " .. table.concat(r2, " / ")) or
       (elapsed(t6) .. " unreachable"))
  local t7 = nowMs()
  local r3 = trGtxSingle("玄幻", tl)
  line(r3 and "✓" or "✗", "Google gtx single",
       r3 and (elapsed(t7) .. " → " .. r3) or
       (elapsed(t7) .. " unreachable (fine when the batch engine works)"))

  -- 10. verdict
  if type(pg) ~= "table" then
    line("→", "Verdict", "fanqienovel.com unreachable — check your network (VPN/DNS) or try again later")
  elseif fontOk == false and not (type(books) == "table" and #books > 0) then
    line("→", "Verdict", "font rotated AND mirror backend down — chapters cannot be decoded right now; everything else works")
  elseif getMode() ~= "translate" then
    line("→", "Verdict", "site OK — switch Mode to Translator in this source's settings to translate, then pull-to-refresh the catalog")
  elseif r1 or mmOk or r3 then
    line("→", "Verdict", "site + translator OK — if titles still show Chinese: pull-to-refresh the catalog (already-loaded pages are not retranslated)")
  else
    line("→", "Verdict", "site OK but ALL translator engines unreachable — your network/region is blocking Google & MyMemory. Try another network or disable the VPN")
  end

  return { items = items, hasNext = false }
end

-- ── Default catalog → Editors' Picks ────────────────────────────────────────
function getCatalogList(index)
  currentSurface = "editors"
  if index > 0 then return { items = {}, hasNext = false } end
  local home = fetchSitePage("/")
  if type(home) ~= "table" or type(home.home) ~= "table" then
    return failedPage("browse lists")
  end
  local list = home.home.editorList
  if type(list) ~= "table" or #list == 0 then return failedPage("browse lists") end
  local items = {}
  for i = 1, #list do
    local it = officialBookToItem(list[i])
    if it then items[#items + 1] = it end
  end
  if #items == 0 then return failedPage("browse lists") end
  return pagedList(items)
end

-- ── Search ───────────────────────────────────────────────────────────────────
-- Official site search is client-side-only; queries go through the mirror
-- backend (same catalog, same ids). Pasted URLs/bare ids resolve directly.
function getCatalogSearch(index, query)
  if index > 0 then return { items = {}, hasNext = false } end
  if type(query) ~= "string" or query == "" then
    return { items = {}, hasNext = false }
  end

  -- 0. pasted URL / bare book id → open the book directly
  local pasted = tryUrlPaste(query)
  if pasted then return pasted end

  -- 1. translate non-Chinese queries to zh-CN (the catalog is Simplified)
  local q = query
  if trActive() and not hasCJK(query) then
    local zh = translateQueryToZh(query, "zh-CN")
    if zh then q = zh end
  end

  local books = mirrorSearch(q)
  local items = {}
  if type(books) == "table" then
    for i = 1, #books do
      local it = mirrorBookToItem(books[i])
      if it then items[#items + 1] = it end
    end
  end

  -- translated query found nothing → retry with the raw query (pinyin /
  -- English titles, author names and book ids still match server-side)
  if q ~= query and #items == 0 then
    books = mirrorSearch(query)
    if type(books) == "table" then
      for i = 1, #books do
        local it = mirrorBookToItem(books[i])
        if it then items[#items + 1] = it end
      end
    end
  end

  if #items == 0 then
    return { items = {{
      title = "⚠ FanqieNovel: no results" ..
              (#items == 0 and (q ~= query and (" for \"" .. q .. "\" or \"" .. query .. "\"") or
               (" for \"" .. query .. "\"")) or "") ..
              " — or the search backend is down (Browse and pasted fanqienovel.com links keep working). " ..
              "Live health: Browse → Page → ⚡ Self-Test.",
      url   = SITE .. "/",
      cover = ""
    }}, hasNext = false }
  end
  return pagedList(items)
end

-- ── Filtered browse ──────────────────────────────────────────────────────────
function getCatalogFiltered(index, filters)
  filters = filters or {}
  local browse = filters["browse"] or "editors"
  if not surfaceDef(browse) then browse = "editors" end
  currentSurface = browse

  if index > 0 then return { items = {}, hasNext = false } end

  if browse == "selftest" then
    local ok, res = pcall(runSelfTest)
    if ok and type(res) == "table" then return res end
    return { items = {{
      title = "Self-test failed: " .. tostring(res),
      url   = SITE .. "/", cover = ""
    }}, hasNext = false }
  end

  if browse == "rank" then
    local st = fetchSitePage("/rank")
    if type(st) ~= "table" or type(st.rank) ~= "table"
       or type(st.rank.book_list) ~= "table" or #st.rank.book_list == 0 then
      return failedPage("rank board")
    end
    local items = {}
    for i = 1, #st.rank.book_list do
      local it = officialBookToItem(st.rank.book_list[i])
      if it then items[#items + 1] = it end
    end
    if #items == 0 then return failedPage("rank board") end
    return pagedList(items)
  end

  -- homepage lists
  local def = surfaceDef(browse)
  local home = fetchSitePage("/")
  if type(home) ~= "table" or type(home.home) ~= "table" then
    return failedPage(def.en)
  end
  local list = home.home[def.list]
  if type(list) ~= "table" or #list == 0 then return failedPage(def.en) end
  local items = {}
  for i = 1, #list do
    local it = officialBookToItem(list[i])
    if it then items[#items + 1] = it end
  end
  if #items == 0 then return failedPage(def.en) end
  return pagedList(items)
end

-- ── Filter list (page-scoped) ────────────────────────────────────────────────
function getFilterList()
  local surface = currentSurface
  if not surfaceDef(surface) then surface = "editors" end

  local options = {}
  for _, s in ipairs(SURFACES) do
    options[#options + 1] = { value = s.value, label = flLabel(s.en, s.zh) }
  end

  return {
    {
      type = "select", key = "browse",
      label = flLabel("Page", "頁面"),
      defaultValue = surface, -- follows the page being browsed
      options = options
    }
  }
end

-- ══ source part: part5_book.lua ══════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- Book details, chapter list, chapter text, settings
-- ═══════════════════════════════════════════════════════════════════════════

-- ── URL → ids ────────────────────────────────────────────────────────────────
-- Book URLs are the site's own: https://fanqienovel.com/page/{bookId}.
-- Legacy/compatible shapes also resolve (fanqietc.com/book/{id},
-- tomatomtl.com/book/{id} — same id space).
local function bookIdFromUrl(url)
  return string.match(url or "", "fanqienovel%.com/page/(%d+)")
      or string.match(url or "", "fanqietc%.com/book/(%d+)")
      or string.match(url or "", "tomatomtl%.com/book/(%d+)")
      or string.match(url or "", "/page/(%d+)")
      or string.match(url or "", "/book/(%d+)")
end

-- ── Book details (one cached /page/{id} request answers them all) ───────────

function getBookTitle(bookUrl)
  local d = fetchBookState(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return nil end
  local title = dt(tostring(d.bookName or ""))
  if title == "" then return nil end
  if trActive() then
    local tr = translateOne(title)
    if tr and tr ~= title then return tr .. " (" .. title .. ")" end
  end
  return title
end

function getBookCoverImageUrl(bookUrl)
  local d = fetchBookState(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return nil end
  -- Signed CDN URL (fqnovelpic.com / byteimg.com, x-expires months out) —
  -- used DIRECTLY: image loaders are exempt from the WebView bypass and
  -- these signed hosts never challenge image requests.
  local u = tostring(d.thumbUri or d.thumbUrl or "")
  if u == "" then return nil end
  return u
end

function getBookDescription(bookUrl)
  local d = fetchBookState(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return nil end
  local desc = dt(tostring(d.abstract or ""))
  if desc == "" then return nil end
  if trActive() then
    if #desc > 4000 then desc = string.sub(desc, 1, 4000) end
    desc = translateOne(desc)
  end
  return desc
end

-- The official book-page state carries no category chips (verified) —
-- category/categoryV2 are empty strings on live pages. Best effort only.
function getBookGenres(bookUrl)
  local d = fetchBookState(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return {} end
  local genres = {}
  local tags = dt(tostring(d.categoryV2 or "") ~= "" and d.categoryV2 or
                  (d.category or ""))
  for _, t in ipairs(string_split(tags, ",")) do
    t = string_trim(t)
    if t ~= "" then genres[#genres + 1] = translateVocab(t) end
  end
  return genres
end

-- creationStatus: '0' = 已完结 Finished, '1' = 连载中 Ongoing (both verified
-- against live finished/ongoing book pages on 2026-10-01).
function getBookStatus(bookUrl)
  local d = fetchBookState(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return nil end
  local s = tostring(d.creationStatus or "")
  if s == "" then return nil end
  if s == "0" then return translateVocab("已完结") end
  return translateVocab("连载中")
end

-- lastPublishTime = unix seconds (string) → "YYYY-MM-DD".
function getBookLastUpdate(bookUrl)
  local d = fetchBookState(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return nil end
  return epochToDate(d.lastPublishTime)
end

-- The official site exposes no per-book score → nil (search results from
-- the mirror backend show ratings in the catalog list instead).
function getBookRating(bookUrl)
  return nil
end

-- ── Chapter list ─────────────────────────────────────────────────────────────
-- The book page embeds the COMPLETE chapterListWithVolume — the same cached
-- request that answered the detail calls answers the TOC. The directory API
-- is a fallback for the rare page whose state lacks the list.

local function fetchToc(bookId)
  local pg = fetchBookState(bookId)
  local toc = pg and tocFromBookState(pg)
  if toc then return toc end
  return fetchDirectoryApi(bookId)
end

function getChapterList(bookUrl)
  local bookId = bookIdFromUrl(bookUrl)
  if not bookId then return {} end
  local items = fetchToc(bookId)
  if type(items) ~= "table" then return {} end

  local chapters = {}
  for i = 1, #items do
    chapters[#chapters + 1] = {
      title = dt(items[i].title),
      url   = SITE .. "/reader/" .. items[i].itemId
    }
  end

  if trActive() and trChaptersEnabled() and #chapters > 0 then
    local titles = {}
    for i = 1, #chapters do titles[i] = chapters[i].title end
    local tr = translateBatch(titles)
    for i = 1, #chapters do chapters[i].title = tr[i] end
  end

  return chapters
end

-- Change hash from the (cached) book page: chapter count + last publish
-- time. Both move whenever a new chapter drops — enough for the app's
-- "this book has updates" check without re-downloading the whole page.
function getChapterListHash(bookUrl)
  local bookId = bookIdFromUrl(bookUrl)
  if not bookId then return nil end
  local d = fetchBookState(bookId)
  if type(d) ~= "table" then return nil end
  local h = tostring(d.chapterTotal or "") .. "|" ..
            tostring(d.lastPublishTime or "")
  if h == "|" then return nil end
  return h
end

-- ── Chapter text ─────────────────────────────────────────────────────────────
-- The app downloads the chapter URL itself — fanqienovel.com serves the
-- SSR reader page to every user agent (verified: browser, okhttp, curl,
-- none) — and hands the HTML + URL to this function. The chapter body is
-- embedded in that very page; only when it is missing, locked (VIP) or the
-- font has rotated does the plugin fetch again / fall back to the mirror.
--
-- Order of attempts:
--   1. parse the PASSED html (zero extra requests)
--   2. fetch /reader/{itemId} ourselves (if the passed html was unusable)
--   3. font rotated or locked preview → mirror backend content (full text)
--   4. still nothing → the preview if we have one (marked), else show_error

function getChapterText(html, url)
  local itemId = string.match(url or "", "/reader/(%d+)")
              or string.match(url or "", "/book/%d+/(%d+)")
  if not itemId then return nil end

  local cd = chapterDataFromState(parseStateHtml(html))
  local readerState = nil

  -- 1-2. get a usable chapterData (prefer the passed page, fetch on miss)
  if type(cd) ~= "table" or type(cd.content) ~= "string" or cd.content == "" then
    readerState = fetchSitePage("/reader/" .. itemId, true)
    cd = chapterDataFromState(readerState)
  end

  local text = cd and contentToText(cd.content)

  -- font check (only when we have the full state around; the passed html's
  -- state works too — reparse only if needed)
  local fontHash = fontHashFromState(readerState)
  if not fontHash and type(html) == "string" then
    local st = parseStateHtml(html)
    fontHash = fontHashFromState(st)
    if st and not readerState then readerState = st end
  end
  local fontRotated = (fontHash ~= nil and fontHash ~= KNOWN_FONT_HASH)

  -- 3. locked preview / rotated font / missing text → mirror fallback
  if fontRotated or text == nil or isLockedPreview(cd, text) then
    local full = mirrorChapterText(itemId)
    if full then
      return full
    end
    -- 4. mirror down: return the (decoded) preview, clearly marked
    if text and not fontRotated then
      return "(⚠ preview only — the full text needs the mirror backend, " ..
             "which is down right now; retry in a minute)\n\n" .. text
    end
    show_error("FanqieNovel: chapter unavailable",
               "fanqienovel.com returned no text for this chapter and the " ..
               "mirror backend (used for VIP chapters) refused the request.\n\n" ..
               "Try again in a minute. Live health: Browse → Page → ⚡ Self-Test.")
    return nil
  end

  if not text then
    show_error("FanqieNovel: chapter unavailable",
               "The reader page for this chapter could not be parsed.\n\n" ..
               "Try again in a minute. Live health: Browse → Page → ⚡ Self-Test.")
    return nil
  end

  return text
end

-- ── Settings schema ─────────────────────────────────────────────────────────

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
