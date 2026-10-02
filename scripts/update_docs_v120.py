#!/usr/bin/env python3
"""Update README.md, pull_request.md and MAINTENANCE.md for wtrlab v1.2.0."""

# ── README.md ───────────────────────────────────────────────────────────────
R = "/home/z/my-project/download/README.md"
src = open(R, encoding="utf-8").read()

src = src.replace(
    "**File:** `wtrlab.lua` · **Version:** 1.1.9",
    "**File:** `wtrlab.lua` · **Version:** 1.2.0", 1)

src = src.replace(
    "A NoveLA external Lua source for WTR-Lab, with novel-finder filters (title search + keyword tag search across 888 tags + per-category tag dropdowns, 40 genres), HTML-first catalog fetching, local decryption of encrypted chapter bodies, and graceful handling of the site's Cloudflare + \"Security Check\" (Turnstile) rate limiting.",
    "A NoveLA external Lua source for WTR-Lab, with novel-finder filters (title search + keyword tag search across 888 tags + multi-select tag chip groups per category, 40 genres), tag discovery straight from the catalog search bar, HTML-first catalog fetching, paragraph-safe chapter rendering, local decryption of encrypted chapter bodies, and graceful handling of the site's Cloudflare + \"Security Check\" (Turnstile) rate limiting.", 1)

src = src.replace(
    "   - **Translation Mode** — `AI (Beta)` (default; server-side AI translation, English output) or `Raw (Web)` (raw Chinese; recommended only with reader-side translation).",
    "   - **Translation Mode** — `AI (Beta)` (default; server-side AI translation, English output), `Raw (Web)` (raw Chinese; recommended only with reader-side translation) or `Web+` (raw Chinese with the book's own glossary terms pre-applied in English; pair it with the app translator).", 1)

new_section = """## 2. What's new in 1.2.0 (vs 1.1.9)

> **If your chapters recently started rendering as one giant "mashup" paragraph:**
> the app auto-updated the extension repo's wtrlab to **upstream 1.1.8** (Sep 7),
> whose new *Web+* mode gsubs glossary translations over the **raw encrypted-JSON
> string**. A translation containing `"` / `\\` breaks the JSON → the parser fails →
> the whole chapter renders as ONE paragraph of raw JSON (a translation containing
> `","` splits it into TWO). This plugin applies the glossary **per paragraph on
> parsed text** with escaped, pcall-armored patterns — the bug cannot occur here.
> Install this file over the old source (Extensions → row → Edit Lua → paste).

### Paragraph safety (the "mashup paragraph" fix)

| Area | Change |
|---|---|
| **Embedded newlines split** | Body elements that carry line breaks (`\\n`, `\\r\\n`, `\\r`) are now split so **every source line becomes its own paragraph**. The reader treats a blank line (`\\n\\s*\\n`) as the paragraph boundary and a single `\\n` as a merged soft break — a chapter mixing both displayed as visually glued blocks. This matches the site's own reader, which splits plain-string bodies on `\\n`. |
| **CRLF normalization** | `\\r\\n` / lone `\\r` are normalized to `\\n` before splitting (previously only string bodies handled this, array elements did not). |
| **gsub armor** | All glossary-marker, patch and Web+ term replacements go through `safeGsub` (Lua pattern **and** replacement escaping + `pcall`). A book whose glossary/patch data contains `%`, `(`, `)`, `.` etc. used to abort the chapter mid-download with `malformed pattern` / `invalid use of '%'` — now the single bad term is skipped and the chapter renders. |

### Multiple tags per category (chip groups)

| Area | Change |
|---|---|
| **11 `Tags: <category>` chip groups** | The per-category dropdowns (single choice + `Any`) are now **multi-select checkbox chip groups**: tap several tags in the same category and they ALL apply (merged into one `ti=` request, dedup'd). Every one of the 888 tags is visible as a chip (the app alphabetizes each group). Genres stays the only tristate filter. |
| **Back-compat** | A stale saved sheet from 1.1.9 still carrying the old single-value form (`tag_pick_N` as a plain string) is honored; unknown/junk ids are skipped. |

### Tag Search behaves like a real search

| Area | Change |
|---|---|
| **Partial keyword = all matches** | Typing `sys` no longer raises an "ambiguous" error demanding the exact name — it now **includes every tag whose name contains it** (`sys` → Game Ranking System, Level System, System, System Misunderstanding). "Shows everything as a search result." Exact full names, raw tag ids and the explicit `keyword*` wildcard still work as before; only a keyword matching **nothing** raises an error. |

### Tag discovery from the catalog search bar (tag books)

| Area | Change |
|---|---|
| **Search finds tags too** | Searching the catalog now lists matching **tags first** as tappable results — `🏷 Honghuang — Adaptations` — followed by the novel matches. |
| **Tag "books"** | Opening a tag result renders it as a browsable book: the **chapter list is the tag's novels** (most-read first, up to 100), the description shows the live novel count, and opening any entry **previews that novel's first chapter**. Search a novel's title in the catalog to add the full book. This is the closest NoveLA's static filter sheet can get to the site's own tag autocomplete — the search bar is the only dynamic list UI the app exposes. |

### Web+ mode (upstream parity, safe implementation)

| Area | Change |
|---|---|
| **Mode option** | `Web+ (glossary raw - best with app translator)` joins the mode picker (same `wtrlab_mode` key; existing settings carry over). It requests the site's `webplus` translate mode: raw Chinese with the **book's own glossary** applied — terms come out in English, the rest via the app's translator. |
| **Safe application** | Unlike upstream 1.1.8 (gsubs the whole encrypted-JSON string with raw, unescaped patterns), the glossary here is applied **per paragraph after parsing**, through `safeGsub` — see the paragraph-safety section above. |

## 2a. What's new in 1.1.9 (vs 1.1.8)"""

