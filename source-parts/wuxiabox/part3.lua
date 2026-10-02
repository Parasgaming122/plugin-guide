
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
                items[#items + 1] = { title = title, url = url, cover = absUrl(cover) }
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
    return tonumber(string.match(body, '<ul class="pagination">.-<b>(%d+)</b>'))
end

-- ── Catalog (default browse: Most Popular) ──────────────────────────────────

function getCatalogList(index)
    local page = index
    local url = SITE .. "/list/all/all-onclick-" .. tostring(page) .. ".html"
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
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

-- Follow up to 3 manual redirect hops (NoveLA's OkHttp client does not
-- follow redirects for plugin calls by default).
local function followRedirects(r)
    local hops = 0
    while hops < 3 do
        local code = tonumber(r.code) or 0
        if code ~= 301 and code ~= 302 and code ~= 303 and code ~= 307 and code ~= 308 then
            return r
        end
        local loc = headerFirst(r.headers, "location")
        if not loc then return r end
        r = http_get(absUrl(loc))
        hops = hops + 1
    end
    return r
end

-- POST the site's own search form; on failure fall back to the GET
-- searchget=1 variant. Returns the RESULT page body (or nil).
local function runSearch(query)
    local form = "show=title&tempid=1&tbname=news&keyboard=" .. url_encode(query)
    local r = http_post(SITE .. "/e/search/index.php", form, {
        headers = {
            ["Referer"] = SITE .. "/search.html",
            ["Origin"]  = SITE,
            ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        }
    })
    r = followRedirects(r)
    if r.success and extractSearchId(r.body) then return r.body end

    -- Fallback: EmpireCMS GET search (verified live: redirects to the
    -- same /e/search/result?searchid=N page).
    local getUrl = SITE .. "/e/search/?searchget=1&keyboard=" .. url_encode(query) ..
        "&show=title&tbname=news&tempid=1"
    local g = http_get(getUrl, { headers = { ["Referer"] = SITE .. "/search.html" } })
    g = followRedirects(g)
    if g.success and extractSearchId(g.body) then return g.body end

    return nil
end

function getCatalogSearch(index, query)
    if index == 0 then
        local body = runSearch(query)
        if not body then return { items = {}, hasNext = false } end
        _searchIdByQuery[query] = extractSearchId(body)
        local items = parseNovelCards(body, false)
        local hasNext = hasNextByLink(body, "page=1&searchid=")
        local total = listTotal(body)
        if total and 1 * 20 < total then hasNext = true end
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

    local url = SITE .. "/e/search/result/index.php?page=" .. tostring(index) ..
        "&searchid=" .. sid
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local items = parseNovelCards(r.body, false)
    local hasNext = hasNextByLink(r.body, "page=" .. tostring(index + 1) .. "&searchid=")
    local total = listTotal(r.body)
    if total and (index + 1) * 20 < total then hasNext = true end
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

local TAG_LETTERS = {
    { value = "",  label = "All" },
    { value = "A", label = "A" }, { value = "B", label = "B" },
    { value = "C", label = "C" }, { value = "D", label = "D" },
    { value = "E", label = "E" }, { value = "F", label = "F" },
    { value = "G", label = "G" }, { value = "H", label = "H" },
    { value = "I", label = "I" }, { value = "J", label = "J" },
    { value = "K", label = "K" }, { value = "L", label = "L" },
    { value = "M", label = "M" }, { value = "N", label = "N" },
    { value = "O", label = "O" }, { value = "P", label = "P" },
    { value = "Q", label = "Q" }, { value = "R", label = "R" },
    { value = "S", label = "S" }, { value = "T", label = "T" },
    { value = "U", label = "U" }, { value = "V", label = "V" },
    { value = "W", label = "W" }, { value = "X", label = "X" },
    { value = "Y", label = "Y" }, { value = "Z", label = "Z" },
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
            type         = "text",
            key          = "tag_search",
            label        = "Tag Search (keyword — shows every matching tag)",
            defaultValue = "",
        },
        {
            type         = "select",
            key          = "tag_letter",
            label        = "Tag Search Category (first letter)",
            defaultValue = "",
            options      = TAG_LETTERS,
        },
    }
end

-- Tag listing URL for result page `index` (0-based).
--   page 0 → /tags/{id}-0.html            (500 items on one page)
--   page N → /e/tags/index.php?page=N&tagid={id}&line=500&tempid=9
local function tagListingUrl(tagId, index)
    if index <= 0 then
        return SITE .. "/tags/" .. tagId .. "-0.html"
    end
    return SITE .. "/e/tags/index.php?page=" .. tostring(index) ..
        "&tagid=" .. tagId .. "&line=500&tempid=9"
end

-- Browse ONE tag listing at page `index`. hasNext: next-page link in the
-- pager, with a grand-total fallback (500 items per tag page).
local function browseTag(tagId, index)
    local url = tagListingUrl(tagId, index)
    browsePacing(400)
    local r = http_get(url)
    if not r.success then return {}, false end
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
    local tagQuery  = filters["tag_search"] or ""
    local tagLetter = filters["tag_letter"] or ""

    -- ── Tag Search: takes priority (the site cannot combine a tag listing
    -- with category/status/sort — documented in the plugin header).
    if tagQuery ~= "" then
        local ok, tagIds = pcall(tagSearchResolve, tagQuery, tagLetter)
        if not ok then error(tostring(tagIds)) end
        if #tagIds == 0 then return { items = {}, hasNext = false } end
        local items, hasNext = browseTagUnion(tagIds, index)
        return { items = items, hasNext = hasNext }
    end

    -- ── Updates mode (ignores category/status/sort)
    if browse == "updates" then
        local url
        if index <= 0 then
            url = SITE .. "/updates/"
        else
            url = SITE .. "/updates/" .. tostring(index) .. ".html"
        end
        local r = http_get(url)
        if not r.success then return { items = {}, hasNext = false } end
        -- cards link to the LATEST chapter → rewrite to the novel page
        local items = parseNovelCards(r.body, true)
        local hasNext = hasNextByLink(r.body, "/updates/" .. tostring(index + 1) .. ".html")
        return { items = items, hasNext = hasNext }
    end

    -- ── Categories mode
    local url = SITE .. "/list/" .. url_encode(category) .. "/" ..
        url_encode(status) .. "-" .. url_encode(sort) .. "-" .. tostring(index) .. ".html"
    local r = http_get(url)
    if not r.success then return { items = {}, hasNext = false } end
    local items = parseNovelCards(r.body, false)
    local hasNext = hasNextByLink(r.body, "-" .. tostring(index + 1) .. ".html")
    return { items = items, hasNext = hasNext }
end
