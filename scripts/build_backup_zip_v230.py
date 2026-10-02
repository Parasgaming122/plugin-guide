#!/usr/bin/env python3
"""Build backup zips for 2026-09-19 (wuxiabox v2.3.0 session).

Outputs:
  download/wuxiabox-backup-20260919.zip        (wuxiabox-focused)
  download/noveLA-plugins-backup-20260919.zip  (all plugins + docs + harness)
"""
import os, zipfile, hashlib

BASE = "/home/z/my-project"

def add_file(files, src, arc):
    p = os.path.join(BASE, src)
    if os.path.exists(p):
        files.append((arc, p))
    else:
        print(f"  [WARN] missing: {src}")

def build(out_path, files, manifest):
    seen, uniq = set(), []
    for arc, p in files:
        if p in seen:
            continue
        seen.add(p)
        uniq.append((arc, p))
    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("README.txt", manifest)
        for arc, p in uniq:
            z.write(p, arc)
    with zipfile.ZipFile(out_path) as z:
        bad = z.testzip()
        n = len(z.namelist())
    digest = hashlib.sha256(open(out_path, "rb").read()).hexdigest()[:16]
    size = os.path.getsize(out_path)
    print(f"OK {os.path.basename(out_path)}: {n} files, {size/1024/1024:.2f} MB, "
          f"integrity={'FAIL:'+str(bad) if bad else 'OK'}, sha256[:16]={digest}")
    return bad is None

# ── shared file lists ────────────────────────────────────────────────────────
wuxiabox_plugin = []
add_file(wuxiabox_plugin, "download/wuxiabox.lua", "plugins/wuxiabox.lua")

wuxiabox_docs = []
add_file(wuxiabox_docs, "download/wuxiabox_pull_request.md", "docs/wuxiabox_pull_request.md")
add_file(wuxiabox_docs, "download/MAINTENANCE.md", "docs/MAINTENANCE.md")

all_plugins = list(wuxiabox_plugin)
add_file(all_plugins, "download/wtrlab.lua", "plugins/wtrlab.lua")
add_file(all_plugins, "download/novel543.lua", "plugins/novel543.lua")
add_file(all_plugins, "download/wuxiaworld_site.lua", "plugins/wuxiaworld_site.lua")

all_docs = list(wuxiabox_docs)
add_file(all_docs, "download/pull_request.md", "docs/wtrlab_pull_request.md")
add_file(all_docs, "download/novel543_pull_request.md", "docs/novel543_pull_request.md")
add_file(all_docs, "download/README.md", "docs/wtrlab_README.md")
add_file(all_docs, "download/wtrlab_50ch_test.md", "docs/wtrlab_50ch_test.md")
add_file(all_docs, "download/wtrlab_50ch_test.csv", "docs/wtrlab_50ch_test.csv")
add_file(all_docs, "worklog.md", "docs/worklog.md")

harness = []
for f in ["WuxiaboxTest.java", "LuaTest.java", "Novel543Test.java", "SyntaxCheck.java",
          "ParaDiag.java", "ChapterTiming.java", "OkHttpTranslateSim.java", "DebugFetch.java"]:
    add_file(harness, f"testenv/{f}", f"test-harness/{f}")
for j in ["luaj-jse-3.0.1.jar", "jsoup-1.17.2.jar", "gson-2.10.1.jar", "ecj.jar"]:
    add_file(harness, f"testenv/lib/{j}", f"test-harness/lib/{j}")
for f in ["reader1.json", "terms_93618.json", "arr_sample.txt", "tag_pickers.lua",
          "tags_live_v2.json", "tags_live_v3.json"]:
    add_file(harness, f"download/test-harness/{f}", f"test-harness/data/{f}")

import glob as g
scripts = []
for f in sorted(g.glob(f"{BASE}/scripts/*.py")):
    name = os.path.basename(f)
    if any(k in name for k in ["wuxiabox", "wtrlab", "novel543", "tag", "harvest",
                                "probe", "splice", "curate", "backup", "integration",
                                "assemble", "swap", "gen_", "test_", "phase"]):
        scripts.append((f"scripts/{name}", f))

research_wuxiabox = []
for f in sorted(g.glob(f"{BASE}/research/wuxiabox/*.html")):
    research_wuxiabox.append((f"research/wuxiabox/{os.path.basename(f)}", f))
for sub in ["v21", "v22", "v23"]:
    for f in sorted(g.glob(f"{BASE}/research/wuxiabox/{sub}/*")):
        research_wuxiabox.append((f"research/wuxiabox/{sub}/{os.path.basename(f)}", f))
add_file(research_wuxiabox, "research/real_tags.json", "research/real_tags.json")
add_file(research_wuxiabox, "research/wuxiabox/tags_raw.json", "research/wuxiabox/tags_raw.json")
add_file(research_wuxiabox, "research/wuxiabox/curated_tags.json", "research/wuxiabox/curated_tags.json")

upstream = []
add_file(upstream, "research/external-sources/en/wuxiabox.lua", "upstream/en/wuxiabox.lua")
add_file(upstream, "research/external-sources/mtl/wtrlab.lua", "upstream/mtl/wtrlab.lua")
add_file(upstream, "research/external-sources/zh/novel543.lua", "upstream/zh/novel543.lua")
add_file(upstream, "research/external-sources/en/wuxiaworld_site.lua", "upstream/en/wuxiaworld_site.lua")
add_file(upstream, "research/external-sources/lua-plugin-guide.md", "upstream/lua-plugin-guide.md")

