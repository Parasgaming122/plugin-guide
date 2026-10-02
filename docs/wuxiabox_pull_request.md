# Pull Request — `en/wuxiabox.lua` v2.3.0 (WuxiaBox)

**Source:** [`en/wuxiabox.lua`](https://github.com/HnDK0/external-sources/blob/main/en/wuxiabox.lua)
**Base version:** `1.0.1` (WuxiaBox — wuxiabox.com, EmpireCMS "Web Novels MTL" platform)
**Proposed version:** `2.3.0` (same site, same source id — in-place upgrade of the 2.x line)
**Date:** 2026-09-19
**Plugin size:** 3,339 lines (~136 KB — same curated tag index as 2.2.0; +286 lines of smart-switcher logic + docs)

---

## TL;DR — what v2.3.0 changes

Same file, same `id`, same book URLs — existing installs and libraries carry over untouched. One headline feature:

1. **SMART MIRROR SWITCHER.** Mirror switching is no longer "try the other site when a request dies". The plugin now ships a **persistent per-site health tracker (circuit breaker)**: two consecutive failures on one site (network error, 5xx, Cloudflare page, or an error page served with status 200) put that site in a **10-minute cooldown** — every subsequent fetch goes straight to the other site with **no wasted doomed request**, and the site is re-admitted automatically when the cooldown expires (half-open, self-healing). Any success resets it. A 404 never counts (the site answered — the page just isn't there). The state persists via `set_preference` across app restarts, so a flapping primary stays skipped even after a relaunch.
2. **Manual switching now actually switches.** Setting *Source site* to "WuxiaSpot first" moves **every plugin-controlled fetch** — catalog, filters, search, book details, chapter lists — to the mirror, and chapter text follows the moment the canonical host serves an error page (the engine's own chapter fetch is the one hop NoveLA does not expose to Lua; the plugin rescues from the healthy site, instantly — the pre-retry sleep is gone). Saved novels keep their canonical `wuxiabox.com` URLs either way: **no library fragmentation, ever**.
3. **Search pagination is mirror-native.** Each running search remembers **which site created its searchid**, so a search that started on the mirror keeps paginating on the mirror (v2.2.0 hard-pinned result pages to the primary, which silently killed pagination for mirror-served searches). Tag listings remain strictly primary-only — the two sites' tag id spaces are completely different.
4. **Clearer failures.** When both sites are dead, chapter loading now raises a clear error naming both hosts instead of returning empty text (which made the engine fall through to generic text-extraction heuristics on the very error page it had just failed on). `200`-but-junk bodies (origin 502 HTML, maintenance interstitials) are detected and treated as failures on **every** fetch path, not just chapters.

All changes verified by a **147-test** luaj/jsoup harness running the real plugin against live-HTML fixtures (`test-harness/WuxiaboxTest.java`) — including cooldown steering, cooldown persistence across a simulated engine restart, cooldown expiry, junk-body failover, 404 neutrality, mirror-native search pagination, and both-sites-dead error propagation. **147/147 pass.** Both sites live-verified as structural twins on 2026-09-19 (same novel slug serves the same content on both).

---

## The smart switcher — how it works

### Site health tracker (circuit breaker)

State (persisted in SharedPreferences via `set_preference`, key `wuxiabox_site_health`, format `box=<fails>,<cooldownUntilMs>;spot=<fails>,<cooldownUntilMs>`):

| Event | Effect |
|---|---|
| fetch fails (network error / non-2xx / CF page / junk body) | `fails + 1` |
| `fails` reaches **2** | site enters **10-minute cooldown** (skipped by every fetch) |
| any fetch on the site succeeds | `fails = 0`, cooldown lifted |
| **404** | *no change* — the site answered; the page just doesn't exist (e.g. the 15 category slugs the mirror doesn't share) |
| cooldown expires | cleared lazily on next read — site gets a fresh chance (half-open) |

`orderedBases()` computes the fetch order: preference order (auto = primary first / spot = mirror first / box = primary only) minus sites in cooldown — and falls back to the plain preference order when *every* site is cooling down (a cooldown is a heuristic, not an outage verdict). Every fetch path feeds the tracker: `httpGetAny` (catalog, filters, updates, novel pages, fy chapter-list fragments), `httpGetPrimary` (tag listings), `runSearch` (both search endpoints), `refetchChapterWithRetry` (chapter rescue), and — critically — **the engine's own failed chapter fetch**: when `getChapterText` receives an error/interstitial body for the canonical `wuxiabox.com` URL, that failure is charged to the primary before the rescue starts, so the rescue's first attempt already lands on the healthy site.

### The one hop the plugin cannot own (and the optional engine patch)

NoveLA's `DownloaderRepository.bookChapter` fetches chapter documents **itself**, from the canonical URL stored in the library, before the plugin is invoked (`SourceInterface.transformChapterUrl` exists in the engine but is not exposed to Lua plugins). Consequences and mitigations:

- The engine's request always targets `wuxiabox.com` first. If it **returns a body** (a 502/504 page after the engine's own 4× interceptor retries, a maintenance interstitial), the plugin receives it in `getChapterText`, charges the failure, and rescues from the healthy site — typically one extra request, no sleep.
- If the engine's request **throws** (connect timeout, unsolvable CF challenge), the chapter fails before the plugin runs — nothing a plugin can do. The *Source site → WuxiaSpot first* setting still moves every other surface (details, lists, search) to the mirror, and the next chapter's rescue will go mirror-first once any body arrives.
- **Optional engine follow-up** (for your own NoveLA build — not required by this plugin): expose `transformChapterUrl` to Lua. The plugin already ships the hook (`transformChapterUrl(url)` — only `/novel/…` chapter URLs switch hosts, everything else keeps its host):

```kotlin
// LuaSourceAdapter.kt — ~10 lines, makes the engine's chapter fetch
// smart-switcher-aware BEFORE the request is made:
override suspend fun transformChapterUrl(url: String): String =
    withSourceContext {
        try {
            val fn = luaScript.get("transformChapterUrl")
            if (fn.isnil()) url else fn.call(LuaValue.valueOf(url)).optjstring(url)
        } catch (_: Exception) { url }
    }
```

With this patch, a cooling or deprioritised primary is skipped even on the engine's own hop — zero doomed requests.

### Search: per-search base memory

A `searchid` is an entry in **one** site's EmpireCMS search table. v2.2.0 pinned result pages to the primary, which broke pagination for searches the mirror served. v2.3.0's `runSearch` records which base produced the result body (`_searchBaseByQuery`); later pages of that query are fetched from **the same base**; a hard failure triggers one fresh search (which `orderedBases()` may route to the other site) and then a retryable error. A fresh engine run re-runs the search (self-healing, unchanged). Tag listings stay **primary-only** — different id spaces, verified live.

### Chapter rescue, upgraded

| | v2.2.0 | v2.3.0 |
|---|---|---|
| attempt order | blind alternation box→spot→box… | `orderedBases()` — health + preference aware, re-evaluated per attempt |
| before first attempt | slept 700–1000 ms | **no sleep** (the engine's retry ladder already waited seconds) |
| engine's failed fetch | ignored | charged to the primary's health → rescue starts on the healthy site |
| 404 on a site | counted as a failure | **neutral** (site healthy, chapter missing) |
| all attempts dead | returned `""` (→ engine heuristics on the error page) | **raises a clear error naming both sites** |

---

## v2.2.0 changes (previous release — kept for context)

---

Same file, same `id`, same book URLs — existing installs and libraries carry over untouched. Four user-facing changes:

1. **POSTERS FIXED.** WuxiaBox cover images live behind the same Cloudflare shield as the pages, but **image URLs are exempt from NoveLA's Cloudflare WebView bypass** (its `STATIC_EXTENSIONS` list short-circuits `.jpg`), so a challenged cover request handed the challenge HTML to the image loader and the poster silently failed. All covers are now served through the **wsrv.nl image proxy** (`images.weserv.nl` — the service the engine itself whitelists for exactly this pattern), resized to `w=450`. A new **"Cover images" setting** offers `proxy` (default) or `direct`.
2. **SEARCH now paginates continuously.** Two bugs killed multi-page results in 2.1.0: (a) the pager's grand-total (`总数`) fallback was **dead code** — the Lua pattern anchored on `<ul class="pagination">` but could not cross the newline that follows it; (b) later search pages used the **mirror fallback**, and a `searchid` is an entry in *this site's* EmpireCMS search table — the mirror served an unrelated or empty page, which the app treats as "no more results", ending the feed after one page. Searchid pages are now **primary-only** with a fresh-search retry, and hard failures raise a **retryable error** (the app keeps loaded pages and offers retry) instead of silently ending pagination. Verified against live captures: pager is 0-based, pages 0/1/2 carry distinct items, `page=1` URL form and `?searchid=` form behave identically.
3. **TAGS CURATED + NATIVELY SEARCHABLE.** The 6,723-entry tag index (148 KB of the file) is replaced by **755 genuinely-used tags** — the wtr-lab taxonomy cross-reference (746 normalized-name matches, i.e. the tropes novels on this platform are actually tagged with) plus every Popular Tag and the whole Honghuang\* family. Browsing them is now a **`tag_input` filter** (a newer NoveLA filter type): a text field with live suggestions — type "protag" and matching tags appear; picked tags become removable chips. This replaces both the old free-text "Tag Search" box and the "Popular Tags" checkbox group. Plugin size drops by ~63 KB and cold-load gets faster.
4. **Cloudflare improvements.** `getUserAgentPreset()` registers a modern **Chrome Mobile** UA for every request of this source *and* its host — including the image loader's cover fetches — so the `cf_clearance` cookie the WebView bypass bakes stays valid for images too (it is bound to User-Agent + IP). `show_error()` (new engine API) surfaces actionable dialogs when both sites are unreachable or a tag pick cannot be resolved.

All changes verified by a **125-test** luaj/jsoup harness running the real plugin against live-HTML fixtures (`test-harness/WuxiaboxTest.java`) — including simulated 502→mirror recovery, searchid primary-only routing, the dead-total-pattern regression case, last-page math, and a consistency sweep of all 756 picker options. **125/125 pass.**

---

## v2.1.0 changes (previous release — kept for context)

### 1. The search gate bug (v2.1.0) — exact-title searches returned nothing

**What the user saw:** copy a novel title from the catalog, paste it into search → empty results. Every time.

**Root cause (verified live, 2026-09-16):** EmpireCMS puts `searchid=` **only into pager links**. A query that matches a single novel (an exact pasted title) returns a perfectly good result page — one `li.novel-item`, correct title, correct URL — with **no pager and therefore no `searchid=` anywhere in the body**. v2.0.0's acceptance gate:

```lua
if r.success and extractSearchId(r.body) then return r.body end   -- rejects single-result pages!
```

discarded the valid page on BOTH the POST path and the GET `searchget=1` fallback → `runSearch` returned nil → the app showed nothing.

**The fix** (`hasSearchResults`):

```lua
local function hasSearchResults(body)
    if not body or body == "" then return false end
    if extractSearchId(body) then return true end              -- multi-page results
    return html_select_first(body, "li.novel-item") ~= nil      -- single/few-result pages
end
```

Pagination is unaffected: later pages are only reachable through the searchid, which every multi-page result carries in its pager. A genuine zero-result search returns the site's "Message hint" interstitial (HTTP 200, no cards) and correctly yields an empty list without wasting a mirror request.

**Also hardened:** relative `Location` headers now resolve against the base the request actually went to (`followRedirects(r, base)`) — matters once the mirror enters the picture; the query is trimmed; the whole pipeline (POST → GET variant → mirror) retries site-by-site only when a site actually fails to serve a page.

Verified in test T4b against a **live-captured fixture**: a real single-result page (7.7 KB, one novel-item, zero searchid occurrences) — v2.0.0 returns 0 items, v2.1.0 returns the novel.

### 2. The mirror site (v2.1.0) — what falls back, what must not

`https://www.wuxiaspot.com/` is a full twin: same EmpireCMS install family, same `/novel/{slug}.html` addresses (verified live: the same novel slug serves on both), same search (the same keyword returns the same single result on both), same page templates. Verified **not portable**:

| Surface | Portable? | Why |
|---|---|---|
| Novel pages `/novel/{slug}.html`, chapters `/novel/{slug}_{n}.html` | ✅ | slug-keyed, identical markup |
| Chapter fragments `/e/extend/fy.php?page=N&wjm={slug}` | ✅ | slug-keyed |
| Search `/e/search/…` | ✅ | keyword-keyed (verified live on both sites) |
| Catalog `/list/…`, `/updates/` | ✅ | 42 of 57 category slugs shared; unshared slugs fail gracefully (empty) |
| **Tag listings `/tags/{id}-0.html`, `/e/tags/index.php?tagid=`** | ❌ **primary-only** | **the two sites' tag ID spaces are completely different** — wuxiabox "Rebirth" = 139, wuxiaspot "Rebirth" = 682, and wuxiabox's id 682 is "Saving the World". A mirror fallback here would silently browse the WRONG TAG. |

**Design:**
- `httpGetAny(path)` — tries the preferred site, then the other (per the setting); used for every portable fetch.
- `httpGetPrimary(path)` — primary only; used for tag listings.
- `absUrl()` canonicalizes **both** hosts to `https://www.wuxiabox.com/...`, so a mirror-served page can never leak `wuxiaspot.com` links into the engine's library (no fragmentation, no duplicate entries).
- The one-run page cache is keyed by site **path**, so a page fetched from the mirror is cached under the same canonical key the primary would use.
- Chapter 502 recovery (`refetchChapterWithRetry`) **alternates** WuxiaBox → WuxiaSpot across attempts, so a single-site outage costs one attempt, not the whole retry budget.
- Setting **"Source site"** (`wuxiabox_site_preference`): `auto` (default) / `box` (wuxiabox.com only) / `spot` (wuxiaspot.com first, wuxiabox.com as backup).

### 3. Popular Tags picker (v2.1.0 — SUPERSEDED in 2.2.0 by the searchable tag_input)

- **Removed:** the "Tag Search Category" select (All + A–Z) — 6,723 tags behind 26 letters was not browsable, and the site's own letter grouping doesn't help find a trope.
- **Added:** "Popular Tags" — a `checkbox` chip group (multi-select, the platform marshals it as `filters["popular_tags_included"] = { value, … }`) with 27 famous tropes: Male Protagonist, Female Protagonist, Overpowered/Genius Protagonist, Handsome/Beautiful Lead, System, Level System, Sign-in, Cultivation, Immortal, Alchemy, Magic, Beasts, Rebirth, Second Chance, Transmigration, Regression, Weak to Strong, Revenge, Farming, Romance, Modern Day, Ancient China, Apocalypse, Academy, Hongmeng, **Honghuang (all Honghuang\* tags)**.
- **Canonical tag ids:** 392 tag names on this site exist under several ids ("Male Protagonist" has 6: 12, 2900, 965, 1287, 1261, 1079). The chips pin the id the site's own novel pages link to (verified: MaleProtagonist→12, AncientChina→34, Farming→229, Transmigration→32) — the lowest/original id. The free-text Tag Search still includes every duplicate, exactly as before.
- **"Honghuang (all)"** uses the keyword `honghuang` on purpose: the site has no plain "Honghuang" tag, only the truncated HongHuangB / HonghuangN / HonghuangS / Honghuangs / HongHuangz family — the keyword expands to all of them in the union browse.
- Chips + free-text keywords merge into ONE resolution, then a union browse with dedup (test T7c). The union cap of 12 tags still applies and its error lists the matches.

### 4. Categories vs tags (v2.1.0) — clean separation

- **Categories** come from the `/list/all/all-newstime-0.html` sidebar: 56 + All, live-verified (and cross-checked against the mirror's own sidebar — the two sites share 42 slugs). The Category select is unchanged from v2.0.0.
- **Tags** come from `/browsetags/` (6,723, shipped as the searchable index). The Popular Tags picker and Tag Search text are the tag entry points.
- **Genres on book pages** now carry ONLY the category chips (`.categories a.property-item`); the tag chips (`a.tag`) in the same block are a different taxonomy and are no longer mixed in.

### 5. The 502 fix (carried from v2.0.0, now mirror-aware)

Root cause recap: a 502 page parses fine as HTML, the app's retry loop only classifies *timeout/connect* errors as transient, so 502 pages surfaced as dead chapters. The plugin detects content-less chapter pages and refetches them itself with exponential backoff + jitter (default 4 attempts), plus a configurable pacing floor (default 1.5 s) between chapter requests. **2.1.0:** the refetch loop alternates WuxiaBox → WuxiaSpot per attempt. Settings: "Chapter retries on 502 / error pages" (2–6, default 4), "Min gap between chapter requests" (Off/0.8/1.5/2.5/4 s, default 1.5 s), plus the new "Source site".

### 6. Filters (v2.2.0 current)

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

Settings (in-app source settings, 4 entries): **Source site** (2.3.0 labels: *Smart switch — WuxiaBox first, auto-failover to WuxiaSpot* / *WuxiaBox only* / *WuxiaSpot first — manual mirror switch, WuxiaBox backup*), **Cover images** (proxy / direct — 2.2.0), **Chapter retries on 502** (2–6), **Chapter request pacing** (ms floor). The switcher itself needs no setting — it is always on, and the preference only decides the *default* order.

## 7. Testing

`test-harness/WuxiaboxTest.java` — luaj 3.0.1 + jsoup, faithful NoveLA API emulation (multimap headers, TextExtractor port, preferences, UA-tagged requests), mock server with per-URL rules, response sequences, request-header capture and body-match narrowing. Live-captured fixtures in `research/wuxiabox/`.

**147/147 PASS** — 125 from ≤2.2.0 plus 22 new smart-switcher checks:

| Suite | New checks (2.3.0) |
|---|---|
| T13/T13b/T15/T15b/T16 | hermetic health resets (each mirror-behaviour test now starts from a clean slate via `reloadPlugin()`) + timing updated for the removed pre-attempt sleep |
| T17 | 502 → failover; health persisted (`box=1,0`); fails=1 still tries primary first; **2 fails → cooldown: primary skipped entirely (0 hits)**, mirror serves straight; cooldown recorded in persisted prefs |
| T17b | **cooldown survives a simulated engine restart** (fresh Lua state reads persisted health; cooling primary still skipped) |
| T17c | **expired cooldown re-admits the primary** (half-open self-healing) |
| T17d | success resets the fail counter |
| T17e | **200-but-junk body** (origin 502 HTML with status 200) → failover + charged to health |
| T17f | **404 is health-neutral** (site answered; counter unchanged) |
| T18 | **spot-preference search paginates on the mirror** (searchid's own base); primary search pages never touched; URLs stay canonical |
| T19 | both sites dead → **clear error naming both hosts**; mirror attempted |
| T14 | site-setting option 1 label mentions the smart switcher |

The v2.2.0 additions (still in the suite):

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

## 8. Install / repo integration

1. Replace `en/wuxiabox.lua` in the repo with this file (same file name, same `id` — installs update in place, libraries carry over).
2. Update `en/index.yaml` (only the version changes):

```yaml
  - id: "wuxiabox"
    name: "WuxiaBox"
    version: "2.3.0"
    url: "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/en/wuxiabox.lua"
    icon: "https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/icons/wuxiabox.png"
    language: "en"
```

3. The icon URL is unchanged — it already points at the repo's `icons/wuxiabox.png`, which keeps working.
4. Cloudflare: nothing to configure — NoveLA's `CloudfareVerificationInterceptor` auto-solves challenges via the integrated WebView for every plugin request, for both hosts. **Do not** add `cf_options = { whitelist = true }` (it disables the recovery path — see the wtrlab plugin docs for the full analysis).

## 9. Tag-index maintenance pipeline (v2.2.0: curated)

The 6,723-tag harvest pipeline still exists, but the shipped index is now the **curated** set. To refresh:

1. `scripts/harvest_wuxiabox_tags.py` — resumable live harvest of `/browsetags/` (unchanged).
2. `scripts/curate_wuxiabox_tags.py` — computes the curated set: normalized-name intersection with the wtr-lab tag taxonomy (wtr-lab novels and WuxiaBox novels are the same corpus, so its 888 tags are the "actually used" set) + the plugin's popular tags + tags observed on novel-page fixtures + the Honghuang\* family. Emits `research/wuxiabox/curated_tags.json`. **Gotcha: exclude `mirror_*` fixtures** — wuxiaspot tag ids map to different names (wuxiaspot 682 = "Rebirth", wuxiabox 682 = "Saving the World").
3. `scripts/splice_wuxiabox_v220.py` — regenerates `TAG_SEARCH_INDEX` **and** `TAG_FILTER_OPTIONS` (the tag_input options) from the curated JSON.
4. Re-run `test-harness/WuxiaboxTest.java` — T7d validates every option id/label pair.

## 10. Known limits

- No tag **exclusion** — the platform's filter sheet cannot express it and the site has no exclude param for tag listings.
- A tag listing cannot be combined with category/status/sort (site limitation; the plugin applies tags with priority).
- Union browse caps at 12 tags per resolution (runaway wildcards would otherwise fetch dozens of listings).
- Searchid pages are served by **the base that created the search** (site-specific ids; a fresh engine run re-searches). Tag listings remain **primary-only** — the mirror's tag ids point at different tags entirely.
- The engine's own chapter-page fetch (canonical URL) happens before the plugin runs; when it *throws* (hard outage / unsolvable CF challenge) the plugin never sees it — the optional engine patch above removes even that gap.
- The 755 curated tags intentionally drop the long tail of the 6,723 harvest (one-off / character-name / Chinese-only tags). The union of wtr-lab taxonomy + popular tags + Honghuang family covers the tropes novels are actually tagged with; if a specific tag is ever requested, re-run the curation with it added.
- wsrv.nl is a third-party image proxy (operated by the images.weserv.nl project); the "direct" setting is the escape hatch if it is ever unavailable.

---

## v2.0.0 change set (context)