src = src.replace("## 2. What's new in 1.1.9 (vs 1.1.8)", new_section, 1)

# §8 test status
src = src.replace("## 2a. What's new in 1.1.8 (vs 1.1.7)",
                  "## 2b. What's new in 1.1.8 (vs 1.1.7)", 1)

open(R, "w", encoding="utf-8").write(src)
print("README.md updated")

# ── MAINTENANCE.md ──────────────────────────────────────────────────────────
M = "/home/z/my-project/download/MAINTENANCE.md"
m = open(M, encoding="utf-8").read()

# version row in Part 0 (wtrlab entry)
m = m.replace("wtrlab.lua v1.1.9", "wtrlab.lua v1.2.0")

# 1.7 version history row — prepend
hist_anchor = "| 1.1.9 |"
if hist_anchor in m:
    m = m.replace(hist_anchor,
        "| 1.2.0 | 2026-09-10 | Paragraph safety (element newline splitting, CRLF normalization, safeGsub pcall+escape armor on ALL glossary/patch/Web+ gsubs); 11 tag_pick selects → multi-select checkbox chip groups (filters[key..\"_included\"] arrays, legacy string form honored); tagSearchResolve all-match semantics (partial keyword includes EVERY match, no ambiguity error — only zero-match raises); tag discovery via catalog search (tag items → tag \"books\": chapters = the tag's novels, most-read first, capped 100, chapter-1 previews); Web+ mode (webplus translate + per-paragraph glossary, vs upstream's raw-JSON gsub). Root cause of user's \"mashup paragraph\": upstream 1.1.8 (auto-updated Sep 7) Web+ gsub breaks the JSON when a glossary translation contains quotes → json_parse fails → whole chapter = 1 paragraph. |\n| 1.1.9 |", 1)

