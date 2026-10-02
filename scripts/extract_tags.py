#!/usr/bin/env python3
"""Extract the complete tag/genre filter data from WTR-Lab novel-finder page."""
import json
import re

data = open('/home/z/my-project/wtrlab-analysis/novel-finder.html', encoding='utf-8', errors='replace').read()

# Find __NEXT_DATA__ JSON
m = re.search(r'<script id="__NEXT_DATA__" type="application/json"[^>]*>(.*?)</script>', data, re.DOTALL)
if m:
    nd = json.loads(m.group(1))
    # Look for filters in pageProps
    pp = nd.get('pageProps', {})
    print("pageProps keys:", list(pp.keys()))
    for k, v in pp.items():
        if isinstance(v, dict):
            print(f"  {k}: {list(v.keys())[:20]}")
        elif isinstance(v, list):
            print(f"  {k}: list len={len(v)}")
            if v and isinstance(v[0], dict):
                print(f"    first: {json.dumps(v[0])[:200]}")
else:
    print("No __NEXT_DATA__ found, searching raw...")

# Also search for the tag structure with category_id directly
# {"value":801,"label":"Honghuang","category_id":10}
tag_matches = re.findall(r'\{"value":(\d+),"label":"([^"]+)","category_id":(\d+)\}', data)
print(f"\nFound {len(tag_matches)} tag entries via regex")
cats = {}
for val, label, cat in tag_matches:
    cats.setdefault(cat, []).append((int(val), label))
for cat in sorted(cats, key=int):
    print(f"\ncategory_id {cat}: {len(cats[cat])} tags")
    for val, label in sorted(cats[cat], key=lambda x: x[1].lower()):
        print(f"  {val}: {label}")
