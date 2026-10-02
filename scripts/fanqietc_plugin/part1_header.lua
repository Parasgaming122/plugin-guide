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
