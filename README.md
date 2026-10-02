# NoveLA Plugin Suite — 7 Sources, Fully Tested & Live-Verified

**Archive date:** 2026-09-30 (rev 2) · **All suites green: 830 checks, 0 failures** · All 7 sites visited and verified live on this date.

Seven production Lua source plugins for the [NoveLA](https://github.com/HnDK0/NoveLA) reader app, covering Chinese / zh-TW / MTL novel sites — each with a full offline test harness, live-verified selectors, and maintenance documentation.

> **rev 2 note:** all plugins now ship `version = "x.y.z"` as a **string literal** — NoveLA's extension manager parses that line with a regex that only matches quoted values; the old `version = VERSION` variable form fell back to "1.0.0" and created update/re-import conflicts. Fixed across 69shubaTw, bixiange, novel543 and oop (wtrlab and wuxiabox were already literal). New in rev 2: **fanqietc** (FanqieTC / 番閒) — the first JSON-API plugin in the suite, with health-checked mirror failover and a full diagnostics self-test.

---

## Quick start

1. Pick a plugin from [`plugins/`](plugins/) below.
2. In NoveLA: **Settings → Sources → Add external source**, load the `.lua` file.
3. Per-plugin options (translation mode, covers, mirrors, tag search…) live in that source's settings screen — see each plugin's doc in [`docs/`](docs/).

---

## `plugins/` — the seven production plugins

| Plugin | Version | Site | What it is |
|---|---|---|---|
| [`plugins/fanqietc.lua`](plugins/fanqietc.lua) | 1.0.0 | fanqietc.com (番閒) | zh source for the **Fanqie Novel** catalog via the site's **JSON backend**: 7 rank boards + recommendations + search, health-checked 10-mirror failover on the reading path, retry + visible degraded pages on the backend's own list endpoints, novel543 translator, ⚡ Self-Test diagnostics |
| [`plugins/wtrlab.lua`](plugins/wtrlab.lua) | 1.2.1 | wtr-lab.com | MTL (Chinese→English) source: novel-finder filters, 888-tag search, local AES-GCM chapter decryption, AI / Raw / Web+ modes |
| [`plugins/novel543.lua`](plugins/novel543.lua) | 1.0.5 | novel543.com (稷下書院) | zh source: bookstack/ranking/shudan browsing, page-scoped filters, built-in Translator mode (15 targets) |
| [`plugins/wuxiabox.lua`](plugins/wuxiabox.lua) | 2.3.0 | wuxiabox.com + wuxiaspot.com mirror | en source: curated 755-tag picker, smart mirror switching with persistent circuit breaker, 502 self-heal |
| [`plugins/oop.lua`](plugins/oop.lua) | 1.1.0 | oop.tw | zh-TW source: Cloudflare-solver-storm fix (paginated `parsePage` TOC + early-abort walk + persistent page cache) |
| [`plugins/bixiange.lua`](plugins/bixiange.lua) | 1.0.1 | bixiange.top + bxg123.cc mirror | zh source on a GB2312/EmpireCMS site: end-to-end GBK handling, mirror failover, translator |
| [`plugins/69shubaTw.lua`](plugins/69shubaTw.lua) | 1.3.0 | 69shuba.tw | zh-TW source behind Tencent EdgeOne: capital-I `/Indexlist/` WAF bypass (no solver storms), 100-ch/page catalogs, protected-span harvesting |

## `docs/` — documentation

| Doc | What it covers |
|---|---|
| [`docs/MAINTENANCE.md`](docs/MAINTENANCE.md) | **The master guide** — architecture maps of all plugins, site facts, engine contracts, triage workflows, the full gotcha list, and the 2026-09-30 seven-site sweep report (Part 0.95) |
| [`docs/fanqietc_pull_request.md`](docs/fanqietc_pull_request.md) | FanqieTC v1.0.0 release notes — JSON-API architecture, mirror failover, the version-literal rule, 86/86 live tests |
| [`docs/wtrlab_README.md`](docs/wtrlab_README.md) | WTR-Lab user guide (install, settings, modes) |
| [`docs/wtrlab_pull_request.md`](docs/wtrlab_pull_request.md) | WTR-Lab v1.2.1 change notes |
| [`docs/wtrlab_50ch_test.md`](docs/wtrlab_50ch_test.md) | WTR-Lab 50-chapter end-to-end test report (ai/web/webplus modes) |
| [`docs/novel543_pull_request.md`](docs/novel543_pull_request.md) | Novel543 v1.0.4/1.0.5 change notes (page-scoped filters, poster fix) |
| [`docs/wuxiabox_pull_request.md`](docs/wuxiabox_pull_request.md) | WuxiaBox v2.3.0 change notes (mirror switcher, tag curation) |
| [`docs/oop_pull_request.md`](docs/oop_pull_request.md) | OOP v1.1.0 change notes (TOC solver-storm fix) |
| [`docs/bixiange_pull_request.md`](docs/bixiange_pull_request.md) | Bixiange v1.0.1 change notes (incl. the 2026-09-30 URL-scheme change report) |
| [`docs/69shubatw_pull_request.md`](docs/69shubatw_pull_request.md) | 69shubaTw v1.3.0 change notes (EdgeOne case-sensitive WAF discovery) |

## `test/` — test harnesses & fixtures

See [`test/README.md`](test/README.md) for how to compile and run everything (incl. the fixture path notes).
**Suites (all green 2026-09-30):** LuaTest 66/66 · Novel543Test 197/197 · WuxiaboxTest 147/147 · OopTest 97/97 · BixiangeTest 90/90 · S69TwTest 127/127 · S69RealSeed 20/20 · **FanqietcTest 86/86**.

| File | Suite for | What it proves |
|---|---|---|
| [`test/FanqietcTest.lua`](test/FanqietcTest.lua) | fanqietc | 86 live checks: rankings ×7, search, 4051-chapter book end-to-end (incl. 番外), translator, mirror failover, degraded-state pages |
| [`test/NoveLaHarness.java`](test/NoveLaHarness.java) | all | the faithful NoveLA Lua sandbox harness (runs `.lua` test scripts with real networking) |
| [`test/LuaTest.java`](test/LuaTest.java) | wtrlab | live API flow + mock decryption/translation batteries |
| [`test/Novel543Test.java`](test/Novel543Test.java) | novel543 | live site + translator fault-injection (hermetic GET fallback) |
| [`test/WuxiaboxTest.java`](test/WuxiaboxTest.java) | wuxiabox | 147 fixture tests incl. mirror circuit-breaker restarts |
| [`test/OopTest.java`](test/OopTest.java) | oop | 97 checks: catalog/cards/TOC pagination/caches/breaker |
| [`test/BixiangeTest.java`](test/BixiangeTest.java) | bixiange | 90 checks incl. T23 — the live-captured 2026-09-30 URL scheme |
| [`test/S69TwTest.java`](test/S69TwTest.java) | 69shubaTw | 127 checks: real /Indexlist/ fixtures, challenge detection, request budgets |
| [`test/S69RealSeed.java`](test/S69RealSeed.java) | 69shubaTw | 20 real-capture end-to-end checks (450-chapter book) |
| [`test/SyntaxCheck.java`](test/SyntaxCheck.java) | all | load + function-surface check for any plugin |
| [`test/run_all.sh`](test/run_all.sh) | all | one command: compile + run all 7 suites |
| [`test/lib/`](test/lib), [`test/lib2/`](test/lib2) | — | jars: luaj-jse, jsoup, gson, ecj compiler, okhttp/okio/kotlin-stdlib |
| [`test/fixtures/`](test/fixtures) | — | every HTML/JSON fixture the suites read (wuxiabox/, newsites/, 69shubatw/, wtrlab samples) |
| [`test/logs-20260930/`](test/logs-20260930) | — | full output logs of the final green run |

## `scripts/` — build pipeline & research tooling

The assembly pipeline (source parts → final plugin), fixture generators, live-capture tooling, and the research probes used to map each site. Highlights:

| Script | Purpose |
|---|---|
| [`scripts/run_all_tests.sh`](scripts/run_all_tests.sh) | compile + run all 7 suites, print summary |
| [`scripts/live_site_sweep.py`](scripts/live_site_sweep.py) | visit all 6 sites, verify plugin markers |
| [`scripts/quick_probe.py`](scripts/quick_probe.py) | one-URL marker probe helper |
| [`scripts/capture_bixiange_2026.py`](scripts/capture_bixiange_2026.py) | captured the 2026-09-30 bixiange URL-scheme fixtures |
| [`scripts/assemble_69shubatw_v130.py`](scripts/assemble_69shubatw_v130.py) | splice 69shubaTw v1.3.0 from source parts |
| [`scripts/assemble_bixiange.py`](scripts/assemble_bixiange.py) / [`assemble_oop.py`](scripts/assemble_oop.py) / [`assemble_plugin.py`](scripts/assemble_plugin.py) | assemble bixiange / oop / wuxiabox from source parts |
| [`scripts/gen_69shubatw_v130_fixtures.py`](scripts/gen_69shubatw_v130_fixtures.py) | de-GT-ify real captures into test fixtures |
| [`scripts/build_structured_zip_20260930.py`](scripts/build_structured_zip_20260930.py) | builds THIS archive |
| [`scripts/`](scripts/) (all 100+) | tag pipelines (harvest/curate/index), patch/splice history per version, backup-zip builders, site research probes |

## `source-parts/` — hand-written Lua sources

The plugins' maintainable source parts (the top-level `.lua` files in `plugins/` are assembled from these):

- [`source-parts/69shubatw/`](source-parts/69shubatw/) — part1–4 + the v1.3.0 TOC core
- [`source-parts/bixiange/`](source-parts/bixiange/) — part1–4
- [`source-parts/fanqietc/`](source-parts/fanqietc/) — part1 (header/metadata) · part2 (API layer + mirror failover) · part3 (translator core) · part4 (catalog + self-test) · part5 (book/chapters/settings) — assembled by [`scripts/fanqietc_plugin/assemble_fanqietc.py`](scripts/fanqietc_plugin/assemble_fanqietc.py)
- [`source-parts/oop/`](source-parts/oop/) — part1–3
- [`source-parts/wuxiabox/`](source-parts/wuxiabox/) — part1–4

---

## The 2026-09-30 verification sweep

Every site was visited live on archive day; every selector was checked against current markup:

- **fanqietc.com** — **NEW** (rev 2). JSON backend `api.fanqietc.com` mapped end-to-end: 7 rank boards, 2 recommend sections, fuzzy search (~50 hits, single page), detail/directory/content proxy actions, /status mirror health, creation_status semantics ('0' = finished), single-`\n` chapter paragraphs. Observed a 25-minute outage of the backend's own /rank//search upstream while sg-1/sg-2 served every proxy request — the plugin's split failure-domain design (mirror failover for reading, retry + degraded pages for discovery) is built around exactly this.
- **wtr-lab.com** — APIs unchanged (`_next/data` search, `api/chapters/{id}`, `api/reader/get` with service strings + AES-GCM `arr:` payload).
- **novel543.com** — book URLs moved to `/{bookId}/`; the plugin follows site hrefs so nothing broke. Multi-page chapters verified live (`8096_1.html` → `8096_1_2.html`).
- **wuxiabox.com / wuxiaspot.com** — unchanged (CF challenge is datacenter-only; devices pass).
- **oop.tw** — unchanged (`/abooka/`, `/areada/`, `?p=N` catalogs).
- **bixiange.top** — **URL scheme changed** (`/cat/{id}/` is now 404; books are `/{cat}/{id}`); plugin survived with **zero code changes** (href-following design), documented in v1.0.1 + 14 new live-capture checks.
- **69shuba.tw** — the capital-I `/Indexlist/` WAF bypass still returns 200 on all catalog pages.

Full report: [`docs/MAINTENANCE.md`](docs/MAINTENANCE.md) → Part 0.95.
