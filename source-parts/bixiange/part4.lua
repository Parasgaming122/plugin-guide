
-- ═══════════════════════════════════════════════════════════════════════════
-- Book details
-- ═══════════════════════════════════════════════════════════════════════════
-- Book page layout (same template for /cat/id/ and /cat/id.html books):
--   .detail .info
--     .cover img                  → cover (relative /d/file/... URL)
--     .desc h1                    → "书名(1-301)" (count suffix stripped)
--     .descTip p span             → 分类：X / 大小：Y MB / 作者：Z / 时间：DATE
--     .descInfo p                 → description (with <br/> line breaks)
--     .catalog ul li a            → ALL chapters (one page), titles “第N节”

-- Split the .descTip spans into named fields (labels are Chinese).
-- NOTE: Lua patterns are byte-based — a character CLASS like [:：] breaks on
-- the 3-byte fullwidth colon (it matches only its FIRST byte, leaving mojibake
-- in the capture). Both colon variants are matched as LITERAL alternatives.
local function matchLabel(t, label)
  local v = string.match(t, "^" .. label .. "：(.+)$")
  if not v then v = string.match(t, "^" .. label .. ":(.+)$") end
  if v then v = string.gsub(v, "^%s+", "") end
  return v
end

local function parseDescTip(body)
  local out = {}
  for _, p in ipairs(html_select(body, ".descTip p")) do
    for _, span in ipairs(html_select(p.html, "span")) do
      local t = string_clean(span.text or "")
      local v
      v = matchLabel(t, "分类"); if v then out.category = v end
      v = matchLabel(t, "作者"); if v then out.author   = v end
      v = matchLabel(t, "时间"); if v then out.date     = v end
      v = matchLabel(t, "大小"); if v then out.size     = v end
    end
  end
  return out
end

-- Strip the trailing "(1-301)" chapter-count suffix from the h1 title.
local function cleanBookTitle(t)
  if type(t) ~= "string" then return t end
  local cleaned = string.gsub(t, "%s*%(%d+%s*-%s*%d+%)%s*$", "")
  if cleaned == "" then return t end
  return cleaned
end

