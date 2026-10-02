#!/usr/bin/env python3
"""Paced fetcher for 69shuba.tw research via Google Translate proxy.
The proxy rate-limits (~2 req then /sorry/), so sleep between requests."""
import subprocess, sys, time, os

OUT = "/home/z/my-project/research/69shubatw"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

PAGES = [
    ("toc_342441.html",   "https://69shuba-tw.translate.goog/indexlist/342441/?_x_tr_sl=zh&_x_tr_tl=en&_x_tr_hl=zh-CN"),
    ("chapter_1.html",    "https://69shuba-tw.translate.goog/read/342441/890315?_x_tr_sl=zh&_x_tr_tl=en&_x_tr_hl=zh-CN"),
    ("home_full.html",    "https://69shuba-tw.translate.goog/?_x_tr_sl=zh&_x_tr_tl=en&_x_tr_hl=zh-CN"),
    ("fenlei_lishi.html", "https://69shuba-tw.translate.goog/fenlei/lishi/1/?_x_tr_sl=zh&_x_tr_tl=en&_x_tr_hl=zh-CN"),
]

def fetch(name, url):
    dest = os.path.join(OUT, name)
    r = subprocess.run([
        "curl", "-s", "-L", "--max-time", "50",
        "-A", UA, "-o", dest, "-w", "%{http_code}",
        url
    ], capture_output=True, text=True)
    code = r.stdout.strip()
    size = os.path.getsize(dest) if os.path.exists(dest) else 0
    # detect /sorry rate limit
    sorry = False
    if size < 100000:
        try:
            head = open(dest, encoding='utf-8', errors='ignore').read(400)
            if "/sorry/" in head or "unusual traffic" in head.lower():
                sorry = True
        except Exception:
            pass
    print(f"{name}: HTTP {code} size {size}{' RATE-LIMITED' if sorry else ''}", flush=True)
    return sorry

if __name__ == "__main__":
    only = sys.argv[1:] if len(sys.argv) > 1 else None
    for name, url in PAGES:
        if only and name not in only:
            continue
        sorry = fetch(name, url)
        if sorry:
            print("Hit rate limit; waiting 90s before next...", flush=True)
            time.sleep(90)
            sorry = fetch(name, url)
            if sorry:
                print("Still limited; aborting for this round.", flush=True)
                sys.exit(1)
        time.sleep(35)
