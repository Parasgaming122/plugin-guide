#!/usr/bin/env python3
"""Inject verified genre/tag option lists into the wtrlab.lua plugin skeleton.

LEGACY / SUPERSEDED for tag refresh as of v2.1.1 — this script targets a
skeleton with `--@@GENRES@@` / `--@@TAGS@@` placeholders and emits a SINGLE
flat `tags` tristate. The shipped plugin (v2.1.1+) instead uses 11
category-grouped tristate pickers (NoveLA renders every tristate option as
an eagerly-built chip, so one 882-item list is unusable).

To refresh the tag list in the shipped plugin, use the two-step idempotent
workflow instead (see README §6):
    python3 scripts/gen_grouped_tags.py   # emit 11 grouped blocks from real_tags.json
    python3 scripts/swap_tag_block.py     # splice into download/wtrlab.lua (idempotent)

This script is retained only for bootstrapping a fresh skeleton from the
template with placeholders; genres are static and already inlined in the
shipped plugin.
"""
import json

PLUGIN = "/home/z/my-project/download/wtrlab.lua"
TAGS = "/home/z/my-project/research/real_tags.json"

# Genres: verified against SERIE_GENRES in site JS chunk 6aa165a60db32ec2.js
GENRES = [
    (1, "Action"), (2, "Adult"), (3, "Adventure"), (4, "Comedy"), (5, "Drama"),
    (6, "Ecchi"), (7, "Erciyuan"), (8, "Fan-fiction"), (9, "Fantasy"), (10, "Game"),
    (11, "Gender Bender"), (12, "Harem"), (13, "Historical"), (14, "Horror"),
    (15, "Josei"), (16, "Martial Arts"), (17, "Mature"), (18, "Mecha"),
    (19, "Military"), (20, "Mystery"), (21, "Psychological"), (22, "Romance"),
    (23, "School Life"), (24, "Sci-fi"), (25, "Seinen"), (26, "Shoujo"),
    (27, "Shoujo-ai"), (28, "Shounen"), (29, "Shounen-ai"), (30, "Slice of Life"),
    (31, "Smut"), (32, "Sports"), (33, "Supernatural"), (34, "Tragedy"),
    (35, "Urban Life"), (36, "Wuxia"), (37, "Xianxia"), (38, "Xuanhuan"),
    (39, "Yaoi"), (40, "Yuri"),
]

def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')

def lua_options(pairs, per_line=4):
    lines = []
    for i in range(0, len(pairs), per_line):
        chunk = pairs[i:i+per_line]
        lines.append("                " + " ".join(
            '{value = "%s", label = "%s"},' % (v, esc(l)) for v, l in chunk))
    return "\n".join(lines)

src = open(PLUGIN, encoding="utf-8").read()

genre_block = lua_options(GENRES, per_line=3)
assert "--@@GENRES@@" in src
src = src.replace("--@@GENRES@@", genre_block)

tags = json.load(open(TAGS, encoding="utf-8"))
pairs = [(str(t["value"]), t["label"]) for t in tags]
assert len(pairs) == 882, len(pairs)
# sanity: honghuang must be present
assert any(v == "801" and "Honghuang" in l for v, l in pairs)
tag_block = lua_options(pairs, per_line=3)
assert "--@@TAGS@@" in src
src = src.replace("--@@TAGS@@", tag_block)

open(PLUGIN, "w", encoding="utf-8").write(src)
print("Injected %d genres and %d tags. File size: %d bytes" % (len(GENRES), len(pairs), len(src)))
