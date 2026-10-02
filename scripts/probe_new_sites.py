#!/usr/bin/env python3
"""Probe bixiange.top and oop.tw for NoveLA plugin research.
Paced fetcher via r.jina.ai (datacenter IPs often CF-blocked directly),
with direct-HTTP fallback. Saves evidence under research/newsites/.
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

OUT = "/home/z/my-project/research/newsites"
os.makedirs(OUT, exist_ok=True)

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36")


def fetch(url, mode="jina", timeout=60):
    """Fetch a URL. mode: jina (via r.jina.ai) | direct."""
    key = re.sub(r"[^A-Za-z0-9]+", "_", url.replace("https://", "").replace("http://", ""))[:150]
    cache = os.path.join(OUT, f"cache_{mode}_{key}.txt")
    if os.path.exists(cache) and os.path.getsize(cache) > 200:
        with open(cache, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    try:
        if mode == "jina":
            target = "https://r.jina.ai/" + url
            req = urllib.request.Request(target, headers={
                "User-Agent": UA,
                "X-Return-Format": "text",
                "X-Timeout": str(timeout),
            })
        else:
            req = urllib.request.Request(url, headers={
                "User-Agent": UA,
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "Accept-Language": "zh-TW,zh;q=0.9,en;q=0.8",
            })
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            # jina returns utf-8 text; direct may be gbk/big5
            if mode == "direct":
                ctype = resp.headers.get("Content-Type", "")
                enc = None
                m = re.search(r"charset=([\w-]+)", ctype, re.I)
                if m:
                    enc = m.group(1)
                if not enc:
                    head = raw[:2000].decode("ascii", errors="ignore")
                    m = re.search(r'charset=["\']?([\w-]+)', head, re.I)
                    if m:
                        enc = m.group(1)
                try:
                    text = raw.decode(enc or "utf-8", errors="replace")
                except Exception:
                    text = raw.decode("utf-8", errors="replace")
                text = f"[HTTP {resp.status} {ctype}]\n" + text
            else:
                text = raw.decode("utf-8", errors="replace")
        with open(cache, "w", encoding="utf-8") as f:
            f.write(text)
        return text
    except Exception as e:
        err = f"[ERROR {type(e).__name__}: {e}]"
        with open(cache, "w", encoding="utf-8") as f:
            f.write(err)
        return err


def save(name, content):
    path = os.path.join(OUT, name)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content if isinstance(content, str) else json.dumps(content, ensure_ascii=False, indent=1))
    print(f"  saved {name} ({len(content)} chars)")


def summary(text, n=2500):
    if not text:
        return "(empty)"
    if text.startswith("[ERROR"):
        return text
    return text[:n]


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "bixiange"

    if which == "bixiange":
        urls = [
            ("home", "https://www.bixiange.top/"),
            ("novel_jsls_23825", "https://www.bixiange.top/jsls/23825/"),
        ]
        mode = sys.argv[2] if len(sys.argv) > 2 else "jina"
        for name, url in urls:
            print(f"== {name}: {url} ({mode})")
            t = fetch(url, mode)
            save(f"bixiange_{name}_{mode}.txt", t)
            print(summary(t, 1800))
            print("...\n")
            time.sleep(3)
    elif which == "bixiange2":
        # chapter-level probing done after reading novel page structure
        urls = [
            ("ch1", "https://www.bixiange.top/jsls/23825/10447914.html"),
        ]
        for name, url in urls:
            print(f"== {name}: {url}")
            t = fetch(url, "jina")
            save(f"bixiange_{name}.txt", t)
            print(summary(t, 1800))
            time.sleep(3)
    elif which == "oop":
        mode = sys.argv[2] if len(sys.argv) > 2 else "jina"
        urls = [
            ("home", "https://www.oop.tw/"),
        ]
        for name, url in urls:
            print(f"== {name}: {url} ({mode})")
            t = fetch(url, mode)
            save(f"oop_{name}_{mode}.txt", t)
            print(summary(t, 2500))
            print("...\n")
            time.sleep(3)
    else:
        print("unknown target")


if __name__ == "__main__":
    main()
