#!/usr/bin/env python3
"""Build the all-plugins backup zip including the two new plugins
(bixiange + oop), their docs, harnesses, scripts, fixtures and sources."""
import zipfile, os, time

BASE = "/home/z/my-project"
OUT = f"{BASE}/download/noveLA-plugins-backup-20260919-v2.zip"

def add(z, arc, path):
    if os.path.isfile(path):
        z.write(path, arc)

now = time.strftime("%Y-%m-%d %H:%M")
manifest = f"""NoveLA plugin backup — {now} (v2: + bixiange + oop)
=====================================================

Contents
--------
plugins/
  wuxiabox.lua      v2.3.0  (unchanged from earlier today)
  wtrlab.lua        v1.2.1
  novel543.lua      v1.0.5
  bixiange.lua      v1.0.0  NEW (2026-09-19) — 笔仙阁 GBK site + mirror + translator
  oop.lua           v1.0.0  NEW (2026-09-19) — OOP 小說網 CF site + translator
docs/
  bixiange_pull_request.md   NEW — full PR doc (site facts, GBK story, 96-check test table)
  oop_pull_request.md        NEW — full PR doc (translate-proxy research technique, 59-check table)
  wuxiabox_pull_request.md / wtrlab docs / novel543 PR / README / MAINTENANCE.md (updated with
    Part 0.8 + gotchas #44-#50)
source-parts/
  bixiange_plugin/part1-4.lua   hand-written plugin source (assemble: scripts/assemble_bixiange.py)
  oop_plugin/part1-4.lua        hand-written plugin source (assemble: scripts/assemble_oop.py)
scripts/
  assemble_bixiange.py / assemble_oop.py — concat parts + syntax check
  clean_oop_fixtures.py  — translate-proxy fixture cleaner (un-reverses CJK paragraphs)
  probe_new_sites.py / probe_bx_search.py — live site probes
test-harness/
  BixiangeTest.java — 76 mock + 20 live checks (GBK charset emulation, EmpireCMS 302 mocks)
  OopTest.java      — 59 mock checks (cleaned translate-proxy fixtures)
  + jars (luaj/jsoup/gson/ecj) and the existing harnesses
research/newsites/
  bixiange live evidence: home/book/ch1/ch150/category/sort/newest/search fixtures (raw GBK),
    search POST captures, mirror probes
  oop evidence: translate-proxy DOM dumps (sort/book/chapter/ch2/search) + cleaned fixtures
    + synthesized catalog page 2

Restore
-------
1. Copy plugins/*.lua into NoveLA via Extensions → import (or restore the dev copies at
   /home/z/my-project/download/).
2. Tests: cd test-harness &&
     java -cp ".:luaj-jse-3.0.1.jar:jsoup-1.23.1.jar:gson-2.14.0.jar" BixiangeTest        # mock
     ... BixiangeTest live                                                               # live network
     ... OopTest                                                                          # mock
   (compile with ECJ if .class missing:
    java -cp ecj.jar org.eclipse.jdt.internal.compiler.batch.Main -cp "luaj-jse-3.0.1.jar:jsoup-1.23.1.jar:gson-2.14.0.jar" -17 -d . BixiangeTest.java)
3. Rebuild plugins after edits: python3 scripts/assemble_bixiange.py / assemble_oop.py
   (sources live in source-parts/, keep them in sync).

Notes
-----
- oop.tw is Cloudflare-challenged from datacenter IPs — its fixtures were captured through
  the Google-Translate proxy and cleaned; on-device the app's WebView bypass fetches the
  real pages. Live tests exist only for bixiange.
- bixiange fixtures are raw GBK bytes — the harness decodes them exactly like the engine.
"""

files = []
# plugins
for f in ["wuxiabox.lua", "wtrlab.lua", "novel543.lua", "bixiange.lua", "oop.lua"]:
    files.append((f"plugins/{f}", f"{BASE}/download/{f}"))
# docs
for f in ["bixiange_pull_request.md", "oop_pull_request.md", "wuxiabox_pull_request.md",
          "novel543_pull_request.md", "pull_request.md", "README.md", "MAINTENANCE.md",
          "worklog.md"]:
    p = f"{BASE}/download/{f}"
    if os.path.isfile(p):
        files.append((f"docs/{f}", p))
# source parts
for d in ["bixiange_plugin", "oop_plugin"]:
    dd = f"{BASE}/scripts/{d}"
    if os.path.isdir(dd):
        for f in sorted(os.listdir(dd)):
            if f.endswith(".lua"):
                files.append((f"source-parts/{d}/{f}", f"{dd}/{f}"))
# scripts
for f in ["assemble_bixiange.py", "assemble_oop.py", "clean_oop_fixtures.py",
          "probe_new_sites.py", "probe_bx_search.py"]:
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

# integrity check
with zipfile.ZipFile(OUT) as z:
    bad = z.testzip()
    names = z.namelist()
print(f"{OUT}: {os.path.getsize(OUT)/1e6:.2f} MB, {len(names)} files, integrity={'OK' if bad is None else 'FAIL: '+bad}")
