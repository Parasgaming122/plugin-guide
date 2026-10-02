# WTR-Lab plugin v1.2.1 — poster fix on top of 1.2.0

**Base:** upstream `HnDK0/external-sources` `mtl/wtrlab.lua` @ 1.1.8 (which is our 1.1.7 + their Web+ addition)
**File:** `wtrlab.lua` (~160 KB) · **Tests:** 66/66 live (1.2.1) · 49/49 mock (1.2.0, unchanged paths) · all integration checks

## TL;DR — the 1.2.1 delta

**Posters fixed.** `img.wtr-lab.com` covers redirect to signed 300 KB+ images and sit behind Cloudflare; image URLs are **exempt** from the engine's CF WebView bypass (`STATIC_EXTENSIONS`), so a challenged cover = a challenge page handed to the image decoder = silently broken poster. All covers now go through the engine-whitelisted **wsrv.nl image proxy** (`w=450` resize ≈ 8× smaller downloads), with a **Cover Images** setting (`proxy` default / `direct`) to revert. Live-verified: the proxied URL serves `200 image/jpeg`. Everything below is the 1.2.0 change set (unchanged).

## TL;DR — 1.2.0 change set (context)

1. **"Mashup paragraph" root-caused and fixed.** Upstream 1.1.8 (auto-delivered to devices Sep 7) applies the Web+ book glossary with a `gsub` over the **raw decrypted JSON string**. A translation containing `"`/`\` breaks the JSON; `json_parse` then fails and the entire chapter renders as **one paragraph of raw JSON** (or two, when the translation contains `","`). This PR applies glossaries **per paragraph on parsed text** through escaped, pcall-armored `safeGsub` — and hardens every other gsub in the chapter pipeline the same way. Elements embedding newlines are now split into real paragraphs, and CRLF is normalized.
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
- `translation` is used as a Lua **replacement** (`%` → error; `"`, `\` → the JSON string breaks → `json_parse` returns nil → `buildParagraphs` falls to the `
`-split branch → **the whole chapter becomes 1 paragraph of JSON**; `","` in a translation splits it into 2 giant elements).

### The fix (this PR)

- `safeGsub(text, pattern, replacement)`: escapes **both** sides (`escLuaPattern` / `escLuaReplacement`) and wraps in `pcall` — a single bad term is skipped, never crashes the chapter.
- Web+ terms are applied **per paragraph**, after JSON parsing — the JSON structure is never touched.
- `buildParagraphs` now splits **every body element on embedded newlines** (`
`, `
`, `
`), matching the site's own reader (plain strings are split on `
` by the site's TipTap parser). This also removes the reader's mixed-separator hazard: a single `
` between blank-line breaks renders as a merged soft break.
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
- [ ] `buildParagraphs` splits elements on `
`/`
`/`
` and never emits single `
`
- [ ] 11 `tag_pick_N` filters are `type = "checkbox"` with no `Any` placeholder; `getCatalogFiltered` reads `_included` arrays and validates ids
- [ ] `tagSearchResolve` includes all substring matches; only zero-match raises
- [ ] `getCatalogSearch` page-1-only tag prepending; tag-book functions detect `novel-finder?ti=` URLs
- [ ] Web+ glossary applied per paragraph AFTER `json_parse`, never on the raw JSON string
- [ ] Version = 1.2.0; header changelog updated
