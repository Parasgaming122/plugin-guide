#!/usr/bin/env python3
"""Patch 69shubaTw.lua to v1.1.0.

Replaces part3.lua's TOC core and chapter-list sections with the v1.1.0
three-layer implementation (real /indexlist/ + book-page seed + #pb_next
walk), bumps the version, reassembles download/69shubaTw.lua.
"""
import os

PDIR = "/home/z/my-project/scripts/69shubatw_plugin"
PART3 = os.path.join(PDIR, "part3.lua")
PART1 = os.path.join(PDIR, "part1.lua")

def read(p):
    return open(p, encoding="utf-8").read()

def main():
    # ── part1: version bump + header note (idempotent) ───────────────────
    p1 = read(PART1)
    if 'local VERSION = "1.0.0"' in p1:
        p1 = p1.replace('local VERSION = "1.0.0"', 'local VERSION = "1.1.0"')
        open(PART1, "w", encoding="utf-8").write(p1)
    else:
        assert 'local VERSION = "1.1.0"' in p1, "unexpected part1 version state"

    # ── part3: replace TOC core + chapter-list sections ──────────────────
    p3 = read(PART3)

    toc_new = read(os.path.join(PDIR, "part3_toc_v110.lua")).rstrip("\n")
    clist_new = read(os.path.join(PDIR, "part3_clist_v110.lua")).rstrip("\n")

    # Region A: from the "Chapter catalog" banner through tocShowUnreachable
    lines = p3.split("\n")
    a_line = next(i for i, l in enumerate(lines) if l.startswith("-- Chapter catalog"))
    a_start = sum(len(l) + 1 for l in lines[:a_line - 1])  # include the banner line above
    a_end_marker = '      "retry resumes where the last one stopped.")\n  end\nend\n'
    a_end = p3.index(a_end_marker) + len(a_end_marker)
    p3 = p3[:a_start] + toc_new + p3[a_end:]

    # Region B: from the "Chapter list — solver-safe walk" banner to EOF of part3
    lines = p3.split("\n")
    b_line = next(i for i, l in enumerate(lines) if l.startswith("-- Chapter list — "))
    b_start = sum(len(l) + 1 for l in lines[:b_line - 1])  # include the banner line above
    # the old section runs to the end of part3 (getChapterList is the last function)
    p3 = p3[:b_start] + clist_new + "\n"

    open(PART3, "w", encoding="utf-8").write(p3)
    print(f"part3.lua patched: {p3.count(chr(10))} lines")

    # sanity: exactly one definition of each function
    all_fns = ("parseTocChapters", "tocTotalPages", "tocNextLink", "tocPageBase",
               "seedFromBookPage", "seedFromMemo", "tocSeedUrls", "tocCacheLoad",
               "tocMerge", "tocCacheSave", "unionByCid", "chaseTotalPages",
               "walkEnsure", "tocFetchPage1", "tocFetchPageN", "finalizeToc",
               "tocShowUnreachable", "tocPrefKey", "cidFromUrl",
               "parsePage", "getChapterList")
    for fn in all_fns:
        c = p3.count(f"local function {fn}(") + p3.count(f"\nfunction {fn}(")
        status = "OK" if c == 1 else f"!! {c}"
        print(f"  {fn:22s} {status}")
    # v1.0.0 internals that must be gone
    for gone in ("tocIndexlistPath", "tocFetchPage"):
        c = p3.count(f"local function {gone}(")
        print(f"  {gone:22s} {'GONE' if c == 0 else 'STILL PRESENT !!'}")

if __name__ == "__main__":
    main()
