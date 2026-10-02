#!/usr/bin/env python3
"""capture_bixiange_2026.py — capture LIVE bixiange fixtures (2026-09-30 URL
scheme: books /{cat}/{id} no trailing slash, chapters /{cat}/{id}/index/{n}.html)
for BixiangeTest's new-shape proof section."""
import subprocess, os

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36"
OUT = "/home/z/my-project/research/newsites"

def get(u):
    return subprocess.run(["curl", "-s", "-m", "30", "-A", UA, "--compressed", "-L",
                           "-H", "Accept-Language: zh-CN,zh;q=0.9", u],
                          capture_output=True).stdout

targets = [
    ("bx26_book_23552.html",  "https://www.bixiange.top/xhqh/23552"),
    ("bx26_ch_23552_1.html",  "https://www.bixiange.top/xhqh/23552/index/1.html"),
    ("bx26_ch_23552_2.html",  "https://www.bixiange.top/xhqh/23552/index/2.html"),
    ("bx26_sort.html",        "https://www.bixiange.top/sort/"),
    ("bx26_cat_trxs.html",    "https://www.bixiange.top/trxs/"),
]

for fn, url in targets:
    raw = get(url)
    # sanity: GBK page with expected markers
    txt = raw.decode("gbk", errors="replace")
    ok = len(raw) > 3000 and ("bixiange" in txt.lower() or "笔仙阁" in txt)
    path = os.path.join(OUT, fn)
    open(path, "wb").write(raw)
    print(f"{fn}: {len(raw)} bytes {'OK' if ok else 'SUSPECT'}")
    if "book_" in fn:
        print("   catalog anchors:", txt.count("index/1.html"), "| descInfo:", "descInfo" in txt)
    if "_ch_" in fn:
        print("   mycontent:", "mycontent" in txt)
