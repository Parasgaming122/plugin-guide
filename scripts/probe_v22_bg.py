#!/usr/bin/env python3
"""Patient background probe v2: wuxiabox search pagination fixtures via jina.
Strategy: get a FRESH searchid via the multi-result search, then fetch page=1.
Runs up to 60 min; logs to v22/probe_bg.log; survives via setsid."""
import os, subprocess, time, re

OUT = "/home/z/my-project/research/wuxiabox/v22"
os.makedirs(OUT, exist_ok=True)
LOG = os.path.join(OUT, "probe_bg.log")

def log(msg):
    with open(LOG, "a") as f:
        f.write(f"[{time.strftime('%H:%M:%S')}] {msg}\n")

def fetch(url, outfile, quiet=False):
    try:
        r = subprocess.run(
            ["curl", "-s", "--max-time", "90",
             "-H", "X-Return-Format: html",
             "-o", outfile, "-w", "%{http_code}",
             "https://r.jina.ai/" + url],
            capture_output=True, text=True, timeout=100)
        code = r.stdout.strip()
        size = os.path.getsize(outfile) if os.path.exists(outfile) else 0
        if not quiet:
            log(f"  fetch {os.path.basename(outfile)}: code={code} size={size}")
        return code, size
    except Exception as e:
        return f"ERR:{e}", 0

def good(path, min_size=600):
    return os.path.exists(path) and os.path.getsize(path) > min_size

SEARCH_URL = "https://www.wuxiabox.com/e/search/?searchget=1&keyboard=cultivation&show=title&tbname=news&tempid=1"
fresh = os.path.join(OUT, "search_multi_cultivation.html")

deadline = time.time() + 60 * 60
round_no = 0
while time.time() < deadline:
    round_no += 1
    # 1) fresh search page (has fresh searchid in pager)
    need_fresh = not good(fresh, 8000)
    if need_fresh:
        log(f"round {round_no}: fetching fresh search page")
        code, size = fetch(SEARCH_URL, fresh, quiet=True)
        log(f"  fresh search: code={code} size={size}")
        if not good(fresh, 8000):
            time.sleep(120)
            continue

    body = open(fresh, encoding="utf-8", errors="replace").read()
    sid = re.search(r"searchid=(\d+)", body)
    if not sid:
        log("  no searchid in fresh page; waiting")
        time.sleep(120)
        continue
    sid = sid.group(1)
    log(f"round {round_no}: searchid={sid}")

    targets = [
        ("result_page1", f"https://www.wuxiabox.com/e/search/result/index.php?page=1&searchid={sid}"),
        ("result_page2", f"https://www.wuxiabox.com/e/search/result/index.php?page=2&searchid={sid}"),
        ("result_noindex", f"https://www.wuxiabox.com/e/search/result?searchid={sid}"),
        ("result_noindex_p1", f"https://www.wuxiabox.com/e/search/result?searchid={sid}&page=1"),
    ]
    all_done = True
    for name, url in targets:
        out = os.path.join(OUT, name + ".html")
        if good(out):
            continue
        all_done = False
        code, size = fetch(url, out, quiet=True)
        log(f"  {name}: code={code} size={size}")
        if not good(out) and os.path.exists(out):
            os.remove(out)
        time.sleep(25)
    if all_done:
        log("ALL DONE")
        break
    time.sleep(90)
log("probe loop ended")
