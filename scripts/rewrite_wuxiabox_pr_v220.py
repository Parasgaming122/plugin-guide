#!/usr/bin/env python3
"""Rewrite wuxiabox_pull_request.md as the v2.2.0 PR (v2.1.0 material demoted to prior-release section)."""
import re

P = "/home/z/my-project/download/wuxiabox_pull_request.md"
src = open(P, encoding="utf-8").read()

# ── new header + TL;DR ─────────────────────────────────────────────────────
old_header = src[:src.index("## 1. The search bug")]
new_header = '''# Pull Request — `en/wuxiabox.lua` v2.2.0 (WuxiaBox)

**Source:** [`en/wuxiabox.lua`](https://github.com/HnDK0/external-sources/blob/main/en/wuxiabox.lua)
**Base version:** `1.0.1` (WuxiaBox — wuxiabox.com, EmpireCMS "Web Novels MTL" platform)
**Proposed version:** `2.2.0` (same site, same source id — in-place upgrade of the 2.x line)
**Date:** 2026-09-18
**Plugin size:** 3,053 lines (~121 KB — down from 8,145 lines / 184 KB in 2.1.0; the tag index shrank from 6,723 to 755 entries)

---

## TL;DR — what v2.2.0 changes

Same file, same `id`, same book URLs — existing installs and libraries carry over untouched. Four user-facing changes:

1. **POSTERS FIXED.** WuxiaBox cover images live behind the same Cloudflare shield as the pages, but **image URLs are exempt from NoveLA's Cloudflare WebView bypass** (its `STATIC_EXTENSIONS` list short-circuits `.jpg`), so a challenged cover request handed the challenge HTML to the image loader and the poster silently failed. All covers are now served through the **wsrv.nl image proxy** (`images.weserv.nl` — the service the engine itself whitelists for exactly this pattern), resized to `w=450`. A new **"Cover images" setting** offers `proxy` (default) or `direct`.
2. **SEARCH now paginates continuously.** Two bugs killed multi-page results in 2.1.0: (a) the pager's grand-total (`总数`) fallback was **dead code** — the Lua pattern anchored on `<ul class="pagination">` but could not cross the newline that follows it; (b) later search pages used the **mirror fallback**, and a `searchid` is an entry in *this site's* EmpireCMS search table — the mirror served an unrelated or empty page, which the app treats as "no more results", ending the feed after one page. Searchid pages are now **primary-only** with a fresh-search retry, and hard failures raise a **retryable error** (the app keeps loaded pages and offers retry) instead of silently ending pagination. Verified against live captures: pager is 0-based, pages 0/1/2 carry distinct items, `page=1` URL form and `?searchid=` form behave identically.
3. **TAGS CURATED + NATIVELY SEARCHABLE.** The 6,723-entry tag index (148 KB of the file) is replaced by **755 genuinely-used tags** — the wtr-lab taxonomy cross-reference (746 normalized-name matches, i.e. the tropes novels on this platform are actually tagged with) plus every Popular Tag and the whole Honghuang\* family. Browsing them is now a **`tag_input` filter** (a newer NoveLA filter type): a text field with live suggestions — type "protag" and matching tags appear; picked tags become removable chips. This replaces both the old free-text "Tag Search" box and the "Popular Tags" checkbox group. Plugin size drops by ~63 KB and cold-load gets faster.
4. **Cloudflare improvements.** `getUserAgentPreset()` registers a modern **Chrome Mobile** UA for every request of this source *and* its host — including the image loader's cover fetches — so the `cf_clearance` cookie the WebView bypass bakes stays valid for images too (it is bound to User-Agent + IP). `show_error()` (new engine API) surfaces actionable dialogs when both sites are unreachable or a tag pick cannot be resolved.

All changes verified by a **125-test** luaj/jsoup harness running the real plugin against live-HTML fixtures (`test-harness/WuxiaboxTest.java`) — including simulated 502→mirror recovery, searchid primary-only routing, the dead-total-pattern regression case, last-page math, and a consistency sweep of all 756 picker options. **125/125 pass.**

---

## v2.1.0 changes (previous release — kept for context)

'''
src = new_header + src[len(old_header):]

