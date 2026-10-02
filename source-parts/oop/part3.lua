
-- ═══════════════════════════════════════════════════════════════════════════
-- List-page parsing + catalog browse
-- ═══════════════════════════════════════════════════════════════════════════
-- /sort/ and /search/ share the card markup:
--   .book-card / .result-item
--     .book-cover a            → book URL + img (src / data-original)
--     .book-status             → "男頻/ 連載" / "短篇/ 全本"
--     .book-info .book-title a → title (search adds .highlight spans — text
--                                concatenation handles them)
--     .book-intro              → description snippet
--     .book-meta .book-author  → author
--     .book-stats              → word count / update time
-- Pagination (.pagination): <strong>N</strong> = current page; the >> link is
-- NEXT (href=/sort/{N+1}/); a javascript:void(0) >> means no next page.

local function parseListCards(body)
  local items = {}
  if not body then return items end
  local cards = html_select(body, ".books-grid .book-card")
  if #cards == 0 then cards = html_select(body, ".search-results .result-item") end
  for _, card in ipairs(cards) do
    local href = html_attr(card.html, ".book-cover a", "href")
    local img  = html_attr(card.html, ".book-cover img", "src")
    local dimg = html_attr(card.html, ".book-cover img", "data-original")
    if dimg and dimg ~= "" then img = dimg end -- lazy-load attribute
    local titleEl = html_select_first(card.html, ".book-title a")
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

-- hasNext from the pager's >> link (href ≠ javascript:).
local function listHasNext(body)
  if not body then return false end
  for _, a in ipairs(html_select(body, ".pagination a")) do
    local t = a.text or ""
    if string.find(t, ">>") or string.find(t, "&gt;&gt;") then
      local href = a.href or ""
      if string.find(href, "javascript") == nil then return true end
    end
  end
  return false
end

local function translateCatalogItems(items)
  if not trActive() or #items == 0 then return items end
  local titles = {}
  for i = 1, #items do titles[i] = items[i].title end
  local tr = translateBatch(titles)
  for i = 1, #items do items[i].title = tr[i] end
  return items
end

-- ── Catalog ──────────────────────────────────────────────────────────────────
-- Default surface: the full 书库 (all books, newest-updated first):
--   index 0 → /sort/            (page 1)
--   index N → /sort/{N+1}/      (pages are 1-based in the URL)
-- Filtered: /sort/{cat}/{page}/ — same 1-based paging.

function getCatalogList(index)
  local path = "/sort/"
  if index > 0 then path = "/sort/" .. tostring(index + 1) .. "/" end
  local r = httpGetPage(path)
  if not (r and r.success) then
    if type(show_error) == "function" then
      show_error("oop.tw unreachable",
        "Could not load the library from www.oop.tw. The site sits behind " ..
        "Cloudflare — if a challenge appears, solve it once in the WebView " ..
        "and retry.")
    end
    return { items = {}, hasNext = false }
  end
  local items = parseListCards(r.body)
  translateCatalogItems(items)
  return { items = items, hasNext = listHasNext(r.body) }
end

function getCatalogFiltered(index, filters)
  local cat = filters and filters.category
  local path
  if cat and cat ~= "" and cat ~= "all" then
    path = "/sort/" .. cat .. "/" .. tostring(index + 1) .. "/"
  else
    path = "/sort/"
    if index > 0 then path = "/sort/" .. tostring(index + 1) .. "/" end
  end
  local r = httpGetPage(path)
  if not (r and r.success) then
    if type(show_error) == "function" then
      show_error("oop.tw unreachable",
        "Could not load the category from www.oop.tw. The site sits behind " ..
        "Cloudflare — if a challenge appears, solve it once in the WebView " ..
        "and retry.")
    end
    return { items = {}, hasNext = false }
  end
  local items = parseListCards(r.body)
  translateCatalogItems(items)
  return { items = items, hasNext = listHasNext(r.body) }
end

