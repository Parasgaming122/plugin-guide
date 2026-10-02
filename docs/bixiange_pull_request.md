# bixiange.lua v1.0.1 — new source plugin for NoveLA (笔仙阁, www.bixiange.top)

**TL;DR:** New plugin for **Bixiange (笔仙阁)** — a free Chinese novel site
(GB2312-encoded EmpireCMS, ~280k books, TXT-imported full novels). Full
browse/search/read support with the **site's GBK encoding handled end-to-end**,
transparent **bxg123.cc mirror failover**, and the battle-tested **novel543
translator** built in (catalog titles, book info, chapter titles, and
search-query translation to Simplified Chinese). Verified **90/90 offline
checks + 20/20 live checks** including the user's target book
`https://www.bixiange.top/jsls/23825/` (家父永乐，我只想修仙 — 300 chapters,
readable end to end).

## v1.0.1 (2026-09-30) — site URL-scheme change, zero code changes needed

The site retired its `/cat/{id}/` and `/cat/{id}.html` book URLs (both **404
now**, live-verified). Books live at **category-prefixed** URLs — `/{cat}/{id}`
(e.g. `/xhqh/23552`) and `/{cat}/{id}.html` for older books — and chapters
moved to `/{cat}/{id}/index/{n}.html`. The mirror bxg123.cc switched to the
identical scheme on the same day, so failover is unaffected.

**No parser changes were required**: the plugin takes every book/chapter URL
from the site's own hrefs (search cards, sort cards, `.catalog ul li a`
anchors) and never constructs `/cat/` paths itself. v1.0.1 is a documentation
release: the header docs now describe the current scheme, and the test suite
gained **T23 — 14 new checks against byte-for-byte live captures** of today's
pages (book `/xhqh/23552` with 504 chapters, chapters `index/1.html` and
`index/2.html`, `/sort/` cards) proving title/description/date parsing, the
full chapter list, chapter text with TXT-header stripping, and canonical card
URLs — **90/90 PASS**.

Live re-verification of every selector on 2026-09-30: `.hd .list ul li`
search cards (斗破苍穹 → `/trxs/21226`), `descInfo`/`descTip` book metadata,
`.catalog ul li a` chapter anchors, `div#mycontent` chapter text, `index_N.html`
pagers, the `总数` search counter, and the EmpireCMS POST search round-trip.

---

## 1. What the site is

| | |
|---|---|
| Content | Full-length Chinese web novels (TXT imports, 1 MB–20 MB books) |
| CMS | EmpireCMS (same family as wuxiabox.com) |
| Encoding | **GB2312/GBK everywhere** — pages, search form, redirects |
| Categories | 12 (都市言情 … 精品小说) |
| Chapters | “第N节” numbered sections; full catalog on the book page |
| Mirror | https://bxg123.cc — a live copy sharing the SAME database (identical book ids AND identical search `searchid`s — verified live) |
| Cloudflare | In front (`server: cloudflare`) but serves directly from datacenter IPs today; engine WebView bypass stays enabled as the safety net |

## 2. The GBK story (the interesting part)

NoveLA's engine is UTF-8 by default. This plugin uses every charset hook the
engine provides (all verified in the Kotlin source):

1. **Plugin metadata `charset = "GBK"`** → the ENGINE decodes its own
   downloads (chapter pages for `getChapterText`, and the redirect-resolve
   hop) as GBK via `source.charset` → `Response.toDocument(charset)`.
2. **`http_get/http_post(url, { charset = "GBK" })`** → every plugin-side
   fetch decodes its response as GBK (`String(bytes, Charset.forName(cs))`).
3. **`url_encode_charset(query, "GBK")`** → the EmpireCMS search POST
   requires the `keyboard` form field percent-encoded as **GBK bytes**
   (`家父永乐` → `keyboard=%BC%D2%B8%B8%D3%C0%C0%D6`). A UTF-8 keyword gets a
   200 "信息提示" error page instead of results — verified live.
4. The mirror shares the same database, so searchids and every path are
   portable between `www.bixiange.top` and `bxg123.cc` — the failover host
   substitution is completely transparent (a `502` on one host falls through
   to the other for the SAME page).

## 3. Site quirks the plugin defends against (all live-verified 2026-09-19)

| Quirk | Defense |
|---|---|
| Two book-URL generations: new books `/cat/{id}/`, old books `/cat/{id}.html` — and the slash form **403s** for .html books | URLs are never normalized; the plugin uses exactly the hrefs the site serves |
| No-slash book URLs 301 → slash form (engine `http_get` does not follow redirects) | Manual Location following (4 hops, RFC-3986 resolution) |
| Chapter 1 embeds a TXT header (书名 / 作者：… / 简介：… / synopsis block) | Two-tier strip: (a) 第X章-heading marker deep in the paragraph stream, (b) structural title/作者/简介 markers |
| Search redirects with a **relative** Location (`result/?searchid=S`) | Resolved against `/e/search/` then fetched |
| Search results are **0-based** pages (`page=1` = second page), 20/page | Total-count `<a title="总数"><b>N</b></a>` drives exact hasNext (the `&nbsp;` inside the anchor defeats `%s` patterns — lazy-match parsing used) |
| Category pager's 尾页 (last) link is wrong (claims 30 while ~45 pages exist) | hasNext uses only the 下一页 (next) link |
| Beyond-end pages serve garbage subsets (cycling items) | App-side duplicate/empty-page detection ends pagination; 404s return empty gracefully |
| Zero-result search = 200 “信息提示” interstitial | Detected as a definitive empty result (NOT an error — no retry storm) |
| Lua patterns are byte-based — `[:：]` character classes corrupt multi-byte colons | Both colon variants matched as literal alternatives everywhere |