# ── fix the embedded v2.1.0 heading numbering context ─────────────────────
# "## 1. The search bug" etc. now live under the v2.1.0 banner — annotate the first one
src = src.replace("## 1. The search bug — exact-title searches returned nothing",
                  "### 1. The search gate bug (v2.1.0) — exact-title searches returned nothing", 1)

# ── update the sections that v2.2.0 supersedes ─────────────────────────────
# §3 Popular Tags — superseded note
src = src.replace("## 3. Popular Tags picker (replaces the A-Z letter filter)",
                  "### 3. Popular Tags picker (v2.1.0 — SUPERSEDED in 2.2.0 by the searchable tag_input)", 1)
src = src.replace("## 2. The mirror site — what falls back, what must not",
                  "### 2. The mirror site (v2.1.0) — what falls back, what must not", 1)
src = src.replace("## 4. Categories vs tags — clean separation",
                  "### 4. Categories vs tags (v2.1.0) — clean separation", 1)
src = src.replace("## 5. The 502 fix (carried from v2.0.0, now mirror-aware)",
                  "### 5. The 502 fix (carried from v2.0.0, now mirror-aware)", 1)
src = src.replace("## 6. Filters (v2.1.0)",
                  "### 6. Filters (v2.2.0 current)", 1)

# ── rewrite the filters table section content ──────────────────────────────
m = re.search(r"### 6\. Filters \(v2\.2\.0 current\).*?(?=## 7\. Testing)", src, re.S)
assert m
new_filters = '''### 6. Filters (v2.2.0 current)

| # | Filter | Type | Values → behaviour |
|---|---|---|---|
| 1 | Browse Mode | select | `Categories` (uses filters 2–4) / `Recently Updated` (`/updates/`) |
| 2 | Category | select | 57 slugs → `/list/{cat}/...` |
| 3 | Status | select | all / Completed / Ongoing (capitalized — base v1.0.1 sent lowercase, silently ignored by the site) |
| 4 | Sort By | select | Newest Added (`newstime`) / Last Updated (`lastdotime`) / Most Viewed (`onclick`) |
| 5 | **Tags** | **tag_input** | **756 searchable options** (755 curated + the `honghuang` family keyword). Type-to-filter suggestions; picked tags are chips. Marshalled as `filters["tags_included"]`; numeric ids resolve to exactly that tag, the keyword expands to the whole Honghuang\* family, and the union browse merges every pick deduplicated by novel URL. |

Filter-correspondence guarantees (each filter maps to a working site surface):
- every category slug verified against the live `/list/` sidebar; unshared mirror slugs fail gracefully on fallback;
- status/sort values are the exact tokens the site's own URLs use;
- every tag option id is **canonical** (the lowest id among duplicate names — the id the site's own novel pages link to), verified programmatically for all 756 options by test T7d;
- tags take priority over category/status/sort because the site cannot combine a tag listing with them (tag pages have no category/status/sort params).

Settings (in-app source settings, 4 entries): **Source site** (auto / wuxiabox only / wuxiaspot first), **Cover images** (proxy / direct — new in 2.2.0), **Chapter retries on 502** (2–6), **Chapter request pacing** (ms floor).

'''
src = src[:m.start()] + new_filters + src[m.end():]

