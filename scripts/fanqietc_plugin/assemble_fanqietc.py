#!/usr/bin/env python3
"""Assemble fanqietc.lua v1.0.0 from source parts and validate.

Part order (Lua locals must be declared before use at compile time):
  part1_header      — metadata + settings keys + shared utilities (nowMs, hasCJK)
  part3_translator  — Translator core (needs nowMs/hasCJK from part1)
  part2_api         — API layer (needs translator's trActive/translateBatch)
  part4_catalog     — catalog/search/filters/self-test (needs API + translator)
  part5_book        — book details/chapters/text + settings schema

Also statically checks the metadata block the way NoveLA's
ExtensionsManagerViewModel.luaField() does — version MUST be a quoted literal.
"""
import re
import sys
from pathlib import Path

BASE = Path("/home/z/my-project/scripts/fanqietc_plugin")
OUT = Path("/home/z/my-project/download/fanqietc.lua")

PARTS = [
    "part1_header.lua",
    "part3_translator.lua",
    "part2_api.lua",
    "part4_catalog.lua",
    "part5_book.lua",
]


def main() -> int:
    chunks = []
    for name in PARTS:
        p = BASE / name
        text = p.read_text(encoding="utf-8")
        chunks.append(f"-- ══ source part: {name} " + "═" * 30 + "\n" + text)
        print(f"  + {name:24s} {len(text):6d} chars")
    assembled = "\n".join(chunks) + "\n"

    OUT.write_text(assembled, encoding="utf-8")
    print(f"\nWrote {OUT} ({len(assembled)} chars, {assembled.count(chr(10))} lines)")

    # ── Lua syntax validation ────────────────────────────────────────────
    try:
        from luaparser import ast
    except ImportError:
        print("WARNING: luaparser unavailable — skipping syntax check")
    else:
        try:
            ast.parse(assembled)
            print("Lua syntax: OK (luaparser)")
        except Exception as e:
            print(f"Lua syntax ERROR: {e}")
            return 1

    # ── Metadata checks (mirror the app's static regex) ──────────────────
    def lua_field(key: str) -> str:
        m = re.search(rf"(?m)^\s*{key}\s*=\s*[\"']([^\"']+)[\"']", assembled)
        return m.group(1) if m else ""

    problems = []
    for key in ("id", "name", "version", "baseUrl", "language"):
        v = lua_field(key)
        if not v:
            problems.append(f"metadata field '{key}' not a quoted literal")
        else:
            print(f"  metadata {key:8s} = {v!r}")

    if re.search(r"(?m)^\s*version\s*=\s*VERSION\b", assembled):
        problems.append("version = VERSION variable form found (regex conflict!)")

    # ── Required API surface ─────────────────────────────────────────────
    required = [
        "getCatalogList", "getCatalogSearch", "getChapterList",
        "getChapterText", "getBookTitle", "getBookCoverImageUrl",
        "getBookDescription", "getBookGenres", "getBookStatus",
        "getBookLastUpdate", "getFilterList", "getCatalogFiltered",
        "getSettingsSchema", "getChapterListHash", "getBookRating",
    ]
    for fn in required:
        if not re.search(rf"^function {fn}\(", assembled, re.M):
            problems.append(f"missing global function: {fn}")

    if problems:
        print("\nPROBLEMS:")
        for p in problems:
            print(f"  ✗ {p}")
        return 1
    print(f"\nAll checks passed — {len(required)} API functions present, "
          "version is a literal string")
    return 0


if __name__ == "__main__":
    sys.exit(main())
