#!/usr/bin/env python3
"""build_structured_zip_20260930.py — the definitive project archive.

Layout (per the user's spec: README.md linking each file, /docs for md,
/test for tests, etc):

  noveLA-plugins-20260930/
  ├── README.md                  master manifest — links EVERY file
  ├── plugins/                   6 production .lua plugins
  ├── docs/                      all documentation (.md)
  ├── test/                      all test harnesses + fixtures + runner
  │   ├── README.md              how to compile & run + path relocation
  │   ├── run_all.sh             one-command full suite
  │   ├── *.java                 7 suites + SyntaxCheck
  │   ├── lib/, lib2/            jars (luaj, jsoup, gson, ecj, okhttp)
  │   └── fixtures/              every fixture the suites read
  ├── scripts/                   build pipeline + research scripts
  └── source-parts/              hand-written Lua source parts per plugin
"""
import os, shutil, zipfile, hashlib, subprocess, datetime

BASE = "/home/z/my-project"
DL = f"{BASE}/download"
OUT_ROOT = f"{DL}/noveLA-plugins-20260930"
ZIP = f"{DL}/noveLA-plugins-20260930.zip"

if os.path.exists(OUT_ROOT):
    shutil.rmtree(OUT_ROOT)
os.makedirs(OUT_ROOT)

def cp(src, dst):
    dst = os.path.join(OUT_ROOT, dst)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)

def cptree(src, dst):
    dst = os.path.join(OUT_ROOT, dst)
    if os.path.isdir(src):
        shutil.copytree(src, dst, dirs_exist_ok=True)
    else:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)

# ── 1. plugins ────────────────────────────────────────────────────────────
PLUGINS = ["wtrlab.lua", "novel543.lua", "wuxiabox.lua", "oop.lua",
           "bixiange.lua", "69shubaTw.lua"]
for p in PLUGINS:
    cp(f"{DL}/{p}", f"plugins/{p}")

# ── 2. docs ───────────────────────────────────────────────────────────────
DOCS = [
    ("MAINTENANCE.md", "MAINTENANCE.md"),
    ("README.md", "wtrlab_README.md"),          # was the wtrlab plugin README
    ("pull_request.md", "wtrlab_pull_request.md"),
    ("wtrlab_50ch_test.md", "wtrlab_50ch_test.md"),
    ("novel543_pull_request.md", "novel543_pull_request.md"),
    ("wuxiabox_pull_request.md", "wuxiabox_pull_request.md"),
    ("oop_pull_request.md", "oop_pull_request.md"),
    ("bixiange_pull_request.md", "bixiange_pull_request.md"),
    ("69shubatw_pull_request.md", "69shubatw_pull_request.md"),
]
for src, dst in DOCS:
    cp(f"{DL}/{src}", f"docs/{dst}")

# ── 3. test ───────────────────────────────────────────────────────────────
H = f"{DL}/test-harness"
TE = f"{BASE}/testenv"
TESTS = ["LuaTest.java", "Novel543Test.java", "WuxiaboxTest.java", "OopTest.java",
         "BixiangeTest.java", "S69TwTest.java", "S69RealSeed.java", "SyntaxCheck.java"]
for t in TESTS:
    # prefer the canonical download/test-harness copy (synced with testenv)
    src = f"{H}/{t}" if os.path.exists(f"{H}/{t}") else f"{TE}/{t}"
    cp(src, f"test/{t}")

# runner (portable version: relative paths, works wherever the archive extracts)
cp(f"{BASE}/scripts/zip_readme/run_all.sh", "test/run_all.sh")

# jars
cptree(f"{TE}/lib", "test/lib")
cptree(f"{TE}/lib2", "test/lib2")

# fixtures: everything the suites read, under their relative names
R = f"{BASE}/research"
for f in ["arr_sample.txt", "reader1.json", "terms_93618.json"]:
    cp(f"{R}/{f}", f"test/fixtures/{f}")
cptree(f"{R}/wuxiabox", "test/fixtures/wuxiabox")
cptree(f"{R}/newsites", "test/fixtures/newsites")
cptree(f"{R}/69shubatw/fixtures", "test/fixtures/69shubatw")

# today's suite logs (evidence)
cptree(f"{BASE}/tool-results", "test/logs-20260930")
# clean non-log files if any
lr = os.path.join(OUT_ROOT, "test/logs-20260930")
for f in os.listdir(lr):
    if not f.startswith("test_") or not f.endswith(".log"):
        os.remove(os.path.join(lr, f))

# ── 4. scripts ────────────────────────────────────────────────────────────
S = f"{BASE}/scripts"
for entry in sorted(os.listdir(S)):
    full = os.path.join(S, entry)
    if entry.startswith("debug_") or entry == "zip_readme":
        continue  # debug scratch + this archive's own readme staging dir
    cptree(full, f"scripts/{entry}")

# ── 5. source-parts ───────────────────────────────────────────────────────
for d in ["69shubatw_plugin", "bixiange_plugin", "oop_plugin", "wuxiabox_plugin"]:
    cptree(f"{S}/{d}", f"source-parts/{d.replace('_plugin', '')}")

# ── 6. READMEs (written in scripts/zip_readme/) ───────────────────────────
cp(f"{BASE}/scripts/zip_readme/README.md", "README.md")
cp(f"{BASE}/scripts/zip_readme/test_README.md", "test/README.md")

print("staged tree:")
total = 0
for root, dirs, files in os.walk(OUT_ROOT):
    dirs.sort()
    for f in sorted(files):
        p = os.path.join(root, f)
        total += os.path.getsize(p)
print(f"  {total/1e6:.2f} MB raw")

# ── 6. zip ────────────────────────────────────────────────────────────────
if os.path.exists(ZIP):
    os.remove(ZIP)
zf = zipfile.ZipFile(ZIP, "w", zipfile.ZIP_DEFLATED, compresslevel=9)
n = 0
for root, dirs, files in os.walk(OUT_ROOT):
    dirs.sort()
    for f in sorted(files):
        p = os.path.join(root, f)
        arc = os.path.join("noveLA-plugins-20260930", os.path.relpath(p, OUT_ROOT))
        zf.write(p, arc)
        n += 1
zf.close()

sz = os.path.getsize(ZIP)
sha = hashlib.sha256(open(ZIP, "rb").read()).hexdigest()[:16]
print(f"zip: {ZIP}")
print(f"  {n} files, {sz/1e6:.2f} MB, sha256[:16] {sha}")

# integrity check
bad = zipfile.ZipFile(ZIP).testzip()
print("  integrity:", "OK" if bad is None else f"CORRUPT: {bad}")
