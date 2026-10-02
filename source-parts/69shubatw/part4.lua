
-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter text — /read/{bid}/{cid}
-- ═══════════════════════════════════════════════════════════════════════════
-- Content lives in div#nr1 as <p> paragraphs. The site interleaves ad DIVs
-- (.reader-ad carrying loadAdv() scripts) BETWEEN the <p>s INSIDE the
-- content div — selecting only the <p> elements skips every one of them.
-- The h1#nr_title carries a "(cur / total)" sub-page suffix; when total > 1
-- the remaining sub-pages live at /read/{bid}/{cid}/{n} and are fetched and
-- concatenated (defensive — every chapter sampled live was (1 / 1), the
-- sub-page URL shape follows the site's family pattern; a failed sub-page
-- fetch just ends the concatenation with what was gathered).
-- Watermark lines (site domains, (本章完)) are stripped.

local SUBPAGE_CAP = 30

-- "(1 / 2)" → 1, 2 ; also tolerates "(1/2)".
local function parsePageSuffix(title)
  local cur, total = string.match(title or "", "%((%d+)%s*/%s*(%d+)%)%s*$")
  return tonumber(cur), tonumber(total)
end

local function isWatermark(p)
  if p == "(本章完)" or p == "（本章完）" then return true end
  if #p > 80 then return false end
  if string.find(p, "69shuba", 1, true) then return true end
  if string.find(p, "69shuba.tw", 1, true) then return true end
  if string.find(p, "cs76.com", 1, true) then return true end
  return false
end

local function chapterParas(html)
  local el = html_select_first(html, "div#nr1")
  if not el then el = html_select_first(html, ".nr_nr") end
  if not el then return nil end
  local paras = {}
  for _, p in ipairs(html_select(el.html, "p")) do
    local t = string_clean(p.text or "")
    paras[#paras + 1] = t
  end
  if #paras == 0 then
    local raw = string_clean(html_text("<div>" .. el.html .. "</div>"))
    if raw == "" then return nil end
    paras = { raw }
  end
  return paras
end

function getChapterText(html, url)
  if type(html) ~= "string" or html == "" then return "" end

  local paras = chapterParas(html)
  if not paras then return "" end

  -- sub-page continuation: title "(cur / total)" with total > 1
  local titleEl = html_select_first(html, "#nr_title")
  local cur, total = parsePageSuffix(titleEl and titleEl.text or "")
  if cur and total and total > 1 and cur < total and cur < SUBPAGE_CAP then
    local bid = string.match(url or "", "/read/(%d+)/%d+")
    local cid = string.match(url or "", "/read/%d+/(%d+)")
    if bid and cid then
      for n = cur + 1, math.min(total, SUBPAGE_CAP) do
        local r = httpGetPage(SITE .. "/read/" .. bid .. "/" .. cid .. "/" .. tostring(n))
        if not (r and r.success) then break end
        local more = chapterParas(r.body)
        if not more or #more == 0 then break end
        for _, t in ipairs(more) do paras[#paras + 1] = t end
      end
    end
  end

  local out = {}
  for _, p in ipairs(paras) do
    if p ~= "" and not isWatermark(p) then out[#out + 1] = p end
  end
  if #out == 0 and #paras > 0 then
    -- never return an empty chapter (a reader error) — fall back to raw
    for _, p in ipairs(paras) do
      if p ~= "" then out[#out + 1] = p end
    end
  end
  return table.concat(out, "\n\n")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Engine hooks + settings
-- ═══════════════════════════════════════════════════════════════════════════

function getUserAgentPreset()
  return "Chrome Mobile"
end

function getSettingsSchema()
  return {
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
