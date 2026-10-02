-- ═══════════════════════════════════════════════════════════════════════════
-- WTR-LAB source plugin for NoveLA
-- Version 1.1.9 (2026-09-03)
--
-- 1.1.9 (2026-09-03) — hotfix: catalog latency + tag visibility.
--
--   CATALOG LATENCY (the "10-15 s to load the homepage" fix):
--   • Root cause 1: the site's /_next/data/*.json routes now STALL
--     intermittently (observed 7-25 s per request, then 0.4 s minutes
--     later — server-side congestion/rate-shaping that affects the
--     app too). The HTML routes (/en/novel-list, /en/novel-finder)
--     render consistently fast (~0.5-1 s) and carry the EXACT SAME
--     pageProps (series, count, tags) inside __NEXT_DATA__.
--   • Root cause 2: every site redeploy changes the Next.js buildId,
--     so the persisted id goes stale → a 404 probe (itself up to 25 s
--     when the JSON routes are stalled) + a 262 KB HTML refresh + a
--     fresh JSON fetch — three round-trips before the first item.
--   • Fix: catalog/search/filtered now fetch the HTML route FIRST and
--     parse pageProps out of __NEXT_DATA__ — ONE request, no buildId,
--     no 404 probe. The _next/data JSON route is kept as automatic
--     fallback (with the buildId machinery) if the HTML route fails.
--   • Verified live: HTML route answers pagination (?page=2) and every
--     finder parameter (text=, ti=/te=/tc=, gi=/ge=/gc=, count_type=,
--     minr=, minrc=, status=, addition_age=, orderBy=) with the same
--     series/count values as the JSON route.
--
--   TAGS NOW SHOW UP (the site-like tag picker):
--   • 11 new "Tags: <category>" pickers (one per site category, 27-190
--     tags each, alphabetized by the app) — the tag list is VISIBLE
--     again after 1.1.8's keyword-only fields, but as compact dropdown
--     rows instead of the old 882-chip wall. Pick a tag to include it.
--   • Tag Search keyword fields got site-autocomplete-like feedback:
--     typing a short keyword (e.g. "sys") that matches SEVERAL tags no
--     longer silently ANDs them all (which returned ~0 novels) — it
--     now raises an error LISTING the matching tag names ("sys →
--     System, System Misunderstanding") so you can type the exact
--     name or add "*" to include every match at once.
--     Resolution order per keyword: exact label match → tag id →
--     single substring match → ambiguous (error with the list) /
--     "keyword*" wildcard (all substring matches).
--   • Tags picked in the dropdowns AND keywords both merge into the
--     same ti=/te= request (deduplicated).
--
-- 1.1.8 (2026-09-03) — maintenance release: performance + tag-filter UX.
--
--   Tag filters: search bar instead of the 882-chip wall (THE fix):
--   • The 11 category-grouped tristate pickers (882 eagerly-built chips)
--     are GONE. Finding one tag in a wall of ~900 chips was impractical
--     and made the filter sheet itself slow to open and scroll.
--   • Replaced by a compact "Tag Search" section:
--       – Tag Search (include) / (exclude): free-text keyword fields.
--         Comma-separate multiple keywords; multi-word phrases match as
--         phrases (e.g. "weak to strong"); numeric tag ids also accepted.
--       – Tag Search Category: one picker with "All categories" + the 11
--         site categories — scopes BOTH keyword fields to that category,
--         mirroring how the site's finder groups its tag list.
--       – Tag (And/Or) picker kept for the resolved set.
--     Keyword resolution happens at apply time; a keyword that matches
--     no tag raises a clear error instead of silently filtering nothing.
--   • Tag index refreshed from the live site: 882 → 888 tags (new:
--     Blue Archive, Food Wars!, Honkai Star Rails, Monster Hunter,
--     Dragon Raja, System Misunderstanding).
--
--   Novel finder inside the filters (search + filters in one place):
--   • New "Title Search" text filter — the app's global search bar has
--     no filter UI, so this puts the site's novel-finder text box into
--     the filter sheet: type a title keyword + combine with genres,
--     tags, status, chapter-count and every other finder filter, all in
--     one applied query (the finder JSON API's text= parameter).
--
--   Performance (chapter load "sometimes ~10 s" fix):
--   • Turnstile backoff cut 2500/5000 ms → 600/1800 ms: the app-level
--     counter only resets via a solved challenge, so long sleeps never
--     helped recovery — they only added up to 7.5 s of dead wait to a
--     3-attempt chain (the "10 seconds" symptom). Fast retries still
--     benefit from the per-instance intermittent enforcement.
--   • Glossary negative caching: books WITHOUT a v2 glossary were
--     re-fetched on EVERY chapter (the old code only cached when terms
--     existed). Now an empty glossary is cached once per book.
--   • Chapter-list/update hash via api/chapters (74 KB JSON) instead of
--     the full book page (250 KB HTML): library update checks are ~3x
--     lighter, and getChapterList + getChapterListHash share one
--     45-second cache, so opening a book fetches the chapter list once.
--   • buildId persisted via set_preference: the first catalog browse
--     after every app restart no longer downloads the 240 KB
--     novel-finder HTML just to extract the build id (a stale persisted
--     id still self-heals — fetchNextData refreshes it once on 404).
--
-- 1.1.7 (2026-08-26) — comprehensive upgrade on top of upstream 1.1.6.
--   Fixes two long-standing root causes of bad reader UX and adds full
--   novel-finder filter parity:
--
--   Gibberish-chapters fix (root cause):
--   • Chapter bodies returned as `arr:`/`str:` AES-256-GCM payloads by
--     /api/reader/get are now decrypted LOCALLY in pure Lua (no third-party
--     proxy round-trip needed). The old fly.dev proxy is kept only as an
--     automatic fallback, and a clear error is raised if both paths fail.
--     Previously, when fly.dev was slow/dead, the raw `arr:…` blob was
--     saved as the chapter text — this was the "large gibberish every
--     2-3 chapters" complaint.
--
--   "Security Check" / Turnstile fix (root cause):
--   • WTR-Lab has an APPLICATION-LEVEL per-IP rate limit on
--     /api/reader/get: once the counter crosses threshold (15), the API
--     returns HTTP 200 with `{"success":false,"requireTurnstile":true,…}`
--     and only submitting a valid turnstileToken resets it. The plugin now
--     detects this, retries with backoff (2 extra attempts — blocking is
--     per-instance and intermittent, so retries often land on a healthy
--     instance), and on persistent failure raises an actionable error
--     telling the user to solve the challenge once in the integrated
--     browser (instead of the old "[?] Unknown API error").
--   • IMPORTANT — do NOT add `cf_options = { whitelist = true }`:
--     NoveLA's CloudfareVerificationInterceptor ALREADY auto-detects
--     both real Cloudflare challenges AND wtr-lab's own `requireTurnstile`
--     JSON responses (marker + `server: cloudflare` + HTTP 200) and runs
--     the integrated WebView bypass ladder (hidden WebView → manual
--     WebViewActivity → retry). `whitelist = true` DISABLES that recovery
--     path for wtr-lab.com — the community v2.0.0 draft shipped it with a
--     comment claiming the opposite; keep it out.
--
--   Full novel-finder filter parity:
--   • Tag list expanded 208 → 882 (every tag the site exposes, incl.
--     Honghuang #801), split into 11 category-grouped tristate pickers
--     matching the site's own finder grouping (Protagonist / Power
--     Systems / Worldbuilding / Socio-Political / Relationships /
--     Narrative / Beings & Factions / Professional / Tone / Adaptations /
--     Misc). NoveLA renders every tristate option as an eagerly-built
--     chip, so a single 882-item list was a literal wall of chips.
--     getCatalogFiltered collects the included/excluded ids from all 11
--     groups into one combined ti=/te= list (single tc= operator applies
--     to the combined set — request params identical to a flat layout).
--   • Tag Search: two free-text filters (Tag Search include / exclude)
--     on top of the 11 grouped chip pickers. Type keywords like
--     "Honghuang, Naruto, adapted" and the plugin resolves them to the
--     matching tag IDs via case-insensitive substring matching against
--     all 882 tag labels, then merges the IDs into the same ti=/te=
--     params the chip pickers populate. Numeric IDs (e.g. "801") are
--     also accepted verbatim. Lets users find a specific tag in one
--     text field instead of scrolling through up to 190 chips per group.
--   • Added Minimum Reviews filter (minrc, 5-50 step 5); full
--     addition_age list (3month / 6month / last_month / last_year /
--     this_year); Daily View / Character Count / Weighted ordering.
--     WORKING chapter & character count filters via
--     count_type/count_filter/count_value (the old `minc=` parameter
--     was silently ignored by the site).
--
--   Catalog/search infrastructure:
--   • Switched from HTML scraping to the Next.js data JSON API
--     (/_next/data/{buildId}/en/novel-list.json / -finder.json) with
--     session buildId caching + stale-once refresh-retry. Reliable,
--     and the response's `count` field enables exact pagination:
--     `hasNext = #items > 0 and returned >= PAGE_SIZE and page *
--     PAGE_SIZE < countNum` (PAGE_SIZE = 10) — short-circuits on a
--     partial final page so it no longer over-fetches one empty page
--     at the end of a list. Note: the site returns `count` as a JSON
--     STRING (must tonumber() it).
--
--   Update detection:
--   • getChapterListHash now returns "<chapterCount>|<serie_data.updated_at>"
--     so re-translations / metadata edits that don't change the chapter
--     count are still detected. In 1.1.6 it returned the literal string
--     "Chapters" (both the label and the number span carry translate="no",
--     so html_select_first returned the label) — chapter-list updates were
--     NEVER detected.
--
--   Robustness:
--   • b64ToBytes now fails loud on a dangling base64 char (len%4==1)
--     instead of silently dropping it; the GCM tag check catches the
--     corruption anyway, but a nil lets the caller distinguish "malformed
--     input" from "decrypted garbage" and exercise the proxy fallback cleanly.
--   • cleanParagraph: line-anchored, word-bounded watermark/credit patterns
--
-- 1.2.1 (2026-09-18) — POSTER FIX: cover images are now served through the
--   wsrv.nl image proxy by default (new "Cover images" setting). Root cause:
--   wtr-lab's covers live on img.wtr-lab.com and are redirected (302 chain)
--   to signed full-size images (300KB+); when Cloudflare challenges the
--   image host, NoveLA's image loader gets the challenge page instead of
--   the JPEG (image URLs are exempt from the Cloudflare WebView bypass) and
--   the poster silently fails. wsrv.nl (images.weserv.nl) fetches
--   server-side, resizes to w=450, and is whitelisted by the engine for
--   exactly this pattern. "Direct" mode keeps the original URLs.
--
-- 1.2.0 (2026-09-10) — user-driven update:
--   • Paragraph safety: body elements that embed newlines are split so every
--     source line becomes its own paragraph (the reader merges text that only
--     carries single \n breaks); \r/\r\n normalized; all glossary/patch gsub
--     replacements are pattern-escaped + pcall-armored (terms with % or ()
--     used to kill the whole chapter with a Lua error).
--   • Multiple tags per category: the 11 tag category dropdowns are now
--     multi-select chip groups — tap several tags in one category.
--   • Tag Search now behaves like a real search: a partial keyword includes
--     EVERY tag whose name contains it (no more "ambiguous" error). Exact
--     names, raw ids and 'x*' wildcards still work.
--   • Tag discovery: the catalog search bar lists matching tags as tappable
--     results — open one to browse that tag's novels (most-read first, up to
--     100) and preview any novel's first chapter.
--   • Web+ mode (matches upstream 1.1.8): raw Chinese + book glossary terms
--     applied per paragraph (escaped), for use with the app translator.
--   • cleanParagraph: line-anchored, word-bounded watermark/credit patterns
--     with correctly-escaped \\s (the community v2.0.0 draft used single
--     backslashes → Lua string literal "s", making those patterns dead).
--   • Optional Chapter Fetch Delay setting (None/2s/4s/6s) — may reduce
--     "Security Check" triggers during bulk downloads, at the cost of speed.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Metadata ───────────────────────────────────────────────────────────────
id = "wtrlab"
name = "WTR-LAB"
version = "1.2.1"
baseUrl = "https://wtr-lab.com/"
language = "MTL"
icon = "https://raw.githubusercontent.com/HnDK0/external-sources/main/icons/wtr-lab.png"
description = "Machine-translated novels (wtr-lab.com). AI and raw (web) translation modes. Novel-finder filters with visible tag pickers, keyword tag search and title search. If a 'Security Check' error appears, open any chapter of the book in the integrated browser, complete the verification, then retry."

-- ── Settings keys ──────────────────────────────────────────────────────────
local PREF_MODE = "wtrlab_mode"           -- "ai" | "raw" | "webplus"  (key kept from 1.x so existing settings survive)
local PREF_DELAY = "wtrlab_chapter_delay" -- ms pause before each chapter fetch
local PREF_BUILDID = "wtrlab_buildid"     -- persisted Next.js buildId (survives app restarts)
local PREF_COVERS = "wtrlab_covers"       -- "proxy" (default) | "direct" — poster loading mode

-- ── Caches (live until app restart) ────────────────────────────────────────
local termCache = {}    -- [novelId] = { termByOriginal }
local _pageCache = {}   -- book page HTML
local _buildIdCache = nil
local _chaptersCache = {} -- [novelId] = { t = fetchedAtMs, chapters = {...} }

-- Millisecond clock with defensive fallbacks (os_time returns MILLISECONDS
-- in NoveLA; some builds lack it entirely — a probe counter still enables
-- short-TTL cache dedup without a clock).
local _clockFallback = 0
local function nowMs()
    local ok, v = pcall(function() return os_time() end)
    if ok and type(v) == "number" and v > 0 then
        if v < 100000000000 then v = v * 1000 end -- seconds → ms heuristic
        return v
    end
    _clockFallback = _clockFallback + 1
    return _clockFallback
end

local function getMode()
    local v = get_preference(PREF_MODE)
    return (v ~= "" and v) or "ai"
end

local function getChapterDelay()
    local v = tonumber(get_preference(PREF_DELAY))
    if v == nil or v < 0 then v = 0 end
    return v
end

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then
        return ""
    end
    if string_starts_with(href, "http") then
        return href
    end
    if string_starts_with(href, "//") then
        return "https:" .. href
    end
    return url_resolve(baseUrl, href)
end

-- ── Cover image proxy (1.2.1 poster fix) ─────────────────────────────────────
-- img.wtr-lab.com covers redirect to 300KB+ signed images and sit behind
-- Cloudflare; image URLs are EXEMPT from the engine's CF bypass
-- (STATIC_EXTENSIONS), so a challenged cover = broken poster. wsrv.nl is
-- the engine-whitelisted image proxy other NoveLA sources use for this.
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

local function fetchPage(url)
    if _pageCache[url] then
        return _pageCache[url]
    end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
    end
    return r.success and r.body or nil
end

-- Rating from the metrics block "Rating ★ 3.9 (563)" (book page + catalog cards)
local function extractRating(html)
    for _, el in ipairs(html_select(html, "div.items-center.text-center")) do
        local label = html_select_first(el.html, "span[translate='no']")
        if label and string_trim(label.text) == "Rating" then
            local m = regex_match(html_text(el.html), "([\\d.]+)")
            if m and m[1] then
                return m[1]
            end
        end
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Pure-Lua AES-256-GCM decryption (for `arr:` / `str:` encrypted chapter bodies)
--
-- Site-side scheme (reverse-engineered from wtr-lab's reader JS, verified
-- against live payloads): AES-256-GCM, static key below, payload format
--     arr:<b64 IV>:<b64 GCM tag>:<b64 ciphertext>   (body is a JSON array)
--     str:<b64 IV>:<b64 GCM tag>:<b64 ciphertext>   (body is one string)
-- The auth tag is NOT verified (unnecessary for display; skipping it avoids
-- a full GHASH implementation for the tag path).
-- ═══════════════════════════════════════════════════════════════════════════

local GCM_KEY = "IJAFUUxjM25hyzL2AZrn0wl7cESED6Ru"

-- F/byte XOR: use bit32 when the host provides it, else arithmetic fallback.
local HAS_BIT32 = (bit32 ~= nil and type(bit32) == "table" and type(bit32.bxor) == "function")

local function bxorB(a, b)
    if HAS_BIT32 then
        return bit32.bxor(a, b)
    end
    local r, p = 0, 1
    for _ = 1, 8 do
        local ab = a % 2
        local bb = b % 2
        if ab ~= bb then r = r + p end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        p = p * 2
    end
    return r
end

local function gmul2(a) -- xtime
    local h = a >= 128 and 1 or 0
    a = a * 2
    if a >= 256 then a = a - 256 end
    if h == 1 then a = bxorB(a, 27) end -- 0x1B
    return a
end

local function gmul3(a)
    return bxorB(gmul2(a), a)
end

-- AES S-box
local SBOX = {
    0x63,0x7C,0x77,0x7B,0xF2,0x6B,0x6F,0xC5,0x30,0x01,0x67,0x2B,0xFE,0xD7,0xAB,0x76,
    0xCA,0x82,0xC9,0x7D,0xFA,0x59,0x47,0xF0,0xAD,0xD4,0xA2,0xAF,0x9C,0xA4,0x72,0xC0,
    0xB7,0xFD,0x93,0x26,0x36,0x3F,0xF7,0xCC,0x34,0xA5,0xE5,0xF1,0x71,0xD8,0x31,0x15,
    0x04,0xC7,0x23,0xC3,0x18,0x96,0x05,0x9A,0x07,0x12,0x80,0xE2,0xEB,0x27,0xB2,0x75,
    0x09,0x83,0x2C,0x1A,0x1B,0x6E,0x5A,0xA0,0x52,0x3B,0xD6,0xB3,0x29,0xE3,0x2F,0x84,
    0x53,0xD1,0x00,0xED,0x20,0xFC,0xB1,0x5B,0x6A,0xCB,0xBE,0x39,0x4A,0x4C,0x58,0xCF,
    0xD0,0xEF,0xAA,0xFB,0x43,0x4D,0x33,0x85,0x45,0xF9,0x02,0x7F,0x50,0x3C,0x9F,0xA8,
    0x51,0xA3,0x40,0x8F,0x92,0x9D,0x38,0xF5,0xBC,0xB6,0xDA,0x21,0x10,0xFF,0xF3,0xD2,
    0xCD,0x0C,0x13,0xEC,0x5F,0x97,0x44,0x17,0xC4,0xA7,0x7E,0x3D,0x64,0x5D,0x19,0x73,
    0x60,0x81,0x4F,0xDC,0x22,0x2A,0x90,0x88,0x46,0xEE,0xB8,0x14,0xDE,0x5E,0x0B,0xDB,
    0xE0,0x32,0x3A,0x0A,0x49,0x06,0x24,0x5C,0xC2,0xD3,0xAC,0x62,0x91,0x95,0xE4,0x79,
    0xE7,0xC8,0x37,0x6D,0x8D,0xD5,0x4E,0xA9,0x6C,0x56,0xF4,0xEA,0x65,0x7A,0xAE,0x08,
    0xBA,0x78,0x25,0x2E,0x1C,0xA6,0xB4,0xC6,0xE8,0xDD,0x74,0x1F,0x4B,0xBD,0x8B,0x8A,
    0x70,0x3E,0xB5,0x66,0x48,0x03,0xF6,0x0E,0x61,0x35,0x57,0xB9,0x86,0xC1,0x1D,0x9E,
    0xE1,0xF8,0x98,0x11,0x69,0xD9,0x8E,0x94,0x9B,0x1E,0x87,0xE9,0xCE,0x55,0x28,0xDF,
    0x8C,0xA1,0x89,0x0D,0xBF,0xE6,0x42,0x68,0x41,0x99,0x2D,0x0F,0xB0,0x54,0xBB,0x16
}

local RCON = {0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1B,0x36,0x6C,0xD8,0xAB,0x4D}

-- AES-256 key expansion → flat round-key array of 15 * 16 bytes
local function aesExpandKey(keyBytes)
    -- keyBytes: 32 bytes; returns rk[1..240] (1-indexed flat)
    local w = {}          -- w[i] = 4-byte word tables, w[1..60]
    for i = 1, 8 do
        w[i] = { keyBytes[i * 4 - 3], keyBytes[i * 4 - 2], keyBytes[i * 4 - 1], keyBytes[i * 4] }
    end
    for i = 9, 60 do
        local t = { w[i - 1][1], w[i - 1][2], w[i - 1][3], w[i - 1][4] }
        if (i - 1) % 8 == 0 then
            -- RotWord + SubWord + Rcon
            t = { t[2], t[3], t[4], t[1] }
            for j = 1, 4 do t[j] = SBOX[t[j] + 1] end
            t[1] = bxorB(t[1], RCON[(i - 1) / 8 + 1 > 14 and 14 or (i - 1) / 8])
        elseif (i - 1) % 8 == 4 then
            for j = 1, 4 do t[j] = SBOX[t[j] + 1] end
        end
        local prev = w[i - 8]
        w[i] = {
            bxorB(prev[1], t[1]),
            bxorB(prev[2], t[2]),
            bxorB(prev[3], t[3]),
            bxorB(prev[4], t[4])
        }
    end
    -- flatten to round keys: rk[round][byte]
    local rk = {}
    for round = 0, 14 do
        for j = 1, 4 do
            local word = w[round * 4 + j]
            for b = 1, 4 do
                rk[round * 16 + (j - 1) * 4 + b] = word[b]
            end
        end
    end
    return rk
end

-- AES-256 encrypt one 16-byte block (state table mutated in place)
local function aesEncryptBlock(state, rk)
    -- AddRoundKey(0)
    for i = 1, 16 do state[i] = bxorB(state[i], rk[i]) end

    for round = 1, 13 do
        -- SubBytes
        for i = 1, 16 do state[i] = SBOX[state[i] + 1] end
        -- ShiftRows (state is column-major: s[c*4+r])
        local t
        t = state[2];  state[2]  = state[6];  state[6]  = state[10]; state[10] = state[14]; state[14] = t
        t = state[3];  state[3]  = state[11]; state[11] = t
        t = state[7];  state[7]  = state[15]; state[15] = t
        t = state[16]; state[16] = state[12]; state[12] = state[8];  state[8]  = state[4];  state[4]  = t
        -- MixColumns
        for c = 0, 3 do
            local i1 = c * 4 + 1
            local a0, a1, a2, a3 = state[i1], state[i1 + 1], state[i1 + 2], state[i1 + 3]
            state[i1]     = bxorB(bxorB(gmul2(a0), gmul3(a1)), bxorB(a2, a3))
            state[i1 + 1] = bxorB(bxorB(a0, gmul2(a1)), bxorB(gmul3(a2), a3))
            state[i1 + 2] = bxorB(bxorB(a0, a1), bxorB(gmul2(a2), gmul3(a3)))
            state[i1 + 3] = bxorB(bxorB(gmul3(a0), a1), bxorB(a2, gmul2(a3)))
        end
        -- AddRoundKey(round)
        local off = round * 16
        for i = 1, 16 do state[i] = bxorB(state[i], rk[off + i]) end
    end

    -- Final round (no MixColumns)
    for i = 1, 16 do state[i] = SBOX[state[i] + 1] end
    local t
    t = state[2];  state[2]  = state[6];  state[6]  = state[10]; state[10] = state[14]; state[14] = t
    t = state[3];  state[3]  = state[11]; state[11] = t
    t = state[7];  state[7]  = state[15]; state[15] = t
    t = state[16]; state[16] = state[12]; state[12] = state[8];  state[8]  = state[4];  state[4]  = t
    local off = 14 * 16
    for i = 1, 16 do state[i] = bxorB(state[i], rk[off + i]) end
    return state
end

-- GF(2^128) multiply for GHASH (right-shift algorithm, SP 800-38D)
local function gfMul(x, y)
    local z = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    local v = { y[1], y[2], y[3], y[4], y[5], y[6], y[7], y[8],
                y[9], y[10], y[11], y[12], y[13], y[14], y[15], y[16] }
    for i = 0, 127 do
        local byte = x[math.floor(i / 8) + 1]
        local bit = math.floor(byte / 2 ^ (7 - (i % 8))) % 2
        if bit == 1 then
            for j = 1, 16 do z[j] = bxorB(z[j], v[j]) end
        end
        local lsb = v[16] % 2
        for j = 16, 2, -1 do
            v[j] = math.floor(v[j] / 2) + (v[j - 1] % 2) * 128
        end
        v[1] = math.floor(v[1] / 2)
        if lsb == 1 then v[1] = bxorB(v[1], 0xE1) end
    end
    return z
end

-- GCM J0 derivation (IV here is 16 bytes → GHASH path; 12-byte IVs also handled)
local function gcmJ0(iv, H)
    if #iv == 12 then
        return { iv[1], iv[2], iv[3], iv[4], iv[5], iv[6], iv[7], iv[8],
                 iv[9], iv[10], iv[11], iv[12], 0, 0, 0, 1 }
    end
    -- J0 = GHASH_H(IV || 0^{s+64} || [len(IV)]_{64})
    local bitLen = #iv * 8
    local blocks = {}
    for i = 1, #iv do blocks[i] = iv[i] end
    local pad = (16 - (#iv % 16)) % 16
    for _ = 1, pad do blocks[#blocks + 1] = 0 end
    -- 8 zero bytes + 64-bit big-endian bit length (upper bytes are 0 for sane sizes)
    for _ = 1, 8 do blocks[#blocks + 1] = 0 end
    local lenBytes = { 0, 0, 0, 0, 0, 0, 0, 0 }
    local n = bitLen
    for i = 8, 1, -1 do
        lenBytes[i] = n % 256
        n = math.floor(n / 256)
    end
    for i = 1, 8 do blocks[#blocks + 1] = lenBytes[i] end

    local y = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    for start = 1, #blocks, 16 do
        local blk = {}
        for i = 1, 16 do blk[i] = blocks[start + i - 1] or 0 end
        for i = 1, 16 do y[i] = bxorB(y[i], blk[i]) end
        y = gfMul(y, H)
    end
    return y
end

local function inc32(block)
    local carry = 1
    for i = 16, 13, -1 do
        local v = block[i] + carry
        block[i] = v % 256
        carry = math.floor(v / 256)
        if carry == 0 then break end
    end
    return block
end

-- Pure-Lua base64 → byte table.
-- IMPORTANT: the host `base64_decode` returns a UTF-8 Java String, which
-- CORRUPTS binary data (IV/ciphertext bytes ≥ 0x80). Binary-safe decoding
-- must be done entirely in Lua via string.char/string.byte.
local B64DEC = {}
do
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #chars do
        B64DEC[string.byte(chars, i)] = i - 1
    end
end

local function b64ToBytes(s)
    s = string.gsub(s, "%s", "")
    s = string.gsub(s, "=", "")
    local out = {}
    local len = #s
    local i = 1
    while i + 3 <= len do
        local a = B64DEC[string.byte(s, i)]
        local b = B64DEC[string.byte(s, i + 1)]
        local c = B64DEC[string.byte(s, i + 2)]
        local d = B64DEC[string.byte(s, i + 3)]
        if not (a and b and c and d) then return nil end
        out[#out + 1] = string.char(
            a * 4 + math.floor(b / 16),
            (b % 16) * 16 + math.floor(c / 4),
            (c % 4) * 64 + d
        )
        i = i + 4
    end
    if i + 2 == len then
        -- 3 leftover chars (unpadded, encodes 2 bytes)
        local a = B64DEC[string.byte(s, i)]
        local b = B64DEC[string.byte(s, i + 1)]
        local c = B64DEC[string.byte(s, i + 2)]
        if not (a and b and c) then return nil end
        out[#out + 1] = string.char(
            a * 4 + math.floor(b / 16),
            (b % 16) * 16 + math.floor(c / 4)
        )
        i = i + 3
    elseif i + 1 == len then
        -- 2 leftover chars (unpadded, encodes 1 byte)
        local a = B64DEC[string.byte(s, i)]
        local b = B64DEC[string.byte(s, i + 1)]
        if not (a and b) then return nil end
        out[#out + 1] = string.char(a * 4 + math.floor(b / 16))
        i = i + 2
    end
    -- After the leftover branches, every input char must have been consumed
    -- (i == len + 1). A single dangling char (len % 4 == 1) is impossible to
    -- decode to any whole byte in either padded or unpadded base64, so fail
    -- loud here -- the GCM tag check would catch the corruption anyway, but a
    -- nil lets the caller distinguish "malformed" from "decrypted garbage".
    if i ~= len + 1 then return nil end
    local bytes = {}
    local n = 0
    for j = 1, #out do
        local part = out[j]
        for k = 1, #part do
            n = n + 1
            bytes[n] = string.byte(part, k)
        end
    end
    return bytes
end

-- Decrypt an "arr:"/"str:" payload → plaintext string (tag NOT verified)
local function gcmDecrypt(payload)
    local prefix = string.sub(payload, 1, 4)
    local body = string.sub(payload, 5)
    local parts = {}
    for part in string.gmatch(body, "[^:]+") do
        parts[#parts + 1] = part
    end
    if #parts ~= 3 then return nil, "bad payload format" end
    local iv = b64ToBytes(parts[1])
    local ct = b64ToBytes(parts[3])
    if not iv or not ct or #iv < 1 or #ct < 1 then return nil, "bad base64" end

    local keyBytes = {}
    for i = 1, 32 do keyBytes[i] = string.byte(GCM_KEY, i) end
    local rk = aesExpandKey(keyBytes)

    -- H = AES_K(0^128)
    local H = aesEncryptBlock({ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, rk)
    local j0 = gcmJ0(iv, H)

    -- CTR decrypt starting from inc32(J0)
    local counter = { j0[1], j0[2], j0[3], j0[4], j0[5], j0[6], j0[7], j0[8],
                      j0[9], j0[10], j0[11], j0[12], j0[13], j0[14], j0[15], j0[16] }
    local out = {}
    for start = 1, #ct, 16 do
        counter = inc32(counter)
        local ks = aesEncryptBlock({ counter[1], counter[2], counter[3], counter[4],
                                     counter[5], counter[6], counter[7], counter[8],
                                     counter[9], counter[10], counter[11], counter[12],
                                     counter[13], counter[14], counter[15], counter[16] }, rk)
        for i = 1, 16 do
            local idx = start + i - 1
            if idx <= #ct then
                out[#out + 1] = string.char(bxorB(ct[idx], ks[i]))
            end
        end
    end
    return table.concat(out), prefix
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter body decryption: local AES-GCM first, fly.dev proxy as fallback
-- ═══════════════════════════════════════════════════════════════════════════

local function decryptBody(rawBody)
    if not string_starts_with(rawBody, "arr:") and not string_starts_with(rawBody, "str:") then
        return rawBody
    end

    -- 1) Local decryption (preferred — no third party involved)
    local ok, plaintext, errOrPrefix = pcall(gcmDecrypt, rawBody)
    if ok and plaintext and #plaintext > 0 then
        log_info("wtrlab: decrypted body locally (" .. tostring(errOrPrefix) .. ", " .. tostring(#plaintext) .. " chars)")
        return plaintext
    end
    log_error("wtrlab: local AES-GCM decrypt failed (ok=" .. tostring(ok) ..
        " err=" .. tostring(plaintext ~= nil and plaintext or errOrPrefix) .. ")")

    -- 2) Fallback: public decrypt proxy (as used by plugin v1.x)
    local r = http_post("https://wtr-lab-proxy.fly.dev/chapter", json_stringify({
        payload = rawBody
    }), {
        headers = {
            ["Content-Type"] = "application/json"
        }
    })
    if not r.success then
        log_error("wtrlab: decrypt proxy failed code=" .. tostring(r.code))
        return nil
    end
    local data = json_parse(r.body)
    if type(data) == "table" then
        if data[1] ~= nil then
            return json_stringify(data)
        end
        if data.body ~= nil then
            return json_stringify(data.body)
        end
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Next.js data API (catalog / search / filters)
-- ═══════════════════════════════════════════════════════════════════════════

local function getBuildId(force)
    if _buildIdCache and not force then
        return _buildIdCache
    end
    -- 1) Persisted buildId (survives app restarts). Validated lazily:
    --    if the site redeployed, fetchNextData's stale-retry refreshes it.
    if not force then
        local saved = get_preference(PREF_BUILDID)
        if saved ~= nil and saved ~= "" then
            _buildIdCache = saved
            return saved
        end
    end
    -- 2) Fetch a page that carries __NEXT_DATA__ and read the build id.
    local fr = http_get(baseUrl .. "en/novel-finder")
    if not fr.success then
        return _buildIdCache
    end
    local buildId = string.match(fr.body, '"buildId":"([^"]+)"')
    if buildId then
        _buildIdCache = buildId
        pcall(function() set_preference(PREF_BUILDID, buildId) end)
    end
    return buildId
end

-- Fetch a _next/data JSON page. Refreshes a stale buildId once and retries.
-- Returns pageProps table or nil.
local function fetchNextData(pathPattern, params)
    for attempt = 1, 2 do
        -- attempt 2 forces an HTML refresh (bypasses the possibly-stale
        -- persisted buildId instead of returning it again)
        local buildId = getBuildId(attempt == 2)
        if not buildId then
            return nil
        end
        local url = baseUrl .. "_next/data/" .. buildId .. pathPattern .. "?" .. params
        local r = http_get(url)
        if r.success then
            local data = json_parse(r.body)
            if data and data.pageProps then
                -- Confirmed working: keep it cached and persisted
                if _buildIdCache ~= buildId then _buildIdCache = buildId end
                pcall(function() set_preference(PREF_BUILDID, buildId) end)
                return data.pageProps
            end
        end
        -- 404 / unexpected shape → buildId is stale (site redeployed): retry once
        if attempt == 1 then
            log_info("wtrlab: stale buildId, refreshing")
            _buildIdCache = nil
        end
    end
    return nil
end

-- ── HTML-first pageProps fetch (v1.1.9) ─────────────────────────────────────
-- The site's _next/data/*.json routes intermittently STALL server-side
-- (observed 7-25 s per request, recovering to ~0.4 s minutes later),
-- while the HTML routes render consistently fast and embed the EXACT
-- SAME pageProps (series / count / tags) in __NEXT_DATA__. Fetching the
-- HTML route removes the buildId dependency (and its stale-404 probe)
-- from the hot path entirely: the first catalog page costs ONE request.
local function extractNextDataProps(html)
    if not html then return nil end
    local json = string.match(html, '<script%s+id="__NEXT_DATA__"[^>]*>(.-)</script>')
    if not json or json == "" then return nil end
    local ok, data = pcall(json_parse, json)
    if ok and type(data) == "table" then
        -- HTML pages embed the props in the standard Next.js __NEXT_DATA__
        -- shape: {"props":{"pageProps":{...}},"buildId":...}; the _next/data
        -- JSON routes return {"pageProps":{...}} at the TOP level. Both carry
        -- the exact same pageProps (series / count / tags) — accept either.
        local pp = data.pageProps
        if type(pp) ~= "table" and type(data.props) == "table" then
            pp = data.props.pageProps
        end
        if type(pp) == "table" then
            return pp
        end
    end
    return nil
end

local function fetchPagePropsHTML(route, params)
    local url = baseUrl .. route .. (params and ("?" .. params) or "")
    local r = http_get(url)
    if not r.success then
        return nil
    end
    return extractNextDataProps(r.body)
end

-- Catalog page fetch: HTML route first (fast, buildId-free), _next/data
-- JSON route as fallback. route = "en/novel-list" | "en/novel-finder";
-- jsonPath = "/en/novel-list.json" | "/en/novel-finder.json".
local function fetchCatalogPage(route, jsonPath, params)
    local pp = fetchPagePropsHTML(route, params)
    if pp and pp.series then
        return pp
    end
    log_info("wtrlab: HTML route failed, falling back to _next/data JSON")
    return fetchNextData(jsonPath, params)
end

local function seriesToItems(series)
    local seen = {}
    local items = {}
    for _, novel in ipairs(series) do
        local rawId = tostring(novel.raw_id or "")
        if rawId ~= "" and not seen[rawId] then
            seen[rawId] = true
            local title = (novel.data and novel.data.title) or ""
            local cover = (novel.data and novel.data.image) or ""
            local slug = novel.slug or ""
            local item = {
                title = string_clean(title),
                url = baseUrl .. "en/novel/" .. rawId .. "/" .. slug,
                cover = coverUrl(absUrl(cover))
            }
            if novel.rating ~= nil then
                item.rating = tostring(novel.rating)
            end
            table.insert(items, item)
        end
    end
    return items
end

-- The site paginates catalog/finder results at a fixed 10 items per page
-- (verified for both novel-list.json and novel-finder.json). Used to
-- short-circuit pagination on a short final page without relying on the
-- (post-dedup) item count, which would mis-count if the API ever returned
-- a duplicate raw_id within one page.
local PAGE_SIZE = 10

local function pagePropsToResult(pp, page)
    if not pp or not pp.series then
        return { items = {}, hasNext = false }
    end
    local items = seriesToItems(pp.series)
    local returned = #pp.series
    -- NOTE: the site returns "count" as a JSON *string* — coerce it
    local countNum = tonumber(pp.count)
    local hasNext
    if countNum ~= nil then
        -- Two conditions must both hold: the page was full (a short page is
        -- always the last one, regardless of what `count` claims), AND there
        -- are more items past this page by the fixed page size. The old
        -- `page * #items < countNum` used the (variable) returned count,
        -- which on a partial final page (e.g. count=12, page 2 returns 2)
        -- evaluated to 2*2<12 = true and fetched a 3rd empty page.
        hasNext = #items > 0 and returned >= PAGE_SIZE and page * PAGE_SIZE < countNum
    else
        -- No total count: assume more pages only when the page was full.
        hasNext = returned >= PAGE_SIZE
    end
    return { items = items, hasNext = hasNext }
end


-- ── Tag search index & resolver (v2) ─────────────────────────────────────
-- Auto-generated by scripts/gen_tag_search_index_v2.py from the live
-- /en/novel-finder __NEXT_DATA__ snapshot (research/tags_live_v2.json;
-- 888 tags as of 2026-09-03). Do not hand-edit; re-run the generator
-- after refreshing the snapshot.
--
-- Format: one "id|Label|catId" triple per line. Parsed once at plugin
-- load into ALL_TAGS ({id, label=display case, lower=match key, cat});
-- TAG_CATEGORIES holds the 11 site category names for the Tag Search
-- Category picker.
--
-- tagSearchResolve(text, cat) → dedup'd list of tag ids matching any
-- comma/semicolon-separated token (multi-word tokens match as phrases
-- first, per-word as fallback; numeric tokens are ids). cat scopes
-- matching to one category ("0"/nil = all categories).

local TAG_CATEGORIES = {
    { id = "0",  label = "All Categories" },
    { id = "1",  label = "Protagonist Archetypes (190)" },
    { id = "2",  label = "Power Systems (100)" },
    { id = "3",  label = "Worldbuilding (56)" },
    { id = "4",  label = "Socio-Political Structures (71)" },
    { id = "5",  label = "Relationship Tropes (136)" },
    { id = "6",  label = "Narrative (46)" },
    { id = "7",  label = "Beings & Factions (68)" },
    { id = "8",  label = "Professional Archetypes (64)" },
    { id = "9",  label = "Tone & Atmosphere (27)" },
    { id = "10", label = "Adaptations (90)" },
    { id = "11", label = "Miscellaneous Narrative Elements (40)" },
}

local TAG_SEARCH_INDEX = [==[
1|Abandoned Children|1
2|Ability Steal|2
3|Absent Parents|1
4|Abusive Characters|9
5|Academy|4
6|Accelerated Growth|1
7|Acting|8
8|Adapted from Manga|10
9|Adapted from Manhua|10
10|Adapted to Anime|10
11|Adapted to Drama|10
12|Adapted to Drama CD|10
13|Adapted to Game|10
14|Adapted to Manga|10
15|Adapted to Manhua|10
16|Adapted to Manhwa|10
17|Adapted to Movie|10
18|Adapted to Visual Novel|10
19|Adopted Children|1
20|Adopted Protagonist|1
21|Adultery|5
22|Adventurers|7
23|Affair|5
24|Age Progression|1
25|Age Regression|1
26|Aggressive Characters|1
27|Alchemy|2
28|Aliens|7
29|All-Girls School|4
30|Alternate World|3
31|Amnesia|6
32|Amusement Park|3
33|Anal|5
34|Ancient China|3
35|Ancient Times|3
36|Androgynous Characters|1
37|Androids|2
38|Angels|7
39|Animal Characteristics|11
40|Animal Rearing|11
41|Anti-Magic|2
42|Anti-social Protagonist|1
43|Antihero Protagonist|1
44|Antique Shop|8
45|Apartment Life|11
46|Apathetic Protagonist|1
47|Apocalypse|3
48|Appearance Changes|2
49|Appearance Different from Actual Age|1
50|Archery|8
51|Aristocracy|4
52|Arms Dealers|4
53|Army|4
54|Army Building|4
55|Arranged Marriage|5
56|Arrogant Characters|1
57|Artifact Crafting|11
58|Artifacts|11
59|Artificial Intelligence|2
60|Artists|8
61|Assassins|4
62|Astrologers|7
63|Autism|1
64|Automatons|2
65|Average-looking Protagonist|1
66|Award-winning Work|10
67|Awkward Protagonist|1
68|Bands|8
69|Based on a Movie|10
70|Based on a Song|10
71|Based on a TV Show|10
72|Based on a Video Game|10
73|Based on a Visual Novel|10
74|Based on an Anime|10
75|Battle Academy|4
76|Battle Competition|4
77|BDSM|5
78|Beast Companions|7
79|Beastkin|7
80|Beasts|7
81|Beautiful Female Lead|1
82|Bestiality|5
83|Betrayal|6
84|Bickering Couple|5
85|Biochip|2
86|Bisexual Protagonist|1
87|Black Belly|1
88|Blackmail|5
89|Blacksmith|8
90|Blind Dates|5
91|Blind Protagonist|1
92|Blood Manipulation|2
93|Bloodlines|2
94|Body Swap|2
95|Body Tempering|2
96|Body-double|11
97|Bodyguards|8
98|Books|11
99|Bookworm|1
100|Boss-Subordinate Relationship|4
101|Brainwashing|2
102|Breast Fetish|5
103|Broken Engagement|5
104|Brother Complex|5
105|Brotherhood|5
106|Buddhism|11
107|Bullying|9
108|Business Management|4
109|Businessmen|8
110|Butlers|8
111|Calm Protagonist|1
112|Cannibalism|6
113|Card Games|11
114|Carefree Protagonist|1
115|Caring Protagonist|1
116|Cautious Protagonist|1
117|Celebrities|8
118|Character Growth|1
119|Charismatic Protagonist|1
120|Charming Protagonist|1
121|Chat Rooms|6
122|Cheats|2
123|Chefs|8
124|Child Abuse|5
125|Child Protagonist|1
126|Childcare|11
127|Childhood Friends|5
128|Childhood Love|5
129|Childhood Promise|5
130|Childish Protagonist|1
131|Chuunibyou|1
132|Clan Building|4
133|Classic|3
134|Clever Protagonist|1
135|Clingy Lover|5
136|Clones|2
137|Clubs|4
138|Clumsy Love Interests|5
139|Co-Workers|11
140|Cohabitation|11
141|Cold Love Interests|5
142|Cold Protagonist|1
143|Collection of Short Stories|6
144|College/University|11
145|Coma|1
146|Comedic Undertone|9
147|Coming of Age|1
148|Complex Family Relationships|5
149|Conditional Power|2
150|Confident Protagonist|1
151|Confinement|5
152|Conflicting Loyalties|6
153|Contracts|4
154|Cooking|11
155|Corruption|9
156|Cosmic Wars|4
157|Cosplay|8
158|Couple Growth|1
159|Court Official|4
160|Cousins|5
161|Cowardly Protagonist|1
162|Crafting|4
163|Crime|6
164|Criminals|6
165|Cross-dressing|1
166|Crossover|6
167|Cruel Characters|9
168|Cryostasis|2
169|Cultivation|2
170|Cunnilingus|5
171|Cunning Protagonist|1
172|Curious Protagonist|1
173|Curses|2
174|Cute Children|11
175|Cute Protagonist|1
176|Cute Story|9
177|Dancers|8
178|Dao Companion|2
179|Dao Comprehension|2
180|Daoism|11
181|Dark|9
182|Dead Protagonist|1
183|Death|6
184|Death of Loved Ones|5
185|Debts|4
186|Delinquents|1
187|Delusions|6
188|Demi-Humans|7
189|Demon Lord|7
190|Demonic Cultivation Technique|2
191|Demons|7
192|Dense Protagonist|1
193|Depictions of Cruelty|9
194|Depression|9
195|Destiny|9
196|Detectives|8
197|Determined Protagonist|1
198|Devoted Love Interests|5
199|Different Social Status|5
200|Disabilities|1
201|Discrimination|9
202|Disfigurement|11
203|Dishonest Protagonist|1
204|Distrustful Protagonist|1
205|Divination|2
206|Divine Protection|2
207|Divorce|5
208|Doctors|8
209|Dolls/Puppets|11
210|Domestic Affairs|11
211|Doting Love Interests|5
212|Doting Older Siblings|1
213|Doting Parents|1
214|Dragon Riders|8
215|Dragon Slayers|8
216|Dragons|7
217|Dreams|11
218|Drugs|4
219|Druids|7
220|Dungeon Master|2
221|Dungeons|3
222|Dwarfs|7
223|Dystopia|3
224|e-Sports|8
225|Early Romance|5
226|Earth Invasion|4
227|Easy Going Life|11
228|Economics|4
229|Editors|8
230|Eidetic Memory|2
231|Elderly Protagonist|1
232|Elemental Magic|2
233|Elves|7
234|Emotionally Weak Protagonist|1
235|Empires|4
236|Enemies Become Allies|5
237|Enemies Become Lovers|5
238|Engagement|5
239|Engineer|7
240|Enlightenment|1
241|Episodic|6
242|Eunuch|4
243|European Ambience|3
244|Evil Gods|7
245|Evil Organizations|7
246|Evil Protagonist|1
247|Evil Religions|4
248|Evolution|1
249|Exhibitionism|5
250|Exorcism|2
251|Eye Powers|2
252|Fairies|7
253|Fallen Angels|7
254|Fallen Nobility|1
255|Familial Love|5
256|Familiars|7
257|Family|5
258|Family Business|4
259|Family Conflict|5
260|Famous Parents|1
261|Famous Protagonist|1
262|Fanaticism|9
264|Fantasy Creatures|7
265|Fantasy World|3
266|Farming|4
267|Fast Cultivation|2
268|Fast Learner|1
269|Fat Protagonist|1
270|Fat to Fit|1
271|Fated Lovers|5
272|Fearless Protagonist|1
273|Fellatio|5
274|Female Master|8
275|Female Protagonist|1
276|Female to Male|1
277|Feng Shui|11
278|Firearms|2
279|First Love|5
280|First-time Intercourse|5
281|Flashbacks|6
282|Fleet Battles|4
283|Folklore|11
284|Forced into a Relationship|5
285|Forced Living Arrangements|5
286|Forced Marriage|5
287|Forgetful Protagonist|1
288|Former Hero|1
289|Fox Spirits|7
290|Friends Become Enemies|5
291|Friendship|9
292|Fujoshi|1
293|Futanari|5
294|Futuristic Setting|3
295|Galge|2
296|Gambling|4
297|Game Elements|2
298|Game Ranking System|2
299|Gamers|8
300|Gangs|4
301|Gate to Another World|3
302|Genderless Protagonist|1
303|Generals|4
304|Genetic Modifications|2
305|Genies|2
306|Genius Protagonist|1
307|Ghosts|7
308|Gladiators|4
309|Glasses-wearing Love Interests|5
310|Glasses-wearing Protagonist|1
311|Goblins|7
312|God Protagonist|1
313|God-human Relationship|7
314|Goddesses|7
315|Godly Powers|2
316|Gods|7
317|Golems|7
318|Gore|6
319|Grave Keepers|7
320|Grinding|2
321|Guardian Relationship|5
322|Guilds|4
323|Gunfighters|8
324|Hackers|8
325|Half-human Protagonist|1
326|Handjob|5
327|Handsome Male Lead|1
328|Hard-Working Protagonist|1
329|Harem-seeking Protagonist|5
330|Harsh Training|1
331|Hated Protagonist|1
332|Healers|2
333|Heartwarming|9
334|Heaven|3
335|Heavenly Tribulation|2
336|Hell|3
337|Helpful Protagonist|1
338|Herbalist|7
339|Heroes|7
340|Heterochromia|11
341|Hidden Abilities|2
342|Hiding True Abilities|1
343|Hiding True Identity|1
344|Hikikomori|1
345|Homunculus|7
346|Honest Protagonist|1
347|Hospital|3
348|Hot-blooded Protagonist|1
349|Human Experimentation|6
350|Human Weapon|1
351|Human-Nonhuman Relationship|5
352|Humanoid Protagonist|1
353|Hunters|4
354|Hypnotism|2
355|Identity Crisis|6
356|Imaginary Friend|6
357|Immortals|7
358|Imperial Harem|4
359|Incest|5
360|Incubus|7
361|Indecisive Protagonist|1
362|Industrialization|4
363|Inferiority Complex|1
364|Inheritance|6
365|Inscriptions|2
366|Insects|7
367|Interconnected Storylines|6
368|Interdimensional Travel|3
369|Introverted Protagonist|1
370|Investigations|6
371|Invisibility|2
372|Jack of All Trades|11
373|Jealousy|5
374|Jiangshi|7
375|Jobless Class|1
376|JSDF|4
377|Kidnappings|5
378|Kind Love Interests|5
379|Kingdom Building|4
380|Kingdoms|4
381|Knights|4
382|Kuudere|1
383|Lack of Common Sense|1
384|Language Barrier|11
385|Late Romance|5
386|Lawyers|8
387|Lazy Protagonist|1
388|Leadership|4
389|Legends|7
390|Level System|2
391|Library|3
392|Limited Lifespan|1
393|Living Abroad|11
394|Living Alone|11
395|Loli|1
396|Loneliness|9
397|Loner Protagonist|1
398|Long Separations|5
399|Long-distance Relationship|5
400|Lost Civilizations|3
401|Lottery|2
402|Love at First Sight|5
403|Love Interest Falls in Love First|5
404|Love Rivals|5
405|Love Triangles|5
406|Lovers Reunited|5
407|Low-key Protagonist|1
408|Loyal Subordinates|4
409|Lucky Protagonist|1
410|Magic|2
411|Magic Beasts|7
412|Magic Formations|2
413|Magical Girls|2
414|Magical Space|2
415|Magical Technology|2
416|Maids|8
417|Male Protagonist|1
418|Male to Female|1
419|Male Yandere|5
420|Management|4
421|Mangaka|8
422|Manipulative Characters|1
423|Manly Gay Couple|5
424|Marriage|5
425|Marriage of Convenience|5
426|Martial Spirits|2
427|Masochistic Characters|1
428|Master-Disciple Relationship|4
429|Master-Servant Relationship|4
430|Masturbation|5
431|Matriarchy|4
432|Mature Protagonist|1
433|Medical Knowledge|8
434|Medieval|3
435|Mercenaries|8
436|Merchants|8
437|Military|4
438|Mind Break|5
439|Mind Control|2
440|Misandry|11
441|Mismatched Couple|5
442|Misunderstandings|9
443|MMORPG|2
444|Mob Protagonist|1
445|Models|8
446|Modern Day|3
447|Modern Knowledge|1
448|Money Grubber|4
449|Monster Girls|7
450|Monster Society|3
451|Monster Tamer|7
452|Monsters|7
453|Movies|8
454|Mpreg|3
455|Multiple Identities|6
456|Multiple Personalities|1
457|Multiple POV|6
458|Multiple Protagonists|1
459|Multiple Realms|3
460|Multiple Reincarnated Individuals|3
461|Multiple Timelines|3
462|Multiple Transported Individuals|3
463|Murders|6
464|Music|8
465|Mutated Creatures|7
466|Mutations|7
467|Mute Character|1
468|Mysterious Family Background|1
469|Mysterious Illness|9
470|Mysterious Past|6
471|Mystery Solving|6
472|Mythical Beasts|7
473|Mythology|11
474|Naive Protagonist|1
475|Narcissistic Protagonist|1
476|Nationalism|9
477|Near-Death Experience|1
478|Necromancer|2
479|Neet|1
480|Netorare|5
481|Netorase|5
482|Netori|5
483|Nightmares|6
484|Ninjas|7
485|Nobles|4
486|Non-humanoid Protagonist|1
487|Non-linear Storytelling|6
488|Nudity|5
489|Nurses|8
490|Obsessive Love|5
491|Office Romance|5
492|Older Love Interests|5
493|Omegaverse|3
494|Oneshot|6
495|Online Romance|5
496|Onmyouji|2
497|Orcs|7
498|Organized Crime|6
499|Orgy|5
500|Orphans|1
501|Otaku|11
502|Otome Game|2
503|Outcasts|1
504|Outdoor Intercourse|5
505|Outer Space|3
506|Overpowered Protagonist|1
507|Overprotective Siblings|5
508|Pacifist Protagonist|1
509|Paizuri|5
510|Parallel Worlds|3
511|Parasites|2
512|Parent Complex|5
513|Parody|6
514|Part-Time Job|8
515|Past Plays a Big Role|6
516|Past Trauma|1
517|Persistent Love Interests|5
518|Personality Changes|1
519|Perverted Protagonist|1
520|Pets|11
521|Pharmacist|8
522|Philosophical|9
523|Phobias|9
524|Phoenixes|7
525|Photography|8
526|Pill Based Cultivation|2
527|Pill Concocting|2
528|Pilots|8
529|Pirates|4
530|Playboys|1
531|Playful Protagonist|1
532|Poetry|8
533|Poisons|8
534|Police|7
535|Polite Protagonist|1
536|Politics|4
537|Polyandry|5
538|Polygamy|5
539|Poor Protagonist|1
540|Poor to Rich|4
541|Popular Love Interests|5
542|Possession|2
543|Possessive Characters|5
544|Post-apocalyptic|3
545|Power Couple|5
546|Power Struggle|6
547|Pragmatic Protagonist|1
548|Precognition|2
549|Pregnancy|5
550|Pretend Lovers|5
551|Previous Life Talent|1
552|Priestesses|7
553|Priests|7
554|Prison|3
555|Proactive Protagonist|1
556|Programmer|8
557|Prophecies|6
558|Prostitutes|5
559|Protagonist Falls in Love First|5
560|Protagonist Strong from the Start|1
561|Protagonist with Multiple Bodies|2
562|Psychic Powers|2
563|Psychopaths|1
564|Puppeteers|8
565|Quiet Characters|1
566|Quirky Characters|1
567|R-15|9
568|R-18|5
569|Race Change|1
570|Racism|9
571|Rape|5
572|Rape Victim Becomes Lover|5
573|Rebellion|6
574|Reincarnated as a Monster|1
575|Reincarnated as an Object|1
576|Reincarnated in a Game World|2
577|Reincarnated in Another World|1
578|Reincarnation|1
579|Religions|4
580|Reluctant Protagonist|1
581|Reporters|8
582|Restaurant|3
583|Resurrection|2
584|Returning from Another World|1
585|Revenge|6
586|Reverse Harem|5
587|Reverse Rape|5
588|Reversible Couple|5
589|Rich to Poor|4
590|Righteous Protagonist|1
591|Rivalry|6
592|Romantic Subplot|5
593|Roommates|11
594|Royalty|4
595|Ruthless Protagonist|1
596|Sadistic Characters|1
597|Saints|7
598|Salaryman|1
599|Samurai|4
600|Saving the World|6
601|Schemes And Conspiracies|6
602|Schizophrenia|1
603|Scientists|8
604|Sculptors|8
605|Sealed Power|1
606|Second Chance|1
607|Secret Crush|5
608|Secret Identity|6
609|Secret Organizations|4
610|Secret Relationship|5
611|Secretive Protagonist|1
612|Secrets|6
613|Sect Development|4
614|Seduction|5
615|Seeing Things Other Humans Can't|2
616|Selfish Protagonist|1
617|Selfless Protagonist|1
618|Seme Protagonist|1
619|Senpai-Kouhai Relationship|5
620|Sentient Objects|7
621|Sentimental Protagonist|1
622|Serial Killers|8
623|Servants|8
624|Seven Deadly Sins|7
625|Seven Virtues|7
626|Sex Friends|5
627|Sex Slaves|5
628|Sexual Abuse|5
629|Sexual Cultivation Technique|2
630|Shameless Protagonist|1
631|Shapeshifters|2
632|Sharing A Body|2
633|Sharp-tongued Characters|1
634|Shield User|8
635|Shikigami|7
636|Short Story|6
637|Shota|1
638|Shoujo-Ai Subplot|5
639|Shounen-Ai Subplot|5
640|Showbiz|8
641|Shy Characters|1
642|Sibling Rivalry|5
643|Sibling's Care|5
644|Siblings|5
645|Siblings Not Related by Blood|5
646|Sickly Characters|9
647|Sign Language|11
648|Singers|8
649|Single Parent|5
650|Sister Complex|5
651|Skill Assimilation|1
652|Skill Books|2
653|Skill Creation|1
654|Slave Harem|5
655|Slave Protagonist|1
656|Slaves|4
657|Sleeping|11
658|Slow Growth at Start|1
659|Slow Romance|5
660|Smart Couple|5
661|Social Outcasts|9
662|Soldiers|8
663|Soul Power|2
664|Souls|7
665|Spatial Manipulation|2
666|Spear Wielder|8
667|Special Abilities|2
668|Spies|8
669|Spirit Advisor|7
670|Spirit Users|2
671|Spirits|7
672|Stalkers|5
673|Stockholm Syndrome|5
674|Stoic Characters|1
675|Store Owner|8
676|Straight Seme|1
677|Straight Uke|1
678|Strategic Battles|4
679|Strategist|7
680|Strength-based Social Hierarchy|4
681|Strong Love Interests|5
682|Strong to Stronger|1
683|Stubborn Protagonist|1
684|Student Council|4
685|Student-Teacher Relationship|4
686|Succubus|7
687|Sudden Strength Gain|1
688|Sudden Wealth|4
689|Suicides|9
690|Summoned Hero|1
691|Summoning Magic|2
692|Survival|6
693|Survival Game|2
694|Sword And Magic|2
695|Sword Wielder|7
696|System|2
697|Teachers|8
698|Teamwork|4
699|Technological Gap|3
700|Tentacles|7
701|Terminal Illness|9
702|Terrorists|4
703|Thieves|8
704|Threesome|5
705|Thriller|6
706|Time Loop|3
707|Time Manipulation|2
708|Time Paradox|3
709|Time Skip|6
710|Time Travel|3
711|Timid Protagonist|1
712|Tomboyish Female Lead|1
713|Torture|5
714|Toys|5
715|Tragic Past|1
716|Transformation Ability|2
717|Transmigration|1
718|Transplanted Memories|1
719|Transported into a Game World|1
720|Transported Modern Structure|3
721|Transported to Another World|1
722|Trap|1
723|Tribal Society|3
724|Trickster|1
725|Tsundere|5
726|Twins|5
727|Twisted Personality|1
728|Ugly Protagonist|1
729|Ugly to Beautiful|11
730|Unconditional Love|5
731|Underestimated Protagonist|1
732|Unique Cultivation Technique|2
733|Unique Weapon User|8
734|Unique Weapons|11
735|Unlimited Flow|2
736|Unlucky Protagonist|1
737|Unreliable Narrator|1
738|Unrequited Love|5
739|Valkyries|7
740|Vampires|7
741|Villainess Noble Girls|1
742|Virtual Reality|2
743|Vocaloid|10
744|Voice Actors|8
745|Voyeurism|5
746|Waiters|8
747|War Records|4
748|Wars|4
749|Weak Protagonist|1
750|Weak to Strong|1
751|Wealthy Characters|4
752|Werebeasts|7
753|Wishes|2
754|Witches|7
755|Wizards|2
756|World Hopping|3
757|World Travel|3
758|World Tree|3
759|Writers|8
760|Yandere|5
761|Youkai|7
762|Younger Brothers|5
763|Younger Love Interests|5
764|Younger Sisters|5
765|Zombies|7
766|Marvel|10
767|One Piece|10
768|Harry Potter|10
769|Naruto|10
770|Bleach|10
771|Pokemon|10
772|Douluo Dalu|10
773|Dragon Ball|10
774|Yu-Gi-Oh!|10
775|Warhammer|10
776|Jujutsu Kaisen|10
777|Hunter x Hunter|10
778|DC Universe|10
779|Hollywood|8
780|Football|8
781|Gao Wu|2
782|Live Streaming|8
783|Cyberpunk 2077|10
784|Game Creator|2
785|Swallowed Star|10
786|Simulator|2
787|Single Female Lead|5
788|Western Names|11
789|Dark Fantasy|9
790|Minecraft|10
791|League of Legends|10
792|Mortal Flow|2
793|Proficiency|2
794|DnD|10
795|Three Kingdoms|3
796|Journey to the West|10
797|Devouring|2
798|Eavesdropping|6
799|Lord of the Mysteries|10
800|Conferred Gods|10
801|Honghuang|10
802|Territory Management|4
803|Heaven Defying Comprehension|1
804|Detective Conan|10
806|Business Wars|4
807|Copy|2
808|Faith Dependent Deities|2
809|Basketball|8
810|Undead Protagonist|1
811|Sign In|2
812|Demon Slayer|10
813|Game of Thrones|10
814|Fairy Tail|10
815|Genshin Impact|10
816|Frieren|10
817|Star Wars|10
818|Honkai Impact 3|10
819|Witcher|10
820|Siheyuan|10
821|Hong Kong|11
822|Array|2
823|Lord|4
824|Life Script|6
825|More Children More Blessings|5
826|Overlord|10
827|Class Awakening|2
828|Spiritual Energy Revival|3
829|Reborn|1
830|Reality-Game Fusion|2
831|Reborn as the Villain|1
832|BTTH|10
833|Arknights|10
834|Uma Musume|10
835|Steampunk|3
836|The Boys|10
837|One Punch Man|10
838|Ultraman|10
839|Black Clover|10
840|Danmachi|10
841|Daily Intelligence|11
842|Simultaneous Transmigration|1
843|Kamen Rider|10
844|Nasuverse|10
845|Versatile Mage|10
846|Adapted to Donghua|10
847|Highschool DxD|10
848|Furry Relationship|5
849|Immortal Protagonist|1
850|Toaru|10
851|Digimon|10
852|The Walking Dead|10
853|Lord of the Ring|10
854|Classroom of the Elite|10
855|Stand User|2
856|Resident Evil|10
857|Touhou Project|10
858|Project Moon|10
859|JoJo’s Bizarre Adventure|10
860|Machinist|8
861|Qing Transmigration|10
862|Kirkmanverse|10
863|Pirates of Caribbean|10
864|King's Avatar|10
865|Hikigaya|10
866|Strike the Blood|10
867|Zenless Zone Zero|10
868|Fabulous Beast|10
869|The Eminence in Shadow|10
870|Slay the Gods|10
871|Behind-the-Scenes Mastermind|1
872|Final Fantasy|10
873|1900s|3
874|1910s|3
875|1920s|3
876|1930s|3
877|1940s|3
878|1950s|3
879|1960s|3
880|1970s|3
881|1980s|3
882|1990s|3
883|2000s|3
884|2010s|3
885|Blue Archive|10
886|Food Wars!|10
887|Dragon Raja|10
888|Monster Hunter|10
889|Honkai Star Rails|10
890|System Misunderstanding|2
]==]

local ALL_TAGS = {}
do
    for line in TAG_SEARCH_INDEX:gmatch("[^\n]+") do
        local id, label, cat = line:match("^([^|]+)|([^|]+)|([^|]+)$")
        if id and label and cat then
            ALL_TAGS[#ALL_TAGS + 1] = { id = id, label = label, lower = label:lower(), cat = cat }
        end
    end
end

-- Resolve a free-text Tag Search field to a dedup'd list of tag IDs.
-- v1.2.0 semantics — a keyword INCLUDES every matching tag:
--   • Tokens are split on comma / semicolon / newline / tab; spaces stay
--     INSIDE tokens so multi-word phrases work ("weak to strong").
--   • Per token, resolution order:
--       1. exact label match (case-insensitive) — "system" → the System
--          tag even though other labels contain it;
--       2. numeric token — a verbatim tag id (validated);
--       3. "keyword*" wildcard — includes ALL substring matches;
--       4. ANY substring match — "sys" now includes System (#696) AND
--          System Misunderstanding (#890) AND everything else containing
--          it: the search "shows everything as a result" (v1.1.9 raised
--          an ambiguity error here and demanded the exact name).
--   • A multi-word token with no phrase match falls back to per-word
--     matching; a token with no match at all raises a clear error.
--   • cat: "0"/nil = all categories, else a single category id ("1".."11")
--     — scopes the whole resolution (mirrors the site finder's grouping).
function tagSearchResolve(text, cat)
    if not text or text == "" then return {} end
    local catFilter = tostring(cat or "0")
    local scopeAll = (catFilter == "0" or catFilter == "" or catFilter == "all")
    local lower = text:lower()
    local seen = {}
    local out = {}

    local function scoped(t)
        return scopeAll or t.cat == catFilter
    end

    -- every tag whose label contains `token` (plain substring, no patterns)
    local function substringMatches(token)
        local matches = {}
        for _, t in ipairs(ALL_TAGS) do
            if scoped(t) and t.lower:find(token, 1, true) then
                matches[#matches + 1] = t
            end
        end
        return matches
    end

    local function addTag(t)
        if not seen[t.id] then
            seen[t.id] = true
            out[#out + 1] = t.id
        end
    end

    local function formatMatches(matches, maxN)
        local names = {}
        for i = 1, math.min(#matches, maxN) do
            names[#names + 1] = matches[i].label .. " (#" .. matches[i].id .. ")"
        end
        local s = table.concat(names, ", ")
        if #matches > maxN then
            s = s .. ", …and " .. (#matches - maxN) .. " more"
        end
        return s
    end

    -- resolve ONE token (already trimmed + lowercased)
    local function resolveToken(token)
        -- 1) exact label match wins (you pick ONE exact tag, like the site)
        for _, t in ipairs(ALL_TAGS) do
            if scoped(t) and t.lower == token then
                addTag(t)
                return
            end
        end
        -- 2) numeric tag id (validated)
        if token:match("^%d+$") then
            for _, t in ipairs(ALL_TAGS) do
                if t.id == token then
                    if scoped(t) then
                        addTag(t)
                        return
                    end
                    error("tag id " .. token .. " is not in the selected tag category.")
                end
            end
            error("no tag with id " .. token .. ".")
        end
        -- 5) trailing-* wildcard: every substring match at once
        if token:sub(-1) == "*" then
            local stem = token:sub(1, -2)
            if stem == "" then return end
            local matches = substringMatches(stem)
            if #matches == 0 then
                error("no tag name contains '" .. stem .. "'.")
            end
            for _, t in ipairs(matches) do addTag(t) end
            return
        end
        -- 3) / 4) substring matches: INCLUDE EVERY MATCH (v1.2.0) — a
        -- partial keyword behaves like the site's tag search: everything
        -- containing it becomes part of the filter.
        local matches = substringMatches(token)
        for _, t in ipairs(matches) do addTag(t) end
        if #matches > 0 then return end
        -- no match: multi-word tokens fall back to per-word resolution
        if token:find("%s") then
            for word in token:gmatch("%S+") do
                resolveToken(word)
            end
            return
        end
        error("no tag name contains '" .. token .. "'. Try a shorter keyword "
            .. "(e.g. 'reincarnat', 'harem', 'system'), or browse the Tags chip "
            .. "groups in this filter sheet (every tag is visible there).")
    end

    for rawToken in lower:gmatch("[^,;\n\t]+") do
        local token = rawToken:gsub("^%s+", ""):gsub("%s+$", "")
        if token ~= "" then
            resolveToken(token)
        end
    end
    return out
end

-- ── v1.2.0 Tag books: novel-finder URLs opened as browsable books ───────────
-- The catalog search bar doubles as a tag finder: matching tags are listed
-- as tappable results whose URL is the site's own novel-finder with ti=
-- pre-applied. Opening one renders it as a "book": the chapter list is the
-- tag's novels (most-read first, capped at 100) and opening a chapter
-- previews that novel's first chapter.
local TAG_CATEGORY_NAMES = {
    ["1"] = "Protagonist", ["2"] = "Power Systems", ["3"] = "Worldbuilding",
    ["4"] = "Socio-Political", ["5"] = "Relationships", ["6"] = "Narrative",
    ["7"] = "Beings & Factions", ["8"] = "Professional", ["9"] = "Tone",
    ["10"] = "Adaptations", ["11"] = "Misc"
}

local function parseTagBookUrl(bookUrl)
    if not bookUrl or not string.find(bookUrl, "novel-finder", 1, true) then
        return nil
    end
    local ids = {}
    local seen = {}
    for chunk in string.gmatch(bookUrl, "[?&]ti=([^&#]*)") do
        for v in string.gmatch(chunk, "%d+") do
            if not seen[v] then
                seen[v] = true
                ids[#ids + 1] = v
            end
        end
    end
    if #ids == 0 then return nil end
    return ids
end

local function tagBookLabels(ids)
    local labels, seen = {}, {}
    for _, id in ipairs(ids) do
        for _, t in ipairs(ALL_TAGS) do
            if t.id == id and not seen[id] then
                seen[id] = true
                labels[#labels + 1] = t.label
                break
            end
        end
    end
    return labels
end

local function fetchTagBookPage(ids, page)
    local params = "ti=" .. table.concat(ids, ",") ..
        "&orderBy=reader&page=" .. tostring(page)
    return fetchCatalogPage("en/novel-finder", "/en/novel-finder.json", params)
end

local function tagBookChapterList(ids)
    local out, seen = {}, {}
    for page = 1, 10 do
        local pp = fetchTagBookPage(ids, page)
        if not pp or type(pp.series) ~= "table" or #pp.series == 0 then break end
        for _, novel in ipairs(pp.series) do
            local rawId = tostring(novel.raw_id or "")
            if rawId ~= "" and not seen[rawId] then
                seen[rawId] = true
                local title = (novel.data and novel.data.title) or ""
                out[#out + 1] = {
                    title = string_clean(title),
                    url = baseUrl .. "en/novel/" .. rawId .. "/" ..
                        (novel.slug or "") .. "/chapter-1"
                }
            end
        end
        local countNum = tonumber(pp.count)
        if countNum and #out >= countNum then break end
    end
    return out
end

-- ── Catalog ─────────────────────────────────────────────────────────────────

function getCatalogList(index)
    local page = index + 1
    local pp = fetchCatalogPage("en/novel-list", "/en/novel-list.json",
        "page=" .. tostring(page) .. "&orderBy=reader")
    if not pp then
        log_error("wtrlab: getCatalogList failed")
        return { items = {}, hasNext = false }
    end
    return pagePropsToResult(pp, page)
end

-- ── Search ──────────────────────────────────────────────────────────────────

function getCatalogSearch(index, query)
    local page = index + 1
    local params = "text=" .. url_encode(query) .. "&page=" .. tostring(page)
    local pp = fetchCatalogPage("en/novel-finder", "/en/novel-finder.json", params)
    if not pp then
        log_error("wtrlab: getCatalogSearch failed")
        return { items = {}, hasNext = false }
    end
    local result = pagePropsToResult(pp, page)

    -- v1.2.0 tag finder: the search bar also finds TAGS — every tag whose
    -- name contains the query is listed first as a tappable result (page 1
    -- only). Opening it browses the tag's novels (see the tag-book helpers).
    if page == 1 and query and query ~= "" then
        local lower = tostring(query):lower()
        local tagItems, seen = {}, {}
        for _, t in ipairs(ALL_TAGS) do
            if not seen[t.id] and t.lower:find(lower, 1, true) then
                seen[t.id] = true
                tagItems[#tagItems + 1] = {
                    title = "🏷 " .. t.label .. " — " ..
                        (TAG_CATEGORY_NAMES[t.cat] or "Tag"),
                    url = baseUrl .. "en/novel-finder?ti=" .. t.id
                }
                if #tagItems >= 8 then break end
            end
        end
        if #tagItems > 0 then
            local merged = {}
            for _, it in ipairs(tagItems) do merged[#merged + 1] = it end
            for _, it in ipairs(result.items or {}) do merged[#merged + 1] = it end
            result.items = merged
            log_info("wtrlab: search: +" .. tostring(#tagItems) .. " tag results")
        end
    end
    return result
end


-- ── Book details ────────────────────────────────────────────────────────────

function getBookTitle(bookUrl)
    local tagIds = parseTagBookUrl(bookUrl)
    if tagIds then
        local labels = tagBookLabels(tagIds)
        if #labels > 0 then
            return "🏷 " .. table.concat(labels, " + ") .. " (tag view)"
        end
        return "Tag view"
    end
    local body = fetchPage(bookUrl)
    if not body then
        return nil
    end
    local el = html_select_first(body, "h1")
    if el then
        return string_trim(el.text)
    end
    return nil
end

function getBookCoverImageUrl(bookUrl)
    if parseTagBookUrl(bookUrl) then return nil end
    local body = fetchPage(bookUrl)
    if not body then
        return nil
    end
    local cover = html_attr(body, ".image-wrap img[alt]:not([aria-hidden])", "src")
    if cover ~= "" then
        return coverUrl(absUrl(cover))
    end
    return nil
end

function getBookDescription(bookUrl)
    local tagIds = parseTagBookUrl(bookUrl)
    if tagIds then
        local labels = tagBookLabels(tagIds)
        local name = (#labels > 0) and table.concat(labels, " + ") or "this tag"
        local countText = ""
        local pp = fetchTagBookPage(tagIds, 1)
        if pp and pp.count then
            local c = tonumber(pp.count)
            if c then countText = " (" .. tostring(c) .. " novels total)" end
        end
        return "All novels tagged " .. name .. countText .. ".\n\n" ..
            "This is a tag browse view: the 'chapters' below are this tag's " ..
            "novels ordered by readers (first 100 shown). Open any entry to " ..
            "preview that novel's first chapter — search its title in the " ..
            "catalog to add the full book. You can also combine tags with the " ..
            "Filter sheet (Tag Search field or the Tags chip groups)."
    end
    local body = fetchPage(bookUrl)
    if not body then
        return nil
    end
    local el = html_select_first(body, ".desc-wrap .description")
    if el then
        return string_trim(el.text)
    end
    return nil
end

-- ── Chapter list (shared, TTL-cached api/chapters fetch) ─────────────────────
-- api/chapters is ~74 KB JSON vs ~250 KB for the book page HTML. Both
-- getChapterList and getChapterListHash use this ONE fetch through a
-- 45-second cache: opening a book (hash + list in one burst) costs a
-- single request, and library refresh checks are ~3x lighter than the
-- old full-page scrape.

local CHAPTERS_CACHE_TTL_MS = 45000

local function fetchChaptersData(novelId, bookUrl)
    local entry = _chaptersCache[novelId]
    local now = nowMs()
    if entry and (now - entry.t) < CHAPTERS_CACHE_TTL_MS then
        return entry.chapters
    end
    local r = http_get(baseUrl .. "api/chapters/" .. novelId, {
        headers = {
            ["Referer"] = bookUrl
        }
    })
    if not r.success then
        log_error("wtrlab: chapters API failed code=" .. tostring(r.code))
        -- serve a still-warm cache entry past TTL rather than nothing
        return entry and entry.chapters or nil
    end
    local data = json_parse(r.body)
    if not data or not data.chapters then
        log_error("wtrlab: cannot parse chapters JSON")
        return entry and entry.chapters or nil
    end
    _chaptersCache[novelId] = { t = now, chapters = data.chapters }
    return data.chapters
end

-- Hash format: "<count>|<max updated_at>|<checksum>" — the count and max
-- timestamp catch new chapters; the rolling checksum over every chapter's
-- (order, updated_at) also catches mid-list re-translations that neither
-- the count nor the max timestamp would see.
function getChapterListHash(bookUrl)
    local tagIds = parseTagBookUrl(bookUrl)
    if tagIds then
        local count = "?"
        local pp = fetchTagBookPage(tagIds, 1)
        if pp and pp.count then count = tostring(pp.count) end
        return "tags:" .. table.concat(tagIds, ",") .. "|" .. count
    end
    local novelId = string.match(bookUrl, "/novel/(%d+)/")
    if not novelId then
        return nil
    end
    local chapters = fetchChaptersData(novelId, bookUrl)
    if not chapters or #chapters == 0 then
        -- Fallback: the legacy book-page scrape (also covers API hiccups)
        local r = http_get(bookUrl)
        if not r.success then
            return nil
        end
        local chapterCount = nil
        for _, block in ipairs(html_select(r.body, "div.items-center.text-center")) do
            local label = html_select_first(block.html, "span[translate='no']")
            if label and string_trim(label.text) == "Chapters" then
                local m = regex_match(html_text(block.html), "(\\d+)")
                if m and m[1] then
                    chapterCount = m[1]
                    break
                end
            end
        end
        local updatedAt = string.match(r.body, '"updated_at":"([^"]+)"')
        if not chapterCount and not updatedAt then
            return nil
        end
        return (chapterCount or "?") .. "|" .. (updatedAt or "")
    end

    local maxUpd, sum = "", 0
    for i = 1, #chapters do
        local ch = chapters[i]
        local u = tostring(ch.updated_at or "")
        if u > maxUpd then maxUpd = u end
        local s = tostring(ch.order or i) .. ":" .. u
        for j = 1, #s do
            sum = (sum * 31 + string.byte(s, j)) % 1000000007
        end
    end
    return tostring(#chapters) .. "|" .. maxUpd .. "|" .. tostring(sum)
end

function getChapterList(bookUrl)
    local tagIds = parseTagBookUrl(bookUrl)
    if tagIds then
        local novels = tagBookChapterList(tagIds)
        log_info("wtrlab: tag book: " .. tostring(#novels) .. " novels")
        if #novels == 0 then
            return {}
        end
        return novels
    end
    local novelId = string.match(bookUrl, "/novel/(%d+)/")
    if not novelId then
        log_error("wtrlab: cannot extract novelId from " .. bookUrl)
        return {}
    end
    local slug = string.match(bookUrl, "/novel/%d+/([^/?#]+)") or ""
    if slug == "" then
        log_error("wtrlab: cannot extract slug from " .. bookUrl)
        return {}
    end

    local chapters = fetchChaptersData(novelId, bookUrl)
    if not chapters then
        return {}
    end

    local out = {}
    for i = 1, #chapters do
        local ch = chapters[i]
        local order = ch.order or i
        local title = ch.title or ("Chapter " .. tostring(order))
        local chUrl = baseUrl .. "novel/" .. novelId .. "/" .. slug .. "/chapter-" .. tostring(order)
        table.insert(out, {
            title = tostring(order) .. ": " .. title,
            url = chUrl
        })
    end

    log_info("wtrlab: loaded " .. tostring(#out) .. " chapters for novelId=" .. novelId)
    return out
end

-- ── Chapter text ─────────────────────────────────────────────────────────────

local function cleanParagraph(text)
    text = string_normalize(text)
    -- Strip repeated chapter headers at the start
    text = regex_replace(text, "(?i)\\A[\\s\\uFEFF]*((Глава\\s+\\d+|Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    -- Strip translator/editor credit lines (line-anchored)
    text = regex_replace(text,
        "(?i)^[\\s\\uFEFF]*(Translator|Editor|Proofreader|Translated\\s+by|Edited\\s+by|Read\\s+(at|on|latest))[:\\s\\u2014-][^\\n\\r]{0,70}(\\r?\\n|$)", "")
    -- Strip watermark lines (whole-line match, word-bounded — avoids eating story text)
    text = regex_replace(text,
        "(?i)^[^\\n\\r]{0,100}\\b(patreon(?:\\.com)?|ko-fi|paypal(?:\\.me)?|discord(?:\\.gg|\\.com)|wtr-lab(?:\\.com)?)\\b[^\\n\\r]{0,100}(\\r?\\n|$)", "")
    return string_trim(text)
end


-- ── v1.2.0 paragraph-safety helpers ─────────────────────────────────────────
-- The reader's paragraph boundary is a blank line (\n\s*\n). A single \n
-- INSIDE a chunk renders as a soft line break, so a chapter whose elements
-- embed single newlines displays as visually merged blocks. normalizeNewlines
-- + splitLines guarantee every source line becomes its own \n\n-joined
-- paragraph — the same rule the site's own reader uses for string bodies.
local function normalizeNewlines(s)
    s = string.gsub(s, "\r\n", "\n")
    s = string.gsub(s, "\r", "\n")
    return s
end

local function splitLines(s)
    local lines = {}
    for line in string.gmatch(normalizeNewlines(s) .. "\n", "(.-)\n") do
        lines[#lines + 1] = line
    end
    return lines
end

-- Lua pattern / replacement escaping. Glossary terms and patches are raw
-- site data: a term containing % ( ) . + - etc. would otherwise throw
-- "malformed pattern" / "invalid use of '%' in replacement" and abort the
-- whole chapter. safeGsub never raises — a bad term is skipped.
local function escLuaPattern(s)
    return (string.gsub(s, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function escLuaReplacement(s)
    return (string.gsub(s, "%%", "%%%%"))
end

local function safeGsub(text, pattern, replacement)
    if pattern == "" or replacement == nil then return text end
    local ok, res = pcall(string.gsub, text, escLuaPattern(pattern),
        escLuaReplacement(tostring(replacement)))
    if ok and type(res) == "string" then return res end
    return text
end

local function applyGlossaryAndPatches(text, glossary, patches, webplusTerms)
    if glossary then
        for idx, term in pairs(glossary) do
            local marker1 = "※" .. tostring(idx) .. "⛬"
            local marker2 = "※" .. tostring(idx) .. "〓"
            text = safeGsub(text, marker1, term)
            text = safeGsub(text, marker2, term)
        end
    end
    if patches then
        for _, patch in ipairs(patches) do
            if patch.zh and patch.en then
                text = safeGsub(text, patch.zh, patch.en)
            end
        end
    end
    -- Web+ mode: book-level glossary applied directly to the (Chinese) text,
    -- per paragraph with escaped patterns — unlike upstream 1.1.8, which
    -- gsubs the whole encrypted-JSON string with raw patterns.
    if webplusTerms then
        for original, translation in pairs(webplusTerms) do
            if original ~= "" and translation ~= "" then
                text = safeGsub(text, original, translation)
            end
        end
    end
    return text
end

local function buildParagraphs(resolvedBody, glossary, patches, webplusTerms)
    local paragraphs = {}
    local bodyArray = json_parse(resolvedBody)
    local sources = {}

    if type(bodyArray) == "table" and bodyArray[1] ~= nil then
        for _, item in ipairs(bodyArray) do
            if type(item) == "string" then
                sources[#sources + 1] = item
            end
        end
    else
        -- Plain-string body: the site's own reader splits these on \n.
        sources[#sources + 1] = tostring(resolvedBody)
    end

    -- Each element may itself embed line breaks (the site packs multi-line
    -- content into single array elements). Split EVERY element on newlines
    -- so each source line becomes its own paragraph — never a single 

    -- (the reader renders that as a merged soft break).
    for _, srcText in ipairs(sources) do
        for _, line in ipairs(splitLines(srcText)) do
            local text = cleanParagraph(line)
            if text ~= "[image]" and text ~= "" then
                text = applyGlossaryAndPatches(text, glossary, patches, webplusTerms)
                if text ~= "" then
                    table.insert(paragraphs, text)
                end
            end
        end
    end

    return paragraphs
end

-- POST /api/reader/get with Turnstile-aware retry.
-- Returns the parsed JSON table, or nil after exhausting retries (error raised).
local function fetchChapterJson(novelId, chapterNo, chapterUrl, translateParam)
    local requestBody = json_stringify({
        translate = translateParam,
        language = "none",
        raw_id = novelId,
        chapter_no = chapterNo,
        retry = false,
        force_retry = false
    })

    local MAX_ATTEMPTS = 3
    local lastTurnstileCount = nil

    for attempt = 1, MAX_ATTEMPTS do
        local r = http_post(baseUrl .. "api/reader/get", requestBody, {
            headers = {
                ["Content-Type"] = "application/json",
                ["Referer"] = chapterUrl,
                ["Origin"] = regex_replace(baseUrl, "/$", "")
            }
        })

        if not r.success then
            log_error("wtrlab: API reader/get failed code=" .. tostring(r.code) .. " body=" .. tostring(r.body):sub(1, 120))
            error("WTR-Lab API request failed (code " .. tostring(r.code) .. "). " ..
                "If this mentions Cloudflare, complete the challenge once in the integrated browser and retry.")
        end

        local json = json_parse(r.body)
        if not json then
            error("WTR-Lab returned an unexpected response (not JSON). " ..
                "This is usually a Cloudflare challenge — open the chapter once in the integrated browser, then retry.")
        end

        if json.requireTurnstile then
            lastTurnstileCount = json.count
            if attempt < MAX_ATTEMPTS then
                -- The block is enforced per backend instance and is intermittent:
                -- a retry often lands on a healthy instance. The app-level
                -- counter only resets via a solved Turnstile challenge, so a
                -- LONG sleep never aids recovery — it only stalls the read.
                -- Keep the waits short (600ms / 1800ms; was 2500/5000 in
                -- 1.1.7, which stacked up to 7.5s of dead time — the
                -- "chapter takes 10 seconds" symptom).
                local waitMs = 600 * attempt * attempt
                log_info("wtrlab: site security check (count=" .. tostring(json.count) ..
                    "), retry " .. attempt .. "/" .. tostring(MAX_ATTEMPTS - 1) .. " in " .. waitMs .. "ms")
                sleep(waitMs)
            end
        elseif json.success == false then
            local errCode = json.code or "?"
            local errMsg = json.message or json.error or "Unknown API error"
            error("[" .. tostring(errCode) .. "] " .. errMsg)
        else
            return json
        end
    end

    error("WTR-Lab security check required (rate limit reached, " ..
        tostring(lastTurnstileCount) .. "/15 requests).\n" ..
        "Fix: open ANY chapter of this book in the integrated browser (browser icon on the book/chapter page), " ..
        "tap 'Verify you are human' once, then download again. This resets the limit for your IP.")
end

function getChapterText(html, chapterUrl)
    if not chapterUrl or chapterUrl == "" then
        chapterUrl = html_attr(html, "link[rel='canonical']", "href")
    end
    if not chapterUrl or chapterUrl == "" then
        log_error("wtrlab: no chapterUrl available")
        return ""
    end

    log_info("wtrlab: getChapterText url=" .. chapterUrl)

    local novelId = string.match(chapterUrl, "/novel/(%d+)/")
    if not novelId then
        log_error("wtrlab: 'novel' not found in URL: " .. chapterUrl)
        return ""
    end

    local chapterNo = tonumber(string.match(chapterUrl, "/chapter%-(%d+)")) or 1
    local mode = getMode()
    local translateParam = (mode == "raw") and "web" or (mode == "webplus") and "webplus" or "ai"

    log_info("wtrlab: novelId=" .. novelId .. " chapterNo=" .. tostring(chapterNo) .. " translate=" .. translateParam)

    -- Optional pacing between chapter fetches (may reduce security-check triggers)
    local delay = getChapterDelay()
    if delay > 0 then
        sleep(delay)
    end

    local json = fetchChapterJson(novelId, chapterNo, chapterUrl, translateParam)

    local outerData = json.data
    local data = nil
    if outerData then
        data = outerData.data or outerData
    end
    if not data then
        log_error("wtrlab: no 'data' in response")
        return ""
    end

    local body = data.body
    if not body then
        log_error("wtrlab: no 'body' in data")
        return ""
    end

    local rawBody
    if type(body) == "table" then
        rawBody = json_stringify(body)
    else
        rawBody = tostring(body)
    end

    if rawBody == "" or rawBody == "null" then
        log_error("wtrlab: body is empty")
        return ""
    end

    local resolvedBody = decryptBody(rawBody)
    if not resolvedBody then
        error("WTR-Lab chapter body is encrypted and could not be decrypted " ..
            "(local AES-GCM failed and the fallback proxy is unreachable). Try again later.")
    end

    -- ── v2 book-level glossary (Chinese original → preferred translation) ──
    local termByOriginal = {}

    if mode ~= "raw" then
        local cache = termCache[novelId]

        if cache then
            termByOriginal = cache.termByOriginal
        else
            local v2Url = baseUrl .. "api/v2/reader/terms/" .. novelId .. ".json"
            local v2r = http_get(v2Url, {
                headers = {
                    ["Referer"] = chapterUrl,
                    ["Origin"] = regex_replace(baseUrl, "/$", "")
                }
            })
            if v2r.success then
                local v2data = json_parse(v2r.body)
                local termsArray = nil
                if v2data and type(v2data) == "table" and v2data.glossaries then
                    for _, glossary in ipairs(v2data.glossaries) do
                        if glossary.data and glossary.data.terms then
                            termsArray = glossary.data.terms
                            break
                        end
                    end
                end
                if termsArray then
                    for _, term in ipairs(termsArray) do
                        local original = term[2]
                        local translations = term[1]
                        if original and original ~= "" and type(translations) == "table" and translations[1] then
                            termByOriginal[original] = translations[1]
                        end
                    end
                end
                -- Cache the NEGATIVE result too: a 200 response with no
                -- usable glossary is stable for the book — without this,
                -- 1.1.7 re-downloaded the terms file on EVERY chapter of
                -- every glossary-less book (one wasted request per chapter).
                termCache[novelId] = { termByOriginal = termByOriginal }
            end
        end
    end

    -- ── Chapter-level glossary (※idx⛬ / ※idx〓 markers) ─────────────────────
    local glossary = {}
    if mode ~= "raw" and data.glossary_data and data.glossary_data.terms then
        local terms = data.glossary_data.terms
        for i = 1, #terms do
            local termEntry = terms[i]
            if type(termEntry) == "table" then
                local idx = i - 1 -- 0-based, matches the ※idx⛬ markers
                local raw = termEntry[1] or ""
                local original = termEntry[2] or ""
                local matched = original ~= "" and termByOriginal[original]
                local termValue = matched or raw
                if termValue ~= "" then
                    glossary[idx] = termValue
                end
            end
        end
    end

    -- ── Patch list (zh → en replacements) ────────────────────────────────────
    local patches = {}
    if data.patch then
        for _, patchItem in ipairs(data.patch) do
            if patchItem.zh and patchItem.en and patchItem.zh ~= "" then
                table.insert(patches, {
                    zh = patchItem.zh,
                    en = patchItem.en
                })
            end
        end
    end

    local paragraphs = buildParagraphs(resolvedBody, glossary, patches,
        (mode == "webplus") and termByOriginal or nil)

    if #paragraphs == 0 then
        log_error("wtrlab: 0 paragraphs parsed")
        return ""
    end

    log_info("wtrlab: parsed " .. tostring(#paragraphs) .. " paragraphs")

    return table.concat(paragraphs, "\n\n")
end

-- ── Settings schema ──────────────────────────────────────────────────────────

function getSettingsSchema()
    return {{
        key = PREF_MODE,
        type = "select",
        label = "Translation Mode",
        current = getMode(),
        options = {{
            value = "ai",
            label = "AI (Beta)"
        }, {{
            value = "raw",
            label = "Raw (Web)"
        }}, {{
            value = "webplus",
            label = "Web+ (glossary raw - best with app translator)"
        }}}
    }, {
        key = PREF_COVERS,
        type = "select",
        label = "Cover Images",
        current = (function()
            if get_preference(PREF_COVERS) == "direct" then return "direct" end
            return "proxy"
        end)(),
        options = {{
            value = "proxy",
            label = "Via wsrv.nl image proxy (recommended - fixes posters)"
        }, {
            value = "direct",
            label = "Direct from img.wtr-lab.com (breaks when Cloudflare challenges images)"
        }}
    }, {
        key = PREF_DELAY,
        type = "select",
        label = "Chapter Fetch Delay (may reduce 'Security Check' triggers)",
        current = tostring(getChapterDelay()),
        options = {{
            value = "0",
            label = "None"
        }, {
            value = "2000",
            label = "2 seconds"
        }, {
            value = "4000",
            label = "4 seconds"
        }, {
            value = "6000",
            label = "6 seconds"
        }}
    }}
end

-- ── Book metadata ────────────────────────────────────────────────────────────

function getBookGenres(bookUrl)
    if parseTagBookUrl(bookUrl) then return {} end
    local body = fetchPage(bookUrl)
    if not body then
        return {}
    end

    local genres = {}
    for _, el in ipairs(html_select(body, "a[href*='novel-list?genre='] span")) do
        local label = string_trim(el.text)
        if label ~= "" then
            table.insert(genres, label)
        end
    end

    return genres
end

function getBookRating(bookUrl)
    if parseTagBookUrl(bookUrl) then return nil end
    local body = fetchPage(bookUrl)
    if not body then
        return nil
    end
    return extractRating(body)
end

function getBookStatus(bookUrl)
    if parseTagBookUrl(bookUrl) then return nil end
    local body = fetchPage(bookUrl)
    if not body then
        return nil
    end
    for _, block in ipairs(html_select(body, "div.items-center.text-center")) do
        if block.text and block.text:find("Status") then
            local st = string.match(block.text, "Status%s+(.+)")
            if st then
                st = string_clean(st)
                return st ~= "" and st or nil
            end
        end
    end
    return nil
end

function getBookLastUpdate(bookUrl)
    if parseTagBookUrl(bookUrl) then return nil end
    local body = fetchPage(bookUrl)
    if not body then
        return nil
    end
    return string.match(body, '"updated_at":"(%d%d%d%d%-%d%d%-%d%d)')
end

-- ── Filter list (full parity with wtr-lab.com/en/novel-finder) ───────────────

function getFilterList()
    return {
        -- ── Novel finder: title text ──────────────────────────────────────
        -- The app's global search bar carries no filters, so the site's
        -- novel-finder text box lives HERE: combine a title keyword with
        -- every filter below in one applied query (finder API text= param).
        {
            type = "text",
            key = "title_search",
            label = "Title Search (novel finder)",
            defaultValue = ""
        },
        {
            type = "select",
            key = "orderBy",
            label = "Order by",
            defaultValue = "update",
            options = {
                {value = "update", label = "Update Date"},
                {value = "date", label = "Addition Date"},
                {value = "random", label = "Random"},
                {value = "daily_rank", label = "Daily View"},
                {value = "weekly_rank", label = "Weekly View"},
                {value = "monthly_rank", label = "Monthly View"},
                {value = "view", label = "All-Time View"},
                {value = "name", label = "Name"},
                {value = "reader", label = "Reader"},
                {value = "chapter", label = "Chapter Count"},
                {value = "character", label = "Character Count"},
                {value = "rating", label = "Rating"},
                {value = "total_rate", label = "Review Count"},
                {value = "vote", label = "Vote Count"},
                {value = "weighted", label = "Top Rated (weighted)"}
            }
        },
        {
            type = "select",
            key = "order",
            label = "Order",
            defaultValue = "desc",
            options = {
                {value = "desc", label = "Descending"},
                {value = "asc", label = "Ascending"}
            }
        },
        {
            type = "select",
            key = "status",
            label = "Status",
            defaultValue = "all",
            options = {
                {value = "all", label = "All"},
                {value = "ongoing", label = "Ongoing"},
                {value = "completed", label = "Completed"},
                {value = "hiatus", label = "Hiatus"},
                {value = "dropped", label = "Dropped"}
            }
        },
        {
            type = "select",
            key = "release_status",
            label = "Release Status",
            defaultValue = "all",
            options = {
                {value = "all", label = "All"},
                {value = "released", label = "Released"},
                {value = "voting", label = "On Voting"}
            }
        },
        {
            type = "select",
            key = "addition_age",
            label = "Added",
            defaultValue = "all",
            options = {
                {value = "all", label = "Any Time"},
                {value = "day", label = "< 2 Days"},
                {value = "week", label = "< 1 Week"},
                {value = "month", label = "< 1 Month"},
                {value = "3month", label = "< 3 Months"},
                {value = "6month", label = "< 6 Months"},
                {value = "year", label = "< 1 Year"},
                {value = "last_month", label = "Last Month"},
                {value = "last_year", label = "Last Year"},
                {value = "this_year", label = "This Year"}
            }
        },
        {
            type = "select",
            key = "count_chapters",
            label = "Chapter Count",
            defaultValue = "",
            options = {
                {value = "", label = "Any"},
                {value = "100", label = "100+"},
                {value = "150", label = "150+"},
                {value = "200", label = "200+"},
                {value = "250", label = "250+"},
                {value = "500", label = "500+"},
                {value = "750", label = "750+"},
                {value = "1000", label = "1000+"},
                {value = "1500", label = "1500+"},
                {value = "2000", label = "2000+"},
                {value = "2500", label = "2500+"},
                {value = "5000", label = "5000+"}
            }
        },
        {
            type = "select",
            key = "count_mode",
            label = "Count Mode",
            defaultValue = "min",
            options = {
                {value = "min", label = "At Least"},
                {value = "max", label = "At Most"}
            }
        },
        {
            type = "select",
            key = "count_characters",
            label = "Character Count",
            defaultValue = "",
            options = {
                {value = "", label = "Any"},
                {value = "100000", label = "100k+"},
                {value = "250000", label = "250k+"},
                {value = "500000", label = "500k+"},
                {value = "750000", label = "750k+"},
                {value = "1000000", label = "1M+"},
                {value = "1500000", label = "1.5M+"},
                {value = "2000000", label = "2M+"},
                {value = "2500000", label = "2.5M+"},
                {value = "3000000", label = "3M+"},
                {value = "4000000", label = "4M+"},
                {value = "5000000", label = "5M+"},
                {value = "7500000", label = "7.5M+"},
                {value = "10000000", label = "10M+"}
            }
        },
        {
            type = "select",
            key = "min_rating",
            label = "Minimum Rating",
            defaultValue = "",
            options = {
                {value = "", label = "Any"},
                {value = "1.0", label = "1.0+"},
                {value = "1.5", label = "1.5+"},
                {value = "2.0", label = "2.0+"},
                {value = "2.5", label = "2.5+"},
                {value = "3.0", label = "3.0+"},
                {value = "3.5", label = "3.5+"},
                {value = "4.0", label = "4.0+"},
                {value = "4.5", label = "4.5+"},
                {value = "5.0", label = "5.0"}
            }
        },
        {
            type = "select",
            key = "min_reviews",
            label = "Minimum Reviews",
            defaultValue = "",
            options = {
                {value = "", label = "Any"},
                {value = "5", label = "5+"},
                {value = "10", label = "10+"},
                {value = "15", label = "15+"},
                {value = "20", label = "20+"},
                {value = "25", label = "25+"},
                {value = "30", label = "30+"},
                {value = "35", label = "35+"},
                {value = "40", label = "40+"},
                {value = "45", label = "45+"},
                {value = "50", label = "50+"}
            }
        },
        {
            type = "select",
            key = "genre_operator",
            label = "Genre (And/Or)",
            defaultValue = "and",
            options = {
                {value = "and", label = "And"},
                {value = "or", label = "Or"}
            }
        },
        {
            type = "tristate",
            key = "genres",
            label = "Genres",
            options = {
                                {value = "1", label = "Action"}, {value = "2", label = "Adult"}, {value = "3", label = "Adventure"},
                {value = "4", label = "Comedy"}, {value = "5", label = "Drama"}, {value = "6", label = "Ecchi"},
                {value = "7", label = "Erciyuan"}, {value = "8", label = "Fan-fiction"}, {value = "9", label = "Fantasy"},
                {value = "10", label = "Game"}, {value = "11", label = "Gender Bender"}, {value = "12", label = "Harem"},
                {value = "13", label = "Historical"}, {value = "14", label = "Horror"}, {value = "15", label = "Josei"},
                {value = "16", label = "Martial Arts"}, {value = "17", label = "Mature"}, {value = "18", label = "Mecha"},
                {value = "19", label = "Military"}, {value = "20", label = "Mystery"}, {value = "21", label = "Psychological"},
                {value = "22", label = "Romance"}, {value = "23", label = "School Life"}, {value = "24", label = "Sci-fi"},
                {value = "25", label = "Seinen"}, {value = "26", label = "Shoujo"}, {value = "27", label = "Shoujo-ai"},
                {value = "28", label = "Shounen"}, {value = "29", label = "Shounen-ai"}, {value = "30", label = "Slice of Life"},
                {value = "31", label = "Smut"}, {value = "32", label = "Sports"}, {value = "33", label = "Supernatural"},
                {value = "34", label = "Tragedy"}, {value = "35", label = "Urban Life"}, {value = "36", label = "Wuxia"},
                {value = "37", label = "Xianxia"}, {value = "38", label = "Xuanhuan"}, {value = "39", label = "Yaoi"},
                {value = "40", label = "Yuri"},
            }
        },
        -- ── Tag Search (keywords) + visible Tag pickers (v1.1.9) ──────────
        -- Two keyword fields (below) + one dropdown per site category
        -- (after Tag And/Or). Keywords resolve at apply time with
        -- autocomplete-like feedback: an ambiguous or unknown keyword
        -- raises an error that LISTS the matching tag names, so typos
        -- never silently filter nothing and short prefixes ("sys")
        -- show you the real tag names ("System"). "keyword*" includes
        -- every matching tag; multi-word phrases match as phrases.
        -- The category picker scopes the keyword fields; each Tags:
        -- dropdown lists that category's tags alphabetically.
        {
            type = "select",
            key = "tag_category",
            label = "Tag Search Category",
            defaultValue = "0",
            options = {
                {value = "0", label = "All Categories"},
                {value = "1", label = "Protagonist Archetypes"},
                {value = "2", label = "Power Systems"},
                {value = "3", label = "Worldbuilding"},
                {value = "4", label = "Socio-Political Structures"},
                {value = "5", label = "Relationship Tropes"},
                {value = "6", label = "Narrative"},
                {value = "7", label = "Beings & Factions"},
                {value = "8", label = "Professional Archetypes"},
                {value = "9", label = "Tone & Atmosphere"},
                {value = "10", label = "Adaptations"},
                {value = "11", label = "Miscellaneous Narrative Elements"}
            }
        },
        {
            type = "text",
            key = "tag_search_inc",
            label = "Tag Search - include (name, id, or name*)",
            defaultValue = ""
        },
        {
            type = "text",
            key = "tag_search_exc",
            label = "Tag Search - exclude (name, id, or name*)",
            defaultValue = ""
        },
        {
            type = "select",
            key = "tag_operator",
            label = "Tag (And/Or)",
            defaultValue = "and",
            options = {
                {value = "and", label = "And"},
                {value = "or", label = "Or"}
            }
        },
        -- ── Tag chip groups (v1.2.0): multi-select per site category ──
        -- Every tag of the category is shown as a chip (the app sorts
        -- alphabetically): tap several to include them ALL — multiple
        -- tags from the same category. Combine freely with the Tag
        -- Search keyword fields. (Exclude via the Tag Search - exclude
        -- keyword field.)
        -- [TAG PICKERS BEGIN]
        -- cat 1: Protagonist Archetypes (190 tags)
        {
            type = "checkbox",
            key = "tag_pick_1",
            label = "Tags: Protagonist Archetypes (190)",
            options = {
                {value = "1", label = "Abandoned Children"},
                {value = "3", label = "Absent Parents"},
                {value = "6", label = "Accelerated Growth"},
                {value = "19", label = "Adopted Children"},
                {value = "20", label = "Adopted Protagonist"},
                {value = "24", label = "Age Progression"},
                {value = "25", label = "Age Regression"},
                {value = "26", label = "Aggressive Characters"},
                {value = "36", label = "Androgynous Characters"},
                {value = "42", label = "Anti-social Protagonist"},
                {value = "43", label = "Antihero Protagonist"},
                {value = "46", label = "Apathetic Protagonist"},
                {value = "49", label = "Appearance Different from Actual Age"},
                {value = "56", label = "Arrogant Characters"},
                {value = "63", label = "Autism"},
                {value = "65", label = "Average-looking Protagonist"},
                {value = "67", label = "Awkward Protagonist"},
                {value = "81", label = "Beautiful Female Lead"},
                {value = "871", label = "Behind-the-Scenes Mastermind"},
                {value = "86", label = "Bisexual Protagonist"},
                {value = "87", label = "Black Belly"},
                {value = "91", label = "Blind Protagonist"},
                {value = "99", label = "Bookworm"},
                {value = "111", label = "Calm Protagonist"},
                {value = "114", label = "Carefree Protagonist"},
                {value = "115", label = "Caring Protagonist"},
                {value = "116", label = "Cautious Protagonist"},
                {value = "118", label = "Character Growth"},
                {value = "119", label = "Charismatic Protagonist"},
                {value = "120", label = "Charming Protagonist"},
                {value = "125", label = "Child Protagonist"},
                {value = "130", label = "Childish Protagonist"},
                {value = "131", label = "Chuunibyou"},
                {value = "134", label = "Clever Protagonist"},
                {value = "142", label = "Cold Protagonist"},
                {value = "145", label = "Coma"},
                {value = "147", label = "Coming of Age"},
                {value = "150", label = "Confident Protagonist"},
                {value = "158", label = "Couple Growth"},
                {value = "161", label = "Cowardly Protagonist"},
                {value = "165", label = "Cross-dressing"},
                {value = "171", label = "Cunning Protagonist"},
                {value = "172", label = "Curious Protagonist"},
                {value = "175", label = "Cute Protagonist"},
                {value = "182", label = "Dead Protagonist"},
                {value = "186", label = "Delinquents"},
                {value = "192", label = "Dense Protagonist"},
                {value = "197", label = "Determined Protagonist"},
                {value = "200", label = "Disabilities"},
                {value = "203", label = "Dishonest Protagonist"},
                {value = "204", label = "Distrustful Protagonist"},
                {value = "212", label = "Doting Older Siblings"},
                {value = "213", label = "Doting Parents"},
                {value = "231", label = "Elderly Protagonist"},
                {value = "234", label = "Emotionally Weak Protagonist"},
                {value = "240", label = "Enlightenment"},
                {value = "246", label = "Evil Protagonist"},
                {value = "248", label = "Evolution"},
                {value = "254", label = "Fallen Nobility"},
                {value = "260", label = "Famous Parents"},
                {value = "261", label = "Famous Protagonist"},
                {value = "268", label = "Fast Learner"},
                {value = "269", label = "Fat Protagonist"},
                {value = "270", label = "Fat to Fit"},
                {value = "272", label = "Fearless Protagonist"},
                {value = "275", label = "Female Protagonist"},
                {value = "276", label = "Female to Male"},
                {value = "287", label = "Forgetful Protagonist"},
                {value = "288", label = "Former Hero"},
                {value = "292", label = "Fujoshi"},
                {value = "302", label = "Genderless Protagonist"},
                {value = "306", label = "Genius Protagonist"},
                {value = "310", label = "Glasses-wearing Protagonist"},
                {value = "312", label = "God Protagonist"},
                {value = "325", label = "Half-human Protagonist"},
                {value = "327", label = "Handsome Male Lead"},
                {value = "328", label = "Hard-Working Protagonist"},
                {value = "330", label = "Harsh Training"},
                {value = "331", label = "Hated Protagonist"},
                {value = "803", label = "Heaven Defying Comprehension"},
                {value = "337", label = "Helpful Protagonist"},
                {value = "342", label = "Hiding True Abilities"},
                {value = "343", label = "Hiding True Identity"},
                {value = "344", label = "Hikikomori"},
                {value = "346", label = "Honest Protagonist"},
                {value = "348", label = "Hot-blooded Protagonist"},
                {value = "350", label = "Human Weapon"},
                {value = "352", label = "Humanoid Protagonist"},
                {value = "849", label = "Immortal Protagonist"},
                {value = "361", label = "Indecisive Protagonist"},
                {value = "363", label = "Inferiority Complex"},
                {value = "369", label = "Introverted Protagonist"},
                {value = "375", label = "Jobless Class"},
                {value = "382", label = "Kuudere"},
                {value = "383", label = "Lack of Common Sense"},
                {value = "387", label = "Lazy Protagonist"},
                {value = "392", label = "Limited Lifespan"},
                {value = "395", label = "Loli"},
                {value = "397", label = "Loner Protagonist"},
                {value = "407", label = "Low-key Protagonist"},
                {value = "409", label = "Lucky Protagonist"},
                {value = "417", label = "Male Protagonist"},
                {value = "418", label = "Male to Female"},
                {value = "422", label = "Manipulative Characters"},
                {value = "427", label = "Masochistic Characters"},
                {value = "432", label = "Mature Protagonist"},
                {value = "444", label = "Mob Protagonist"},
                {value = "447", label = "Modern Knowledge"},
                {value = "456", label = "Multiple Personalities"},
                {value = "458", label = "Multiple Protagonists"},
                {value = "467", label = "Mute Character"},
                {value = "468", label = "Mysterious Family Background"},
                {value = "474", label = "Naive Protagonist"},
                {value = "475", label = "Narcissistic Protagonist"},
                {value = "477", label = "Near-Death Experience"},
                {value = "479", label = "Neet"},
                {value = "486", label = "Non-humanoid Protagonist"},
                {value = "500", label = "Orphans"},
                {value = "503", label = "Outcasts"},
                {value = "506", label = "Overpowered Protagonist"},
                {value = "508", label = "Pacifist Protagonist"},
                {value = "516", label = "Past Trauma"},
                {value = "518", label = "Personality Changes"},
                {value = "519", label = "Perverted Protagonist"},
                {value = "530", label = "Playboys"},
                {value = "531", label = "Playful Protagonist"},
                {value = "535", label = "Polite Protagonist"},
                {value = "539", label = "Poor Protagonist"},
                {value = "547", label = "Pragmatic Protagonist"},
                {value = "551", label = "Previous Life Talent"},
                {value = "555", label = "Proactive Protagonist"},
                {value = "560", label = "Protagonist Strong from the Start"},
                {value = "563", label = "Psychopaths"},
                {value = "565", label = "Quiet Characters"},
                {value = "566", label = "Quirky Characters"},
                {value = "569", label = "Race Change"},
                {value = "829", label = "Reborn"},
                {value = "831", label = "Reborn as the Villain"},
                {value = "574", label = "Reincarnated as a Monster"},
                {value = "575", label = "Reincarnated as an Object"},
                {value = "577", label = "Reincarnated in Another World"},
                {value = "578", label = "Reincarnation"},
                {value = "580", label = "Reluctant Protagonist"},
                {value = "584", label = "Returning from Another World"},
                {value = "590", label = "Righteous Protagonist"},
                {value = "595", label = "Ruthless Protagonist"},
                {value = "596", label = "Sadistic Characters"},
                {value = "598", label = "Salaryman"},
                {value = "602", label = "Schizophrenia"},
                {value = "605", label = "Sealed Power"},
                {value = "606", label = "Second Chance"},
                {value = "611", label = "Secretive Protagonist"},
                {value = "616", label = "Selfish Protagonist"},
                {value = "617", label = "Selfless Protagonist"},
                {value = "618", label = "Seme Protagonist"},
                {value = "621", label = "Sentimental Protagonist"},
                {value = "630", label = "Shameless Protagonist"},
                {value = "633", label = "Sharp-tongued Characters"},
                {value = "637", label = "Shota"},
                {value = "641", label = "Shy Characters"},
                {value = "842", label = "Simultaneous Transmigration"},
                {value = "651", label = "Skill Assimilation"},
                {value = "653", label = "Skill Creation"},
                {value = "655", label = "Slave Protagonist"},
                {value = "658", label = "Slow Growth at Start"},
                {value = "674", label = "Stoic Characters"},
                {value = "676", label = "Straight Seme"},
                {value = "677", label = "Straight Uke"},
                {value = "682", label = "Strong to Stronger"},
                {value = "683", label = "Stubborn Protagonist"},
                {value = "687", label = "Sudden Strength Gain"},
                {value = "690", label = "Summoned Hero"},
                {value = "711", label = "Timid Protagonist"},
                {value = "712", label = "Tomboyish Female Lead"},
                {value = "715", label = "Tragic Past"},
                {value = "717", label = "Transmigration"},
                {value = "718", label = "Transplanted Memories"},
                {value = "719", label = "Transported into a Game World"},
                {value = "721", label = "Transported to Another World"},
                {value = "722", label = "Trap"},
                {value = "724", label = "Trickster"},
                {value = "727", label = "Twisted Personality"},
                {value = "728", label = "Ugly Protagonist"},
                {value = "810", label = "Undead Protagonist"},
                {value = "731", label = "Underestimated Protagonist"},
                {value = "736", label = "Unlucky Protagonist"},
                {value = "737", label = "Unreliable Narrator"},
                {value = "741", label = "Villainess Noble Girls"},
                {value = "749", label = "Weak Protagonist"},
                {value = "750", label = "Weak to Strong"},
            }
        },
        -- cat 2: Power Systems (100 tags)
        {
            type = "checkbox",
            key = "tag_pick_2",
            label = "Tags: Power Systems (100)",
            options = {
                {value = "2", label = "Ability Steal"},
                {value = "27", label = "Alchemy"},
                {value = "37", label = "Androids"},
                {value = "41", label = "Anti-Magic"},
                {value = "48", label = "Appearance Changes"},
                {value = "822", label = "Array"},
                {value = "59", label = "Artificial Intelligence"},
                {value = "64", label = "Automatons"},
                {value = "85", label = "Biochip"},
                {value = "92", label = "Blood Manipulation"},
                {value = "93", label = "Bloodlines"},
                {value = "94", label = "Body Swap"},
                {value = "95", label = "Body Tempering"},
                {value = "101", label = "Brainwashing"},
                {value = "122", label = "Cheats"},
                {value = "827", label = "Class Awakening"},
                {value = "136", label = "Clones"},
                {value = "149", label = "Conditional Power"},
                {value = "807", label = "Copy"},
                {value = "168", label = "Cryostasis"},
                {value = "169", label = "Cultivation"},
                {value = "173", label = "Curses"},
                {value = "178", label = "Dao Companion"},
                {value = "179", label = "Dao Comprehension"},
                {value = "190", label = "Demonic Cultivation Technique"},
                {value = "797", label = "Devouring"},
                {value = "205", label = "Divination"},
                {value = "206", label = "Divine Protection"},
                {value = "220", label = "Dungeon Master"},
                {value = "230", label = "Eidetic Memory"},
                {value = "232", label = "Elemental Magic"},
                {value = "250", label = "Exorcism"},
                {value = "251", label = "Eye Powers"},
                {value = "808", label = "Faith Dependent Deities"},
                {value = "267", label = "Fast Cultivation"},
                {value = "278", label = "Firearms"},
                {value = "295", label = "Galge"},
                {value = "784", label = "Game Creator"},
                {value = "297", label = "Game Elements"},
                {value = "298", label = "Game Ranking System"},
                {value = "781", label = "Gao Wu"},
                {value = "304", label = "Genetic Modifications"},
                {value = "305", label = "Genies"},
                {value = "315", label = "Godly Powers"},
                {value = "320", label = "Grinding"},
                {value = "332", label = "Healers"},
                {value = "335", label = "Heavenly Tribulation"},
                {value = "341", label = "Hidden Abilities"},
                {value = "354", label = "Hypnotism"},
                {value = "365", label = "Inscriptions"},
                {value = "371", label = "Invisibility"},
                {value = "390", label = "Level System"},
                {value = "401", label = "Lottery"},
                {value = "410", label = "Magic"},
                {value = "412", label = "Magic Formations"},
                {value = "413", label = "Magical Girls"},
                {value = "414", label = "Magical Space"},
                {value = "415", label = "Magical Technology"},
                {value = "426", label = "Martial Spirits"},
                {value = "439", label = "Mind Control"},
                {value = "443", label = "MMORPG"},
                {value = "792", label = "Mortal Flow"},
                {value = "478", label = "Necromancer"},
                {value = "496", label = "Onmyouji"},
                {value = "502", label = "Otome Game"},
                {value = "511", label = "Parasites"},
                {value = "526", label = "Pill Based Cultivation"},
                {value = "527", label = "Pill Concocting"},
                {value = "542", label = "Possession"},
                {value = "548", label = "Precognition"},
                {value = "793", label = "Proficiency"},
                {value = "561", label = "Protagonist with Multiple Bodies"},
                {value = "562", label = "Psychic Powers"},
                {value = "830", label = "Reality-Game Fusion"},
                {value = "576", label = "Reincarnated in a Game World"},
                {value = "583", label = "Resurrection"},
                {value = "615", label = "Seeing Things Other Humans Can't"},
                {value = "629", label = "Sexual Cultivation Technique"},
                {value = "631", label = "Shapeshifters"},
                {value = "632", label = "Sharing A Body"},
                {value = "811", label = "Sign In"},
                {value = "786", label = "Simulator"},
                {value = "652", label = "Skill Books"},
                {value = "663", label = "Soul Power"},
                {value = "665", label = "Spatial Manipulation"},
                {value = "667", label = "Special Abilities"},
                {value = "670", label = "Spirit Users"},
                {value = "855", label = "Stand User"},
                {value = "691", label = "Summoning Magic"},
                {value = "693", label = "Survival Game"},
                {value = "694", label = "Sword And Magic"},
                {value = "696", label = "System"},
                {value = "890", label = "System Misunderstanding"},
                {value = "707", label = "Time Manipulation"},
                {value = "716", label = "Transformation Ability"},
                {value = "732", label = "Unique Cultivation Technique"},
                {value = "735", label = "Unlimited Flow"},
                {value = "742", label = "Virtual Reality"},
                {value = "753", label = "Wishes"},
                {value = "755", label = "Wizards"},
            }
        },
        -- cat 3: Worldbuilding (56 tags)
        {
            type = "checkbox",
            key = "tag_pick_3",
            label = "Tags: Worldbuilding (56)",
            options = {
                {value = "873", label = "1900s"},
                {value = "874", label = "1910s"},
                {value = "875", label = "1920s"},
                {value = "876", label = "1930s"},
                {value = "877", label = "1940s"},
                {value = "878", label = "1950s"},
                {value = "879", label = "1960s"},
                {value = "880", label = "1970s"},
                {value = "881", label = "1980s"},
                {value = "882", label = "1990s"},
                {value = "883", label = "2000s"},
                {value = "884", label = "2010s"},
                {value = "30", label = "Alternate World"},
                {value = "32", label = "Amusement Park"},
                {value = "34", label = "Ancient China"},
                {value = "35", label = "Ancient Times"},
                {value = "47", label = "Apocalypse"},
                {value = "133", label = "Classic"},
                {value = "221", label = "Dungeons"},
                {value = "223", label = "Dystopia"},
                {value = "243", label = "European Ambience"},
                {value = "265", label = "Fantasy World"},
                {value = "294", label = "Futuristic Setting"},
                {value = "301", label = "Gate to Another World"},
                {value = "334", label = "Heaven"},
                {value = "336", label = "Hell"},
                {value = "347", label = "Hospital"},
                {value = "368", label = "Interdimensional Travel"},
                {value = "391", label = "Library"},
                {value = "400", label = "Lost Civilizations"},
                {value = "434", label = "Medieval"},
                {value = "446", label = "Modern Day"},
                {value = "450", label = "Monster Society"},
                {value = "454", label = "Mpreg"},
                {value = "459", label = "Multiple Realms"},
                {value = "460", label = "Multiple Reincarnated Individuals"},
                {value = "461", label = "Multiple Timelines"},
                {value = "462", label = "Multiple Transported Individuals"},
                {value = "493", label = "Omegaverse"},
                {value = "505", label = "Outer Space"},
                {value = "510", label = "Parallel Worlds"},
                {value = "544", label = "Post-apocalyptic"},
                {value = "554", label = "Prison"},
                {value = "582", label = "Restaurant"},
                {value = "828", label = "Spiritual Energy Revival"},
                {value = "835", label = "Steampunk"},
                {value = "699", label = "Technological Gap"},
                {value = "795", label = "Three Kingdoms"},
                {value = "706", label = "Time Loop"},
                {value = "708", label = "Time Paradox"},
                {value = "710", label = "Time Travel"},
                {value = "720", label = "Transported Modern Structure"},
                {value = "723", label = "Tribal Society"},
                {value = "756", label = "World Hopping"},
                {value = "757", label = "World Travel"},
                {value = "758", label = "World Tree"},
            }
        },
        -- cat 4: Socio-Political Structures (71 tags)
        {
            type = "checkbox",
            key = "tag_pick_4",
            label = "Tags: Socio-Political Structures (71)",
            options = {
                {value = "5", label = "Academy"},
                {value = "29", label = "All-Girls School"},
                {value = "51", label = "Aristocracy"},
                {value = "52", label = "Arms Dealers"},
                {value = "53", label = "Army"},
                {value = "54", label = "Army Building"},
                {value = "61", label = "Assassins"},
                {value = "75", label = "Battle Academy"},
                {value = "76", label = "Battle Competition"},
                {value = "100", label = "Boss-Subordinate Relationship"},
                {value = "108", label = "Business Management"},
                {value = "806", label = "Business Wars"},
                {value = "132", label = "Clan Building"},
                {value = "137", label = "Clubs"},
                {value = "153", label = "Contracts"},
                {value = "156", label = "Cosmic Wars"},
                {value = "159", label = "Court Official"},
                {value = "162", label = "Crafting"},
                {value = "185", label = "Debts"},
                {value = "218", label = "Drugs"},
                {value = "226", label = "Earth Invasion"},
                {value = "228", label = "Economics"},
                {value = "235", label = "Empires"},
                {value = "242", label = "Eunuch"},
                {value = "247", label = "Evil Religions"},
                {value = "258", label = "Family Business"},
                {value = "266", label = "Farming"},
                {value = "282", label = "Fleet Battles"},
                {value = "296", label = "Gambling"},
                {value = "300", label = "Gangs"},
                {value = "303", label = "Generals"},
                {value = "308", label = "Gladiators"},
                {value = "322", label = "Guilds"},
                {value = "353", label = "Hunters"},
                {value = "358", label = "Imperial Harem"},
                {value = "362", label = "Industrialization"},
                {value = "376", label = "JSDF"},
                {value = "379", label = "Kingdom Building"},
                {value = "380", label = "Kingdoms"},
                {value = "381", label = "Knights"},
                {value = "388", label = "Leadership"},
                {value = "823", label = "Lord"},
                {value = "408", label = "Loyal Subordinates"},
                {value = "420", label = "Management"},
                {value = "428", label = "Master-Disciple Relationship"},
                {value = "429", label = "Master-Servant Relationship"},
                {value = "431", label = "Matriarchy"},
                {value = "437", label = "Military"},
                {value = "448", label = "Money Grubber"},
                {value = "485", label = "Nobles"},
                {value = "529", label = "Pirates"},
                {value = "536", label = "Politics"},
                {value = "540", label = "Poor to Rich"},
                {value = "579", label = "Religions"},
                {value = "589", label = "Rich to Poor"},
                {value = "594", label = "Royalty"},
                {value = "599", label = "Samurai"},
                {value = "609", label = "Secret Organizations"},
                {value = "613", label = "Sect Development"},
                {value = "656", label = "Slaves"},
                {value = "678", label = "Strategic Battles"},
                {value = "680", label = "Strength-based Social Hierarchy"},
                {value = "684", label = "Student Council"},
                {value = "685", label = "Student-Teacher Relationship"},
                {value = "688", label = "Sudden Wealth"},
                {value = "698", label = "Teamwork"},
                {value = "802", label = "Territory Management"},
                {value = "702", label = "Terrorists"},
                {value = "747", label = "War Records"},
                {value = "748", label = "Wars"},
                {value = "751", label = "Wealthy Characters"},
            }
        },
        -- cat 5: Relationship Tropes (136 tags)
        {
            type = "checkbox",
            key = "tag_pick_5",
            label = "Tags: Relationship Tropes (136)",
            options = {
                {value = "21", label = "Adultery"},
                {value = "23", label = "Affair"},
                {value = "33", label = "Anal"},
                {value = "55", label = "Arranged Marriage"},
                {value = "77", label = "BDSM"},
                {value = "82", label = "Bestiality"},
                {value = "84", label = "Bickering Couple"},
                {value = "88", label = "Blackmail"},
                {value = "90", label = "Blind Dates"},
                {value = "102", label = "Breast Fetish"},
                {value = "103", label = "Broken Engagement"},
                {value = "104", label = "Brother Complex"},
                {value = "105", label = "Brotherhood"},
                {value = "124", label = "Child Abuse"},
                {value = "127", label = "Childhood Friends"},
                {value = "128", label = "Childhood Love"},
                {value = "129", label = "Childhood Promise"},
                {value = "135", label = "Clingy Lover"},
                {value = "138", label = "Clumsy Love Interests"},
                {value = "141", label = "Cold Love Interests"},
                {value = "148", label = "Complex Family Relationships"},
                {value = "151", label = "Confinement"},
                {value = "160", label = "Cousins"},
                {value = "170", label = "Cunnilingus"},
                {value = "184", label = "Death of Loved Ones"},
                {value = "198", label = "Devoted Love Interests"},
                {value = "199", label = "Different Social Status"},
                {value = "207", label = "Divorce"},
                {value = "211", label = "Doting Love Interests"},
                {value = "225", label = "Early Romance"},
                {value = "236", label = "Enemies Become Allies"},
                {value = "237", label = "Enemies Become Lovers"},
                {value = "238", label = "Engagement"},
                {value = "249", label = "Exhibitionism"},
                {value = "255", label = "Familial Love"},
                {value = "257", label = "Family"},
                {value = "259", label = "Family Conflict"},
                {value = "271", label = "Fated Lovers"},
                {value = "273", label = "Fellatio"},
                {value = "279", label = "First Love"},
                {value = "280", label = "First-time Intercourse"},
                {value = "284", label = "Forced into a Relationship"},
                {value = "285", label = "Forced Living Arrangements"},
                {value = "286", label = "Forced Marriage"},
                {value = "290", label = "Friends Become Enemies"},
                {value = "848", label = "Furry Relationship"},
                {value = "293", label = "Futanari"},
                {value = "309", label = "Glasses-wearing Love Interests"},
                {value = "321", label = "Guardian Relationship"},
                {value = "326", label = "Handjob"},
                {value = "329", label = "Harem-seeking Protagonist"},
                {value = "351", label = "Human-Nonhuman Relationship"},
                {value = "359", label = "Incest"},
                {value = "373", label = "Jealousy"},
                {value = "377", label = "Kidnappings"},
                {value = "378", label = "Kind Love Interests"},
                {value = "385", label = "Late Romance"},
                {value = "398", label = "Long Separations"},
                {value = "399", label = "Long-distance Relationship"},
                {value = "402", label = "Love at First Sight"},
                {value = "403", label = "Love Interest Falls in Love First"},
                {value = "404", label = "Love Rivals"},
                {value = "405", label = "Love Triangles"},
                {value = "406", label = "Lovers Reunited"},
                {value = "419", label = "Male Yandere"},
                {value = "423", label = "Manly Gay Couple"},
                {value = "424", label = "Marriage"},
                {value = "425", label = "Marriage of Convenience"},
                {value = "430", label = "Masturbation"},
                {value = "438", label = "Mind Break"},
                {value = "441", label = "Mismatched Couple"},
                {value = "825", label = "More Children More Blessings"},
                {value = "480", label = "Netorare"},
                {value = "481", label = "Netorase"},
                {value = "482", label = "Netori"},
                {value = "488", label = "Nudity"},
                {value = "490", label = "Obsessive Love"},
                {value = "491", label = "Office Romance"},
                {value = "492", label = "Older Love Interests"},
                {value = "495", label = "Online Romance"},
                {value = "499", label = "Orgy"},
                {value = "504", label = "Outdoor Intercourse"},
                {value = "507", label = "Overprotective Siblings"},
                {value = "509", label = "Paizuri"},
                {value = "512", label = "Parent Complex"},
                {value = "517", label = "Persistent Love Interests"},
                {value = "537", label = "Polyandry"},
                {value = "538", label = "Polygamy"},
                {value = "541", label = "Popular Love Interests"},
                {value = "543", label = "Possessive Characters"},
                {value = "545", label = "Power Couple"},
                {value = "549", label = "Pregnancy"},
                {value = "550", label = "Pretend Lovers"},
                {value = "558", label = "Prostitutes"},
                {value = "559", label = "Protagonist Falls in Love First"},
                {value = "568", label = "R-18"},
                {value = "571", label = "Rape"},
                {value = "572", label = "Rape Victim Becomes Lover"},
                {value = "586", label = "Reverse Harem"},
                {value = "587", label = "Reverse Rape"},
                {value = "588", label = "Reversible Couple"},
                {value = "592", label = "Romantic Subplot"},
                {value = "607", label = "Secret Crush"},
                {value = "610", label = "Secret Relationship"},
                {value = "614", label = "Seduction"},
                {value = "619", label = "Senpai-Kouhai Relationship"},
                {value = "626", label = "Sex Friends"},
                {value = "627", label = "Sex Slaves"},
                {value = "628", label = "Sexual Abuse"},
                {value = "638", label = "Shoujo-Ai Subplot"},
                {value = "639", label = "Shounen-Ai Subplot"},
                {value = "642", label = "Sibling Rivalry"},
                {value = "643", label = "Sibling's Care"},
                {value = "644", label = "Siblings"},
                {value = "645", label = "Siblings Not Related by Blood"},
                {value = "787", label = "Single Female Lead"},
                {value = "649", label = "Single Parent"},
                {value = "650", label = "Sister Complex"},
                {value = "654", label = "Slave Harem"},
                {value = "659", label = "Slow Romance"},
                {value = "660", label = "Smart Couple"},
                {value = "672", label = "Stalkers"},
                {value = "673", label = "Stockholm Syndrome"},
                {value = "681", label = "Strong Love Interests"},
                {value = "704", label = "Threesome"},
                {value = "713", label = "Torture"},
                {value = "714", label = "Toys"},
                {value = "725", label = "Tsundere"},
                {value = "726", label = "Twins"},
                {value = "730", label = "Unconditional Love"},
                {value = "738", label = "Unrequited Love"},
                {value = "745", label = "Voyeurism"},
                {value = "760", label = "Yandere"},
                {value = "762", label = "Younger Brothers"},
                {value = "763", label = "Younger Love Interests"},
                {value = "764", label = "Younger Sisters"},
            }
        },
        -- cat 6: Narrative (46 tags)
        {
            type = "checkbox",
            key = "tag_pick_6",
            label = "Tags: Narrative (46)",
            options = {
                {value = "31", label = "Amnesia"},
                {value = "83", label = "Betrayal"},
                {value = "112", label = "Cannibalism"},
                {value = "121", label = "Chat Rooms"},
                {value = "143", label = "Collection of Short Stories"},
                {value = "152", label = "Conflicting Loyalties"},
                {value = "163", label = "Crime"},
                {value = "164", label = "Criminals"},
                {value = "166", label = "Crossover"},
                {value = "183", label = "Death"},
                {value = "187", label = "Delusions"},
                {value = "798", label = "Eavesdropping"},
                {value = "241", label = "Episodic"},
                {value = "281", label = "Flashbacks"},
                {value = "318", label = "Gore"},
                {value = "349", label = "Human Experimentation"},
                {value = "355", label = "Identity Crisis"},
                {value = "356", label = "Imaginary Friend"},
                {value = "364", label = "Inheritance"},
                {value = "367", label = "Interconnected Storylines"},
                {value = "370", label = "Investigations"},
                {value = "824", label = "Life Script"},
                {value = "455", label = "Multiple Identities"},
                {value = "457", label = "Multiple POV"},
                {value = "463", label = "Murders"},
                {value = "470", label = "Mysterious Past"},
                {value = "471", label = "Mystery Solving"},
                {value = "483", label = "Nightmares"},
                {value = "487", label = "Non-linear Storytelling"},
                {value = "494", label = "Oneshot"},
                {value = "498", label = "Organized Crime"},
                {value = "513", label = "Parody"},
                {value = "515", label = "Past Plays a Big Role"},
                {value = "546", label = "Power Struggle"},
                {value = "557", label = "Prophecies"},
                {value = "573", label = "Rebellion"},
                {value = "585", label = "Revenge"},
                {value = "591", label = "Rivalry"},
                {value = "600", label = "Saving the World"},
                {value = "601", label = "Schemes And Conspiracies"},
                {value = "608", label = "Secret Identity"},
                {value = "612", label = "Secrets"},
                {value = "636", label = "Short Story"},
                {value = "692", label = "Survival"},
                {value = "705", label = "Thriller"},
                {value = "709", label = "Time Skip"},
            }
        },
        -- cat 7: Beings & Factions (68 tags)
        {
            type = "checkbox",
            key = "tag_pick_7",
            label = "Tags: Beings & Factions (68)",
            options = {
                {value = "22", label = "Adventurers"},
                {value = "28", label = "Aliens"},
                {value = "38", label = "Angels"},
                {value = "62", label = "Astrologers"},
                {value = "78", label = "Beast Companions"},
                {value = "79", label = "Beastkin"},
                {value = "80", label = "Beasts"},
                {value = "188", label = "Demi-Humans"},
                {value = "189", label = "Demon Lord"},
                {value = "191", label = "Demons"},
                {value = "216", label = "Dragons"},
                {value = "219", label = "Druids"},
                {value = "222", label = "Dwarfs"},
                {value = "233", label = "Elves"},
                {value = "239", label = "Engineer"},
                {value = "244", label = "Evil Gods"},
                {value = "245", label = "Evil Organizations"},
                {value = "252", label = "Fairies"},
                {value = "253", label = "Fallen Angels"},
                {value = "256", label = "Familiars"},
                {value = "264", label = "Fantasy Creatures"},
                {value = "289", label = "Fox Spirits"},
                {value = "307", label = "Ghosts"},
                {value = "311", label = "Goblins"},
                {value = "313", label = "God-human Relationship"},
                {value = "314", label = "Goddesses"},
                {value = "316", label = "Gods"},
                {value = "317", label = "Golems"},
                {value = "319", label = "Grave Keepers"},
                {value = "338", label = "Herbalist"},
                {value = "339", label = "Heroes"},
                {value = "345", label = "Homunculus"},
                {value = "357", label = "Immortals"},
                {value = "360", label = "Incubus"},
                {value = "366", label = "Insects"},
                {value = "374", label = "Jiangshi"},
                {value = "389", label = "Legends"},
                {value = "411", label = "Magic Beasts"},
                {value = "449", label = "Monster Girls"},
                {value = "451", label = "Monster Tamer"},
                {value = "452", label = "Monsters"},
                {value = "465", label = "Mutated Creatures"},
                {value = "466", label = "Mutations"},
                {value = "472", label = "Mythical Beasts"},
                {value = "484", label = "Ninjas"},
                {value = "497", label = "Orcs"},
                {value = "524", label = "Phoenixes"},
                {value = "534", label = "Police"},
                {value = "552", label = "Priestesses"},
                {value = "553", label = "Priests"},
                {value = "597", label = "Saints"},
                {value = "620", label = "Sentient Objects"},
                {value = "624", label = "Seven Deadly Sins"},
                {value = "625", label = "Seven Virtues"},
                {value = "635", label = "Shikigami"},
                {value = "664", label = "Souls"},
                {value = "669", label = "Spirit Advisor"},
                {value = "671", label = "Spirits"},
                {value = "679", label = "Strategist"},
                {value = "686", label = "Succubus"},
                {value = "695", label = "Sword Wielder"},
                {value = "700", label = "Tentacles"},
                {value = "739", label = "Valkyries"},
                {value = "740", label = "Vampires"},
                {value = "752", label = "Werebeasts"},
                {value = "754", label = "Witches"},
                {value = "761", label = "Youkai"},
                {value = "765", label = "Zombies"},
            }
        },
        -- cat 8: Professional Archetypes (64 tags)
        {
            type = "checkbox",
            key = "tag_pick_8",
            label = "Tags: Professional Archetypes (64)",
            options = {
                {value = "7", label = "Acting"},
                {value = "44", label = "Antique Shop"},
                {value = "50", label = "Archery"},
                {value = "60", label = "Artists"},
                {value = "68", label = "Bands"},
                {value = "809", label = "Basketball"},
                {value = "89", label = "Blacksmith"},
                {value = "97", label = "Bodyguards"},
                {value = "109", label = "Businessmen"},
                {value = "110", label = "Butlers"},
                {value = "117", label = "Celebrities"},
                {value = "123", label = "Chefs"},
                {value = "157", label = "Cosplay"},
                {value = "177", label = "Dancers"},
                {value = "196", label = "Detectives"},
                {value = "208", label = "Doctors"},
                {value = "214", label = "Dragon Riders"},
                {value = "215", label = "Dragon Slayers"},
                {value = "224", label = "e-Sports"},
                {value = "229", label = "Editors"},
                {value = "274", label = "Female Master"},
                {value = "780", label = "Football"},
                {value = "299", label = "Gamers"},
                {value = "323", label = "Gunfighters"},
                {value = "324", label = "Hackers"},
                {value = "779", label = "Hollywood"},
                {value = "386", label = "Lawyers"},
                {value = "782", label = "Live Streaming"},
                {value = "860", label = "Machinist"},
                {value = "416", label = "Maids"},
                {value = "421", label = "Mangaka"},
                {value = "433", label = "Medical Knowledge"},
                {value = "435", label = "Mercenaries"},
                {value = "436", label = "Merchants"},
                {value = "445", label = "Models"},
                {value = "453", label = "Movies"},
                {value = "464", label = "Music"},
                {value = "489", label = "Nurses"},
                {value = "514", label = "Part-Time Job"},
                {value = "521", label = "Pharmacist"},
                {value = "525", label = "Photography"},
                {value = "528", label = "Pilots"},
                {value = "532", label = "Poetry"},
                {value = "533", label = "Poisons"},
                {value = "556", label = "Programmer"},
                {value = "564", label = "Puppeteers"},
                {value = "581", label = "Reporters"},
                {value = "603", label = "Scientists"},
                {value = "604", label = "Sculptors"},
                {value = "622", label = "Serial Killers"},
                {value = "623", label = "Servants"},
                {value = "634", label = "Shield User"},
                {value = "640", label = "Showbiz"},
                {value = "648", label = "Singers"},
                {value = "662", label = "Soldiers"},
                {value = "666", label = "Spear Wielder"},
                {value = "668", label = "Spies"},
                {value = "675", label = "Store Owner"},
                {value = "697", label = "Teachers"},
                {value = "703", label = "Thieves"},
                {value = "733", label = "Unique Weapon User"},
                {value = "744", label = "Voice Actors"},
                {value = "746", label = "Waiters"},
                {value = "759", label = "Writers"},
            }
        },
        -- cat 9: Tone & Atmosphere (27 tags)
        {
            type = "checkbox",
            key = "tag_pick_9",
            label = "Tags: Tone & Atmosphere (27)",
            options = {
                {value = "4", label = "Abusive Characters"},
                {value = "107", label = "Bullying"},
                {value = "146", label = "Comedic Undertone"},
                {value = "155", label = "Corruption"},
                {value = "167", label = "Cruel Characters"},
                {value = "176", label = "Cute Story"},
                {value = "181", label = "Dark"},
                {value = "789", label = "Dark Fantasy"},
                {value = "193", label = "Depictions of Cruelty"},
                {value = "194", label = "Depression"},
                {value = "195", label = "Destiny"},
                {value = "201", label = "Discrimination"},
                {value = "262", label = "Fanaticism"},
                {value = "291", label = "Friendship"},
                {value = "333", label = "Heartwarming"},
                {value = "396", label = "Loneliness"},
                {value = "442", label = "Misunderstandings"},
                {value = "469", label = "Mysterious Illness"},
                {value = "476", label = "Nationalism"},
                {value = "522", label = "Philosophical"},
                {value = "523", label = "Phobias"},
                {value = "567", label = "R-15"},
                {value = "570", label = "Racism"},
                {value = "646", label = "Sickly Characters"},
                {value = "661", label = "Social Outcasts"},
                {value = "689", label = "Suicides"},
                {value = "701", label = "Terminal Illness"},
            }
        },
        -- cat 10: Adaptations (90 tags)
        {
            type = "checkbox",
            key = "tag_pick_10",
            label = "Tags: Adaptations (90)",
            options = {
                {value = "8", label = "Adapted from Manga"},
                {value = "9", label = "Adapted from Manhua"},
                {value = "10", label = "Adapted to Anime"},
                {value = "846", label = "Adapted to Donghua"},
                {value = "11", label = "Adapted to Drama"},
                {value = "12", label = "Adapted to Drama CD"},
                {value = "13", label = "Adapted to Game"},
                {value = "14", label = "Adapted to Manga"},
                {value = "15", label = "Adapted to Manhua"},
                {value = "16", label = "Adapted to Manhwa"},
                {value = "17", label = "Adapted to Movie"},
                {value = "18", label = "Adapted to Visual Novel"},
                {value = "833", label = "Arknights"},
                {value = "66", label = "Award-winning Work"},
                {value = "69", label = "Based on a Movie"},
                {value = "70", label = "Based on a Song"},
                {value = "71", label = "Based on a TV Show"},
                {value = "72", label = "Based on a Video Game"},
                {value = "73", label = "Based on a Visual Novel"},
                {value = "74", label = "Based on an Anime"},
                {value = "839", label = "Black Clover"},
                {value = "770", label = "Bleach"},
                {value = "885", label = "Blue Archive"},
                {value = "832", label = "BTTH"},
                {value = "854", label = "Classroom of the Elite"},
                {value = "800", label = "Conferred Gods"},
                {value = "783", label = "Cyberpunk 2077"},
                {value = "840", label = "Danmachi"},
                {value = "778", label = "DC Universe"},
                {value = "812", label = "Demon Slayer"},
                {value = "804", label = "Detective Conan"},
                {value = "851", label = "Digimon"},
                {value = "794", label = "DnD"},
                {value = "772", label = "Douluo Dalu"},
                {value = "773", label = "Dragon Ball"},
                {value = "887", label = "Dragon Raja"},
                {value = "868", label = "Fabulous Beast"},
                {value = "814", label = "Fairy Tail"},
                {value = "872", label = "Final Fantasy"},
                {value = "886", label = "Food Wars!"},
                {value = "816", label = "Frieren"},
                {value = "813", label = "Game of Thrones"},
                {value = "815", label = "Genshin Impact"},
                {value = "768", label = "Harry Potter"},
                {value = "847", label = "Highschool DxD"},
                {value = "865", label = "Hikigaya"},
                {value = "801", label = "Honghuang"},
                {value = "818", label = "Honkai Impact 3"},
                {value = "889", label = "Honkai Star Rails"},
                {value = "777", label = "Hunter x Hunter"},
                {value = "859", label = "JoJo’s Bizarre Adventure"},
                {value = "796", label = "Journey to the West"},
                {value = "776", label = "Jujutsu Kaisen"},
                {value = "843", label = "Kamen Rider"},
                {value = "864", label = "King's Avatar"},
                {value = "862", label = "Kirkmanverse"},
                {value = "791", label = "League of Legends"},
                {value = "799", label = "Lord of the Mysteries"},
                {value = "853", label = "Lord of the Ring"},
                {value = "766", label = "Marvel"},
                {value = "790", label = "Minecraft"},
                {value = "888", label = "Monster Hunter"},
                {value = "769", label = "Naruto"},
                {value = "844", label = "Nasuverse"},
                {value = "767", label = "One Piece"},
                {value = "837", label = "One Punch Man"},
                {value = "826", label = "Overlord"},
                {value = "863", label = "Pirates of Caribbean"},
                {value = "771", label = "Pokemon"},
                {value = "858", label = "Project Moon"},
                {value = "861", label = "Qing Transmigration"},
                {value = "856", label = "Resident Evil"},
                {value = "820", label = "Siheyuan"},
                {value = "870", label = "Slay the Gods"},
                {value = "817", label = "Star Wars"},
                {value = "866", label = "Strike the Blood"},
                {value = "785", label = "Swallowed Star"},
                {value = "836", label = "The Boys"},
                {value = "869", label = "The Eminence in Shadow"},
                {value = "852", label = "The Walking Dead"},
                {value = "850", label = "Toaru"},
                {value = "857", label = "Touhou Project"},
                {value = "838", label = "Ultraman"},
                {value = "834", label = "Uma Musume"},
                {value = "845", label = "Versatile Mage"},
                {value = "743", label = "Vocaloid"},
                {value = "775", label = "Warhammer"},
                {value = "819", label = "Witcher"},
                {value = "774", label = "Yu-Gi-Oh!"},
                {value = "867", label = "Zenless Zone Zero"},
            }
        },
        -- cat 11: Miscellaneous Narrative Elements (40 tags)
        {
            type = "checkbox",
            key = "tag_pick_11",
            label = "Tags: Miscellaneous Narrative Elements (40)",
            options = {
                {value = "39", label = "Animal Characteristics"},
                {value = "40", label = "Animal Rearing"},
                {value = "45", label = "Apartment Life"},
                {value = "57", label = "Artifact Crafting"},
                {value = "58", label = "Artifacts"},
                {value = "96", label = "Body-double"},
                {value = "98", label = "Books"},
                {value = "106", label = "Buddhism"},
                {value = "113", label = "Card Games"},
                {value = "126", label = "Childcare"},
                {value = "139", label = "Co-Workers"},
                {value = "140", label = "Cohabitation"},
                {value = "144", label = "College/University"},
                {value = "154", label = "Cooking"},
                {value = "174", label = "Cute Children"},
                {value = "841", label = "Daily Intelligence"},
                {value = "180", label = "Daoism"},
                {value = "202", label = "Disfigurement"},
                {value = "209", label = "Dolls/Puppets"},
                {value = "210", label = "Domestic Affairs"},
                {value = "217", label = "Dreams"},
                {value = "227", label = "Easy Going Life"},
                {value = "277", label = "Feng Shui"},
                {value = "283", label = "Folklore"},
                {value = "340", label = "Heterochromia"},
                {value = "821", label = "Hong Kong"},
                {value = "372", label = "Jack of All Trades"},
                {value = "384", label = "Language Barrier"},
                {value = "393", label = "Living Abroad"},
                {value = "394", label = "Living Alone"},
                {value = "440", label = "Misandry"},
                {value = "473", label = "Mythology"},
                {value = "501", label = "Otaku"},
                {value = "520", label = "Pets"},
                {value = "593", label = "Roommates"},
                {value = "647", label = "Sign Language"},
                {value = "657", label = "Sleeping"},
                {value = "729", label = "Ugly to Beautiful"},
                {value = "734", label = "Unique Weapons"},
                {value = "788", label = "Western Names"},
            }
        },
        -- [TAG PICKERS END]
    }
end

-- ── Filtered catalog ─────────────────────────────────────────────────────────

function getCatalogFiltered(index, filters)
    local page = index + 1
    local orderBy = filters["orderBy"] or "update"
    local order = filters["order"] or "desc"
    local status = filters["status"] or "all"
    local release_status = filters["release_status"] or "all"
    local addition_age = filters["addition_age"] or "all"
    local min_rating = filters["min_rating"] or ""
    local min_reviews = filters["min_reviews"] or ""
    local count_chapters = filters["count_chapters"] or ""
    local count_mode = filters["count_mode"] or "min"
    local count_characters = filters["count_characters"] or ""
    local genre_op = filters["genre_operator"] or "and"
    local tag_op = filters["tag_operator"] or "and"
    local title_search = filters["title_search"] or ""
    local tag_cat = filters["tag_category"] or "0"

    local genres_inc = filters["genres_included"] or {}
    local genres_exc = filters["genres_excluded"] or {}

    -- ── Tags: keywords + category scope + chip picks (v1.2.0) ──────────
    -- The tag_search_inc / tag_search_exc keyword fields resolve through
    -- tagSearchResolve, scoped to the tag_category picker. A partial
    -- keyword includes EVERY tag whose name contains it (v1.2.0 search
    -- semantics); only a keyword with zero matches raises an error.
    -- The 11 tag_pick_N chip groups contribute all their selected ids;
    -- everything merges into one deduplicated ti= list.
    local incText = filters["tag_search_inc"] or ""
    local excText = filters["tag_search_exc"] or ""

    local function resolveTagField(text, fieldName)
        if text == nil or text == "" then return {} end
        local ok, res = pcall(tagSearchResolve, text, tag_cat)
        if not ok then
            error("Tag Search (" .. fieldName .. "): " .. tostring(res))
        end
        return res
    end

    local tags_inc = resolveTagField(incText, "include")
    local tags_exc = resolveTagField(excText, "exclude")

    -- Chip-picked tags (include side, v1.2.0 multi-select): each of the
    -- 11 tag_pick_N checkbox groups contributes ALL its selected ids
    -- (marshalled by the app as filters["tag_pick_N_included"] arrays).
    -- A stale sheet from an older plugin version could still carry the
    -- v1.1.9 single-value form (plain string) — honored too. Every id is
    -- validated against the index; junk is skipped.
    local pickedSeen = {}
    for _, id in ipairs(tags_inc) do pickedSeen[id] = true end
    local function addPickedId(pid)
        if pid == "" or pickedSeen[pid] then return end
        for _, t in ipairs(ALL_TAGS) do
            if t.id == pid then
                pickedSeen[pid] = true
                tags_inc[#tags_inc + 1] = pid
                return
            end
        end
    end
    for i = 1, 11 do
        local picks = filters["tag_pick_" .. i .. "_included"]
        if type(picks) == "table" then
            for _, picked in ipairs(picks) do
                addPickedId(tostring(picked))
            end
        end
        addPickedId(tostring(filters["tag_pick_" .. i] or ""))
    end

    local params = "orderBy=" .. orderBy .. "&order=" .. order .. "&status=" .. status ..
        "&release_status=" .. release_status .. "&addition_age=" .. addition_age ..
        "&page=" .. tostring(page)

    -- Title search (the novel-finder text box, now inside the filters)
    if title_search ~= "" then
        params = params .. "&text=" .. url_encode(title_search)
    end

    -- Rating filters
    if min_rating ~= "" then
        params = params .. "&minr=" .. min_rating
    end
    if min_reviews ~= "" then
        params = params .. "&minrc=" .. min_reviews
    end

    -- Count filters (the site supports ONE count_type at a time;
    -- chapters take priority over characters)
    if count_chapters ~= "" then
        params = params .. "&count_type=chapter&count_filter=" .. count_mode .. "&count_value=" .. count_chapters
    elseif count_characters ~= "" then
        params = params .. "&count_type=character&count_filter=min&count_value=" .. count_characters
    end

    -- The site forces minrc=5 for weighted ordering (matches site behaviour)
    if orderBy == "weighted" and min_reviews == "" then
        params = params .. "&minrc=5"
    end

    -- Genres
    if #genres_inc > 0 then
        params = params .. "&gi=" .. table.concat(genres_inc, ",") .. "&gc=" .. genre_op
    end
    if #genres_exc > 0 then
        params = params .. "&ge=" .. table.concat(genres_exc, ",")
    end

    -- Tags
    if #tags_inc > 0 then
        params = params .. "&ti=" .. table.concat(tags_inc, ",") .. "&tc=" .. tag_op
    end
    if #tags_exc > 0 then
        params = params .. "&te=" .. table.concat(tags_exc, ",")
    end

    local pp = fetchCatalogPage("en/novel-finder", "/en/novel-finder.json", params)
    if not pp then
        log_error("wtrlab: getCatalogFiltered failed")
        return { items = {}, hasNext = false }
    end
    return pagePropsToResult(pp, page)
end
