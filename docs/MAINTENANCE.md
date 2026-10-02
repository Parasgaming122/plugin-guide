# NoveLA Plugin Maintenance Guide — WTR-Lab, Novel543 & WuxiaBox

**Purpose:** This is the single reference file that captures EVERYTHING needed to update the `wtrlab.lua` and `novel543.lua` plugins when their sites change. Read this before touching either plugin. If a site update breaks a plugin, Part 5 (triage workflow) tells you exactly where to look.

**Last verified against live sites:** 2026-09-30 (full 6-site sweep — see Part 0.95)
**Plugins covered:** `mtl/wtrlab.lua` v1.1.9 · `zh/novel543.lua` v1.0.4 (internal dev builds 1.1.0–1.2.2 superseded)
**Upstream repo:** https://github.com/HnDK0/external-sources (⚠️ upstream main now hosts our 1.1.7 verbatim — 1.1.9's diff base is 1.1.8, itself pending upstream)

---

## Part 0 — Quick Reference Card

| | WTR-Lab | Novel543 | WuxiaBox | Bixiange | OOP 小說網 | 69書吧 tw |
|---|---|---|---|---|---|---|
| Plugin file | `mtl/wtrlab.lua` (~4,000 lines) | `zh/novel543.lua` (~1,660 lines) | `en/wuxiabox.lua` (3,339 lines) | `bixiange.lua` (1,219 lines, NEW 2026-09-19) | `oop.lua` (1,262 lines, NEW 2026-09-19)  `69shubaTw.lua` (1,541 lines, NEW 2026-09-20, v1.3.0 2026-09-26 — WAF case-bypass) |
| Current version | **1.2.1 (2026-09-18)** — poster fix on 1.2.0 (paragraph safety + multi-tag chips + tag search/discovery + safe Web+) | **1.0.5 (2026-09-18)** — poster fix + name sync on 1.0.4 | **2.3.0 (2026-09-19)** — smart mirror switcher (persistent circuit breaker, health-aware fetch order, mirror-native search pagination) on 2.2.0 (poster fix + search pagination + curated 755-tag searchable picker) | **1.0.1 (2026-09-30)** — site URL-scheme change (/cat/ → /{cat}/{id}; docs + 14 new live-capture checks, zero parser changes) on 1.0.0 (initial release) | **1.1.0 (2026-09-19)** — TOC Cloudflare-solver-storm fix (parsePage + early-abort walk + persistent page cache) on 1.0.0 (CF site via translate-proxy research, translator)  **1.2.0 (2026-09-20)** — real /indexlist/ pagination (100/page, family-verified via wcshuba.com): any-URL book adds (/book/, /indexlist/, /read/), family-accurate pager (all selects, global next-scan, book-id-option rejection, 共N章 hint), parallel batch prefetch, soft-serve guard, tocMerge keep-rule fix — on 1.1.0 (three-layer TOC, parsePage(1) never nil) on 1.0.0 (EdgeOne trigger_markers, translator, direct covers) |
| Site | https://wtr-lab.com/ | https://www.novel543.com/ (brands as 稷下書院) | https://www.wuxiabox.com/ + mirror https://www.wuxiaspot.com/ | https://www.bixiange.top/ + mirror https://bxg123.cc/ | https://www.oop.tw/ (R18 wing on oopr18.tw — separate site)  https://69shuba.tw/ (NOT the `shuba69` plugin's 69shuba.com — different DB/encoding/URLs) |
| Language | MTL (Chinese→English) | zh (Chinese) + built-in Translator mode (15 target languages) | en | zh (GB2312 site!) + built-in Translator mode | zh-TW + built-in Translator mode (queries → zh-TW)  zh-TW (UTF-8) + built-in Translator mode (queries → zh-TW, zh-CN retry) |
| Catalog data source | **HTML route first** (`/en/novel-list`, `/en/novel-finder` — same `pageProps` inside `__NEXT_DATA__`, no buildId) with `_next/data/{buildId}/` JSON as automatic fallback (buildId persisted via `set_preference`) | HTML scraping of `/bookstack/`, `/tags/`, `/ranking/`, `/shudan/`, `/search/` (all share `ul.list li.media`) | HTML scraping of `/list/{cat}/{status}-{sort}-{page}.html`, `/updates/`, `/tags/{id}-0.html`, `/e/search/` (EmpireCMS; all share `li.novel-item`) | HTML scraping (GBK) of `/dsyq/…/sort/`, search via `/e/search/indexpage.php` | HTML scraping of `/sort/` + `/search/` | HTML scraping of `/quanben/fenlei/{N}/`, `/fenlei/{slug}/{N}/`, `/search/` (all share `table.list-item` + `div.index-container` pager) |
| Chapter body | `POST /api/reader/get` JSON; `arr:` AES-256-GCM encrypted | HTML `div.content`, multi-page `_2.html` | HTML `#chapter-article .chapter-content` + `/e/extend/fy.php` paginated lists; 502 self-heal | HTML `div#mycontent` <p>; ch1 TXT header stripped | HTML `article#article` <p> only (ad DIVs inside skipped); ch1 TXT header kept-if-only-content | HTML `div#nr1` <p> only (`.reader-ad` between paragraphs skipped); `(cur / total)` sub-page fetch `/read/{bid}/{cid}/{n}` |
| Cloudflare profile | App-level Turnstile rate limit + CF infra | CF on `/search/` + TLS-fingerprint rules | CF managed challenge on everything incl. images; UA preset registered | CF in front but serves directly (2026-09-19); WebView bypass kept enabled | **CF managed challenge on EVERYTHING from datacenter**; WebView bypass kept enabled; wsrv.nl covers  **Tencent EdgeOne aegis captcha (NOT CF)** — `cf_options.trigger_markers` route it into the same WebView ladder; `/indexlist/*` is the WAF-hard path |
| Covers | **wsrv.nl proxy default** (1.2.1) | **wsrv.nl proxy default** (1.0.5) | **wsrv.nl proxy default** (2.2.0) | **wsrv.nl proxy default** (1.0.0) | **wsrv.nl proxy default** (1.0.0; nocover.jpg passthrough)  **DIRECT from p.69shuba.tw** (open CDN, no proxy; deterministic `p.69shuba.tw/{id÷1000}/{id}/{id}s.jpg`) |
| Test harness | `testenv/LuaTest.java` (**66 live** + 49 mock) + `scripts/test_plugin_integration.py` (22 offline) + `testenv/ChapterTiming.java` | `testenv/Novel543Test.java` (**197 live** + 1 env-skip; TEST 38 hermetic since 2026-09-30 — Google 302s the GET /translate_a/t variant from datacenter IPs) | `testenv/WuxiaboxTest.java` (**147 fixture tests**, header-capturing mocks + plugin-reload restart simulation) | `test-harness/BixiangeTest.java` (**90 mock** + 20 live, GBK fixtures + charset emulation + T23 live-captured 2026-09-30 URL scheme) | `test-harness/OopTest.java` (**97 mock**, cleaned translate-proxy fixtures + synthesized 5-page TOC battery) | `test-harness/S69TwTest.java` (**127 mock** + **S69RealSeed.java 20/20 real-capture**, v1.3.0 real /Indexlist/ fixtures + challenge detection + request-budget battery) |
| Local dev plugin copies | `/home/z/my-project/download/wtrlab.lua` | `/home/z/my-project/download/novel543.lua` | `/home/z/my-project/download/wuxiabox.lua` | `/home/z/my-project/download/bixiange.lua` | `/home/z/my-project/download/oop.lua` | `/home/z/my-project/download/69shubaTw.lua` |

**Test commands** (run from `/home/z/my-project/testenv/`):

```bash
# WTR-Lab — syntax + live suite + mock suite
java -cp "lib/*:." SyntaxCheck.java /home/z/my-project/download/wtrlab.lua
java -cp "lib/*:." LuaTest.java /home/z/my-project/download/wtrlab.lua
java -cp "lib/*:." LuaTest.java /home/z/my-project/download/wtrlab.lua mock
java -cp "lib/*:." LuaTest.java /home/z/my-project/download/wtrlab.lua nobit32 mock   # arithmetic fallback path

# Novel543 — syntax + live suite (harness HTTP routes through curl; see Part 2.5)
java -cp "lib/*:." SyntaxCheck.java /home/z/my-project/download/novel543.lua
java -cp "lib/*:." Novel543Test.java /home/z/my-project/download/novel543.lua

# WuxiaBox — syntax + fixture suite (mocks serve live-captured HTML from research/wuxiabox/)
java -cp "lib/*:." SyntaxCheck.java /home/z/my-project/download/wuxiabox.lua
java -cp "lib/*:." WuxiaboxTest.java /home/z/my-project/download/wuxiabox.lua

# Note: SyntaxCheck flags getBookRating as "MISSING" for novel543 — it is OPTIONAL in
# NoveLA (SourceInterface.kt provides a null default). Novel543 has no rating system, so
# this is correct by design. getSettingsSchema EXISTS since v1.2.0 (Translator mode).
#
# javac is NOT installed in this environment — compile with the bundled Eclipse compiler:
#   java -jar lib/ecj.jar -source 19 -target 19 -cp "lib/luaj-jse-3.0.1.jar:lib/jsoup-1.17.2.jar:lib/gson-2.10.1.jar" -d . <File>.java
#   java -cp ".:lib/*" <File> <args>

# Bixiange + OOP — run from /home/z/my-project/test-harness/ (jars sit flat there)
java -jar ecj.jar -source 19 -target 19 -cp "luaj-jse-3.0.1.jar:jsoup-1.23.1.jar:gson-2.14.0.jar" -d . OopTest.java
java -cp ".:luaj-jse-3.0.1.jar:jsoup-1.23.1.jar:gson-2.14.0.jar" OopTest
java -jar ecj.jar -source 19 -target 19 -cp "luaj-jse-3.0.1.jar:jsoup-1.23.1.jar:gson-2.14.0.jar" -d . BixiangeTest.java
java -cp ".:luaj-jse-3.0.1.jar:jsoup-1.23.1.jar:gson-2.14.0.jar" BixiangeTest
```

---

## Part 0.5 — The September 2026 NoveLA engine update (reclone 2026-09-18, dc3d18c)

50 upstream commits landed between the Aug-25 clone and Sep-18. Everything a plugin author must know:

### New Lua APIs
| API | What it does | Notes |
|---|---|---|
| `show_error(title, message)` | Queues an error dialog surfaced in catalog/search/chapters/filters | Fire-and-forget; still return a valid (empty) result. Better than silent empties — use for "site unreachable" / "tag unresolvable" cases. |
| `getUserAgentPreset()` | Plugin declares a UA preset name; engine applies it to ALL source requests + untagged requests to the baseUrl host (incl. **image loader cover fetches**) | Presets: "Chrome 150 (Windows)", "Chrome Mobile", "Safari Mobile", "Firefox Mobile", etc. Keep cf_clearance UA-consistent. Do NOT hardcode UA in headers (that overrides the preset). |
| `http_get(url, {binary=true})` | Returns body as 1-based Lua byte table | Binary responses are NOT cached. |
| `http_get_batch(urls [, config])` | Parallel GETs → array of `{success, body, code}` | Supports binary. |
| `aes_decrypt(data, key, iv)` | AES/CBC/PKCS5 | **CBC only** — wtr-lab's GCM still needs the pure-Lua implementation. |
| `set_preference(key, value)` | Write to SharedPreferences "lua_preferences" | wtrlab already persists buildId with it. |
| `get_localStorage(url)` | Extracts localStorage from the WebView | |
| `detect_pagination(html)` | Finds next-page link (`a[href]` containing next/›/») → `{hasNext, next_url}` | |

### New filter type: `tag_input` (THE answer for big tag lists)
`{ type = "tag_input", key = …, label = …, options = {{value,label}…}, allowCustom = bool }` — renders a **text field with live inline suggestions** (substring filter over options) + selected values as removable chips. Marshalled as `filters[key.."_included"]` = Lua array of the option `value` strings (custom text too, when allowCustom). Unlike checkbox/tristate there is NO eager chip rendering, so hundreds of options are fine. Used by wuxiabox 2.2.0 (756 tag options).

### cf_options extensions
`{ whitelist=bool, ignore_markers={…}, trigger_markers={…} }` — `trigger_markers` are custom body markers that FORCE the WebView bypass ladder (for non-CF WAFs that answer 200 with a captcha page). `whitelist=true` remains the landmine it always was (disables bypass) — never set it for CF-protected sites.

