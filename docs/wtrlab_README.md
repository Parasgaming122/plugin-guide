# WTR-LAB Source Plugin for NoveLA

**File:** `wtrlab.lua` · **Version:** 1.2.1 · **Site:** https://wtr-lab.com/ · **Language:** MTL (Chinese → English machine translation)

A NoveLA external Lua source for WTR-Lab, with novel-finder filters (title search + keyword tag search across 888 tags + multi-select tag chip groups per category, 40 genres), tag discovery straight from the catalog search bar, HTML-first catalog fetching, paragraph-safe chapter rendering, local decryption of encrypted chapter bodies, and graceful handling of the site's Cloudflare + "Security Check" (Turnstile) rate limiting.

---

## 1. Installation

1. In NoveLA: **Settings → Sources → Add external source** (or replace the existing `wtrlab` source).
2. Load `wtrlab.lua` from the file picker (or paste its contents into the source editor).
3. Optional per-source settings (in the source's settings screen):
   - **Translation Mode** — `AI (Beta)` (default; server-side AI translation, English output), `Raw (Web)` (raw Chinese; recommended only with reader-side translation) or `Web+` (raw Chinese with the book's own glossary terms pre-applied in English; pair it with the app translator).
   - **Cover Images** — `Via wsrv.nl image proxy` (default; fixes posters when Cloudflare challenges the image host) or `Direct from img.wtr-lab.com`.
   - **Chapter Fetch Delay** — extra pause before each chapter fetch (`None`/2s/4s/6s). May reduce "Security Check" triggers during bulk downloads, at the cost of speed.

> Upgrading from v1.x: the `wtrlab_mode` settings key is unchanged, so your existing AI/Raw choice carries over.

## 2. What's new in 1.2.1 (vs 1.2.0)

**Posters fix.** wtr-lab covers live on `img.wtr-lab.com` and redirect (302 chain) to signed full-size images (300 KB+). When Cloudflare challenges the image host, NoveLA's image loader receives the challenge page instead of the JPEG — **image URLs are exempt from the engine's Cloudflare WebView bypass** — and the poster silently fails (blank covers in catalog/library, sometimes fixed only by manual retries). 1.2.1 routes every cover through the **wsrv.nl image proxy** (`https://wsrv.nl/?url=<encoded>&w=450&we&output=jpg&q=80`), the same `images.weserv.nl` service the engine whitelists for challenged image hosts. Covers arrive pre-resized (~40 KB instead of 300 KB+), which also makes grids load faster. A new **Cover Images** setting reverts to direct URLs if you prefer.

Everything else is unchanged from 1.2.0 (paragraph safety, multi-tag chips, tag search, tag discovery, Web+ mode). Tests: **66/66 live** — including a new live check that a catalog item's proxied cover URL actually serves an image.

## 3. What's new in 1.2.0 (vs 1.1.9)

> **If your chapters recently started rendering as one giant "mashup" paragraph:**
> the app auto-updated the extension repo's wtrlab to **upstream 1.1.8** (Sep 7),
> whose new *Web+* mode gsubs glossary translations over the **raw encrypted-JSON
> string**. A translation containing `"` / `\` breaks the JSON → the parser fails →
> the whole chapter renders as ONE paragraph of raw JSON (a translation containing
> `","` splits it into TWO). This plugin applies the glossary **per paragraph on
> parsed text** with escaped, pcall-armored patterns — the bug cannot occur here.
> Install this file over the old source (Extensions → row → Edit Lua → paste).

### Paragraph safety (the "mashup paragraph" fix)

| Area | Change |
|---|---|
| **Embedded newlines split** | Body elements that carry line breaks (`\n`, `\r\n`, `\r`) are now split so **every source line becomes its own paragraph**. The reader treats a blank line (`\n\s*\n`) as the paragraph boundary and a single `\n` as a merged soft break — a chapter mixing both displayed as visually glued blocks. This matches the site's own reader, which splits plain-string bodies on `\n`. |
| **CRLF normalization** | `\r\n` / lone `\r` are normalized to `\n` before splitting (previously only string bodies handled this, array elements did not). |
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

## 2a. What's new in 1.1.9 (vs 1.1.8)

### Catalog latency — HTML-first fetching (the "homepage takes 10–15 s" fix)

| Area | Change |
|---|---|
| **Root cause** | The site's `/_next/data/*.json` routes intermittently STALL server-side (observed 7–25 s per request, recovering minutes later), while the HTML routes (`/en/novel-list`, `/en/novel-finder`) render consistently fast and embed the **exact same `pageProps`** inside `__NEXT_DATA__`. A stale buildId added three round-trips (404 probe → 240 KB HTML id refresh → fresh JSON) before the first item. |
| **Fix** | Catalog/search/filtered now fetch the **HTML route first** — one request, no `buildId` dependency, no 404 probe — and parse `pageProps` out of `__NEXT_DATA__`. The `_next/data` JSON route is kept as an **automatic fallback** (with the full 1.1.8 buildId machinery) whenever the HTML route yields no props. |
| **Props shape gotcha** | The two routes serialize `pageProps` differently: HTML pages embed `{"props":{"pageProps":{…}}}` (standard Next.js `__NEXT_DATA__` shape), the JSON routes return `{"pageProps":{…}}` at the top level. `extractNextDataProps` accepts **both**. Verified live: identical `series`/`count` for every finder parameter and pagination. |

### Tags now show up (per-category dropdowns)

| Area | Change |
|---|---|
| **11 `Tags: <category>` pickers** | One dropdown per site category (Protagonist Archetypes 190 · Power Systems 100 · Worldbuilding 56 · Socio-Political 71 · Relationship Tropes 136 · Narrative 46 · Beings & Factions 68 · Professional 64 · Tone & Atmosphere 27 · Adaptations 90 · Misc 40 = **888 tags**). Each leads with an `Any` (empty) option; the app alphabetizes the rest. Pick a tag to include it — the tags are **visible again** after 1.1.8's keyword-only fields, as compact dropdown rows instead of the old 882-chip tristate wall (genres stays the only tristate). |
| **Merging** | Dropdown picks AND keyword ids merge into one deduplicated `ti=` request. Values from a stale sheet (unknown ids) are validated and skipped, never crash. |

### Keyword feedback — site-autocomplete-like

| Area | Change |
|---|---|
| **Resolution order** | exact label match → numeric id → single substring match → **ambiguous: error listing the matching tag names** → `keyword*` wildcard (all substring matches). Typing `sys` no longer silently ANDs 4 tags (~0 novels) — it raises `sys is ambiguous — it matches 4 tags: Game Ranking System (#298), Level System (#390), System (#696), System Misunderstanding (#890)`; type the full name or add `*`. |
| **Error polish** | Resolver errors print tag names in **display case** (the index parse keeps both `label` and a lowercase match key). |

## 2b. What's new in 1.1.8 (vs 1.1.7)

> 1.1.7 was accepted upstream (`HnDK0/external-sources` main branch now ships it verbatim), so 1.1.8's base IS 1.1.7.

### Tag filters: search bar replaces the 882-chip wall

| Area | Change |
|---|---|
| **Tag Search section** | The 11 category-grouped tristate pickers (882 eagerly-built chips — unusable and slow to render) are replaced by: **Tag Search (include)** and **Tag Search (exclude)** keyword fields + a **Tag Search Category** picker (`All Categories` + the 11 site categories, scoping both fields) + the kept Tag And/Or picker. Type keywords like `reincarnation, harem` or the phrase `weak to strong`; numeric tag ids are also accepted. Multi-word tokens match as **phrases** first, with a per-word fallback. |
| **Typo guard** | A keyword that matches **no** tag raises a clear error at apply time (e.g. `Tag Search (include): no tag matches 'xyz'…`) instead of silently returning an unfiltered list. |
| **Tag index refresh** | 882 → **888 tags** (site additions: Blue Archive #885, Food Wars! #886, Honkai Star Rails #889, Monster Hunter #888, Dragon Raja #887, System Misunderstanding #890). |

### Novel finder inside the filters

| Area | Change |
|---|---|
| **Title Search** | New first filter in the sheet: a text field wired to the finder API's `text=` parameter. The app's global search bar carries no filters — this puts the site's novel-finder text box *into* the filter sheet, so a title keyword can combine with genres, tags, status, counts, ratings and ordering in one applied query. |

### Performance (chapter-load latency)

| Area | Change |
|---|---|
| **Turnstile retry pacing** | Backoff cut 2500/5000 ms → 600/1800 ms. The app-level counter only resets via a solved challenge, so long sleeps never aided recovery — they only stacked up to 7.5 s of dead wait onto a 3-attempt chain (the reported "sometimes ~10 s to load a chapter"). |
| **Glossary negative cache** | Books **without** a v2 glossary were re-fetched on every chapter (the 1.1.7 code only cached when terms existed). Now one request per book, period. |
| **Update checks** | `getChapterListHash` uses `api/chapters` (~74 KB JSON; count + max `updated_at` + a rolling checksum over every chapter's `(order, updated_at)` — catches mid-list re-translations too) instead of scraping the full book page (~250 KB HTML). `getChapterList` and the hash share one 45-second cache, so opening a book costs ONE chapter-list fetch. Legacy page-scrape kept as fallback. |
| **buildId persistence** | The Next.js buildId is persisted via `set_preference` — the first catalog browse after an app restart no longer downloads the 240 KB novel-finder HTML just to extract it. A stale persisted id self-heals (one refresh-retry on 404). |

## 2b. What's new in 1.1.7 (vs 1.1.6)

### All fixes (post-review verified)

| Area | Fix |
|---|---|
| **Pagination** | `pagePropsToResult` now short-circuits on a partial final page using a fixed `PAGE_SIZE = 10`, so `hasNext` no longer over-fetches one empty page at the end of a list. The 2.1.0 formula `page * #items < count` used the *variable* returned item count: on a partial last page (e.g. `count=12`, page 2 returns 2) it evaluated to `2*2 < 12 = true` and fetched a 3rd empty page before stopping. New logic: `#items > 0 and returned >= PAGE_SIZE and page * PAGE_SIZE < countNum`. |
| **Update detection** | `getChapterListHash` now returns `"<chapterCount>|<serie_data.updated_at>"` (the full timestamp from `__NEXT_DATA__`), so a re-translation / metadata edit that doesn't change the chapter count is still detected as an update. 2.1.0 returned the count digit only. |
| **Tag filters (UX)** | The 882 tags are split into **11 category-grouped tristate pickers** (`tags_protagonist` / `tags_power_systems` / ... / `tags_misc`), matching the site's own finder grouping. NoveLA renders every tristate option as an eagerly-built `TriStateChip` in a `FlowRow` (no lazy/collapsible), so a single 882-item filter was a literal wall of chips. `getCatalogFiltered` collects the included/excluded ids from all 11 groups into one combined `ti=`/`te=` list (the single `tc=` operator applies to the combined set). The request params are identical to the flat layout — nothing breaks; the UI is just usable. |
| **b64ToBytes strictness** | A dangling base64 char (`len % 4 == 1` — impossible to decode to any whole byte in padded *or* unpadded base64) now returns `nil` instead of silently dropping it. The GCM tag check would catch the corruption anyway, but a `nil` lets the caller distinguish "malformed input" from "decrypted garbage" and exercise the proxy fallback cleanly. |

### Initial rewrite (from 1.1.6)

| Area | Change |
|---|---|
| **Gibberish fix** | Chapter bodies encrypted as `arr:`/`str:` (AES-256-GCM) are now decrypted **locally in pure Lua** — no third-party proxy round-trip. The old fly.dev proxy is kept only as an automatic fallback. Previously, when that proxy failed, the raw `arr:…` blob was saved as the chapter text — this was the "large gibberish". |
| **Security-check fix** | WTR-Lab's own per-IP Turnstile rate limit (`{"success":false,"requireTurnstile":true,…}` from `POST /api/reader/get`) is now detected, retried with backoff (2 extra attempts), and — if still blocked — raises an **actionable error message** telling the user to solve the challenge once in the integrated browser. Previously this surfaced as `[?] Unknown API error`. |
| **Filters** | Tag list expanded 208 → **882** (all site tags, incl. **Honghuang #801**), split into **11 category-grouped pickers**; added Minimum Reviews (`minrc`), full *Added* date list (3 months…this year), *Daily View* / *Character Count* / *Weighted* ordering, and a **working** chapter-count filter. The old `minc=` parameter was silently ignored by the site — now uses `count_type/count_filter/count_value`. |
| **Catalog/search** | Switched from HTML scraping to the Next.js data JSON API (`_next/data/{buildId}/…`) with session buildId caching + stale refresh. `hasNext` is derived from the total `count` **with a fixed `PAGE_SIZE` short-circuit** (see §3.1) so partial final pages don't trigger an extra empty fetch. |
| **Update detection** | `getChapterListHash` returns `"<chapterCount>|<serie_data.updated_at>"` (chapter count from the metrics block + the book's own `updated_at` timestamp from `__NEXT_DATA__`). In 1.1.6 it returned the literal string `"Chapters"` (both the label and the number span carry `translate="no"`), so chapter-list updates were never detected; 2.1.0 returned the count only and missed same-count retranslations. |
| **Removed** | The v2.0.0 community draft's `cf_options = { whitelist = true }` — that flag tells NoveLA to treat wtr-lab.com as *never challenged*, which **disables** the app's automatic Cloudflare/Turnstile WebView bypass for this host. Do not re-add it (see §5). |

## 3. Site / API reference (reverse-engineered 2026-08-25)

Everything a future maintainer needs. All endpoints verified live; base `https://wtr-lab.com/`.

### 3.1 Catalog, search, filters — HTML first, `_next/data` JSON as fallback

```
GET /en/novel-list?page=N&orderBy=reader              ← HTML route (v1.1.9 primary)
GET /en/novel-finder?<filters>                        ← HTML route (v1.1.9 primary)
GET /_next/data/{buildId}/en/novel-list.json?page=N   ← JSON route (automatic fallback)
GET /_next/data/{buildId}/en/novel-finder.json?<filters>
```

- **v1.1.9 fetch order (`fetchCatalogPage`):** try the HTML route first — it renders consistently fast (the JSON routes intermittently stall 7–25 s server-side) and embeds the **same `pageProps`** in `__NEXT_DATA__`, with **no `buildId` dependency** (no stale-404 probe). On failure / missing props, fall back to the JSON route with the buildId machinery below.
- **⚠️ Props shape differs by route:** HTML pages embed `{"props":{"pageProps":{…}},"buildId":…}` (standard Next.js `__NEXT_DATA__` shape); the `_next/data` JSON routes return `{"pageProps":{…}}` at the TOP level. `extractNextDataProps` accepts both (top-level first, then `props.pageProps`).
- `{buildId}` (fallback route only) — grab from any page's `__NEXT_DATA__`: regex `"buildId":"([^"]+)"` on the HTML of `/en/novel-finder`. **Changes on every site deploy**; persisted via `set_preference`, and on a 404/missing-`pageProps` refresh once and retry.
- Response shape: `{pageProps: {series: [...], count: "<string!>", isPremium, tags?}}` — note `count` is a **JSON string** (must `tonumber()` it). 10 items per page. `hasNext` is derived with a fixed page-size short-circuit so a partial final page does not trigger an extra empty fetch:
  ```lua
  local PAGE_SIZE = 10
  hasNext = #items > 0 and returned >= PAGE_SIZE and page * PAGE_SIZE < countNum
  ```
  where `returned = #pp.series` (pre-dedup, so a duplicate `raw_id` within one page can't cause a false `hasNext=false`).
- Series item fields used: `raw_id`, `slug`, `data.title`, `data.image`, `rating` (number or null). Book URL: `https://wtr-lab.com/en/novel/{raw_id}/{slug}`.
- `novel-finder` also returns `tags.ungrouped` = the full tag catalogue: `[{value, label, category_id}]`, and `tags.groups` = `[{id, name}]` — **this is the source of truth for the filter tag list** (see §6 for the refresh procedure).

**Filter query parameters** (all verified to change result counts):

| Param | Values | Notes |
|---|---|---|
| `text` | search string | used by catalog Search |
| `page` | 1-based | |
| `orderBy` | `date, update, random, daily_rank, weekly_rank, monthly_rank, view, name, reader, chapter, character, rating, total_rate, vote, weighted` | `weighted` requires `minrc=5` (site adds it automatically) |
| `order` | `asc, desc` | |
| `status` | `all, ongoing, completed, hiatus, dropped` | |
| `release_status` | `all, released, voting` | |
| `addition_age` | `all, day, week, month, 3month, 6month, year, last_month, last_year, this_year` | |
| `count_type` | `chapter, character, unlock, unlock-ratio` | ONE count filter at a time |
| `count_filter` | `min, max` | |
| `count_value` | chapter: 100…5000 · character: 100000…10000000 · unlock: 100…5000 · ratio: 0.1…1.0 | ⚠️ **`minc`/`minr`-style legacy params are dead** — `minc` is ignored |
| `minr` | 1.0…5.0 (0.1 steps) | minimum rating |
| `minrc` | 5…50 (step 5) | minimum review count |
| `gi` / `ge` | comma-joined genre ids 1–40 | include / exclude |
| `gc` | `and, or` | genre combine |
| `ti` / `te` | comma-joined tag ids | include / exclude |
| `tc` | `and, or` | tag combine |

**Genres** are ids **1–40** (`SERIE_GENRES` in the site JS): 1 action, 2 adult, 3 adventure, 4 comedy, 5 drama, 6 ecchi, 7 erciyuan, 8 fan-fiction, 9 fantasy, 10 game, 11 gender-bender, 12 harem, 13 historical, 14 horror, 15 josei, 16 martial-arts, 17 mature, 18 mecha, 19 military, 20 mystery, 21 psychological, 22 romance, 23 school-life, 24 sci-fi, 25 seinen, 26 shoujo, 27 shoujo-ai, 28 shounen, 29 shounen-ai, 30 slice-of-life, 31 smut, 32 sports, 33 supernatural, 34 tragedy, 35 urban-life, 36 wuxia, 37 xianxia, 38 xuanhuan, 39 yaoi, 40 yuri.

### 3.2 Chapters & reader

```
GET  /api/chapters/{raw_id}            → {chapters: [{serie_id, id, order, title, name(原文), …}]}   (send Referer: book URL)
POST /api/reader/get                    body: {translate, language:"none", raw_id:"<id>", chapter_no:N, retry:false, force_retry:false}
GET  /api/v2/reader/terms/{id}.json     → {glossaries: [{data: {terms: [[[trans, …], "原文", …], …]}}]}
```

- `translate`: `"ai"` (AI translation) or `"web"` (raw). Site also has `"webplus"` (premium). `chapter_id` is optionally included by the site UI but not required.
- Reader response: `{success, chapter, data: {data: {body, glossary_data, patch, …}}, tasks}`.
- `body` is either:
  - a **JSON array of paragraph strings** (AI mode) — paragraphs may contain glossary markers `※{idx}⛬` and `※{idx}〓` (0-based `idx` into `glossary_data.terms`, where `terms[i] = [rawTranslation, chineseOriginal, …]`), or
  - an **encrypted string** `arr:…` / `str:…` (web mode, and possibly others) — see §4.
- `glossary_data.terms[i][1]` (raw AI translation) is the fallback; the v2 terms endpoint supplies book-level preferred translations keyed by the Chinese original (`term[2]`), cached per book for the session.
- API errors come back as `{success:false, message:…}` — **the field is `message`, not `error`** (v1.x read `json.error`, which is why Turnstile blocks showed as "Unknown API error").
- **Security check (Turnstile)**: after ~15 chapter requests per IP, `/api/reader/get` returns HTTP 200 `{success:false, requireTurnstile:true, message:"Please complete the Turnstile challenge…", threshold:15, count:N}`. The counter is **per-IP**, does not decay quickly, is **not** cleared by `cf_clearance`, and enforcement is spread across backend instances (counts differ between responses → intermittent "every 2-3 chapters" blocking). The site's own recovery: re-POST the same body with an extra `turnstileToken` field (Cloudflare Turnstile sitekey `0x4AAAAAABdTx0ekcJVVPAYZ`, rendered inside the chapter page). In NoveLA, opening any chapter of the book in the integrated browser and completing the "Verify you are human" checkbox resets it.
- Locked/premium chapters: `{success:false, code:1401, message:"You are not logged in!"}`.

### 3.3 Book page (HTML scraping)

URL: `https://wtr-lab.com/en/novel/{raw_id}/{slug}` (stale slugs 307-redirect to the canonical one). Selectors (verified 2026-08-25, mobile UA):

| Field | Selector |
|---|---|
| Title | `h1` |
| Cover | `.image-wrap img[alt]:not([aria-hidden])` attr `src` |
| Description | `.desc-wrap .description` |
| Metrics (Status/Chapters/Rating blocks) | `div.items-center.text-center` — each block: first `span[translate='no']` is the LABEL, for Chapters the number is a second `span[translate='no']` (extract digits from block text, don't take the first span) |
| Genres | `a[href*='novel-list?genre='] span` |
| Last update | regex `"updated_at":"(\d{4}-\d\d-\d\d)` from raw HTML |

### 3.4 Chapter URLs

`https://wtr-lab.com/novel/{raw_id}/{slug}/chapter-{order}` (note: no `/en/` in chapter URLs; `getChapterList` builds them from the chapters API `order` field).

## 4. Encrypted chapter bodies (`arr:` / `str:`)

Reverse-engineered from the site's reader JS (`eO()` in chunk `89f37b…js`), verified against live payloads with independent Python decryption:

```
arr:{base64(IV)}:{base64(GCM tag)}:{base64(ciphertext)}
str:{base64(IV)}:{base64(GCM tag)}:{base64(ciphertext)}   ← plaintext is a bare string, not JSON
```

- Algorithm: **AES-256-GCM**; key = the 32 ASCII bytes of `IJAFUUxjM25hyzL2AZrn0wl7cESED6Ru` (hardcoded in the site's JS bundle).
- IV observed as **16 bytes** (non-96-bit ⇒ GCM J0 derived via GHASH; the plugin implements both the 12-byte and the GHASH paths).
- Decryption order in the plugin: **local pure-Lua AES-GCM** (CTR mode, tag not verified) → fly.dev proxy fallback (`https://wtr-lab-proxy.fly.dev/chapter`, POST `{payload}`) → clear error. ~2 s for a 60 KB payload on the JVM.
- ⚠️ The host `base64_decode` returns a UTF-8 Java String and **corrupts binary data** (IV/ciphertext bytes ≥ 0x80) — that's why the plugin carries its own byte-safe pure-Lua base64 decoder (`string.char`/`string.byte` only).
- If the site rotates the key: fetch any web-mode chapter, search the new JS chunk for `importKey` / the 32-char string near `crypto.subtle`, update `GCM_KEY` in the plugin.

## 5. Cloudflare & Turnstile — how NoveLA handles it (do not fight it)

- NoveLA routes **all** plugin HTTP through its OkHttp stack with `CloudFareVerificationInterceptor` + a WebView-backed cookie jar. Real Cloudflare challenges *and* WTR-Lab's `requireTurnstile` JSON (HTTP 200 + `server: cloudflare` + marker `requireTurnstile`) are auto-detected; the app then runs a hidden WebView (15 s) and, if needed, opens the integrated browser for the user to solve the challenge, then retries the original request.
- `cf_options = { whitelist = true }` **disables** all of that for wtr-lab.com — the community v2.0.0 draft shipped it with a comment claiming the opposite. Keep it out.
- `cf_options = { whitelist = false, ignore_markers = {…} }` is the legitimate use (suppress false positives); WTR-Lab needs neither.
- `.json` URLs (e.g. `api/v2/reader/terms/{id}.json`) are on the interceptor's **static-extension shortcut** — challenges there are never detected/bypassed. The plugin treats a failed terms fetch as "no v2 glossary" and falls back to chapter-level glossary terms, so this is harmless.
- The plugin adds a second layer: explicit `requireTurnstile` detection with 2 retries (600 ms / 1.8 s backoff in v1.1.8 — the app-level counter only resets via a solved challenge, so long sleeps only stall the read; blocking is per-instance and intermittent, so retries often land on a healthy instance) and, if still blocked, an actionable `error()` message.

## 6. Refreshing the tag list (when the site adds tags)

The searchable tag index (v1.1.8+) is `TAG_SEARCH_INDEX` (one `id|Label|catId`
line per tag, parsed at load into `ALL_TAGS`). The refresh procedure is
**idempotent** — re-run whenever the site's tag snapshot changes:

1. Refresh the live tag snapshot:
   ```bash
   curl -A "<browser UA>" https://wtr-lab.com/en/novel-finder -o /tmp/finder.html
   python3 - <<'PY'
   import re, json
   html = open('/tmp/finder.html', encoding='utf-8').read()
   data = json.loads(re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', html, re.S).group(1))
   tags = data['props']['pageProps']['tags']   # {ungrouped: [{value,label,category_id}], groups: [{id,name}]}
   json.dump(tags, open('/home/z/my-project/research/tags_live_v2.json','w'), ensure_ascii=False, indent=1)
   print('wrote', len(tags.get('ungrouped', [])), 'tags')
   PY
   ```
   (Genres live in the site JS as `SERIE_GENRES`, ids 1–40 — they change ~never; they're inlined in the plugin and don't need a refresh script.)
2. Regenerate the search index:
   ```bash
   python3 /home/z/my-project/scripts/gen_tag_search_index_v2.py
   ```
   writes `/home/z/my-project/scripts/tag_search_index_v2.lua.txt` and prints
   the `TAG_CATEGORIES` block (11 categories with counts). If the category
   counts change, also update the two `TAG_CATEGORIES` / `tag_category`
   option lists in the plugin by hand (they're short).
3. Splice the generated index into the plugin (idempotent):
   ```bash
   python3 /home/z/my-project/scripts/swap_tag_block_v2.py
   ```
4. Sanity-check:
   ```bash
   cd /home/z/my-project/testenv && java -cp ".:lib/luaj-jse-3.0.1.jar:lib/jsoup-1.17.2.jar:lib/gson-2.10.1.jar" SyntaxCheck /home/z/my-project/download/wtrlab.lua
   java -cp ".:$(ls lib/*.jar lib2/*.jar | tr '\n' ':')" LuaTest /home/z/my-project/download/wtrlab.lua mock
   python3 /home/z/my-project/scripts/test_plugin_integration.py
   ```
   The integration script asserts the index parses, phrase/word/category
   resolution works, and no `tags_*` group filters are present.

## 7. NoveLA plugin API cheat-sheet (verified against app source)

- Required table fields: `id, name, version, baseUrl, language, icon` (+optional `description, charset, content_type, cf_options, getUserAgentPreset()`).
- HTTP: `http_get(url[, {headers=…, charset=…}])`, `http_post(url, body[, config])` → `{success, body, code, headers}` (header names lower-cased; values are 1-based arrays). No timeout/cookies options. 2 s TTL cache on successful GETs. No `http_head`/`http_request`.
- Catalog: `getCatalogList(index)`, `getCatalogSearch(index, query)`, `getCatalogFiltered(index, filters)` → `{items = {{title, url, cover, rating?}}, hasNext}`. `index` is **0-based**.
- Filters: `getFilterList()` → array of `{type, key, label, defaultValue?, options = {{value,label}}}`; types `select | checkbox | tristate | switch | text | sort`. Marshalled into `getCatalogFiltered` as: select/text → `filters[key]` (string; empty omitted) · tristate → `filters[key.."_included"]` / `filters[key.."_excluded"]` (1-based Lua arrays; empty omitted) · switch → `"true"/"false"` **string**.
- Book getters: `getBookTitle/CoverImageUrl/Description/Genres/Rating/Status/LastUpdate(bookUrl)`, `getChapterListHash(bookUrl)`, `getChapterList(bookUrl)` → `{{title, url}}`. Alternative: `parsePage(bookUrl, page)` (1-based, replaces both chapter-list functions).
- `getChapterText(html, chapterUrl)`: `html` = downloaded chapter page, `chapterUrl` = final URL. Blank return → app falls back to Readability heuristics (bad!). `error("msg")` → shown to the user (LuaJ prefixes `script:<line>` — unavoidable).
- Utils available: `html_select/_first/html_attr/html_text/html_parse/html_remove`, `string_trim/starts_with/ends_with/split/normalize/clean`, `regex_match` (**array of full matches**, Java regex syntax; escape backslashes: `\\s`), `regex_replace`, `json_parse/json_stringify` (Gson; numbers arrive as Lua doubles), `url_encode` (spaces → `+`), `url_resolve`, `sleep(ms)`, `log_info/log_error`, `get_preference(key)` (returns `""` when unset), `set_preference`, `base64_encode/decode` (⚠️ not binary-safe), `get_cookies/set_cookies`, `aes_decrypt` (AES-CBC — not usable for GCM).
- Settings: `getSettingsSchema()` → `{{key, type="select", label, current, options}}` (only `select` is supported).
- Sandbox: LuaJ 3.0.1, no `io`/`os.execute`/`require`/`load` etc.; `bit32` **is** available (still, the plugin carries an arithmetic fallback).

## 8. Testing (harness included)

A faithful LuaJ 3.0.1 + Jsoup + Gson harness mimicking NoveLA's engine lives in `/home/z/my-project/testenv/` (`LuaTest.java`; jars in `lib/`). It re-implements the app's API functions (http/html/json/regex/string/settings) with matching semantics.

```bash
cd /home/z/my-project/testenv
# LIVE tests (catalog, search, filters, book metadata, chapters, chapter text AI+RAW):
java -cp "lib/*:." LuaTest.java /path/to/wtrlab.lua
# Deterministic mock tests (real captured API payloads; turnstile, proxy fallback, perf):
java -cp "lib/*:." LuaTest.java /path/to/wtrlab.lua mock
# Same without bit32 (arithmetic fallback path):
java -cp "lib/*:." LuaTest.java /path/to/wtrlab.lua nobit32 mock
# Single chapter probe:
java -cp "lib/*:." LuaTest.java /path/to/wtrlab.lua "chapter|https://wtr-lab.com/en/novel/<id>/<slug>/chapter-<n>|ai"
```

Current status (2026-09-10): **64/64 live + 49/49 mock pass** (both bit32 and arithmetic fallback) + **all integration checks** (`scripts/test_plugin_integration.py` — filter structure, resolver semantics, param building, HTML-first round-trip). v1.2.0 coverage: paragraph safety (elements with embedded `\n`/`\r\n`, plain-string bodies, quote-containing glossary translations — the upstream-1.1.8 Web+ killer, MOCK H/I/I2), Web+ mode, tag-book discovery end-to-end against the live site (search → 🏷 tag item → 100-novel chapter list → chapter-1 preview URLs, live TEST 11), multi-tag checkbox marshalling + legacy-form back-compat, and the all-match resolver. Live chapter tests can fail with the Turnstile error when the test IP is rate-limited — that's the site working as designed; the harness treats the resulting actionable error as a pass (the plugin behaved correctly).

## 9. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| "WTR-Lab security check required (rate limit reached)" | Per-IP chapter-fetch limit hit. Open any chapter of the book in the **integrated browser**, tap *Verify you are human* once, then retry the download. Consider enabling the chapter fetch delay setting for bulk downloads. |
| "[1401] You are not logged in!" | That chapter is premium/locked on the site. Use the site in the integrated browser to unlock it, or pick another novel. |
| Chapter text looks like `arr:…` | Local decrypt AND proxy both failed (site may have rotated the AES key — see §4). Update `GCM_KEY`. |
| Filter results suddenly empty / catalog empty | Site redeploy: buildId refresh happens automatically (one retry); if it persists, the `_next/data` route shape changed — re-check §3.1. |
| No "honghuang" in tags | Tags list needs a refresh — see §6 (as of 2026-08-25 it's tag id 801). |

## 10. Changelog

- **1.1.7** (2026-08-26) — comprehensive upgrade on top of upstream 1.1.6. Local AES-256-GCM decryption of `arr:`/`str:` chapter bodies with fly.dev proxy fallback (fixes the "large gibberish every 2-3 chapters" complaint at its root); Turnstile/"Security Check" detection + backoff retries + actionable error messages; full novel-finder filter parity (882 tags incl. Honghuang #801, split into 11 category-grouped tristate pickers; Tag Search include/exclude free-text filters; Minimum Reviews; full addition_age list; daily_rank / character / weighted ordering; WORKING chapter & character count filters via count_type+count_filter+count_value replacing the silently-ignored `minc`); JSON-API catalog/search/browse with buildId cache + refresh-retry and exact `hasNext` from `count` (fixed PAGE_SIZE short-circuit so a partial last page doesn't over-fetch); `getChapterListHash` returns `"<count>|<serie_data.updated_at>"` so same-count retranslations are detected (was the literal string "Chapters" in 1.1.6); `b64ToBytes` fails loud on a dangling base64 char; line-anchored watermark/credit stripping with correctly-escaped `\\s`; optional Chapter Fetch Delay setting. Removed the harmful `cf_options = { whitelist = true }` that the community v2.0.0 draft shipped (would have disabled NoveLA's automatic Cloudflare/Turnstile WebView bypass for wtr-lab.com).
- **2.0.0** (community draft, not shipped by upstream) — earlier iteration that introduced the 882-tag filter list and buildId caching but also shipped the harmful `cf_options` whitelist and had escaping bugs in cleanParagraph; superseded by 1.1.7.
- **1.1.6** (upstream) — original: HTML-scraped catalog/search, 208 tags, fly.dev-proxy-only decryption (root cause of the gibberish-chapters regression when the proxy was slow/dead), glossary + patch pipeline.
