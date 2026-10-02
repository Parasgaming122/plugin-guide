# Pull Request: 69shubaTw v1.3.0 — the WAF case-bypass fix (solver storm eliminated, real catalog markup)

**Plugin ID:** `69shubaTw` · **Version:** 1.3.0 · **File:** `69shubaTw.lua` (1,541 lines)
**Target:** https://69shuba.tw/ — 69書吧, Traditional-Chinese novel portal
**Verified:** 127/127 mock-harness checks + 20/20 real-capture end-to-end checks (S69TwTest.java, S69RealSeed.java) against the LIVE-CAPTURED catalog of the user's own book (342441 = 450 chapters on 5 pages)

---

## TL;DR

The user reported v1.2.0 still failed the same way: *"it keeps opening
cloudflare solver but doesn't load chapters — a 40-chapter novel opened the
solver 5+ times and the chapters never loaded; a page supports 100 chapters,
then it adds /2 or /3."* v1.3.0 finds and removes the actual root cause:

1. **THE ROOT CAUSE — a case-sensitive WAF path rule.** Tencent EdgeOne (the
   site's CDN, `Server: Edge/1.1.28`) challenges **lowercase `/indexlist/*`
   from every IP** — verified live: from Google's clean translate-proxy IPs,
   `/indexlist/342441/` → **403 human-verification challenge** while
   `/Indexlist/342441/` (capital I) → **200, the real catalog page**, seconds
   apart. The verification pass cookie (`__ct_ac_cpg`) lives only **5
   minutes**, so on the lowercase path every catalog request re-challenged →
   the app's WebView solver opened again and again (the "5+ times"), burned
   its 2-manual-attempt ladder, fast-failed everything → **chapters never
   loaded**. The site's router is case-insensitive, so **all catalog fetches
   now use `/Indexlist/{id}/{N}/` — WAF-free, zero solver openings**.
2. **THE REAL MARKUP — captured at last.** All prior versions guessed the
   catalog markup from the wcshuba.com sibling. v1.3.0 captures the REAL
   pages (via the capital-I + clean-IP translate proxy) and finds a
   second, unknown chapter-entry form: ~2 of every 100 chapters are
   anti-scrape **`<span class="protected-chapter-link" data-cid-url=…>`**
   elements — not anchors. The old parser **silently dropped them**; both
   forms are now collected (verified end-to-end: chapter 2 and 99 of book
   342441 are span-form and both parse and open).
3. **ZERO SPECULATIVE REQUESTS.** The v1.2.0 parallel batch prefetch
   (pages 2–8), the blind page-2 probe, the window chase and the
   per-chapter `#pb_next` walk are all **removed** — on a WAF'd site each
   speculative fetch is another solver ladder. v1.3.0 fetches exactly what
   the engine asks for: page 1 = ONE request; page N = ONE request each,
   lazy and sequential. **A ≤100-chapter novel costs exactly one catalog
   request** (the user's 40-chapter case: 1 request, no solver).

Net effect for the user's exact scenarios: 40-chapter novel = **1 catalog
fetch, 0 solver** (was: seed + probe + batch = 5–10 challenged fetches);
book 342441 = **5 lazy fetches, 0 solver** (was: up to 13).

---

## The investigation (how the root cause was found)

| Step | Finding |
|---|---|
| Re-probe direct + proxies | Direct: still 403 on every path (datacenter IP). Translate-proxy: `/book/`, `/read/` pass; lowercase `/indexlist/` 403-challenged (re-confirms the v1.1.0 "path asymmetry") |
| **The break** — path-case experiments through the translate proxy | `/Indexlist/342441/` (capital I) → **200, 42 KB of real catalog** while the lowercase form 403s from the same clean IP. The EdgeOne rule is case-sensitive; the origin router is not |
| Full capture | All 5 pages of book 342441 (`/Indexlist/342441/` … `/5/`): 100+100+100+100+**50** chapters = 450; titles 第1章…第450章 老怪甦醒，大明的星門計劃 |
| Markup analysis | List = `div#alllist.lb_mulu` → `ul.last9` → `li` items; **two entry forms** (anchor + protected span); pager = `div.index-container` with `select#indexselect-top` whose option values are **every** page URL (`1 - 100章` … `401 - 450章`) + 上一页/下一页 anchors + `没有了` disabled span on the last page |
| Engine audit (Kotlin) | `DownloaderRepository` walks `parsePage(1..totalPages)` sequentially and **keeps collected pages on failure** (early-stop is safe); `cf_options` supports `whitelist` + `ignore_markers` (+ `trigger_markers` per the official plugin guide — current builds); the stock CF detector requires `Server: cloudflare`, so EdgeOne challenges need the registered `trigger_markers` to engage the WebView ladder at all |
| Chapter-page check | `/read/342441/890316` (a protected-span chapter) serves **full real content** — the span form is link obfuscation, not a paywall; both captured chapters parse with the existing `div#nr1` engine |

## What changed in the plugin

| Area | v1.2.0 | v1.3.0 |
|---|---|---|
| Catalog URL | `SITE/indexlist/{id}/{N}/` (WAF path rule → challenge → solver storm) | **`SITE/Indexlist/{id}/{N}/`** (capital I, WAF-exempt) |
| Chapter entries | `<a>` anchors only | anchors **+ `[data-cid-url]` protected spans** (~2/page previously lost) |
| Pager | wcshuba-derived multi-signal engine (dual selects, h3 heading, window chase, blind probe) | the real single `select#indexselect-top` (option values → page numbers, book-id trap rejected) + 下一页 cross-check |
| Pages 2..N | parallel `http_get_batch` prefetch (2..8) + chase probes | **lazy, one fetch each**, engine-driven; cache-first for interior pages, last page re-fetches for growth |
| Fallback layers | /book/ seed (last9) + per-chapter `#pb_next` walk | **removed** (on a WAF'd site the walk = one solver ladder per chapter); guided `show_error` instead; stale TOC cache still serves offline |
| Challenge handling | relied on the app ladder | plugin-side **body-marker detection** (403 or 200-served challenge) → immediate guided error, zero fallback fetches |
| TOC cache | format v2 (walk fields) | format **v3** (old entries discarded → clean migration off the walk data) |
| `bookIdFromUrl` | lowercase shapes only | case-insensitive (`/Indexlist/` pastes work), still accepts `/book/`, `/indexlist/`, `/read/` shapes |
| Headers | Referer + Accept | + `Accept-Language: zh-TW,zh;q=0.9,en-US;q=0.8` |
| cf_options | 3 trigger markers | 4 (+ `challenges.cloudflare.com/turnstile`) |
| Size | 2,019 lines | 1,541 lines (−478: the storm machinery is gone) |

## Test evidence (all green)

**S69TwTest — 127/127** (mock harness, real captured fixtures):
- T9: parsePage(1) on the real page → **100 chapters incl. both protected spans**, totalPages 5, canonical `/read/{bid}/{cid}` URLs, capital-I fetch URL asserted, double-call = 1 fetch
- T10: full walk → **450 chapters**, 第1章…第450章, cids ascending across pages, each page fetched once, immediate re-walk = zero network
- T11: challenge on page 2 → abort keeps page-1's 100 chapters; page 3 never fetched (early-stop, no storm)
- T12: the user's case — 40-chapter novel: **1 request total**, totalPages 1, no page-2 fetch from the engine, works added via `/book/`, `/indexlist/` and `/Indexlist/` URLs
- T12b: soft-serve guard (page-N URL re-serving page 1) → nil, TOC never polluted
- T13: challenge blocks page 1 → **empty table, never nil** (the v1.0.0 lesson), one show_error, **zero fallback fetches**; 200-served challenge body also detected
- T14: persistent cache v3 (`3|5|…`), interior page from cache with zero network, last page stale-serves on failure
- T15: full 450-chapter stale-serve when the site is unreachable
- T16–T21: chapter text (sub-pages, watermarks), translator, search-query translation, unreachable paths — unchanged, still green

**S69RealSeed — 20/20** (real-data end-to-end): real book details → real catalog pages → 450-chapter TOC → real chapter text for **both** a normal and a protected-span chapter → zero lowercase requests → exactly 5 capital-I fetches → unknown book = one attempt + guided error.

## Known limits

- If EdgeOne ever makes the rule case-insensitive (or the router case-sensitive), catalog fetches will challenge again — the challenge is detected in-plugin (guided error, no storm) and the app's WebView ladder (`trigger_markers`) remains the manual recovery path.
- Dirty IPs (datacenters/VPNs) are challenged on **every** path regardless of the catalog fix — one solver pass then works within the 5-minute cookie window; nothing a plugin can do beyond minimizing requests (which v1.3.0 does).
- The pager select lists ALL pages on this site; if a future very long book windows the select, each fetched page still re-reveals the true count (totalPages updates mid-walk) — handled.
