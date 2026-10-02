
-- ═══════════════════════════════════════════════════════════════════════════
-- Book details (one cached /proxy?action=detail request answers them all)
-- ═══════════════════════════════════════════════════════════════════════════

function getBookTitle(bookUrl)
  local d = fetchBookDetail(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return nil end
  local title = tostring(d.book_name or d.original_book_name or "")
  if title == "" then return nil end
  if trActive() then
    local tr = translateOne(title)
    if tr and tr ~= title then return tr .. " (" .. title .. ")" end
  end
  return title
end

function getBookCoverImageUrl(bookUrl)
  local d = fetchBookDetail(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return nil end
  -- Signed CDN URL (fqnovelpic.com, x-expires months out) — used DIRECTLY:
  -- the image loader is exempt from the WebView bypass, and these signed
  -- hosts have never been observed challenging image requests.
  local u = tostring(d.thumb_url or d.audio_thumb_uri or "")
  if u == "" then return nil end
  return u
end

function getBookDescription(bookUrl)
  local d = fetchBookDetail(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return nil end
  local desc = tostring(d.abstract or "")
  if desc == "" then return nil end
  if trActive() then
    if #desc > 4000 then desc = string.sub(desc, 1, 4000) end
    desc = translateOne(desc)
  end
  return desc
end

-- tags = comma-separated Chinese category names ("东方仙侠,玄幻,仙侠").
function getBookGenres(bookUrl)
  local d = fetchBookDetail(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return {} end
  local genres = {}
  local tags = tostring(d.tags or d.category or "")
  for _, t in ipairs(string_split(tags, ",")) do
    t = string_trim(t)
    if t ~= "" then genres[#genres + 1] = translateVocab(t) end
  end
  if #genres == 0 then
    local cat = tostring(d.category or "")
    if cat ~= "" then genres[1] = translateVocab(cat) end
  end
  return genres
end

-- Score: 0-10 scale string ("9.3"); "0" = unscored → nil.
function getBookRating(bookUrl)
  local d = fetchBookDetail(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return nil end
  local s = tostring(d.score or "")
  if s == "" or s == "0" then return nil end
  return s
end

-- creation_status: '0' = 已完结 Finished, any other truthy value = 连载中
-- Ongoing (verified against the reader's bookInfo.js normalization).
function getBookStatus(bookUrl)
  local d = fetchBookDetail(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return nil end
  local s = tostring(d.creation_status or "")
  if s == "" then return nil end
  if s == "0" then return translateVocab("已完结") end
  return translateVocab("连载中")
end

-- last_publish_time = unix seconds (string) → "YYYY-MM-DD".
function getBookLastUpdate(bookUrl)
  local d = fetchBookDetail(bookIdFromUrl(bookUrl) or bookUrl)
  if type(d) ~= "table" then return nil end
  return epochToDate(d.last_publish_time)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter list (directory action — ALL chapters in one response)
-- ═══════════════════════════════════════════════════════════════════════════

function getChapterList(bookUrl)
  local bookId = bookIdFromUrl(bookUrl)
  if not bookId then return {} end
  local items = fetchDirectory(bookId)
  if type(items) ~= "table" then return {} end

  local chapters = {}
  for i = 1, #items do
    local it = items[i]
    if type(it) == "table" and type(it.item_id) == "string" then
      chapters[#chapters + 1] = {
        title = tostring(it.title or it.item_id),
        url   = SITE .. "/book/" .. bookId .. "/" .. it.item_id
      }
    end
  end

  if trActive() and trChaptersEnabled() and #chapters > 0 then
    local titles = {}
    for i = 1, #chapters do titles[i] = chapters[i].title end
    local tr = translateBatch(titles)
    for i = 1, #chapters do chapters[i].title = tr[i] end
  end

  return chapters
end

-- Change hash from the (cached) detail: chapter count + last publish time.
-- Both move whenever a new chapter or 番外 drops — enough for the app's
-- "this book has updates" check without re-downloading the whole directory.
function getChapterListHash(bookUrl)
  local bookId = bookIdFromUrl(bookUrl)
  if not bookId then return nil end
  local d = fetchBookDetail(bookId)
  if type(d) ~= "table" then return nil end
  local h = tostring(d.content_chapter_number or "") .. "|" ..
            tostring(d.last_publish_time or "")
  if h == "|" then return nil end
  return h
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter text
-- ═══════════════════════════════════════════════════════════════════════════
-- The app downloads the chapter URL first (fanqietc.com → static SPA shell,
-- never Cloudflare-challenged) and hands the HTML + URL to this function.
-- The REAL text lives at api.fanqietc.com (content action), keyed by the
-- item id embedded in the URL — fetched here with the auth header set.
-- Content arrives as one paragraph per "\n", which is exactly how NoveLA's
-- reader splits chapter bodies (TextToItemsConverter: split("\n")) — only
-- blank-line noise and stray spaces are cleaned.

function getChapterText(html, url)
  local itemId = string.match(url or "", "/book/%d+/(%d+)")
  if not itemId then return nil end

  local c = proxyAction("content", { item_id = itemId })
  if type(c) ~= "table" or type(c.content) ~= "string" then
    -- surface a readable error instead of a silent empty chapter: every
    -- mirror (incl. the backend's own 'default' pick) refused the request.
    show_error("FanqieTC: chapter unavailable",
               "The backend and all its mirrors refused this chapter request.\n\n" ..
               "Try again in a minute, or open this source's Settings and pick " ..
               "a different API mirror (cn-1 / cn-2 / sg-1 / sg-2 were healthy " ..
               "at release time). The ⚡ Self-Test page (Browse → Page → " ..
               "Self-Test) shows live mirror health.")
    return nil
  end

  -- Re-flow: strip blank lines, trim each paragraph, drop the leading space
  -- some mirrors prepend to the first line.
  local lines = string_split(c.content, "\n")
  local out = {}
  for _, ln in ipairs(lines) do
    ln = string_trim(ln)
    if ln ~= "" then out[#out + 1] = ln end
  end
  if #out == 0 then return nil end
  return table.concat(out, "\n")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Settings schema
-- ═══════════════════════════════════════════════════════════════════════════

function getSettingsSchema()
  local mirrorOptions = {
    { value = "auto",    label = "Auto — health-checked (recommended)" },
    { value = "default", label = "default — let the backend pick" }
  }
  for _, id in ipairs(MIRRORS) do
    mirrorOptions[#mirrorOptions + 1] = { value = id, label = id }
  end

  return {
    {
      key = PREF_MIRROR,
      type = "select",
      label = "API Mirror (API 鏡像)",
      current = getMirrorSetting(),
      options = mirrorOptions
    },
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