# ── update testing section numbers ─────────────────────────────────────────
src = src.replace("## 7. Testing", "## 7. Testing", 1)
m = re.search(r"## 7\. Testing.*?(?=## 8\. Install)", src, re.S)
assert m
new_testing = '''## 7. Testing

`test-harness/WuxiaboxTest.java` — luaj 3.0.1 + jsoup, faithful NoveLA API emulation (multimap headers, TextExtractor port, preferences, UA-tagged requests), mock server with per-URL rules, response sequences, request-header capture and body-match narrowing. Live-captured fixtures in `research/wuxiabox/`.

**125/125 PASS**, the additions over v2.1.0's 111:

| Suite | New checks |
|---|---|
| T0 | version 2.2.0; `getUserAgentPreset()` registered returning "Chrome Mobile" |
| T1 | 5 filters; `tags` is a `tag_input` with **756 options**, `allowCustom=false`; `tag_search` text + `popular_tags` checkbox gone; honghuang keyword present |
| T2 | curated resolver: `'adapted*'` → exactly the 3 Adapted-to-\* tags; canonical ids `'12,225'` |
| T3 / T8 / T8d | covers are `https://wsrv.nl/?url=https%3A%2F%2Fwww.wuxiabox.com%2F…&w=450…`; direct-mode toggle returns bare site URLs; proxy toggle restores |
| T4c | hasNext from the `总数` total alone on a page with **no next links** (the dead-pattern regression case); last page (page=50 of 1008) → hasNext=false via total math |
| T4d | searchid page primary failure → **retryable error** raised (not silent empty); mirror **never** requested for searchid pages |
| T7b/c | `tags_included` chip marshalling (12 + 225 + honghuang family → union browse incl. `/tags/5779-0.html`) |
| T7d | **all 756** picker options: each value resolves to exactly one tag AND its label resolves back to that id |
| T14 | 4 settings incl. covers (default proxy) |

Carried from v2.1.0: single-result search acceptance, relative-Location resolution, status casing, updates-mode URL rewriting, category browse, tag union + dedup, primary-only tag listings, book getters (description preference chain, cover fallbacks, genres-without-tags, last-update via last fy page), parsePage chapter pagination (100/page, 13 pages, XHR headers), chapter-text cleaning (base merge), 502 recovery with mirror alternation + backoff, box-only preference, catalog/search mirror fallbacks with canonical URLs.

'''
src = src[:m.start()] + new_testing + src[m.end():]

# ── update the size/line references in remaining sections ─────────────────
src = src.replace("## 9. Tag-index maintenance pipeline",
                  "## 9. Tag-index maintenance pipeline (v2.2.0: curated)", 1)
m = re.search(r"## 9\. Tag-index maintenance pipeline \(v2\.2\.0: curated\).*?(?=## 10\. Known limits)", src, re.S)
assert m
new_maint = '''## 9. Tag-index maintenance pipeline (v2.2.0: curated)

The 6,723-tag harvest pipeline still exists, but the shipped index is now the **curated** set. To refresh:

1. `scripts/harvest_wuxiabox_tags.py` — resumable live harvest of `/browsetags/` (unchanged).
2. `scripts/curate_wuxiabox_tags.py` — computes the curated set: normalized-name intersection with the wtr-lab tag taxonomy (wtr-lab novels and WuxiaBox novels are the same corpus, so its 888 tags are the "actually used" set) + the plugin's popular tags + tags observed on novel-page fixtures + the Honghuang\* family. Emits `research/wuxiabox/curated_tags.json`. **Gotcha: exclude `mirror_*` fixtures** — wuxiaspot tag ids map to different names (wuxiaspot 682 = "Rebirth", wuxiabox 682 = "Saving the World").
3. `scripts/splice_wuxiabox_v220.py` — regenerates `TAG_SEARCH_INDEX` **and** `TAG_FILTER_OPTIONS` (the tag_input options) from the curated JSON.
4. Re-run `test-harness/WuxiaboxTest.java` — T7d validates every option id/label pair.

'''
src = src[:m.start()] + new_maint + src[m.end():]

# ── known limits ───────────────────────────────────────────────────────────
m = re.search(r"## 10\. Known limits.*", src, re.S)
assert m
new_limits = '''## 10. Known limits

- No tag **exclusion** — the platform's filter sheet cannot express it and the site has no exclude param for tag listings.
- A tag listing cannot be combined with category/status/sort (site limitation; the plugin applies tags with priority).
- Union browse caps at 12 tags per resolution (runaway wildcards would otherwise fetch dozens of listings).
- Searchid pages and tag listings are **primary-only** (ids are site-specific); everything else falls back to the mirror.
- The 755 curated tags intentionally drop the long tail of the 6,723 harvest (one-off / character-name / Chinese-only tags). The union of wtr-lab taxonomy + popular tags + Honghuang family covers the tropes novels are actually tagged with; if a specific tag is ever requested, re-run the curation with it added.
- wsrv.nl is a third-party image proxy (operated by the images.weserv.nl project); the "direct" setting is the escape hatch if it is ever unavailable.

---

## v2.0.0 change set (context)

'''
src = src[:m.start()] + new_limits

open(P, "w", encoding="utf-8").write(src)
print(f"rewritten: {P} ({len(src)} bytes)")
