# Pull Request — `zh/novel543.lua` v1.0.5

**Source:** [`zh/novel543.lua`](https://raw.githubusercontent.com/HnDK0/external-sources/refs/heads/main/zh/novel543.lua)
**Base version:** `1.0.4` (upstream — this repo already carries our 1.0.4)
**Proposed version:** `1.0.5`
**Date:** 2026-09-18
**Plugin size:** ~1,660 lines

---

## TL;DR — what 1.0.5 adds on top of 1.0.4

1. **Posters fixed.** Novel543 covers live on `i2.novel543.com`; when that image host is challenged by its CDN, NoveLA's image loader receives the challenge page instead of the JPEG — **image URLs are exempt from the engine's Cloudflare WebView bypass** (`STATIC_EXTENSIONS`) — and the poster silently fails. All covers (catalog cards, book pages, booklist headers) are now served through the **wsrv.nl image proxy** (`https://wsrv.nl/?url=<encoded>&w=450&we&output=jpg&q=80` — the `images.weserv.nl` service the engine whitelists for exactly this pattern). A new **Cover Images** setting offers `proxy` (default) or `direct`.
2. **Display name synced with upstream** ("Novel543 Full" → "Novel543", matching the repo rename) and the in-app self-test banner follows.

Verified by the live harness: **197/197 pass** (+1 environment skip: `/search/` is Cloudflare-blocked from datacenter IPs and can only be verified on a device). All four cover surfaces assert the proxy URL shape.

---

## TL;DR — the 1.0.4 change set (context)

This PR upgrades the Novel543 (稷下書院) source plugin for NoveLA from a minimal 192-line bookstack scraper to a full-featured source with **filter parity with the live site** and an opt-in **Translator mode** for non-Chinese readers:

1. **Full site filters, scoped to the page being browsed (the funnel button).** A "Page" picker (Bookstack 書庫 / Rankings 排行榜 / Booklists 書單) heads the filter sheet, and the sheet shows **only the filters that belong to that page** — exactly like each page's own sidebar on the site: Bookstack → Type / Status / 13 categories / **100 tags with curated English names**; Booklists → Type / 3 sorts; Rankings → Ranking Type (閱讀/潛力/風雲) / Gender (女生/男生) / 40 categories. (The app's filter UI cannot hide sections dynamically — it renders whatever `getFilterList` returns — so the plugin returns a different, page-matched list per page; see §2.1.) Filter labels are bilingual `English (中文)`, and **English-only when Translator mode is on** (the old tag list was raw Chinese only — unusable for anyone who cannot read Chinese).
2. **Translator mode (mirrors `mtl/wtrlab.lua`'s mode picker).** A settings-selectable mode that machine-translates **everything except chapter text** — catalog / search / ranking / booklist titles, book title (as `English (原文)`), description, genres, status, chapter titles (toggle), and even the search query itself (English → zh-TW, zh-CN retry). Chapter bodies are deliberately left alone: NoveLA's built-in reader translator already handles novel content. Engine: Google's free `dict-chrome-ex` endpoint with a 6-step fallback chain, a session cache, a failure circuit breaker, and pass-through to the original text on ANY error — **browsing can never break because of the translator**.
3. **Core scraper fixes over 1.0.3.** Exact `hasNext` (the old `#items > 0` heuristic over-fetched because the site clamps out-of-range pages to the last page with HTTP 200), a change-detecting chapter-list hash (`update_time|latest_chapter_name` — catches same-day retranslations), stripping of the site's trailing 溫馨提示 reader notice from every chapter, manual redirect following (NoveLA's `http_get` does not follow 301s; `/ranking.html` and mismatched ranking combos 301-redirect), one page fetch per book open instead of 6–8, and `getBookGenres`.

All changes are **backward-compatible**: raw mode preserves 1.0.3 behavior for every original function, and `id` / `baseUrl` / `language` / `icon` are untouched.

---

## 1. Background — what 1.0.3 looked like

Upstream 1.0.3 (192 lines, 10 functions) scraped exactly one surface — `/bookstack/?page=N` — with:

