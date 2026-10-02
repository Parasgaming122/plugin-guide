#!/usr/bin/env python3
"""Wuxiabox v2.1 remaining live probes."""
import os, subprocess, time

OUT = "/home/z/my-project/research/wuxiabox/v21"
os.makedirs(OUT, exist_ok=True)

PROBES = [
    ("search_zero",      "https://www.wuxiabox.com/e/search/?searchget=1&keyboard=zzxxqqwweerrttyy12345&show=title&tbname=news&tempid=1"),
    ("mirror_search",    "https://www.wuxiaspot.com/e/search/?searchget=1&keyboard=Hongmeng+Heavenly+Book&show=title&tbname=news&tempid=1"),
    ("mirror_list",      "https://www.wuxiaspot.com/list/all/all-newstime-0.html"),
    ("mirror_novel",     "https://www.wuxiaspot.com/novel/kks31307.html"),
    ("list_live_check",  "https://www.wuxiabox.com/list/all/all-newstime-0.html"),
]

def fetch(url, outfile, retries=6):
    for attempt in range(retries):
        try:
            r = subprocess.run(
                ["curl", "-s", "--max-time", "90",
                 "-H", "X-Return-Format: html",
                 "-o", outfile, "-w", "%{http_code}",
                 "https://r.jina.ai/" + url],
                capture_output=True, text=True, timeout=100)
            code = r.stdout.strip()
            size = os.path.getsize(outfile) if os.path.exists(outfile) else 0
            if code == "200" and size >= 800:
                return True, code, size
            if code == "401":
                wait = 40 + attempt * 35
                print(f"    401 blocked, backoff {wait}s (attempt {attempt+1})", flush=True)
                time.sleep(wait)
                continue
            print(f"    code={code} size={size}, retry in 10s", flush=True)
            time.sleep(10)
        except Exception as e:
            print(f"    error: {e}", flush=True)
            time.sleep(10)
    return False, "?", os.path.getsize(outfile) if os.path.exists(outfile) else 0

for name, url in PROBES:
    out = os.path.join(OUT, name + ".html")
    if os.path.exists(out) and os.path.getsize(out) > 800:
        print(f"[skip] {name} already fetched", flush=True)
        continue
    ok, code, size = fetch(url, out)
    print(f"[{'OK' if ok else 'FAIL'}] {name}: code={code} size={size}", flush=True)
    if not ok and os.path.exists(out):
        os.remove(out)
    time.sleep(10)

print("DONE")
