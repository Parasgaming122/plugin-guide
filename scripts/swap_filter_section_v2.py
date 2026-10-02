#!/usr/bin/env python3
"""Replace the 11 grouped tag tristate filters with the compact v2 Tag Search
section (category picker + keyword fields), keeping the tag_operator select."""

PLUGIN = '/home/z/my-project/download/wtrlab.lua'
src = open(PLUGIN, encoding='utf-8').read()

start_marker = '''        {
            type = "select",
            key = "tag_operator",
            label = "Tag (And/Or)",
            defaultValue = "and",
            options = {
                {value = "and", label = "And"},
                {value = "or", label = "Or"}
            }
        },
'''
end_marker = '''    }
end

-- ── Filtered catalog ─────────────────────────────────────────────────────────
'''

start = src.index(start_marker)
end = src.index(end_marker)

new_block = '''        -- ── Tag Search (replaces the 11 grouped tristate pickers, v1.1.8) ──
        -- 882 chips made the sheet unusable; now: one category picker +
        -- two keyword fields. Keywords resolve to tag ids at apply time
        -- (see tagSearchResolve); a keyword matching no tag raises a
        -- clear error so a typo never silently filters nothing.
        {
            type = "select",
            key = "tag_category",
            label = "Tag Search Category",
            defaultValue = "0",
            options = {
                {value = "0", label = "All Categories"},
                {value = "1", label = "Protagonist Archetypes"},
                {value = "2", label = "Power Systems"},
                {value = "3", label = "Worldbuilding"},
                {value = "4", label = "Socio-Political Structures"},
                {value = "5", label = "Relationship Tropes"},
                {value = "6", label = "Narrative"},
                {value = "7", label = "Beings & Factions"},
                {value = "8", label = "Professional Archetypes"},
                {value = "9", label = "Tone & Atmosphere"},
                {value = "10", label = "Adaptations"},
                {value = "11", label = "Miscellaneous Narrative Elements"}
            }
        },
        {
            type = "text",
            key = "tag_search_inc",
            label = "Tag Search - include (keywords or ids)",
            defaultValue = ""
        },
        {
            type = "text",
            key = "tag_search_exc",
            label = "Tag Search - exclude (keywords or ids)",
            defaultValue = ""
        },
        {
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
end

-- ── Filtered catalog ─────────────────────────────────────────────────────────
'''

src = src[:start] + new_block + src[end + len(end_marker):]
open(PLUGIN, 'w', encoding='utf-8').write(src)
removed = end - start
print(f"removed {removed} chars of grouped tag filters; inserted {len(new_block)} chars")
print(f"file is now {len(src.splitlines())} lines")
