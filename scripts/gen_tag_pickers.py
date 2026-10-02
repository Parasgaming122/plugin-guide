#!/usr/bin/env python3
"""Generate the 11 per-category tag-pick select filter blocks for wtrlab.lua v1.1.9.
Reads research/tags_live_v3.json (live site dump). Emits research/tag_pickers.lua
wrapped in [TAG PICKERS BEGIN]/[END] markers for idempotent splicing.
"""
import json, sys

data = json.load(open("/home/z/my-project/research/tags_live_v3.json"))
groups = {str(g["id"]): g["name"] for g in data["groups"]}
ung = data["ungrouped"]

from collections import defaultdict
cats = defaultdict(list)
for t in ung:
    cats[str(t["category_id"])].append((str(t["value"]), t["label"].strip()))

# duplicate label check (exact-match resolution safety)
from collections import Counter
all_labels = Counter(t["label"].strip().lower() for t in ung)
dupes = [l for l, c in all_labels.items() if c > 1]
if dupes:
    print(f"DUPLICATE LABELS FOUND: {dupes}")
    sys.exit(1)

total = sum(len(v) for v in cats.values())
assert total == 888, f"expected 888 tags, got {total}"
assert len(cats) == 11

out = []
out.append("        -- ── Tag pickers (v1.1.9): one dropdown per site category ──────")
out.append("        -- The tags now SHOW UP: each picker lists its category's tags")
out.append("        -- alphabetically (the app sorts options). Pick one tag to")
out.append("        -- include it; combine with the Tag Search keyword fields and")
out.append("        -- the category-scoped pickers as needed. (Exclude via the")
out.append("        -- Tag Search - exclude keyword field.)")
out.append("        -- [TAG PICKERS BEGIN]")
for cid in sorted(cats, key=int):
    name = groups[cid]
    tags = sorted(cats[cid], key=lambda x: x[1].lower())
    out.append(f'        -- cat {cid}: {name} ({len(tags)} tags)')
    out.append("        {")
    out.append('            type = "select",')
    out.append(f'            key = "tag_pick_{cid}",')
    out.append(f'            label = "Tags: {name} ({len(tags)})",')
    out.append('            defaultValue = "",')
    out.append("            options = {")
    out.append('                {value = "", label = "Any"},')
    for tid, label in tags:
        assert "|" not in label and '"' not in label and "\\" not in label, f"bad char in label: {label!r}"
        out.append(f'                {{value = "{tid}", label = "{label}"}},')
    out.append("            }")
    out.append("        },")
out.append("        -- [TAG PICKERS END]")

block = "\n".join(out)
open("/home/z/my-project/research/tag_pickers.lua", "w", encoding="utf-8").write(block + "\n")
print(f"OK: wrote research/tag_pickers.lua  ({len(block.splitlines())} lines, {total} tag options)")
for cid in sorted(cats, key=int):
    print(f"  tag_pick_{cid}: {groups[cid]} — {len(cats[cid])} options")
