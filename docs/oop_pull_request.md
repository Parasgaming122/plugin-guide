# oop.lua v1.1.0 — chapter-list Cloudflare fix ("solver storm")

**TL;DR:** v1.0.0's chapter list walked every 30-chapter catalog page and
kept fetching the NEXT page after each failure — and on oop.tw a failed
fetch means the engine already burned a full Cloudflare solver attempt
(15 s hidden WebView + up to 2 x 35 s manual WebView). Result: opening a
novel launched the solver once per catalog page and the TOC never finished
loading. **v1.1.0** ships the engine's paginated `parsePage()` API (walks
stop at the first failed page, TOC refreshes become incremental), an
early-abort fallback walk for older engines, and a persistent per-book page
cache that serves immutable interior pages without network, resumes broken
walks where they stopped, and shows a stale TOC when the site is entirely
unreachable. Verified **97/97 offline checks**.

---

## 0. The incident & the fix (v1.1.0)

### Symptom (user report)

> "OOP plugin isn't working novels aren't loading, it keeps launching
> cloudflare solver I think it's trying to get content of each page in
> table of contents, each page has 30 chapters."

### Root cause chain (verified against the engine source)

1. **Every catalog page is a separate `http_get`.** oop.tw paginates book
   catalogs at 30 chapters/page (`?p=N`); v1.0.0's `getChapterList` fetched
   page after page inside one Lua call.
2. **A failed fetch already cost one solver launch.** When oop.tw's
   managed challenge does not clear for the app's HTTP client,
   `CloudfareVerificationInterceptor` runs the full ladder per request:
   cookie retry -> 15 s hidden auto-WebView -> up to 2 x 35 s manual
   `WebViewActivity` (the visible "solver") -> exception. `http_get`
   catches that exception and returns `{success=false}` — **it does not
   throw into Lua**.
3. **v1.0.0 treated a failed page as "skip and continue"** — the walk
   fetched the next page, which re-ran the whole ladder. One solver launch
   per 30-chapter page, N pages in a row, TOC never completes.
4. **Every TOC open re-walked everything** — only a 60 s in-memory page
   cache existed, so each revisit paid the full walk again.

### The fix (4 layers)

| Layer | What it does |
|---|---|
| **`parsePage(bookUrl, page)`** | The engine's paginated chapter-list API (present in BOTH the Aug-25 and Sep-18 NoveLA builds — verified). The engine walks pages through it, **stops at the first failed page** (`bookChaptersList` breaks on `Response.Error`), and TOC refreshes become **incremental**: only the last known page + genuinely new pages are re-fetched (`ChaptersViewModel.updateChaptersIncremental`), not the whole catalog. Mid-walk gaps self-heal: the engine's `ChapterPagination.isPageCounterConsistent` uses a 30-chapter/page floor — exactly oop.tw's page size — so a partial walk trips the check and forces a clean full reparse. |
| **Early-abort fallback walk** | `getChapterList` (for engines without `parsePage`) now **breaks at the first failed page**. Worst case per TOC open: ONE solver attempt, not N. |
| **Persistent page cache** (`set_preference`, `oop_toc_<bookId>`) | oop.tw only **appends** chapters, so pages `1..totalPages-1` are immutable. Interior pages are served from the cache with **zero network**; the last known page and anything beyond it is always fetched fresh. Progress accumulates: a walk that dies at page 3 keeps pages 1-2 cached, and the next attempt resumes there. LRU-capped at 5 books / 100 KB per book. |
| **Stale-serve + clear errors** | When a fetch fails but a cached copy exists, the stale copy is served (a readable stale TOC beats an error screen). When page 1 is unreachable and nothing is cached, `show_error` explains the Cloudflare situation and that progress is remembered — no more silent empty lists. |

Also in v1.1.0: `getChapterListHash` now includes `totalPages` + the last
chapter number parsed from the pager's option labels ("第31～44章" → 44), so
library updates detect new chapters even when the update-time string
happens not to change.

### What the user sees after the fix

