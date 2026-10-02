#!/usr/bin/env python3
"""Generate the getFilterList section with all 882 tags and append to the plugin."""
import json

data = json.load(open('/home/z/my-project/wtrlab-analysis/tags_full.json'))
tags = data['tags']

bycat = {}
for t in tags:
    bycat.setdefault(t['category_id'], []).append(t)

catnames = {1: "Protagonist", 2: "Power Systems", 3: "Worldbuilding", 4: "Socio-Political",
            5: "Relationships", 6: "Narrative", 7: "Beings & Factions", 8: "Professional",
            9: "Tone & Atmosphere", 10: "Adaptations", 11: "Miscellaneous"}
keys = {1: "tags_protagonist", 2: "tags_power", 3: "tags_world", 4: "tags_socio",
        5: "tags_relationship", 6: "tags_narrative", 7: "tags_beings",
        8: "tags_professional", 9: "tags_tone", 10: "tags_adaptations", 11: "tags_misc"}


def lua_options(entries):
    parts = []
    for t in sorted(entries, key=lambda x: x['label'].lower()):
        label = t['label'].replace('\\', '\\\\').replace('"', '\\"')
        parts.append('            { value = "%s", label = "%s" }' % (t['value'], label))
    return ",\n".join(parts)


out = []
out.append("""
-- ── Filter list ────────────────────────────────────────────────────────────
-- Complete mirror of https://wtr-lab.com/en/novel-finder (all 882 tags).

function getFilterList()
    local filters = {}
    local function add(f)
        filters[#filters + 1] = f
    end

    local function selectFilter(key, label, default, options)
        add({
            type = "select",
            key = key,
            label = label,
            defaultValue = default,
            options = options
        })
    end

    local function triStateFilter(key, label, options)
        add({
            type = "tristate",
            key = key,
            label = label,
            options = options
        })
    end
""")

# orderBy
out.append("""    selectFilter("orderBy", "Sort by", "update", {
        { value = "update", label = "Update Date" },
        { value = "date", label = "Addition Date" },
        { value = "daily_rank", label = "Daily View" },
        { value = "weekly_rank", label = "Weekly View" },
        { value = "monthly_rank", label = "Monthly View" },
        { value = "view", label = "All-Time View" },
        { value = "name", label = "Name" },
        { value = "reader", label = "Reader" },
        { value = "chapter", label = "Chapter Count" },
        { value = "character", label = "Character Count" },
        { value = "rating", label = "Rating" },
        { value = "total_rate", label = "Review Count" },
        { value = "vote", label = "Vote Count" },
        { value = "weighted", label = "Weighted Rating [Beta]" },
        { value = "random", label = "Random" }
    })

    selectFilter("order", "Sort direction", "desc", {
        { value = "desc", label = "Descending" },
        { value = "asc", label = "Ascending" }
    })
""")

# status tristate
out.append("""    triStateFilter("status", "Status", {
        { value = "ongoing", label = "Ongoing" },
        { value = "completed", label = "Completed" },
        { value = "hiatus", label = "Hiatus" },
        { value = "dropped", label = "Dropped" }
    })
""")

# release_status
out.append("""    selectFilter("release_status", "Release status", "all", {
        { value = "all", label = "All" },
        { value = "released", label = "Released" },
        { value = "voting", label = "On Voting" }
    })
""")

# addition_age
out.append("""    selectFilter("addition_age", "Added", "all", {
        { value = "all", label = "Any time" },
        { value = "day", label = "< 2 Days" },
        { value = "week", label = "< 1 Week" },
        { value = "month", label = "< 1 Month" },
        { value = "3month", label = "< 3 Months" },
        { value = "6month", label = "< 6 Months" },
        { value = "year", label = "< 1 Year" },
        { value = "last_month", label = "Last Month" },
        { value = "last_year", label = "Last Year" },
        { value = "this_year", label = "This Year" }
    })
""")

