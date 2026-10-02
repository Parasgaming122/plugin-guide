#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Splice wuxiabox.lua v2.2.0 -> v2.3.0 (SMART MIRROR SWITCHER).

Changes:
  1. Header: 2.3.0 changelog block + version strings.
  2. Health tracker (persistent circuit breaker) + orderedBases() + junk-body
     detectors, inserted after siteBases().
  3. httpGetAny / httpGetPrimary: health-aware, junk-gated, 404-neutral.
  4. refetchChapterWithRetry: smart attempt order, no pre-sleep, 404 exemption.
  5. runSearch: orderedBases + per-query base memory (_searchBaseByQuery).
  6. getCatalogSearch: searchid pages served by the search's OWN base.
  7. getChapterText: engine's junk doc charges SITE health; total failure
     raises a clear error instead of returning "".
  8. transformChapterUrl: forward-compatible hook for patched engines.
  9. Settings: relabelled site options (smart switch).
"""
import sys

PATH = "/home/z/my-project/download/wuxiabox.lua"

with open(PATH, "r", encoding="utf-8") as f:
    src = f.read()

def replace_once(text, old, new, what):
    n = text.count(old)
    if n != 1:
        print(f"ANCHOR FAIL ({what}): {n} occurrences", file=sys.stderr)
        sys.exit(1)
    return text.replace(old, new, 1)

def replace_span(text, start_marker, end_marker, new, what, keep_end=True):
    i = text.find(start_marker)
    if i < 0:
        print(f"SPAN START FAIL ({what})", file=sys.stderr)
        sys.exit(1)
    if text.find(start_marker, i + 1) >= 0:
        print(f"SPAN START NOT UNIQUE ({what})", file=sys.stderr)
        sys.exit(1)
    j = text.find(end_marker, i)
    if j < 0:
        print(f"SPAN END FAIL ({what})", file=sys.stderr)
        sys.exit(1)
    if keep_end:
        return text[:i] + new + text[j:]
    return text[:i] + new + text[j + len(end_marker):]

# ── 1a. header line ─────────────────────────────────────────────────────────
src = replace_once(
    src,
    "-- File: en/wuxiabox.lua — Version 2.2.0 (2026-09-18)",
    "-- File: en/wuxiabox.lua — Version 2.3.0 (2026-09-19)",
    "header line")

# ── 1b. 2.3.0 changelog block ───────────────────────────────────────────────
CHANGELOG_230 = """--
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
"""
src = replace_once(
    src,
    "--\n-- 2.2.0 (2026-09-18) — POSTER FIX, SEARCH PAGINATION, TAG CURATION.",
    CHANGELOG_230 + "--\n-- 2.2.0 (2026-09-18) — POSTER FIX, SEARCH PAGINATION, TAG CURATION.",
    "changelog insert")

# ── 1c. metadata version ────────────────────────────────────────────────────
src = replace_once(
    src,
    'version  = "2.2.0"',
    'version  = "2.3.0"',
    "metadata version")

# ── 2. health tracker + orderedBases + junk detectors ───────────────────────
HEALTH_BLOCK = """
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
"""

old_fetchers = """-- GET {path} on the preferred site, transparently retrying on the
-- mirror when the request fails (network error / CF / 5xx). Returns the
-- LAST response table plus the base that served it (nil when all failed).
--
-- MIRROR PORTABILITY (verified live 2026-09-16): the two sites share
-- novel slugs, chapter URLs, fy.php fragments, search keywords and most
-- category slugs — but their TAG ID SPACES ARE COMPLETELY DIFFERENT
-- (wuxiabox "Rebirth" = 139, wuxiaspot "Rebirth" = 682; wuxiabox id 682
-- is "Saving the World"). A tag listing fetched from the wrong site would
-- silently browse the WRONG TAG, so tag URLs must use httpGetPrimary.
local function httpGetAny(path, headers)
    local last
    for _, base in ipairs(siteBases()) do
        local r
        if headers then
            r = http_get(base .. path, { headers = headers })
        else
            r = http_get(base .. path)
        end
        if r.success then return r, base end
        last = r
    end
    return last, nil
end

