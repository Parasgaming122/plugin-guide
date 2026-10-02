#!/usr/bin/env python3
"""Build the all-plugins backup zip for 2026-09-18."""
import os, zipfile, subprocess, hashlib

BASE = "/home/z/my-project"
OUT = f"{BASE}/download/noveLA-plugins-backup-20260918.zip"

files = []  # (archive_path, source_path)

def add(src, arc):
    p = os.path.join(BASE, src)
    if os.path.exists(p):
        files.append((arc, p))
    else:
        print(f"  [WARN] missing: {src}")

# 1. plugins
add("download/wuxiabox.lua", "plugins/wuxiabox.lua")
add("download/wtrlab.lua", "plugins/wtrlab.lua")
add("download/novel543.lua", "plugins/novel543.lua")
add("download/wuxiaworld_site.lua", "plugins/wuxiaworld_site.lua")

# 2. docs
add("download/wuxiabox_pull_request.md", "docs/wuxiabox_pull_request.md")
add("download/pull_request.md", "docs/wtrlab_pull_request.md")
add("download/novel543_pull_request.md", "docs/novel543_pull_request.md")
add("download/README.md", "docs/wtrlab_README.md")
add("download/MAINTENANCE.md", "docs/MAINTENANCE.md")
add("download/wtrlab_50ch_test.md", "docs/wtrlab_50ch_test.md")
add("download/wtrlab_50ch_test.csv", "docs/wtrlab_50ch_test.csv")
add("worklog.md", "docs/worklog.md")

# 3. test harness (java + jars + scripts)
for f in ["WuxiaboxTest.java", "LuaTest.java", "Novel543Test.java", "SyntaxCheck.java",
          "ParaDiag.java", "ChapterTiming.java", "OkHttpTranslateSim.java", "DebugFetch.java"]:
    add(f"testenv/{f}", f"test-harness/{f}")
for j in ["luaj-jse-3.0.1.jar", "jsoup-1.17.2.jar", "gson-2.10.1.jar", "ecj.jar"]:
    add(f"testenv/lib/{j}", f"test-harness/lib/{j}")
# harness helper data (lives in download/test-harness/)
for f in ["reader1.json", "terms_93618.json", "arr_sample.txt", "tag_pickers.lua",
          "tags_live_v2.json", "tags_live_v3.json"]:
    add(f"download/test-harness/{f}", f"test-harness/data/{f}")
# scripts
import glob as g
for f in sorted(g.glob(f"{BASE}/scripts/*.py")):
    name = os.path.basename(f)
    if any(k in name for k in ["wuxiabox", "wtrlab", "novel543", "tag", "harvest",
                                "probe", "splice", "curate", "backup", "integration",
                                "assemble", "swap", "gen_", "test_", "phase"]):
        files.append((f"scripts/{name}", f))

# 4. research fixtures
for f in sorted(g.glob(f"{BASE}/research/wuxiabox/*.html")):
    files.append((f"research/wuxiabox/{os.path.basename(f)}", f))
for f in sorted(g.glob(f"{BASE}/research/wuxiabox/v21/*.html")):
    files.append((f"research/wuxiabox/v21/{os.path.basename(f)}", f))
for f in sorted(g.glob(f"{BASE}/research/wuxiabox/v22/*")):
    files.append((f"research/wuxiabox/v22/{os.path.basename(f)}", f))
add("research/real_tags.json", "research/real_tags.json")
add("research/wuxiabox/tags_raw.json", "research/wuxiabox/tags_raw.json")
add("research/wuxiabox/curated_tags.json", "research/wuxiabox/curated_tags.json")

# 5. upstream snapshots for diffing
add("research/external-sources/en/wuxiabox.lua", "upstream/en/wuxiabox.lua")
add("research/external-sources/mtl/wtrlab.lua", "upstream/mtl/wtrlab.lua")
add("research/external-sources/zh/novel543.lua", "upstream/zh/novel543.lua")
add("research/external-sources/en/wuxiaworld_site.lua", "upstream/en/wuxiaworld_site.lua")
add("research/external-sources/lua-plugin-guide.md", "upstream/lua-plugin-guide.md")