function getBookTitle(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local el = html_select_first(r.body, ".desc h1")
  if not el then el = html_select_first(r.body, "h1") end
  if not el then return nil end
  local title = cleanBookTitle(string_clean(el.text))
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
  local src = html_attr(r.body, ".cover img", "src")
  if not src or src == "" then return nil end
  return coverUrl(absUrl(src))
end

function getBookDescription(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local meta = parseDescTip(r.body)
  local el = html_select_first(r.body, ".descInfo p")
  if not el then return nil end
  local desc = string_clean(el.text)
  if desc == "" then return nil end

  -- Prefix the author line (the app has no dedicated author field).
  local header = ""
  if meta.author and meta.author ~= "" then
    header = "作者：" .. meta.author .. "\n\n"
  end
  desc = header .. desc

  if #desc > 4000 then desc = string.sub(desc, 1, 4000) end
  if trActive() then desc = translateOne(desc) end
  return desc
end

function getBookGenres(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return {} end
  local meta = parseDescTip(r.body)
  if meta.category and meta.category ~= "" then
    return { translateVocab(meta.category) }
  end
  return {}
end

-- The site does not expose an ongoing/completed status anywhere on the book
-- page — return nil rather than guessing.
function getBookStatus(bookUrl)
  return nil
end

function getBookLastUpdate(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local meta = parseDescTip(r.body)
  if meta.date then
    local d = string.match(meta.date, "(%d%d%d%d%-%d%d%-%d%d)")
    if d then return d end
    return meta.date
  end
  return nil
end

-- Update hash: last-update date + chapter count + last chapter URL tail.
-- Catches both new chapters and whole-book replacements.
function getChapterListHash(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return nil end
  local meta = parseDescTip(r.body)
  local chapters = html_select(r.body, ".catalog ul li a")
  local lastHref = ""
  if #chapters > 0 then
    lastHref = chapters[#chapters].href or ""
  end
  if meta.date or #chapters > 0 then
    return (meta.date or "") .. "|" .. tostring(#chapters) .. "|" .. lastHref
  end
  return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter list
-- ═══════════════════════════════════════════════════════════════════════════

function getChapterList(bookUrl)
  local r = fetchPageCached(bookUrl)
  if not (r and r.success) then return {} end

  local chapters = {}
  for _, a in ipairs(html_select(r.body, ".catalog ul li a")) do
    local chUrl = absUrl(a.href)
    if chUrl ~= "" then
      local title = string_clean(a.text)
      if title == "" then title = "第" .. tostring(#chapters + 1) .. "节" end
      chapters[#chapters + 1] = { title = title, url = chUrl }
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

-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter text
-- ═══════════════════════════════════════════════════════════════════════════
-- Content lives in div.content#mycontent as <p> paragraphs (both URL
-- generations). Chapter 1 embeds a TXT header before the real content:
--     书名 / 作者：X / 简介： / …synopsis paragraphs… / 第1章 …
-- The header is stripped: if a 第X章-style heading is found at paragraph
-- index ≥ 4 within the first 30 paragraphs, everything before it is dropped;
-- otherwise only title/作者/简介 marker lines are dropped.

local function isChapterHeading(p)
  return string.match(p, "^第[%d一二三四五六七八九十百千零两]+%s*[章节回卷部]") ~= nil
    or string.match(p, "^[Cc]hapter%s+%d+") ~= nil
end

local function stripTxtHeader(paras, pageTitle)
  local n = #paras
  if n == 0 then return paras end

  -- Tier 1: a real chapter heading deeper in the paragraph stream marks the
  -- true content start (TXT header is always ≥ 4 paragraphs: title+author+
  -- 简介+synopsis).
  local limit = n
  if limit > 30 then limit = 30 end
  for i = 5, limit do
    if paras[i] ~= "" and isChapterHeading(paras[i]) then
      local out = {}
      for k = i, n do out[#out + 1] = paras[k] end
      return out
    end
  end

  -- Tier 2: strip known marker lines off the top (title / 作者： / 简介：).
  local start = 1
  local titleCore = pageTitle and string.gsub(pageTitle, "%s", "") or ""
  while start <= n do
    local p = paras[start]
    local isMarker = (p == "")
      or (p and titleCore ~= "" and string.gsub(p, "%s", "") == titleCore)
      or (p and string.match(p, "^作者："))
      or (p and string.match(p, "^作者:"))
      or (p and string.match(p, "^简介：?$"))
      or (p and string.match(p, "^简介:?$"))
    if not isMarker then break end
    start = start + 1
  end
  if start > n then return paras end -- everything matched (shouldn't happen)
  local out = {}
  for k = start, n do out[#out + 1] = paras[k] end
  return out
end

function getChapterText(html, url)
  if type(html) ~= "string" or html == "" then return "" end

  local el = html_select_first(html, "#mycontent")
  if not el then el = html_select_first(html, "div.content") end
  if not el then return "" end

  -- Remove ad/script scaffolding inside the content block, if any.
  local cleaned = html_remove(el.html, "script", "ins", "div.adBlock", "div.gadBlock")
  local paras = {}
  for _, p in ipairs(html_select("<div>" .. cleaned .. "</div>", "p")) do
    local t = string_clean(p.text or "")
    paras[#paras + 1] = t
  end
  if #paras == 0 then
    local raw = string_clean(html_text("<div>" .. cleaned .. "</div>"))
    if raw == "" then return "" end
    paras = { raw }
  end

  -- Chapter title from the page (used only for TXT-header stripping).
  local h1 = html_select_first(html, ".article h1")
  local pageTitle = h1 and string_clean(h1.text) or ""

  paras = stripTxtHeader(paras, pageTitle)

  local out = {}
  for _, p in ipairs(paras) do
    if p ~= "" then out[#out + 1] = p end
  end
  return table.concat(out, "\n\n")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Engine hooks + settings
-- ═══════════════════════════════════════════════════════════════════════════

-- Chrome Mobile UA preset: the engine applies it to this plugin's requests
-- AND to untagged image loads for the baseUrl host.
function getUserAgentPreset()
  return "Chrome Mobile"
end

function getSettingsSchema()
  local sitePref = get_preference(PREF_SITE)
  if sitePref ~= "top" and sitePref ~= "mirror" then sitePref = "auto" end
  local coverPref = get_preference(PREF_COVERS)
  if coverPref ~= "direct" then coverPref = "proxy" end
  return {
    {
      key = PREF_SITE,
      type = "select",
      label = "Site (站点)",
      current = sitePref,
      options = {
        { value = "auto",   label = "Auto — bixiange.top first, bxg123.cc mirror fallback (recommended)" },
        { value = "top",    label = "bixiange.top only" },
        { value = "mirror", label = "bxg123.cc mirror first — bixiange.top backup" }
      }
    },
    {
      key = PREF_COVERS,
      type = "select",
      label = "Cover Images",
      current = coverPref,
      options = {
        { value = "proxy",  label = "Via wsrv.nl image proxy (recommended — fixes posters)" },
        { value = "direct", label = "Direct from bixiange.top" }
      }
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
