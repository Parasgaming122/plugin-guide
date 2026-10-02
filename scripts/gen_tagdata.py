#!/usr/bin/env python3
"""Generate the compact tag data string for the Lua plugin."""
import json

data = json.load(open('/home/z/my-project/wtrlab-analysis/tags_full.json'))
cats = {int(k): v for k, v in data['categories'].items()}
tags = data['tags']

# group by category
bycat = {}
for t in tags:
    bycat.setdefault(t['category_id'], []).append(t)

# check for separator conflicts
for t in tags:
    label = t['label']
    assert '=' not in label and ';' not in label and '\n' not in label, f"conflict: {label}"

out = []
order = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
catnames = {1: "Protagonist", 2: "Power Systems", 3: "Worldbuilding", 4: "Socio-Political",
            5: "Relationships", 6: "Narrative", 7: "Beings & Factions", 8: "Professional",
            9: "Tone & Atmosphere", 10: "Adaptations", 11: "Miscellaneous"}

total = 0
for cat in order:
    entries = sorted(bycat.get(cat, []), key=lambda x: x['label'].lower())
    parts = [f"{t['value']}={t['label']}" for t in entries]
    total += len(parts)
    s = (catnames[cat] + "\n" + ";".join(parts))
    out.append(s)

print(f"total tags: {total}")
with open('/home/z/my-project/wtrlab-analysis/tagdata.lua.txt', 'w', encoding='utf-8') as f:
    f.write("<<<TAGDATA>>>\n")
    for s in out:
        f.write("[[<" + s + ">]]\n")
print("written")

# Also generate genre list check
genres = {1:"Action",2:"Adult",3:"Adventure",4:"Comedy",5:"Drama",6:"Ecchi",7:"Erciyuan",8:"Fan-fiction",9:"Fantasy",10:"Game",11:"Gender Bender",12:"Harem",13:"Historical",14:"Horror",15:"Josei",16:"Martial Arts",17:"Mature",18:"Mecha",19:"Military",20:"Mystery",21:"Psychological",22:"Romance",23:"School Life",24:"Sci-fi",25:"Seinen",26:"Shoujo",27:"Shoujo-ai",28:"Shounen",29:"Shounen-ai",30:"Slice of Life",31:"Smut",32:"Sports",33:"Supernatural",34:"Tragedy",35:"Urban Life",36:"Wuxia",37:"Xianxia",38:"Xuanhuan",39:"Yaoi",40:"Yuri"}
print(f"genres: {len(genres)}")