-- Primary-site-only GET — for URLs whose meaning is site-specific
-- (tag listings: the mirror's tag ids point at different tags).
local function httpGetPrimary(path, headers)
    local r
    if headers then
        r = http_get(SITE .. path, { headers = headers })
    else
        r = http_get(SITE .. path)
    end
    return r, (r and r.success) and SITE or nil
end
"""

new_fetchers = HEALTH_BLOCK + """
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
"""

src = replace_once(src, old_fetchers, new_fetchers, "httpGetAny/httpGetPrimary block")

# ── 3. refetchChapterWithRetry ──────────────────────────────────────────────
old_refetch = """-- Refetch a chapter URL with exponential backoff + jitter, alternating
-- WuxiaBox → WuxiaSpot across attempts (the mirror rides out CF / 502
-- flaps on the primary). Every attempt goes through the app's OkHttp
-- stack, so the CloudfareVerification interceptor keeps working
-- (challenges → WebView bypass → retry).
local function refetchChapterWithRetry(chapterUrl)
    local attempts = getRetryCount()
    local bases = siteBases()
    local novelUrl = chapterToNovelUrl(chapterUrl)
    local path = urlToPath(chapterUrl) or chapterUrl
    for attempt = 1, attempts do
        if attempt > 1 then
            local waitMs = 900 * attempt * attempt + math.random(0, 400)
            sleep(waitMs)
        else
            sleep(700 + math.random(0, 300)) -- brief pause before the first retry
        end
        -- alternate the site per attempt: box, spot, box, spot, …
        local base = bases[1 + ((attempt - 1) % #bases)]
        local r = http_get(base .. path, {
            headers = {
                ["Referer"] = base .. "/novel/" .. (novelSlug(chapterUrl) or "") .. ".html",
                ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            }
        })
        if r.success and not isChapterErrorPage(r.body) then
            log_info("wuxiabox: chapter refetch succeeded on attempt " .. attempt ..
                " (" .. (string.match(base, "^https?://([^/]+)") or "?") .. "): " .. chapterUrl)
            return r.body
        end
        log_error("wuxiabox: chapter fetch attempt " .. attempt .. "/" .. attempts ..
            " failed (code " .. tostring(r.code) .. "): " .. base .. path)
    end
    return nil
end
"""

new_refetch = """-- Refetch a chapter URL with exponential backoff + jitter (2.3.0: smart
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
"""

src = replace_once(src, old_refetch, new_refetch, "refetchChapterWithRetry")

# ── 4. runSearch with per-query base memory ─────────────────────────────────
old_runsearch = """local function runSearch(query)
    query = string_trim(query or "")
    if query == "" then return nil end
    for _, base in ipairs(siteBases()) do
        local body = runSearchOn(base, query)
        if body then return body end
    end
    return nil
end
"""

new_runsearch = """-- searchid pages are site-specific (an id created by wuxiabox.com's
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
"""

src = replace_once(src, old_runsearch, new_runsearch, "runSearch")

# ── 5. getCatalogSearch: searchid pages from the search's OWN base ──────────
old_search_tail = """    local sid = _searchIdByQuery[query]
    if not sid then
        -- engine asked for a later page without page 0 in this run
        local body = runSearch(query)
        if not body then return { items = {}, hasNext = false } end
        sid = extractSearchId(body)
        _searchIdByQuery[query] = sid
    end
    if not sid then return { items = {}, hasNext = false } end

    local path = "/e/search/result/index.php?page=" .. tostring(index) ..
        "&searchid=" .. sid
    -- PRIMARY-ONLY, like tag listings: a searchid is an entry in THIS site's
    -- EmpireCMS search table — the mirror's searchid space is completely
    -- different, so a mirror fallback here would serve an unrelated (or
    -- empty) result page and silently kill pagination (the app treats an
    -- empty page as "no more results"). v2.1.0 used httpGetAny here — a
    -- transient primary hiccup (502/CF check) meant ONE page shown and the
    -- scroll feed ending forever.
    local r = httpGetPrimary(path)
    if not r or not r.success then
        -- one retry with a FRESH search (new searchid) before giving up
        local body = runSearch(query)
        if body then
            local freshSid = extractSearchId(body)
            if freshSid then
                _searchIdByQuery[query] = freshSid
                local r2 = httpGetPrimary("/e/search/result/index.php?page=" ..
                    tostring(index) .. "&searchid=" .. freshSid)
                if r2 and r2.success then
                    local it = parseNovelCards(r2.body, false)
                    return { items = it, hasNext = searchHasNext(r2.body, index + 1, freshSid) }
                end
            end
        end
        -- surface as a RETRYABLE app error (the reader keeps loaded pages;
        -- retry re-runs this index) instead of silently ending pagination
        error("WuxiaBox: search page " .. (index + 1) .. " could not be loaded " ..
            "from wuxiabox.com. If a Cloudflare check appeared, solve it and " ..
            "tap retry.")
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
"""

new_search_tail = """    local sid = _searchIdByQuery[query]
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
"""

src = replace_once(src, old_search_tail, new_search_tail, "getCatalogSearch tail")

# ── 6. getChapterText: charge engine junk to SITE + clear error ─────────────
old_chaptertext_head = """function getChapterText(html, url)
    -- Pacing floor between chapter requests (default 1500 ms; setting).
    chapterPacing()

    local body = html
    if isChapterErrorPage(body) then
        log_error("wuxiabox: error/interstitial page for " .. tostring(url) ..
            " — refetching with backoff")
        body = refetchChapterWithRetry(url)
    end
    if not body or isChapterErrorPage(body) then
        log_error("wuxiabox: chapter could not be loaded: " .. tostring(url))
        return ""
    end
"""

new_chaptertext_head = """function getChapterText(html, url)
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
"""

src = replace_once(src, old_chaptertext_head, new_chaptertext_head,
                   "getChapterText head")

# ── 7. transformChapterUrl hook (before the SETTINGS banner) ────────────────
SETTINGS_BANNER = """-- ═══════════════════════════════════════════════════════════════════════════
-- SETTINGS
-- ═══════════════════════════════════════════════════════════════════════════
"""

TRANSFORM_HOOK = """-- ═══════════════════════════════════════════════════════════════════════════
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

"""

src = replace_once(src, SETTINGS_BANNER, TRANSFORM_HOOK + SETTINGS_BANNER,
                   "transformChapterUrl insert")

# ── 8. settings labels ──────────────────────────────────────────────────────
src = replace_once(
    src,
    """            options = {
                { value = "auto", label = "WuxiaBox → WuxiaSpot fallback (recommended)" },
                { value = "box",  label = "WuxiaBox only (www.wuxiabox.com)" },
                { value = "spot", label = "WuxiaSpot first (www.wuxiaspot.com), WuxiaBox backup" },
            }""",
    """            options = {
                { value = "auto", label = "Smart switch — WuxiaBox first, auto-failover to WuxiaSpot (recommended)" },
                { value = "box",  label = "WuxiaBox only (www.wuxiabox.com)" },
                { value = "spot", label = "WuxiaSpot first (www.wuxiaspot.com) — manual mirror switch, WuxiaBox backup" },
            }""",
    "settings labels")

with open(PATH, "w", encoding="utf-8") as f:
    f.write(src)

lines = src.count("\n") + 1
print(f"OK — spliced to v2.3.0: {lines} lines, {len(src.encode('utf-8'))} bytes")
