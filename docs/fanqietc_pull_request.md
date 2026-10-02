# fanqietc.lua v1.0.0 — new source plugin for NoveLA (FanqieTC / 番閱, fanqietc.com)

**TL;DR:** New plugin for **FanqieTC (番閱)** — the open-source, zero-ad web
reader for **番茄小說 (Fanqie Novel)**, the largest Chinese web-novel catalog
(millions of titles, 完本 and 连载, per-chapter word counts, 0–10 scores).
Unlike the other six plugins this is **not an HTML-scraping source**:
fanqietc.com is a static React SPA whose entire catalog lives behind a JSON
backend (`api.fanqietc.com`) fronting a pool of **ten Fanqie API mirrors**
(hk-1…6, cn-1…2, sg-1…2). The plugin speaks that JSON API directly — with the
exact header set the official web client sends (X-API-Token / Origin /
Referer), **health-checked mirror failover** for the reading path, retry-with-
backoff + a visible degraded-state page for the backend's own list endpoints,
the complete **novel543 translator** built in, and a **⚡ Self-Test**
diagnostics page. Verified **86/86 live checks** (rankings ×7, recommendations
×2, search, a 4051-chapter book read end-to-end incl. the 番外 extras,
translator engines, mirror failover, robustness).

## The version-literal rule (applies to ALL plugins — fixed in this release)

NoveLA's extension manager parses plugin metadata **statically, with a regex
that only matches quoted string literals**:

```kotlin
Regex("""(?m)^\s*version\s*=\s*["']([^"']+)["']""")
```

Writing `version = VERSION` (a variable) makes that regex fall back to
`"1.0.0"` while the runtime reports the real value — the mismatch confuses
update detection and re-import ("Extension already exists", phantom updates).
fanqietc.lua ships `version = "1.0.0"` as a **literal**, and this release
also converts the four affected plugins (**69shubaTw 1.3.0, bixiange 1.0.1,
novel543 1.0.5, oop 1.1.0**) to literal version lines. wtrlab and wuxiabox
were already literal.

---

## 1. What the site is

| | |
|---|---|
| Site | https://fanqietc.com — "番閱", a PWA reader for Fanqie Novel (zh) |
| Open source | https://github.com/denniemok/fanqie-novel-reader (MIT, frontend only) |
| Content | 番茄小說 catalog — millions of Simplified-Chinese web novels |
| Backend | `https://api.fanqietc.com` — JSON API proxying 10 Fanqie mirrors; **backend source is private**, the frontend is public |
| Auth | `X-API-Token: fqtc_…` + `Origin: https://fanqietc.com` + `Referer: https://fanqietc.com/` — all three REQUIRED (dropping any one → Cloudflare challenge, verified live) |
| Mirrors | `hk-1…6` (down at release), `cn-1…2`, `sg-1…2` (healthy), `default` (backend-side pick) |
| Health | `GET /status` — per-mirror up/down for detail/directory/content/comment, refreshed by the backend every 15 min |
| Also reads | book ids from the original sites: `fanqienovel.com/page/{id}`, `tomatomtl.com/book/{id}` |

## 2. The API surface (all verified live 2026-09-30)