# gotcha #31 (new)
gotcha_anchor = "## Gotchas library"
if gotcha_anchor in m:
    m = m.replace(gotcha_anchor, """## Gotchas library

31. **Upstream divergence warning**: upstream `HnDK0/external-sources` main = our 1.1.7 + their own 1.1.8 (Web+ mode with a gsub over the RAW decrypted JSON string). The app AUTO-UPDATES repo extensions — the user's installed copy may silently become upstream 1.1.8 even after importing ours. When a wtrlab regression report arrives, FIRST check which copy/version is loaded (Extensions screen version label). Upstream's Web+ JSON-mangling (translations containing `"`/`\\`/`","`) yields the exact "whole chapter as 1-2 mashup paragraphs" symptom — our v1.2.0 applies the glossary per-paragraph with escaped patterns and cannot hit it.
32. **Checkbox filter marshalling** (LuaFilterSupport.kt): `type = "checkbox"` groups arrive in Lua as `filters[key .. "_included"]` = 1-based Lua array table (there is NO `_excluded` for checkbox — use a separate group or a text field for exclusions). `multiselect` defaults to TRUE. `select` has NO multi-select form at all. The app sorts checkbox chips alphabetically by label.
33. **Lua lexical scoping for helper blocks**: a `local` helper table defined later in the file is invisible to functions defined EARLIER (they resolve the name as a nil global at call time → "attempt to index a nil value"). Tag-book helpers must live BEFORE the first function that uses them (before the Catalog section), not grouped with Book details.
34. **string.find with plain=true must NOT use pattern escapes** (`"novel%-finder"` never matches — `%-` is literal text in plain mode). Pattern escapes only apply when plain is nil/false.
""", 1)

open(M, "w", encoding="utf-8").write(m)
print("MAINTENANCE.md updated")

