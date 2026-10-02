#!/usr/bin/env python3
"""Wuxiabox v2.2 probes part B: POST-redirect result page + real page=1&searchid=2279."""
import os, subprocess, sys, time

OUT = "/home/z/my-project/research/wuxiabox/v22"
os.makedirs(OUT, exist_ok=True)

PROBES = [
    ("result_noindex",  "https://www.wuxiabox.com/e/search/result?searchid=2279"),
    ("result_page1",    "https://www.wuxiabox.com/e/search/result/index.php?page=1&searchid=2279"),
    ("result_page50",   "https://www.wuxiabox.com/e/search/result/index.php?page=50&searchid=2279"),
    ("result_page51",   "https://www.wuxiabox.com/e/search/result/index.php?page=51&searchid=2279"),
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
            if code == "200" and size >= 600:
                return True, code, size
            if code == "401":
                wait = 45 + attempt * 30
                print(f"    401 blocked, backoff {wait}s (attempt {attempt+1})", flush=True)
                time.sleep(wait)
                continue
            print(f"    code={code} size={size}, retry in 12s", flush=True)
            time.sleep(12)
        except Exception as e:
            print(f"    error: {e}", flush=True)
            time.sleep(10)
    return False, "?", 0

only = sys.argv[1] if len(sys.argv) > 1 else None
for name, url in PROBES:
    if only and only not in name:
        continue
    out = os.path.join(OUT, name + ".html")
    if os.path.exists(out) and os.path.getsize(out) > 600:
        print(f"[skip] {name} already fetched", flush=True)
        continue
    ok, code, size = fetch(url, out)
    print(f"[{'OK' if ok else 'FAIL'}] {name}: code={code} size={size}", flush=True)
    time.sleep(6)
