#!/usr/bin/env python3
"""Rewrite oop_pull_request.md as the v1.1.0 release (TOC Cloudflare-storm
fix), demoting the v1.0.0 material to context sections."""

PATH = "/home/z/my-project/download/oop_pull_request.md"

with open(PATH, encoding="utf-8") as f:
    s = f.read()

# ── title + TL;DR ───────────────────────────────────────────────────────────
i = s.index("## 1. What the site is")
head = """# oop.lua v1.1.0 — chapter-list Cloudflare fix ("solver storm")

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

"""
s = head + s[i:]

# ── retitle remaining doc as context, fix feature + testing sections ───────
s = s.replace("## 1. What the site is", "## 1. Context: what the site is (v1.0.0 research)")
s = s.replace("## 2. Research technique", "## 2. Context: research technique")
s = s.replace("## 3. Site quirks", "## 3. Context: site quirks")
s = s.replace("## 4. Features", "## 4. Features (v1.0.0, unchanged unless noted)")

s = s.replace(
    """- **Chapter catalogs**: every `?p=N` page walked via the chap-pager select
  options (books with 870+ chapters fetch all their catalog pages).""",
    """- **Chapter catalogs** (v1.1.0): paginated via `parsePage()` — the engine
  stops at the first failed page and refreshes incrementally; a persistent
  per-book page cache serves immutable interior pages without network and
  resumes broken walks (see section 0). Chapter URLs use global article
  ids, so pages must be enumerated — there is no single-request full-TOC
  endpoint (probed `?p=all`: not supported).""")

s = s.replace(
    "- **Search**: one-shot GET (≤100 results)",
    "- **Search**: one-shot GET (≤100 results)")

# features: hash line update
s = s.replace(
    "  last update, chapter-list hash = update-time + chapter count.",
    "  last update, chapter-list hash = update-time + totalPages + last\n  chapter number (v1.1.0).")

# ── testing section rewrite ────────────────────────────────────────────────
i = s.index("## 6. Testing")
j = s.index("## 7. Known limits")
testing = """## 6. Testing — 97 checks, all green

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

"""
s = s[:i] + testing + s[j:]

# ── known limits ────────────────────────────────────────────────────────────
s = s.replace(
    """- **Cloudflare**: from datacenter/shared IPs the site challenges everything.
  On real devices the engine's hidden WebView solves it (or the manual
  WebView appears once). If covers break while the site challenges images,
  keep the default wsrv.nl proxy.""",
    """- **Cloudflare**: from datacenter/shared IPs the site challenges everything.
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
  chapter number).""")

with open(PATH, "w", encoding="utf-8") as f:
    f.write(s)

print("OK: oop_pull_request.md rewritten as v1.1.0,", len(s), "chars")