function getFilterList()
  local catOptions = { { value = "all", label = flLabel("All Books", "全部小說") } }
  for _, c in ipairs(CATEGORIES) do
    catOptions[#catOptions + 1] = { value = c.value, label = flLabel(c.en, c.zh) }
  end
  return {
    {
      type = "select",
      key = "category",
      label = "Category (分類)",
      options = catOptions
    }
  }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Search — GET /search/?searchkey={q}&searchtype=all (one page, ≤100 results)
-- ═══════════════════════════════════════════════════════════════════════════

function getCatalogSearch(index, query)
  if type(query) ~= "string" or query == "" or index > 0 then
    return { items = {}, hasNext = false }
  end

  local q = query
  if not hasCJK(q) then
    local tq = translateQueryToZhTw(q, "auto")
    if tq then q = tq end
  end

  local r = http_get(SITE .. "/search/?searchkey=" .. url_encode(q) .. "&searchtype=all", {
    headers = {
      ["Referer"] = SITE .. "/",
      ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    }
  })
  if not (r and r.success) then
    if type(show_error) == "function" then
      show_error("Search unreachable",
        "The search could not run on www.oop.tw. The site sits behind " ..
        "Cloudflare — if a challenge appears, solve it once in the WebView " ..
        "and retry.")
    end
    return { items = {}, hasNext = false }
  end

  local items = parseListCards(r.body)
  translateCatalogItems(items)
  -- No pager on search pages (≤100 results, single page — verified live).
  return { items = items, hasNext = false }
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Book details
-- ═══════════════════════════════════════════════════════════════════════════
-- Book page /abooka/a{id}a/:
--   .novel-main .novel-cover img      → cover
--   h1.novel-title                    → title
--   .novel-info .novel-meta (1st)     → .meta-tag: category, word count,
--                                       全本/連載 status (tag.full), rating
--   .novel-info .novel-meta (2nd)     → 關鍵字 tags → genres
--   .latest-chapter .update-time      → last update (YYYY-MM-DD)
--   #info-content .intro p            → description
--   #catalog-content .chap-pager select option → catalog pages (?p=N)
--   #ul_all_chapters li.chapter-item a → chapters (30/page)

local function parseBookMeta(body)
  local out = {}
  local metas = html_select(body, ".novel-info .novel-meta")
  local first = metas[1]
  if first then
    for _, tag in ipairs(html_select(first.html, ".meta-tag")) do
      local t = string_clean(tag.text or "")
      if t ~= "" then out.metaTags = out.metaTags or {}; out.metaTags[#out.metaTags + 1] = t end
      if t == "全本" or t == "完結" then out.status = "全本" end
      if t == "連載" or t == "连载" then out.status = "連載" end
      local rating = string.match(t, "(%d+%.%d)分")
      if rating then out.rating = rating end
    end
  end
  local second = metas[2]
  if second then
    out.genres = {}
    for _, tag in ipairs(html_select(second.html, ".meta-tag")) do
      local t = string_clean(tag.text or "")
      if t ~= "" then out.genres[#out.genres + 1] = t end
    end
  end
  return out
end

function getBookTitle(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local el = html_select_first(r.body, "h1.novel-title")
  if not el then return nil end
  local title = string_clean(el.text)
  if title == "" then return nil end
  if trActive() then
    local tr = translateOne(title)
    if tr ~= title then return tr .. " (" .. title .. ")" end
  end
  return title
end

function getBookCoverImageUrl(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local src = html_attr(r.body, ".novel-cover img", "src")
  if not src or src == "" then
    src = html_attr(r.body, ".novel-cover img", "data-original")
  end
  if not src or src == "" then return nil end
  return coverUrl(absUrl(src))
end

function getBookDescription(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local el = html_select_first(r.body, ".intro")
  local desc = el and string_clean(el.text) or ""
  local meta = parseBookMeta(r.body)
  local header = ""
  if meta.genres and #meta.genres > 0 then
    header = "关键字：" .. table.concat(meta.genres, " / ") .. "\n\n"
  end
  if desc == "" and header == "" then return nil end
  desc = header .. desc
  if #desc > 4000 then desc = string.sub(desc, 1, 4000) end
  if trActive() then desc = translateOne(desc) end
  return desc
end

function getBookGenres(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return {} end
  local meta = parseBookMeta(r.body)
  local out = {}
  for _, g in ipairs(meta.genres or {}) do
    out[#out + 1] = translateVocab(g)
  end
  -- fall back to the category meta-tag when no keywords exist
  if #out == 0 and meta.metaTags and meta.metaTags[1] then
    out[1] = translateVocab(meta.metaTags[1])
  end
  return out
end

function getBookStatus(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local meta = parseBookMeta(r.body)
  if meta.status then return translateVocab(meta.status) end
  return nil
end

function getBookLastUpdate(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local el = html_select_first(r.body, ".latest-chapter .update-time")
  if el then
    local d = string.match(el.text or "", "(%d%d%d%d%-%d%d%-%d%d)")
    if d then return d end
  end
  return nil
end

function getChapterListHash(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local el = html_select_first(r.body, ".latest-chapter .update-time")
  local ts = el and string_clean(el.text) or ""
  local chapters = html_select(r.body, "#ul_all_chapters li.chapter-item a")
  if ts ~= "" or #chapters > 0 then
    return ts .. "|" .. tostring(#chapters)
  end
  return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter list (paginated catalog — walk every ?p=N page)
-- ═══════════════════════════════════════════════════════════════════════════

function getChapterList(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return {} end

  -- Every catalog page is enumerated by the .chap-pager select options
  -- (element.attr(name) is the engine's attribute accessor).
  local pageNumbers = { 1 }
  for _, sel in ipairs(html_select(r.body, ".chap-pager select option")) do
    local ok, v = pcall(function() return sel.attr("value") end)
    if ok and v and v ~= "" then
      local n = tonumber(v)
      if n then pageNumbers[#pageNumbers + 1] = n end
    end
  end

  -- de-duplicate page numbers (page 1 already included)
  local seen, pages = {}, {}
  for _, p in ipairs(pageNumbers) do
    if not seen[p] then seen[p] = true; pages[#pages + 1] = p end
  end
  table.sort(pages)

  local chapters = {}
  for _, p in ipairs(pages) do
    local pr = r
    if p ~= 1 then
      pr = httpGetPage(string.match(bookUrl, "^https?://[^/]+(/.*)$") .. "?p=" .. tostring(p))
    end
    if pr and pr.success then
      for _, a in ipairs(html_select(pr.body, "#ul_all_chapters li.chapter-item a")) do
        local chUrl = absUrl(a.href)
        if chUrl ~= "" then
          local title = string_clean(a.text)
          if title == "" then title = (a.title or "") end
          if title ~= "" then
            chapters[#chapters + 1] = { title = title, url = chUrl }
          end
        end
      end
    end
  end

  -- Reading order: the site's catalog occasionally swaps adjacent chapters
  -- (live-verified: page lists 003,005,004,006…). When EVERY title carries an
  -- unambiguous chapter number, sort by it; otherwise keep the site's order.
  local function chapterSortKey(title)
    local n = tonumber(string.match(title, "^(%d+)$"))            -- "001"
    if not n then n = tonumber(string.match(title, "^第(%d+)%s*[章节回]")) end -- "第3章…"
    if not n then n = tonumber(string.match(title, "^[Cc]hapter%s+(%d+)")) end
    return n
  end
  local sortable = #chapters > 0
  local keyed = {}
  for i, ch in ipairs(chapters) do
    local k = chapterSortKey(ch.title)
    if not k then sortable = false; break end
    keyed[i] = { k = k, ch = ch }
  end
  if sortable then
    table.sort(keyed, function(a, b) return a.k < b.k end)
    local sorted = {}
    for i, e in ipairs(keyed) do sorted[i] = e.ch end
    chapters = sorted
  end

  if trActive() and trChaptersEnabled() and #chapters > 0 then
    local titles = {}
    for i = 1, #chapters do titles[i] = chapters[i].title end
    local tr = translateBatch(titles)
    for i = 1, #chapters do chapters[i].title = tr[i] end
  end

  return chapters
end