## 4. Features

- **Browse surfaces** (filter sheet): 最新更新 Latest Updates (`/newest/`),
  总排行榜 Overall Rankings (`/sort/`), 分类浏览 By Category (12 categories),
  分类排行榜 Category Rankings (`/sort_{cat}/`). All share the same card
  markup and `index_N.html` pager (15/page).
- **Search** with GBK-encoded keywords, 20/page pagination, total-based
  hasNext, mirror-transparent.
- **Translator mode** (copied from novel543 v1.0.5): Google free dict endpoint
  (POST + GET on 2 hosts) → MyMemory → gtx single fallback chain, translation
  cache, 3-strike circuit breaker (10-min half-open), pcall armor on every
  entry point. Translates catalog titles, book title (+ original in
  parentheses), description, genres, status vocabulary, chapter titles
  (toggle), and **search queries typed in any language → Simplified Chinese**.
- **Mirror switcher setting**: Auto (bixiange.top first, bxg123.cc fallback) /
  bixiange.top only / bxg123.cc first — every fetch (catalog, search,
  book, chapter) respects it; book/chapter URLs stay canonical
  `www.bixiange.top` so libraries never fragment.
- **Poster fix**: covers via the wsrv.nl image proxy by default (engine
  exempts image URLs from the CF bypass — the established poster pattern);
  "direct" setting to opt out.
- **Chrome Mobile UA preset** (engine applies it to plugin requests AND
  image loads).
- **show_error** surfaces when both hosts are unreachable (avoids the
  app's 3× retry loop on hard outages by not using trigger words in the text).

## 5. Settings

| Setting | Values |
|---|---|
| Site (站点) | Auto / bixiange.top only / bxg123.cc mirror first |
| Cover Images | wsrv.nl proxy (default) / direct |
| Mode (模式) | Raw / Translator |
| Translate To | 15 languages |
| Translate Chapter Titles | On / Off |

## 6. Testing — 96 checks, all green

Harness: `test-harness/BixiangeTest.java` (LuaJ 3.0.1 + jsoup + gson; the
NoveLA engine emulated with the same semantics verified against the Kotlin
source — including the charset option and `url_encode_charset`).

**Mock suite (76/76)** — fixtures recorded live from the site (raw GBK bytes,
decoded by the harness exactly like the engine):

| Group | Checks | Highlights |
|---|---|---|
| T0 metadata | 6 | id/version/**charset=GBK**/baseUrl/required fns/no cf_options |
| T1 filters | 4 | 4 surfaces, 12 categories |
| T2 category list | 5 | 15 items, canonical URLs, proxied covers, hasNext |
| T3 newest default | 3 | default surface + `/newest/index_2.html` paging |
| T4 book page | 10 | "(1-301)" suffix stripped, cover, author-prefixed description, genres, date, hash, 1-fetch session cache |
| T5 chapter list | 4 | 300 chapters, URL pattern `/index/N.html` |
| T6 chapter 1 text | 5 | TXT header stripped → starts at 第1章 |
| T7 chapter 150 | 2 | clean mid-chapter content |
| T8 old book `.html` | 3 | 288 chapters at `/khjj/20819/N.html` |
| T9 search 302 | 5 | POST → 302 → 1 result; **GBK keyword encoding asserted byte-for-byte** |
| T10 search pages | 5 | 84 results, 0-based `page=1`, exact total-based hasNext |
| T11 zero results | 3 | 信息提示 interstitial → empty, no error |
| T12 mirror failover | 3 | 502 on primary → mirror serves; canonical URLs kept |
| T13/14 site preference | 2 | top-only never touches mirror; mirror-first order |
| T15 covers direct | 1 | setting honored |
| T16 settings | 2 | 5 entries |
| T17 UA preset | 1 | Chrome Mobile |
| T18 translator | 4 | titles/book/chapters translated; toggle off |
| T19 query translation | 2 | English → zh-CN → GBK POST |
| T20 breaker | 1 | dead engines → raw pass-through |
| T21 dead sites | 3 | show_error |
| T22 beyond-end | 2 | 404 → empty |

**Live suite (20/20)** — real network, real GBK decoding:

- `/newest/` 20 items + hasNext
- **Book `/jsls/23825/` (the user's target): title 家父永乐，我只想修仙, 300
  chapters, chapter 1 starts at 第1章 (header stripped), 2,170 chars; chapter
  150 clean; description/genres/date/cover all parse**
- Search 家父永乐 → exactly the target book at its canonical URL
- Search 三国 → 20 + 20 distinct items across pages, total-based hasNext

## 7. Known limits

- Book pages carry no ongoing/completed status — `getBookStatus` returns nil
  (the site simply doesn't expose it).
- Chapter titles are the site's bare "第N节" numbering (translator mode
  renders them as "Section N"/"Chapter N").
- Category browsing deeper than the pager's real end (~page 45 for 军事历史)
  degrades to the site's own garbage pages; the app's duplicate-page
  detection ends pagination there.
- The site's client-side mainland-China+Windows redirect (`/404.html`) is
  pure JS — irrelevant for the app.

## 8. Install

Import `bixiange.lua` as a local extension in NoveLA (Extensions → import).
No conflicts: new source id `bixiange`, name "Bixiange 笔仙阁".