# count filters: type, direction, value
out.append("""    selectFilter("count_type", "Count filter type", "chapter", {
        { value = "chapter", label = "Chapters" },
        { value = "character", label = "Characters" }
    })

    selectFilter("count_filter", "Count filter direction", "min", {
        { value = "min", label = "Minimum (at least)" },
        { value = "max", label = "Maximum (at most)" }
    })

    selectFilter("count_value", "Chapter count", "none", {
        { value = "none", label = "Any Chapters" },
        { value = "100", label = "100 Chapters" },
        { value = "150", label = "150 Chapters" },
        { value = "200", label = "200 Chapters" },
        { value = "250", label = "250 Chapters" },
        { value = "500", label = "500 Chapters" },
        { value = "750", label = "750 Chapters" },
        { value = "1000", label = "1000 Chapters" },
        { value = "1500", label = "1500 Chapters" },
        { value = "2000", label = "2000 Chapters" },
        { value = "2500", label = "2500 Chapters" },
        { value = "5000", label = "5000 Chapters" }
    })
""")

# min rating (41 options 1.0-5.0)
rating_opts = ['        { value = "none", label = "Any Rating" }']
for i in range(41):
    v = "%.1f" % (1.0 + 0.1 * i)
    rating_opts.append('        { value = "%s", label = "%s+ Stars" }' % (v, v))
out.append("""    selectFilter("min_rating", "Minimum rating", "none", {
%s
    })
""" % (",\n".join(rating_opts)))

# min reviews (5-50)
review_opts = ['        { value = "none", label = "Any" }']
for i in range(10):
    v = str((i + 1) * 5)
    review_opts.append('        { value = "%s", label = "%s+ Reviews" }' % (v, v))
out.append("""    selectFilter("min_reviews", "Minimum review count", "none", {
%s
    })
""" % (",\n".join(review_opts)))

# genre operator + genres tristate
genres = {1: "Action", 2: "Adult", 3: "Adventure", 4: "Comedy", 5: "Drama", 6: "Ecchi",
          7: "Erciyuan", 8: "Fan-fiction", 9: "Fantasy", 10: "Game", 11: "Gender Bender",
          12: "Harem", 13: "Historical", 14: "Horror", 15: "Josei", 16: "Martial Arts",
          17: "Mature", 18: "Mecha", 19: "Military", 20: "Mystery", 21: "Psychological",
          22: "Romance", 23: "School Life", 24: "Sci-fi", 25: "Seinen", 26: "Shoujo",
          27: "Shoujo-ai", 28: "Shounen", 29: "Shounen-ai", 30: "Slice of Life", 31: "Smut",
          32: "Sports", 33: "Supernatural", 34: "Tragedy", 35: "Urban Life", 36: "Wuxia",
          37: "Xianxia", 38: "Xuanhuan", 39: "Yaoi", 40: "Yuri"}
genre_opts = []
for gid in sorted(genres):
    genre_opts.append('        { value = "%d", label = "%s" }' % (gid, genres[gid]))
out.append("""    selectFilter("genre_operator", "Genres: match mode", "and", {
        { value = "and", label = "Match ALL selected genres (and)" },
        { value = "or", label = "Match ANY selected genre (or)" }
    })

    triStateFilter("genres", "Genres (include / exclude)", {
%s
    })
""" % (",\n".join(genre_opts)))

# tag operator
out.append("""    selectFilter("tag_operator", "Tags: match mode", "and", {
        { value = "and", label = "Match ALL selected tags (and)" },
        { value = "or", label = "Match ANY selected tag (or)" }
    })
""")

# tag categories
for cat in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]:
    entries = bycat.get(cat, [])
    out.append("""    triStateFilter("%s", "Tags: %s (%d)", {
%s
    })
""" % (keys[cat], catnames[cat], len(entries), lua_options(entries)))

out.append("""    return filters
end
""")

section = "\n".join(out)
with open('/home/z/my-project/download/wtrlab.lua', 'a', encoding='utf-8') as f:
    f.write(section)

total = sum(len(v) for v in bycat.values())
print(f"Appended filter section with {total} tags across {len(bycat)} categories")
