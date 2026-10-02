#!/usr/bin/env python3
"""Build noveLA-plugins-backup-20260920.zip — v3 backup + 69shubaTw additions."""
import zipfile, os, hashlib

OUT = "/home/z/my-project/download/noveLA-plugins-backup-20260920.zip"
BASE = "/home/z/my-project"

FILES = [
    # plugins
    ("download/wuxiabox.lua",        "plugins/wuxiabox.lua"),
    ("download/wtrlab.lua",          "plugins/wtrlab.lua"),
    ("download/novel543.lua",        "plugins/novel543.lua"),
    ("download/bixiange.lua",        "plugins/bixiange.lua"),
    ("download/oop.lua",             "plugins/oop.lua"),
    ("download/69shubaTw.lua",       "plugins/69shubaTw.lua"),
    # docs
    ("download/69shubatw_pull_request.md", "docs/69shubatw_pull_request.md"),
    ("download/oop_pull_request.md",       "docs/oop_pull_request.md"),
    ("download/bixiange_pull_request.md",  "docs/bixiange_pull_request.md"),
    ("download/wuxiabox_pull_request.md",  "docs/wuxiabox_pull_request.md"),
    ("download/novel543_pull_request.md",  "docs/novel543_pull_request.md"),
    ("download/pull_request.md",           "docs/wtrlab_pull_request.md"),
    ("download/README.md",                 "docs/README.md"),
    ("download/MAINTENANCE.md",            "docs/MAINTENANCE.md"),
    # plugin source parts
    ("scripts/69shubatw_plugin/part1.lua", "source-parts/69shubatw/part1.lua"),
    ("scripts/69shubatw_plugin/part2.lua", "source-parts/69shubatw/part2.lua"),
    ("scripts/69shubatw_plugin/part3.lua", "source-parts/69shubatw/part3.lua"),
    ("scripts/69shubatw_plugin/part4.lua", "source-parts/69shubatw/part4.lua"),
    ("scripts/assemble_69shubatw.py",      "source-parts/69shubatw/assemble_69shubatw.py"),
    # scripts (69shubaTw pipeline + prior session key scripts)
    ("scripts/fetch_69shubatw.py",              "scripts/fetch_69shubatw.py"),
    ("scripts/clean_69shubatw_fixtures.py",     "scripts/clean_69shubatw_fixtures.py"),
    ("scripts/gen_69shubatw_toc_fixtures.py",   "scripts/gen_69shubatw_toc_fixtures.py"),
    ("scripts/update_maintenance_69shubatw.py", "scripts/update_maintenance_69shubatw.py"),
    ("scripts/build_backup_zip_69shubatw.py",   "scripts/build_backup_zip_69shubatw.py"),
    ("scripts/patch_69shubatw_v110.py",         "scripts/patch_69shubatw_v110.py"),
    ("scripts/gen_69shubatw_walk_fixtures.py",  "scripts/gen_69shubatw_walk_fixtures.py"),
    ("scripts/patch_69shubatw_tests_v110.py",   "scripts/patch_69shubatw_tests_v110.py"),
    ("download/test-harness/S69RealSeed.java",  "test-harness/S69RealSeed.java"),
    ("research/69shubatw/toc_342441.html",      "evidence/toc_342441_captcha.html"),
    ("research/69shubatw/headers.txt",          "evidence/edgeone_403_headers.txt"),
    # test harness
    ("download/test-harness/S69TwTest.java", "test-harness/S69TwTest.java"),
    ("download/test-harness/OopTest.java",   "test-harness/OopTest.java"),
    ("download/test-harness/BixiangeTest.java", "test-harness/BixiangeTest.java"),
    ("download/test-harness/WuxiaboxTest.java", "test-harness/WuxiaboxTest.java"),
    ("download/test-harness/Novel543Test.java", "test-harness/Novel543Test.java"),
    ("download/test-harness/LuaTest.java",     "test-harness/LuaTest.java"),
    ("download/test-harness/SyntaxCheck.java", "test-harness/SyntaxCheck.java"),
]

# harness jars + 69shubaTw fixtures
for jar in ("luaj-jse-3.0.1.jar", "jsoup-1.17.2.jar", "gson-2.10.1.jar", "ecj.jar"):
    p = f"testenv/lib/{jar}"
    if os.path.exists(os.path.join(BASE, p)):
        FILES.append((p, f"test-harness/lib/{jar}"))

FIXDIR = "research/69shubatw/fixtures"
for f in sorted(os.listdir(os.path.join(BASE, FIXDIR))):
    FILES.append((f"{FIXDIR}/{f}", f"research/69shubatw/fixtures/{f}"))

# raw research evidence (challenge page + probe outputs)
for f in ("home.html", "book_gt.html", "chapter_1.html", "chapter_2.html",
          "home_full.html", "fenlei_lishi.html", "quanben.html", "search_test.html",
          "common.js", "headers.txt"):
    p = f"research/69shubatw/{f}"
    if os.path.exists(os.path.join(BASE, p)):
        FILES.append((p, f"research/69shubatw/raw/{f}"))

README = """NoveLA plugins backup — 2026-09-20
==================================

Contents
--------
plugins/       wuxiabox.lua 2.3.0, wtrlab.lua 1.2.1, novel543.lua 1.0.5,
               bixiange.lua 1.0.0, oop.lua 1.1.0, 69shubaTw.lua 1.0.0 (NEW)
docs/          per-plugin PR docs, README, MAINTENANCE.md (knowledge base)
source-parts/  69shubaTw.lua source parts + assembler
scripts/       69shubaTw research/fixture/test pipeline
test-harness/  Java harnesses (S69TwTest 101 mock, OopTest 97, BixiangeTest
               96, WuxiaboxTest 147, Novel543Test 197, LuaTest 66 live) + jars
research/      69shuba.tw fixtures (cleaned translate-proxy captures +
               synthesized TOC layout variants) and raw probe evidence

69shubaTw.lua v1.0.0 — the new plugin
-------------------------------------
Target: https://69shuba.tw/ (Traditional 69shuba portal — NOT 69shuba.com).
Anti-bot: Tencent EdgeOne aegis captcha; the plugin registers
cf_options.trigger_markers so the app's WebView ladder can solve it.
Covers: DIRECT from the open CDN p.69shuba.tw (no wsrv.nl, per user request).
TOC: layout-agnostic anchor scan (/read/{bid}/{cid}, cid-sorted) because the
/indexlist/ markup is WAF-uncapturable; solver-safe walks (parsePage +
early-abort + persistent page cache + cross-page dedupe).
Translator: novel543 core (zh-TW source; queries -> zh-TW, zh-CN retry).

Restore: copy plugins/*.lua into the app's plugin folder.
Tests: compile with ecj (see MAINTENANCE.md Part 0 commands) and run
  java -cp ".:lib/*" S69TwTest        (expect 101/101)
"""

def main():
    if os.path.exists(OUT):
        os.remove(OUT)
    z = zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED)
    z.writestr("README.txt", README)
    n = 0
    for src, dst in FILES:
        p = os.path.join(BASE, src)
        if not os.path.exists(p):
            print("MISSING:", src)
            continue
        z.write(p, dst)
        n += 1
    z.close()
    # integrity
    z = zipfile.ZipFile(OUT)
    bad = z.testzip()
    size = os.path.getsize(OUT)
    names = z.namelist()
    print(f"\n{OUT}")
    print(f"files: {len(names)}  size: {size/1024/1024:.2f} MB  integrity: {'OK' if bad is None else 'CORRUPT: ' + bad}")

if __name__ == "__main__":
    main()
