
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
    local cover = html_attr(body, "figure.cover img", "data-src")
    if cover == "" then cover = html_attr(body, "figure.cover img", "src") end
    if cover ~= "" then return absUrl(cover) end
    return nil
end

function getBookDescription(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return nil end
    local el = html_select_first(body, ".summary .content")
    if not el then return nil end
    local text = html_text(el.html)
    text = string_trim(text)
    if text == "" then return nil end
    -- The site often prepends a bracketed tag-soup line
    -- ("[Farming + Relaxed Entertainment + Traveling]") — keep it, it is
    -- part of the site's own synopsis presentation.
    return text
end

-- Genres = the site's Categories chips + the novel's Tags chips (the tags
-- are shown with their FULL names here, unlike /browsetags/ listings).
function getBookGenres(bookUrl)
    local body = fetchPage(bookUrl)
    if not body then return {} end
    local genres, seen = {}, {}
    for _, a in ipairs(html_select(body, ".categories a")) do
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
        local fyUrl = SITE .. "/e/extend/fy.php?page=" .. tostring(maxFy) ..
            "&wjm=" .. url_encode(slug)
        local frag = fetchPage(fyUrl)
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
        body = fetchPage(SITE .. "/e/extend/fy.php?page=" .. tostring(page - 1) ..
            "&wjm=" .. url_encode(slug))
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
        log_error("wuxiabox: error/interstitial page for " .. tostring(url) ..
            " — refetching with backoff")
        body = refetchChapterWithRetry(url)
    end
    if not body or isChapterErrorPage(body) then
        log_error("wuxiabox: chapter could not be loaded: " .. tostring(url))
        return ""
    end

    local cleaned = html_remove(body,
        "script", "style",
        ".ads", ".advertisement", ".chapternav", ".recommends")

    local el = html_select_first(cleaned, "#chapter-article .chapter-content")
    if not el then el = html_select_first(cleaned, ".chapter-content") end
    if not el then return "" end

    local text = html_text(el.html)
    text = stripTitleEcho(text, body)
    return applyStandardContentTransforms(text)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- SETTINGS
-- ═══════════════════════════════════════════════════════════════════════════

function getSettingsSchema()
    return {
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
