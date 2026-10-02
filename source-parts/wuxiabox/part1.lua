-- ═══════════════════════════════════════════════════════════════════════════
-- WuxiaBox source plugin for NoveLA  (https://www.wuxiabox.com)
-- File: en/wuxiaworld_site.lua — Version 2.0.0 (2026-09-14)
--
-- 2.0.0 (2026-09-14) — FULL REWRITE: the source now targets WuxiaBox
--     (wuxiabox.com) instead of WuxiaWorld.site. The two are completely
--     different platforms (WuxiaWorld.site = WordPress/Madara; WuxiaBox =
--     EmpireCMS "Web Novels MTL" family), so every function was rewritten
--     and re-verified against live pages. The source id/file slot is kept
--     ("wuxia_world_site") so existing installs update in place; note that
--     books saved from the old wuxiaworld.site URLs do NOT carry over.
--
--   WHAT'S NEW
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
--     Tag Search Category = A-Z letter scope (the site groups tags by
--     first letter on /browsetags/).
--   • Full filter parity with the site's "Categories" browser:
--     57 categories × status (All/Completed/Ongoing) × sort
--     (Newest Added / Last Updated / Most Viewed), plus an "Updates"
--     browse mode (recently updated novels, /updates/).
--   • Improved search: the site's search is an EmpireCMS POST form
--     (/e/search/index.php, fields show=title&tempid=1&tbname=news&
--     keyboard=…) that 302-redirects to /e/search/result?searchid=N.
--     NoveLA's http_post does NOT follow redirects, so the old-style
--     "POST and parse" never worked here — the plugin now follows the
--     redirect chain manually (Location header, up to 3 hops), falls
--     back to the GET searchget=1 variant, and supports result
--     pagination (/e/search/result/index.php?page=N&searchid=S,
--     20 items/page, total count parsed from the pager).
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
--                        .categories → a.property-item (genres) + a.tag (tags, full names)
--                        #info → .summary .content (description) · .tags ul.content (tag chips)
--   • Chapter list      novel page (chapters 1-100, ascending) +
--                        /e/extend/fy.php?page={N-1}&wjm={slug} fragments (100/page)
--   • Chapter page      GET  /novel/{slug}_{n}.html → #chapter-article .chapter-content
--                        (.titles h1 = novel title link, h2 = chapter title)
--
--   NOTES / LIMITS
--   • wuxiabox.com sits behind a Cloudflare managed challenge. NoveLA's
--     CloudfareVerificationInterceptor already auto-solves challenges via
--     the integrated WebView for every plugin http_get/http_post — do NOT
--     add cf_options (see wtrlab.lua docs; whitelist=true disables the
--     recovery path).
--   • The origin behind Cloudflare intermittently returns 502/504 —
--     that is what the in-plugin chapter retry + pacing address. The app
--     also issues two HTTP hits per chapter (one URL-resolve pass + one
--     document fetch in DownloaderRepository.bookChapter), which makes
--     the pacing floor all the more useful.
--   • Tag exclusion is NOT offered: the site cannot exclude tags via any
--     URL, and novel cards do not carry their tag list, so client-side
--     exclusion would require fetching every novel page.
--   • The site has no numeric ratings; getBookRating is intentionally
--     not implemented.
--   • Tag labels in /browsetags/ are truncated to 10 chars by the site
--     itself (AncientChi, AdaptedtoM…). The build script expands them to
--     full spaced names when the prefix is unambiguous; the in-plugin
--     search is space-insensitive regardless.
--
--   TAG INDEX MAINTENANCE: regenerate with
--     scripts/build_wuxiabox_tag_index.py  (harvest → dedup → name
--     expansion → splice into TAG_SEARCH_INDEX below). See
--     WUXIABOX_PLUGIN.md for the full pipeline.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Metadata ────────────────────────────────────────────────────────────────
id       = "wuxia_world_site"
name     = "WuxiaBox"
version  = "2.0.0"
baseUrl  = "https://www.wuxiabox.com"
language = "en"
icon     = "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/icons/wuxiaworld.site.png"

local SITE = baseUrl

-- ── Settings keys ───────────────────────────────────────────────────────────
local PREF_RETRY = "wuxiabox_chapter_retries"
local PREF_PACE  = "wuxiabox_chapter_pace_ms"

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

-- ── Small helpers ───────────────────────────────────────────────────────────

local function absUrl(href)
    if not href or href == "" then return "" end
    if string_starts_with(href, "http") then return href end
    if string_starts_with(href, "//") then return "https:" .. href end
    return url_resolve(SITE, href)
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
-- parallel). fy.php fragment fetches are cached here too.

local _pageCache = {}

local function fetchPage(url)
    if _pageCache[url] then return _pageCache[url] end
    local r = http_get(url)
    if r.success then
        _pageCache[url] = r.body
        return r.body
    end
    return nil
end

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

-- Refetch a chapter URL with exponential backoff + jitter. Every attempt
-- goes through the app's OkHttp stack, so the CloudfareVerification
-- interceptor keeps working (challenges → WebView bypass → retry).
local function refetchChapterWithRetry(chapterUrl)
    local attempts = getRetryCount()
    local novelUrl = chapterToNovelUrl(chapterUrl)
    for attempt = 1, attempts do
        if attempt > 1 then
            local waitMs = 900 * attempt * attempt + math.random(0, 400)
            sleep(waitMs)
        else
            sleep(700 + math.random(0, 300)) -- brief pause before the first retry
        end
        local r = http_get(chapterUrl, {
            headers = {
                ["Referer"] = novelUrl,
                ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            }
        })
        if r.success and not isChapterErrorPage(r.body) then
            log_info("wuxiabox: chapter refetch succeeded on attempt " .. attempt .. ": " .. chapterUrl)
            return r.body
        end
        log_error("wuxiabox: chapter fetch attempt " .. attempt .. "/" .. attempts ..
            " failed (code " .. tostring(r.code) .. "): " .. chapterUrl)
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
    text = regex_replace(text, "(?i)\\A[\\s\\p{Z}\\uFEFF]*((Chapter\\s+\\d+)[^\\n\\r]*[\\n\\r\\s]*)+", "")
    text = regex_replace(text, "(?im)^\\s*(Translator|Editor|Proofreader|Read\\s+(at|on|latest))[:\\s][^\\n\\r]{0,70}(\\r?\\n|$)", "")
    -- Site-specific: the chapter body repeats the novel title / Author /
    -- Synopsis echo lines at the top of every chapter.
    text = regex_replace(text, "(?im)^\\s*(Author|Synopsis|P\\.?S\\.?)[:\\s][^\\n\\r]{0,160}(\\r?\\n|$)", "")
    text = string_trim(text)
    return text
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
