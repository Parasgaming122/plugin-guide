#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Rewrite wuxiabox_pull_request.md as the v2.3.0 (smart mirror switcher) PR."""
import sys

PATH = "/home/z/my-project/download/wuxiabox_pull_request.md"

with open(PATH, "r", encoding="utf-8") as f:
    src = f.read()

def replace_once(text, old, new, what):
    n = text.count(old)
    if n != 1:
        print(f"ANCHOR FAIL ({what}): {n} occurrences", file=sys.stderr)
        sys.exit(1)
    return text.replace(old, new, 1)

# ── title + header meta ─────────────────────────────────────────────────────
src = replace_once(
    src,
    """# Pull Request — `en/wuxiabox.lua` v2.2.0 (WuxiaBox)

**Source:** [`en/wuxiabox.lua`](https://github.com/HnDK0/external-sources/blob/main/en/wuxiabox.lua)
**Base version:** `1.0.1` (WuxiaBox — wuxiabox.com, EmpireCMS "Web Novels MTL" platform)
**Proposed version:** `2.2.0` (same site, same source id — in-place upgrade of the 2.x line)
**Date:** 2026-09-18
**Plugin size:** 3,053 lines (~121 KB — down from 8,145 lines / 184 KB in 2.1.0; the tag index shrank from 6,723 to 755 entries)
""",
    """# Pull Request — `en/wuxiabox.lua` v2.3.0 (WuxiaBox)

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
""",
    "title + TL;DR")

# ── demote the old TL;DR heading ────────────────────────────────────────────
src = replace_once(
    src,
    """## TL;DR — what v2.2.0 changes

Same file, same `id`, same book URLs — existing installs and libraries carry over untouched. Four user-facing changes:""",
    """Same file, same `id`, same book URLs — existing installs and libraries carry over untouched. Four user-facing changes:""",
    "old TL;DR demotion")

# ── testing section: counts + new rows ──────────────────────────────────────
src = replace_once(
    src,
    "**125/125 PASS**, the additions over v2.1.0's 111:",
    """**147/147 PASS** — 125 from ≤2.2.0 plus 22 new smart-switcher checks:

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

The v2.2.0 additions (still in the suite):""",
    "testing counts")

# ── settings line ───────────────────────────────────────────────────────────
src = replace_once(
    src,
    'Settings (in-app source settings, 4 entries): **Source site** (auto / wuxiabox only / wuxiaspot first), **Cover images** (proxy / direct — new in 2.2.0), **Chapter retries on 502** (2–6), **Chapter request pacing** (ms floor).',
    'Settings (in-app source settings, 4 entries): **Source site** (2.3.0 labels: *Smart switch — WuxiaBox first, auto-failover to WuxiaSpot* / *WuxiaBox only* / *WuxiaSpot first — manual mirror switch, WuxiaBox backup*), **Cover images** (proxy / direct — 2.2.0), **Chapter retries on 502** (2–6), **Chapter request pacing** (ms floor). The switcher itself needs no setting — it is always on, and the preference only decides the *default* order.',
    "settings line")

# ── install: index.yaml version fix (was stale at 2.1.0) ────────────────────
src = replace_once(
    src,
    '    version: "2.1.0"',
    '    version: "2.3.0"',
    "index.yaml version")

# ── known limits: searchid line now per-search-base ─────────────────────────
src = replace_once(
    src,
    '- Searchid pages and tag listings are **primary-only** (ids are site-specific); everything else falls back to the mirror.',
    """- Searchid pages are served by **the base that created the search** (site-specific ids; a fresh engine run re-searches). Tag listings remain **primary-only** — the mirror's tag ids point at different tags entirely.
- The engine's own chapter-page fetch (canonical URL) happens before the plugin runs; when it *throws* (hard outage / unsolvable CF challenge) the plugin never sees it — the optional engine patch above removes even that gap.""",
    "known limits searchid")

with open(PATH, "w", encoding="utf-8") as f:
    f.write(src)
print(f"OK — PR doc rewritten for v2.3.0: {src.count(chr(10)) + 1} lines")
