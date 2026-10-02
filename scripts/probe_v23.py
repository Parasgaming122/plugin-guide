#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
v2.3.0 sanity probe: verify both sites are still EmpireCMS structural twins
(paced, resumable, via r.jina.ai — datacenter IPs get CF-challenged direct).
"""
import json, time, urllib.request, urllib.error, os, sys

OUT = "/home/z/my-project/research/wuxiabox/v23"
os.makedirs(OUT, exist_ok=True)

TARGETS = [
    # (name, direct url, markers that must appear via jina text extraction)
    ("spot_home",   "https://www.wuxiaspot.com/",
     ["novel", "list"]),
    ("spot_novel",  "https://www.wuxiaspot.com/novel/kks31307.html",
     ["Hongmeng Heavenly Book", "novel-title"]),
    ("box_novel",   "https://www.wuxiabox.com/novel/kks31307.html",
     ["Hongmeng Heavenly Book", "novel-title"]),
]

def fetch(url):
    req = urllib.request.Request(
        "https://r.jina.ai/" + url,
        headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8", "replace")

for name, url, markers in TARGETS:
    path = os.path.join(OUT, name + ".txt")
    if os.path.exists(path) and os.path.getsize(path) > 500:
        print(f"[skip] {name} already captured")
        body = open(path, encoding="utf-8").read()
    else:
        try:
            body = fetch(url)
            open(path, "w", encoding="utf-8").write(body)
            print(f"[ok]   {name}: {len(body)} bytes")
        except Exception as e:
            print(f"[FAIL] {name}: {e}")
            continue
        time.sleep(8)  # pacing
    hits = {m: (m.lower() in body.lower()) for m in markers}
    print(f"       markers: {hits}")
print("done")
