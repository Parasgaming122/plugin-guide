#!/usr/bin/env python3
"""MAINTENANCE.md — oop v1.1.0 updates: card, Part 0.8, test commands,
gotchas #50 update + new #51-#53."""

PATH = "/home/z/my-project/download/MAINTENANCE.md"

with open(PATH, encoding="utf-8") as f:
    s = f.read()

# ── 1. quick-reference card, OOP column ────────────────────────────────────
old = "`oop.lua` (1,040 lines, NEW 2026-09-19)"
assert s.count(old) == 1
s = s.replace(old, "`oop.lua` (1,262 lines, NEW 2026-09-19)")

old = ("**1.0.0 (2026-09-19)** — initial release (CF site via translate-proxy "
       "research, paginated catalogs, translator)")
assert s.count(old) == 1
s = s.replace(old, ("**1.1.0 (2026-09-19)** — TOC Cloudflare-solver-storm fix "
                    "(parsePage + early-abort walk + persistent page cache) on "
                    "1.0.0 (CF site via translate-proxy research, translator)"))

old = "`test-harness/OopTest.java` (**59 mock**, cleaned translate-proxy fixtures)"
assert s.count(old) == 1
s = s.replace(old, ("`test-harness/OopTest.java` (**97 mock**, cleaned "
                    "translate-proxy fixtures + synthesized 5-page TOC battery)"))

# ── 2. test commands: add the test-harness (bixiange/oop) block ────────────
old = """# javac is NOT installed in this environment — compile with the bundled Eclipse compiler:
#   java -jar lib/ecj.jar -source 19 -target 19 -cp "lib/luaj-jse-3.0.1.jar:lib/jsoup-1.17.2.jar:lib/gson-2.10.1.jar" -d . <File>.java
#   java -cp ".:lib/*" <File> <args>
```"""
assert s.count(old) == 1
s = s.replace(old, """# javac is NOT installed in this environment — compile with the bundled Eclipse compiler:
#   java -jar lib/ecj.jar -source 19 -target 19 -cp "lib/luaj-jse-3.0.1.jar:lib/jsoup-1.17.2.jar:lib/gson-2.10.1.jar" -d . <File>.java
#   java -cp ".:lib/*" <File> <args>

# Bixiange + OOP — run from /home/z/my-project/test-harness/ (jars sit flat there)
java -jar ecj.jar -source 19 -target 19 -cp "luaj-jse-3.0.1.jar:jsoup-1.23.1.jar:gson-2.14.0.jar" -d . OopTest.java
java -cp ".:luaj-jse-3.0.1.jar:jsoup-1.23.1.jar:gson-2.14.0.jar" OopTest
java -jar ecj.jar -source 19 -target 19 -cp "luaj-jse-3.0.1.jar:jsoup-1.23.1.jar:gson-2.14.0.jar" -d . BixiangeTest.java
java -cp ".:luaj-jse-3.0.1.jar:jsoup-1.23.1.jar:gson-2.14.0.jar" BixiangeTest
```""")

# ── 3. Part 0.8 title + oop section v1.1.0 update ──────────────────────────
old = "## Part 0.8 — Bixiange + OOP plugins (`bixiange.lua` / `oop.lua` v1.0.0) — quick map (2026-09-19)"
assert s.count(old) == 1
s = s.replace(old, ("## Part 0.8 — Bixiange + OOP plugins "
                    "(`bixiange.lua` v1.0.0 / `oop.lua` v1.1.0) — quick map (2026-09-19)"))

old = """- **Chapter catalogs paginated 30/page via `?p=N`** — the `.chap-pager`
  select options enumerate every page; getChapterList walks them all
  (element `.attr("value")` accessor)."""
assert s.count(old) == 1
s = s.replace(old, """- **Chapter catalogs paginated 30/page via `?p=N`** — the `.chap-pager`
  select options enumerate every page (any page's select yields totalPages;
  element `.attr("value")` accessor). v1.1.0: served through
  `parsePage(bookUrl, page)` (engine walks pages + stops at first failure +
  refreshes incrementally); `getChapterList` fallback ABORTS at the first
  failed page; a persistent `oop_toc_<id>` page cache (LRU 5 books / 100KB)
  serves immutable interior pages (site only APPENDS chapters) without
  network, resumes broken walks, and serves a stale TOC when the site is
  unreachable. Chapter URLs use global article ids — NOT synthesizable
  (probed `?p=all`: no full-TOC endpoint).""")

# ── 4. gotchas: #50 refresh + new #51-#53 ──────────────────────────────────
old = """**#50 — oop.tw specifics**: ad DIVs are nested INSIDE `article#article`
(extract `<p>` elements only); book catalogs paginate 30/page via `?p=N`
(select options enumerate pages — walk them all); the catalog data itself
sometimes swaps adjacent chapters (re-sort only when EVERY title parses to
a number); search caps at 100 results on one page with NO pagination."""
assert s.count(old) == 1
s = s.replace(old, """**#50 — oop.tw specifics**: ad DIVs are nested INSIDE `article#article`
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
cache never stores translated text.""")

with open(PATH, "w", encoding="utf-8") as f:
    f.write(s)

print("OK: MAINTENANCE.md updated for oop v1.1.0")
