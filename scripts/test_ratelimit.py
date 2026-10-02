#!/usr/bin/env python3
"""Test WTR-Lab API rate limiting and encryption behavior."""
import json
import time
import urllib.request

BASE = "https://wtr-lab.com"
URL = BASE + "/api/reader/get"
HDRS = {
    "Content-Type": "application/json",
    "Origin": "https://wtr-lab.com",
    "Referer": "https://wtr-lab.com/en/novel/93618/primordial-era-transcending-to-the-heavens-im-not-signing-the-investiture-of-the-gods/chapter-1",
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36",
}

def fetch_chapter(chapter_no, novel_id="93618", translate="ai"):
    payload = json.dumps({
        "translate": translate, "language": "none", "raw_id": novel_id,
        "chapter_no": chapter_no, "retry": False, "force_retry": False,
    }).encode()
    req = urllib.request.Request(URL, data=payload, headers=HDRS, method="POST")
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.status, r.read().decode("utf-8", errors="replace")

for i, ch in enumerate(range(1, 9)):
    try:
        status, body = fetch_chapter(ch)
        d = json.loads(body)
        if not d.get("success"):
            print(f"ch{ch}: API error: {json.dumps(d)[:200]}")
            continue
        b = d["data"]["data"]["body"]
        if isinstance(b, list):
            print(f"ch{ch}: PLAIN array, {len(b)} paragraphs")
        elif isinstance(b, str):
            print(f"ch{ch}: STRING body, prefix={b[:60]!r}")
        else:
            print(f"ch{ch}: type={type(b)}")
    except Exception as e:
        print(f"ch{ch}: EXCEPTION {e}")
    time.sleep(1)