| Limitation | Consequence |
|---|---|
| No `getFilterList` / `getCatalogFiltered` | No funnel icon in the app at all — none of the site's categories, tags, rankings or booklists were reachable |
| No `getSettingsSchema` | No gear icon, no settings |
| `hasNext = #items > 0` | The site **clamps** out-of-range pages to the last page with HTTP 200 (verified: `page=9999` serves 第20頁 content), so the heuristic could never detect the end and over-fetched a clamped duplicate page |
| `getChapterListHash` read a date-granularity 更新 label from `p.meta` | Same-day updates and same-day retranslations were invisible to library refresh |
| `div.content` scraped as-is | The site appends a 溫馨提示 (kindly-notice) blurb inside `div.content` on **every** chapter page — it was saved into the reader text of every chapter |
| `http_get` assumed to follow redirects | NoveLA's `NetworkClient` runs `followRedirects=false`; `/ranking.html` and cross-gender ranking combos answer 301 → those pages "failed" |
| No `getBookGenres` | Genres row never populated |
| Each book-metadata getter fetched the page independently | Opening one book = 6–8 downloads of the same page |
| Entire UI in Chinese | Site is zh; non-Chinese readers could not browse or search at all |

---

## 2. What changed (full breakdown)

### 2.1 Filters (`getFilterList`) — PAGE-SCOPED: the sheet mirrors the browsed page

Every page of the site has its **own** filter sidebar, so the plugin's filter sheet does too. `getFilterList()` returns the Page picker followed by **only the current page's filters**; the remembered page is updated on every Apply (`getCatalogFiltered`) and reset when an unfiltered catalog session starts (`getCatalogList`):

**Page picker (always present, first)** — 4 options: Bookstack (書庫) / Rankings (排行榜) / Booklists (書單) / ⚡ Translator Self-Test (diagnostics, §2.6)

**Bookstack page — 4 filters, mirroring the `/bookstack/` sidebar in site order (類型 · 作品狀態 · 分類 · 標籤):**

| Filter | Options | Notes |
|---|---|---|
| `gender` — Type (類型) | 3 | All / Male (男生) / Female (女生) → `gender=boy\|girl` query param |
| `end_status` — Status (作品狀態) | 3 | All / Ongoing (連載) / Completed (完結) → `end=1\|2` query param |
| `category` — Category (分類) | 14 | All + the 13 `/bookstack/<cat>/` path segments (xuanhuan, xiuzhen, dushi, lishi, wangyou, kehuan, nvpin, lingyi, tongren, junshi, xuanyi, chuanyue, other) — all verified live |
| `tag` — Tags (標籤) | 101 | None + the site's 100-tag cloud. **Each tag has a curated English name** — e.g. 穿越 → *Transmigration*, 豪門總裁 → *Wealthy CEO*, 打臉 → *Face-Slapping*, 扮豬吃虎 → *Playing Pig to Eat Tiger*. Tag VALUES remain the raw site tags (they are URL-encoded into `/tags/` URLs — only labels changed, so saved filter state keeps working) |

**Booklists page — 2 filters, mirroring the `/shudan/` sidebar:**

| Filter | Options | Notes |
|---|---|---|
| `gender` — Type (類型) | 3 | All / Male / Female → `/shudan/boy\|girl/` path |
| `shudan_sort` — Sort (排序) | 3 | Latest (最新發佈) / Most Favorited (最多收藏) / Editor's Picks (小編推薦) |

**Rankings page — 3 filters, mirroring the `/ranking.html` sidebar (閱讀榜/潛力榜/風雲榜 sections + 女生/男生 tabs):**