### Poster loading (the September poster breakage, all plugins affected)
- Image URLs (`.jpg/.png/.webp/.json/.txt/.lua`…, see `STATIC_EXTENSIONS` in `CloudfareVerificationInterceptor) are **EXEMPT from the CF WebView bypass** — a challenged cover hands the challenge HTML to Coil → silently broken poster.
- Coil 3 (since Sep 7) shares the engine OkHttp client (CF interceptor + cookies) and sends `Referer: scheme://host/` (derived from the image URL) on every cover request; auto-retry 2x + manual retry button.
- **The fix pattern (all three plugins, 2026-09-18): route covers through `https://wsrv.nl/?url=<url-encoded cover>&w=450&we&output=jpg&q=80`** — wsrv.nl / images.weserv.nl is in the engine's `CLOUDFLARE_WHITELIST` (no useless bypass attempts), fetches server-side (its IPs are not challenged), and resizes. A per-plugin "Cover images" setting (`proxy` default / `direct`) is the escape hatch.
- Live verification: wuxiabox direct cover = 403 challenge; via wsrv.nl = 200 image/jpeg. wtr-lab covers redirect 302→302→full-size 300 KB+; via wsrv.nl = ~44 KB @ w=450.

### Other engine changes
- `ServerErrorRetryInterceptor`: GETs auto-retry on 429/502/503/504 (500ms→2s exponential, 4 retries) — extra resilience under wuxiabox's intermittent 502s.
- Engine auto-adds `User-Agent`, `Referer` (same-origin), `Accept-Language` to every plugin HTTP call; plugin `headers` override them.
- App search/browse pagination: `PagedListIteratorState` dedupes by URL hash; an **empty page or a duplicate page ENDS pagination (CONSUMED)**; a Lua `error()` becomes a retryable Response.Error (list kept, index rolled back on retry) — so plugins should raise errors instead of returning silent empties for transient failures, and NEVER return the same items for consecutive indices.
- Source catalog screen supports filter presets + TagInput + text autocomplete (sourceExplorer).

## Part 0.7 — WuxiaBox plugin (`en/wuxiabox.lua` v2.3.0) — quick map

Full documentation lives in `download/wuxiabox_pull_request.md` (v2.3.0 PR; smart-switcher design, engine-fetch reality + optional patch, site map, mirror portability table, curation pipeline, 147-test table). Key facts for maintenance:

- **Site**: wuxiabox.com (EmpireCMS "Web Novels MTL"); full mirror wuxiaspot.com (same slugs; DIFFERENT tag-id AND searchid spaces — only slug/keyword URLs are portable).
- **Surfaces**: `/list/{cat}/{status}-{sort}-{page}.html` (0-based, 30/page, statuses Capitalized) · `/updates/{n}.html` · `/tags/{id}-0.html` + `/e/tags/index.php?page=N&tagid=ID&line=500&tempid=9` (500/page, primary-only) · search POST `/e/search/index.php` (show=title&tempid=1&tbname=news&keyboard=…) → 302 → `/e/search/result?searchid=S`; pages `/e/search/result/index.php?page=N&searchid=S` (0-based; pager never links the current page; 总数 grand-total marker).
- **Chapters**: novel page embeds ch 1–100; `/e/extend/fy.php?page=N-1&wjm={slug}` (XHR headers required) paginates the rest; `parsePage` chapter pagination; 502 self-heal with health-aware attempt order + quadratic backoff (NO pre-attempt sleep in 2.3.0 — the engine's retry ladder already waited); pacing setting.
- **Smart switcher (v2.3.0)**: per-site health tracker persisted via `set_preference` key `wuxiabox_site_health` (`box=<fails>,<cooldownUntilMs>;spot=…`) — 2 consecutive fails → 10-min cooldown (skipped by `orderedBases()`), success resets, 404 neutral, expiry half-open. Every fetch path feeds it, INCLUDING the engine's own failed chapter fetch (getChapterText charges junk bodies to SITE before rescuing). Search records its searchid's base per query (`_searchBaseByQuery`) so mirror-started searches paginate on the mirror. `transformChapterUrl(url)` ships as a forward-compatible hook — inert on stock engines, active on builds that expose it (PR doc has the 10-line Kotlin patch).
- **Tags (v2.2.0)**: 755 curated (`scripts/curate_wuxiabox_tags.py` — wtrlab taxonomy ∩ + popular + fixtures + Honghuang family; exclude mirror fixtures!) surfaced as ONE `tag_input` filter (756 options incl. the "honghuang" family keyword); union browse dedups by novel URL; canonical id = LOWEST id among duplicate names.
- **Covers**: wsrv.nl proxy default (`wuxiabox_covers` setting).
- **UA**: `getUserAgentPreset()` = "Chrome Mobile".

## Part 0.8 — Bixiange + OOP plugins (`bixiange.lua` v1.0.0 / `oop.lua` v1.1.0) — quick map (2026-09-19)

Two NEW sources added this session. Both ship the novel543 translator core
(Google dict → MyMemory → gtx, cache, breaker, pcall armor) with per-plugin
preference prefixes (`bixiange_*` / `oop_*`).

**bixiange.top (笔仙阁)** — GB2312 EmpireCMS, mirror bxg123.cc (SAME database:
identical book ids AND searchids → fully transparent host-substitution
failover on every fetch incl. search):
- `charset = "GBK"` metadata → engine decodes its own chapter downloads;
  plugin fetches pass `{charset="GBK"}`; search keyword percent-encoded as
  GBK via `url_encode_charset(q, "GBK")` (UTF-8 keyword → 信息提示 error page).
- Books: two URL generations `/cat/{id}/` (new) vs `/cat/{id}.html` (old,
  slash form 403s!) — NEVER normalize; use the site's own hrefs.
- Search: POST `/e/search/indexpage.php` → 302 (RELATIVE Location
  `result/?searchid=S`) → 20/page, **0-based** `page=1..`; total in
  `<a title="总数"><b>N</b></a>` (the &nbsp; inside kills `%s` patterns — use
  `.-` lazy match); zero results = 200 信息提示 page (NOT an error).
- List pager `index_N.html`; 尾页 link UNRELIABLE (claims 30, ~45 exist) —
  hasNext = 下一页 link only; beyond-end pages serve cycling garbage (app's
  duplicate detection ends pagination).
- Ch1 embeds TXT header (title/作者/简介+synopsis) — two-tier strip
  (第X章-marker ≥ para 4, else structural markers).

**oop.tw (OOP 小說網)** — UTF-8 zh-TW, CF managed challenge on EVERYTHING
from datacenter (research done via the Google-Translate proxy
`www-oop-tw.translate.goog` — preserves DOM structure; fixtures cleaned by
`scripts/clean_oop_fixtures.py`, incl. un-reversing CJK paragraphs that the
proxy character-reversed):
- Library `/sort/{page}/` (10/page), category `/sort/{cat}/{page}/`
  (1-14, 12=R18); hasNext from pager `>>` link (javascript:void = no next).
- Search GET `/search/?searchkey=…&searchtype=all` — **≤100 results, ONE
  page, no pagination** (live-verified); queries translated to zh-TW.
- Book `/abooka/a{id}a/`: meta-tags (category, 萬字, 全本/連載, rating),
  2nd .novel-meta 关键字 tags = genres, `.update-time` = last update.
- **Chapter catalogs paginated 30/page via `?p=N`** — the `.chap-pager`
  select options enumerate every page (any page's select yields totalPages;
  element `.attr("value")` accessor). v1.1.0: served through
  `parsePage(bookUrl, page)` (engine walks pages + stops at first failure +
  refreshes incrementally); `getChapterList` fallback ABORTS at the first
  failed page; a persistent `oop_toc_<id>` page cache (LRU 5 books / 100KB)
  serves immutable interior pages (site only APPENDS chapters) without
  network, resumes broken walks, and serves a stale TOC when the site is
  unreachable. Chapter URLs use global article ids — NOT synthesizable
  (probed `?p=all`: no full-TOC endpoint).
- Chapter text: `article#article` <p> ONLY (ad DIVs nested inside the
  article); ch1 often = pure TXT header → kept when nothing follows
  (empty chapter = reader error).
- The site's catalog sometimes swaps adjacent chapters (003,005,004…) —
  chapters re-sorted ONLY when every title parses to a number.

## Part 0.9 — 69shubaTw plugin (`69shubaTw.lua` v1.3.0) — quick map (2026-09-26)

**v1.3.0 (the "solver storm" root-cause fix):** the user reported v1.2.0
still failed — *"solver opens 5+ times, chapters never load; a 40-chapter
novel, 100 chapters per page, /2 /3 pagination"*. The root cause turned out
to be **a case-sensitive EdgeOne WAF path rule**: lowercase `/indexlist/*`
is challenged from EVERY IP (even Google Translate's clean egress; the pass
cookie `__ct_ac_cpg` lasts only 5 minutes → re-challenge per request =
solver storm + fast-fail ladder = empty TOC), while **`/Indexlist/`**
(capital I) serves the identical page WAF-free. Live-proven side by side
through the translate proxy: `/indexlist/342441/` → 403 challenge vs
`/Indexlist/342441/` → 200 real catalog, same session, seconds apart.

- **Catalog fetches → capital-I URLs only** (`tocPageUrl`):
  `SITE/Indexlist/{id}/` and `…/{N}/`. Zero solver openings from any IP the
  site otherwise tolerates. `/book/`, `/read/`, `/search/`, `/fenlei/`,
  `/quanben/` carry no such rule (verified from clean IPs) and stay
  lowercase/canonical.

- **The REAL markup, captured at last** (all 5 pages of book 342441 =
  450 chapters, via capital-I + clean-IP translate proxy; fixtures
  `idx_p1..p5.html` produced by `scripts/gen_69shubatw_v130_fixtures.py`):
  list = `div#alllist.lb_mulu` → `ul.last9` → `li`; **two chapter-entry
  forms** — plain anchors AND anti-scrape `<span class=protected-chapter-link
  data-cid-url=/read/{bid}/{cid}>` (~2 per page; v1.2.0 silently dropped
  them — `collectChapterItems` now harvests `[data-cid-url]` too); pager =
  `select#indexselect-top` whose option VALUES are every page URL
  (`1 - 100章` … `401 - 450章`; page 1 unnumbered) + 上一页/下一页 anchors +
  a `没有了` disabled span on the last page. `tocTotalPages` reads option
  page numbers (book-id trap still rejected) with the 下一页 href as
  cross-check (its trailing number also reveals the next page).

- **Zero speculative requests:** the v1.2.0 `http_get_batch` prefetch,
  blind page-2 probe, window chase and the v1.1.0 seed + per-chapter
  `#pb_next` walk are ALL removed (each speculative fetch = one more solver
  ladder when the WAF bites; the walk was the storm machine — one ladder
  per chapter). Page 1 = ONE fetch; page N = ONE fetch each, lazy and
  engine-driven (`DownloaderRepository` walks 1..totalPages sequentially and
  KEEPS collected pages on failure — early-stop is safe). A ≤100-chapter
  novel costs exactly ONE catalog request.

- **Challenge detection in-plugin** (`isChallengeBody`): the aegis page's
  body markers (POST endpoint, checkbox widget class, page title, Turnstile
  script URL) are checked on EVERY catalog response — 403 or 200 — and a
  challenge answer becomes an immediate guided `show_error` with ZERO
  fallback fetches. `cf_options.trigger_markers` (4 markers now) stays
  registered so the app's WebView ladder can still engage manually on other
  surfaces. **TOC cache format v3** (`3|tp|pages…`) — v1/v2 walk-era entries
  are discarded on load (clean migration); interior pages serve offline,
  the last page re-fetches for growth. `bookIdFromUrl` is case-insensitive
  (accepts `/Indexlist/` pastes). Headers gained `Accept-Language`.

**Key facts kept from v1.0–v1.2:** `parsePage(1)` NEVER returns nil (empty
table + show_error worst case); `normalizeReadUrl` requires the exact
same-book `/read/{bid}/{cid}` path; canonical chapter URLs everywhere;
covers direct from the open CDN `p.69shuba.tw/{id÷1000}/{id}/{id}s.jpg`
(no wsrv.nl — deliberate); the translator is the novel543 engine (zh-TW
source); UA preset = Chrome Mobile.

**Tests:** S69TwTest.java **127/127** (T9 real page-1 contract incl. both
protected spans + capital-I URL assertion; T10 450-chapter lazy walk; T11
early-abort keeps page 1; T12 the user's 40-chapter case = ONE request,
single-page, any URL shape; T12b soft-serve guard; T13 challenge → empty
table never nil, zero fallback fetches, 200-challenge detected; T14 cache
v3 + zero-network interior + stale last page; T15 full stale-serve; T16-T21
chapter text/translator/search unchanged) + S69RealSeed.java **20/20**
(real-data end-to-end: real book details → real catalog pages → 450-chapter
TOC → real chapter text for BOTH entry forms → zero lowercase requests →
exactly 5 capital fetches). Docs: `download/69shubatw_pull_request.md`.

## Part 0.95 — The 2026-09-30 full sweep (all 6 sites, all suites, all green)

**What was done:** every plugin re-tested (7 suites, 744 checks total — see the
final status below), every site visited live, every selector verified against
current markup. Findings and actions:

| Site | Live status | What changed | Action taken |
|---|---|---|---|
| wtr-lab.com | UP | nothing — `_next/data` search (buildId `OwRVqCzcuPWEvGCYQC47j`), `api/chapters/{id}` (112 ch for raw_id 98477), `api/reader/get` (`translate: "web"/"webplus"/"ai"` service strings, `arr:` AES-GCM payload in `data.data.body`) all intact; `/en/serie-{id}/` 308-redirects to `/en/novel/{id}/` which the plugin already uses | none — 66/66 |
| novel543.com | UP | book URLs now `/{bookId}/` (e.g. `/1022705585/`), chapters `/{bookId}/{cid}_{n}.html`, multi-page `{cid}_{n}_{p}.html` (live proof: `/0205702733/8096_1.html` (1/2) → `8096_1_2.html`); book 93618 removed from site; bookstack/ranking/shudan cards + `div.content` + `<bookUrl>/dir` unchanged; `/search/` still CF-challenged from datacenter (solver handles it on devices) | doc note in header; TEST 38 made hermetic (Google 302s the GET `/translate_a/t` variant from datacenter IPs — POST still serves; counter moved before canned handling so the GET-fallback logic stays provable) — 197/197 |
| wuxiabox.com + wuxiaspot.com | UP | nothing — CF "Just a moment" from datacenter (as always; devices pass); via translate-proxy: home/book/chapter pages verified, `chapter-list` + 107 chapter links + `#chapter-article .chapter-content` + `strong.chapter-title`/`span.chapter-no` all present | none — 147/147 |
| oop.tw | UP | nothing — via translate-proxy (redirects to `www-oop-tw`): book `/abooka/a{id}a/` (`novel-title`/`novel-cover`/`novel-meta`/`novel-main`), catalog `?p=2` (`catalog-content`/`chap-pager`), chapters `/areada/a{bid}a/a{cid}a.html` (`article#article`, `.reading-content`, `#prev_url`/`#next_url`) all present | none — 97/97 |
| bixiange.top + bxg123.cc | UP | **URL scheme changed**: `/cat/{id}/` + `/cat/{id}.html` → **404**; books now `/{cat}/{id}` (e.g. `/xhqh/23552`) and `/{cat}/{id}.html`; chapters `/{cat}/{id}/index/{n}.html`; mirror switched identically; all selectors unchanged (`.hd .list ul li`, `descInfo`/`descTip`, `.catalog ul li a` — 504 anchors, `div#mycontent`, `总数`, `index_N.html`) | **v1.0.1** — docs updated, fresh live captures (bx26_*.html) + 14 new T23 checks; plugin code UNCHANGED (href-following design proved future-proof) — 90/90 |
| 69shuba.tw | UP | nothing — capital-I `/Indexlist/342441/` WAF bypass still 200 (all 5 pages), `/book/342441/` (`startread`/`last9`), `/read/342441/890315` (`nr_title` + `div#nr1`), search `/search/?searchkey=…&searchtype=all` all working via translate-proxy | none — 127+20/127+20 |

**Google-translate environment change (affects tests, not plugins):** the GET
variant of `translate.googleapis.com/translate_a/t?client=dict-chrome-ex` now
302-redirects to `google.com/sorry` from datacenter IPs (the POST variant
still serves normally — live-verified the same minute). Real devices
(residential/mobile IPs) are unaffected. Novel543Test TEST 38 was made
hermetic: the GET path is now served by the canned-response handler while the
`translateGetCalls` counter (incremented before canned/block handling) still
proves the plugin actually takes the GET fallback. The plugin's engine chain
order (POST first) remains optimal.

**Final suite status (2026-09-30):** LuaTest 66/66 · Novel543Test 197/197
(+1 env-skip) · WuxiaboxTest 147/147 · OopTest 97/97 · BixiangeTest 90/90 ·
S69TwTest 127/127 · S69RealSeed 20/20 — **744 checks, 0 failures** (incl.
the 197-test live Novel543 run). SyntaxCheck green on all six plugins.

## Part 1 — WTR-Lab Plugin (`wtrlab.lua` v1.1.9)

### 1.1 Architecture map (where things live in the file)

| Lines (approx) | Section | What it does |
|---|---|---|
| 1–176 | Header changelog comment | Full change history + the `cf_options` warning. Keep the warning. |
| 178–186 | Metadata | `id="wtrlab"`, `version`, `baseUrl=https://wtr-lab.com/`, `language="MTL"`, icon URL |
| 187–222 | Settings keys + caches + clock | `PREF_MODE="wtrlab_mode"` (**do NOT rename** — existing user settings), `PREF_DELAY`, `PREF_BUILDID="wtrlab_buildid"`; `termCache`, `_pageCache`, `_buildIdCache`, `_chaptersCache` (45 s TTL); `nowMs()` |
| 223–262 | Helpers | `absUrl`, `fetchPage` (session page cache), `extractRating` |
| 263–580 | **AES-256-GCM local decryptor** | Pure-Lua: S-box, key expansion, ShiftRows/MixColumns, GF(2^128) GHASH (16-byte-IV J0 path), CTR mode. `GCM_KEY` constant + fly.dev proxy fallback live here. Byte-safe base64 decoder included (host `base64_decode` corrupts bytes ≥ 0x80). |
| 626–680 | JSON-route fallback machinery | `getBuildId(force)` (persisted via `set_preference`; force → HTML refresh), `fetchNextData(path, params)` (stale-buildId refresh + one retry; persists confirmed buildId) — used only when the HTML route fails |
| 682–719 | **HTML-first fetch (v1.1.9)** | `extractNextDataProps(html)` — parses `__NEXT_DATA__`, accepts **BOTH** props shapes (top-level `pageProps` AND `props.pageProps` — the real site uses the nested form on HTML routes!); `fetchPagePropsHTML`; `fetchCatalogPage` (HTML route first → `fetchNextData` fallback) |
| 721–774 | Result shaping | `seriesToItems`, `pagePropsToResult` (**`PAGE_SIZE = 10` short-circuit hasNext formula**) |
| 787–1843 | **Tag search index & resolver** | `TAG_CATEGORIES` (12), `TAG_SEARCH_INDEX` (888 `id\|Label\|catId` lines — auto-generated, do not hand-edit), `ALL_TAGS` parser (keeps `label` display-case + `lower` match key), `tagSearchResolve(text, cat)` — v1.1.9 semantics: exact → id → single substring → **ambiguous (error listing tags)** → `keyword*` wildcard; phrase-first + word fallback; category scoping |
| 1845–1869 | Catalog entry points | `getCatalogList`, `getCatalogSearch` — both via `fetchCatalogPage` (HTML-first) |
| 1871–2022 | Book metadata + chapter list | Title/cover/desc selectors (session-cached); `fetchChaptersData()` — ONE `api/chapters` call behind a 45 s TTL cache shared by `getChapterListHash` (`"<count>\|<max updated_at>\|<checksum>"`, legacy book-page fallback) and `getChapterList` |
| 2023–2304 | Chapter text | `cleanParagraph`, glossary/patch application, `fetchChapterJson` (**`POST api/reader/get`**, requireTurnstile detection + 2 retries 600 ms/1.8 s + actionable `error()`), `getChapterText` (table/`arr:`/`str:` dispatch; v2 glossary **negative-cached**; local decrypt → proxy fallback) |
| 2305–2340 | Settings schema | Mode select (key `wtrlab_mode`) + Chapter Fetch Delay select |
| 2393–3662 | **Filter list (28 filters)** | 17 finder filters (`title_search` FIRST, 13 selects, 40-genre tristate, `tag_category` 12, 2 tag-search text fields, `tag_operator`) + **11 `tag_pick_N` selects** (`Tags: <category>` dropdowns, 888 tags + `Any` each = 899 options; generated by `scripts/gen_tag_pickers.py` from `research/tags_live_v3.json`, spliced by `scripts/splice_v119.py` between `[TAG PICKERS BEGIN]/[END]` markers). **No `tags_*` tristate group filters** |
| 3663–3782 | `getCatalogFiltered` | `title_search` → `text=`; tag keywords → scoped resolution (errors propagate with the field name) + `tag_pick_N` merge (validated, deduped, junk skipped) → `ti=`/`te=`; fetch via `fetchCatalogPage` |

### 1.2 Site API reference (all verified live 2026-09-03)

**Catalog / search / filtered browse** — HTML route first (v1.1.9), `_next/data` JSON as fallback (10 items/page):

```
GET /en/novel-list?page=N&orderBy=reader              ← HTML route (primary since 1.1.9)
GET /en/novel-finder?<filters>                        ← HTML route (primary since 1.1.9)
GET /_next/data/{buildId}/en/novel-list.json?page=N   ← JSON route (automatic fallback)
GET /_next/data/{buildId}/en/novel-finder.json?<filters>
```

- **Why HTML-first:** the JSON routes intermittently STALL server-side (observed 7–25 s per request, recovering minutes later); the HTML routes render consistently (~0.5–1.6 s) and answer every finder param + pagination identically.
- **⚠️ Props shape differs by route (gotcha #30):** HTML pages embed `{"props":{"pageProps":{…}},"buildId":…}` (standard Next.js `__NEXT_DATA__` shape); the JSON routes return `{"pageProps":{…}}` at the TOP level. `extractNextDataProps` must accept BOTH. (This exact mismatch made the first v1.1.9 draft always fall back — every live catalog call logged "HTML route failed".)
- `buildId` (fallback route only) changes **on every site deploy**. Regex it from `/en/novel-finder` HTML: `"buildId":"([^"]+)"`. Persisted via `set_preference`; on 404/missing-`pageProps` → refresh once → retry.
- Response: `{pageProps: {series: [...], count: "<STRING!>", tags?}}`. ⚠️ **`count` is a JSON string — must `tonumber()`** (this was a real bug).
- `hasNext = #items > 0 and returned >= PAGE_SIZE and page * PAGE_SIZE < countNum` (PAGE_SIZE=10, `returned = #pp.series` pre-dedup).
- Series item fields: `raw_id`, `slug`, `data.title`, `data.image`, `rating`. Book URL: `https://wtr-lab.com/en/novel/{raw_id}/{slug}`.
- `tags.ungrouped` (888 items: `{value, label, category_id}`) + `tags.groups` (11 categories) = **source of truth for the tag filter list**.

**Filter URL params** (each verified to change result count):

```
text= · page= · orderBy=(date|update|random|daily_rank|weekly_rank|monthly_rank|view|
  name|reader|chapter|character|rating|total_rate|vote|weighted) · order=(asc|desc) ·
status=(all|ongoing|completed|hiatus|dropped) · release_status=(all|released|voting) ·
addition_age=(all|day|week|month|3month|6month|year|last_month|last_year|this_year) ·
gi=1,2,3 (genre include) · ge= (genre exclude) · gc=(and|or) ·
ti=801,802 (tag include) · te= (tag exclude) · tc=(and|or) ·
count_type=(chapter|character|unlock|unlock-ratio) · count_filter=(min|max) · count_value=N ·
minr=1.0-5.0 step .1 · minrc=5-50 step 5
```

⚠️ `minc=` is **DEAD** (silently ignored by the site — verified: `minc=1000` returns the unfiltered baseline of 87,809). The old 1.1.6 "Minimum Chapters" filter never worked. Use `count_type/count_filter/count_value`.

**Chapters / reader / glossary:**

```
GET  /api/chapters/{raw_id}                → {chapters:[{order, title, ...}]}   (all chapters, one call)
POST /api/reader/get                       → chapter body (see below)
       body: {"translate":"ai"|"web", "language":"none", "raw_id":"<id>",
              "chapter_no":N, "retry":false, "force_retry":false}
       headers: Content-Type: application/json, Referer: <chapter URL>, Origin: https://wtr-lab.com
GET  /api/v2/reader/terms/{raw_id}.json    → v2 glossary {glossaries:[{data:{terms:[[["trans"],"原文",…]}}]}
```

- `body` in AI mode = array of paragraphs with `※N⛬`/`※N〓` glossary markers; in web/webplus mode = `"arr:…"` encrypted string (see 1.3).
- `data.glossary_data.terms` = chapter-level glossary `[[raw, original], ...]` (0-based idx matches markers).
- `data.patch` = `[{zh, en}, ...]` replacement pairs.
- Rate limit after ~15 fetches/IP: HTTP 200 + `{"success":false,"requireTurnstile":true,"threshold":15,"count":N}` — see 1.4.
- Premium error: `[1401] You are not logged in!` — chapter locked, nothing the plugin can do.
- AI-mode free tier: ~10 chapters/novel/day for free accounts (surfaces via standard `success:false` → `error()`).

**Book page HTML selectors** (mobile UA): `h1` (title), `.image-wrap img` (cover), `.desc-wrap .description` (desc), `div.items-center.text-center` (metrics: Chapters/Status blocks), `a[href*='novel-list?genre=']` (genres), `"updated_at":"…"` first match in `__NEXT_DATA__` (book's own row). 307 redirect on stale slug — catalog URLs are canonical.

### 1.3 AES-256-GCM chapter decryption (the gibberish fix)

- Format: `arr:{b64 IV}:{b64 GCM tag}:{b64 ciphertext}` or `str:{plain}`.
- Algorithm: **AES-256-GCM**, key = 32 ASCII bytes `IJAFUUxjM25hyzL2AZrn0wl7cESED6Ru` (hardcoded in the site's public JS bundle — chunk containing `importKey`/`crypto.subtle`).
- IV observed 16 bytes → non-96-bit → GCM J0 derived via GHASH (plugin implements both 12-byte and GHASH paths).
- Decrypt order: local pure-Lua (tag skipped) → fly.dev proxy → clear `error()`. ~2 s for 60 KB on the JVM.
- ⚠️ Host `base64_decode` is **not binary-safe** (UTF-8 Java String corrupts bytes ≥ 0x80) — the plugin's own byte-safe decoder is mandatory.
- **If the site rotates the key:** fetch any web-mode chapter, find the new 32-char string near `crypto.subtle`/`importKey` in the JS chunks, update `GCM_KEY`. Symptom of rotation: every chapter errors with "Local decrypt AND proxy both failed" and the proxy ALSO fails (proxy may lag on rotation too — check the proxy independently before concluding).

### 1.4 Turnstile / "Security Check" (rate limit)

- **Application-level** per-IP counter on `/api/reader/get` (NOT Cloudflare infra). Threshold 15. Counter does NOT decay quickly; `cf_clearance` does NOT reset it; only a valid `turnstileToken` re-POST resets it (sitekey `0x4AAAAAABdTx0ekcJVVPAYZ`, widget renders inside the chapter page).
- Blocking is **per-backend-instance and intermittent** → the plugin's 2 retries (600 ms/1.8 s backoff since v1.1.8 — long sleeps are pure latency, the counter only resets via a solved `turnstileToken`) often land on a healthy instance.
- NoveLA's `CloudfareVerificationInterceptor` auto-detects this exact response (marker `requireTurnstile` + `server: cloudflare` + HTTP 200) and runs the WebView bypass ladder automatically. The plugin's own detection is a second layer that ends in an actionable error message.
- **NEVER add `cf_options = { whitelist = true }`** — it makes `isNotCloudflare()` return true for the host → disables ALL of the above recovery. (The community v2.0.0 draft shipped it with a comment claiming the opposite.)
- `.json` URLs (terms endpoint) are on the interceptor's static-extension shortcut — challenges there pass undetected; plugin treats failed terms fetch as "no v2 glossary" (harmless fallback to chapter-level glossary).

### 1.5 Tag refresh procedure (when the site adds tags)

Idempotent script chain — safe to re-run (v1.1.9: index format `id|Label|catId` + 11 `tag_pick_N` dropdown blocks):

```bash
# 1. Refresh source data (tags + groups) → research/tags_live_v3.json
python3 scripts/wtrlab_tags_v3.py        # dumps live finder __NEXT_DATA__ tags
# 2. Regenerate the search index (+ prints the TAG_CATEGORIES block)
python3 scripts/gen_tag_search_index_v2.py
# 3. Splice the index into wtrlab.lua (idempotent)
python3 scripts/swap_tag_block_v2.py
# 4. Regenerate the 11 tag_pick_N dropdown blocks → research/tag_pickers.lua
python3 scripts/gen_tag_pickers.py       # reads tags_live_v3.json; refuses on duplicate labels
# 5. Splice the pickers into getFilterList (idempotent, [TAG PICKERS BEGIN]/[END])
python3 scripts/splice_v119.py
#    (If category counts changed, hand-update the two TAG_CATEGORIES/tag_category
#     option lists AND the 11 "Tags: <category> (n)" picker labels.)
# 6. Verify

cd testenv && java -cp ".:$(ls lib/*.jar lib2/*.jar | tr '\n' ':')" SyntaxCheck ../download/wtrlab.lua
java -cp ".:$(ls lib/*.jar lib2/*.jar | tr '\n' ':')" LuaTest ../download/wtrlab.lua mock
python3 ../scripts/test_plugin_integration.py
```

Genres (ids 1–40, `SERIE_GENRES` in site JS) change ~never — inlined, no refresh script.

### 1.6 WTR-Lab failure modes playbook

| Symptom | Likely cause | Fix |
|---|---|---|
| Chapters error "Local decrypt AND proxy both failed" | AES key rotated | Update `GCM_KEY` (see 1.3) |
| Chapters error "…Security Check / rate limit reached" | Per-IP Turnstile limit (working as designed) | No code fix; user solves challenge once in integrated browser. Optional: enable Chapter Fetch Delay setting |
| Catalog/search suddenly empty | HTML route AND JSON fallback both failing, or props shape changed (gotcha #30) | Re-verify §1.2 endpoints manually with curl; check BOTH props shapes; update `extractNextDataProps`/`fetchNextData`/`pagePropsToResult` |
| Homepage/catalog slow AGAIN (the 1.1.9 report) | `_next/data` congestion AND the HTML route degraded, or the buildId 404-probe loop | Run the harness live suite and watch the log lines: "HTML route failed, falling back" means the primary path is dead — curl the HTML route and check `__NEXT_DATA__` still carries `props.pageProps` |
| Filter results wrong/empty | Site changed param names (like `minc` dying) | Re-verify each param changes result count (§1.2); fix `getCatalogFiltered` param building |
| "no tag matches 'xyz'" / "'xyz' is ambiguous" error at filter apply | Tag Search keyword typo, or tag renamed/removed by the site | Ambiguity is by design (autocomplete feedback — type the full name or add `*`); if a previously-valid keyword breaks, re-run the §1.5 refresh chain |
| New tags missing from Tag Search / pickers | Tag index stale | Run §1.5 refresh chain (site added 6 tags between 2026-08-26 and 09-03) |
| Tags invisible in the filter sheet (1.1.8 report) | Keyword-only fields — fixed in 1.1.9 by the 11 `tag_pick_N` dropdowns | Verify TEST 2: 28 filters, 899 tag options, `Any`-first |
| Update checks never fire | `api/chapters` shape changed (hash source since 1.1.8) | Verify with curl that `chapters[i].updated_at` still exists; fix `fetchChaptersData`/hash folding |
| Chapter list empty | `api/chapters/{id}` shape changed | Verify with curl; fix `getChapterList` parsing |
| Gibberish returns | Local decrypt AND proxy both silently failing → raw `arr:` saved | Should be impossible (both-fail → `error()`); if seen, the error path itself broke — check `decryptBody`/`b64ToBytes` |
| Catalog slow on FIRST browse after app restart | HTML route failing + persisted buildId missing/stale | Check `wtrlab_buildid` pref exists; one 404→refresh cycle is normal after site redeploys (fallback path only) |

### 1.7 WTR-Lab version history

| Version | Date | Summary |
|---|---|---|
| 1.1.6 | (upstream) | HTML scraping, 208 tags, proxy-only decrypt (gibberish root cause), dead minc filter, hash always "Chapters" |
| 2.0.0 | (community draft, never shipped) | +882 tags, buildId cache, **harmful cf_options whitelist**, broken `\s` regexes |
| 1.1.7 | 2026-08-26 | Local AES-GCM decrypt + proxy fallback; Turnstile detect/retry/actionable error; 882 tags in 11 groups + Tag Search; 26 filters total; JSON-API catalog with exact hasNext (PAGE_SIZE short-circuit); hash = `count\|updated_at`; b64 strict; delay setting; cf_options kept out. Internal staging names 2.1.0/2.1.1/2.1.2 were consolidated into this single upstream patch. **Merged upstream 2026-09-03** (upstream main == our 1.1.7 byte-identical). |
| 1.1.8 | 2026-09-03 | **Tag Search replaces the 882-chip wall**: `tag_category` picker (All+11) + include/exclude keyword fields (phrase-first matching, word fallback, id passthrough, category scoping, zero-match typo guard); `title_search` text filter (novel finder `text=` — search + filters in one sheet); index refreshed 882→888 (+Blue Archive, Food Wars!, Honkai Star Rails, Monster Hunter, Dragon Raja, System Misunderstanding); Turnstile backoff 2500/5000→600/1800 ms; glossary negative caching; update hash via `api/chapters` (count\|maxUpdated\|checksum, 45 s shared cache, book-page fallback); buildId persisted via `set_preference`. 17 filters, ~140 total options (was ~960). |
| 1.2.0 | 2026-09-10 | Paragraph safety: buildParagraphs splits EVERY body element on embedded newlines (\n, \r\n, \r — the reader renders single \n as a merged soft break; site's own reader splits plain strings on \n); CRLF normalization; safeGsub (escLuaPattern + escLuaReplacement + pcall) on ALL glossary/patch/Web+ gsubs (terms with % or () used to abort the chapter). Tags: 11 tag_pick selects → multi-select checkbox groups (filters[key..'_included'] arrays; legacy string form honored; no Any placeholder). tagSearchResolve: partial keyword includes EVERY match (no ambiguity error; only zero-match raises). Tag discovery: catalog search lists tag matches first (🏷 label — category) → tag 'books' (chapters = tag's novels, most-read first, capped 100, chapter-1 preview URLs; all book functions short-circuit for finder URLs). Web+ mode (webplus translate; glossary per-paragraph, escaped — fixes upstream 1.1.8's raw-JSON gsub that mashed whole chapters into 1-2 paragraphs when a glossary translation contains quotes). |
| 1.1.9 | 2026-09-03 | **Hotfix: catalog latency + tag visibility.** HTML-first catalog fetch (`fetchCatalogPage`: HTML route → `__NEXT_DATA__` pageProps, one request, no buildId; `_next/data` JSON as automatic fallback) — fixes the "10–15 s homepage" class (JSON-route congestion + stale-buildId triple round-trip); **gotcha #30:** HTML `__NEXT_DATA__` wraps props as `props.pageProps`, JSON routes use top-level `pageProps` — `extractNextDataProps` accepts both. 11 `tag_pick_N` "Tags: <category>" dropdowns (888 tags + Any each = 899 options; tags visible again, still no tristate chip wall — 28 filters). `tagSearchResolve` v1.1.9 semantics: exact match → id → single substring → ambiguous (error LISTING matching tag names, display case via `label`+`lower` keys) → `keyword*` wildcard; `tag_pick` merge into `ti=` (validated, deduped, junk skipped). Harness: TEST 2b resolver semantics, TEST 5d/5e merge+ambiguity, MOCK G HTML-first. 59 live + 23 mock + 22 integration. |

---

## Part 2 — Novel543 Plugin (`novel543.lua` v1.0.4)

**PAGE-SCOPED FILTERS (v1.0.4):** each site page has its own filter sidebar, and the plugin mirrors that — the filter sheet shows the **Page picker + only the current page's filters** (bookstack: Type/Status/Category/Tags · booklists: Type/Sort · rankings: Ranking Type/Gender/Ranking Category). The app's filter UI CANNOT show/hide sections dynamically and `SourceCatalogViewModel` fetches `getFilterList()` **once per catalog-screen session** — so the plugin adapts its list to the remembered page (`currentSurface`, set on every Apply, reset by `getCatalogList`). After switching Page inside the sheet, the reduced filter set appears the NEXT time the source screen is opened (back out and re-enter). See gotcha #29.

### 2.1 Architecture map

| Lines (approx) | Section | What it does |
|---|---|---|
| 1–180 | Header + metadata | Changelog + site facts + cf_options warning. `id="novel543"`, `version="1.0.4"` (upstream line), `name="Novel543 Full"` (distribution workaround, see 2.7), `baseUrl=https://www.novel543.com/`, `language="zh"` |
| 182–402 | Preference keys + site taxonomy | `novel543_mode` / `novel543_tlang` / `novel543_tr_chapters`; `CATEGORIES` (13), `TAGS` (**100 entries `{zh, en}`** — zh is the VALUE/URL key, en is the curated display name), `RANK_TYPES` (**3: 閱讀 t=2 / 潛力 t=1 / 風雲 t=8**), `RANK_CATEGORIES` (**40: "default" + 34 gender-matched `<g>-<cid>` entries + 5 Trending sub-ranks `8-800x`**) — ALL `{value, en, zh}`; `STATIC_EN` (free English lookups for 連載/完結/categories) |
| 404–429 | URL helpers | `absUrl`, `hasCJK` (UTF-8 lead-byte test E4–E9), `isShudanUrl` (`/shudan/%d+/`), `isBookPageUrl` (`^host/%d+/?$` — the sampler trigger) |
| 431–471 | `httpGetFollow` | Manual Location-header redirect following (max 4 hops) — REQUIRED because NoveLA's http_get does NOT follow redirects |
| 473–491 | Page cache | `nowMs` (ms-aware clock, pcall-guarded) + `fetchPageCached` (60 s TTL / 12 pages) |
| 493–875 | **Translator core** (+ `flLabel` ~534 + **self-test** ~737) | Cache (4000-entry cap) → `trActive` circuit breaker (3 failed batches → pass-through 10 min, half-opens via `os_time`) → `parseTrArray` (handles BOTH `/t` response shapes) → `trChunkGoogle` (POST, both Google hosts) → `trChunkMyMemory` (per-item GET fallback) → `translateBatch` (≤40 items / ≤3000 chars per chunk) → `translateOne` / `translateVocab` / `translateQueryToZh` (reverse direction, sl=auto); `flLabel(en, zh)` = mode-aware filter labels; `runSelfTest` = ⚡ diagnostics report |
| 877–972 | List parsing | `parseListPage` (pure parsing — items + exact hasNext + booklist `count` from 共N本書), `translateCatalogItems` (batch title translation, applied AFTER caller decorations) |
| 975–1158 | Catalog + filtered browse | `local currentSurface` (line 994 — **the page-scoped-filter state**: set by `getCatalogFiltered` to the applied `browse` value, RESET to "bookstack" by `getCatalogList`); `getCatalogList`; `getCatalogSearch` (reverse-translates non-CJK queries zh-TW first, zh-CN retry); `getCatalogFiltered` routing: bookstack (category path + gender/end params) / tag (`/tags/[boy|girl/]<tag>/`) / ranking (`/ranking/<g>-<t>-<cid>.html` — t from `rank_type` 2/1/8, g from `rank_gender` 0/1, cid from `rank_category`; legacy 8001–8005 rank_type values fold into t=8; mismatched type/category combos fall back safely) / shudan (`/shudan/[boy|girl/][new|fav|commend/]?page=`) |
| 1160–1279 | `getFilterList` | **PAGE-SCOPED (v1.0.4): Page picker (key `browse`, defaultValue = currentSurface) + ONLY the current page's filters** — bookstack: gender/end_status/category/tag (site order 類型·作品狀態·分類·標籤); shudan: gender/shudan_sort; ranking: rank_type (3)/rank_gender (2)/rank_category (40); selftest: picker only. **Labels are MODE-AWARE via `flLabel(en, zh)`**: raw → `English (中文)`, translate → English ONLY (headers + every option, 100 tags included); Latin-only zh (HE, 1V1) collapse to the EN name in both modes. Tag VALUES are ALWAYS the raw zh site tags (URL keys — never translate them) |
| 1281–1386 | Book details | Branches on `isShudanUrl`: books use og: metas + `h1.title`/`.cover img`/`div.intro`; booklists use the same header selectors + `p.meta` (creator + 更新 ts) + book count. Translator mode: title → `"English (原文)"`, desc → translated, genres/status → static map |
| 1388–1487 | Chapter list + hash | Books: `/dir` (`ul.all li a`) with optional batch-translated titles; booklists: the list's novels AS chapters (title + `(score/10)` suffix). Hash: books `update_time|latest_chapter_name`; booklists `count|ts` |
| 1489–1597 | Chapter text | `extractChapterText` (div.content + removals + multi-page `_2.._20.html`); **sampler**: a book-page URL as "chapter" → fetch `/dir` → first chapter → text + bilingual footer telling the reader which original title to search |
| 1599–1639 | Settings schema | Mode (raw/translate), target language (15), translate chapter titles (on/off) |

### 2.2 Site structure (verified live 2026-08-28)

**Every list surface shares the same card markup** — `ul.list li.media` → `div.media-content h3 a` (title), `div.media-left a` (URL), `div.media-left img` (cover), optional `span.score` / `span.author` / `p.desc`. One `parseListPage` parses them all.

**Catalog (bookstack)** — `GET /bookstack/[<category>/]?page=N[&gender=boy|girl][&end=1|2]` (HTML only, 18 items/page):
- 13 category paths: `xuanhuan xiuzhen dushi lishi wangyou kehuan nvpin lingyi tongren junshi xuanyi chuanyue other` — combine freely with gender/end params.
- **Exact hasNext:** `li.next.pagination-link:not(.disabled)` exists → next page. ⚠️ The site **clamps out-of-range pages to the last page** (page=9999 → serves 第20頁 content, HTTP 200) — an items-count heuristic can NEVER detect the end.

**Tags** — `GET /tags/[boy|girl/]<urlencoded-tag>/?page=N` (18 items/page). Gender path goes BEFORE the tag. The 100-tag cloud in the sidebar is identical on `/bookstack/` and every `/tags/` page (single source of truth for `TAGS`). Gender genuinely filters (現代言情 boy-vs-all = ZERO overlap) — but some tags' top page is gender-identical (玄幻 top-18 is all-male), so verify with a romance tag. No category/end params on tag pages.

**Rankings** — `GET /ranking/<g>-<t>-<cid>.html`:
- `g`: 0=女生 1=男生; regular ranks `t`: 2=閱讀榜, 1=潛力榜 (30 items); **風雲榜 special ranks use `t=8` with cid 8001大熱/8002新書/8003完結/8004收藏/8005更新 (40 items)**: `/ranking/<g>-8-<800N>.html`.
- 34 gender-specific cids (see `RANK_CATEGORIES` in the plugin). cid=0 or a cross-gender cid → **301 redirect** to that gender's default (girl 1015 / boy 8) — httpGetFollow handles it.
- No pagination. Some (category, type) combos are legitimately EMPTY (潛力榜×奇幻仙俠 → 200 + 0 items — not a bug).

**Booklists (書單)** — `GET /shudan/[boy|girl/][new|fav|commend/]?page=N` (20 lists/page). ⚠️ **Path order matters: gender BEFORE sort** — `/shudan/boy/fav/` ✓, `/shudan/fav/boy/` = 404. Card adds `p.desc` "共N本書" (parsed into `item.count`). Booklist detail `GET /shudan/<id>/`: `h1.title`, `.cover img`, `div.intro` (often empty), `p.meta` (用戶 creator + 更新 timestamp), books as the same `li.media` cards (with `span.score`).

**Search** — `GET /search/<url-encoded-query>`:
- Site's own JS does `window.location.href = "/search/" + kw` — pattern correct.
- ⚠️ **Cloudflare-protected.** Datacenter IPs get 403-challenged; NoveLA's CF interceptor solves it on real devices. Do NOT add `cf_options`.

**Book page** (`/NNNNNNNNNN/` numeric ID URLs):

| Selector | Field |
|---|---|
| `h1.title` | title |
| `.cover img` | cover |
| `div.intro` (has modifier classes like `is-hidden-mobile` — jsoup class selector still matches) | description |
| `meta[name='og:novel:category']` | genre (e.g. 其他) |
| `meta[name='og:novel:status']` | 連載 / 完結 |
| `meta[name='og:novel:update_time']` | `YYYY-MM-DD HH:MM:SS` |
| `meta[name='og:novel:latest_chapter_name']` | latest chapter title (hash component) |

**Chapter list** — `GET <bookUrl>/dir` → `ul.all li a` (all chapters in one page; 145 for the test book).

**Chapter text** — `<bookUrl>/<chapterID>_<N>.html`:
- Content: `div.content` (class has modifiers, e.g. `content py-5`).
- Remove before text extraction: `div.gadBlock`, `div.adBlock`, `script`, `ins`, `div:has(p:contains(溫馨提示))` (site notice wrapper).
- **Multi-page:** long chapters split as `<file>_2.html`, `_3.html`… linked from the current page; follow up to 20 sub-pages (cap).
- Site notice (stripped, two tiers): structural removal first, then regex fallback `溫馨提示[:：]?\\s*iphone[^!]{0,400}!\\s*`.

### 2.3 Translator mode architecture (v1.2.0, hardened in v1.2.1; distribution fixed in v1.2.2)

**Goal:** a reader who cannot read Chinese can browse/search the whole site. Everything EXCEPT chapter body text is translated (NoveLA's built-in reader translator handles novel content — the plugin must not double-translate).

**Engine — Google free dict endpoint (no API key):**
```
POST https://translate.googleapis.com/translate_a/t?client=dict-chrome-ex&sl=zh-CN&tl=<tl>
     body: q=<urlencoded text>&q=<text>…        (one q per text → one translation per q)
→ ["trans1","trans2",…]                            (explicit sl)
→ [["trans1","zh-CN"],…]                          (sl=auto — nested, includes detected source)

GET  …/translate_a/t?client=dict-chrome-ex&sl=…&tl=…&q=…&q=…   (same shape; q in the URL)
```
- Both hosts work: `translate.googleapis.com` (primary) and `clients5.google.com` (secondary). Verified live 2026-08-28, works even from datacenter IPs — via POST **and** GET (verified with the exact OkHttp header set the app sends).
- ⚠️ The CLASSIC endpoint `translate_a/single?client=gtx` serves a "Sorry…" abuse page to datacenter IPs (fine on residential/mobile — i.e. real devices) — used as the per-item last resort (first 6 of a failed chunk). `parseTrArray` handles ALL `/t` response shapes plus a plain `[["t",…]]` nesting.
- **GET URL-length trap:** an 18-title Chinese page URL-encodes to ~2k chars. The GET fallback therefore SPLITS the chunk into ≤1400-char groups (`trGetChunk`) — a single hard cap would silently skip the fallback for real pages (that was v1.2.0's behavior).
- Reverse direction (search queries): `sl=auto&tl=zh-TW` (site indexes Traditional titles), zh-CN retry if 0 results. Never translate a query that already contains CJK (`hasCJK`).
- `url_encode` produces `+` for spaces — fine for both query params and POST form bodies.
- **Empty-string results are valid**: Google returns `""` for an empty `q`; `parseTrArray` accepts it and the caller maps it back to the original text. (v1.2.0 rejected the WHOLE batch on the first empty — one empty title killed all 18 translations on a page.)

**Fallback provider — MyMemory:** `GET https://api.mymemory.translated.net/get?q=<text>&langpair=zh|<tl>` → `responseData.translatedText` (ignore entries containing `MYMEMORY WARNING` — quota exhaustion marker). Per-item, short texts only (≤300 chars). Returns an array with originals where an item failed — **or NIL when NOTHING was translated**. That nil is load-bearing: a full array of originals makes every failed batch look "successful" and the circuit breaker NEVER trips (v1.2.0's dead-breaker bug — silent all-Chinese UI with no recovery signal).

**Request chain (in order):** POST host1 → POST host2 → GET host1 (split) → GET host2 (split) → MyMemory per-item → gtx-single per-item (first 6). Every step only on the previous step's failure.

**Resilience (browsing must NEVER break):** session cache (original→translation, 4000 entries) → circuit breaker (3 consecutive failed batches → pass-through, half-open after **10 minutes of MILLISECONDS** — see gotcha #22) → **pcall armor on every translator entry point** (`translateBatch`, `translateOne`, `translateVocab`, `translateQueryToZh`, settings readers, the clock): any Lua error degrades to untranslated text, never a failed page. `trFailStreak` resets on any full Google success (MyMemory success alone does not reset it — Google is the healthy path). If `os_time` is missing entirely (old app build) the breaker degrades to a 1-in-16 probe counter instead of crashing.

**Page cache (v1.2.1):** the app calls getBookTitle/Cover/Description/Genres/Status/LastUpdate/ChapterListHash separately — each used to re-download the SAME book page (6-8 round-trips per book open, ×translation latency). `fetchPageCached` serves the burst from ONE fetch (60s TTL, 12 pages, self-disabling when no clock). Chapter text and catalog pages are NEVER cached.

**⚡ Translator Self-Test (v1.2.1, banner in v1.2.2):** Browse filter → "⚡ Translator Self-Test (診斷)" turns the catalog into a live diagnostics report — **line 1 banner (plugin name + version — proves WHICH source is loaded)**, mode + target language, `os_time`/`http_post`/`json_parse` availability, each engine with latency + a sample translation, end-to-end batch, verdict with the next step. Runs in ANY mode (engines are probed directly, so it diagnoses a broken setup without logcat). THIS is the first tool to reach for when a user reports "translator doesn't work" — it shows exactly which step fails on their device. If the report CANNOT be found under the Browse filter at all, the user is on the old repo v1.0.3 (see 2.7).

**What gets translated (mode=translate):** catalog/search/ranking/booklist item titles; book title → `"Translation (原文)"` (original kept for re-search); description (first 4000 chars); genres + status via `STATIC_EN` when tl=en (zero API calls) else API; chapter titles when `novel543_tr_chapters=1` (batched ≤40/request); booklist sampler footers are static bilingual strings (no API). Rank `#N` prefixes and `(N books)` suffixes are appended AFTER translation so Google never mangles them. Chapter BODY text is never translated.

**Settings keys (load-bearing — never rename):** `novel543_mode` (`raw` default | `translate`), `novel543_tlang` (default `en`; 15 codes valid for BOTH Google and MyMemory), `novel543_tr_chapters` (`1` default | `0`).

**UX note (user-facing, not fixable in-plugin):** toggling the mode does NOT auto-refresh an already-loaded catalog — pull-to-refresh after switching. Already-translated pages persist for the session via the translation cache; already-shown raw pages do not re-translate in place.

### 2.4 Cloudflare profile (IMPORTANT — different from WTR-Lab)

- The site sits behind Cloudflare with **TLS-fingerprint-sensitive rules**: Java's `HttpURLConnection` fingerprint gets 403-challenged on ALL paths, while curl/Python/OkHttp pass. The real NoveLA app uses **OkHttp** (accepted fingerprint) → the plugin works in the app.
- `/search/` is challenged more aggressively (403 even from curl on datacenter IPs).
- **Consequence for testing:** the Java test harness must route HTTP through curl (`ProcessBuilder`) — already implemented in `Novel543Test.java`. Never "fix" a CF 403 in the plugin with `cf_options = { whitelist = true }` — that disables NoveLA's WebView bypass ladder for this host.
- If the site ever starts challenging OkHttp too (symptom: users report "Just a moment…" empty pages), that's when the app's CF interceptor + manual WebView flow matters — nothing to change in the plugin.

### 2.5 Novel543 failure modes playbook

| Symptom | Likely cause | Fix |
|---|---|---|
| Catalog empty | `ul.list li.media` structure changed | Re-inspect `/bookstack/` HTML; update `parseListPage` selectors (fixes ALL surfaces at once — they share markup) |
| Catalog loops forever / repeats last page | hasNext selector broke (pagination markup changed) | Verify `li.next.pagination-link` classes; remember the site CLAMPS out-of-range pages — never use items-count heuristics |
| Search empty from the app | CF challenge escalated beyond auto-bypass | User solves once in integrated browser; otherwise verify `/search/` pattern in `/min/main.20.js` |
| English search finds nothing in Translator mode | Query translation broken OR site search indexes different variant | Test `POST …/translate_a/t?client=dict-chrome-ex&sl=auto&tl=zh-TW` with the query; check the zh-CN retry path |
| Ranking browse empty | URL shape changed (301 not followed / new layout) | curl the exact `/ranking/<g>-<t>-<cid>.html`; check `httpGetFollow` still sees the `location` header (response headers are lowercased Lua arrays) |
| Ranking shows 0 items for a category | Legitimately EMPTY (category × type) combo on the site (e.g. 潛力榜×奇幻仙俠) | Not a bug — verify by curling the page (200 + no li.media) |
| Booklist browse empty | `/shudan/` path scheme changed (gender/sort order!) | curl `/shudan/boy/fav/` — gender must come BEFORE sort; re-verify sort slugs new/fav/commend |
| Booklist opens but no "chapters" | Booklist detail markup changed | curl `/shudan/<id>/`; books are `ul.list li.media` in the `section.mt-3` — update `getChapterList` shudan branch |
| Sampler returns intro instead of chapter 1 | `/dir` fetch or `ul.all li a` broke, OR book removed (404) | curl `<book>/dir`; the intro fallback is by design for dead books |
| Translations suddenly all-original (UI back to Chinese) | Circuit breaker tripped (3 failed batches) or Google endpoint changed | Run the ⚡ Translator Self-Test; watch for `translator disabled for 10 min` in log_info; curl the dict endpoint; check response shape still parses (both forms in `parseTrArray`) |
| **"Translator doesn't work" (user report)** | Many causes — DON'T guess | **FIRST: confirm they are on the right SOURCE** (see 2.7 — the #1 cause is the old repo v1.0.3 being browsed instead of the imported "Novel543 Full"). Then have the user run Browse → ⚡ Translator Self-Test and read the report: banner line (plugin version — proves the right source), mode line (was the setting applied?), os_time/http_post lines (app build), engine lines with latency (network/region), e2e line (pipeline). The verdict line states the next step. Also confirm they PULLED-TO-REFRESH after toggling the mode |
| **"Filters don't show up / no filters button" (user report)** | The browsed source's loaded Lua has NO `getFilterList` — i.e. they are browsing the OLD repo v1.0.3, not the imported plugin (see 2.7) | The funnel icon appears ONLY for sources whose loaded script defines `getFilterList` (LuaSourceAdapter.kt:50 → FilterableCatalog → SourceCatalogScreen `state.hasFilters`). The fix is on-device installation, not code: remove/disable the old repo "Novel543", import the current file, browse the "Novel543 Full" entry |
| Titles stay Chinese right after toggling the mode | Already-loaded catalog page was not re-fetched | Pull-to-refresh — the app does not auto-refresh the catalog on a settings change |
| Translations slow on first book open | Chapter-title batch (145 titles ≈ 4 POSTs) + no cache yet | By design — session cache + 60s page cache kick in; user can turn off `Translate Chapter Titles` |
| Chapter list empty | `/dir` shape changed | curl `<book>/dir`, check `ul.all li a` |
| Chapter text empty | `div.content` renamed | curl a chapter page, update `extractPage` selector + removal list |
| Site notice reappears in text | Notice wording/markup changed | Update `div:has(p:contains(溫馨提示))` selector and/or the `stripSiteNotice` regex (they're adjacent in the file) |
| Update checks never fire | og: meta tags renamed | curl book page, check `og:novel:update_time` / `og:novel:latest_chapter_name` metas |
| Filters do nothing | `gender`/`end`/category/tag params renamed | Verify with curl: `/bookstack/xuanhuan/?gender=girl&end=2` changes results; `/tags/boy/<tag>/` differs from `/tags/<tag>/` (use 現代言情 — some tags are gender-identical!) |

### 2.6 Novel543 version history

| Version | Date | Summary |
|---|---|---|
| 1.0.3 | (upstream) | Basic catalog/search/book/chapters; over-fetching hasNext (`#items > 0` — site clamps pages so it can never detect the end); weak date-only hash; no filters/genres; site notice not stripped |
| 1.1.0 | 2026-08-28 | +gender/end filters; +getBookGenres; exact hasNext from pagination widget; hash = `update_time\|latest_chapter_name`; site notice stripped (structural + regex); cf_options warning documented |
| 1.2.0 | 2026-08-28 | **Full site filters**: browse surface (bookstack/ranking/shudan), 13 categories, 100 tags (gender paths), 7 rank types × 34 rank categories (special ranks t=8, 40 entries, #N prefixes), 3 booklist sorts; **manual redirect following** (http_get doesn't follow 301s); **booklists as books** (novels as chapters, score suffixes, chapter-1 sampler with bilingual footer, `count\|ts` hash); **Translator mode** (Google dict-chrome-ex POST batching + MyMemory fallback + 4000-entry cache + circuit breaker; reverse-translated search queries; static EN vocab; 15 target languages; chapter-title toggle); getSettingsSchema |
| 1.2.1 | 2026-08-28 | **Hotfix — "Translator doesn't work" reports**: pcall armor on ALL translator entry points (a Lua error can never break a page again); os_time **milliseconds** bug fixed (breaker re-armed after 0.6s instead of 10 min; crash on builds without os_time); GET fallback for the Google endpoint with URL-length SPLITTING (v1.2.0's 1500-char cap silently skipped the fallback for real 18-title pages); MyMemory now returns nil when nothing was translated — the circuit breaker was dead code in v1.2.0 (silent all-Chinese UI, no recovery); empty-string results no longer poison a whole batch; 60s page cache (book open: 1 fetch instead of 6-8); **⚡ Translator Self-Test** diagnostics surface; gtx-single per-item last resort (works from residential IPs = real devices). 139 live tests incl. fault-injection (POST blocked, engines dead, os_time missing) |
| 1.2.2 | 2026-08-29 | **Hotfix — "Filters don't show up / no filters button" reports**. ROOT CAUSE was distribution, not code: the app's built-in extension repository ships v1.0.3 (no getFilterList, no getSettingsSchema), sources resolve BY BASE URL (`Scraper.getCompatibleSourceCatalog` returns the FIRST match), and two identically-named "Novel543" sources are indistinguishable — so the app kept opening the old repo v1.0.3 even after importing v1.2.x. Fix: **RENAMED the plugin to "Novel543 Full"** (distinct in the source list; imports cleanly — re-importing under the old name is rejected with "Extension Novel543 already exists locally"); self-test banner line 1 = "⚡ Plugin — Novel543 Full v1.2.2 — …you are on the RIGHT source"; single `VERSION` constant. All v1.2.1 behavior unchanged. 141 live tests (139 + name + banner checks; TEST 40 latin-count relaxed to ≤4 for per-title cache replays after live content drift) |
| 1.0.4 | 2026-08-29 | **Upstream PR release — version realigned to the upstream line (1.0.3 → 1.0.4; dev builds 1.1.0–1.2.2 superseded)**. (1) **PAGE-SCOPED FILTERS: the filter sheet mirrors the browsed page** — Page picker + ONLY that page's filters (bookstack: Type/Status/Category/Tags in site order · booklists: Type/Sort · rankings: Ranking Type (閱讀/潛力/風雲) + Gender (女生/男生) + Ranking Category (default + 34 + 5 Trending sub-ranks)); previously all 8 sections were stacked into one sheet with "Category — Bookstack only" clutter. `currentSurface` is set by `getCatalogFiltered` and reset by `getCatalogList`; the sheet picks up a page switch the next time the source screen is opened (the ViewModel fetches getFilterList once per screen session — see gotcha #29). Ranking taxonomy rebuilt: `RANK_TYPES` 3 entries (t=2/1/8), `rank_gender` NEW key (0/1), legacy rank_type 8001–8005 fold into t=8, mismatched type/category combos fall back safely, stale foreign keys ignored. (2) **All 100 tag filter options now carry curated English names** (穿越→Transmigration, 豪門總裁→Wealthy CEO, 打臉→Face-Slapping…) — the tag dropdown was raw Chinese only. (3) **Mode-aware filter labels via `flLabel(en, zh)`**: raw mode keeps bilingual `English (中文)`; Translator mode shows English ONLY for every filter label (section headers + all options, tags included) — labels rebuild when the source screen is (re)opened. Taxonomy tables restructured to `{value, en, zh}`; Latin-only tags (HE, 1V1) collapse to their EN name in both modes; tag VALUES unchanged (URL keys — saved filter state keeps working). (4) `download/novel543_pull_request.md` written for the external-sources PR (merge note: revert `name` to "Novel543" upstream). 196 live tests (+39: TEST 2 rebuilt for page-scoping, NEW TEST 2d surface-switching on every surface incl. stale-key tolerance + reset, ranking-URL-builder fallback matrix, translate-mode CJK scans per surface, self-test picker-only sheet) |
| 1.0.5 | 2026-09-18 | **Poster fix + upstream name sync.** Covers via wsrv.nl image proxy (all four cover surfaces: catalog cards, book pages, booklist headers) with a "Cover Images" setting (proxy default / direct); name "Novel543 Full" → "Novel543" matching the upstream repo rename; self-test banner follows. Same STATIC_EXTENSIONS root cause as the other plugins. Tests 197/197 (+1 env skip: /search/ CF-blocked from datacenter). |

### 2.7 Distribution & installation (READ before shipping ANY update to a user)

**How the app loads Lua sources** (verified in Kotlin):
1. Extensions are stored as files `luaDir/<storageId>.lua`; repo installs use the repo id (`novel543`), local imports get `local_novel543_XXXXX` BAKED into the script by `withLocalId` (ExtensionsManagerViewModel.kt:393 — it rewrites the `id =` line).
2. `createLuaSourceAdapter` picks the adapter by what the loaded script defines: `getFilterList` → FilterableCatalog (funnel icon in the source's top bar), `getSettingsSchema` → Configurable (gear icon on the source row in the Catalog list). **No function = no icon. The old repo v1.0.3 has neither.**
3. The Catalog list navigates BY BASE URL: `sourceCatalog(sourceBaseUrl)` → `Scraper.getCompatibleSourceCatalog` finds the FIRST source whose baseUrl matches (Scraper.kt:80). Two Novel543 sources installed → the tapped entry may NOT be the opened source!

**Consequences (the traps):**
- The repo "Novel543" v1.0.3 + an imported "Novel543" v1.2.x collide on baseUrl — user taps "Novel543", app may open v1.0.3 → "no filters button, translator doesn't work".
- Re-importing an updated file under the same name is BLOCKED ("Extension Novel543 already exists locally") because a fresh import gets a NEW random storage id and the old-name check fires.
- Updating via the in-app Lua editor (pencil icon on a LOCAL extension only — repo extensions have no editable code) keeps the same storage id, but pasted code with `id = "novel543"` changes the script-declared id… the app keys sources by storage id when loading, so it still loads, but keep the baked `local_…` id line when pasting if you can.

**Ship checklist for user-facing updates:**
1. Keep the plugin `name` DISTINCT from any repo extension of the same source (v1.2.2: "Novel543 Full").
2. Tell the user to UNINSTALL or DISABLE the old repo "Novel543" in the Extensions screen FIRST.
3. Then import the .lua (Extensions screen → "Import Lua" file picker, or paste into the Lua editor).
4. **Updating an ALREADY-installed local copy:** re-importing under the same name is REJECTED — use the in-app Lua editor instead (extension row → Edit Lua → select all → paste the new file → Save; `saveLuaEditor` writes under the SAME storage id and refreshes name/version from the pasted code). Keep the baked `local_…` id line when pasting if you can — the app loads by storage id either way.
5. Verify in the Catalog list: the "Novel543 Full" row shows the ⚙ gear icon (= Configurable = settings present). No gear = old version.
6. Settings → Mode = Translator → close → open the source → PULL-TO-REFRESH (the catalog does not auto-refresh after a settings change; same for the filter sheet — reopen it to pick up mode-aware labels).
7. Still Chinese? Funnel → Browse → ⚡ Translator Self-Test — line 1 proves the plugin version; the verdict line states the failing step.

---

## Part 3 — NoveLA Plugin API Cheat Sheet (verified against app Kotlin source)

**Required table fields:** `id, name, version, baseUrl, language, icon` (+ optional `description, charset, content_type, cf_options, getUserAgentPreset()`).

**HTTP:**
- `http_get(url[, {headers=…, charset=…}])`, `http_post(url, body[, config])` → `{success, body, code, headers={lowername={vals}}}`.
- ⚠️ **`http_get` does NOT follow redirects** (`NetworkClient.call(builder)` uses the default `followRedirects=false` — verified in Kotlin). 3xx → `success=false` + `code` + `headers.location[1]` (lowercased key, Lua array value). Follow manually if needed (see novel543's `httpGetFollow`).
- No timeout opt, no cookies field. **2 s TTL cache on successful GETs** (multiple `getBook*` calls hitting the same page are deduped). SSRF guard. All requests go through shared OkHttp + CF interceptor + WebView cookie jar (`cf_clearance` shared automatically).
- No `http_head`/`http_request`. No default User-Agent — pass one via config `headers` when an endpoint cares (e.g. Google translate).

**Filters:** `getFilterList()` → `{{type, key, label, defaultValue?, options={{value,label}…}, defaultAscending?, multiselect?}}`; types `select | checkbox | tristate | switch | text | sort`.
Marshalled into `getCatalogFiltered(index, filters)`:
- select/text → `filters[key]` (string; omitted when empty)
- tristate → `filters[key.."_included"]` / `filters[key.."_excluded"]` (1-based Lua arrays; omitted when empty)
- switch → `"true"/"false"` STRING
- sort → `filters[key]` + `filters[key.."_ascending"]`

**Catalog:** `getCatalogList/Search/Filtered(index, …)` → `{items={{title, url, cover, rating?}}, hasNext}`. **`index` is 0-based.**

**Book getters:** `getBookTitle/CoverImageUrl/Description/Genres/Rating/Status/LastUpdate(bookUrl)`, `getChapterListHash(bookUrl)`, `getChapterList(bookUrl)` → `{{title, url}}`. `getBookRating` + `getSettingsSchema` are OPTIONAL (null defaults exist in SourceInterface.kt / LuaSettingsSupport.kt).

**`getChapterText(html, chapterUrl)`:** `html` = full downloaded chapter page HTML, `chapterUrl` = final URL. App retries download 4×. **Blank return → app falls back to Readability heuristics (bad — avoid)**. `error("msg")` → shown to the user (LuaJ prefixes `script:<line>` — unavoidable). Chapter validation: body <100 chars or containing CF markers → reader shows "Content error".

**Utils:** `html_select/_first/html_attr/html_text/html_parse/html_remove` (jsoup-based — supports `:not()`, `:has()`, `:contains()`), `string_trim/starts_with/ends_with/split/normalize/clean`, `regex_match` (**array of full matches**, Java regex syntax — in Lua strings escape backslashes: `\\s`), `regex_replace`, `json_parse/json_stringify` (Gson; numbers arrive as Lua doubles; **top-level JSON arrays → 1-based Lua tables**), `url_encode` (spaces → `+`), `url_resolve`, `sleep(ms)`, `os_time()` (**MILLISECONDS** — `System.currentTimeMillis()`, see gotcha #22; the ONLY clock available to plugins), `log_info/log_error`, `get_preference(key)` (**returns `""` never nil** when unset), `set_preference`, `base64_encode/decode` (⚠️ NOT binary-safe), `get_cookies/set_cookies`, `aes_decrypt` (AES-CBC only — not GCM).

**Sandbox:** LuaJ 3.0.1 — no `io`/`os.execute`/`require`/`load`/`package`/`debug`/`luajava`; `bit32` IS available; script load timeout 10 s (load only, not per-call); result table gets `__index=globals` metatable; plugins CANNOT drive the WebView (no webview functions exist).

**cf_options:** `{ whitelist = true }` disables ALL CF/Turnstile auto-bypass for the host (NEVER use for these two sites). `{ whitelist = false, ignore_markers = {…} }` is the legitimate false-positive suppression — neither site needs it.

---

## Part 4 — Test Harness

Location: `/home/z/my-project/testenv/` (jars in `lib/`: luaj-jse-3.0.1, jsoup-1.17.2, gson-2.10.1). Copied to `download/test-harness/` for shipping.

- **Faithful emulation:** sandbox globals exactly as NoveLA creates them (verified against `LuaSourceLoader.kt`), element tables with lazy metatables, Gson JSON semantics, Java regex, 2s GET cache equivalent behavior where it matters.
- `LuaTest.java` — WTR-Lab suite (27 live + 15 mock + bit32/arithmetic-fallback variants). Mock mode replays real captured payloads (`research/*.json`).
- `Novel543Test.java` — Novel543 suite (**157 live tests**, v1.0.4): filters/schema, **mode-aware filter-label checks in BOTH modes (TEST 2b/2c: bilingual raw / zero-CJK translate / tag values stable across the mode toggle)**, all browse surfaces, redirect following, booklist-as-book, sampler, **live Translator-mode checks against the real Google dict endpoint** (reachable from datacenter IPs), and **fault injection** — `blockPost` / `blockMyMemory` / `blockTranslate` / `cannedTranslate("EMPTY_LAST")` / `clockOffsetMs` / per-URL fetch counting — proving the GET fallback, the ms-accurate circuit breaker, the page cache (7 metadata calls → 1 fetch), batch survival on empty-string results, and no-crash behavior when `os_time` is missing entirely. HTTP routed through **curl with `-D -` header capture** because novel543.com's Cloudflare challenges Java's TLS fingerprint (see 2.4). `json_parse` is a REAL Gson→Lua bridge; `os_time` returns MILLISECONDS exactly like the app (the old seconds-stub masked the breaker bug — gotcha #22). If you need to change the test book: `java -cp ".:lib/*" Novel543Test <lua> <bookUrl>`.
- ⚠️ **javac is NOT installed** — compile with `java -jar lib/ecj.jar -source 19 -target 19 -cp "lib/luaj-jse-3.0.1.jar:lib/jsoup-1.17.2.jar:lib/gson-2.10.1.jar" -d . <File>.java`.
- `SyntaxCheck.java` — compiles + verifies required functions + metadata + cf_options absence.
- **When the site changes:** re-run the suites FIRST to get a precise failure list, fix, re-run until green. Add a new test case for whatever broke so the regression is permanently covered.

---

## Part 5 — Universal "Site Updated, Plugin Broke" Triage Workflow

1. **Reproduce precisely.** Run the relevant test suite. Note exactly which functions fail (catalog only? chapter text only? specific mode?).
2. **Check site availability & shape manually** (curl with a browser UA; for novel543 remember Java-native HTTP gets CF-challenged — use curl):
   - Catalog URL still 200? (buildId/API path/HTML structure)
   - Book page still has the expected selectors/metas?
   - Chapter list endpoint/`/dir` still returns chapters?
   - Chapter body endpoint still returns the same shape (WTR: `arr:`/table/`str:`; N543: `div.content`)?
3. **Classify the break:**
   - *Transport/CF* (403/challenge): usually nothing to change in the plugin — verify with curl; if the site now blocks OkHttp too, users must solve challenges via the integrated browser (app-side flow). NEVER add `cf_options = {whitelist = true}`.
   - *Endpoint moved/renamed*: update the URL builders (WTR §1.2, N543 §2.2).
   - *Response shape changed*: update parsing (`pagePropsToResult`, `parseListPage`, `getChapterList`, `extractPage`, …).
   - *Crypto changed* (WTR only): key rotated or format changed → update `GCM_KEY` / payload parser (§1.3).
   - *Markup changed*: update selectors; prefer og: metas and JSON over CSS selectors wherever available (they're stabler).
   - *Params changed*: re-verify each filter param changes result counts; update `getCatalogFiltered`.
4. **Fix, then extend the test suite** with a case covering the new breakage pattern.
5. **Bump the version** in metadata AND the header changelog comment (WTR keeps upstream's 1.1.x scheme — next would be 1.1.8; N543 now also follows the UPSTREAM line — next is 1.0.5).
6. **Run the full suite** (both bit32 variants for WTR) until green.
7. **Update this file** (Part 1.2/2.2 site facts, failure-mode tables, version history) so the next session starts accurate.

---

## Part 6 — Gotchas Library (hard-won lessons; do not relearn these)

1. **Lua string escaping for Java regex:** in a Lua string, `\\s` → regex `\s` (correct); `\s` → literal `s` (silent dead pattern). The community v2.0.0 draft shipped dead patterns this way. ALWAYS double-check backslashes in `regex_*` patterns.
2. **`count` from wtr-lab's `_next/data` is a JSON STRING** — `tonumber()` before comparing, or hasNext is garbage.
3. **wtr-lab hasNext needs the PAGE_SIZE short-circuit** — `page * #items < count` mis-counts on partial last pages (count=12, page2=2 items → 2*2<12 → over-fetches an empty page 3).
4. **novel543 clamps out-of-range pages to the last page** (HTTP 200, full content) — items-count heuristics can NEVER detect the end. Use the pagination widget's next-link state.
5. **Host `base64_decode` corrupts binary** (UTF-8 String conversion) — any binary decode (AES IV/ciphertext) needs the plugin's own byte-safe decoder.
6. **`get_preference` returns `""` (never nil)** when unset — test with `v ~= ""`.
7. **`cf_options = { whitelist = true }` disables CF recovery** — the single most harmful line ever shipped in a draft for either site. Both plugins carry an explicit warning comment; keep it.
8. **`.json` URLs bypass NoveLA's CF interceptor** (static-extension shortcut) — WTR's terms endpoint can fail silently under challenge; the plugin already falls back gracefully.
9. **novel543's Cloudflare fingerprints TLS stacks** — Java HttpURLConnection is challenged, curl/Python/OkHttp pass. Test harnesses for that site MUST route through curl (already done). Symptom to remember: 403 + "Just a moment…" + `Cf-Mitigated: challenge` header.
10. **WTR's Turnstile limit is per-backend-instance and intermittent** — retrying (2.5s/5s) often succeeds; it is NOT a hard block. Don't surface an error before retries are exhausted.
11. **Both plugins' settings keys are load-bearing:** `wtrlab_mode` must never be renamed (existing user AI/Raw choice survives upgrades through it).
12. **jsoup class selectors match ANY of the classes** — `div.intro` still matches `<div class="intro is-hidden-mobile">`. Don't "fix" selectors that still work just because the class attribute grew.
13. **Chapter text <100 chars = "Content error" in the app** — never return short/blank strings; raise `error("…")` with an actionable message instead.
14. **The wtrlab `getChapterListHash` must include the updated_at timestamp** — count-only hashes miss same-count retranslations; 1.1.6 returned the literal string "Chapters" (both label and number spans carry `translate="no"`, so `html_select_first` returned the label) and update detection NEVER worked.
15. **Element tables in NoveLA are lazy** — `el.text`/`el.html`/`el.href`/`el.src` are computed on access; there's no `.class` field guaranteed on all builds — use `html_attr(el.html, "selector", "attr")` or CSS pseudo-selectors (`:not()`, `:has()`, `:contains()`) instead of reading `.class` directly. (The test harness exposes `.class`, but prefer the portable forms in plugin code.)
16. **`http_get` does NOT follow redirects** — `NetworkClient.call()` defaults to `followRedirects=false` (Kotlin-verified). A 301 (e.g. `/ranking.html`, mismatched ranking cid) returns `success=false, code=301` with the target in `headers.location[1]` (lowercase key, array value). novel543's `httpGetFollow` follows up to 4 hops — reuse it anywhere a surface may redirect.
17. **Google translate endpoints are NOT equal:** `translate_a/single?client=gtx` (the famous one) serves a "Sorry…" abuse page to datacenter IPs, while `translate_a/t?client=dict-chrome-ex` (GET or POST) works from datacenter AND residential IPs. POST with repeated `q=` params batches 1:1 (`["t1","t2",…]`); `sl=auto` changes the shape to `[["t","src"],…]` — parse both. Plugin `parseTrArray` + both host fallbacks (translate.googleapis.com → clients5.google.com) → MyMemory as last resort.
18. **novel543 shudan path order matters** — gender BEFORE sort: `/shudan/boy/fav/` ✓ but `/shudan/fav/boy/` = 404. Ranking paths have no such trap but cid=0/cross-gender cid 301-redirects.
19. **novel543 ranking special ranks use `t=8`** — `/ranking/<g>-8-<800N>.html` (40 entries), NOT `g-<800N>-<cid>`. Regular ranks: `g-<1|2>-<cid>.html` (30 entries). Some (category × type) combos are legitimately EMPTY (潛力榜×奇幻仙俠 → 200 + 0 items) — don't "fix" empty results without curling the URL first.
20. **novel543 tag pages support gender paths** (`/tags/boy/<tag>/`) and it genuinely filters — but verify with 現代言情 (boy vs all = zero overlap); 玄幻's top-18 happens to be all-male so the filtered and unfiltered pages look identical.
21. **novel543 settings keys are load-bearing** — `novel543_mode` / `novel543_tlang` / `novel543_tr_chapters` must never be renamed (user choices survive upgrades through them), same as `wtrlab_mode`.
22. **`os_time()` returns MILLISECONDS, not seconds** (`LuaSourceLoader.kt`: `System.currentTimeMillis().toDouble()`). v1.2.0's breaker compared it against `600` "seconds" → re-armed after 0.6 s; and on app builds without `os_time` the breaker-trip line CRASHED the page ("attempt to call a nil value") — after 3 failed batches, i.e. exactly when things were already broken. The harness originally stubbed SECONDS, which MASKED the bug (all 116 tests passed against broken code) — the stub now returns ms like the app. Lesson: emulate host functions EXACTLY, units included.
23. **A fallback that always "succeeds" kills your circuit breaker** — `trChunkMyMemory` returned a full-length array of originals on failure, so every failed batch looked like a successful fallback: `trFailStreak` never incremented, the breaker never tripped, and the UI silently stayed Chinese forever. Failure must be distinguishable from success (nil vs array), or recovery logic is dead code that green tests can't catch (the old tests asserted items-come-back, not WHICH path served them).
24. **URL length breaks GET fallbacks silently** — 18 Chinese titles ≈ 2k URL-encoded chars. v1.2.0's `#qstr <= 1500` guard meant the GET fallback NEVER ran for real catalog pages (only short 1-2 item calls). Fixed by splitting batches into ≤1400-char groups (`trGetChunk`). When adding a URL-length guard, test with REAL payload sizes, not toy examples.
25. **NoveLA calls every book metadata getter separately** — getBookTitle/Cover/Description/Genres/Status/LastUpdate/ChapterListHash = up to 8 Lua calls per book open, each free to re-fetch the page; the per-source mutex serializes them, so latency ADDS UP (6-8 × RTT + translation). A 60s plugin-level page cache cut book-open to 1 fetch. Chapter text must NEVER come from such a cache.
26. **The catalog does not auto-refresh after a settings change** — toggling Translator mode changes nothing on an already-rendered screen until pull-to-refresh. This looks EXACTLY like "the feature doesn't work". Mode-like settings must tell the user to refresh (novel543's self-test verdict line does).
27. **THE #1 "feature missing" cause is the app resolving the WRONG source, not the code** (cost: one full debugging session, 2026-08-29). NoveLA's Catalog navigates by BASE URL (`Scraper.getCompatibleSourceCatalog` → FIRST match); the extension repository's novel543 v1.0.3 and an imported v1.2.x share `https://www.novel543.com/`, so the app can open v1.0.3 no matter which entry was tapped — and both entries are named "Novel543", so the user cannot tell them apart. Symptoms: "no filters button", "no settings gear", "translator doesn't work" — ALL at once, because the browsed script has no `getFilterList`/`getSettingsSchema` at all. Prevention: (a) ship user-imported plugins under a DISTINCT name (v1.2.2: "Novel543 Full"); (b) tell users to disable/uninstall the repo version before importing; (c) put a version banner in any in-app diagnostics surface so "which source am I on?" is answerable in one glance. Also: re-importing an updated file under the same name is REJECTED ("Extension … already exists locally") — a fresh import gets a new random `local_…` storage id, and the duplicate-NAME check fires before the update path is ever considered. To UPDATE an installed local copy, use the in-app Lua editor (same storage id, no rejection).
28. **Filter labels are MODE-AWARE and rebuilt when the source screen is (re)opened** (v1.0.4): `flLabel(en, zh)` renders `English (中文)` in raw mode and English only in Translator mode; the app fetches `getFilterList()` ONCE per catalog-screen session (SourceCatalogViewModel init — the ADAPTER has no cache, but the VIEWMODEL caches the list for the screen's lifetime), so the language switch appears after leaving the catalog and re-entering the source. ⚠️ An earlier note here (and in the 1.0.4 changelog) wrongly claimed the app re-calls getFilterList on every sheet open — do NOT rely on that. TWO invariants when editing taxonomy tables: (a) tag/category VALUES must stay the raw Chinese site tokens — they are URL-encoded into `/tags/` URLs AND persist in the user's saved filter state; translating a value silently breaks browsing AND saved filters; (b) every `{value, en, zh}` entry needs both names — a missing `en` shows `nil`-containing labels in Translator mode. Latin-only zh values (HE, 1V1) collapse to the EN name in both modes (never emit "HE (HE)").
29. **PAGE-SCOPED FILTERS — the sheet must mirror the browsed page** (v1.0.4): the site's pages each have their OWN filter sidebar (bookstack: 類型/作品狀態/分類/標籤 · shudan: 類型 + sort · ranking: 閱讀/潛力/風雲 + 女生/男生 + per-type categories), and the app's filter sheet CANNOT show/hide sections dynamically (FilterBottomSheet renders whatever the list contains). The plugin therefore returns the Page picker + only `currentSurface`'s filters, where `currentSurface` is written by `getCatalogFiltered` (the applied `browse` value) and reset to "bookstack" by `getCatalogList` (fresh unfiltered session). Consequences: (a) after switching Page inside the sheet, the catalog updates instantly but the reduced filter set shows the NEXT time the source screen is opened — tell users "back out and re-enter"; (b) `getCatalogFiltered` MUST tolerate STALE foreign keys (an old sheet can still pass category/tag/gender while browsing=ranking) — every branch ignores keys it doesn't own; (c) the ranking branch folds legacy rank_type values 8001–8005 into t=8 and falls back safely on mismatched type/category combos (Trending sub-rank ↔ reading category); (d) NEW key `rank_gender` (0/1) — gender for rankings no longer rides inside the rank_category value (the (F)/(M) category entries still carry their own gender, like the site sidebar).
30. **wtr-lab `__NEXT_DATA__` props shape differs BY ROUTE** (v1.1.9, cost: the HTML-first fix silently never worked): HTML pages (`/en/novel-list`, `/en/novel-finder`) embed `{"props":{"pageProps":{…}},"buildId":…}` — the STANDARD Next.js `__NEXT_DATA__` wrapper — while the `_next/data/{buildId}/*.json` routes return `{"pageProps":{…}}` at the TOP level. An extractor that only checks top-level `data.pageProps` "works" against JSON-route mocks but returns nil for every real HTML page, so the plugin logs "HTML route failed, falling back" on EVERY catalog call and eats a wasted 232 KB request. `extractNextDataProps` must accept BOTH shapes (top-level first, then `data.props.pageProps`). When testing extraction logic, mock the REAL structure — a mock written from the same wrong assumption as the code will pass while the code is broken (the first MOCK G did exactly this). Also: `research/novel-finder.html` (the older snapshot) has the same nested shape — check saved snapshots before concluding the site changed.
31. **Upstream divergence + the "mashup paragraph" root cause** (v1.2.0): upstream `HnDK0/external-sources` main = our 1.1.7 + THEIR own 1.1.8 (Web+ mode). The app AUTO-UPDATES repo extensions — the user's installed copy can silently become upstream 1.1.8 even after importing ours (the reverse can also happen). When a wtrlab regression report arrives, FIRST check which copy/version the device actually loads. Upstream 1.1.8's Web+ applies the book glossary with `resolvedBody:gsub(original, translation)` over the RAW decrypted JSON string: a translation containing `"`/`\` breaks the JSON → `json_parse` nil → the else-branch splits on `\n` (JSON has none) → **the whole chapter renders as ONE mashup paragraph** (a `","` inside a translation splits it into two). Pattern-magic chars in `original` (`%`, `(`…) instead throw `malformed pattern` and fail the chapter outright. Our v1.2.0 applies Web+ glossary per-paragraph on PARSED text through safeGsub (escaped + pcall) — immune by construction.
32. **Checkbox filter marshalling** (LuaFilterSupport.kt, Kotlin-verified): `type = "checkbox"` groups arrive in Lua as `filters[key .. "_included"]` = 1-based Lua array of the selected VALUES (there is NO `_excluded` for checkbox — exclusions need a separate mechanism, e.g. the tag_search_exc text field). `multiselect` defaults to TRUE; `multiselect=false` enforces single-choice. `select` has NO multi-select form at all. The app sorts checkbox chips alphabetically by label (case-insensitive). Saved filter state from a version that used the same key as a select still arrives in the OLD form — read both (`filters[key]` string + `filters[key.."_included"]` table) during migrations.
33. **Lua lexical scoping for helper blocks**: a `local` table/function defined later in the file is INVISIBLE to functions defined earlier — those resolve the name as a nil global at call time → "attempt to index a nil value" on the FIRST call (syntax check passes, mock tests that don't exercise the caller pass too). The v1.2.0 tag-book helpers (TAG_CATEGORY_NAMES, parseTagBookUrl, …) must stay BEFORE the Catalog section (getCatalogSearch uses them), not grouped with Book details.
34. **`string.find(s, pattern, 1, true)` is a PLAIN search** — pattern escapes inside the needle are literal text: `"novel%-finder"` NEVER matches "novel-finder" (bit me in parseTagBookUrl; caught by MOCK TEST J). Pattern escapes (`%-`) only apply in pattern mode (plain=nil/false).
35. **Image URLs are exempt from the CF bypass** (`STATIC_EXTENSIONS`: jpg/png/webp/json/txt/lua…) — a Cloudflare-challenged cover returns the challenge HTML to the image loader and the poster breaks with no recovery (auto-retry re-requests the same URL). The fix is the **wsrv.nl proxy pattern** (all three plugins since 2026-09-18): `https://wsrv.nl/?url=<url-encoded cover>&w=450&we&output=jpg&q=80` — the host is in the engine's `CLOUDFLARE_WHITELIST` and fetches server-side. Never "fix" posters by adding the image host to a bypass — the bypass never runs for these extensions.
36. **EmpireCMS searchids are SITE-SPECIFIC** (wuxiabox): a `searchid` is a row in THAT site's search table. Falling back to the mirror for a searchid page serves an unrelated/empty result — which the app treats as end-of-pagination (gotcha: `PagedListIteratorState` CONSUMES on empty OR duplicate pages). Same class of bug as tag ids: only slug-keyed and keyword-keyed URLs are portable between wuxiabox and wuxiaspot.
37. **Lua `.-` / `.*` cannot cross newlines** — a lazy pattern anchored on `<ul class="pagination">` silently fails when the site puts a newline before the 总数 marker (wuxiabox `listTotal` was dead code this way for two releases). Anchor on a marker that shares the line (总数), or pre-normalize whitespace.
38. **Mirror fixtures poison id-space analysis** — when computing curated tag sets from HTML fixtures, EXCLUDE `mirror_*` captures: wuxiaspot tag id 682 = "Rebirth" while wuxiabox 682 = "Saving the World". Ids are only meaningful per-site.
39. **Lua locals are lexically scoped — helper blocks must be declared AFTER their dependencies.** A `local function coverUrl()` placed above `local function absUrl()` compiles fine and then crashes at runtime (`absUrl` resolves to the nil global). The wuxiabox 2.2.0 splice shipped this bug for a few minutes before the syntax-check run caught it (as a runtime nil call in tests).
40. **The app's pagination iterator ends the feed on empty OR duplicate pages** (`PagedListIteratorState`: `unique.isEmpty()` or `lastPageHash == newItems.hashCode()` → CONSUMED). Plugins must (a) never return the same items for consecutive indices, (b) raise `error("…")` for transient failures so the app shows a RETRYABLE error state instead of silently ending the feed.
41. **Hardcoded `User-Agent` headers override the UA preset** — engine priority: plugin header > preset by source id > preset by host > global UA. If a plugin hardcodes a UA anywhere, `getUserAgentPreset()` stops applying to that request (and breaks UA-consistency with the baked cf_clearance). Use the preset; let the engine add headers.
42. **The engine's chapter fetch is canonical-host-first and NOT exposed to Lua** (wuxiabox 2.3.0 research): `DownloaderRepository.bookChapter` does TWO engine-side requests to the stored chapter URL (redirect-resolve + document fetch) before `getChapterText(html, url)` ever runs. `SourceInterface.transformChapterUrl` exists but `LuaSourceAdapter` does not implement it — a Lua plugin cannot steer that hop. If the engine request RETURNS a body (502 page after ServerErrorRetryInterceptor's 4 retries — the interceptor RETURNS the last 502 response, it does not throw), the plugin gets it and can rescue from the mirror; if it THROWS (connect timeout / unsolvable CF challenge), the chapter fails with the plugin never invoked. Also: source matching is HOST-prefix based (`url.startsWith(baseUrl + "/")`) — chapter/book URLs MUST stay canonical wuxiabox.com or the engine can no longer route them to the plugin ("Source not supported"). The plugin ships an inert `transformChapterUrl()` hook + the PR documents the 10-line adapter patch that activates it.
43. **`set_preference` is the plugin's persistent store, not just settings UI** (wuxiabox 2.3.0): keys written via `set_preference` land in SharedPreferences "lua_preferences" and survive app restarts; keys NOT listed in `getSettingsSchema()` never appear in the UI. Ideal for engine-restart-surviving state (the smart switcher's health/cooldown state lives in `wuxiabox_site_health`). BUT the engine's `http_get` cache is only 2 s — never assume HTTP-level caching across runs; and remember a RELOADED Lua state re-reads prefs lazily (per `get_preference` call), so persisted state must be parsed defensively (clamp absurd values — clock skew after reboot can make old cooldowns look future-dated; the plugin ignores cooldowns > 1 h ahead).


---

**#44 — GBK sites need the charset wired in THREE places** (bixiange):
plugin metadata `charset = "GBK"` (engine's own chapter/book downloads decode
via `source.charset`), `{charset="GBK"}` on every plugin-side http_get/http_post
(response decoding), and `url_encode_charset(q, "GBK")` for form fields
(REQUEST encoding — a UTF-8 keyword makes EmpireCMS search return the
信息提示 error page instead of results). All three verified in the Kotlin
source AND live.

**#45 — Lua character classes break on multi-byte characters** (bixiange):
a class like `[:：]` matches only the FIRST BYTE of the 3-byte fullwidth
colon — the remaining 2 bytes leak into the capture as mojibake (saw
"༚军事历史" instead of "军事历史"). Always match multi-byte literals as
whole-string alternatives: `match(t, "^分类：(.+)$") or match(t, "^分类:(.+)$")`.

**#46 — EmpireCMS search quirks** (bixiange): the POST 302 Location is
RELATIVE to `/e/search/` (`result/?searchid=S`); result pages are 0-BASED
(`page=1` is the SECOND page); the result-count anchor contains `&nbsp;`
between text and `<b>` (defeats `%s*` patterns — use `title="总数".-<b>(%d+)</b>`);
the 尾页 (last) link is unreliable on list pages (claims 30 while ~45 pages
exist) — hasNext from 下一页 only.

**#47 — 3xx responses come back success=false** (bixiange search): NoveLA's
responseTable marks `success = code in 200..299` — a 302 is NOT successful.
Redirect-handling code must check `r.code` WITHOUT requiring `r.success`,
or the whole branch is dead code (caught by the mock harness, not by syntax
checks).

**#48 — CF-challenged sites can be researched via the Google-Translate proxy**
(oop): `https://www-{host-with-dashes}.translate.goog/{path}?_x_tr_sl=zh-TW&_x_tr_tl=zh-CN`
serves the real DOM (classes/ids/link paths preserved) through Google's
fetchers. Caveats: text is translated, links are rewritten (restore from
paths), some CJK paragraphs get character-REVERSED (un-reverse by matching
text that ends with reversed markers like `介簡`), and Google rate-limits
after ~2 requests (pace with 30-45s sleeps). Fixture cleaner:
`scripts/clean_oop_fixtures.py`.

**#49 — Keep-the-header rule for TXT-imported chapter 1** (both new plugins):
when chapter 1's ONLY content is the TXT header (title/作者/简介), stripping
it produces an EMPTY chapter → the reader shows "Content error". Strip only
when ≥200 chars of real content follow; otherwise keep the header.

**#50 — oop.tw specifics**: ad DIVs are nested INSIDE `article#article`
(extract `<p>` elements only); book catalogs paginate 30/page via `?p=N`
(select options enumerate pages — see #51/#52 before walking them); the
catalog data itself sometimes swaps adjacent chapters (re-sort only when
EVERY title parses to a number); search caps at 100 results on one page
with NO pagination.

**#51 — a failed `http_get` already burned the CF solver — NEVER continue
a page walk after a failure** (oop v1.1.0 incident): when a site's
Cloudflare challenge does not clear for the app's OkHttp client,
`CloudfareVerificationInterceptor` runs its full ladder per REQUEST
(cookie retry → 15 s hidden auto-WebView → up to 2 x 35 s manual
WebViewActivity → `CloudfareVerificationBypassFailedException`). `http_get`
CATCHES that exception and returns `{success=false}` — it does not throw
into Lua. A Lua loop that skips a failed page and fetches the next one
therefore launches the visible solver once per page (oop v1.0.0: one
launch per 30-chapter catalog page, TOC never finished). Correct pattern:
ABORT the walk at the first failure; cache progress; resume on the next
call.

**#52 — the engine's `parsePage(bookUrl, page)` API is the paginated TOC
contract** (present in BOTH the Aug-25 and Sep-18 engine builds): return
`{ chapters = {...}, totalPages = N }`; a NON-TABLE return (nil) is a
per-page error. Engine behavior: first load walks pages 2..totalPages via
parsePage and BREAKS on the first error (`bookChaptersList`); later TOC
refreshes are INCREMENTAL (`updateChaptersIncremental` re-reads only the
last known page + new pages). Mid-walk gaps self-heal because
`ChapterPagination.isPageCounterConsistent` uses a 30-chapter/page floor —
if a site's page size is >= 30, a partial walk trips the check and forces
a clean full reparse. `parsePage` present ⇒ `getChapterList` no longer
required by the engine (keep it as the old-engine fallback).
`bookChaptersList` also calls `parsePage(1)` twice on first load (full
walk + totalPages probe) — an in-memory page cache makes the second call
free.

**#53 — append-only chapter sites allow an immutable interior-page cache**
(oop v1.1.0): when a site only APPENDS chapters (live-verified for
oop.tw), catalog pages 1..totalPages-1 never change — cache them
persistently (`set_preference`), serve interior pages with zero network,
and always re-fetch the LAST known page (it keeps filling before spilling
onto a new page) and anything beyond. On fetch failure serve the stale
cached copy (readable-stale beats an error screen) and keep partial
progress so the next attempt resumes where the last one stopped. The
engine's own DB + `chaptersLastPage` is the durable copy on parsePage
engines; the plugin cache exists for old-engine fallback walks and
gap-heal reparses. Guard: when totalPages changes, drop the previous last
page (keep = min(old, new) - 1); translate titles into COPIES so the
cache never stores translated text.

## Part 7 — Where Everything Lives (dev environment)

```
/home/z/my-project/
├── download/
│   ├── wtrlab.lua              # current plugin v1.1.9 (ship this)
│   ├── novel543.lua            # current plugin v1.0.4 (ships as "Novel543 Full")
│   ├── README.md               # wtrlab maintainer/README doc
│   ├── pull_request.md         # wtrlab PR description (1.1.9 vs 1.1.8)
│   ├── MAINTENANCE.md          # this file — the shared knowledge base
│   ├── wtrlab_50ch_test.{md,csv}
│   └── test-harness/           # copy of testenv for shipping
├── testenv/                    # LuaJ 3.0.1 + jsoup + gson + ecj harness (jars in lib/)
│   ├── LuaTest.java            # wtrlab suite (59 live + 23 mock; TEST 2b/5d/5e + MOCK G for v1.1.9)
│   ├── Novel543Test.java       # novel543 suite (196 live tests, curl-backed HTTP + real json_parse + live Google-translate + fault injection)
│   ├── ChapterTiming.java      # wtrlab latency/cache proof (counts POST reader/get too, v1.1.9)
│   ├── OkHttpTranslateSim.java # one-off: proved the app's exact OkHttp POST/header set works against Google (jars in lib2/)
│   └── SyntaxCheck.java
├── scripts/                    # reproducible generation/refresh scripts
│   ├── gen_tag_search_index_v2.py  # TAG_SEARCH_INDEX (id|Label|catId) from tags_live_v2.json
│   ├── swap_tag_block_v2.py        # idempotent index splice into wtrlab.lua
│   ├── wtrlab_tags_v3.py           # dump live finder tags → research/tags_live_v3.json
│   ├── gen_tag_pickers.py          # 11 tag_pick_N dropdown blocks (refuses duplicate labels)
│   ├── splice_v119.py              # idempotent picker splice into getFilterList
│   ├── test_plugin_integration.py # 22 offline lupa checks (v1.1.9 semantics)
│   └── …                       # capture/verify/debug scripts from the wtrlab work
├── research/
│   ├── NoveLA/                 # the app's Kotlin source (API ground truth)
│   ├── external-sources/       # upstream plugin repo clone
│   ├── tags_live_v3.json       # 888-tag source of truth (wtrlab, v1.1.9 refresh chain input)
│   ├── tag_pickers.lua         # generated 11-picker block (splice_v119 input)
│   ├── novel543_*.html/js      # captured novel543 pages (bookstack/tags/ranking/shudan/search/book/chapter + shudan detail)
│   └── …                       # captured wtr-lab payloads for mock tests
├── wtrlab_original.lua         # upstream wtrlab 1.1.6 (diff baseline)
├── novel543_original.lua (research/)  # upstream novel543 1.0.3 (diff baseline)
└── worklog.md                  # full session-by-session work log
```

**Submitting updates:** replace `mtl/wtrlab.lua` (and/or `zh/novel543.lua`) in https://github.com/HnDK0/external-sources, keep the icon URL in metadata pointing at the repo's `icons/` path, and use the PR description in `download/pull_request.md` (for wtrlab; novel543 can reuse the same structure).
**#54 — non-Cloudflare WAFs are INVISIBLE to the engine's CF detector**
(69shubaTw): `isNotCloudflare` requires a cloudflare/ddos-guard `Server`
header (or `cf-mitigated: challenge`), so Tencent EdgeOne / other custom
captcha walls pass straight through to the plugin as {success=false} 403s.
`cf_options = { trigger_markers = { … } }` (LuaSourceAdapter →
LuaCfOptionsRegistry) makes the interceptor treat ANY body containing a
marker as a challenge on ANY status code → the WebView ladder runs, and the
post-solve retry carries ALL WebView cookies (not just cf_clearance). Pick
markers unique to the challenge page (the verify endpoint path, the widget
class, the page title) — never anything that can appear on real pages.

**#55 — WAF rules can be path-asymmetric** (69shubaTw): probe MORE than the
homepage before concluding a site is (in)accessible — 69shuba.tw challenges
`/indexlist/*` even for the Google-Translate proxy while serving `/book/*`,
`/read/*`, `/search/*` happily. The practical consequence: a plugin's
chapter-catalog fetch is the surface most likely to need the one-time
WebView solve, and mock fixtures for that surface may be impossible to
capture (synthesize them + make the parser layout-agnostic instead).

**#56 — layout-agnostic TOC parsing when the catalog markup is unknown**
(69shubaTw): when a site's chapter list cannot be captured, don't guess
containers — scan every `<a>` for the site's chapter-URL shape
(`/read/{bookId}/{cid}`), filter by the SAME book id (kills recommendation
links), dedupe by the id and sort by it (global article ids follow reading
order on Jieqi-family sites — verify with ch1→ch2→latest samples first).
Cross-page dedupe by URL in the walk guards against a wrong page-N URL
soft-serving page 1 again.

**#57 — parsePage(1) must NEVER return nil** (69shubaTw v1.1.0): the engine's
adapter converts a nil into `Response.Error("parsePage returned non-table")`,
and app builds that don't propagate `show_error` from parsePage show the user
exactly that bare string (real incident, 2026-09-20). Contract: page 1 →
ALWAYS a table (`{chapters={}, totalPages=1}` worst case, after show_error);
pages > 1 → nil to stop the walk. Pair with a fallback data source whenever
one exists (here: the book page's latest-chapters preview + a #pb_next walk
— both on never-challenged paths) so the "empty table" branch is nearly
unreachable in practice.

**#58 — the book page is a TOC fallback** (69shubaTw): before inventing
proxies or walks, check what the BOOK page already carries — many CMS themes
embed 最新章節預覽 (latest-N chapters with real titles) plus a start-reading
link. Twelve real chapters + chapter 1 = an instant readable TOC on any app
build, no captcha. Emit the seed as the FINAL virtual page (positions!) and
report a huge totalPages (9999) so `ChapterPagination.isPageCounterConsistent`
fails and the engine rebuilds positions cleanly on the next full load.

**#59 — pager selects are windows, not totals** (69shubaTw): the site-wide
`#indexselect` shows a 10-page window — page 1 of a 15-page TOC answers "10",
and the engine's walk bound is FIXED by page 1's answer (long books silently
truncate). Chase it: probe the max-option page; a probed page without a
next link IS the last page; otherwise continue from its window max (≤12
probes). Probes are real pages the walk needs anyway — cache them. A
`【共N章】` heading cross-check lets the chase JUMP straight to the hinted
page (ceil(N/pageSize)) instead of walking windows.

**#60 — find the same-CMS sibling when the target is uncapturable**
(69shubaTw v1.2.0): when every proxy fails against the one WAF-hard path,
hunt for a family site running the same CMS generation WITHOUT the wall —
69shuba.app → wcshuba.com (無錯書吧) served the exact counterpart of .tw's
`/indexlist/` (`/chapterlist/{id}.html`) with live captures: h3
`章節目錄【共N章】`, dual `#indexselect-top/-bottom` selects whose option
VALUES are the page URLs, a global 下一页 link, 100 chapters/page, the main
list rendered twice. Verify family kinship FIRST (same URL grammar, same
pager component names, same charset/script), then pin the parser to the
sibling's markup and keep generic fallbacks for target-site drift.

**#61 — pager intel: values can be URLs, and one of them is a trap**
(69shubaTw v1.2.0): on the family pager the select's option VALUES are the
actual page URLs — use them directly for parallel prefetch (zero template
guessing). But page 1's option may be the UNNUMBERED canonical form
(`/indexlist/{id}/`), which a trailing-number parser reads as the BOOK ID
(342441 pages!) — reject values equal to the book id and absurd counts, and
only treat same-path values as fetchable URLs (a sibling's
`/chapterlist/…` value is a page NUMBER, not a .tw URL).



**#62 — WAF path rules can be CASE-SENSITIVE — flip the case before
inventing fallback walks** (69shubaTw v1.3.0): the uncapturable `/indexlist/*`
challenge was simply a case-sensitive EdgeOne rule; `/Indexlist/` (same
router, case-insensitive) serves the page WAF-free. When a site 403s ONE
path family from every IP (verified via a clean-IP proxy), try capital /
mixed-case variants of the FIRST path segment before building fallback
walks. Discovery cost: one proxy fetch pair. Payoff: the whole solver-storm
class of bugs disappears. Corollary: register the challenge body markers in
the plugin anyway (`isChallengeBody`-style detection) so a future rule fix
degrades into a guided error, not a parse-the-captcha-page bug.

**#63 — anti-scrape "protected" list entries are still real pages**
(69shubaTw v1.3.0): the catalog's protected chapters render as
`<span data-cid-url=…>` instead of `<a href=…>` (~2% of entries — enough to
corrupt a TOC silently). Harvest BOTH forms (`html_select(body,
"[data-cid-url]")` — jsoup attribute selectors work in the engine), and
verify by opening one: the protected chapter served full content at the
plain `/read/{bid}/{cid}` URL (the span is link obfuscation, not a
paywall). General rule: parse chapter LISTS by URL SHAPE (the /read/
pattern), not by tag name.

