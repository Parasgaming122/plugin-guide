#!/usr/bin/env python3
"""Dump live tag list from finder HTML __NEXT_DATA__; verify against plugin index; emit Lua per-category select blocks."""
import json, ssl, gzip, re, urllib.request, sys

BASE = "https://wtr-lab.com/"
UA = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
ctx = ssl.create_default_context()

def get(url):
    r = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Encoding": "gzip"})
    with urllib.request.urlopen(r, timeout=30, context=ctx) as resp:
        raw = resp.read()
        if resp.headers.get("Content-Encoding") == "gzip":
            raw = gzip.decompress(raw)
        return raw

html = get(BASE + "en/novel-finder?page=1").decode("utf-8", "replace")
m = re.search(r'<script id="__NEXT_DATA__" type="application/json"[^>]*>(.*?)</script>', html, re.S)
d = json.loads(m.group(1))
pp = d["props"]["pageProps"]
tags = pp["tags"]
un = tags["ungrouped"]
groups = tags["groups"]
print(f"buildId: {d.get('buildId')}")
print(f"ungrouped tags: {len(un)}; groups: {len(groups)}")
print("group sample:", json.dumps(groups[0])[:200])
print("tag sample:", json.dumps(un[0])[:200])

json.dump({"buildId": d.get("buildId"), "groups": groups, "ungrouped": un},
          open("/home/z/my-project/research/tags_live_v3.json", "w"), ensure_ascii=False, indent=1)

# per-category counts
from collections import Counter
cnt = Counter(t.get("category_id") for t in un)
print("per-category counts:", dict(sorted(cnt.items(), key=lambda kv: int(kv[0]))))

# group id → name mapping
gmap = {str(g["id"]): g for g in groups}
for gid, g in sorted(gmap.items(), key=lambda kv: int(kv[0])):
    print(f"  cat {gid}: {g.get('name') or g.get('title')} — {cnt.get(gid, 0)} tags")

# compare with plugin's TAG_SEARCH_INDEX
idx = {}
for line in open("/home/z/my-project/download/wtrlab.lua", encoding="utf-8").read().splitlines():
    mm = re.match(r'^(\d+)\|(.+)\|(\d+)$', line)
    if mm:
        idx[mm.group(1)] = (mm.group(2), mm.group(3))
live = {str(t["value"]): (t.get("label", ""), str(t["category_id"])) for t in un}
print(f"\nplugin index: {len(idx)} tags; live: {len(live)} tags")
missing_in_plugin = [k for k in live if k not in idx]
missing_in_live = [k for k in idx if k not in live]
print(f"  tags new on live site (missing in plugin): {missing_in_plugin}")
print(f"  tags in plugin but not live: {missing_in_live}")
label_diffs = [(k, idx[k][0], live[k][0]) for k in live if k in idx and idx[k][0] != live[k][0]]
cat_diffs = [(k, idx[k][1], live[k][1]) for k in live if k in idx and idx[k][1] != live[k][1]]
print(f"  label diffs: {label_diffs[:10]} ({len(label_diffs)} total)")
print(f"  category diffs: {cat_diffs[:10]} ({len(cat_diffs)} total)")