| Filter | Options | Notes |
|---|---|---|
| `rank_type` — Ranking Type (榜單類型) | 3 | Reading Rank (閱讀榜, t=2) / Potential Rank (潛力榜, t=1) / Trending Rank (風雲榜, t=8) |
| `rank_gender` — Gender (性別) | 2 | Female (女生, g=0) / Male (男生, g=1) — the site's gender tabs |
| `rank_category` — Ranking Category (榜單分類) | 40 | Default (per-gender landing category) + 34 gender-matched categories (value `<gender>-<cid>` so the URL is always gender-matched — never triggers the site's cross-gender 301) + the 5 風雲榜 sub-ranks as "Trending · …" entries (Hot / New Books / Completed / Most Collected / Recently Updated, cid 8001–8005, 40 entries each) |

Mismatched combinations degrade safely: a Trending sub-rank selected while on a Reading/Potential type falls back to the per-gender default category, and vice versa; legacy saved `rank_type` values (8001–8005) fold into the Trending type. Stale keys from a previous page's sheet are simply ignored.

**Why not one combined sheet?** NoveLA's filter UI renders whatever `getFilterList` returns and cannot show/hide sections dynamically (verified: `SourceCatalogViewModel` fetches the list once per catalog-screen session). An earlier draft stacked all 8 sections into one sheet with "Category — Bookstack only"-style labels; page-scoping replaces that. Practical flow: switching Page inside the sheet applies instantly (new catalog), and the reduced filter set appears the next time the source screen is opened (back out of the catalog and re-enter — that is when the app re-fetches the list).

**Mode-aware labels (new in 1.0.4):** every label — section headers and options, all 100 tags included — is built by one helper at `getFilterList()` call time (labels rebuild when the source screen is opened/re-opened):

- **Raw mode:** bilingual `English (中文)` — keeps the site flavor, e.g. `Transmigration (穿越)`
- **Translator mode:** **English only**, e.g. `Transmigration` — no Chinese counterparts, matching the user's translated UI
- Latin-only tags (`HE`, `1V1`) collapse to their English name in both modes (no pointless `HE (HE)`)

### 2.2 Filtered browse (`getCatalogFiltered`)

All URL shapes verified live (2026-08-28):

| Surface | URL | Notes |
|---|---|---|
| Bookstack | `/bookstack/[<cat>/]?page=N[&gender=boy\|girl][&end=1\|2]` | 18 items/page |
| Tag browse | `/tags/[boy\|girl/]<urlencoded tag>/?page=N` | Tag overrides category; gender path goes BEFORE the tag (verified: reversed order 404s) |
| Rankings | `/ranking/<g>-<t>-<cid>.html` | g: 0=女生 1=男生 (from the Gender filter); t: 2=閱讀 1=潛力 8=風雲 (from the Ranking Type filter); an explicitly picked (F)/(M) category carries its own gender (cids are gender-specific, like the site sidebar); 風雲榜 takes its sub-rank cid (8001–8005) from the Trending · category entries; 30 (40 for trending) items, no pagination; items prefixed `#N` with their rank; some (cat, type) combos are legitimately empty on the site — degrades gracefully |
| Booklists | `/shudan/[boy\|girl/][new\|fav\|commend/]?page=N` | Path order matters (gender BEFORE sort — `/shudan/fav/boy/` is a 404); 20 lists/page |

**Booklist detail pages open like a book** (new in 1.1.0+): title / cover / description come from the booklist header (same `h1.title` / `.cover img` / `div.intro` selectors as book pages), and the "chapter list" is the booklist's novels (title + score). Opening a novel "chapter" fetches that novel's first chapter as a sampler and appends a bilingual footer telling the reader which original title to search for to continue the full book.

Every list surface shares `ul.list li.media` cards + `li.next.pagination-link` pagination — one parser handles all of them.

### 2.3 Translator mode (`getSettingsSchema`)

Three settings, mirroring `mtl/wtrlab.lua`'s established pattern:

| Setting | Key | Options |
|---|---|---|
| Mode (模式) | `novel543_mode` | Raw (原文) / Translator (翻譯模式) |
| Translate To (目標語言) | `novel543_tlang` | 15 languages (en, es, pt, ru, fr, de, tr, ar, id, th, vi, ja, ko, hi, ur) |
| Translate Chapter Titles (章節標題) | `novel543_tr_chapters` | On / Off (default On) |

**What gets translated** (in Translator mode): catalog / search / ranking / booklist item titles, book title (rendered `English (原文)`), description (≤4,000 chars), genres & status (static English map when target = English, API otherwise), chapter titles (batched ≤40/request, toggleable), filter labels (English-only, §2.1), booklist count suffixes (`(N books)`), and search queries typed in a non-Chinese language (translated to zh-TW first — the site indexes Traditional titles — with a zh-CN retry if nothing is found).

**What is NEVER translated:** chapter body text. NoveLA's built-in reader translator owns that job.

**Engine chain** (each step only on the previous step's failure):
1. POST `translate.googleapis.com/translate_a/t` (client `dict-chrome-ex`, repeated `q` params, no API key)
2. POST `clients5.google.com/translate_a/t`
3. GET `translate.googleapis.com/translate_a/t` (long chunks split into ≤1,400-char URL groups — survives middleboxes that mangle POST bodies)
4. GET `clients5.google.com/translate_a/t`
5. MyMemory (api.mymemory.translated.net, anonymous per-item fallback)
6. Google `gtx` single (per item, first 6 of a failed chunk — blocked on some datacenter IPs but works from residential/mobile, i.e. real devices)

**Resilience (nothing here can break browsing):**
- 4,000-entry session translation cache
- Failure circuit breaker: 3 consecutive failed batches → pass-through for 10 minutes → half-open (millisecond-accurate — NoveLA's `os_time()` returns **milliseconds**, verified in `LuaSourceLoader.kt`; probe-counter fallback when no clock exists)
- Every translator entry point is `pcall`-armored — a Lua error degrades to untranslated text, never a failed page
- Empty-string API results map back to originals (Google returns `""` for an empty `q`; one empty title must not fail a whole 18-item page)
- On ANY failure the original text is returned

### 2.4 Book metadata

| Function | 1.0.3 | 1.0.4 |
|---|---|---|
| `getBookTitle` / `getBookCoverImageUrl` / `getBookDescription` | per-call page fetch | Same selectors, served from a 60 s / 12-page session cache — **one fetch per book open** (was 6–8) |
| `getBookGenres` | ✗ missing | **NEW** — `og:novel:category` meta tag; translated in Translator mode |
| `getBookStatus` | `og:novel:status` (連載/完結) | ✓ unchanged (+ translated: Ongoing/Completed) |
| `getBookLastUpdate` | `og:novel:update_time` | ✓ unchanged |
| `getChapterListHash` | date-granularity `p.meta` label (missed same-day updates) | **`update_time \| latest_chapter_name`** — catches new chapters AND same-day retranslations |
| Chapter text | 溫馨提示 notice saved into every chapter | **Notice stripped** (`div.gadBlock` / `div.adBlock` / `script` / `ins` removed from `div.content`) |

### 2.5 Chapter list & chapter text

Unchanged pipelines, preserved verbatim from 1.0.3: `GET <bookUrl>/dir` → `ul.all li a` (all chapters, one page); multi-page chapter following (`<file>_2.html`, `<file>_3.html`… linked from the current page, cap 20 sub-pages). Only the ad/notice removal (above) and the optional chapter-title translation were added.

### 2.6 ⚡ Translator Self-Test (diagnostics surface)

Pick "⚡ Translator Self-Test" under the Page picker and the catalog becomes a live diagnostics report: plugin name + version banner (proves which source is loaded — a stale repository copy cannot render this), mode + target language, `os_time` / `http_post` / `json_parse` availability, each translation engine with latency and a sample, an end-to-end batch check, and a verdict line naming the failing step. Runs in raw mode too, so a broken on-device setup can be diagnosed without logcat.

### 2.7 Unchanged from 1.0.3 (regression audit)

This is the section a reviewer will care about most. **Nothing user-facing was deleted.**

- All 10 original functions kept their names, selectors, and raw-mode behavior (verified by regression tests written against 1.1.0 and still passing).
- `id = "novel543"`, `baseUrl`, `language = "zh"`, `icon` — unchanged.
- Search still uses `GET /search/<urlencoded query>` (the site's own JS redirect target); the Cloudflare challenge on that path is handled by NoveLA's `CloudfareVerificationInterceptor` on real devices.
- **No `cf_options`** — deliberately absent. `cf_options = { whitelist = true }` would disable NoveLA's Cloudflare/WebView auto-bypass for this host (it sits in front of `/search/`). The header comment documents this landmine.
- No third-party runtime dependencies, no proxies, no API keys — pure Lua + the NoveLA plugin API.

---

## 3. Testing — what was run before this PR

### 3.1 Syntax / completeness
LuaJ 3.0.1 syntax check: `SYNTAX OK — compiles cleanly (71,189 bytes, 1,639 lines)`; 14/14 functions defined (`getBookRating` intentionally absent — optional in NoveLA, the site has no rating system).

### 3.2 Live suite — **196 PASS / 0 FAIL / 1 SKIP**
Custom Java harness (`Novel543Test.java`, LuaJ 3.0.1 sandbox emulating the NoveLA plugin API, HTTP routed through curl — the site's Cloudflare fingerprints TLS stacks so plain Java HTTP gets challenged; the real app uses OkHttp and is unaffected). The suite covers:

- Metadata, the page-scoped filter sheets (option counts, keys, types, site-sidebar ORDER), raw-mode catalog pages 1/2, gender/end-status/category/tag/combination browse (all live)
- **Page-scoping tests (v1.0.4):** bookstack sheet shows exactly its 4 filters and leaks no ranking/booklist keys; applying the Rankings page switches the sheet to Ranking Type/Gender/Ranking Category (and back); the Booklists page switches to Type/Sort; an unfiltered `getCatalogList` session resets the sheet to bookstack; the self-test page shows the Page picker alone; stale foreign keys from an old sheet are ignored; Page-picker defaults follow the browsed page on every surface
- **v1.0.4 label tests:** all 100 tag values stay raw site tags; no tag label is Chinese-only anymore; bilingual format in raw mode; spot checks (穿越/豪門總裁/打臉/HE/1V1); **zero CJK in any filter label in Translator mode on every surface** (bookstack, rankings, booklists — every option incl. 100 tags); tag values unchanged across a mode toggle
- Ranking URL builder: reading/potential/trending types × explicit vs default categories × gender tabs; legacy `rank_type` 8001–8005 folding; mismatched combos falling back safely (all live)
- Live Google-translation end-to-end: 18/18 catalog titles translated, book title `English (原文)` format, description, genres, 145 chapter titles batched, chapter text **not** translated
- Fault injection: POST blocked → GET fallback works; all engines dead → pages load untranslated + breaker opens/half-opens with millisecond math; empty-string batch results; missing `os_time` on old app builds
- Page cache: 7 metadata calls → exactly 1 network fetch
- Rankings (30 items, `#N` prefixes), booklists (20/page, `(N books)` suffix), self-test report structure

The single SKIP is `/search/` results (Cloudflare-challenged from datacenter IPs; the search path itself is unchanged from 1.0.3 except for the optional query-translation pre-step and works on real devices via the CF interceptor).

### 3.3 Cross-plugin regression
`mtl/wtrlab.lua` v1.1.7: syntax OK, all 15 functions, `cf_options` absent — untouched by this change.

---

## 4. Site / API reference (reverse-engineered, all verified live 2026-08-28/29)

| Surface | Details |
|---|---|
| Catalog | `GET /bookstack/[<cat>/]?page=N[&gender=boy\|girl][&end=1\|2]` — 18 items/page, HTML only (no JSON API); out-of-range pages clamp to the last page with HTTP 200; exact end detection = `li.next.pagination-link:not(.disabled)` |
| Tags | `GET /tags/[boy\|girl/]<urlencoded tag>/?page=N` — gender path BEFORE the tag; no category/end params on tag pages; the 100-tag sidebar cloud is identical everywhere |
| Rankings | `GET /ranking/<g>-<t>-<cid>.html` — g: 0=女 1=男; t: 2=閱讀 1=潛力; 風雲榜 uses `t=8` with cid 8001–8005; 30/40 items, no pagination; `cid=0` or cross-gender cid → 301 |
| Booklists | `GET /shudan/[boy\|girl/][new\|fav\|commend/]?page=N` — path order matters (gender BEFORE sort); detail pages reuse the book-page selectors + `li.media` cards with `span.score` |
| Search | `GET /search/<kw>` — behind Cloudflare; solved on-device by NoveLA's interceptor |
| Book page | `h1.title`, `.cover img`, `div.intro`, `og:novel:{category,author,book_name,status,update_time,latest_chapter_name}` meta tags |
| Chapter list | `GET <bookUrl>/dir` → `ul.all li a` |
| Chapter text | `div.content` (+ `div.gadBlock`/`div.adBlock`/`script`/`ins` to remove); long chapters paginate as `<file>_2.html`… |

---

## 5. Merge notes for the maintainer

1. **Display name.** The shipped file uses `name = "Novel543 Full"` so it can be imported and run **side-by-side** with the repository's v1.0.3 during testing: NoveLA resolves sources by **base URL** (`Scraper.getCompatibleSourceCatalog` returns the first match) and rejects a local re-import under a name that already exists — with two identically-named "Novel543" sources installed, the app could keep opening the old one no matter which entry was tapped. **When merging, `name` may be reverted to `"Novel543"`** (one line) — existing repository users then update 1.0.3 → 1.0.4 in place, which is the intended end state. If the rename is kept, existing users would see a "new" source next to the stale one instead of an in-place update, so reverting is recommended.
2. **Version.** `1.0.4` continues the upstream version line (1.0.3 → 1.0.4). The internal dev builds 1.1.0–1.2.2 (documented in the file header) were incremental deliveries of this same feature set to a single tester and are all superseded by this file.
3. **No new dependencies.** Pure Lua + the documented NoveLA plugin API (`http_get`, `http_post`, `url_encode`, `url_resolve`, `html_select*`, `html_attr`, `html_remove`, `html_text`, `json_parse`, `string_*` helpers, `get_preference`, `os_time`). Degrades gracefully on older app builds that lack `http_post` / `os_time` (GET fallback / probe-counter breaker).

---

## 6. Upgrade notes for end users

- **Updating an existing local import:** NoveLA rejects re-importing a file under a name that is already installed. Update in place instead: Extensions → (the source's row) → Edit Lua → select all → paste the new file → Save. (Or uninstall the old local copy and import fresh.)
- **If both the repository "Novel543" (v1.0.3) and this plugin are installed:** disable/uninstall the repository one — with two sources sharing `https://www.novel543.com/`, the app may open either one when navigating by base URL. The self-test banner (Page picker → ⚡ Translator Self-Test, line 1) shows which source is actually loaded.
- **Filter sheets are page-scoped:** switching Page inside the filter sheet applies immediately; the new page's reduced filter set appears the next time the source screen is opened (back out of the catalog and re-enter — the app fetches the filter list once per screen session).
- **After toggling the mode** in Settings, pull-to-refresh the catalog — already-loaded pages are not retranslated, and filter-sheet labels pick up the new language the next time the source screen is opened.

---

## 7. Known limitations

- `/search/` is Cloudflare-challenged from datacenter IPs; on real devices NoveLA's Cloudflare interceptor solves it. Search behavior is otherwise unchanged from 1.0.3.
- The Google `dict-chrome-ex` endpoint is unofficial and unauthenticated by design (no key to leak); the 6-step fallback chain, the cache, and the pass-through contract keep browsing functional when any subset of engines is unreachable. The `gtx` single-item step is expected to fail from datacenter IPs and succeed from residential/mobile ones.
- Some (ranking category × rank type) combinations are legitimately empty on the site itself — the plugin returns an empty list for them, exactly like the site.
- Machine translation quality is what it is: titles/genres/status use a curated English map where one exists (including all 100 filter tags); everything else goes through the API and is cached per session.
- The booklist-as-book "chapters" deliver each novel's first chapter as a sampler with a pointer to the original title — a full booklist-to-library import is out of scope for a source plugin.

---

## 8. Files in this PR

| File | Contents |
|---|---|
| `zh/novel543.lua` | The plugin (1,639 lines, version 1.0.4) |

Optional (not part of the source repo, available on request): `Novel543Test.java` — the 196-check live test harness (LuaJ 3.0.1 sandbox emulating the NoveLA plugin API) used to validate every claim in this PR.

---

## 9. Reviewer checklist

- [ ] `luaj` syntax check passes; 14 functions defined; `id`/`baseUrl`/`language`/`icon` unchanged
- [ ] Raw mode: all v1.0.3 behaviors intact (catalog, search, book details, chapter list, chapter text minus the notice)
- [ ] Page-scoped filters: each page's sheet shows ONLY that page's filters (bookstack 4, booklists 2, rankings 3 + the Page picker); tag values are the raw site tags; labels bilingual in raw mode, English-only in Translator mode on every surface
- [ ] Ranking builder: type/gender/category semantics; legacy 8001–8005 values fold into Trending; mismatched combos fall back safely
- [ ] Translator mode: titles/description/genres/status/chapter-titles translated; **chapter body text untouched**; all engines dead → pages still load (pass-through)
- [ ] No `cf_options` anywhere in the file
- [ ] Version `1.0.4`; decide on `name` (recommend reverting to `"Novel543"` at merge time, see §5.1)