- **CF clearance works** (normal case): first TOC open = one walk
  (1 request per page, solver at most once); every later open = 1-2
  requests (incremental), interior pages never re-fetched.
- **CF clearance doesn't stick** (the reported case): the walk stops at
  the first failed page — at most ONE solver launch per TOC open — and
  each retry makes progress via the persistent cache until the catalog
  completes. A book whose catalog was fully cached opens with **zero**
  site requests.
- Reading chapters is unchanged (the engine pre-fetches the chapter
  document; `getChapterText` parses it without extra requests).

---

## 1. Context: what the site is (v1.0.0 research)

| | |
|---|---|
| Content | TC novels: short stories (短篇), long serializations (up to 2.69M words / 870+ chapters), R18 novels (category 12) |
| Encoding | UTF-8, Traditional Chinese titles/text |
| URL model | Books `/abooka/a{id}a/`, chapters `/areada/a{book}a/a{chap}a.html`, library `/sort/{cat}/{page}/` |
| Search | `GET /search/?searchkey=…&searchtype=all` — up to **100 results on one page** (no pagination, verified live) |
| Catalogs | Book-page catalogs are **paginated 30/page via `?p=N`** (a `<select>` enumerates every page) |
| Cloudflare | **Aggressive managed challenge from datacenter IPs** (`cf-mitigated: challenge` on every path). On real devices the engine's WebView bypass handles it — the plugin explicitly keeps that path enabled |

## 2. Context: research technique (why the fixtures are trustworthy)

oop.tw challenges every datacenter IP (direct curl, r.jina.ai, allorigins,
codetabs, z-ai page_reader — all blocked; even the headless browser cannot
pass the managed challenge). The site was researched through the
**Google-Translate proxy** (`www-oop-tw.translate.goog`), which preserves the
DOM structure (classes, ids, link paths) while translating text. Fixtures
were then cleaned (`scripts/clean_oop_fixtures.py`): font wrappers stripped,
links restored to relative site paths, and the CJK paragraphs Google's proxy
character-reversed (a direction artifact) un-reversed. The mock tests run
against these cleaned, structurally-faithful captures. On-device the app
fetches the real pages through its CF WebView bypass.

## 3. Context: site quirks the plugin defends against

