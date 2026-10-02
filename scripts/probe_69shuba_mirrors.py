#!/usr/bin/env python3
"""Probe 69shuba family mirror domains for the new-style CMS (UTF-8, /book/{id}/, /indexlist/{id}/)."""
import subprocess, re

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
OUT = "/home/z/my-project/research/69shubatw"

DOMAINS = [
    "https://69shuba.cx/",
    "https://www.69shuba.cx/",
    "https://69shuba.pro/",
    "https://www.69shuba.pro/",
    "https://69shuba.moe/",
    "https://69shuba.cc/",
    "https://69shuba.app/",
    "https://69shuba.xyz/",
    "https://69shuba.tv/",
    "https://69shuba.net/",
    "https://www.69shuba.tw/",
    "https://69shuba.tw/",
    "https://69shuba.id/",
    "https://69shuba.link/",
    "https://www.69shuba.link/",
    "https://69shuba.win/",
    "https://69shuba.vip/",
]

def get(url, timeout=18):
    r = subprocess.run(["curl", "-s", "-L", "--max-time", str(timeout), "-A", UA,
                        "-o", "/dev/null", "-w", "%{http_code}|%{size_download}|%{url_effective}", url],
                       capture_output=True, text=True)
    return r.stdout.strip()

def body(url, timeout=18):
    r = subprocess.run(["curl", "-s", "-L", "--max-time", str(timeout), "-A", UA, url],
                       capture_output=True)
    return r.stdout

for d in DOMAINS:
    try:
        meta = get(d)
    except Exception as e:
        print(f"{d:35s} EXC {e}")
        continue
    code, size, final = (meta.split("|") + ["", ""])[:3]
    verdict = ""
    if code == "200" and int(size or 0) > 3000:
        b = body(d)
        # new-CMS markers: UTF-8 + /indexlist/ links + Edge/1.1 vs old GBK CMS
        head = b[:6000].decode("utf-8", errors="ignore")
        if "indexlist" in b.decode("utf-8", errors="ignore")[:60000] or "charset=UTF-8" in head or "charset=\"UTF-8\"" in head:
            full = b.decode("utf-8", errors="ignore")
            if "/book/" in full and ("69shuba" in full):
                verdict = "NEW-CMS? (utf8, /book/ links)"
        if "gbk" in head.lower():
            verdict = "OLD-GBK-CMS"
        if "human verification" in head or "aegis" in head:
            verdict = "WALL"
    print(f"{d:35s} http={code} size={size:>7} final={final[:60]:60s} {verdict}")
