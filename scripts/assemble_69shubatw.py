#!/usr/bin/env python3
"""Assemble 69shubaTw.lua from parts 1-4 and validate basic shape."""
import os

PARTS_DIR = "/home/z/my-project/scripts/69shubatw_plugin"
OUT = "/home/z/my-project/download/69shubaTw.lua"

def main():
    chunks = []
    for n in (1, 2, 3, 4):
        p = os.path.join(PARTS_DIR, f"part{n}.lua")
        chunks.append(open(p, encoding="utf-8").read().rstrip("\n"))
    lua = "\n\n".join(chunks) + "\n"
    open(OUT, "w", encoding="utf-8").write(lua)
    lines = lua.count("\n")
    print(f"assembled {OUT}: {lines} lines, {len(lua.encode())} bytes")
    # sanity: required functions present exactly once
    for fn in ("getCatalogList", "getCatalogFiltered", "getFilterList",
               "getCatalogSearch", "getBookTitle", "getBookCoverImageUrl",
               "getBookDescription", "getBookGenres", "getBookStatus",
               "getBookLastUpdate", "getChapterListHash", "parsePage",
               "getChapterList", "getChapterText", "getUserAgentPreset",
               "getSettingsSchema"):
        c = lua.count(f"function {fn}(")
        status = "OK" if c == 1 else f"!! {c}"
        print(f"  {fn:26s} {status}")
    for k in ("cf_options", 'id       = "69shubaTw"', "trigger_markers"):
        print(f"  {k:26s} {'OK' if k in lua else 'MISSING'}")

if __name__ == "__main__":
    main()
