
-- ═══════════════════════════════════════════════════════════════════════════
-- List-page parsing + catalog browse
-- ═══════════════════════════════════════════════════════════════════════════

-- Every site list surface (category /sort/ /newest/ /sort_{cat}/ search
-- results) uses the same card markup:
--   .hd .list ul > li
--     .cover a            → href (book URL — EXACT site form) + img (cover)
--     .info .title strong a → title
--     .info .title .tips span → 作者：… / size / date
--     .descript a         → description snippet
-- Pagination widget: .page — <b>N</b> is the CURRENT page, plus links to
-- index_K.html pages, a 下一页 (next) link and a 尾页 (last) link. The 尾页
-- target is unreliable beyond the pager's window (live-verified: /jsls/
-- claims 尾页=30 while pages up to ~45 exist) — hasNext uses 下一页 only.
local function parseListCards(body)
  local items = {}
  if not body then return items end
  for _, li in ipairs(html_select(body, ".hd .list ul li")) do
    local href = html_attr(li.html, ".cover a", "href")
    local img  = html_attr(li.html, ".cover img", "src")
    local titleEl = html_select_first(li.html, ".title strong a")
    if titleEl and href and href ~= "" then
      items[#items + 1] = {
        title = string_clean(titleEl.text),
        url   = absUrl(href),
        cover = coverUrl(absUrl(img))
      }
    end
  end
  return items
end

-- hasNext from the pager's 下一页 link (exact; never trusts 尾页).
local function listHasNext(body)
  if not body then return false end
  for _, a in ipairs(html_select(body, ".page a")) do
    if a.text and string.find(a.text, "下一页") then return true end
  end
  return false
end

-- Batch-translate catalog item titles in place.
local function translateCatalogItems(items)
  if not trActive() or #items == 0 then return items end
  local titles = {}
  for i = 1, #items do titles[i] = items[i].title end
  local tr = translateBatch(titles)
  for i = 1, #items do items[i].title = tr[i] end
  return items
end

-- Build a list-page URL for a directory path ("" = site root of surface):
--   index 0 → /{path}/            (page 1 = bare directory)
--   index N → /{path}/index_{N+1}.html
local function listPagePath(path, index)
  if index <= 0 then return "/" .. path .. "/" end
  return "/" .. path .. "/index_" .. tostring(index + 1) .. ".html"
end

-- ── Filter state ─────────────────────────────────────────────────────────────
-- The app's filter UI cannot show/hide sections dynamically, so the Category
-- picker is always present and simply ignored by surfaces that don't use it.
local currentSurface = "newest"
local currentCategory = "dsyq"

local function surfacePath(surface, cat)
  if surface == "rank" then return "sort" end
  if surface == "catrank" then return "sort_" .. cat end
  if surface == "category" then return cat end
  return "newest"
end

function getCatalogList(index)
  currentSurface = "newest"
  local path = listPagePath("newest", index)
  local r = httpGetAny(path)
  if not (r and r.success) then
    if type(show_error) == "function" then
      show_error("Bixiange unreachable",
        "Could not load the latest list from www.bixiange.top or the bxg123.cc mirror. " ..
        "Check your connection and retry.")
    end
    return { items = {}, hasNext = false }
  end
  local items = parseListCards(r.body)
  translateCatalogItems(items)
  return { items = items, hasNext = listHasNext(r.body) }
end

function getCatalogFiltered(index, filters)
  local surface = (filters and filters.surface) or currentSurface or "newest"
  local cat     = (filters and filters.category) or currentCategory or "dsyq"
  currentSurface, currentCategory = surface, cat

  local path = listPagePath(surfacePath(surface, cat), index)
  local r = httpGetAny(path)
  if not (r and r.success) then
    if type(show_error) == "function" then
      show_error("Bixiange unreachable",
        "Could not load the list page from www.bixiange.top or the bxg123.cc mirror. " ..
        "Check your connection and retry.")
    end
    return { items = {}, hasNext = false }
  end
  local items = parseListCards(r.body)
  translateCatalogItems(items)
  return { items = items, hasNext = listHasNext(r.body) }
end

