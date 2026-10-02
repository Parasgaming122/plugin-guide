
-- ═══════════════════════════════════════════════════════════════════════════
-- Chapter text
-- ═══════════════════════════════════════════════════════════════════════════
-- Content lives in article#article. The site interleaves ad DIVs
-- (.mid-content-ad, #oneadMIRDFPTag00 …) INSIDE the article — selecting only
-- the <p> children skips every one of them.
--
-- Chapter 1 of TXT-imported books is often just the TXT header:
--     [書名（…）] [作者: …] [簡介: …]
-- The header is stripped ONLY when real content follows (a 第X章-style
-- heading, or ≥200 chars of remaining text) — otherwise it IS the chapter
-- (an empty chapter would surface as a reader content error).

local function isChapterHeading(p)
  return string.match(p, "^第[%d一二三四五六七八九十百千零两]+%s*[章节回卷部]") ~= nil
    or string.match(p, "^[Cc]hapter%s+%d+") ~= nil
end

local function stripTxtHeader(paras)
  local n = #paras
  if n == 0 then return paras end

  -- Structural TXT header: [short title-ish line][作者: …][簡介: …]
  -- When paragraph 2 starts with 作者 and paragraph 3 with 簡介/简介, the
  -- header is paragraphs 1..3 (+ any trailing empties).
  if n >= 3 then
    local p2 = paras[2]
    if p2 and (string.match(p2, "^作者[:：]") or string.match(p2, "^作者:")) then
      local stop = 3
      local p3 = paras[3]
      if p3 and (string.match(p3, "^簡介") or string.match(p3, "^简介") or p3 == "") then
        stop = 3
      elseif p3 and string.match(p2, "^作者") then
        stop = 2
      end
      local out = {}
      for k = stop + 1, n do out[#out + 1] = paras[k] end
      -- keep the header when stripping would leave nothing meaningful
      local kept = table.concat(out, "")
      if #string.gsub(kept, "%s", "") >= 200 then
        return out
      end
      return paras
    end
  end

  -- 第X章 heading deeper in the stream marks the true content start.
  local limit = n
  if limit > 30 then limit = 30 end
  for i = 4, limit do
    if paras[i] ~= "" and isChapterHeading(paras[i]) then
      local out = {}
      for k = i, n do out[#out + 1] = paras[k] end
      local kept = table.concat(out, "")
      if #string.gsub(kept, "%s", "") >= 200 then
        return out
      end
      return paras
    end
  end

  return paras
end

function getChapterText(html, url)
  if type(html) ~= "string" or html == "" then return "" end

  local el = html_select_first(html, "article#article")
  if not el then el = html_select_first(html, "#article") end
  if not el then el = html_select_first(html, ".reading-content article") end
  if not el then return "" end

  -- Only <p> elements — skips the ad DIVs nested inside the article.
  local paras = {}
  for _, p in ipairs(html_select(el.html, "p")) do
    local t = string_clean(p.text or "")
    paras[#paras + 1] = t
  end
  if #paras == 0 then
    local raw = string_clean(html_text("<div>" .. el.html .. "</div>"))
    if raw == "" then return "" end
    paras = { raw }
  end

  paras = stripTxtHeader(paras)

  local out = {}
  for _, p in ipairs(paras) do
    if p ~= "" then out[#out + 1] = p end
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
  local coverPref = get_preference(PREF_COVERS)
  if coverPref ~= "direct" then coverPref = "proxy" end
  return {
    {
      key = PREF_COVERS,
      type = "select",
      label = "Cover Images",
      current = coverPref,
      options = {
        { value = "proxy",  label = "Via wsrv.nl image proxy (recommended — fixes posters)" },
        { value = "direct", label = "Direct from oop.tw (breaks when Cloudflare challenges images)" }
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
