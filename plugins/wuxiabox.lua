-- ═══════════════════════════════════════════════════════════════════════════
-- WuxiaBox source plugin for NoveLA  (https://www.wuxiabox.com)
-- File: en/wuxiabox.lua — Version 2.3.0 (2026-09-19)
-- Upgrades the community plugin en/wuxiabox.lua v1.0.1 in place (same
-- source id "wuxiabox"). Book URLs are unchanged (same site, same
-- /novel/{slug}.html addresses), so existing libraries carry over.
--
-- 2.3.0 (2026-09-19) — SMART MIRROR SWITCHER.
--
--   • MIRROR SWITCHING REWORKED. The "Source site" setting now truly
--     moves every plugin-controlled fetch — catalog, filters, search,
--     book details, chapter lists — to the chosen site, and chapter text
--     follows the moment the canonical host stumbles (the engine itself
--     always fetches chapter pages from the canonical wuxiabox.com URL
--     first — NoveLA does not expose that hop to Lua; when it yields an
--     error page, the plugin charges the failure and rescues the chapter
--     from the healthy site). Saved novels keep their canonical
--     wuxiabox.com URLs either way — no library fragmentation, ever.
--   • SITE HEALTH TRACKER (circuit breaker, persists across app restarts
--     via set_preference): 2 consecutive failures on one site (network
--     error, 5xx, Cloudflare page, error-page body) put it in a
--     10-minute cooldown — every later fetch goes straight to the other
--     site with no wasted doomed request, and the site is re-admitted
--     automatically when the cooldown expires (self-healing). Any success
--     resets it. A 502 you hit while reading is paid for ONCE: the
--     chapter is rescued from the healthy site and the next 10 minutes
--     of requests skip the failing one entirely.
--   • Chapter rescue is instant and smart: no sleep before the first
--     retry attempt, attempt order follows the health tracker (the
--     engine's own failed fetch of the primary charges it first), and a
--     404 on one site no longer poisons that site's health (the site
--     answered — the page just isn't there; e.g. mirror-only slugs).
--   • 200-but-junk bodies (origin 502/504 HTML served with status 200,
--     maintenance interstitials) are detected and treated as failures on
--     every fetch path, not just chapter pages.
--   • SEARCH pagination is now mirror-native: each running search
--     remembers WHICH site created its searchid, so a search that started
--     on the mirror keeps paginating on the mirror (searchids are
--     site-specific — v2.2.0 hard-pinned result pages to the primary,
--     which silently killed pagination for mirror-served searches).
--   • Chapter-text failures now raise a clear error naming both sites
--     instead of returning empty text (the empty path made the engine
--     fall through to generic heuristics on the very error page it just
--     failed on).
--   • transformChapterUrl() added as a forward-compatible hook: engines
--     that expose it (see the PR doc's optional 15-line Kotlin patch)
--     let this plugin rewrite the engine's OWN chapter fetch to the
--     healthy site before the doomed canonical request is even made.
--     On stock engines the function is simply never called.
--
-- 2.2.0 (2026-09-18) — POSTER FIX, SEARCH PAGINATION, TAG CURATION.
--
--   • POSTERS FIXED — the site's cover images are served behind the
--     same Cloudflare shield as the pages, but image URLs (.jpg) are
--     EXEMPT from NoveLA's Cloudflare bypass (STATIC_EXTENSIONS), so a
--     challenged cover request returned the challenge page to the
--     image loader and the poster silently failed. All cover URLs are
--     now routed through the wsrv.nl image proxy (the same
--     images.weserv.nl service other NoveLA sources use for exactly
--     this problem — the engine whitelists it). Direct-from-site
--     covers remain available via the new "Cover images" setting.
--   • SEARCH now paginates continuously: the total count fallback
--     (was dead — the Lua pattern could not cross the newline between
--     <ul class="pagination"> and the 总数 marker) and the next-page
--     link detection both work again, and each result page re-extracts
--     the searchid from its own pager so pagination survives engine
--     restarts mid-scroll.
--   • TAGS CURATED — the 6,723-entry tag index (148 KB of the file!)
--     is replaced by 755 genuinely-used tags (the wtr-lab taxonomy
--     cross-reference plus every Popular Tag and the whole Honghuang
--     family). Browsing them is now a native SEARCHABLE picker: the
--     "Tags" filter is a tag_input — type a few letters and matching
--     tags appear as suggestions; picked tags become chips. This
--     replaces both the old free-text "Tag Search" box and the
--     "Popular Tags" chip group.
--   • CLOUDFLARE: getUserAgentPreset() registers a modern Chrome
--     Mobile UA for every request of this source AND its image host,
--     so the cf_clearance cookie the WebView bakes stays valid for
--     cover loads too (it is bound to the User-Agent).
--   • show_error() (new NoveLA API) surfaces actionable dialogs when
--     both sites are unreachable or a tag pick cannot be resolved.
--
-- 2.1.0 (2026-09-16) — SEARCH FIX, POPULAR TAGS, MIRROR SITE.

--
--   • SEARCH FIXED — the v2.0.0 search rejected valid result pages.
--     Root cause (verified live): a search that matches only ONE (or a
--     few) novels returns a result page WITHOUT a pager, and the site
--     only puts "searchid=" in PAGER links — so the v2.0.0 gate
--     "extractSearchId(body) ~= nil" discarded the perfectly good
--     result page and the app showed NOTHING. Pasting an exact title
--     (1 hit, no pager) always produced an empty list. The page is now
--     accepted when it contains novel cards OR a searchid; pagination
--     is unchanged (later pages still need the searchid, which every
--     multi-page result carries).
--   • MIRROR SITE — https://www.wuxiaspot.com/ added as an automatic
--     fallback (same content, same /novel/{slug}.html addresses, zero
--     cross-references). When the main site fails (Cloudflare, 502s,
--     downtime) every fetch — catalog, filters, tags, search, book
--     pages, chapter lists, chapter text — transparently retries on the
--     mirror. A "Source site" setting picks the behaviour:
--       auto (default)  WuxiaBox first, WuxiaSpot on failure
--       wuxiabox only   never touch the mirror
--       wuxiaspot first mirror as the default, WuxiaBox as backup
--     URLs handed to the engine are ALWAYS canonical wuxiabox.com
--     links regardless of which site served the bytes (libraries never
--     fragment across the two hosts).
--   • POPULAR TAGS picker — the A-Z "Tag Search Category" letter
--     filter is GONE (6,723 tags behind 26 letters was not browsable).
--     Replaced by a multi-select "Popular Tags" chip group (the famous
--     tropes: Male/Female Protagonist, System, Cultivation, Rebirth,
--     Transmigration, Regression, Weak to Strong, Honghuang (the whole
--     Honghuang* family), Hongmeng, Ancient China, …). Selections
--     merge with the free-text Tag Search keywords into one union
--     browse. The free-text search still resolves partial keywords to
--     EVERY matching tag, exactly as before.
--   • GENRES = categories only. The site's novel pages put categories
--     (<a class="property-item"> → /list/{slug}/) and tags
--     (<a class="tag"> → /tags/{id}-0.html) in the same block; v2.0.0
--     merged both into genres. They are different taxonomies on
--     different pages (categories: /list/…, tags: /browsetags/) —
--     genres now carry ONLY the category chips.
--   • Categories list re-verified against the live
--     /list/all/all-newstime-0.html sidebar (56 categories + All,
--     unchanged from the v2.0.0 harvest).
--
-- 2.0.0 (2026-09-15) — MAJOR UPGRADE of the WuxiaBox plugin. The base
--     v1.0.1 (HnDK0/external-sources) was re-verified function by function
--     against live pages and every behavior worth keeping was carried over;
--     the plugin gained the full tag index, a working search pipeline, and
--     self-healing chapter fetching. Details below.
--
--   UPGRADE NOTES vs BASE v1.0.1
--   • KEPT from v1.0.1 (verified against live HTML): the one-run page
--     cache shared by all book getters; XHR headers on fy.php chapter
--     fragments; cover data-src → src fallback; p.description selector
--     preference; relative-date normalization ("5 hours ago" → date);
--     html_remove selector set (scripts/styles/ads/iframes — merged with
--     the v2 set); "(End of this chapter)" marker removal; the
--     WuxiaBox branding / Chapter-echo / translator-credit line cleaners
--     (merged and extended).
--   • FIXED from v1.0.1:
--       – Status filter values were lowercase ("ongoing"/"completed") but
--         the site's list URLs are capitalized — its own filter links go to
--         /list/all/Completed-newstime-0.html and /list/all/Ongoing-
--         lastdotime-0.html. The old status filter silently did nothing.
--       – getBookDescription preferred <p class="description">, which the
--         site renders EMPTY on novel pages (the real synopsis lives in
--         .summary .content) — and since "" is truthy in Lua, the old
--         code returned empty descriptions. The selector preference is
--         kept, but empty results now fall through to .summary .content.
--       – getBookLastUpdate read the last <time> of the embedded chapter
--         list — but the novel page embeds the OLDEST 100 chapters, so any
--         novel longer than 100 chapters got a stale update date. The date
--         now comes from the newest chapter on the LAST fy.php page (one
--         cached fragment request), with the old behavior as fallback.
--       – Search relied on the engine following the POST redirect and had
--         no result pagination (see "Improved search" below).
--
--   WHAT'S NEW (2.0.0 core feature set)
--   • ALL site tags (see TAG_SEARCH_INDEX below) harvested from
--     https://www.wuxiabox.com/browsetags/ and shipped as a searchable
--     index: the "Tag Search" filter takes any keyword ("system",
--     "male prot", "ancient") and resolves it to EVERY tag whose name
--     contains it — matching is case-insensitive AND space-insensitive
--     ("maleprot" == "Male Protagonist"), so the site's squashed tag
--     names (AncientChina, MaleProtagonist…) are found either way.
--     Numeric tag ids ("34") and "prefix*" wildcards also work.
--     Multiple keywords: comma-separated, all resolved tags are merged.
--     The plugin then browses the tag listings (one request per tag,
--     lightly paced) and merges the results — "everything as search
--     result", the way the site's own tag pages work.
--     The Popular Tags picker (2.1.0) offers the famous tropes as
--     multi-select chips and merges into the same union browse.
--   • Full filter parity with the site's "Categories" browser:
--     57 categories × status (All/Completed/Ongoing) × sort
--     (Newest Added / Last Updated / Most Viewed), plus an "Updates"
--     browse mode (recently updated novels, /updates/).
--     Categories and tags are DIFFERENT taxonomies on different pages:
--     categories come from the /list/ sidebar (56 + All), tags from
--     /browsetags/ (6,723). Genres on book pages carry categories only.
--   • Improved search: the site's search is an EmpireCMS POST form
--     (/e/search/index.php, fields show=title&tempid=1&tbname=news&
--     keyboard=…) that 302-redirects to /e/search/result?searchid=N.
--     NoveLA's http_post does NOT follow redirects, so the old-style
--     "POST and parse" never worked here — the plugin follows the
--     redirect chain manually (Location header, up to 3 hops), falls
--     back to the GET searchget=1 variant, and supports result
--     pagination (/e/search/result/index.php?page=N&searchid=S,
--     20 items/page, total count parsed from the pager). 2.1.0:
--     single-result pages (no pager → no searchid) are accepted via
--     their novel cards, and the whole pipeline retries on the
--     wuxiaspot.com mirror when the main site fails.
--   • "502 Bad Gateway every ~2 chapters" FIX (root cause): a 502/504
--     page from the origin parses fine as HTML, so the app fetched it,
--     got empty text from the plugin, and DownloaderRepository's retry
--     loop classified the failure as non-transient (it only retries
--     timeout/connect errors) — the chapter just failed. The plugin now
--     detects chapter pages without real content (#chapter-article /
--     .chapter-content missing → error/interstitial page) and REFETCHES
--     the chapter itself with exponential backoff (default 4 attempts:
--     ~0.9s / 2.8s / 6.3s waits + jitter), which rides out the site's
--     transient origin flaps. A configurable pacing floor (default
--     1500 ms between chapter requests, os_time is millisecond-
--     resolution in NoveLA) additionally keeps sequential reading from
--     hammering the origin.
--   • Chapter list via parsePage (paginated): the novel page holds the
--     first 100 chapters (ascending); further pages load from
--     /e/extend/fy.php?page=N-1&wjm={slug} (HTML fragment, 100/page).
--     parsePage gives the engine incremental updates (re-reads only the
--     last page on library refresh) instead of re-fetching everything.
--   • Chapter text cleanup: ad <script>s removed, the novel-title /
--     "Author:" / "Synopsis:" echo paragraphs that the site prepends
--     to every chapter are stripped, standard site-reference/translator
--     lines removed, paragraphs preserved via html_text.
--
--   SITE MAP (verified 2026-09-14 against live HTML)
--   • Catalog list      GET  /list/{category}/{status}-{sort}-{page}.html
--                        category: all + 57 slugs · status: all|Completed|Ongoing
--                        sort: newstime (added) | lastdotime (updated) | onclick (views)
--                        page is 0-based, 30 items/page, ~104 000 novels
--   • Tag browse        GET  /tags/{tagid}-0.html (first page, 500 items)
--                        GET  /e/tags/index.php?page={N}&tagid={id}&line=500&tempid=9
--                        total count in the pager: <a title="总数"><b>N</b></a>
--   • Updates           GET  /updates/ then /updates/{N}.html (0-based, 50/page,
--                        cards link to the LATEST chapter — url rewritten to the novel)
--   • Search            POST /e/search/index.php (show=title&tempid=1&tbname=news&keyboard=…)
--                        → 302 → /e/search/result?searchid=S (20/page)
--                        pages: /e/search/result/index.php?page={N}&searchid=S
--                        GET variant: /e/search/?searchget=1&keyboard=…&show=title&tbname=news&tempid=1
--   • Novel page        GET  /novel/{slug}.html
--                        header.novel-header → h1.novel-title · figure.cover img[data-src]
--                        .author span[itemprop=author] · .header-stats (Chapters/Status)
--                        .categories → a.property-item (genres, 2.1.0) +
--                        a.tag (tags, full names — not genres)
--                        #info → p.description (renders EMPTY; fallback) →
--                        .summary .content (real synopsis) · .tags ul.content (tag chips)
--   • Chapter list      novel page (chapters 1-100, ascending) +
--                        /e/extend/fy.php?page={N-1}&wjm={slug} fragments (100/page)
--   • Chapter page      GET  /novel/{slug}_{n}.html → #chapter-article .chapter-content
--                        (.titles h1 = novel title link, h2 = chapter title)
--
--   NOTES / LIMITS
--   • wuxiabox.com sits behind a Cloudflare managed challenge; the
--     wuxiaspot.com mirror is its failover twin (same EmpireCMS site,
--     same slugs). NoveLA's CloudfareVerificationInterceptor already
--     auto-solves challenges via the integrated WebView for every
--     plugin http_get/http_post — do NOT add cf_options (see wtrlab.lua
--     docs; whitelist=true disables the recovery path).
--   • The origin behind Cloudflare intermittently returns 502/504 —
--     that is what the in-plugin chapter retry + pacing address. The app
--     also issues two HTTP hits per chapter (one URL-resolve pass + one
--     document fetch in DownloaderRepository.bookChapter), which makes
--     the pacing floor all the more useful. 2.1.0: the refetch loop
--     alternates WuxiaBox → WuxiaSpot per attempt.
--   • Tag exclusion is NOT offered: the site cannot exclude tags via any
--     URL, and novel cards do not carry their tag list, so client-side
--     exclusion would require fetching every novel page.
--   • The site has no numeric ratings; getBookRating is intentionally
--     not implemented.
--   • Tag labels in /browsetags/ are truncated to 10 chars by the site
--     itself (AncientChi, AdaptedtoM…). The build script expands them to
--     full spaced names when the prefix is unambiguous; the in-plugin
--     search is space-insensitive regardless.
--   • The Popular Tags picker's "Honghuang (all)" entry uses the
--     keyword "honghuang" on purpose: the site has no plain "Honghuang"
--     tag, only the truncated HongHuangB / HonghuangN / HonghuangS /
--     Honghuangs / HongHuangz family — the keyword includes every one
--     of them in the union browse.
--
--   TAG INDEX MAINTENANCE: regenerate with
--     scripts/harvest_wuxiabox_tags.py  (resumable live harvest)
--     scripts/build_wuxiabox_tag_index.py  (dedup → name expansion →
--     splice into TAG_SEARCH_INDEX below), then re-run the harness
--     (test-harness/WuxiaboxTest.java). The full pipeline is documented
--     in wuxiabox_pull_request.md § 9.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "wuxiabox"
name     = "WuxiaBox"
version  = "2.3.0"
baseUrl  = "https://www.wuxiabox.com"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/icons/wuxiabox.png"

local SITE = baseUrl

-- ── Settings keys ───────────────────────────────────────────────────────────
local PREF_RETRY = "wuxiabox_chapter_retries"
local PREF_PACE  = "wuxiabox_chapter_pace_ms"
local PREF_SITE  = "wuxiabox_site_preference"
local PREF_COVERS = "wuxiabox_covers"

local function getRetryCount()
    local v = tonumber(get_preference(PREF_RETRY))
    if v and v >= 1 and v <= 6 then return math.floor(v) end
    return 4
end

local function getPaceMs()
    local v = tonumber(get_preference(PREF_PACE))
    if v and v >= 0 and v <= 10000 then return math.floor(v) end
    return 1500
end

-- ── Mirror site (fallback + optional default) ───────────────────────────────
-- wuxiaspot.com is a full twin of wuxiabox.com: same EmpireCMS install,
-- same /novel/{slug}.html addresses, no cross-links between the two.
-- URLs handed to the engine are ALWAYS canonical (SITE) so libraries
-- never fragment — the mirror only ever serves bytes.
local MIRROR = "https://www.wuxiaspot.com"

local function siteBases()
    local pref = get_preference(PREF_SITE)
    if pref == "box" then return { SITE } end
    if pref == "spot" then return { MIRROR, SITE } end
    return { SITE, MIRROR } -- auto (default)
end


-- ── Smart mirror switcher (2.3.0) ──────────────────────────────────────────
-- A per-site health tracker (circuit breaker) that PERSISTS across engine
-- runs via set_preference, plus health-aware base ordering for every fetch.
--
--   • 2 consecutive failures (network error, 5xx, Cloudflare page,
--     error-page body) on one site → that site enters a 10-minute
--     cooldown: every subsequent fetch goes straight to the other site.
--   • Any success resets the site's health instantly.
--   • A 404 is NOT a health failure (the site answered — the page just
--     doesn't exist; e.g. the 15 unshared category slugs on the mirror).
--   • Cooldown expiry re-admits the site automatically (half-open
--     circuit: transient 502 flaps recover without user action).
--
-- The engine itself still fetches CHAPTER pages from the canonical
-- wuxiabox.com URL first (NoveLA's DownloaderRepository owns that hop —
-- it is not exposed to Lua on stock engines). When that fetch yields an
-- error page the plugin receives the body, charges the failure to the
-- primary here and refetches from the healthy/preferred site — see
-- refetchChapterWithRetry and getChapterText.
local HEALTH_PREF          = "wuxiabox_site_health"
local HEALTH_FAILS_TRIGGER = 2               -- consecutive fails → cooldown
local HEALTH_COOLDOWN_MS   = 10 * 60 * 1000  -- 10 minutes

local _health = nil

-- Load (once per engine run) + parse the persisted health state.
-- Format: "box=<fails>,<cooldownUntilMs>;spot=<fails>,<cooldownUntilMs>"
local function healthLoad()
    if _health then return _health end
    _health = {
        [SITE]   = { fails = 0, cooldownUntil = 0 },
        [MIRROR] = { fails = 0, cooldownUntil = 0 },
    }
    local tagToBase = { box = SITE, spot = MIRROR }
    local raw = get_preference(HEALTH_PREF) or ""
    for tag, fails, cd in string.gmatch(raw, "(%a+)=(%d+),(%d+)") do
        local st = tagToBase[tag] and _health[tagToBase[tag]]
        if st then
            st.fails = tonumber(fails) or 0
            st.cooldownUntil = tonumber(cd) or 0
            -- sanity clamps: never trust absurd persisted values
            if st.fails > 99 then st.fails = 0 end
            if st.cooldownUntil > os_time() + 3600000 then st.cooldownUntil = 0 end
        end
    end
    return _health
end

local function healthSave()
    if not set_preference then return end -- very old engine guard
    local h = healthLoad()
    set_preference(HEALTH_PREF,
        "box=" .. h[SITE].fails .. "," .. h[SITE].cooldownUntil ..
        ";spot=" .. h[MIRROR].fails .. "," .. h[MIRROR].cooldownUntil)
end

local function baseFailed(base)
    local st = healthLoad()[base]
    if not st then return end
    st.fails = st.fails + 1
    if st.fails >= HEALTH_FAILS_TRIGGER then
        if st.cooldownUntil == 0 then
            log_info("wuxiabox: " .. (string.match(base, "^https?://([^/]+)") or base) ..
                " failed " .. st.fails .. "x in a row — switching to the other site for " ..
                tostring(math.floor(HEALTH_COOLDOWN_MS / 60000)) .. " min")
        end
        st.cooldownUntil = os_time() + HEALTH_COOLDOWN_MS
    end
    healthSave()
end

local function baseSucceeded(base)
    local st = healthLoad()[base]
    if not st then return end
    if st.fails ~= 0 or st.cooldownUntil ~= 0 then
        st.fails = 0
        st.cooldownUntil = 0
        healthSave()
    end
end

-- True while a site is in cooldown. Checked lazily: an expired cooldown
-- is cleared on read (half-open — the site gets a fresh chance).
local function baseInCooldown(base)
    local st = healthLoad()[base]
    if not st then return false end
    if st.cooldownUntil > 0 and os_time() < st.cooldownUntil then
        return true
    end
    if st.cooldownUntil ~= 0 then
        st.cooldownUntil = 0
        healthSave()
    end
    return false
end

-- Health-aware preference order: sites in cooldown are skipped whenever
-- at least one site is eligible. If EVERY site is cooling down the plain
-- preference order is returned — a cooldown is a heuristic, not an
-- outage verdict; still try.
local function orderedBases()
    local bases = siteBases()
    local active = {}
    for _, b in ipairs(bases) do
        if not baseInCooldown(b) then active[#active + 1] = b end
    end
    if #active == 0 then return bases end
    return active
end

-- Error/interstitial-page markers — a 200 response whose body is an
-- origin 502/504 page, a Cloudflare challenge/block page or a
-- maintenance interstitial. These strings live in the <head>/<title>
-- area of such pages and never appear there on real content pages.
local JUNK_MARKERS = {
    "502 Bad Gateway",
    "504 Gateway Time-out",
    "503 Service Temporarily Unavailable",
    "<title>Just a moment",   -- Cloudflare managed challenge
    "cf-error-details",       -- Cloudflare error page container
    "error code: 50",         -- Cloudflare "error code: 502/504" pages
    "Attention Required",     -- Cloudflare block page title
    "Under Maintenance",
}

-- Marker-only check (no size floor) — for pages that are legitimately
-- small (sparse search result pages).
local function isErrorMarkerBody(body)
    if not body or body == "" then return true end
    local head = string.sub(body, 1, 4096)
    for _, m in ipairs(JUNK_MARKERS) do
        if string.find(head, m, 1, true) then return true end
    end
    return false
end

-- Full junk gate for content pages: real pages on this site are 5 KB+
-- (list pages ~39 KB, novel pages ~46 KB, fy fragments ~27 KB, even the
-- zero-result search interstitial is 1.2 KB), so a sub-350-byte body is
-- a stub/error document, not content.
local function isJunkBody(body)
    if not body or body == "" then return true end
    if #body < 350 then return true end
    return isErrorMarkerBody(body)
end

-- GET {path} on the preferred HEALTHY site, transparently failing over to
-- the other site when the request fails (network error / CF / 5xx /
-- error-page body). Returns the LAST response table plus the base that
-- served it (nil when all failed). Every attempt feeds the health tracker.
--
-- MIRROR PORTABILITY (verified live 2026-09-16): the two sites share
-- novel slugs, chapter URLs, fy.php fragments, search keywords and most
-- category slugs — but their TAG ID SPACES ARE COMPLETELY DIFFERENT
-- (wuxiabox "Rebirth" = 139, wuxiaspot "Rebirth" = 682; wuxiabox id 682
-- is "Saving the World"). A tag listing fetched from the wrong site would
-- silently browse the WRONG TAG, so tag URLs must use httpGetPrimary.
local function httpGetAny(path, headers)
    local last
    for _, base in ipairs(orderedBases()) do
        local r
        if headers then
            r = http_get(base .. path, { headers = headers })
        else
            r = http_get(base .. path)
        end
        if r and r.success and not isJunkBody(r.body) then
            baseSucceeded(base)
            return r, base
        end
        -- 200-but-junk bodies (origin 502 HTML, CF pages, maintenance
        -- interstitials) are downgraded to failures — the next site is
        -- tried and the tracker learns this one is misbehaving.
        if r then
            if r.success then r.success = false end
            if tonumber(r.code) ~= 404 then baseFailed(base) end
            last = r
        end
    end
    return last, nil
end

-- Primary-site-only GET — for URLs whose meaning is site-specific
-- (tag listings: the mirror's tag ids point at different tags; searchid
-- pages are fetched by getCatalogSearch through the search's OWN base).
-- Feeds the health tracker so a failing primary is detected once for
-- every fetch path.
local function httpGetPrimary(path, headers)
    local r
    if headers then
        r = http_get(SITE .. path, { headers = headers })
    else
        r = http_get(SITE .. path)
    end
    if r and r.success and not isJunkBody(r.body) then
        baseSucceeded(SITE)
        return r, SITE
    end
    if r then
        if r.success then r.success = false end
        if tonumber(r.code) ~= 404 then baseFailed(SITE) end
    end
    return r, nil
end

-- ── User-Agent preset ────────────────────────────────────────────────────────
-- Registered with the engine (LuaSourceAdapter.registerUAPreset): applies to
-- EVERY request of this source (tagged source:wuxiabox) and every untagged
-- request to the wuxiabox.com host — including the image loader's cover
-- fetches. One uniform, modern browser UA keeps the cf_clearance cookie the
-- Cloudflare WebView bypass bakes valid for pages AND images (clearance is
-- bound to User-Agent + IP; a mismatched image request gets challenged, and
-- .jpg URLs are exempt from the bypass ladder → broken posters).
function getUserAgentPreset()
    return "Chrome Mobile"
end

-- ── Small helpers ───────────────────────────────────────────────────────────

-- Canonicalize any site URL (both hosts → SITE; other hosts untouched)
-- so mirror-served pages can never leak wuxiaspot.com links into the
-- engine's library.
local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then
        local host = string.match(href, "^https?://([^/]+)")
        if host and (string.find(host, "wuxiabox.com", 1, true)
            or string.find(host, "wuxiaspot.com", 1, true)) then
            local path = string.match(href, "^https?://[^/]+(/.*)$")
            return SITE .. (path or "/")
        end
        return href
    end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(SITE, href)
end

-- ── Cover image proxy ────────────────────────────────────────────────────────
-- The site's covers (https://wuxiabox.com/d/file/…) sit behind the same
-- Cloudflare shield as the pages. NoveLA's image loader shares the engine's
-- OkHttp stack but .jpg URLs are EXEMPT from the Cloudflare bypass
-- (STATIC_EXTENSIONS in CloudfareVerificationInterceptor), so any challenge
-- on a cover request is handed to the image decoder as-is → broken poster.
-- wsrv.nl (images.weserv.nl) fetches server-side and is whitelisted by the
-- engine for exactly this pattern; w=450 keeps the payload small.
local COVER_PROXY = "https://wsrv.nl/?url="

local function coversViaProxy()
    local pref = get_preference(PREF_COVERS)
    return pref ~= "direct"
end

-- Wrap a site cover URL for the image loader. Non-site URLs pass through
-- untouched (already-absolute third-party covers, empty strings).
local function coverUrl(u)
    if not u or u == "" then return u end
    local site = absUrl(u)  -- canonicalize (mirror paths -> wuxiabox.com)
    if site == "" then return u end
    if not coversViaProxy() then return site end
    if not string_starts_with(site, SITE) then return site end
    return COVER_PROXY .. url_encode(site) .. "&w=450&we&output=jpg&q=80"
end

-- First value of a response header (NoveLA marshals headers as a
-- multimap: r.headers["location"] = {"https://…"}).
local function headerFirst(headers, name)
    if type(headers) ~= "table" then return nil end
    local v = headers[name] or headers[string.lower(name)]
    if type(v) == "table" then
        return (v[1] ~= nil and v[1] ~= "") and v[1] or nil
    elseif type(v) == "string" then
        return v ~= "" and v or nil
    end
    return nil
end

-- /novel/{slug}.html → "slug" ; /novel/{slug}_{n}.html → "slug"
local function novelSlug(url)
    if not url then return nil end
    return string.match(url, "/novel/([^/?#]+)%.html")
end

local function chapterToNovelUrl(chapterUrl)
    local slug = novelSlug(chapterUrl)
    if not slug then return chapterUrl end
    return SITE .. "/novel/" .. slug .. ".html"
end

-- ── Page cache (one engine run) ─────────────────────────────────────────────
-- All book-detail getters + parsePage(page 1) + getBookLastUpdate share the
-- novel page fetch through this cache (the engine calls the getters in
-- parallel). fy.php fragment fetches are cached here too. Keys are site
-- PATHS ("/novel/x.html"), so a page fetched from the mirror is cached
-- under the same canonical key the primary would use.

local _pageCache = {}

-- Canonical URL (https://www.wuxiabox.com/novel/x.html) → site path.
local function urlToPath(url)
    if not url then return nil end
    local path = string.match(url, "^https?://[^/]+(/.*)$")
    return path or url
end

local function fetchPage(url, headers)
    local path = urlToPath(url)
    if not path then return nil end
    if _pageCache[path] then return _pageCache[path] end
    local r = httpGetAny(path, headers)
    if r and r.success then
        _pageCache[path] = r.body
        return r.body
    end
    return nil
end

-- EmpireCMS AJAX fragment endpoints (fy.php) expect an XHR request.
-- Carried over from the community wuxiabox.lua v1.0.1.
local FY_HEADERS = {
    ["X-Requested-With"] = "XMLHttpRequest",
    ["Accept"]          = "text/html",
}

-- ── Request pacing ──────────────────────────────────────────────────────────
-- os_time() in NoveLA is System.currentTimeMillis() → millisecond precision.
-- A floor between chapter requests keeps sequential reading (and downloads)
-- from hammering an origin that intermittently 502s under load.

local _lastChapterTs = 0

local function chapterPacing()
    local gap = getPaceMs()
    if gap <= 0 then return end
    local now = os_time()
    local elapsed = now - _lastChapterTs
    if elapsed >= 0 and elapsed < gap then
        sleep(gap - elapsed)
    end
    _lastChapterTs = os_time()
end

-- Light pacing for multi-request browse paths (tag union, fy pages).
local _lastBrowseTs = 0

local function browsePacing(gap)
    gap = gap or 400
    local now = os_time()
    local elapsed = now - _lastBrowseTs
    if elapsed >= 0 and elapsed < gap then
        sleep(gap - elapsed)
    end
    _lastBrowseTs = os_time()
end

-- ── Error / interstitial page detection ─────────────────────────────────────
-- A real chapter page always contains #chapter-article .chapter-content.
-- Cloudflare "Just a moment…", nginx 502/504, and the site's "Maintenance"
-- interstitial do not. The engine hands exactly such bodies to
-- getChapterText when the origin flaps (the app's own retry loop only
-- retries timeout/connect errors, so a 502 page reached the plugin).

local function isChapterErrorPage(html)
    if not html or html == "" then return true end
    if html_select_first(html, "#chapter-article .chapter-content") then return false end
    if html_select_first(html, ".chapter-content") then return false end
    return true
end

-- Refetch a chapter URL with exponential backoff + jitter (2.3.0: smart
-- attempt order). orderedBases() re-evaluates per attempt, so the rescue
-- starts on the healthy/preferred site — after the engine's own failed
-- fetch of the canonical host (which getChapterText already charged to
-- the primary), the doomed primary hit is skipped, and a site that enters
-- cooldown mid-rescue hands its remaining attempts to the other one.
-- There is deliberately NO sleep before the first attempt: the engine's
-- fetch ladder (ServerErrorRetryInterceptor: 4x 502-retries with backoff)
-- already waited seconds before handing the error page over. Every
-- attempt goes through the app's OkHttp stack, so the
-- CloudfareVerification interceptor keeps working (challenges → WebView
-- bypass → retry).
local function refetchChapterWithRetry(chapterUrl)
    local attempts = getRetryCount()
    local path = urlToPath(chapterUrl) or chapterUrl
    for attempt = 1, attempts do
        if attempt > 1 then
            local waitMs = 900 * attempt * attempt + math.random(0, 400)
            sleep(waitMs)
        end
        local bases = orderedBases()
        local base = bases[1 + ((attempt - 1) % #bases)]
        local r = http_get(base .. path, {
            headers = {
                ["Referer"] = base .. "/novel/" .. (novelSlug(chapterUrl) or "") .. ".html",
                ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            }
        })
        if r and r.success and not isChapterErrorPage(r.body) then
            baseSucceeded(base)
            log_info("wuxiabox: chapter refetch succeeded on attempt " .. attempt ..
                " (" .. (string.match(base, "^https?://([^/]+)") or "?") .. "): " .. chapterUrl)
            return r.body
        end
        -- 404 = this site answered but has no such chapter — NOT a health
        -- failure (the site is up); keep the tracker clean.
        if r and tonumber(r.code) == 404 then
            log_error("wuxiabox: 404 (site healthy, chapter missing): " .. base .. path)
        else
            if r and r.success then r.success = false end
            baseFailed(base)
            log_error("wuxiabox: chapter fetch attempt " .. attempt .. "/" .. attempts ..
                " failed (code " .. tostring(r and r.code) .. "): " .. base .. path)
        end
    end
    return nil
end

-- ── Relative date normalization ("5 hours ago" → YYYY-MM-DD) ────────────────

local function normalizeUpdateDate(raw)
    if not raw or raw == "" then return nil end
    local n, unit = string.match(raw, "(%d+)%s+(%w+)%s+ago")
    if not n then return nil end
    local mult = {
        minute = 60, minutes = 60,
        hour   = 3600, hours = 3600,
        day    = 86400, days = 86400,
        week   = 7 * 86400, weeks = 7 * 86400,
        month  = 30 * 86400, months = 30 * 86400,
        year   = 365 * 86400, years = 365 * 86400,
    }
    local secs = mult[string.lower(unit)]
    if not secs then return nil end
    return os.date("%Y-%m-%d", os.time() - tonumber(n) * secs)
end

-- ── Content transforms ──────────────────────────────────────────────────────

local function applyStandardContentTransforms(text)
    if not text or text == "" then return "" end
    text = string_normalize(text)
    local domain = SITE:gsub("https?://", ""):gsub("^www%.", ""):gsub("/$", "")
    text = regex_replace(text, "(?i)" .. domain .. ".*?\\n", "")
    -- Bare branding lines ("WuxiaBox — Read …") without the domain suffix
    -- — kept from base v1.0.1 (\b so "WuxiaBoxian" story words survive).
    text = regex_replace(text, "(?im)^\\s*wuxiabox\\b[^\\n\\r]*$", "")
    -- Standalone "Chapter N …" echo lines ANYWHERE in the body (the site
    -- repeats them at split points) — kept from base v1.0.1, now also in
    -- Russian (Глава) and anchored per line.
    text = regex_replace(text, "(?im)^\\s*(Chapter|Глава)\\s+\\d+[^\\n\\r]*$", "")
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    -- Credit lines with a colon: base v1.0.1's set (incl. T/N, E/N and the
    -- Russian variants) + proofreader.
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|T/N|E/N|Перевод|Редакция)\\s*:\\s*[^\\n\\r]{0,120}(\\r?\\n|$)", "")
    -- "Read at / on / latest …" watermarks.
    text = regex_replace(text, "(?im)^\\s*Read\\s+(at|on|latest)[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
    -- Site-specific: the chapter body repeats the novel title / Author /
    -- Synopsis echo lines at the top of every chapter.
    text = regex_replace(text, "(?im)^\\s*(Author|Synopsis|P\\.?S\\.?)[:\\s][^\\n\\r]{0,160}(\\r?\\n|$)", "")
    return string_trim(text)
end

-- Strip the leading novel-title echo paragraph (the site prepends the book
-- title as the first <p> of every chapter). The real title is parsed from
-- the same page (.titles h1) so no extra request is needed.
local function stripTitleEcho(text, pageHtml)
    local h1 = html_select_first(pageHtml, ".titles h1")
    if h1 then
        local title = string_clean(h1.text)
        if title ~= "" then
            -- Compare the first text line with the title, ignoring
            -- case/spacing/punctuation ("Bengtie: A Genius's Idea" ==
            -- "bengtie a geniuss idea").
            local firstLine = text:match("^(.-)\n") or text
            local function flat(s)
                s = string.lower(s)
                s = s:gsub("[%s%p%s+]", "")
                return (s:gsub("^%s+", ""))
            end
            local a, b = flat(firstLine), flat(title)
            if a ~= "" and (a == b or string.find(b, a, 1, true) or string.find(a, b, 1, true)) then
                text = text:gsub("^[^\n]*\n?", "", 1)
            end
        end
    end
    return text
end

-- ═══════════════════════════════════════════════════════════════════════════
-- TAG SEARCH INDEX
-- One "id|Label|L" triple per line, auto-generated from the live
-- https://www.wuxiabox.com/browsetags/ pages (all letters, all pages) by
-- scripts/build_wuxiabox_tag_index.py. Labels are the site's own names;
-- where the site truncates to 10 chars, the build script expands to the
-- full spaced name when the prefix is unambiguous. L is the letter page
-- the tag lives on (pinyin letter for the site's Chinese tags: 报仇 → B).
-- Do not hand-edit — re-run the generator after refreshing the harvest.
--
-- Parsed once at plugin load into ALL_TAGS:
--   { id = "34", label = "Ancient China", lower = "ancient china",
--     flat = "ancientchina", letter = "A" }
--   flat = lowercased label with ALL whitespace removed — the match key
--   that makes the search space-insensitive.
-- ═══════════════════════════════════════════════════════════════════════════

local TAG_SEARCH_INDEX = [==[
-- BEGIN_TAG_INDEX (auto-generated — do not edit)
145|Abandoned Children|A
289|Ability Steal|A
240|Absent Parents|A
1|Abusive Characters|A
50|Academy|A
51|Accelerated Growth|A
103|Acting|A
87|Adapted to Anime|A
334|Adapted to Game|A
973|Adapted to Visual Novel|A
262|Adopted Children|A
270|Adopted Protagonist|A
433|Adultery|A
276|Adventurers|A
670|Affair|A
206|Age Progression|A
436|Age Regression|A
242|Aggressive Characters|A
52|Alchemy|A
243|Aliens|A
1024|All-Girls School|A
220|Alternate World|A
244|Amnesia|A
766|Amusement Park|A
53|Anal|A
34|Ancient China|A
149|Ancient Times|A
318|Androgynous Characters|A
471|Androids|A
369|Angels|A
120|Animal Characteristics|A
453|Animal Rearing|A
688|Anti-Magic|A
454|Anti-social Protagonist|A
36|Antihero Protagonist|A
619|Antique Shop|A
725|Apartment Life|A
295|Apathetic Protagonist|A
89|Apocalypse|A
411|Archery|A
221|Aristocracy|A
1540|Arknights|A
357|Arms Dealers|A
329|Army|A
163|Army Building|A
223|Arranged Marriage|A
55|Arrogant Characters|A
209|Artifact Crafting|A
210|Artifacts|A
91|Artificial Intelligence|A
302|Artists|A
217|Assassins|A
700|Astrologers|A
241|Autism|A
675|Automatons|A
245|Average-looking Protagonist|A
985|Award-winning Work|A
271|Awkward Protagonist|A
579|Based on a Movie|B
1118|Based on a Song|B
671|Based on a TV Show|B
1052|Based on an Anime|B
226|Basketball|B
416|Battle Academy|B
211|Battle Competition|B
190|BDSM|B
57|Beast Companions|B
8|Beastkin|B
58|Beasts|B
21|Beautiful Female Lead|B
628|Bestiality|B
40|Betrayal|B
79|Bickering Couple|B
473|Biochip|B
813|Bisexual Protagonist|B
38|Black Belly|B
171|Blackmail|B
379|Blacksmith|B
1123|Bleach|B
676|Blind Dates|B
481|Blind Protagonist|B
534|Blood Manipulation|B
9|Bloodlines|B
269|Body Swap|B
246|Body Tempering|B
980|Body-double|B
439|Bodyguards|B
337|Books|B
659|Bookworm|B
80|Boss-Subordinate Relationship|B
396|Brainwashing|B
974|Breast Fetish|B
231|Broken Engagement|B
521|Brother Complex|B
570|Brotherhood|B
1288|BTTH|B
442|Buddhism|B
134|Bullying|B
60|Business Management|B
227|Businessmen|B
763|Butlers|B
22|Calm Protagonist|C
407|Cannibalism|C
512|Card Games|C
121|Carefree Protagonist|C
122|Caring Protagonist|C
222|Cautious Protagonist|C
23|Celebrities|C
61|Character Growth|C
39|Charismatic Protagonist|C
520|Charming Protagonist|C
142|Chat Rooms|C
62|Cheats|C
260|Chefs|C
393|Child Abuse|C
491|Child Protagonist|C
81|Childcare|C
197|Childhood Friends|C
176|Childhood Love|C
588|Childhood Promise|C
123|Childish Protagonist|C
713|Chuunibyou|C
327|Clan Building|C
6438|Classic|C
92|Clever Protagonist|C
297|Clingy Lover|C
644|Clones|C
611|Clubs|C
204|Clumsy Love Interests|C
662|Co-Workers|C
152|Cohabitation|C
84|Cold Love Interests|C
10|Cold Protagonist|C
749|Collection of Short Stories|C
1454|College/University|C
105|Coma|C
154|Comedic Undertone|C
722|Coming of Age|C
253|Complex Family Relationships|C
445|Conditional Power|C
232|Confident Protagonist|C
172|Confinement|C
541|Conflicting Loyalties|C
294|Contracts|C
161|Cooking|C
408|Corruption|C
338|Cosmic Wars|C
726|Cosplay|C
153|Couple Growth|C
594|Court Official|C
683|Cousins|C
290|Cowardly Protagonist|C
374|Crafting|C
440|Crime|C
173|Criminals|C
155|Cross-dressing|C
492|Crossover|C
42|Cruel Characters|C
741|Cryostasis|C
63|Cultivation|C
164|Cunning Protagonist|C
261|Curious Protagonist|C
528|Curses|C
224|Cute Children|C
124|Cute Protagonist|C
125|Cute Story|C
3294|Cyberpunk 2077|C
380|Dancers|D
1636|Danmachi|D
417|Dao Companion|D
583|Dao Comprehension|D
444|Daoism|D
319|Dark|D
922|Dark Fantasy|D
835|DC Universe|D
723|Dead Protagonist|D
194|Death|D
64|Death of Loved Ones|D
515|Debts|D
247|Delinquents|D
640|Delusions|D
430|Demi-Humans|D
218|Demon Lord|D
1124|Demon Slayer|D
395|Demonic Cultivation Technique|D
219|Demons|D
65|Dense Protagonist|D
156|Depictions of Cruelty|D
303|Depression|D
342|Destiny|D
1347|Detective Conan|D
180|Detectives|D
165|Determined Protagonist|D
24|Devoted Love Interests|D
6330|Devouring|D
136|Different Social Status|D
1767|Digimon|D
263|Disabilities|D
504|Discrimination|D
634|Disfigurement|D
516|Dishonest Protagonist|D
542|Distrustful Protagonist|D
535|Divination|D
984|Divine Protection|D
44|Divorce|D
3199|DnD|D
25|Doctors|D
414|Domestic Affairs|D
26|Doting Love Interests|D
177|Doting Older Siblings|D
178|Doting Parents|D
326|Douluo Dalu|D
1309|Dragon Ball|D
308|Dragon Riders|D
309|Dragon Slayers|D
310|Dragons|D
494|Dreams|D
543|Drugs|D
506|Druids|D
742|Dungeon Master|D
632|Dungeons|D
311|Dwarfs|D
618|Dystopia|D
275|e-Sports|E
2|Early Romance|E
712|Earth Invasion|E
434|Easy Going Life|E
505|Economics|E
575|Editors|E
397|Eidetic Memory|E
776|Elderly Protagonist|E
398|Elemental Magic|E
354|Elves|E
381|Emotionally Weak Protagonist|E
437|Empires|E
655|Engagement|E
697|Engineer|E
577|Enlightenment|E
157|Episodic|E
343|Eunuch|E
457|European Ambience|E
333|Evil Gods|E
66|Evil Organizations|E
382|Evil Protagonist|E
529|Evil Religions|E
339|Evolution|E
1036|Exhibitionism|E
468|Exorcism|E
351|Eye Powers|E
584|Fairies|F
1023|Fairy Tail|F
596|Fallen Angels|F
524|Fallen Nobility|F
291|Familial Love|F
780|Familiars|F
148|Family|F
459|Family Business|F
248|Family Conflict|F
627|Famous Parents|F
383|Famous Protagonist|F
710|Fanaticism|F
362|Fantasy Creatures|F
277|Fantasy World|F
229|Farming|F
67|Fast Cultivation|F
68|Fast Learner|F
358|Fat Protagonist|F
359|Fat to Fit|F
272|Fated Lovers|F
639|Fearless Protagonist|F
629|Fellatio|F
557|Female Master|F
18|Female Protagonist|F
734|Female to Male|F
581|Feng Shui|F
166|Firearms|F
207|First Love|F
192|First-time Intercourse|F
135|Flashbacks|F
745|Fleet Battles|F
623|Folklore|F
352|Football|F
110|Forced into a Relationship|F
317|Forced Living Arrangements|F
111|Forced Marriage|F
384|Forgetful Protagonist|F
478|Former Hero|F
256|Fox Spirits|F
737|Friends Become Enemies|F
421|Friendship|F
69|Fujoshi|F
193|Futanari|F
126|Futuristic Setting|F
1109|Galge|G
661|Gambling|G
70|Game Elements|G
3422|Game of Thrones|G
392|Game Ranking System|G
170|Gamers|G
321|Gangs|G
5673|Gao Wu|G
214|Gate to Another World|G
609|Genderless Protagonist|G
233|Generals|G
312|Genetic Modifications|G
215|Genies|G
216|Genius Protagonist|G
1321|Genshin Impact|G
158|Ghosts|G
981|Gladiators|G
616|Goblins|G
298|God Protagonist|G
668|God-human Relationship|G
278|Goddesses|G
356|Godly Powers|G
234|Gods|G
778|Golems|G
94|Gore|G
1016|Grave Keepers|G
544|Grinding|G
264|Guardian Relationship|G
631|Guilds|G
95|Gunfighters|G
367|Hackers|H
265|Half-human Protagonist|H
699|Handjob|H
11|Handsome Male Lead|H
127|Hard-Working Protagonist|H
37|Harem-seeking Protagonist|H
237|Harry Potter|H
625|Harsh Training|H
112|Hated Protagonist|H
566|Healers|H
106|Heartwarming|H
582|Heaven|H
128|Heavenly Tribulation|H
651|Hell|H
612|Helpful Protagonist|H
779|Herbalist|H
536|Heroes|H
969|Heterochromia|H
259|Hidden Abilities|H
1039|Highschool DxD|H
1196|Hollywood|H
648|Honest Protagonist|H
5779|HongHuangB|H
2516|HonghuangN|H
4496|HonghuangS|H
5286|HongHuangz|H
6483|Hongmeng|H
636|Hospital|H
300|Hot-blooded Protagonist|H
413|Human Experimentation|H
490|Human Weapon|H
159|Human-Nonhuman Relationship|H
129|Humanoid Protagonist|H
1338|Hunter x Hunter|H
531|Hunters|H
377|Hypnotism|H
344|Identity Crisis|I
1077|Immortal|I
235|Immortals|I
238|Imperial Harem|I
179|Incest|I
1019|Incubus|I
568|Indecisive Protagonist|I
641|Industrialization|I
431|Inferiority Complex|I
426|Inheritance|I
744|Inscriptions|I
313|Insects|I
1745|Interconnected Storylines|I
27|Interdimensional Travel|I
680|Introverted Protagonist|I
496|Investigations|I
6217|Invisibility|I
71|Jack of All Trades|J
258|Jealousy|J
603|Jiangshi|J
2882|JoJo’s Bizarre Adventure|J
1326|Journey to the West|J
1127|Jujutsu Kaisen|J
509|Kidnappings|K
131|Kind Love Interests|K
340|Kingdom Building|K
181|Kingdoms|K
208|Knights|K
708|Kuudere|K
160|Lack of Common Sense|L
133|Language Barrier|L
249|Late Romance|L
548|Lawyers|L
441|Lazy Protagonist|L
375|Leadership|L
849|League of Legends|L
607|Legends|L
201|Level System|L
773|Library|L
1721|Life Script|L
470|Limited Lifespan|L
883|Live Streaming|L
474|Living Alone|L
576|Loli|L
6211|Loneliness|L
585|Loner Protagonist|L
412|Long Separations|L
273|Long-distance Relationship|L
895|Lord of the Mysteries|L
330|Lost Civilizations|L
573|Lottery|L
168|Love at First Sight|L
19|Love Interest Falls in Love First|L
610|Love Rivals|L
485|Love Triangles|L
502|Lovers Reunited|L
328|Low-key Protagonist|L
507|Loyal Subordinates|L
368|Lucky Protagonist|L
182|Magic|M
314|Magic Beasts|M
72|Magic Formations|M
1744|Magical Girls|M
73|Magical Space|M
608|Magical Technology|M
649|Maids|M
12|Male Protagonist|M
480|Male to Female|M
28|Male Yandere|M
642|Management|M
809|Mangaka|M
597|Manipulative Characters|M
96|Manly Gay Couple|M
85|Marriage|M
489|Marriage of Convenience|M
394|Martial Spirits|M
537|Marvel|M
45|Masochistic Characters|M
304|Master-Disciple Relationship|M
361|Master-Servant Relationship|M
733|Masturbation|M
686|Matriarchy|M
97|Mature Protagonist|M
299|Medical Knowledge|M
429|Medieval|M
167|Mercenaries|M
527|Merchants|M
86|Military|M
621|Mind Break|M
389|Mind Control|M
6246|Minecraft|M
1343|Mismatched Couple|M
113|Misunderstandings|M
202|MMORPG|M
443|Mob Protagonist|M
657|Models|M
3|Modern Day|M
307|Modern Knowledge|M
82|Money Grubber|M
569|Monster Girls|M
1151|Monster Society|M
74|Monster Tamer|M
230|Monsters|M
3150|Mortal Flow|M
292|Movies|M
257|Mpreg|M
387|Multiple Identities|M
20|Multiple Personalities|M
279|Multiple POV|M
501|Multiple Protagonists|M
615|Multiple Timelines|M
293|Multiple Transported Individuals|M
345|Murders|M
186|Music|M
320|Mutated Creatures|M
418|Mutations|M
736|Mute Character|M
185|Mystery Solving|M
427|Mythical Beasts|M
484|Mythology|M
75|Naive Protagonist|N
469|Narcissistic Protagonist|N
335|Naruto|N
305|Nationalism|N
76|Near-Death Experience|N
422|Necromancer|N
645|Neet|N
77|Netorare|N
78|Netori|N
346|Nightmares|N
460|Ninjas|N
280|Nobles|N
143|Non-humanoid Protagonist|N
6212|Non-linear Storytelling|N
972|Nudity|N
637|Nurses|N
205|Obsessive Love|O
517|Office Romance|O
364|Older Love Interests|O
301|Omegaverse|O
336|One Piece|O
1063|One Punch Man|O
638|Online Romance|O
720|Orcs|O
174|Organized Crime|O
428|Orphans|O
472|Otaku|O
1580|Otome Game|O
991|Outcasts|O
409|Outer Space|O
1184|Overlord|O
41|Overpowered Protagonist|O
717|Overprotective Siblings|O
1186|Pacifist Protagonist|P
752|Paizuri|P
458|Parallel Worlds|P
331|Parasites|P
650|Parent Complex|P
620|Parody|P
268|Part-Time Job|P
98|Past Plays a Big Role|P
114|Past Trauma|P
274|Persistent Love Interests|P
137|Personality Changes|P
281|Perverted Protagonist|P
107|Pets|P
689|Pharmacist|P
774|Philosophical|P
236|Phoenixes|P
705|Photography|P
399|Pill Based Cultivation|P
400|Pill Concocting|P
1592|Pilots|P
546|Pirates|P
653|Playboys|P
714|Playful Protagonist|P
731|Poetry|P
370|Poisons|P
587|Pokemon|P
419|Police|P
684|Polite Protagonist|P
43|Politics|P
669|Polyandry|P
282|Polygamy|P
522|Poor Protagonist|P
132|Poor to Rich|P
592|Popular Love Interests|P
605|Possession|P
4|Possessive Characters|P
401|Post-apocalyptic|P
47|Power Couple|P
690|Power Struggle|P
593|Pragmatic Protagonist|P
724|Precognition|P
83|Pregnancy|P
250|Pretend Lovers|P
138|Previous Life Talent|P
1059|Priestesses|P
707|Priests|P
560|Prison|P
423|Proactive Protagonist|P
704|Programmer|P
718|Prophecies|P
447|Prostitutes|P
715|Psychic Powers|P
498|Psychopaths|P
4301|Puppeteers|P
719|Quiet Characters|Q
198|Quirky Characters|Q
646|R-15|R
5058|R18|R
604|Race Change|R
13|Racism|R
402|Rape|R
6|Rape Victim Becomes Lover|R
6417|Reality-Game Fusion|R
757|Rebellion|R
139|Rebirth|R
831|Reborn|R
3835|Regression|R
706|Religions|R
545|Reporters|R
2887|Resident Evil|R
635|Restaurant|R
390|Resurrection|R
695|Returning from Another World|R
225|Revenge|R
378|Reverse Harem|R
571|Reverse Rape|R
740|Reversible Couple|R
743|Rich to Poor|R
630|Righteous Protagonist|R
687|Rivalry|R
768|Romance|R
14|Romantic Subplot|R
772|Roommates|R
35|Royalty|R
15|Ruthless Protagonist|R
622|Sadistic Characters|S
598|Saints|S
1025|Samurai|S
682|Saving the World|S
405|Schemes And Conspiracies|S
486|Scientists|S
284|Sealed Power|S
99|Second Chance|S
266|Secret Crush|S
285|Secret Identity|S
652|Secret Organizations|S
1021|Secret Relationship|S
552|Secretive Protagonist|S
286|Secrets|S
692|Sect Development|S
732|Seduction|S
633|Seeing Things Other Humans Can't|S
254|Selfish Protagonist|S
558|Selfless Protagonist|S
500|Seme Protagonist|S
970|Sentient Objects|S
771|Sentimental Protagonist|S
550|Serial Killers|S
665|Servants|S
691|Seven Deadly Sins|S
475|Sex Slaves|S
175|Sexual Abuse|S
748|Sexual Cultivation Technique|S
203|Shameless Protagonist|S
267|Shapeshifters|S
296|Sharp-tongued Characters|S
559|Short Story|S
493|Shota|S
595|Shoujo-Ai Subplot|S
530|Shounen-Ai Subplot|S
108|Showbiz|S
482|Shy Characters|S
46|Sibling Rivalry|S
48|Siblings|S
448|Siblings Not Related by Blood|S
600|Sickly Characters|S
934|Sign-in|S
1172|Simulator|S
187|Singers|S
6340|Single Female Lead|S
503|Single Parent|S
709|Sister Complex|S
403|Skill Assimilation|S
508|Skill Books|S
572|Skill Creation|S
730|Slave Harem|S
540|Slave Protagonist|S
287|Slaves|S
487|Slow Growth at Start|S
144|Slow Romance|S
513|Smart Couple|S
755|Social Outcasts|S
455|Soldiers|S
404|Soul Power|S
449|Souls|S
721|Spatial Manipulation|S
578|Spear Wielder|S
347|Special Abilities|S
251|Spies|S
654|Spirit Advisor|S
450|Spirit Users|S
555|Spirits|S
2884|Stand User|S
1302|Star Wars|S
896|Steampunk|S
188|Stockholm Syndrome|S
729|Stoic Characters|S
322|Store Owner|S
643|Straight Seme|S
438|Straight Uke|S
150|Strategic Battles|S
451|Strategist|S
371|Strength-based Social Hierarchy|S
30|Strong Love Interests|S
118|Strong to Stronger|S
565|Stubborn Protagonist|S
365|Student-Teacher Relationship|S
681|Succubus|S
551|Sudden Strength Gain|S
660|Sudden Wealth|S
775|Suicides|S
602|Summoned Hero|S
315|Summoning Magic|S
100|Survival|S
514|Survival Game|S
1339|Swallowed Star|S
288|Sword And Magic|S
325|Sword Wielder|S
119|System|S
252|Teachers|T
101|Teamwork|T
488|Technological Gap|T
1020|Tentacles|T
658|Terminal Illness|T
1725|Territory Management|T
767|Terrorists|T
420|Thieves|T
1356|Three Kingdoms|T
1042|Threesome|T
476|Thriller|T
702|Time Loop|T
672|Time Manipulation|T
777|Time Paradox|T
410|Time Skip|T
199|Time Travel|T
463|Timid Protagonist|T
466|Tomboyish Female Lead|T
728|Torture|T
140|Tragic Past|T
109|Transformation Ability|T
32|Transmigration|T
525|Transplanted Memories|T
348|Trap|T
465|Tribal Society|T
452|Trickster|T
349|Tsundere|T
196|Twins|T
499|Twisted Personality|T
739|Ugly Protagonist|U
483|Ugly to Beautiful|U
141|Unconditional Love|U
4345|Undead Protagonist|U
580|Underestimated Protagonist|U
323|Unique Cultivation Technique|U
1530|Unlimited Flow|U
432|Unlucky Protagonist|U
456|Unreliable Narrator|U
561|Unrequited Love|U
16|Vampires|V
1222|Versatile Mage|V
538|Villainess Noble Girls|V
93|Virtual Reality|V
549|Voice Actors|V
1187|War Records|W
6207|Warhammer|W
151|Wars|W
477|Weak Protagonist|W
17|Weak to Strong|W
7|Wealthy Characters|W
765|Werebeasts|W
562|Wishes|W
647|Witches|W
316|Wizards|W
33|World Hopping|W
332|World Travel|W
679|World Tree|W
406|Writers|W
510|Yandere|Y
747|Younger Brothers|Y
769|Younger Love Interests|Y
563|Younger Sisters|Y
1085|Yu-Gi-Oh!|Y
102|Zombies|Z
-- END_TAG_INDEX
]==]

local ALL_TAGS = {}
local TAGS_BY_ID = {}
do
    local seen = {}
    for line in TAG_SEARCH_INDEX:gmatch("[^\r\n]+") do
        if string.sub(line, 1, 2) ~= "--" then
            local id, label, letter = string.match(line, "^([^|]+)|([^|]+)|([^|]*)$")
            if not id then
                id, label = string.match(line, "^([^|]+)|([^|]+)$")
            end
            if id and label and not seen[id] then
                seen[id] = true
                local lower = string.lower(label)
                if not letter or letter == "" then
                    letter = string.upper(string.sub(label, 1, 1))
                end
                local tag = {
                    id     = id,
                    label  = label,
                    lower  = lower,
                    flat   = lower:gsub("%s+", ""),
                    letter = letter,
                }
                ALL_TAGS[#ALL_TAGS + 1] = tag
                TAGS_BY_ID[id] = tag
            end
        end
    end
end

-- Resolve tag picks / free text into a deduplicated list of tag ids.
-- Since 2.2.0 the index is the CURATED 755-tag set (wtr-lab taxonomy
-- cross-reference + Popular Tags + the Honghuang family) — everything a
-- novel on this site is actually tagged with; the 6,723-entry dump is gone.
-- Semantics (mirrors the site's own tag browsing + the wtrlab tag search):
--   • Tokens are split on comma / semicolon; spaces stay INSIDE tokens so
--     multi-word phrases work ("weak to strong" == "weaktostrong").
--   • Per token, resolution order:
--       1. exact name match, case- AND space-insensitive ("male prot" →
--          MaleProtagonist); several site tags share a squashed name —
--          every exact match is included;
--       2. numeric token — a verbatim tag id (validated);
--       3. "keyword*" wildcard — includes ALL substring matches at once;
--       4. ANY substring match — a partial keyword INCLUDES every tag
--          containing it: the search "shows everything as a result";
--       5. multi-word token with no phrase match → per-word fallback.
--   • A token with no match at all raises a clear error.
--   • letter: ""/"all"/nil = all letters, else a single "A".."Z" — scopes
--     the whole resolution (mirrors the /browsetags/ letter grouping).
local MAX_UNION_TAGS = 12

function tagSearchResolve(text, letter)
    if not text or text == "" then return {} end
    local scopeAll = (not letter) or letter == "" or string.lower(letter) == "all"
    local scopeLetter = nil
    if not scopeAll then scopeLetter = string.upper(letter) end

    local seen, out = {}, {}

    local function scoped(t)
        return (scopeLetter == nil) or t.letter == scopeLetter
    end

    -- every tag whose flattened name contains `flatToken` (plain substring)
    local function substringMatches(flatToken)
        local matches = {}
        for _, t in ipairs(ALL_TAGS) do
            if scoped(t) and string.find(t.flat, flatToken, 1, true) then
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

    local function resolveToken(token)
        local lowerToken = string.lower(token)
        local flatToken  = lowerToken:gsub("%s+", "")

        -- 1) exact (space-insensitive) name match
        local exact = {}
        for _, t in ipairs(ALL_TAGS) do
            if scoped(t) and t.flat == flatToken then exact[#exact + 1] = t end
        end
        if #exact > 0 then
            for _, t in ipairs(exact) do addTag(t) end
            return
        end

        -- 2) verbatim numeric tag id
        if string.match(token, "^%d+$") then
            local t = TAGS_BY_ID[token]
            if t then
                if scoped(t) then addTag(t) return end
                error("tag id " .. token .. " does not start with letter " .. tostring(scopeLetter) .. ".")
            end
            error("no tag with id " .. token .. " on wuxiabox.com.")
        end

        -- 3) trailing-* wildcard: every substring match at once
        if string.sub(token, -1) == "*" then
            local stem = flatToken:sub(1, -2)
            if stem == "" then return end
            local matches = substringMatches(stem)
            if #matches == 0 then
                error("no tag name contains '" .. stem .. "'." ..
                    (scopeLetter ~= nil and (" (scoped to letter " .. scopeLetter .. ")") or ""))
            end
            for _, t in ipairs(matches) do addTag(t) end
            return
        end

        -- 4) substring: INCLUDE EVERY MATCH
        local matches = substringMatches(flatToken)
        if #matches > 0 then
            for _, t in ipairs(matches) do addTag(t) end
            return
        end

        -- 5) multi-word fallback: resolve word by word
        if string.find(token, "%s") then
            for word in token:gmatch("%S+") do resolveToken(word) end
            return
        end

        error("no tag name contains '" .. token .. "'." ..
            (scopeLetter ~= nil and (" (scoped to letter " .. scopeLetter .. ")") or ""))
    end

    for token in string.gmatch(text, "[^,;]+") do
        token = string.gsub(token, "^%s+", "")
        token = string.gsub(token, "%s+$", "")
        if token ~= "" then resolveToken(token) end
    end

    if #out > MAX_UNION_TAGS then
        local names = {}
        for _, id in ipairs(out) do
            names[#names + 1] = TAGS_BY_ID[id] and TAGS_BY_ID[id].label or id
        end
        error("Tag Search matched " .. #out .. " tags (" ..
            table.concat(names, ", ", 1, MAX_UNION_TAGS) .. ", …). " ..
            "wuxiabox.com browses ONE tag listing at a time, so the plugin merges " ..
            "them into " .. #out .. " parallel requests per result page — too many. " ..
            "Type a more specific keyword or an exact tag name.")
    end

    return out
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CATALOG / SEARCH / FILTERS
-- ═══════════════════════════════════════════════════════════════════════════

-- Parse .novel-item cards — shared by catalog list, tag listings, search
-- results and the updates page. Card anatomy (verified live):
--   <li class="novel-item"><a href="/novel/{slug}.html" title="{Title}">
--     … img.lazy[data-src] … <h4 class="novel-title">{Title}</h4> …
-- `toNovelUrl` rewrites the updates-page variant (links point at the
-- LATEST CHAPTER, /novel/{slug}_{n}.html) back to the novel page.
local function parseNovelCards(body, toNovelUrl)
    local items = {}
    local seen = {}
    for _, card in ipairs(html_select(body, "li.novel-item")) do
        local a = html_select_first(card.html, "a[href]")
        if a then
            local url = absUrl(a.href)
            if toNovelUrl then
                url = string.gsub(url, "_(%d+)%.html$", ".html")
            end
            local title = string_clean(a.title)
            if title == "" then
                local t = html_select_first(card.html, "h4.novel-title, h5.novel-title")
                if t then title = string_clean(t.text) end
            end
            if url ~= "" and title ~= "" and not seen[url] then
                seen[url] = true
                local cover = html_attr(card.html, "img[data-src]", "data-src")
                if cover == "" then cover = html_attr(card.html, "img[src]", "src") end
                items[#items + 1] = { title = title, url = url, cover = coverUrl(cover) }
            end
        end
    end
    return items
end

-- hasNext via "link to the NEXT page exists in the pager" — the generic
-- scheme for every listing on this site (numbered pages + > / >> links).
-- needle is the literal URL fragment identifying the next page.
-- listTotal: when the pager carries a grand-total marker
-- (<ul class="pagination"><a title="总数"><b>N</b>), a page-full math
-- fallback covers pagers whose link format shifts.
local function hasNextByLink(body, needle)
    if string.find(body, needle, 1, true) then return true end
    return false
end

local function listTotal(body)
    -- v2.1.0 bug: the pattern anchored on <ul class="pagination">, but the
    -- site puts a NEWLINE between it and the 总数 marker, and Lua's `.-`
    -- cannot cross newlines — the total was NEVER extracted, so the
    -- total-based hasNext fallback was dead code. Anchor on the 总数 title
    -- marker itself (the whole marker sits on one line).
    return tonumber(string.match(body, '总数[^<]-<b>(%d+)</b>'))
        or tonumber(string.match(body, '<ul class="pagination">%s*<a[^>]*>[^<]-<b>(%d+)</b>'))
end

-- ── Catalog (default browse: Most Popular) ──────────────────────────────────

function getCatalogList(index)
    local page = index
    local path = "/list/all/all-onclick-" .. tostring(page) .. ".html"
    local r = httpGetAny(path)
    if not r or not r.success then return { items = {}, hasNext = false } end
    local items = parseNovelCards(r.body, false)
    local hasNext = hasNextByLink(r.body, "/list/all/all-onclick-" .. tostring(page + 1) .. ".html")
    return { items = items, hasNext = hasNext }
end

-- ── Search (EmpireCMS POST form + manual redirect following) ────────────────

-- searchid cache per query for the lifetime of one engine run
local _searchIdByQuery = {}

local function extractSearchId(body)
    return string.match(body, "searchid=(%d+)")
end

-- A result page counts as "has results" when it carries novel cards OR
-- a searchid (in pager links). THE 2.0.0 BUG: single-hit searches return
-- a page WITHOUT a pager — and the site only puts "searchid=" into pager
-- links — so the old searchid-only gate discarded those perfectly good
-- pages and pasted-title searches showed NOTHING (verified live: an
-- exact-title query returns one novel-item, zero searchid occurrences).
local function hasSearchResults(body)
    if not body or body == "" then return false end
    if extractSearchId(body) then return true end
    return html_select_first(body, "li.novel-item") ~= nil
end

-- Follow up to 3 manual redirect hops (NoveLA's OkHttp client does not
-- follow redirects for plugin calls by default). `base` is the site the
-- request went to — a relative Location resolves against THAT site.
local function followRedirects(r, base)
    base = base or SITE
    local hops = 0
    while hops < 3 do
        local code = tonumber(r.code) or 0
        if code ~= 301 and code ~= 302 and code ~= 303 and code ~= 307 and code ~= 308 then
            return r
        end
        local loc = headerFirst(r.headers, "location")
        if not loc then return r end
        local target
        if string_starts_with(loc, "http") then
            target = loc
        else
            target = url_resolve(base, loc)
        end
        r = http_get(target)
        hops = hops + 1
    end
    return r
end

-- POST the site's own search form; on failure fall back to the GET
-- searchget=1 variant. Returns the RESULT page body (or nil when the
-- site could not be reached / served no usable page at all).
local function runSearchOn(base, query)
    local form = "show=title&tempid=1&tbname=news&keyboard=" .. url_encode(query)
    local r = http_post(base .. "/e/search/index.php", form, {
        headers = {
            ["Referer"] = base .. "/search.html",
            ["Origin"]  = base,
            ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        }
    })
    r = followRedirects(r, base)
    if r.success and hasSearchResults(r.body) then return r.body end

    -- Fallback: EmpireCMS GET search (verified live: redirects to the
    -- same /e/search/result?searchid=N page).
    local getUrl = base .. "/e/search/?searchget=1&keyboard=" .. url_encode(query) ..
        "&show=title&tbname=news&tempid=1"
    local g = http_get(getUrl, { headers = { ["Referer"] = base .. "/search.html" } })
    g = followRedirects(g, base)
    if g.success and hasSearchResults(g.body) then return g.body end

    -- Both requests reached the server but found nothing: a definitive
    -- zero-result page still counts as "searched" (do NOT fall through
    -- to the mirror — it serves the same index). Prefer the POST body.
    if r.success then return r.body end
    if g.success then return g.body end
    return nil
end

-- searchid pages are site-specific (an id created by wuxiabox.com's
-- search table is meaningless on the mirror), so each running search
-- remembers WHICH base created its searchid — later pages of that query
-- are fetched from the SAME base (2.3.0: a search that started on the
-- mirror now paginates on the mirror instead of dying on the primary).
local _searchBaseByQuery = {}

local function runSearch(query)
    query = string_trim(query or "")
    if query == "" then return nil end
    for _, base in ipairs(orderedBases()) do
        local body = runSearchOn(base, query)
        if body then
            _searchBaseByQuery[query] = base
            baseSucceeded(base)
            return body
        end
        baseFailed(base)
    end
    return nil
end

-- EmpireCMS search pager is 0-BASED: first page has no page= param, the
-- link labelled "2" points at page=1, ">>" (last) at page=last. The app
-- index is also 0-based, so app index N maps to URL page=N directly.
-- Each fetched page re-extracts the searchid from its OWN pager links
-- (self-healing: pagination survives a fresh engine run mid-scroll).
local function searchHasNext(body, nextIndex, sid)
    -- link-based: next page link in either param order
    if hasNextByLink(body, "page=" .. tostring(nextIndex) .. "&searchid=") then
        return true
    end
    if sid and hasNextByLink(body, "searchid=" .. sid .. "&page=" .. tostring(nextIndex)) then
        return true
    end
    -- total-based fallback: 总数 marker x 20 per page
    local total = listTotal(body)
    if total and nextIndex * 20 < total then return true end
    return false
end

function getCatalogSearch(index, query)
    if index == 0 then
        local body = runSearch(query)
        if not body then
            show_error("WuxiaBox search failed",
                "Neither wuxiabox.com nor the wuxiaspot.com mirror could be " ..
                "reached for the search. If a Cloudflare check appeared, solve " ..
                "it and try again.")
            return { items = {}, hasNext = false }
        end
        local sid = extractSearchId(body)
        _searchIdByQuery[query] = sid
        local items = parseNovelCards(body, false)
        local hasNext = searchHasNext(body, 1, sid)
        return { items = items, hasNext = hasNext }
    end

    local sid = _searchIdByQuery[query]
    if not sid then
        -- engine asked for a later page without page 0 in this run
        local body = runSearch(query)
        if not body then return { items = {}, hasNext = false } end
        sid = extractSearchId(body)
        _searchIdByQuery[query] = sid
    end
    if not sid then return { items = {}, hasNext = false } end

    -- THE SEARCHID'S OWN BASE serves the page (2.3.0). A searchid is an
    -- entry in ONE site's EmpireCMS search table — the other site's
    -- searchid space is completely different, so a page fetched from the
    -- wrong site would serve an unrelated (or empty) result and silently
    -- kill pagination (the app treats an empty page as "no more
    -- results"). runSearch() records which base created the id; a fresh
    -- engine run re-runs the search (self-healing), which re-records it.
    local base = _searchBaseByQuery[query] or SITE
    local function searchPageOK(r)
        return r ~= nil and r.success and not isErrorMarkerBody(r.body)
    end
    local function searchPageUrl(b, sidVal)
        return b .. "/e/search/result/index.php?page=" ..
            tostring(index) .. "&searchid=" .. sidVal
    end
    local r = http_get(searchPageUrl(base, sid))
    if searchPageOK(r) then
        baseSucceeded(base)
    else
        if r and r.success then r.success = false end
        if r and tonumber(r.code) ~= 404 then baseFailed(base) end
        -- one retry with a FRESH search (new searchid on the healthy
        -- site — orderedBases already skips a cooling one) before giving up
        local body = runSearch(query)
        if body then
            local freshSid = extractSearchId(body)
            if freshSid then
                _searchIdByQuery[query] = freshSid
                local freshBase = _searchBaseByQuery[query] or base
                local r2 = http_get(searchPageUrl(freshBase, freshSid))
                if searchPageOK(r2) then
                    baseSucceeded(freshBase)
                    local it = parseNovelCards(r2.body, false)
                    return { items = it, hasNext = searchHasNext(r2.body, index + 1, freshSid) }
                end
                if r2 and r2.success then r2.success = false end
                if r2 and tonumber(r2.code) ~= 404 then baseFailed(freshBase) end
            end
        end
        -- surface as a RETRYABLE app error (the reader keeps loaded pages;
        -- retry re-runs this index) instead of silently ending pagination
        error("WuxiaBox: search page " .. (index + 1) .. " could not be loaded " ..
            "from " .. (string.match(base, "^https?://([^/]+)") or "the site") ..
            ". If a Cloudflare check appeared, solve it and tap retry.")
    end
    -- refresh the cached searchid from THIS page's own pager (self-healing)
    local freshSid = extractSearchId(r.body)
    if freshSid and freshSid ~= sid then
        _searchIdByQuery[query] = freshSid
        sid = freshSid
    end
    local items = parseNovelCards(r.body, false)
    local hasNext = searchHasNext(r.body, index + 1, sid)
    return { items = items, hasNext = hasNext }
end

-- ── Filters ─────────────────────────────────────────────────────────────────

local CATEGORIES = {
    { value = "all",                  label = "All" },
    { value = "action",               label = "Action" },
    { value = "adventure",            label = "Adventure" },
    { value = "chinese",              label = "Chinese" },
    { value = "comedy",               label = "Comedy" },
    { value = "contemporary-romance", label = "Contemporary Romance" },
    { value = "drama",                label = "Drama" },
    { value = "eastern-fantasy",      label = "Eastern Fantasy" },
    { value = "erciyuan",             label = "Erciyuan" },
    { value = "faloo",                label = "Faloo" },
    { value = "fan-fiction",          label = "Fan-Fiction" },
    { value = "fantasy",              label = "Fantasy" },
    { value = "fantasy-romance",      label = "Fantasy Romance" },
    { value = "game",                 label = "Game" },
    { value = "gender-bender",        label = "Gender Bender" },
    { value = "harem",                label = "Harem" },
    { value = "hentai",               label = "Hentai" },
    { value = "historical",           label = "Historical" },
    { value = "horror",               label = "Horror" },
    { value = "isekai",               label = "Isekai" },
    { value = "japanese",             label = "Japanese" },
    { value = "josei",                label = "Josei" },
    { value = "lolicon",              label = "Lolicon" },
    { value = "magic",                label = "Magic" },
    { value = "magical-realism",      label = "Magical Realism" },
    { value = "martial-arts",         label = "Martial Arts" },
    { value = "mecha",                label = "Mecha" },
    { value = "military",             label = "Military" },
    { value = "mystery",              label = "Mystery" },
    { value = "official_circles",     label = "Official Circles" },
    { value = "psychological",        label = "Psychological" },
    { value = "romance",              label = "Romance" },
    { value = "school-life",          label = "School Life" },
    { value = "sci-fi",               label = "Sci-fi" },
    { value = "science_fiction",      label = "Science Fiction" },
    { value = "seinen",               label = "Seinen" },
    { value = "shoujo",               label = "Shoujo" },
    { value = "shoujo-ai",            label = "Shoujo Ai" },
    { value = "shounen",              label = "Shounen" },
    { value = "shounen-ai",           label = "Shounen Ai" },
    { value = "slice-of-life",        label = "Slice of Life" },
    { value = "sports",               label = "Sports" },
    { value = "supernatural",         label = "Supernatural" },
    { value = "suspense_thriller",    label = "Suspense Thriller" },
    { value = "tragedy",              label = "Tragedy" },
    { value = "travel_through_time",  label = "Travel Through Time" },
    { value = "two-dimensional",      label = "Two-dimensional" },
    { value = "urban",                label = "Urban" },
    { value = "urban-life",           label = "Urban Life" },
    { value = "video-games",          label = "Video Games" },
    { value = "virtual-reality",      label = "Virtual Reality" },
    { value = "wuxia",                label = "Wuxia" },
    { value = "wuxia_xianxia",        label = "Wuxia Xianxia" },
    { value = "xianxia",              label = "Xianxia" },
    { value = "xuanhuan",             label = "Xuanhuan" },
    { value = "yaoi",                 label = "Yaoi" },
    { value = "yuri",                 label = "Yuri" },
}

-- Popular Tags — the famous tropes as multi-select chips (2.1.0,
-- replacing the A-Z letter scoper). Values go through tagSearchResolve:
-- numeric ids resolve to exactly that tag; the one keyword value
-- ("honghuang") deliberately expands to the WHOLE truncated Honghuang*
-- family (the site has no plain "Honghuang" tag). The platform marshals
-- selections as filters["popular_tags_included"] = { value, … }.
--
-- IDs are the CANONICAL duplicate of each name — the one the site's own
-- novel pages link to (verified: novel pages use MaleProtagonist→12,
-- AncientChina→34, Farming→229, Transmigration→32). 392 tag names on
-- this site exist under several ids ("Male Protagonist": 12, 2900, 965,
-- 1287, 1261, 1079); the LOWEST id is the original listing the novel
-- pages reference. The free-text Tag Search still includes every
-- duplicate — the picker pins the canonical one to keep one request per
-- chip and predictable union sizes.
local TAG_FILTER_OPTIONS = {
    { value = "145", label = "Abandoned Children" },
    { value = "289", label = "Ability Steal" },
    { value = "240", label = "Absent Parents" },
    { value = "1", label = "Abusive Characters" },
    { value = "50", label = "Academy" },
    { value = "51", label = "Accelerated Growth" },
    { value = "103", label = "Acting" },
    { value = "87", label = "Adapted to Anime" },
    { value = "334", label = "Adapted to Game" },
    { value = "973", label = "Adapted to Visual Novel" },
    { value = "262", label = "Adopted Children" },
    { value = "270", label = "Adopted Protagonist" },
    { value = "433", label = "Adultery" },
    { value = "276", label = "Adventurers" },
    { value = "670", label = "Affair" },
    { value = "206", label = "Age Progression" },
    { value = "436", label = "Age Regression" },
    { value = "242", label = "Aggressive Characters" },
    { value = "52", label = "Alchemy" },
    { value = "243", label = "Aliens" },
    { value = "1024", label = "All-Girls School" },
    { value = "220", label = "Alternate World" },
    { value = "244", label = "Amnesia" },
    { value = "766", label = "Amusement Park" },
    { value = "53", label = "Anal" },
    { value = "34", label = "Ancient China" },
    { value = "149", label = "Ancient Times" },
    { value = "318", label = "Androgynous Characters" },
    { value = "471", label = "Androids" },
    { value = "369", label = "Angels" },
    { value = "120", label = "Animal Characteristics" },
    { value = "453", label = "Animal Rearing" },
    { value = "688", label = "Anti-Magic" },
    { value = "454", label = "Anti-social Protagonist" },
    { value = "36", label = "Antihero Protagonist" },
    { value = "619", label = "Antique Shop" },
    { value = "725", label = "Apartment Life" },
    { value = "295", label = "Apathetic Protagonist" },
    { value = "89", label = "Apocalypse" },
    { value = "411", label = "Archery" },
    { value = "221", label = "Aristocracy" },
    { value = "1540", label = "Arknights" },
    { value = "357", label = "Arms Dealers" },
    { value = "329", label = "Army" },
    { value = "163", label = "Army Building" },
    { value = "223", label = "Arranged Marriage" },
    { value = "55", label = "Arrogant Characters" },
    { value = "209", label = "Artifact Crafting" },
    { value = "210", label = "Artifacts" },
    { value = "91", label = "Artificial Intelligence" },
    { value = "302", label = "Artists" },
    { value = "217", label = "Assassins" },
    { value = "700", label = "Astrologers" },
    { value = "241", label = "Autism" },
    { value = "675", label = "Automatons" },
    { value = "245", label = "Average-looking Protagonist" },
    { value = "985", label = "Award-winning Work" },
    { value = "271", label = "Awkward Protagonist" },
    { value = "579", label = "Based on a Movie" },
    { value = "1118", label = "Based on a Song" },
    { value = "671", label = "Based on a TV Show" },
    { value = "1052", label = "Based on an Anime" },
    { value = "226", label = "Basketball" },
    { value = "416", label = "Battle Academy" },
    { value = "211", label = "Battle Competition" },
    { value = "190", label = "BDSM" },
    { value = "57", label = "Beast Companions" },
    { value = "8", label = "Beastkin" },
    { value = "58", label = "Beasts" },
    { value = "21", label = "Beautiful Female Lead" },
    { value = "628", label = "Bestiality" },
    { value = "40", label = "Betrayal" },
    { value = "79", label = "Bickering Couple" },
    { value = "473", label = "Biochip" },
    { value = "813", label = "Bisexual Protagonist" },
    { value = "38", label = "Black Belly" },
    { value = "171", label = "Blackmail" },
    { value = "379", label = "Blacksmith" },
    { value = "1123", label = "Bleach" },
    { value = "676", label = "Blind Dates" },
    { value = "481", label = "Blind Protagonist" },
    { value = "534", label = "Blood Manipulation" },
    { value = "9", label = "Bloodlines" },
    { value = "269", label = "Body Swap" },
    { value = "246", label = "Body Tempering" },
    { value = "980", label = "Body-double" },
    { value = "439", label = "Bodyguards" },
    { value = "337", label = "Books" },
    { value = "659", label = "Bookworm" },
    { value = "80", label = "Boss-Subordinate Relationship" },
    { value = "396", label = "Brainwashing" },
    { value = "974", label = "Breast Fetish" },
    { value = "231", label = "Broken Engagement" },
    { value = "521", label = "Brother Complex" },
    { value = "570", label = "Brotherhood" },
    { value = "1288", label = "BTTH" },
    { value = "442", label = "Buddhism" },
    { value = "134", label = "Bullying" },
    { value = "60", label = "Business Management" },
    { value = "227", label = "Businessmen" },
    { value = "763", label = "Butlers" },
    { value = "22", label = "Calm Protagonist" },
    { value = "407", label = "Cannibalism" },
    { value = "512", label = "Card Games" },
    { value = "121", label = "Carefree Protagonist" },
    { value = "122", label = "Caring Protagonist" },
    { value = "222", label = "Cautious Protagonist" },
    { value = "23", label = "Celebrities" },
    { value = "61", label = "Character Growth" },
    { value = "39", label = "Charismatic Protagonist" },
    { value = "520", label = "Charming Protagonist" },
    { value = "142", label = "Chat Rooms" },
    { value = "62", label = "Cheats" },
    { value = "260", label = "Chefs" },
    { value = "393", label = "Child Abuse" },
    { value = "491", label = "Child Protagonist" },
    { value = "81", label = "Childcare" },
    { value = "197", label = "Childhood Friends" },
    { value = "176", label = "Childhood Love" },
    { value = "588", label = "Childhood Promise" },
    { value = "123", label = "Childish Protagonist" },
    { value = "713", label = "Chuunibyou" },
    { value = "327", label = "Clan Building" },
    { value = "6438", label = "Classic" },
    { value = "92", label = "Clever Protagonist" },
    { value = "297", label = "Clingy Lover" },
    { value = "644", label = "Clones" },
    { value = "611", label = "Clubs" },
    { value = "204", label = "Clumsy Love Interests" },
    { value = "662", label = "Co-Workers" },
    { value = "152", label = "Cohabitation" },
    { value = "84", label = "Cold Love Interests" },
    { value = "10", label = "Cold Protagonist" },
    { value = "749", label = "Collection of Short Stories" },
    { value = "1454", label = "College/University" },
    { value = "105", label = "Coma" },
    { value = "154", label = "Comedic Undertone" },
    { value = "722", label = "Coming of Age" },
    { value = "253", label = "Complex Family Relationships" },
    { value = "445", label = "Conditional Power" },
    { value = "232", label = "Confident Protagonist" },
    { value = "172", label = "Confinement" },
    { value = "541", label = "Conflicting Loyalties" },
    { value = "294", label = "Contracts" },
    { value = "161", label = "Cooking" },
    { value = "408", label = "Corruption" },
    { value = "338", label = "Cosmic Wars" },
    { value = "726", label = "Cosplay" },
    { value = "153", label = "Couple Growth" },
    { value = "594", label = "Court Official" },
    { value = "683", label = "Cousins" },
    { value = "290", label = "Cowardly Protagonist" },
    { value = "374", label = "Crafting" },
    { value = "440", label = "Crime" },
    { value = "173", label = "Criminals" },
    { value = "155", label = "Cross-dressing" },
    { value = "492", label = "Crossover" },
    { value = "42", label = "Cruel Characters" },
    { value = "741", label = "Cryostasis" },
    { value = "63", label = "Cultivation" },
    { value = "164", label = "Cunning Protagonist" },
    { value = "261", label = "Curious Protagonist" },
    { value = "528", label = "Curses" },
    { value = "224", label = "Cute Children" },
    { value = "124", label = "Cute Protagonist" },
    { value = "125", label = "Cute Story" },
    { value = "3294", label = "Cyberpunk 2077" },
    { value = "380", label = "Dancers" },
    { value = "1636", label = "Danmachi" },
    { value = "417", label = "Dao Companion" },
    { value = "583", label = "Dao Comprehension" },
    { value = "444", label = "Daoism" },
    { value = "319", label = "Dark" },
    { value = "922", label = "Dark Fantasy" },
    { value = "835", label = "DC Universe" },
    { value = "723", label = "Dead Protagonist" },
    { value = "194", label = "Death" },
    { value = "64", label = "Death of Loved Ones" },
    { value = "515", label = "Debts" },
    { value = "247", label = "Delinquents" },
    { value = "640", label = "Delusions" },
    { value = "430", label = "Demi-Humans" },
    { value = "218", label = "Demon Lord" },
    { value = "1124", label = "Demon Slayer" },
    { value = "395", label = "Demonic Cultivation Technique" },
    { value = "219", label = "Demons" },
    { value = "65", label = "Dense Protagonist" },
    { value = "156", label = "Depictions of Cruelty" },
    { value = "303", label = "Depression" },
    { value = "342", label = "Destiny" },
    { value = "1347", label = "Detective Conan" },
    { value = "180", label = "Detectives" },
    { value = "165", label = "Determined Protagonist" },
    { value = "24", label = "Devoted Love Interests" },
    { value = "6330", label = "Devouring" },
    { value = "136", label = "Different Social Status" },
    { value = "1767", label = "Digimon" },
    { value = "263", label = "Disabilities" },
    { value = "504", label = "Discrimination" },
    { value = "634", label = "Disfigurement" },
    { value = "516", label = "Dishonest Protagonist" },
    { value = "542", label = "Distrustful Protagonist" },
    { value = "535", label = "Divination" },
    { value = "984", label = "Divine Protection" },
    { value = "44", label = "Divorce" },
    { value = "3199", label = "DnD" },
    { value = "25", label = "Doctors" },
    { value = "414", label = "Domestic Affairs" },
    { value = "26", label = "Doting Love Interests" },
    { value = "177", label = "Doting Older Siblings" },
    { value = "178", label = "Doting Parents" },
    { value = "326", label = "Douluo Dalu" },
    { value = "1309", label = "Dragon Ball" },
    { value = "308", label = "Dragon Riders" },
    { value = "309", label = "Dragon Slayers" },
    { value = "310", label = "Dragons" },
    { value = "494", label = "Dreams" },
    { value = "543", label = "Drugs" },
    { value = "506", label = "Druids" },
    { value = "742", label = "Dungeon Master" },
    { value = "632", label = "Dungeons" },
    { value = "311", label = "Dwarfs" },
    { value = "618", label = "Dystopia" },
    { value = "275", label = "e-Sports" },
    { value = "2", label = "Early Romance" },
    { value = "712", label = "Earth Invasion" },
    { value = "434", label = "Easy Going Life" },
    { value = "505", label = "Economics" },
    { value = "575", label = "Editors" },
    { value = "397", label = "Eidetic Memory" },
    { value = "776", label = "Elderly Protagonist" },
    { value = "398", label = "Elemental Magic" },
    { value = "354", label = "Elves" },
    { value = "381", label = "Emotionally Weak Protagonist" },
    { value = "437", label = "Empires" },
    { value = "655", label = "Engagement" },
    { value = "697", label = "Engineer" },
    { value = "577", label = "Enlightenment" },
    { value = "157", label = "Episodic" },
    { value = "343", label = "Eunuch" },
    { value = "457", label = "European Ambience" },
    { value = "333", label = "Evil Gods" },
    { value = "66", label = "Evil Organizations" },
    { value = "382", label = "Evil Protagonist" },
    { value = "529", label = "Evil Religions" },
    { value = "339", label = "Evolution" },
    { value = "1036", label = "Exhibitionism" },
    { value = "468", label = "Exorcism" },
    { value = "351", label = "Eye Powers" },
    { value = "584", label = "Fairies" },
    { value = "1023", label = "Fairy Tail" },
    { value = "596", label = "Fallen Angels" },
    { value = "524", label = "Fallen Nobility" },
    { value = "291", label = "Familial Love" },
    { value = "780", label = "Familiars" },
    { value = "148", label = "Family" },
    { value = "459", label = "Family Business" },
    { value = "248", label = "Family Conflict" },
    { value = "627", label = "Famous Parents" },
    { value = "383", label = "Famous Protagonist" },
    { value = "710", label = "Fanaticism" },
    { value = "362", label = "Fantasy Creatures" },
    { value = "277", label = "Fantasy World" },
    { value = "229", label = "Farming" },
    { value = "67", label = "Fast Cultivation" },
    { value = "68", label = "Fast Learner" },
    { value = "358", label = "Fat Protagonist" },
    { value = "359", label = "Fat to Fit" },
    { value = "272", label = "Fated Lovers" },
    { value = "639", label = "Fearless Protagonist" },
    { value = "629", label = "Fellatio" },
    { value = "557", label = "Female Master" },
    { value = "18", label = "Female Protagonist" },
    { value = "734", label = "Female to Male" },
    { value = "581", label = "Feng Shui" },
    { value = "166", label = "Firearms" },
    { value = "207", label = "First Love" },
    { value = "192", label = "First-time Intercourse" },
    { value = "135", label = "Flashbacks" },
    { value = "745", label = "Fleet Battles" },
    { value = "623", label = "Folklore" },
    { value = "352", label = "Football" },
    { value = "110", label = "Forced into a Relationship" },
    { value = "317", label = "Forced Living Arrangements" },
    { value = "111", label = "Forced Marriage" },
    { value = "384", label = "Forgetful Protagonist" },
    { value = "478", label = "Former Hero" },
    { value = "256", label = "Fox Spirits" },
    { value = "737", label = "Friends Become Enemies" },
    { value = "421", label = "Friendship" },
    { value = "69", label = "Fujoshi" },
    { value = "193", label = "Futanari" },
    { value = "126", label = "Futuristic Setting" },
    { value = "1109", label = "Galge" },
    { value = "661", label = "Gambling" },
    { value = "70", label = "Game Elements" },
    { value = "3422", label = "Game of Thrones" },
    { value = "392", label = "Game Ranking System" },
    { value = "170", label = "Gamers" },
    { value = "321", label = "Gangs" },
    { value = "5673", label = "Gao Wu" },
    { value = "214", label = "Gate to Another World" },
    { value = "609", label = "Genderless Protagonist" },
    { value = "233", label = "Generals" },
    { value = "312", label = "Genetic Modifications" },
    { value = "215", label = "Genies" },
    { value = "216", label = "Genius Protagonist" },
    { value = "1321", label = "Genshin Impact" },
    { value = "158", label = "Ghosts" },
    { value = "981", label = "Gladiators" },
    { value = "616", label = "Goblins" },
    { value = "298", label = "God Protagonist" },
    { value = "668", label = "God-human Relationship" },
    { value = "278", label = "Goddesses" },
    { value = "356", label = "Godly Powers" },
    { value = "234", label = "Gods" },
    { value = "778", label = "Golems" },
    { value = "94", label = "Gore" },
    { value = "1016", label = "Grave Keepers" },
    { value = "544", label = "Grinding" },
    { value = "264", label = "Guardian Relationship" },
    { value = "631", label = "Guilds" },
    { value = "95", label = "Gunfighters" },
    { value = "367", label = "Hackers" },
    { value = "265", label = "Half-human Protagonist" },
    { value = "699", label = "Handjob" },
    { value = "11", label = "Handsome Male Lead" },
    { value = "127", label = "Hard-Working Protagonist" },
    { value = "37", label = "Harem-seeking Protagonist" },
    { value = "237", label = "Harry Potter" },
    { value = "625", label = "Harsh Training" },
    { value = "112", label = "Hated Protagonist" },
    { value = "566", label = "Healers" },
    { value = "106", label = "Heartwarming" },
    { value = "582", label = "Heaven" },
    { value = "128", label = "Heavenly Tribulation" },
    { value = "651", label = "Hell" },
    { value = "612", label = "Helpful Protagonist" },
    { value = "779", label = "Herbalist" },
    { value = "536", label = "Heroes" },
    { value = "969", label = "Heterochromia" },
    { value = "259", label = "Hidden Abilities" },
    { value = "1039", label = "Highschool DxD" },
    { value = "1196", label = "Hollywood" },
    { value = "648", label = "Honest Protagonist" },
    { value = "5779", label = "HongHuangB" },
    { value = "2516", label = "HonghuangN" },
    { value = "4496", label = "HonghuangS" },
    { value = "5286", label = "HongHuangz" },
    { value = "6483", label = "Hongmeng" },
    { value = "636", label = "Hospital" },
    { value = "300", label = "Hot-blooded Protagonist" },
    { value = "413", label = "Human Experimentation" },
    { value = "490", label = "Human Weapon" },
    { value = "159", label = "Human-Nonhuman Relationship" },
    { value = "129", label = "Humanoid Protagonist" },
    { value = "1338", label = "Hunter x Hunter" },
    { value = "531", label = "Hunters" },
    { value = "377", label = "Hypnotism" },
    { value = "344", label = "Identity Crisis" },
    { value = "1077", label = "Immortal" },
    { value = "235", label = "Immortals" },
    { value = "238", label = "Imperial Harem" },
    { value = "179", label = "Incest" },
    { value = "1019", label = "Incubus" },
    { value = "568", label = "Indecisive Protagonist" },
    { value = "641", label = "Industrialization" },
    { value = "431", label = "Inferiority Complex" },
    { value = "426", label = "Inheritance" },
    { value = "744", label = "Inscriptions" },
    { value = "313", label = "Insects" },
    { value = "1745", label = "Interconnected Storylines" },
    { value = "27", label = "Interdimensional Travel" },
    { value = "680", label = "Introverted Protagonist" },
    { value = "496", label = "Investigations" },
    { value = "6217", label = "Invisibility" },
    { value = "71", label = "Jack of All Trades" },
    { value = "258", label = "Jealousy" },
    { value = "603", label = "Jiangshi" },
    { value = "2882", label = "JoJo’s Bizarre Adventure" },
    { value = "1326", label = "Journey to the West" },
    { value = "1127", label = "Jujutsu Kaisen" },
    { value = "509", label = "Kidnappings" },
    { value = "131", label = "Kind Love Interests" },
    { value = "340", label = "Kingdom Building" },
    { value = "181", label = "Kingdoms" },
    { value = "208", label = "Knights" },
    { value = "708", label = "Kuudere" },
    { value = "160", label = "Lack of Common Sense" },
    { value = "133", label = "Language Barrier" },
    { value = "249", label = "Late Romance" },
    { value = "548", label = "Lawyers" },
    { value = "441", label = "Lazy Protagonist" },
    { value = "375", label = "Leadership" },
    { value = "849", label = "League of Legends" },
    { value = "607", label = "Legends" },
    { value = "201", label = "Level System" },
    { value = "773", label = "Library" },
    { value = "1721", label = "Life Script" },
    { value = "470", label = "Limited Lifespan" },
    { value = "883", label = "Live Streaming" },
    { value = "474", label = "Living Alone" },
    { value = "576", label = "Loli" },
    { value = "6211", label = "Loneliness" },
    { value = "585", label = "Loner Protagonist" },
    { value = "412", label = "Long Separations" },
    { value = "273", label = "Long-distance Relationship" },
    { value = "895", label = "Lord of the Mysteries" },
    { value = "330", label = "Lost Civilizations" },
    { value = "573", label = "Lottery" },
    { value = "168", label = "Love at First Sight" },
    { value = "19", label = "Love Interest Falls in Love First" },
    { value = "610", label = "Love Rivals" },
    { value = "485", label = "Love Triangles" },
    { value = "502", label = "Lovers Reunited" },
    { value = "328", label = "Low-key Protagonist" },
    { value = "507", label = "Loyal Subordinates" },
    { value = "368", label = "Lucky Protagonist" },
    { value = "182", label = "Magic" },
    { value = "314", label = "Magic Beasts" },
    { value = "72", label = "Magic Formations" },
    { value = "1744", label = "Magical Girls" },
    { value = "73", label = "Magical Space" },
    { value = "608", label = "Magical Technology" },
    { value = "649", label = "Maids" },
    { value = "12", label = "Male Protagonist" },
    { value = "480", label = "Male to Female" },
    { value = "28", label = "Male Yandere" },
    { value = "642", label = "Management" },
    { value = "809", label = "Mangaka" },
    { value = "597", label = "Manipulative Characters" },
    { value = "96", label = "Manly Gay Couple" },
    { value = "85", label = "Marriage" },
    { value = "489", label = "Marriage of Convenience" },
    { value = "394", label = "Martial Spirits" },
    { value = "537", label = "Marvel" },
    { value = "45", label = "Masochistic Characters" },
    { value = "304", label = "Master-Disciple Relationship" },
    { value = "361", label = "Master-Servant Relationship" },
    { value = "733", label = "Masturbation" },
    { value = "686", label = "Matriarchy" },
    { value = "97", label = "Mature Protagonist" },
    { value = "299", label = "Medical Knowledge" },
    { value = "429", label = "Medieval" },
    { value = "167", label = "Mercenaries" },
    { value = "527", label = "Merchants" },
    { value = "86", label = "Military" },
    { value = "621", label = "Mind Break" },
    { value = "389", label = "Mind Control" },
    { value = "6246", label = "Minecraft" },
    { value = "1343", label = "Mismatched Couple" },
    { value = "113", label = "Misunderstandings" },
    { value = "202", label = "MMORPG" },
    { value = "443", label = "Mob Protagonist" },
    { value = "657", label = "Models" },
    { value = "3", label = "Modern Day" },
    { value = "307", label = "Modern Knowledge" },
    { value = "82", label = "Money Grubber" },
    { value = "569", label = "Monster Girls" },
    { value = "1151", label = "Monster Society" },
    { value = "74", label = "Monster Tamer" },
    { value = "230", label = "Monsters" },
    { value = "3150", label = "Mortal Flow" },
    { value = "292", label = "Movies" },
    { value = "257", label = "Mpreg" },
    { value = "387", label = "Multiple Identities" },
    { value = "20", label = "Multiple Personalities" },
    { value = "279", label = "Multiple POV" },
    { value = "501", label = "Multiple Protagonists" },
    { value = "615", label = "Multiple Timelines" },
    { value = "293", label = "Multiple Transported Individuals" },
    { value = "345", label = "Murders" },
    { value = "186", label = "Music" },
    { value = "320", label = "Mutated Creatures" },
    { value = "418", label = "Mutations" },
    { value = "736", label = "Mute Character" },
    { value = "185", label = "Mystery Solving" },
    { value = "427", label = "Mythical Beasts" },
    { value = "484", label = "Mythology" },
    { value = "75", label = "Naive Protagonist" },
    { value = "469", label = "Narcissistic Protagonist" },
    { value = "335", label = "Naruto" },
    { value = "305", label = "Nationalism" },
    { value = "76", label = "Near-Death Experience" },
    { value = "422", label = "Necromancer" },
    { value = "645", label = "Neet" },
    { value = "77", label = "Netorare" },
    { value = "78", label = "Netori" },
    { value = "346", label = "Nightmares" },
    { value = "460", label = "Ninjas" },
    { value = "280", label = "Nobles" },
    { value = "143", label = "Non-humanoid Protagonist" },
    { value = "6212", label = "Non-linear Storytelling" },
    { value = "972", label = "Nudity" },
    { value = "637", label = "Nurses" },
    { value = "205", label = "Obsessive Love" },
    { value = "517", label = "Office Romance" },
    { value = "364", label = "Older Love Interests" },
    { value = "301", label = "Omegaverse" },
    { value = "336", label = "One Piece" },
    { value = "1063", label = "One Punch Man" },
    { value = "638", label = "Online Romance" },
    { value = "720", label = "Orcs" },
    { value = "174", label = "Organized Crime" },
    { value = "428", label = "Orphans" },
    { value = "472", label = "Otaku" },
    { value = "1580", label = "Otome Game" },
    { value = "991", label = "Outcasts" },
    { value = "409", label = "Outer Space" },
    { value = "1184", label = "Overlord" },
    { value = "41", label = "Overpowered Protagonist" },
    { value = "717", label = "Overprotective Siblings" },
    { value = "1186", label = "Pacifist Protagonist" },
    { value = "752", label = "Paizuri" },
    { value = "458", label = "Parallel Worlds" },
    { value = "331", label = "Parasites" },
    { value = "650", label = "Parent Complex" },
    { value = "620", label = "Parody" },
    { value = "268", label = "Part-Time Job" },
    { value = "98", label = "Past Plays a Big Role" },
    { value = "114", label = "Past Trauma" },
    { value = "274", label = "Persistent Love Interests" },
    { value = "137", label = "Personality Changes" },
    { value = "281", label = "Perverted Protagonist" },
    { value = "107", label = "Pets" },
    { value = "689", label = "Pharmacist" },
    { value = "774", label = "Philosophical" },
    { value = "236", label = "Phoenixes" },
    { value = "705", label = "Photography" },
    { value = "399", label = "Pill Based Cultivation" },
    { value = "400", label = "Pill Concocting" },
    { value = "1592", label = "Pilots" },
    { value = "546", label = "Pirates" },
    { value = "653", label = "Playboys" },
    { value = "714", label = "Playful Protagonist" },
    { value = "731", label = "Poetry" },
    { value = "370", label = "Poisons" },
    { value = "587", label = "Pokemon" },
    { value = "419", label = "Police" },
    { value = "684", label = "Polite Protagonist" },
    { value = "43", label = "Politics" },
    { value = "669", label = "Polyandry" },
    { value = "282", label = "Polygamy" },
    { value = "522", label = "Poor Protagonist" },
    { value = "132", label = "Poor to Rich" },
    { value = "592", label = "Popular Love Interests" },
    { value = "605", label = "Possession" },
    { value = "4", label = "Possessive Characters" },
    { value = "401", label = "Post-apocalyptic" },
    { value = "47", label = "Power Couple" },
    { value = "690", label = "Power Struggle" },
    { value = "593", label = "Pragmatic Protagonist" },
    { value = "724", label = "Precognition" },
    { value = "83", label = "Pregnancy" },
    { value = "250", label = "Pretend Lovers" },
    { value = "138", label = "Previous Life Talent" },
    { value = "1059", label = "Priestesses" },
    { value = "707", label = "Priests" },
    { value = "560", label = "Prison" },
    { value = "423", label = "Proactive Protagonist" },
    { value = "704", label = "Programmer" },
    { value = "718", label = "Prophecies" },
    { value = "447", label = "Prostitutes" },
    { value = "715", label = "Psychic Powers" },
    { value = "498", label = "Psychopaths" },
    { value = "4301", label = "Puppeteers" },
    { value = "719", label = "Quiet Characters" },
    { value = "198", label = "Quirky Characters" },
    { value = "646", label = "R-15" },
    { value = "5058", label = "R18" },
    { value = "604", label = "Race Change" },
    { value = "13", label = "Racism" },
    { value = "402", label = "Rape" },
    { value = "6", label = "Rape Victim Becomes Lover" },
    { value = "6417", label = "Reality-Game Fusion" },
    { value = "757", label = "Rebellion" },
    { value = "139", label = "Rebirth" },
    { value = "831", label = "Reborn" },
    { value = "3835", label = "Regression" },
    { value = "706", label = "Religions" },
    { value = "545", label = "Reporters" },
    { value = "2887", label = "Resident Evil" },
    { value = "635", label = "Restaurant" },
    { value = "390", label = "Resurrection" },
    { value = "695", label = "Returning from Another World" },
    { value = "225", label = "Revenge" },
    { value = "378", label = "Reverse Harem" },
    { value = "571", label = "Reverse Rape" },
    { value = "740", label = "Reversible Couple" },
    { value = "743", label = "Rich to Poor" },
    { value = "630", label = "Righteous Protagonist" },
    { value = "687", label = "Rivalry" },
    { value = "768", label = "Romance" },
    { value = "14", label = "Romantic Subplot" },
    { value = "772", label = "Roommates" },
    { value = "35", label = "Royalty" },
    { value = "15", label = "Ruthless Protagonist" },
    { value = "622", label = "Sadistic Characters" },
    { value = "598", label = "Saints" },
    { value = "1025", label = "Samurai" },
    { value = "682", label = "Saving the World" },
    { value = "405", label = "Schemes And Conspiracies" },
    { value = "486", label = "Scientists" },
    { value = "284", label = "Sealed Power" },
    { value = "99", label = "Second Chance" },
    { value = "266", label = "Secret Crush" },
    { value = "285", label = "Secret Identity" },
    { value = "652", label = "Secret Organizations" },
    { value = "1021", label = "Secret Relationship" },
    { value = "552", label = "Secretive Protagonist" },
    { value = "286", label = "Secrets" },
    { value = "692", label = "Sect Development" },
    { value = "732", label = "Seduction" },
    { value = "633", label = "Seeing Things Other Humans Can't" },
    { value = "254", label = "Selfish Protagonist" },
    { value = "558", label = "Selfless Protagonist" },
    { value = "500", label = "Seme Protagonist" },
    { value = "970", label = "Sentient Objects" },
    { value = "771", label = "Sentimental Protagonist" },
    { value = "550", label = "Serial Killers" },
    { value = "665", label = "Servants" },
    { value = "691", label = "Seven Deadly Sins" },
    { value = "475", label = "Sex Slaves" },
    { value = "175", label = "Sexual Abuse" },
    { value = "748", label = "Sexual Cultivation Technique" },
    { value = "203", label = "Shameless Protagonist" },
    { value = "267", label = "Shapeshifters" },
    { value = "296", label = "Sharp-tongued Characters" },
    { value = "559", label = "Short Story" },
    { value = "493", label = "Shota" },
    { value = "595", label = "Shoujo-Ai Subplot" },
    { value = "530", label = "Shounen-Ai Subplot" },
    { value = "108", label = "Showbiz" },
    { value = "482", label = "Shy Characters" },
    { value = "46", label = "Sibling Rivalry" },
    { value = "48", label = "Siblings" },
    { value = "448", label = "Siblings Not Related by Blood" },
    { value = "600", label = "Sickly Characters" },
    { value = "934", label = "Sign-in" },
    { value = "1172", label = "Simulator" },
    { value = "187", label = "Singers" },
    { value = "6340", label = "Single Female Lead" },
    { value = "503", label = "Single Parent" },
    { value = "709", label = "Sister Complex" },
    { value = "403", label = "Skill Assimilation" },
    { value = "508", label = "Skill Books" },
    { value = "572", label = "Skill Creation" },
    { value = "730", label = "Slave Harem" },
    { value = "540", label = "Slave Protagonist" },
    { value = "287", label = "Slaves" },
    { value = "487", label = "Slow Growth at Start" },
    { value = "144", label = "Slow Romance" },
    { value = "513", label = "Smart Couple" },
    { value = "755", label = "Social Outcasts" },
    { value = "455", label = "Soldiers" },
    { value = "404", label = "Soul Power" },
    { value = "449", label = "Souls" },
    { value = "721", label = "Spatial Manipulation" },
    { value = "578", label = "Spear Wielder" },
    { value = "347", label = "Special Abilities" },
    { value = "251", label = "Spies" },
    { value = "654", label = "Spirit Advisor" },
    { value = "450", label = "Spirit Users" },
    { value = "555", label = "Spirits" },
    { value = "2884", label = "Stand User" },
    { value = "1302", label = "Star Wars" },
    { value = "896", label = "Steampunk" },
    { value = "188", label = "Stockholm Syndrome" },
    { value = "729", label = "Stoic Characters" },
    { value = "322", label = "Store Owner" },
    { value = "643", label = "Straight Seme" },
    { value = "438", label = "Straight Uke" },
    { value = "150", label = "Strategic Battles" },
    { value = "451", label = "Strategist" },
    { value = "371", label = "Strength-based Social Hierarchy" },
    { value = "30", label = "Strong Love Interests" },
    { value = "118", label = "Strong to Stronger" },
    { value = "565", label = "Stubborn Protagonist" },
    { value = "365", label = "Student-Teacher Relationship" },
    { value = "681", label = "Succubus" },
    { value = "551", label = "Sudden Strength Gain" },
    { value = "660", label = "Sudden Wealth" },
    { value = "775", label = "Suicides" },
    { value = "602", label = "Summoned Hero" },
    { value = "315", label = "Summoning Magic" },
    { value = "100", label = "Survival" },
    { value = "514", label = "Survival Game" },
    { value = "1339", label = "Swallowed Star" },
    { value = "288", label = "Sword And Magic" },
    { value = "325", label = "Sword Wielder" },
    { value = "119", label = "System" },
    { value = "252", label = "Teachers" },
    { value = "101", label = "Teamwork" },
    { value = "488", label = "Technological Gap" },
    { value = "1020", label = "Tentacles" },
    { value = "658", label = "Terminal Illness" },
    { value = "1725", label = "Territory Management" },
    { value = "767", label = "Terrorists" },
    { value = "420", label = "Thieves" },
    { value = "1356", label = "Three Kingdoms" },
    { value = "1042", label = "Threesome" },
    { value = "476", label = "Thriller" },
    { value = "702", label = "Time Loop" },
    { value = "672", label = "Time Manipulation" },
    { value = "777", label = "Time Paradox" },
    { value = "410", label = "Time Skip" },
    { value = "199", label = "Time Travel" },
    { value = "463", label = "Timid Protagonist" },
    { value = "466", label = "Tomboyish Female Lead" },
    { value = "728", label = "Torture" },
    { value = "140", label = "Tragic Past" },
    { value = "109", label = "Transformation Ability" },
    { value = "32", label = "Transmigration" },
    { value = "525", label = "Transplanted Memories" },
    { value = "348", label = "Trap" },
    { value = "465", label = "Tribal Society" },
    { value = "452", label = "Trickster" },
    { value = "349", label = "Tsundere" },
    { value = "196", label = "Twins" },
    { value = "499", label = "Twisted Personality" },
    { value = "739", label = "Ugly Protagonist" },
    { value = "483", label = "Ugly to Beautiful" },
    { value = "141", label = "Unconditional Love" },
    { value = "4345", label = "Undead Protagonist" },
    { value = "580", label = "Underestimated Protagonist" },
    { value = "323", label = "Unique Cultivation Technique" },
    { value = "1530", label = "Unlimited Flow" },
    { value = "432", label = "Unlucky Protagonist" },
    { value = "456", label = "Unreliable Narrator" },
    { value = "561", label = "Unrequited Love" },
    { value = "16", label = "Vampires" },
    { value = "1222", label = "Versatile Mage" },
    { value = "538", label = "Villainess Noble Girls" },
    { value = "93", label = "Virtual Reality" },
    { value = "549", label = "Voice Actors" },
    { value = "1187", label = "War Records" },
    { value = "6207", label = "Warhammer" },
    { value = "151", label = "Wars" },
    { value = "477", label = "Weak Protagonist" },
    { value = "17", label = "Weak to Strong" },
    { value = "7", label = "Wealthy Characters" },
    { value = "765", label = "Werebeasts" },
    { value = "562", label = "Wishes" },
    { value = "647", label = "Witches" },
    { value = "316", label = "Wizards" },
    { value = "33", label = "World Hopping" },
    { value = "332", label = "World Travel" },
    { value = "679", label = "World Tree" },
    { value = "406", label = "Writers" },
    { value = "510", label = "Yandere" },
    { value = "747", label = "Younger Brothers" },
    { value = "769", label = "Younger Love Interests" },
    { value = "563", label = "Younger Sisters" },
    { value = "1085", label = "Yu-Gi-Oh!" },
    { value = "102", label = "Zombies" },
    { value = "honghuang", label = "Honghuang (all Honghuang* tags)" },
}

function getFilterList()
    return {
        {
            type         = "select",
            key          = "browse",
            label        = "Browse Mode",
            defaultValue = "catalog",
            options = {
                { value = "catalog", label = "Categories (filters below)" },
                { value = "updates", label = "Recently Updated" },
            }
        },
        {
            type         = "select",
            key          = "category",
            label        = "Category",
            defaultValue = "all",
            options      = CATEGORIES,
        },
        {
            type         = "select",
            key          = "status",
            label        = "Status",
            defaultValue = "all",
            options = {
                { value = "all",       label = "All" },
                { value = "Completed", label = "Completed" },
                { value = "Ongoing",   label = "Ongoing" },
            }
        },
        {
            type         = "select",
            key          = "sort",
            label        = "Sort By",
            defaultValue = "newstime",
            options = {
                { value = "newstime",   label = "Newest Added" },
                { value = "lastdotime", label = "Last Updated" },
                { value = "onclick",    label = "Most Viewed" },
            }
        },
        {
            type        = "tag_input",
            key         = "tags",
            label       = "Tags (type to search — 755 curated tags)",
            allowCustom = false,
            options     = TAG_FILTER_OPTIONS,
        },
    }
end

-- Tag listing site PATH for result page `index` (0-based).
--   page 0 → /tags/{id}-0.html            (500 items on one page)
--   page N → /e/tags/index.php?page=N&tagid={id}&line=500&tempid=9
local function tagListingPath(tagId, index)
    if index <= 0 then
        return "/tags/" .. tagId .. "-0.html"
    end
    return "/e/tags/index.php?page=" .. tostring(index) ..
        "&tagid=" .. tagId .. "&line=500&tempid=9"
end

-- Browse ONE tag listing at page `index`. hasNext: next-page link in the
-- pager, with a grand-total fallback (500 items per tag page).
-- PRIMARY-ONLY fetching: the mirror's tag ids point at DIFFERENT tags
-- (verified live), so a mirror fallback here would browse the wrong tag.
local function browseTag(tagId, index)
    local path = tagListingPath(tagId, index)
    browsePacing(400)
    local r = httpGetPrimary(path)
    if not r or not r.success then return {}, false end
    local items = parseNovelCards(r.body, false)
    local hasNext = hasNextByLink(r.body, "page=" .. tostring(index + 1) .. "&tagid=" .. tagId)
    local total = listTotal(r.body)
    if total and (index + 1) * 500 < total then hasNext = true end
    return items, hasNext
end

-- UNION browse: merge the listings of several tags ("everything as search
-- result"), deduplicated by novel URL. One paced request per tag.
local function browseTagUnion(tagIds, index)
    local merged, seen = {}, {}
    local anyNext = false
    for _, tagId in ipairs(tagIds) do
        local items, hasNext = browseTag(tagId, index)
        if hasNext then anyNext = true end
        for _, it in ipairs(items) do
            if not seen[it.url] then
                seen[it.url] = true
                merged[#merged + 1] = it
            end
        end
    end
    return merged, anyNext
end

function getCatalogFiltered(index, filters)
    local browse    = filters["browse"]    or "catalog"
    local category  = filters["category"]  or "all"
    local status    = filters["status"]    or "all"
    local sort      = filters["sort"]      or "newstime"
    local picks     = filters["tags_included"] or {}

    -- ── Tags (2.2.0): the searchable tag_input picker marshals its chips
    -- as filters["tags_included"] = { value, … } — numeric tag ids plus the
    -- "honghuang" family keyword. One union browse. Takes priority (the
    -- site cannot combine a tag listing with category/status/sort).
    if #picks > 0 then
        local ok, tagIds = pcall(tagSearchResolve, table.concat(picks, ","), nil)
        if not ok then
            show_error("WuxiaBox tag error", tostring(tagIds))
            return { items = {}, hasNext = false }
        end
        if #tagIds == 0 then
            show_error("WuxiaBox tags",
                "None of the picked tags could be resolved. This should not " ..
                "happen — please report the tags you picked.")
            return { items = {}, hasNext = false }
        end
        local items, hasNext = browseTagUnion(tagIds, index)
        return { items = items, hasNext = hasNext }
    end

    -- ── Updates mode (ignores category/status/sort)
    if browse == "updates" then
        local path
        if index <= 0 then
            path = "/updates/"
        else
            path = "/updates/" .. tostring(index) .. ".html"
        end
        local r = httpGetAny(path)
        if not r or not r.success then return { items = {}, hasNext = false } end
        -- cards link to the LATEST chapter → rewrite to the novel page
        local items = parseNovelCards(r.body, true)
        local hasNext = hasNextByLink(r.body, "/updates/" .. tostring(index + 1) .. ".html")
        return { items = items, hasNext = hasNext }
    end

    -- ── Categories mode
    local path = "/list/" .. url_encode(category) .. "/" ..
        url_encode(status) .. "-" .. url_encode(sort) .. "-" .. tostring(index) .. ".html"
    local r = httpGetAny(path)
    if not r or not r.success then return { items = {}, hasNext = false } end
    local items = parseNovelCards(r.body, false)
    local hasNext = hasNextByLink(r.body, "-" .. tostring(index + 1) .. ".html")
    return { items = items, hasNext = hasNext }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- BOOK DETAILS  (all share the novel page via fetchPage — one HTTP request)
-- ═══════════════════════════════════════════════════════════════════════════

function getBookTitle(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, "h1.novel-title")
    if el then
        local t = string_clean(el.text)
        if t ~= "" then return t end
    end
    return nil
end

function getBookCoverImageUrl(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    -- figure.cover is the novel-page shape; ".cover img" kept from base
    -- v1.0.1 as a fallback for variant markups.
    local cover = html_attr(body, "figure.cover img", "data-src")
    if cover == "" then cover = html_attr(body, "figure.cover img", "src") end
    if cover == "" then cover = html_attr(body, ".cover img", "data-src") end
    if cover == "" then cover = html_attr(body, ".cover img", "src") end
    if cover ~= "" then return coverUrl(cover) end
    return nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    -- Selector preference kept from base v1.0.1, but the site renders
    -- <p class="description"> EMPTY on novel pages (and "" is truthy in
    -- Lua, so v1.0.1 returned empty descriptions) — fall through to the
    -- real synopsis block when the preferred node has no text.
    local el = html_select_first(body, "p.description")
    local text = ""
    if el then text = string_trim(html_text(el.html)) end
    if text == "" then
        el = html_select_first(body, ".summary .content")
        if el then text = string_trim(html_text(el.html)) end
    end
    if text == "" then return nil end
    -- The site often prepends a bracketed tag-soup line
    -- ("[Farming + Relaxed Entertainment + Traveling]") — keep it, it is
    -- part of the site's own synopsis presentation.
    return text
end

-- Genres = the site's CATEGORY chips only (2.1.0): <a class="property-item">
-- inside .categories, linking to /list/{slug}/. The same block also
-- carries tag chips (<a class="tag"> → /tags/{id}-0.html) — a DIFFERENT
-- taxonomy that lives on /browsetags/, not in genres.
function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local genres, seen = {}, {}
    for _, a in ipairs(html_select(body, ".categories a.property-item")) do
        local g = string_clean(a.text)
        if g ~= "" and not seen[g] then
            seen[g] = true
            genres[#genres + 1] = g
        end
    end
    return genres
end

-- Status from .header-stats: <span><strong>Completed</strong><small>Status</small></span>
function getBookStatus(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    for _, sp in ipairs(html_select(body, ".header-stats span")) do
        local small = html_select_first(sp.html, "small")
        if small and string.lower(string_clean(small.text)) == "status" then
            local strong = html_select_first(sp.html, "strong")
            if strong then
                local v = string_clean(strong.text)
                if v ~= "" then return v end
            end
        end
    end
    return nil
end

-- Last update = the date under the NEWEST chapter (the novel page shows the
-- OLDEST 100 chapters, so for long novels the newest chapter lives on the
-- LAST fy.php page; one extra lightweight fragment request, cached).
function getBookLastUpdate(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local slug = novelSlug(bookUrl)
    if not slug then return nil end

    local function lastTimeOf(htmlBody)
        local times = html_select(htmlBody, "ul.chapter-list time")
        if #times == 0 then return nil end
        local last = times[#times]
        return normalizeUpdateDate(string_clean(last.text))
    end

    -- highest fy.php page linked from the novel page's chapter pager
    local maxFy = 0
    for _, a in ipairs(html_select(body, "a[href]")) do
        local p = string.match(a.href or "", "/e/extend/fy%.php%?page=(%d+)&wjm=")
        if p then
            local n = tonumber(p) or 0
            if n > maxFy then maxFy = n end
        end
    end

    if maxFy > 0 then
        local fyPath = "/e/extend/fy.php?page=" .. tostring(maxFy) ..
            "&wjm=" .. url_encode(slug)
        local frag = fetchPage(fyPath, FY_HEADERS)
        if frag then
            local d = lastTimeOf(frag)
            if d then return d end
        end
    end
    return lastTimeOf(body)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CHAPTER LIST  (parsePage — paginated, incremental updates)
--
--   engine page 1  → the novel page itself (chapters 1-100, ASCENDING)
--   engine page N  → /e/extend/fy.php?page={N-1}&wjm={slug} (100/page)
--   totalPages     → highest fy.php page linked in the pager + 1
-- The site serves old→new within every page and old pages first, exactly
-- the order the engine expects — no inversion needed.
-- ═══════════════════════════════════════════════════════════════════════════

local function parseChapterItems(body)
    local chapters = {}
    for _, a in ipairs(html_select(body, "ul.chapter-list li a[href]")) do
        local chUrl = absUrl(a.href)
        if chUrl ~= "" then
            local title = ""
            local strong = html_select_first(a.html, "strong.chapter-title")
            if strong then title = string_clean(strong.text) end
            if title == "" then title = string_clean(a.title) end
            if title == "" then
                local no = html_select_first(a.html, "span.chapter-no")
                if no then title = string_clean(no.text) end
            end
            if title == "" then
                local n = string.match(chUrl, "_(%d+)%.html$")
                if n then title = "Chapter " .. n end
            end
            chapters[#chapters + 1] = { title = title, url = chUrl }
        end
    end
    return chapters
end

local function detectTotalListPages(body)
    local maxFy = 0
    for _, a in ipairs(html_select(body, "a[href]")) do
        local p = string.match(a.href or "", "/e/extend/fy%.php%?page=(%d+)&wjm=")
        if p then
            local n = tonumber(p) or 0
            if n > maxFy then maxFy = n end
        end
    end
    return maxFy + 1
end

function parsePage(bookUrl, page)
    local slug = novelSlug(bookUrl)
    if not slug then return { chapters = {}, totalPages = 1 } end

    local body
    if page <= 1 then
        body = fetchPage(bookUrl)
    else
        browsePacing(350)
        body = fetchPage("/e/extend/fy.php?page=" .. tostring(page - 1) ..
            "&wjm=" .. url_encode(slug), FY_HEADERS)
    end
    if not body then return { chapters = {}, totalPages = 1 } end

    local chapters = parseChapterItems(body)
    local totalPages = detectTotalListPages(body)
    if #chapters == 0 and page > 1 then
        -- a fy page beyond the end: keep totalPages sane
        return { chapters = {}, totalPages = page - 1 > 0 and page - 1 or 1 }
    end
    return { chapters = chapters, totalPages = totalPages }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CHAPTER TEXT  (+ the "502 every ~2 chapters" self-healing path)
-- ═══════════════════════════════════════════════════════════════════════════

function getChapterText(html, url)
    -- Pacing floor between chapter requests (default 1500 ms; setting).
    chapterPacing()

    local body = html
    if isChapterErrorPage(body) then
        -- The ENGINE fetched the canonical wuxiabox.com URL and got an
        -- error/interstitial page (its own retry ladder already ran —
        -- ServerErrorRetryInterceptor retried the 502 four times before
        -- handing it over). If the body is junk (origin 502/CF/maintenance
        -- rather than a real page), charge the failure to the primary
        -- site so the smart switcher steers this rescue — and every
        -- later fetch — to the healthy site.
        if isJunkBody(body) then baseFailed(SITE) end
        log_error("wuxiabox: error/interstitial page for " .. tostring(url) ..
            " — refetching via the smart switcher")
        body = refetchChapterWithRetry(url)
    end
    if not body or isChapterErrorPage(body) then
        log_error("wuxiabox: chapter could not be loaded: " .. tostring(url))
        -- A raised error beats returning "": the empty path falls through
        -- to the engine's generic heuristics, which would try to extract
        -- "text" out of the very error page they just failed on. The
        -- message deliberately avoids timeout/connect words so the app
        -- does not burn three more full retry cycles on a dead pair.
        error("WuxiaBox: chapter could not be loaded — wuxiabox.com and the " ..
            "wuxiaspot.com mirror both failed after several attempts. " ..
            "Wait a moment and try again.")
    end

    local cleaned = html_remove(body,
        "script", "style", "iframe", "ins",
        "div[align=center]", ".ads", ".advertisement",
        ".chapternav", ".recommends")

    local el = html_select_first(cleaned, "#chapter-article .chapter-content")
    if not el then el = html_select_first(cleaned, ".chapter-content") end
    if not el then return "" end

    local text = html_text(el.html)
    text = stripTitleEcho(text, body)
    text = applyStandardContentTransforms(text)
    -- Trailing author-note + end marker — kept from base v1.0.1.
    text = regex_replace(text, "(?s)\\s*\\([^)]*\\)\\s*\\(End of this chapter\\)\\s*$", "")
    text = regex_replace(text, "(?s)\\s*\\(End of this chapter\\)\\s*$", "")
    return string_trim(text)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- transformChapterUrl — forward-compatible engine hook (2.3.0)
--
-- NoveLA's DownloaderRepository fetches chapter pages itself, from the
-- canonical URL, BEFORE the plugin is invoked — on stock engines that hop
-- is not exposed to Lua, which is why the rescue path above exists. A
-- 15-line engine patch (see wuxiabox_pull_request.md § "Optional engine
-- follow-up") exposes SourceInterface.transformChapterUrl to Lua plugins;
-- on patched builds the engine calls THIS function with the chapter URL
-- before making its request, letting the smart switcher move the fetch
-- to the healthy/preferred site up front (no doomed canonical request at
-- all). Only portable URLs may switch hosts: /novel/… chapter pages
-- (same slugs on both sites). Everything else keeps its host.
-- ═══════════════════════════════════════════════════════════════════════════

function transformChapterUrl(url)
    if not url or url == "" then return url end
    local path = urlToPath(url)
    if not path or not string.match(path, "^/novel/") then return url end
    local bases = orderedBases()
    if bases[1] == SITE then return url end
    return bases[1] .. path
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SETTINGS
-- ═══════════════════════════════════════════════════════════════════════════

function getSettingsSchema()
    return {
        {
            key     = PREF_SITE,
            type    = "select",
            label   = "Source site",
            current = (function()
                local pref = get_preference(PREF_SITE)
                if pref == "box" then return "box" end
                if pref == "spot" then return "spot" end
                return "auto"
            end)(),
            options = {
                { value = "auto", label = "Smart switch — WuxiaBox first, auto-failover to WuxiaSpot (recommended)" },
                { value = "box",  label = "WuxiaBox only (www.wuxiabox.com)" },
                { value = "spot", label = "WuxiaSpot first (www.wuxiaspot.com) — manual mirror switch, WuxiaBox backup" },
            }
        },
        {
            key     = PREF_COVERS,
            type    = "select",
            label   = "Cover images",
            current = (function()
                local pref = get_preference(PREF_COVERS)
                if pref == "direct" then return "direct" end
                return "proxy"
            end)(),
            options = {
                { value = "proxy",  label = "Via wsrv.nl image proxy (recommended — fixes posters)" },
                { value = "direct", label = "Direct from wuxiabox.com (breaks when Cloudflare challenges images)" },
            }
        },
        {
            key     = PREF_RETRY,
            type    = "select",
            label   = "Chapter retries on 502 / error pages",
            current = tostring(getRetryCount()),
            options = {
                { value = "2", label = "2 attempts" },
                { value = "3", label = "3 attempts" },
                { value = "4", label = "4 attempts (recommended)" },
                { value = "5", label = "5 attempts" },
                { value = "6", label = "6 attempts" },
            }
        },
        {
            key     = PREF_PACE,
            type    = "select",
            label   = "Min gap between chapter requests (502 prevention)",
            current = tostring(getPaceMs()),
            options = {
                { value = "0",    label = "Off" },
                { value = "800",  label = "0.8 seconds" },
                { value = "1500", label = "1.5 seconds (recommended)" },
                { value = "2500", label = "2.5 seconds" },
                { value = "4000", label = "4 seconds" },
            }
        },
    }
end
