#!/usr/bin/env python3
"""Generate the v2 tag-search index for wtrlab.lua from live site data.

Input:  research/tags_live_v2.json  (as extracted from /en/novel-finder __NEXT_DATA__)
Output: scripts/tag_search_index_v2.lua.txt  — lines "id|Label|catId"
        (embedded into the plugin between TAG_SEARCH_INDEX markers)

v2 format adds the category id so tagSearchResolve(text, cat) can scope
matching to one of the 11 site categories. 888 tags as of 2026-09-03.
"""
import json

SRC = '/home/z/my-project/research/tags_live_v2.json'
OUT = '/home/z/my-project/scripts/tag_search_index_v2.lua.txt'

data = json.load(open(SRC))
tags = sorted(data['ungrouped'], key=lambda t: (int(t['value'])))
groups = {g['id']: g['name'] for g in data['groups']}

lines = []
for t in tags:
    label = t['label'].strip()
    # '|' would break the format; none of the site labels contain it, but be safe.
    label = label.replace('|', '/')
    lines.append(f"{t['value']}|{label}|{t['category_id']}")

with open(OUT, 'w', encoding='utf-8') as f:
    f.write("\n".join(lines))

counts = {}
for t in tags:
    counts[t['category_id']] = counts.get(t['category_id'], 0) + 1

print(f"wrote {len(lines)} tags to {OUT}")
print("\n-- TAG_CATEGORIES block for the plugin (copy-paste):")
print("local TAG_CATEGORIES = {")
for gid in sorted(groups):
    print(f'    {{ id = "{gid}", label = "{groups[gid]} ({counts.get(gid, 0)})" }},')
print("}")
print(f"total = {len(tags)}")
