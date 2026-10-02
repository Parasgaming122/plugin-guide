#!/usr/bin/env python3
"""Compute the curated (actually-used) wuxiabox tag set.

Sources of "used" evidence:
 1. wtrlab taxonomy (research/real_tags.json, 882 tags wtr-lab novels are tagged with)
 2. POPULAR_TAGS in the current plugin (27 famous tropes)
 3. Tags observed on novel-page HTML fixtures (research/wuxiabox/*.html)
"""
import json, re, glob, unicodedata, os

WT = json.load(open("/home/z/my-project/research/wuxiabox/tags_raw.json"))       # 6723 {id,label,letter}
WTR = json.load(open("/home/z/my-project/research/real_tags.json"))               # 882 wtrlab tags

# The plugin's TAG_INDEX carries EXPANDED full names (989 truncated browsetags
# labels were expanded via the wtrlab cross-ref during the v2.0.0 build).
# Prefer those labels; fall back to the raw harvest label.
_plugin = open("/home/z/my-project/download/wuxiabox.lua", encoding="utf-8").read()
_idx = _plugin.split("BEGIN_TAG_INDEX")[1].split("END_TAG_INDEX")[0]
EXPANDED = {}
for line in _idx.splitlines():
    line = line.strip()
    if not line or line.startswith("--"):
        continue
    parts = line.split("|")
    if len(parts) >= 2:
        EXPANDED[parts[0]] = parts[1]
print(f"plugin TAG_INDEX expanded labels: {len(EXPANDED)}")
for t in WT:
    if t["id"] in EXPANDED:
        t["label"] = EXPANDED[t["id"]]

def norm(s):
    """Normalize a tag label: lowercase, strip spaces/punct/camelcase joins."""
    s = unicodedata.normalize("NFKD", s or "")
    s = s.lower()
    s = re.sub(r"[^a-z0-9\u4e00-\u9fff\u3040-\u30ff]+", "", s)
    return s

# wtrlab tag labels -> set of normalized names
wtr_names = set()
for t in WTR:
    lab = t.get("label") or t.get("name") or ""
    wtr_names.add(norm(lab))
print(f"wtrlab normalized names: {len(wtr_names)}")

# wuxiabox tags by normalized name
by_norm = {}
for t in WT:
    by_norm.setdefault(norm(t["label"]), []).append(t)

# 1) intersection
inter = {}
for n, tags in by_norm.items():
    if n in wtr_names:
        inter[n] = tags
print(f"wuxiabox ∩ wtrlab (by normalized name): {len(inter)} names")

# canonical id per name = LOWEST id (site's novel pages link the original listing)
def canonical(tags):
    return sorted(tags, key=lambda t: int(t["id"]))[0]

curated = {}  # norm -> (canonical tag, n_duplicates)
for n, tags in inter.items():
    curated[n] = (canonical(tags), len(tags))

# 2) POPULAR_TAGS from the plugin
plugin = open("/home/z/my-project/download/wuxiabox.lua", encoding="utf-8").read()
m = re.search(r"local POPULAR_TAGS = \{(.*?)\n\}", plugin, re.S)
pop_ids = set(re.findall(r'value\s*=\s*"(\d+)"', m.group(1))) if m else set()
print(f"POPULAR_TAGS ids in plugin: {len(pop_ids)}")

# 3) tags on novel-page fixtures ONLY (exclude browsetags/letter/tag-index pages
#    which list every tag on the site and would defeat the purpose)
import html as htmlmod
fx_tags = {}
novel_files = [f for f in glob.glob("/home/z/my-project/research/wuxiabox/*.html")
               if "novel" in os.path.basename(f).lower() and "mirror" not in os.path.basename(f).lower()]
novel_files += [f for f in glob.glob("/home/z/my-project/research/wuxiabox/v2*/*.html")
                if "novel" in os.path.basename(f).lower() and "mirror" not in os.path.basename(f).lower()]
print("novel fixtures:", [os.path.basename(f) for f in novel_files])
for f in novel_files:
    try:
        body = open(f, encoding="utf-8", errors="replace").read()
    except Exception:
        continue
    for mm in re.finditer(r'href="/tags/(\d+)-0\.html"[^>]*>([^<]+)</a>', body):
        fx_tags.setdefault(mm.group(1), htmlmod.unescape(htmlmod.unescape(mm.group(2).strip())))
print(f"fixture-observed tag ids: {len(fx_tags)}")

# merge: curated + popular + fixture tags (fixtures prove usage even if not in wtrlab)
final = dict(curated)
for tid, label in fx_tags.items():
    n = norm(label)
    if n not in final:
        entry = [t for t in WT if t["id"] == tid]
        if entry:
            final[n] = (canonical(entry), len(entry))
        else:
            final[n] = ({"id": tid, "label": label, "letter": (label[:1] or "?").upper()}, 1)
for tid in pop_ids:
    entry = [t for t in WT if t["id"] == tid]
    if entry:
        n = norm(entry[0]["label"])
        if n not in final:
            final[n] = (canonical(entry), len(entry))

# 4) The Honghuang family — wtrlab's plain "Honghuang" does not substring-match
#    wuxiabox's truncated family labels (HongHuangB/z, HonghuangS/N/s), so the
#    intersection misses them. They are a major browsing category on this site.
hh_added = 0
for t in WT:
    lab = EXPANDED.get(t["id"], t["label"])
    if "honghuang" in lab.lower():
        n = norm(lab)
        if n not in final:
            final[n] = (t, 1)
            hh_added += 1
print(f"honghuang family added: {hh_added}")

print(f"FINAL curated tags: {len(final)}")
dupes = sum(1 for _, (_, c) in final.items() if c > 1)
print(f"  names with duplicate ids on wuxiabox: {dupes}")

out = sorted(
    [{"id": t["id"], "label": t["label"], "letter": t["letter"], "dupes": c} for t, c in final.values()],
    key=lambda x: x["label"].lower())
json.dump(out, open("/home/z/my-project/research/wuxiabox/curated_tags.json", "w"), indent=1)
print("sample:", [f'{t["label"]}(#{t["id"]})' for t in out[:10]])
print("saved research/wuxiabox/curated_tags.json")

# size estimate for the plugin index
idx = "\n".join(f'{t["id"]}|{t["label"]}|{t["letter"]}' for t in out)
print(f"index size estimate: {len(idx)} bytes vs current {6723*22} approx")
