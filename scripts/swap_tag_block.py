#!/usr/bin/env python3
"""Swap (or refresh) the 11 category-grouped tag tristate blocks in wtrlab.lua.

Idempotent: works whether the plugin currently has
  (a) the old single flat `key = "tags"` tristate (first run after 2.1.0), or
  (b) the 11 grouped blocks already in place (subsequent refreshes).

Run after `gen_grouped_tags.py` whenever research/real_tags.json is updated
(i.e. the site added/removed tags). The generator emits the canonical 11
blocks; this script splices them in, matching the start of the first tag
group (tags_protagonist) through the end of the last (tags_misc).
"""
import sys

PLUGIN = "/home/z/my-project/download/wtrlab.lua"
GEN    = "/home/z/my-project/scripts/grouped_tags.lua.txt"

src = open(PLUGIN, encoding="utf-8").read()
grouped = open(GEN, encoding="utf-8").read().strip()
if grouped.endswith(','):
    grouped = grouped[:-1]  # last entry has no trailing comma

# The grouped blocks sit between the `tag_operator` select (always present,
# immediately before the tag groups) and the `    }` + `end` that close
# getFilterList's return array and the function. Both the flat and grouped
# layouts share this tail, so we anchor on it.
tail = '            }\n        }\n    }\nend\n'  # options-close, entry-close, return-close, func-end

if 'key = "tags_protagonist"' in src:
    # (b) grouped already present — refresh in place. Anchor from the first
    # tag-group entry's opening brace to the shared tail.
    start = '        {\n            type = "tristate",\n            key = "tags_protagonist",\n'
    assert start in src, "tags_protagonist anchor not found"
    assert tail in src, "getFilterList tail anchor not found"
    i = src.index(start)
    j = src.index(tail, i) + len(tail)
elif 'key = "tags"' in src:
    # (a) legacy flat `tags` block — replace it (one-shot migration).
    start = '        {\n            type = "tristate",\n            key = "tags",\n            label = "Tags",\n            options = {\n'
    assert start in src, "flat tags anchor not found"
    assert tail in src, "getFilterList tail anchor not found"
    i = src.index(start)
    j = src.index(tail, i) + len(tail)
else:
    sys.exit("ERROR: no tag block (flat or grouped) found in " + PLUGIN)

replacement = grouped + '\n    }\nend\n'
new_src = src[:i] + replacement + src[j:]
assert new_src != src, "no change made"
assert 'key = "tags_protagonist"' in new_src
assert 'key = "tags_misc"' in new_src

open(PLUGIN, "w", encoding="utf-8").write(new_src)
print("Refreshed 11 tag-group blocks in %s (%d bytes, %d lines)" %
      (PLUGIN, len(new_src), new_src.count("\n") + 1))
