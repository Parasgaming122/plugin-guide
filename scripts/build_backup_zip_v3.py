#!/usr/bin/env python3
"""Build the all-plugins backup zip v3 — oop.lua v1.1.0 (TOC Cloudflare
solver-storm fix). Same structure as v2, plus the v1.1.0 scripts and the
synthesized TOC fixtures."""
import zipfile, os, time

BASE = "/home/z/my-project"
OUT = f"{BASE}/download/noveLA-plugins-backup-20260919-v3.zip"

def add(z, arc, path):
    if os.path.isfile(path):
        z.write(path, arc)
    else:
        print(f"  [WARN] missing {path}")

now = time.strftime("%Y-%m-%d %H:%M")
manifest = f"""NoveLA plugin backup — {now} (v3: oop.lua v1.1.0)
==================================================

What changed since v2
---------------------
oop.lua 1.0.0 -> 1.1.0 — CHAPTER-LIST CLOUDFLARE FIX ("solver storm"):
  v1.0.0 walked every 30-chapter catalog page and kept fetching the NEXT page
  after each failure; on oop.tw a failed fetch means the engine already burned
  a full CF solver attempt (15s hidden WebView + up to 2x35s manual), so opening
  a novel launched the solver once per page and TOCs never loaded.
  v1.1.0: parsePage(bookUrl, page) engine API (walk stops at first failure, TOC
  refreshes incremental), early-abort getChapterList fallback, persistent
  per-book page cache (immutable interior pages served with zero network, walks
  resume where they stopped, stale-serve when the site is unreachable), richer
  getChapterListHash. OopTest 59 -> 97 checks.

Contents
--------
plugins/
  wuxiabox.lua      v2.3.0  (unchanged)
  wtrlab.lua        v1.2.1  (unchanged)
  novel543.lua      v1.0.5  (unchanged)
  bixiange.lua      v1.0.0  (unchanged)
  oop.lua           v1.1.0  UPDATED (2026-09-19)
docs/
  oop_pull_request.md       REWRITTEN as the v1.1.0 PR (incident analysis + fix table + 97-check table)
  MAINTENANCE.md            UPDATED (card, Part 0.8 oop v1.1.0, gotchas #50 refresh + NEW #51-#53)
  bixiange/wuxiabox/wtrlab/novel543 docs (unchanged)
scripts/  (v1.1.0 pipeline)
  patch_oop_v110.py           oop.lua 1.0.0 -> 1.1.0 splice (exact-string anchors)
  gen_oop_tocgen_fixtures.py  synthesized 5-page + single-page catalog fixtures
  patch_oop_tests_v110.py     OopTest.java +38 checks (both harness copies)
  rewrite_oop_pr_v110.py      PR doc rewrite
  patch_maintenance_oop_v110.py  MAINTENANCE.md update
  build_backup_zip_v3.py      this zip
  (+ the v1.0.0 pipeline: assemble_oop.py, clean_oop_fixtures.py, probes)
source-parts/
  oop_plugin/part1-4.lua   v1.0.0 source parts (v1.1.0 applied directly to download/oop.lua
                           via patch_oop_v110.py — the parts are the 1.0.0 baseline)
test-harness/
  OopTest.java — 97 checks (compile+run notes below)
  BixiangeTest.java + the other harnesses (unchanged)
research/newsites/
  oop_tocgen_p1..p5.html, oop_tocgen_single.html — synthesized TOC fixtures (150-chapter
    5-page book with the swapped-adjacent quirk on page 2 + a single-page book)
  oop_probe_pall.html — the ?p=all probe (proves no full-TOC endpoint)
  + all v1.0.0 evidence fixtures

Restore
-------
1. Copy plugins/*.lua into NoveLA via Extensions -> import.
2. OOP tests: cd test-harness &&
     java -jar ecj.jar -source 19 -target 19 -cp "luaj-jse-3.0.1.jar:jsoup-1.23.1.jar:gson-2.14.0.jar" -d . OopTest.java
     java -cp ".:luaj-jse-3.0.1.jar:jsoup-1.23.1.jar:gson-2.14.0.jar" OopTest
   (expect: 97 checks, 97 PASS)
3. Rebuild after edits: edit download/oop.lua directly (v1.1.0+ pipeline is
   patch-based; scripts/patch_oop_v110.py documents every change).

Notes
-----
- oop.tw is Cloudflare-challenged from datacenter IPs; fixtures were captured
  through the Google-Translate proxy (v1.0.0) or synthesized (v1.1.0). On-device
  the app's WebView bypass fetches the real pages.
- Engine facts baked into v1.1.0 (see MAINTENANCE.md gotchas #51-#53):
  http_get returns {{success=false}} (never throws) after a failed CF solver
  ladder; parsePage exists in BOTH Aug-25 and Sep-18 engine builds; the
  engine's ChapterPagination floor is 30 chapters/page (== oop.tw's page size).
"""

files = []
# plugins
for f in ["wuxiabox.lua", "wtrlab.lua", "novel543.lua", "bixiange.lua", "oop.lua"]:
    files.append((f"plugins/{f}", f"{BASE}/download/{f}"))
# docs
for f in ["bixiange_pull_request.md", "oop_pull_request.md", "wuxiabox_pull_request.md",
          "novel543_pull_request.md", "pull_request.md", "README.md", "MAINTENANCE.md"]:
    p = f"{BASE}/download/{f}"
    if os.path.isfile(p):
        files.append((f"docs/{f}", p))
if os.path.isfile(f"{BASE}/worklog.md"):
    files.append(("docs/worklog.md", f"{BASE}/worklog.md"))
# source parts
for d in ["bixiange_plugin", "oop_plugin"]:
    dd = f"{BASE}/scripts/{d}"
    if os.path.isdir(dd):
        for f in sorted(os.listdir(dd)):
            if f.endswith(".lua"):
                files.append((f"source-parts/{d}/{f}", f"{dd}/{f}"))
# scripts (v1.0.0 + v1.1.0 pipelines)
for f in ["assemble_bixiange.py", "assemble_oop.py", "clean_oop_fixtures.py",
          "probe_new_sites.py", "probe_bx_search.py",
          "patch_oop_v110.py", "gen_oop_tocgen_fixtures.py", "patch_oop_tests_v110.py",
          "rewrite_oop_pr_v110.py", "patch_maintenance_oop_v110.py", "build_backup_zip_v3.py"]:
    p = f"{BASE}/scripts/{f}"
    if os.path.isfile(p):
        files.append((f"scripts/{f}", p))
# harness
for f in ["BixiangeTest.java", "OopTest.java", "LuaTest.java", "WuxiaboxTest.java",
          "Novel543Test.java", "luaj-jse-3.0.1.jar", "jsoup-1.23.1.jar",
          "gson-2.14.0.jar", "ecj.jar", "SyntaxCheck2.java"]:
    p = f"{BASE}/test-harness/{f}"
    if os.path.isfile(p):
        files.append((f"test-harness/{f}", p))
# fixtures/evidence
nd = f"{BASE}/research/newsites"
if os.path.isdir(nd):
    for f in sorted(os.listdir(nd)):
        if f.startswith(("bx_", "oop_")) and not f.endswith("_raw.txt"):
            files.append((f"research/newsites/{f}", f"{nd}/{f}"))

with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("README.txt", manifest)
    for arc, path in files:
        add(z, arc, path)

with zipfile.ZipFile(OUT) as z:
    bad = z.testzip()
    names = z.namelist()
print(f"{OUT}: {os.path.getsize(OUT)/1e6:.2f} MB, {len(names)} files, "
      f"integrity={'OK' if bad is None else 'FAIL: ' + bad}")