| Endpoint | Returns |
|---|---|
| `GET /rank?board=recommend\|finished\|new\|chasing\|darkhorse\|peak\|reading` | 30 books (100 for darkhorse/reading), single page |
| `GET /recommend?section=realtime\|guess` | 11–16 books |
| `GET /search?query=…` | ~50 books, **no pagination**; fuzzy (garbage queries return populars, never zero) |
| `GET /proxy?api={mirror}&action=detail&book_id={id}` | title/author/abstract/cover/score/tags/category/sub_info/word_number/last_publish_time/creation_status/content_chapter_number |
| `GET /proxy?api={mirror}&action=directory&book_id={id}` | `item_data_list[]` = {item_id, title, version} — ALL chapters, oldest→newest, 番外 extras last (4051 items for the probe book) |
| `GET /proxy?api={mirror}&action=content&item_id={id}` | `content` — one paragraph per `\n` (exactly what NoveLA's reader splits on) |

Semantics worth remembering: **`creation_status '0'` = 已完结 Finished,
other truthy = 连载中 Ongoing** (inverted from what you'd guess — verified
against the reader's own `bookInfo.js`); `score "0"` = unscored → hide;
`last_publish_time` = unix seconds as a string; item ids are **global across
mirrors** (same content from cn-2/sg-1/sg-2, byte-identical modulo a leading
space some mirrors prepend — the plugin trims it).

## 3. Architecture decisions

**URL scheme (synthetic, plugin-resolved).** The SPA has no server-rendered
routes, so the plugin defines its own: books `https://fanqietc.com/book/{id}`,
chapters `https://fanqietc.com/book/{id}/{itemId}`. The app's chapter
downloader fetches that URL first — fanqietc.com (Cloudflare Pages static)
serves the SPA shell to **any** UA without a challenge — then
`getChapterText(html, url)` extracts the item id and pulls the real text from
the API. This costs one ~6 KB static fetch per chapter and **completely
avoids the Cloudflare-solver storm class of bugs** (the 69shuba/oop lesson):
the downloader never touches a challenged host, and the plugin's own API
calls carry the header set that passes Cloudflare on real devices.

**Two failure domains, two strategies.**
- *Proxy path* (detail/directory/content — the reading path): full mirror
  failover. Candidates = last-good mirror, then /status-healthy mirrors in
  the site's canonical order, then `default`; a failed request advances to
  the next candidate; attempt-capped at 6; /status re-checked when the chain
  is exhausted. A dead pool surfaces through `show_error()` with a
  actionable message instead of a silent empty chapter.
- *Direct path* (`/rank` `/recommend` `/search` — discovery): **no `api=`
  parameter exists for these** (verified — the proxy rejects other actions
  with 400), so when the backend's own upstream pick flaps they 503
  `{"error":"Upstream temporarily unavailable"}` for minutes at a time —
  the official web client shows its 搜尋失敗/獲取榜單失敗 errors in exactly
  these windows (observed live for ~25 min on release day while sg-1/sg-2
  served every proxy request fine). The plugin retries 3× at 1.5 s, then
  returns a **visible ⚠ degraded-state page** telling the user what still
  works and how to check live health — never a silently blank catalog.

**Caching.** Opening a book fires 6–8 Lua calls (title/cover/description/
genres/status/rating/last-update/hash) — all answered by ONE detail request
through a 5-min LRU cache (12 entries); the directory gets the same
treatment (getChapterList + first reads). No clock available → caches
bypass cleanly.

**Translator.** Copied verbatim from novel543 (user request) with
fanqietc-scoped preference keys (`fanqietc_mode` / `_tlang` / `_tr_chapters`),
a Fanqie-specific STATIC_EN vocabulary (东方仙侠→Eastern Xianxia, 已完结→
Completed, 30+ entries), `sl=zh-CN` (the catalog is Simplified), and the same
6-step engine chain (Google dict POST/GET × 2 hosts → MyMemory → gtx single),
session cache, 3-failure circuit breaker, and pcall armor on every entry
point. Search queries typed in a non-Chinese language are translated to
zh-CN first, with the raw query retried when the translation finds nothing.

**Self-Test.** Browse → Page → ⚡ Self-Test renders a live diagnostics
catalog: settings echo, environment probes (os_time/http_post/json_parse),
**per-mirror health** (fresh /status read, all 10 mirrors listed), the three
API probes end-to-end (detail → directory → content, with latency and
content length), the three translator engines, and a verdict line that names
the next step for each failure mode. This is the first plugin whose
self-test covers the site API as well as the translator.

## 4. Settings

| Setting | Values | Default |
|---|---|---|
| API Mirror | auto · default · hk-1…6 · cn-1…2 · sg-1…2 | auto (health-checked) |
| Mode | raw · translate | raw |
| Translate To | 15 languages | en |
| Translate Chapter Titles | on · off | on |

## 5. Test suite — 86/86 PASS (live, 2026-09-30)

`test/FanqietcTest.lua` runs under the NoveLaHarness (luaj sandbox with real
networking, mirroring NoveLA's plugin API). Coverage: metadata surface
(9) · default catalog (6) · all 7 rank boards (7) · both recommend sections
(2) · invalid-filter fallbacks (2) · search incl. Chinese top-hit / English /
empty / garbage / page-2 (6) · book details ×2 books incl. cache-busting (9)
· alternate-URL id extraction + invalid id (3) · chapter list/hash (5) ·
chapter text via the real downloader flow (first/second/last-番外) (8) ·
bad-item show_error path (1) · page-scoped filter lists ×3 surfaces (5) ·
self-test page (3) · settings schema (5) · translator mode incl. STATIC_EN
and translated titles (4) · mirror failover sg-1/default/auto (3) ·
robustness/pcall armor (6). The suite ran during BOTH the healthy window and
the 503 upstream outage — list tests accept the documented degraded page,
proxy-path tests must always pass.

## 6. Known limitations

- **Direct-list flakiness is upstream-owned**: /rank /recommend /search have
  no mirror parameter; during backend-upstream outages the plugin can only
  retry and report (same as the official site).
- **Search is single-page** (~50 results) — that's the whole API surface;
  no page parameter exists.
- **Chapter text is never translated by the plugin** (same policy as
  novel543/bixiange/oop): NoveLA's built-in reader translator owns novel
  content.
- **Token rotation**: the X-API-Token is baked into the official web bundle
  (public by design — the client is open source). If the backend ever rotates
  it, extract the new one from `fanqietc.com/assets/index-*.js` (constant
  `$h` next to `Ah="https://api.fanqietc.com"`) and update `API_TOKEN`.