# dedupe by source path
seen = set()
uniq = []
for arc, p in files:
    if p in seen:
        continue
    seen.add(p)
    uniq.append((arc, p))
files = uniq

MANIFEST = f"""NoveLA Plugins Backup — 2026-09-18
====================================

Contents
--------
plugins/          wuxiabox.lua v2.2.0 · wtrlab.lua v1.2.1 · novel543.lua v1.0.5 ·
                  wuxiaworld_site.lua (the separate WuxiaWorld.site source, untouched this session)
docs/             PR documents + READMEs + MAINTENANCE.md (knowledge base) + worklog
test-harness/     Java suites (luaj 3.0.1 + jsoup + gson + ecj jars) + data fixtures
scripts/          Regeneration pipeline: curation, splices, probes, test patches
research/         Live-captured HTML fixtures (wuxiabox incl. v22 search-pagination
                  evidence), curated_tags.json, real_tags.json (wtrlab taxonomy)
upstream/         Current HnDK0/external-sources plugin snapshots + lua-plugin-guide.md

This session's releases
-----------------------
- wuxiabox.lua 2.2.0 — posters via wsrv.nl proxy; search paginates continuously
  (total-marker fix + primary-only searchid pages + retryable errors); 6,723-tag
  index replaced by 755 curated tags in a searchable tag_input picker;
  getUserAgentPreset("Chrome Mobile"); show_error adoption. 125/125 tests.
- wtrlab.lua 1.2.1 — posters via wsrv.nl proxy (Cover Images setting). 66/66 live.
- novel543.lua 1.0.5 — posters via wsrv.nl proxy + name sync with upstream.
  197/197 live (+1 env skip).

Restore
-------
1. Copy plugins/*.lua to /home/z/my-project/download/ (the harness hardcodes these paths).
2. Copy research/wuxiabox/ to /home/z/my-project/research/wuxiabox/ (fixture paths).
3. Compile + run tests from test-harness/:
     java -jar test-harness/lib/ecj.jar -source 17 -target 17 \\
       -cp "test-harness/lib/luaj-jse-3.0.1.jar:test-harness/lib/jsoup-1.17.2.jar:test-harness/lib/gson-2.10.1.jar" \\
       test-harness/WuxiaboxTest.java -d .
     java -cp "test-harness/lib/*:." WuxiaboxTest
   (same pattern for LuaTest [wtrlab, live] and Novel543Test [live, curl-routed])

Tag-refresh pipeline (wuxiabox)
-------------------------------
  scripts/harvest_wuxiabox_tags.py   (resumable live harvest)
  scripts/curate_wuxiabox_tags.py    (taxonomy cross-ref; EXCLUDE mirror fixtures!)
  scripts/splice_wuxiabox_v220.py    (regenerate TAG_SEARCH_INDEX + TAG_FILTER_OPTIONS)
  WuxiaboxTest.java                  (T7d validates all 756 option id/label pairs)

Notes
-----
- wsrv.nl (images.weserv.nl) is the engine-whitelisted image proxy; the "Cover images"
  setting in each plugin reverts to direct URLs if the proxy is ever unavailable.
- The wtrlab/novel543 live suites need network patience from datacenter IPs
  (novel543.com intermittently 429s/challenges; on-device is unaffected).
- Full session knowledge: docs/MAINTENANCE.md (esp. Part 0.5 — September 2026 engine
  update, and gotchas #35-41) + docs/worklog.md (tasks multi-1/multi-2).
"""

with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    z.writestr("README.txt", MANIFEST)
    for arc, p in files:
        z.write(p, arc)

size = os.path.getsize(OUT)
with zipfile.ZipFile(OUT) as z:
    n = len(z.namelist())
    bad = z.testzip()
print(f"built {OUT}")
print(f"  {n} files, {size/1024/1024:.2f} MB, integrity: {'OK' if bad is None else 'CORRUPT: '+bad}")
# sha256
h = hashlib.sha256(open(OUT, 'rb').read()).hexdigest()
print(f"  sha256: {h[:16]}…")
