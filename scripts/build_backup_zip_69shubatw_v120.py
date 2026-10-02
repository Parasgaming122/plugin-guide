#!/usr/bin/env python3
"""Build noveLA-plugins-backup-20260920-v2.zip — the v1.2.0 69shubaTw release.

Same layout as the earlier 20260920 zip, updated with:
  - plugins/69shubaTw.lua v1.2.0 (real /indexlist/ pagination, 2,019 lines)
  - updated docs (69shubatw_pull_request.md v1.2.0, MAINTENANCE.md)
  - the v1.2.0 pipeline scripts (fixtures generator, test patch)
  - updated harnesses (S69TwTest.java 218 checks + S69RealSeed.java)
  - raw evidence: the LIVE wcshuba.com family captures that drove the fix
"""
import zipfile, os, hashlib

OUT = "/home/z/my-project/download/noveLA-plugins-backup-20260920-v2.zip"
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
    # v1.2.0 pipeline scripts
    ("scripts/fetch_69shubatw_indexlist.py",    "scripts/v120/fetch_69shubatw_indexlist.py"),
    ("scripts/probe_69shuba_mirrors.py",        "scripts/v120/probe_69shuba_mirrors.py"),
    ("scripts/gen_69shubatw_toc_fixtures_v120.py", "scripts/v120/gen_69shubatw_toc_fixtures_v120.py"),
    ("scripts/patch_69shubatw_tests_v120.py",   "scripts/v120/patch_69shubatw_tests_v120.py"),
    # v1.0.0/v1.1.0 pipeline (history)
    ("scripts/fetch_69shubatw.py",              "scripts/v100/fetch_69shubatw.py"),
    ("scripts/clean_69shubatw_fixtures.py",     "scripts/v100/clean_69shubatw_fixtures.py"),
    ("scripts/gen_69shubatw_toc_fixtures.py",   "scripts/v100/gen_69shubatw_toc_fixtures.py"),
    ("scripts/assemble_69shubatw.py",           "scripts/v100/assemble_69shubatw.py"),
    ("scripts/patch_69shubatw_v110.py",         "scripts/v110/patch_69shubatw_v110.py"),
    ("scripts/gen_69shubatw_walk_fixtures.py",  "scripts/v110/gen_69shubatw_walk_fixtures.py"),
    ("scripts/patch_69shubatw_tests_v110.py",   "scripts/v110/patch_69shubatw_tests_v110.py"),
    # harnesses
    ("download/test-harness/S69TwTest.java",    "test-harness/S69TwTest.java"),
    ("download/test-harness/S69RealSeed.java",  "test-harness/S69RealSeed.java"),
    # fixtures (v1.2.0 battery + prior)
    ("research/69shubatw/fixtures/toc2_p1.html", "fixtures/toc2_p1.html"),
    ("research/69shubatw/fixtures/toc2_p2.html", "fixtures/toc2_p2.html"),
    ("research/69shubatw/fixtures/toc2_p3.html", "fixtures/toc2_p3.html"),
    ("research/69shubatw/fixtures/toc2_p4.html", "fixtures/toc2_p4.html"),
    ("research/69shubatw/fixtures/toc2_p5.html", "fixtures/toc2_p5.html"),
    ("research/69shubatw/fixtures/toc2b_p1.html", "fixtures/toc2b_p1.html"),
    ("research/69shubatw/fixtures/toc2b_p2.html", "fixtures/toc2b_p2.html"),
    ("research/69shubatw/fixtures/toc2c_p1.html", "fixtures/toc2c_p1.html"),
    ("research/69shubatw/fixtures/toc2d_p1.html", "fixtures/toc2d_p1.html"),
    ("research/69shubatw/fixtures/toc2d_p15.html", "fixtures/toc2d_p15.html"),
    ("research/69shubatw/fixtures/toc2e_p1.html", "fixtures/toc2e_p1.html"),
    ("research/69shubatw/fixtures/toc2f_p1.html", "fixtures/toc2f_p1.html"),
    ("research/69shubatw/fixtures/toc2f_p2.html", "fixtures/toc2f_p2.html"),
    ("research/69shubatw/fixtures/toc2g_p1.html", "fixtures/toc2g_p1.html"),
    ("research/69shubatw/fixtures/toc2g_p6soft.html", "fixtures/toc2g_p6soft.html"),
    ("research/69shubatw/fixtures/toc2h_p1.html", "fixtures/toc2h_p1.html"),
    ("research/69shubatw/fixtures/toc2h_p2.html", "fixtures/toc2h_p2.html"),
    # LIVE family evidence (wcshuba.com — same CMS, not WAF'd)
    ("research/69shubatw/wc_home.html",        "evidence-wcshuba/wc_home.html"),
    ("research/69shubatw/wc_book.html",        "evidence-wcshuba/wc_book.html"),
    ("research/69shubatw/wc_chapterlist.html", "evidence-wcshuba/wc_chapterlist.html"),
    ("research/69shubatw/wc_cl_p2.html",       "evidence-wcshuba/wc_cl_p2.html"),
    ("research/69shubatw/wc_cl_p3.html",       "evidence-wcshuba/wc_cl_p3.html"),
    ("research/69shubatw/com_home.html",       "evidence-wcshuba/com_home.html"),
    ("research/69shubatw/com_toc.html",        "evidence-wcshuba/com_toc.html"),
]

def main():
    if os.path.exists(OUT):
        os.remove(OUT)
    n, total = 0, 0
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for src, arc in FILES:
            p = os.path.join(BASE, src)
            if not os.path.exists(p):
                print(f"MISSING (skipped): {src}")
                continue
            z.write(p, arc)
            n += 1
            total += os.path.getsize(p)
    size = os.path.getsize(OUT)
    sha = hashlib.sha256(open(OUT, "rb").read()).hexdigest()[:16]
    with zipfile.ZipFile(OUT) as z:
        bad = z.testzip()
    print(f"{OUT}\n  files: {n}, raw: {total/1e6:.2f} MB, zip: {size/1e6:.2f} MB")
    print(f"  integrity: {'OK' if bad is None else 'CORRUPT: ' + bad}")
    print(f"  sha256[:16]: {sha}")

if __name__ == "__main__":
    main()