# ── pull_request.md: rewrite as the 1.2.0 PR ────────────────────────────────
P = "/home/z/my-project/download/pull_request.md"
pr = """# WTR-Lab plugin v1.2.0 — paragraph-safety + multi-tag + tag search

**Base:** upstream `HnDK0/external-sources` `mtl/wtrlab.lua` @ 1.1.8 (which is our 1.1.7 + their Web+ addition)
**File:** `wtrlab.lua` (3,987 lines, ~159 KB) · **Tests:** 64/64 live · 49/49 mock (bit32 + nobit32) · all integration checks

## TL;DR

1. **"Mashup paragraph" root-caused and fixed.** Upstream 1.1.8 (auto-delivered to devices Sep 7) applies the Web+ book glossary with a `gsub` over the **raw decrypted JSON string**. A translation containing `"`/`\\` breaks the JSON; `json_parse` then fails and the entire chapter renders as **one paragraph of raw JSON** (or two, when the translation contains `","`). This PR applies glossaries **per paragraph on parsed text** through escaped, pcall-armored `safeGsub` — and hardens every other gsub in the chapter pipeline the same way. Elements embedding newlines are now split into real paragraphs, and CRLF is normalized.
2. **Multiple tags per category.** The 11 category dropdowns become **multi-select checkbox chip groups** — pick any number of tags per category; all merge into one `ti=` request.
3. **Tag search shows everything.** A partial keyword now includes **every** matching tag (no more "ambiguous — type the exact name" error). Zero-match keywords still raise a typo guard.
4. **Tag discovery from the search bar.** Catalog search lists matching **tags first** as tappable results; opening one browses that tag's novels as a "book" (chapters = top 100 novels by readers, each entry previews the novel's first chapter).
5. **Web+ mode with the safe implementation** (upstream's feature, minus the JSON-mangling bug).

## 1. The paragraph fix in detail

### The bug (upstream 1.1.8)

```lua
-- upstream: gsub over the WHOLE encrypted-JSON string, raw patterns
if mode == "webplus" and next(termByOriginal) then
    for original, translation in pairs(termByOriginal) do
        resolvedBody = resolvedBody:gsub(original, translation)  -- 💥
    end
end
```

- `original` is used as a Lua **pattern** (terms with `%`/`(`/`)` → *malformed pattern* error → chapter fails).
- `translation` is used as a Lua **replacement** (`%` → error; `"`, `\\` → the JSON string breaks → `json_parse` returns nil → `buildParagraphs` falls to the `\n`-split branch → **the whole chapter becomes 1 paragraph of JSON**; `","` in a translation splits it into 2 giant elements).

### The fix (this PR)

- `safeGsub(text, pattern, replacement)`: escapes **both** sides (`escLuaPattern` / `escLuaReplacement`) and wraps in `pcall` — a single bad term is skipped, never crashes the chapter.
- Web+ terms are applied **per paragraph**, after JSON parsing — the JSON structure is never touched.
- `buildParagraphs` now splits **every body element on embedded newlines** (`\n`, `\r\n`, `\r`), matching the site's own reader (plain strings are split on `\n` by the site's TipTap parser). This also removes the reader's mixed-separator hazard: a single `\n` between blank-line breaks renders as a merged soft break.
- Glossary markers, chapter patches and Web+ terms all go through `safeGsub`.

**Verified:** the exact upstream-breaking input (a glossary translation containing `"The Sage"` quotes) produces **54 clean paragraphs** through this code path (MOCK TEST I2) where upstream produces 1 mashup.

## 2. Tag filters

| Aspect | 1.1.9 | 1.2.0 |
|---|---|---|
| Per-category picking | 11 dropdowns, single choice + `Any` | 11 **multi-select chip groups** (checkbox) — several tags per category |
| Marshalling | `filters["tag_pick_N"]` (string) | `filters["tag_pick_N_included"]` (Lua array; legacy string form still honored) |
| Keyword search | substring → 1 match ok, **multiple → error** ("ambiguous, type exact name") | partial keyword **includes every match**; only zero-match errors |
| Discovery | none (must know names / browse dropdowns) | **search bar lists matching tags first**; tag "books" browse the tag's novels |

### Tag books (search-bar discovery)

- `getCatalogSearch` page 1 prepends up to 8 tag matches (`🏷 <label> — <category>`, URL = the site's own finder with `ti=` applied).
- Opening one: title `🏷 <Tag> (tag view)`, description with the live novel count, hash `tags:<ids>|<count>`, and the **chapter list = the tag's novels** (most-read first, up to 100 — 10 finder requests, dedup'd, stops at `count`). Each entry points at the novel's `chapter-1` (a preview; search the title in the catalog to add the full book).
- All other book functions short-circuit cleanly for finder URLs (nil cover/rating/status, empty genres).

## 3. Regression audit

| Check | Status |
|---|---|
| 15/15 required functions, `cf_options` absent | ✓ (SyntaxCheck) |
| Chapter text: AI / RAW(arr: local decrypt) / Web+ / proxy fallback / turnstile error | ✓ live + mock |
| Paragraph counts for real captured payloads (96 / 54 paragraphs) | ✓ |
| HTML-first catalog, pagination boundaries (F1-F3), buildId persistence | ✓ |
| `minc=` stays dead (count_type/count_filter/count_value used) | ✓ |
| Genre tristate (40) unchanged; `wtrlab_mode` key preserved (AI/Raw settings carry over) | ✓ |
| All 888 tag ids present and site-accurate; Honghuang #801 | ✓ |
| Chapter fetch delay setting unchanged | ✓ |
| novel543.lua untouched | ✓ (196 PASS / 0 FAIL / 1 SKIP suite unchanged) |

## 4. Reviewer checklist

- [ ] `safeGsub` + `escLuaPattern`/`escLuaReplacement` armor every gsub in the chapter pipeline
- [ ] `buildParagraphs` splits elements on `\n`/`\r\n`/`\r` and never emits single `\n`
- [ ] 11 `tag_pick_N` filters are `type = "checkbox"` with no `Any` placeholder; `getCatalogFiltered` reads `_included` arrays and validates ids
- [ ] `tagSearchResolve` includes all substring matches; only zero-match raises
- [ ] `getCatalogSearch` page-1-only tag prepending; tag-book functions detect `novel-finder?ti=` URLs
- [ ] Web+ glossary applied per paragraph AFTER `json_parse`, never on the raw JSON string
- [ ] Version = 1.2.0; header changelog updated
"""
open(P, "w", encoding="utf-8").write(pr)
print("pull_request.md rewritten")