# ── manifest ─────────────────────────────────────────────────────────────────
COMMON_RESTORE = """Restore
-------
1. Copy plugins/wuxiabox.lua to /home/z/my-project/download/wuxiabox.lua
   (the harness hardcodes this path).
2. Copy research/wuxiabox/ to /home/z/my-project/research/wuxiabox/ (fixtures).
3. Compile + run the suite from test-harness/:
     java -jar test-harness/lib/ecj.jar -source 17 -target 17 \\
       -cp "test-harness/lib/luaj-jse-3.0.1.jar:test-harness/lib/jsoup-1.17.2.jar:test-harness/lib/gson-2.10.1.jar" \\
       test-harness/WuxiaboxTest.java -d .
     java -cp "test-harness/lib/*:." WuxiaboxTest
   Expected: 147/147 PASS.

wuxiabox v2.3.0 — what changed (2026-09-19)
-------------------------------------------
SMART MIRROR SWITCHER:
- Persistent per-site health tracker (circuit breaker) via set_preference key
  "wuxiabox_site_health": 2 consecutive failures -> 10-min cooldown (site
  skipped by every fetch), any success resets, 404 neutral, expiry half-open.
- orderedBases() = preference order minus cooling sites; every fetch path is
  health-aware (catalog, filters, updates, novel pages, fy fragments, tags,
  search, chapter rescue) and every failure feeds the tracker - including the
  ENGINE's own failed chapter fetch (getChapterText charges junk bodies to the
  primary before rescuing).
- Chapter rescue: no pre-attempt sleep, health-aware attempt order, 404 does
  not poison health, both-sites-dead raises a clear error (no more silent
  empty text -> engine heuristics).
- 200-but-junk bodies (origin 502 HTML, CF pages, maintenance) are failures on
  every fetch path (isJunkBody / isErrorMarkerBody).
- Search: each query remembers WHICH base created its searchid
  (_searchBaseByQuery) -> mirror-started searches paginate on the mirror;
  tag listings stay primary-only (different id spaces).
- transformChapterUrl(url) shipped as a forward-compatible hook (inert on
  stock engines; PR doc has the 10-line LuaSourceAdapter patch that activates
  it and removes the last doomed-canonical-fetch gap).
- Settings relabelled: "Smart switch - WuxiaBox first, auto-failover to
  WuxiaSpot (recommended)" / "WuxiaBox only" / "WuxiaSpot first - manual
  mirror switch, WuxiaBox backup".
- Tests: 125 -> 147 (T17 family: cooldown steering + persistence + expiry +
  reset + junk + 404; T18 mirror-native search pagination; T19 clear error;
  hermetic reloadPlugin() resets in all mirror tests).

Engine facts this build relies on (verified in noveLA-repo @ dc3d18c):
- DownloaderRepository.bookChapter fetches the canonical chapter URL itself
  (2 requests) before the plugin runs; transformChapterUrl is NOT exposed to
  Lua on stock engines.
- ServerErrorRetryInterceptor RETURNS the last 502 body (does not throw) ->
  the plugin receives it and can rescue; CF-unsolved/hard-outage THROW ->
  plugin never runs (engine patch closes this).
- set_preference persists in SharedPreferences "lua_preferences"; keys not in
  getSettingsSchema never show in the UI.
- Scraper.getCompatibleSource matches by host prefix -> URLs must stay
  canonical wuxiabox.com.
"""

manifest_box = f"""WuxiaBox Plugin Backup — 2026-09-19 (v2.3.0)
================================================

Contents
--------
plugins/          wuxiabox.lua v2.3.0 (smart mirror switcher)
docs/             wuxiabox_pull_request.md (v2.3.0 PR) + MAINTENANCE.md
test-harness/     WuxiaboxTest.java (147 checks) + luaj/jsoup/gson/ecj jars + data
scripts/          Full wuxiabox pipeline: harvest, curate, splice (v220/v230),
                  test patches, probes (incl. probe_v23.py)
research/         Live-captured fixtures incl. v21 (search/mirror evidence),
                  v22 (pagination evidence), v23 (twin-structure sanity),
                  curated_tags.json, real_tags.json

{COMMON_RESTORE}"""

manifest_all = f"""NoveLA Plugins Backup — 2026-09-19
===================================

Contents
--------
plugins/          wuxiabox.lua v2.3.0 (smart mirror switcher) · wtrlab.lua v1.2.1 ·
                  novel543.lua v1.0.5 · wuxiaworld_site.lua (untouched)
docs/             All PR docs + READMEs + MAINTENANCE.md + worklog
test-harness/     Java suites (luaj 3.0.1 + jsoup + gson + ecj) + data fixtures
scripts/          Regeneration pipelines for all three plugins
research/         wuxiabox fixtures (v21/v22/v23), curated_tags.json,
                  real_tags.json (wtrlab taxonomy)
upstream/         HnDK0/external-sources snapshots + lua-plugin-guide.md

This session's release
----------------------
- wuxiabox.lua 2.3.0 — SMART MIRROR SWITCHER: persistent circuit breaker
  (set_preference), health-aware fetch order on every path, instant chapter
  rescue, junk-body detection, mirror-native search pagination, clear
  both-sites-dead errors, forward-compatible transformChapterUrl hook.
  147/147 tests. (wtrlab 1.2.1 and novel543 1.0.5 unchanged from 2026-09-18.)

{COMMON_RESTORE}"""

ok1 = build(os.path.join(BASE, "download", "wuxiabox-backup-20260919.zip"),
            wuxiabox_plugin + wuxiabox_docs + harness + scripts + research_wuxiabox,
            manifest_box)
ok2 = build(os.path.join(BASE, "download", "noveLA-plugins-backup-20260919.zip"),
            all_plugins + all_docs + harness + scripts + research_wuxiabox + upstream,
            manifest_all)
print("ALL OK" if (ok1 and ok2) else "ZIP INTEGRITY FAILURE")
