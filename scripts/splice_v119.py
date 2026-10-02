#!/usr/bin/env python3
"""Idempotent splice of the 11 tag-pick select filters into wtrlab.lua's getFilterList.
Inserts research/tag_pickers.lua (wrapped in [TAG PICKERS BEGIN]/[END] markers)
between the tag_operator block and the end of the filter list. Also refreshes the
Tag Search section comment + field labels for v1.1.9.
"""
import re, sys

PLUGIN = "/home/z/my-project/download/wtrlab.lua"
BLOCK = open("/home/z/my-project/research/tag_pickers.lua", encoding="utf-8").read().rstrip("\n")

src = open(PLUGIN, encoding="utf-8").read()

if "[TAG PICKERS BEGIN]" in src:
    # refresh in place: replace old block
    src = re.sub(r"        -- \[TAG PICKERS BEGIN\].*?-- \[TAG PICKERS END\]", BLOCK, src, flags=re.S)
    print("refreshed existing TAG PICKERS block")
else:
    anchor = '''        {
            type = "select",
            key = "tag_operator",
            label = "Tag (And/Or)",
            defaultValue = "and",
            options = {
                {value = "and", label = "And"},
                {value = "or", label = "Or"}
            }
        }
    }
end'''
    replacement = '''        {
            type = "select",
            key = "tag_operator",
            label = "Tag (And/Or)",
            defaultValue = "and",
            options = {
                {value = "and", label = "And"},
                {value = "or", label = "Or"}
            }
        },
''' + BLOCK + '''
    }
end'''
    if anchor not in src:
        print("ANCHOR NOT FOUND — getFilterList tail changed; inspect manually")
        sys.exit(1)
    src = src.replace(anchor, replacement, 1)
    print("inserted TAG PICKERS block")

# refresh the Tag Search section comment + labels (v1.1.9 wording)
old_comment = '''        -- ── Tag Search (replaces the 11 grouped tristate pickers, v1.1.8) ──
        -- 882 chips made the sheet unusable; now: one category picker +
        -- two keyword fields. Keywords resolve to tag ids at apply time
        -- (see tagSearchResolve); a keyword matching no tag raises a
        -- clear error so a typo never silently filters nothing.'''
new_comment = '''        -- ── Tag Search (keywords) + visible Tag pickers (v1.1.9) ──────────
        -- Two keyword fields (below) + one dropdown per site category
        -- (after Tag And/Or). Keywords resolve at apply time with
        -- autocomplete-like feedback: an ambiguous or unknown keyword
        -- raises an error that LISTS the matching tag names, so typos
        -- never silently filter nothing and short prefixes ("sys")
        -- show you the real tag names ("System"). "keyword*" includes
        -- every matching tag; multi-word phrases match as phrases.
        -- The category picker scopes the keyword fields; each Tags:
        -- dropdown lists that category's tags alphabetically.'''
if old_comment in src:
    src = src.replace(old_comment, new_comment, 1)
    print("updated Tag Search section comment")
else:
    print("note: Tag Search section comment already updated or moved")

src = src.replace(
    'label = "Tag Search - include (keywords or ids)"',
    'label = "Tag Search - include (name, id, or name*)"', 1)
src = src.replace(
    'label = "Tag Search - exclude (keywords or ids)"',
    'label = "Tag Search - exclude (name, id, or name*)"', 1)

open(PLUGIN, "w", encoding="utf-8").write(src)
lines = src.count("\\n") + 1
print(f"OK: {PLUGIN} now {len(src)} bytes")
