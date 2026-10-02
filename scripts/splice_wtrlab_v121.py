#!/usr/bin/env python3
"""wtrlab.lua v1.2.0 -> v1.2.1 — covers via wsrv.nl proxy (poster fix)."""
import sys

P = "/home/z/my-project/download/wtrlab.lua"
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

if 'version = "1.2.1"' in src:
    print("already spliced"); sys.exit(0)

# 1. version + header note
rep('version = "1.2.0"', 'version = "1.2.1"', "version")

rep('''-- 1.2.0 (2026-09-10) — user-driven update:''',
    '''-- 1.2.1 (2026-09-18) — POSTER FIX: cover images are now served through the
--   wsrv.nl image proxy by default (new "Cover images" setting). Root cause:
--   wtr-lab's covers live on img.wtr-lab.com and are redirected (302 chain)
--   to signed full-size images (300KB+); when Cloudflare challenges the
--   image host, NoveLA's image loader gets the challenge page instead of
--   the JPEG (image URLs are exempt from the Cloudflare WebView bypass) and
--   the poster silently fails. wsrv.nl (images.weserv.nl) fetches
--   server-side, resizes to w=450, and is whitelisted by the engine for
--   exactly this pattern. "Direct" mode keeps the original URLs.
--
-- 1.2.0 (2026-09-10) — user-driven update:''',
    "header changelog")

# 2. pref const
rep('''local PREF_BUILDID = "wtrlab_buildid"     -- persisted Next.js buildId (survives app restarts)''',
    '''local PREF_BUILDID = "wtrlab_buildid"     -- persisted Next.js buildId (survives app restarts)
local PREF_COVERS = "wtrlab_covers"       -- "proxy" (default) | "direct" — poster loading mode''',
    "pref const")

# 3. coverUrl helper after absUrl
rep('''local function fetchPage(url)
    if _pageCache[url] then
        return _pageCache[url]
    end''',
    '''-- ── Cover image proxy (1.2.1 poster fix) ─────────────────────────────────────
-- img.wtr-lab.com covers redirect to 300KB+ signed images and sit behind
-- Cloudflare; image URLs are EXEMPT from the engine's CF bypass
-- (STATIC_EXTENSIONS), so a challenged cover = broken poster. wsrv.nl is
-- the engine-whitelisted image proxy other NoveLA sources use for this.
local COVER_PROXY = "https://wsrv.nl/?url="

local function coversViaProxy()
    return get_preference(PREF_COVERS) ~= "direct"
end

local function coverUrl(u)
    if not u or u == "" then return u end
    if not coversViaProxy() then return u end
    if not string_starts_with(u, "http") then return u end
    return COVER_PROXY .. url_encode(u) .. "&w=450&we&output=jpg&q=80"
end

local function fetchPage(url)
    if _pageCache[url] then
        return _pageCache[url]
    end''',
    "coverUrl helper")

# 4. seriesToItems cover
rep('''                cover = absUrl(cover)''',
    '''                cover = coverUrl(absUrl(cover))''',
    "seriesToItems cover")

# 5. getBookCoverImageUrl
rep('''    local cover = html_attr(body, ".image-wrap img[alt]:not([aria-hidden])", "src")
    if cover ~= "" then
        return absUrl(cover)
    end
    return nil
end''',
    '''    local cover = html_attr(body, ".image-wrap img[alt]:not([aria-hidden])", "src")
    if cover ~= "" then
        return coverUrl(absUrl(cover))
    end
    return nil
end''',
    "getBookCoverImageUrl cover")

# 6. settings entry (insert before the delay entry)
rep('''    }, {
        key = PREF_DELAY,''',
    '''    }, {
        key = PREF_COVERS,
        type = "select",
        label = "Cover Images",
        current = (function()
            if get_preference(PREF_COVERS) == "direct" then return "direct" end
            return "proxy"
        end)(),
        options = {{
            value = "proxy",
            label = "Via wsrv.nl image proxy (recommended - fixes posters)"
        }, {
            value = "direct",
            label = "Direct from img.wtr-lab.com (breaks when Cloudflare challenges images)"
        }}
    }, {
        key = PREF_DELAY,''',
    "settings covers")

open(P, "w", encoding="utf-8").write(src)
print(f"written {P} ({len(src)} bytes)")
