#!/usr/bin/env python3
"""Test wsrv.nl / images.weserv.nl proxy fetching covers from all 3 sites."""
import subprocess

def probe(url, max_time=30):
    cmd = ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}|%{content_type}|%{size_download}",
           "--max-time", str(max_time), "-A",
           "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.6834.83 Mobile Safari/537.36"]
    cmd.append(url)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=max_time + 10)
    return r.stdout.strip()

tests = [
    # wuxiabox cover (CF-challenged direct)
    ("wuxiabox direct", "https://wuxiabox.com/d/file/cover_qb/bdvy31yopuy.jpg"),
    ("wuxiabox via wsrv.nl", "https://wsrv.nl/?url=wuxiabox.com/d/file/cover_qb/bdvy31yopuy.jpg"),
    ("wuxiabox via images.weserv.nl", "https://images.weserv.nl/?url=wuxiabox.com/d/file/cover_qb/bdvy31yopuy.jpg"),
    # wtr-lab cover (redirecting direct)
    ("wtr-lab via wsrv.nl", "https://wsrv.nl/?url=img.wtr-lab.com/cdn/series/mOjUBOW73TUvR1Q_2KymcaD9l9Qn4gl4_13D6OgoR44.jpg?w=300&h=400"),
    # novel543 cover (works direct)
    ("novel543 via wsrv.nl", "https://wsrv.nl/?url=i2.novel543.com/thumb/120x160/20260918/040460501940.jpg"),
    # mirror wuxiaspot cover (same path shape)
    ("wuxiaspot direct", "https://wuxiaspot.com/d/file/cover_qb/bdvy31yopuy.jpg"),
    ("wuxiaspot via wsrv.nl", "https://wsrv.nl/?url=wuxiaspot.com/d/file/cover_qb/bdvy31yopuy.jpg"),
]
for name, url in tests:
    print(f"{name:35s} -> {probe(url)}")