function getFilterList()
  local surfaces = {
    { value = "newest",   label = flLabel("Latest Updates", "最新更新") },
    { value = "rank",     label = flLabel("Overall Rankings", "总排行榜") },
    { value = "category", label = flLabel("By Category", "分类浏览") },
    { value = "catrank",  label = flLabel("Category Rankings", "分类排行榜") }
  }
  local catOptions = {}
  for _, c in ipairs(CATEGORIES) do
    catOptions[#catOptions + 1] = { value = c.value, label = flLabel(c.en, c.zh) }
  end
  return {
    {
      type = "select",
      key = "surface",
      label = "Browse",
      options = surfaces
    },
    {
      type = "select",
      key = "category",
      label = "Category (分类)",
      options = catOptions
    }
  }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Search (EmpireCMS GBK POST + searchid pagination)
-- ═══════════════════════════════════════════════════════════════════════════
-- POST /e/search/indexpage.php with keyboard percent-encoded as GBK bytes
-- → 302 Location: result/?searchid=S (RELATIVE to /e/search/)
-- → GET /e/search/result/?searchid=S          (page 1, 20 items)
--   GET /e/search/result/index.php?page=K&searchid=S  (0-based: K=1 → page 2)
-- Total count: <a title="总数"><b>N</b></a>. Zero results: a 200 page titled
-- 信息提示 with no cards. The mirror shares the SAME searchids (live-verified:
-- both hosts return searchid 7735027 for the same query) — pagination may use
-- any base.

-- searchid cache per query for the lifetime of one engine run
local _searchIdByQuery = {}
local SEARCH_PAGE_SIZE = 20

-- GBK-percent-encode a query for the EmpireCMS form. url_encode_charset is
-- pcall-guarded: on builds where it is missing, fall back to UTF-8 url_encode
-- (the search will not match, but the caller surfaces a readable error).
local function gbkEncodeQuery(query)
  local ok, enc = pcall(url_encode_charset, query, "GBK")
  if ok and type(enc) == "string" and enc ~= "" then return enc, true end
  return url_encode(query), false
end

-- POST the search form on one base; returns response table (302 included).
local function postSearch(base, query)
  local enc = gbkEncodeQuery(query)
  local form = "keyboard=" .. enc .. "&show=title&classid=0"
  return http_post(base .. "/e/search/indexpage.php", form, {
    headers = {
      ["Content-Type"] = "application/x-www-form-urlencoded",
      ["Referer"] = base .. "/",
      ["Accept"]   = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    },
    charset = "GBK"
  })
end

local function extractSearchId(body)
  if type(body) ~= "string" then return nil end
  return string.match(body, "searchid=(%d+)")
end

-- Zero-result interstitial detection: the 信息提示 page has no cards and no
-- searchid; a real result page has cards or a searchid in its pager.
local function hasSearchResults(body)
  if type(body) ~= "string" then return false end
  if #html_select(body, ".hd .list ul li") > 0 then return true end
  return extractSearchId(body) ~= nil
end

-- Total results from `<a title="总数">&nbsp;<b>N</b></a>` (the &nbsp; between
-- the anchor text and the <b> defeats %s-based patterns — use a lazy match on
-- a single line; nil when absent).
local function searchTotal(body)
  if type(body) ~= "string" then return nil end
  return tonumber(string.match(body, 'title="总数".-<b>(%d+)</b>'))
end

function getCatalogSearch(index, query)
  if type(query) ~= "string" or query == "" then
    return { items = {}, hasNext = false }
  end

  -- Translate non-Chinese queries to Simplified Chinese (the site's index
  -- is zh-CN; a raw English query returns nothing).
  local q = query
  if not hasCJK(q) then
    local tq = translateQueryToZh(q, "auto")
    if tq then q = tq end
  end

  -- Page 1: run the search (POST → 302 → result page).
  -- NOTE: NoveLA marks 3xx responses success=false (isSuccessful), so the
  -- redirect branch must check r.code WITHOUT requiring r.success.
  if index <= 0 then
    local body = nil
    for _, base in ipairs(orderedBases()) do
      local r = postSearch(base, q)
      if r then
        local code = tonumber(r.code) or 0
        if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
          local loc = readHeader(r, "location")
          if type(loc) == "string" and loc ~= "" then
            local next_
            if string_starts_with(loc, "http") then
              next_ = loc
            elseif string_starts_with(loc, "/") then
              next_ = base .. loc
            else
              -- EmpireCMS Location "result/?searchid=S" is relative to /e/search/
              next_ = base .. "/e/search/" .. loc
            end
            local rr = followRedirects(httpGetRaw(base, next_), next_)
            if rr and rr.success then body = rr.body end
          end
        elseif r.success then
          -- 200 = result page served directly, or the 信息提示 zero-result page
          body = r.body
        end
      end
      if body then break end
    end

    if not body then
      if type(show_error) == "function" then
        show_error("Bixiange search unreachable",
          "The search could not run on www.bixiange.top or the bxg123.cc mirror. " ..
          "Check your connection and retry.")
      end
      return { items = {}, hasNext = false }
    end

    local sid = extractSearchId(body)
    if sid then _searchIdByQuery[q] = sid end

    if not hasSearchResults(body) then
      return { items = {}, hasNext = false } -- definitive zero results
    end

    local items = parseListCards(body)
    translateCatalogItems(items)
    local total = searchTotal(body)
    local hasNext = false
    if total then
      hasNext = total > SEARCH_PAGE_SIZE
    else
      hasNext = listHasNext(body)
    end
    return { items = items, hasNext = hasNext }
  end

  -- Pages 2+: paginate the stored searchid (0-based page param).
  local sid = _searchIdByQuery[q]
  if not sid then
    return { items = {}, hasNext = false } -- no search session → stop
  end
  local path = "/e/search/result/index.php?page=" .. tostring(index) .. "&searchid=" .. sid
  local r = httpGetAny(path)
  if not (r and r.success) then
    return { items = {}, hasNext = false }
  end
  local items = parseListCards(r.body)
  translateCatalogItems(items)
  local total = searchTotal(r.body)
  local hasNext = false
  if total then
    hasNext = total > (index + 1) * SEARCH_PAGE_SIZE
  else
    hasNext = listHasNext(r.body)
  end
  return { items = items, hasNext = hasNext }
end