| Quirk | Defense |
|---|---|
| Ad DIVs **inside** the chapter `<article>` (`.mid-content-ad`, ONEAD tags) | Content extracted from `<p>` elements only — every ad div is skipped |
| Chapter 1 of TXT-imported books is often **only** the TXT header (書名 / 作者: / 簡介:) | Header stripped only when ≥200 chars of real content follow; otherwise KEPT (an empty chapter would surface as a reader content error) |
| The site's catalog occasionally swaps adjacent chapters (live: 003,005,004,006…) | When EVERY title parses to an unambiguous number ("001", "第3章…", "Chapter 7"), chapters are sorted by it; otherwise the site's order is kept |
| Covers: `nocover.jpg` placeholder | Passed through un-proxied (no point proxying a static asset) |
| Cloudflare on every path | No `cf_options` whitelist (keeps the engine's WebView bypass); covers via wsrv.nl proxy by default (image URLs are exempt from the bypass); `show_error` messages tell the user to solve the challenge once in the WebView |

## 4. Features (v1.0.0, unchanged unless noted)

- **Browse**: full library `/sort/{page}/` (10/page, 28k+ pages) with a
  15-option category picker (All + 玄幻魔法 1 … 男頻都市 14, incl. R18 12);
  hasNext from the pager's `>>` link.
- **Search**: one-shot GET (≤100 results), same card markup as the library,
  `.highlight` spans merged into titles.
- **Book pages**: title, cover, 关键字 tags as genres, 全本/連載 →
  Completed/Ongoing status, rating parsed, latest-chapter `.update-time` as
  last update, chapter-list hash = update-time + totalPages + last
  chapter number (v1.1.0).
- **Chapter catalogs** (v1.1.0): paginated via `parsePage()` — the engine
  stops at the first failed page and refreshes incrementally; a persistent
  per-book page cache serves immutable interior pages without network and
  resumes broken walks (see section 0). Chapter URLs use global article
  ids, so pages must be enumerated — there is no single-request full-TOC
  endpoint (probed `?p=all`: not supported).
- **Translator mode** (novel543 engine, source zh-TW): catalog titles, book
  title (+ original), description (keywords-prefixed), genres, status
  vocabulary, chapter titles (toggle), and **search queries translated to
  Traditional Chinese** (the site indexes zh-TW).
- **Poster fix**: wsrv.nl proxy default, direct opt-out.
- **Chrome Mobile UA preset**.

## 5. Settings

| Setting | Values |
|---|---|
| Cover Images | wsrv.nl proxy (default) / direct |
| Mode (模式) | Raw / Translator |
| Translate To | 15 languages |
| Translate Chapter Titles | On / Off |

## 6. Testing — 97 checks, all green

Harness: `test-harness/OopTest.java` (engine emulation; fixtures captured
through the Google-Translate proxy and cleaned — see section 2; live
network tests impossible from datacenter IPs, CF-challenged).

v1.0.0 groups (T0-T18, 59 checks) all still pass unchanged in substance
(version/parsePage assertions updated). The **v1.1.0 battery (38 new
checks)** uses a synthesized 5-page, 150-chapter book
(`research/newsites/oop_tocgen_p1..p5.html`, with the site's
swapped-adjacent-chapters quirk embedded on page 2) plus a single-page
book:

| Group | Checks | Highlights |
|---|---|---|
| T0 metadata | 7 | version 1.1.0, **parsePage present**, no cf_options |
| T1-T18 | 52 | the full v1.0.0 battery (browse/search/details/text/translator/covers) |
| **T6b early abort** | 4 | **p3 fails → walk stops: 60 of 150 chapters; p4 NEVER fetched; progress cached** |
| **T6c resume** | 7 | rerun completes 150 chapters; **interior page 2 served with 0 network**; missing p3/p4 fetched; last page always fresh; 001→150 ascending |
| **T6d parsePage** | 11 | table contract (chapters + totalPages=5 from any page's select); swapped-quirk re-sorted (031,032 — not 031,033); interior = 0 network; last page fresh on every call; unreachable → non-table; **show_error only for page 1** |
| **T6e stale serve** | 2 | fully-cached book serves 150 chapters with NO site access, no error |
| **T6f cache purity** | 4 | translated titles returned to the reader while the persistent cache keeps RAW titles |
| **T6g LRU** | 9 | 6 books walked → cache capped at 5, oldest evicted, LRU order exact |

## 7. Known limits

- **Cloudflare**: from datacenter/shared IPs the site challenges everything.
  On real devices the engine's hidden WebView solves it (or the manual
  WebView appears once). If covers break while the site challenges images,
  keep the default wsrv.nl proxy.
- **v1.1.0 residual limit**: when the challenge does not clear for the
  app's HTTP client at all, each TOC open still pays ONE solver attempt
  (the book-page fetch) before the early abort — the plugin cannot prevent
  the engine's own WebView ladder, only stop compounding it. The stale
  cache keeps already-loaded books readable in that state.
- The interior-page cache assumes oop.tw only APPENDS chapters (live-verified
  behavior). A hypothetical mid-list chapter insertion would leave older
  cached pages stale until the book's hash changes or the cache is evicted
  (LRU). `getChapterListHash` covers the append case (totalPages + last
  chapter number).
- The R18 sister site (oopr18.tw) is a separate domain and is NOT part of
  this plugin (only the main site's category 12 肉文小說).
- Booklists (`/booklist/`) and author pages (`/author/{name}/`) are not
  surfaced as browse options (v1 scope).
- Search returns at most 100 results with no pagination (site-side cap).

## 8. Install

Import `oop.lua` as a local extension in NoveLA (Extensions → import).
No conflicts: new source id `oop`, name "OOP 小說網".
