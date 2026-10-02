#!/usr/bin/env python3
"""novel543.lua v1.0.4 -> v1.0.5 — covers via wsrv.nl proxy (poster fix) + upstream name sync."""
import sys

P = "/home/z/my-project/download/novel543.lua"
src = open(P, encoding="utf-8").read()

def rep(old, new, tag):
    global src
    if new in src and old not in src:
        print(f"  [skip] {tag}")
        return
    if old not in src:
        print(f"  [MISS] {tag}")
        sys.exit(1)
    assert src.count(old) == 1, f"{tag}: not unique"
    src = src.replace(old, new, 1)
    print(f"  [ok] {tag}")

if 'local VERSION = "1.0.5"' in src:
    print("already spliced"); sys.exit(0)

# 1. version + name sync with upstream (HnDK0 renamed "Novel543 Full" -> "Novel543")
rep('''local VERSION = "1.0.4" -- upstream line: 1.0.3 → 1.0.4 (dev builds 1.1.0–1.2.2 superseded)
id       = "novel543"
name     = "Novel543 Full"
version  = VERSION''',
    '''local VERSION = "1.0.5"
id       = "novel543"
name     = "Novel543"
version  = VERSION''',
    "metadata")

# 2. header changelog
rep('''-- 1.0.4 (upstream PR release):''',
    '''-- 1.0.5 (2026-09-18) — POSTER FIX: cover images are now served through the
--   wsrv.nl image proxy by default (new "Cover Images" setting). novel543's
--   covers live on i2.novel543.com; when that image host is challenged by
--   its CDN, NoveLA's image loader gets the challenge page instead of the
--   JPEG (image URLs are exempt from the Cloudflare WebView bypass) and the
--   poster silently fails. wsrv.nl (images.weserv.nl) fetches server-side
--   and is whitelisted by the engine for exactly this pattern. "Direct"
--   mode keeps the original URLs.
--
-- 1.0.4 (upstream PR release):''',
    "header changelog")

# 3. pref const
rep('''local PREF_TR_CH   = "novel543_tr_chapters" -- "1" | "0" (translate chapter titles)''',
    '''local PREF_TR_CH   = "novel543_tr_chapters" -- "1" | "0" (translate chapter titles)
local PREF_COVERS  = "novel543_covers"       -- "proxy" (default) | "direct"''',
    "pref const")

# 4. coverUrl helper right after absUrl
import re
m = re.search(r"local function absUrl\(href\)\n(.*?)\nend\n", src, re.S)
assert m, "absUrl not found"
abs_block = m.group(0)
helper = abs_block + '''
-- ── Cover image proxy (1.0.5 poster fix) ─────────────────────────────────────
local COVER_PROXY = "https://wsrv.nl/?url="

local function coversViaProxy()
  return get_preference(PREF_COVERS) ~= "direct"
end

-- Wrap a cover URL for the app's image loader. Non-http values pass through.
local function coverUrl(u)
  if not u or u == "" then return u end
  if not coversViaProxy() then return u end
  if not string_starts_with(u, "http") then return u end
  return COVER_PROXY .. url_encode(u) .. "&w=450&we&output=jpg&q=80"
end
'''
src = src.replace(abs_block, helper, 1)
print("  [ok] coverUrl helper")

# 5. list-page cover
rep('''    local cover   = absUrl(html_attr(li.html, "div.media-left img", "src"))''',
    '''    local cover   = coverUrl(absUrl(html_attr(li.html, "div.media-left img", "src")))''',
    "list cover")

# 6. getBookCoverImageUrl
rep('''  local el = html_select_first(r.body, ".cover img")
  if el then return absUrl(el.src) end
  return nil
end''',
    '''  local el = html_select_first(r.body, ".cover img")
  if el then return coverUrl(absUrl(el.src)) end
  return nil
end''',
    "book cover")

# 7. settings entry (before mode entry)
rep('''  return {
    {
      key = PREF_MODE,''',
    '''  return {
    {
      key = PREF_COVERS,
      type = "select",
      label = "Cover Images",
      current = (function()
        if get_preference(PREF_COVERS) == "direct" then return "direct" end
        return "proxy"
      end)(),
      options = {
        { value = "proxy",  label = "Via wsrv.nl image proxy (recommended — fixes posters)" },
        { value = "direct", label = "Direct from novel543.com (breaks when the CDN challenges images)" }
      }
    },
    {
      key = PREF_MODE,''',
    "settings")

open(P, "w", encoding="utf-8").write(src)
print(f"written {P}")
