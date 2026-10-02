#!/usr/bin/env python3
"""live_site_sweep.py — visit all 6 plugin sites, verify up-status + the exact
markers each plugin's parsers depend on. Reports changes that would break plugins.

Direct curl first; falls back to the Google-Translate proxy (clean IPs) for
WAF'd hosts (69shuba.tw, oop.tw)."""
import subprocess, sys, json, re

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36"

def curl(url, timeout=25, extra=None):
    cmd = ["curl", "-s", "-L", "-m", str(timeout), "-A", UA,
           "-H", "Accept-Language: zh-TW,zh;q=0.9,en;q=0.8",
           "--compressed", "-w", "\n__HTTP_CODE__%{http_code}"]
    if extra: cmd += extra
    cmd.append(url)
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout+10).stdout
        if "__HTTP_CODE__" in out:
            body, code = out.rsplit("__HTTP_CODE__", 1)
            return int(code.strip()), body
        return -1, out
    except Exception as e:
        return -1, str(e)

def gt(host, path):
    d = host.replace(".", "-")
    return f"https://{d}.translate.goog{path}?_x_tr_sl=zh&_x_tr_tl=en&_x_tr_hl=zh-CN"

results = []
def probe(name, url, markers, anti_markers=()):
    code, body = curl(url)
    status = f"{code}"
    found = {m: (m in body) for m in markers}
    anti = {m: (m in body) for m in anti_markers}
    ok = code == 200 and all(found.values()) and not any(anti.values())
    size = len(body)
    results.append((name, url, status, size, ok, found, anti))
    return code, body

print("=" * 100)
print("LIVE SITE SWEEP — 2026-09-30")
print("=" * 100)

# ── 1. 69shuba.tw ─────────────────────────────────────────────────────────
print("\n[1] 69shuba.tw (EdgeOne WAF: direct 403 expected; GT proxy + capital-I /Indexlist/)")
probe("69shuba home (GT)", gt("69shuba.tw", "/"), ["69shuba", "book"], ["aegis", "captcha"])
probe("69shuba book 342441 (GT)", gt("69shuba.tw", "/book/342441/"),
      ["342441", "startread", "last9"])
probe("69shuba Indexlist p1 (GT, capital I)", gt("69shuba.tw", "/Indexlist/342441/"),
      ["indexselect", "read/342441"], ["aegis", "captcha_verify"])
probe("69shuba Indexlist p2 (GT)", gt("69shuba.tw", "/Indexlist/342441/2/"),
      ["indexselect"], ["aegis"])
probe("69shuba chapter (GT)", gt("69shuba.tw", "/read/342441/890315/"),
      ["nr_title", "chaptercontent"], ["aegis"])

# ── 2. wuxiabox.com (+ wuxiaspot mirror) ──────────────────────────────────
print("\n[2] wuxiabox.com + wuxiaspot.com mirror")
code_wb, body_wb = curl("https://wuxiabox.com/")
print(f"  wuxiabox.com home: {code_wb}, {len(body_wb)} bytes")
if code_wb != 200:
    code_wb, body_wb = curl("https://wuxiaspot.com/")
    print(f"  → wuxiaspot.com home: {code_wb}, {len(body_wb)} bytes")

# ── 3. wtr-lab.com ────────────────────────────────────────────────────────
print("\n[3] wtr-lab.com")
c, b = curl("https://wtr-lab.com/")
print(f"  home: {c}, {len(b)} bytes, has __NEXT_DATA__: {'__NEXT_DATA__' in b}")
c, b = curl("https://wtr-lab.com/api/search?query=dragon&page=1")
print(f"  api/search: {c}, {len(b)} bytes, starts '{b[:60].strip()[:50]}'")
c, b = curl("https://wtr-lab.com/api/chapters/slug-unique-value?page=1")
print(f"  api/chapters (dummy slug): {c}, {b[:100].strip()[:80]}")

# ── 4. novel543.com ───────────────────────────────────────────────────────
print("\n[4] novel543.com")
c, b = curl("https://novel543.com/")
print(f"  home: {c}, {len(b)} bytes")
c, b = curl("https://novel543.com/search.html?searchtype=novel&searchkey=%E4%BF%AE%E7%9C%9F")
print(f"  search 修真: {c}, {len(b)} bytes, has results: {'book' in b.lower()}")
c, b = curl("https://novel543.com/novel/93618.html")
print(f"  book 93618: {c}, {len(b)} bytes")

# ── 5. oop.tw ─────────────────────────────────────────────────────────────
print("\n[5] oop.tw (datacenter-blocked? GT proxy)")
c, b = curl("https://oop.tw/")
print(f"  direct home: {c}, {len(b)} bytes")
if c != 200:
    probe("oop home (GT)", gt("oop.tw", "/"), ["oop", "novel"], ["captcha", "challenge"])
    probe("oop book 15379 (GT)", gt("oop.tw", "/novel/15379"), ["15379", "chapter"], ["captcha"])

# ── 6. bixiange.top ───────────────────────────────────────────────────────
print("\n[6] bixiange.top")
c, b = curl("https://bixiange.top/")
print(f"  home: {c}, {len(b)} bytes")
if c == 200:
    for m in ["bixiange", "novel", "chapter"]:
        if m in b.lower(): print(f"    marker '{m}': present")
else:
    probe("bixiange home (GT)", gt("bixiange.top", "/"), ["bixiange"], ["captcha"])

print("\n" + "=" * 100)
print("MARKER PROBE RESULTS")
print("=" * 100)
for name, url, status, size, ok, found, anti in results:
    flag = "OK " if ok else "!!!"
    print(f"[{flag}] {name}: HTTP {status}, {size}B")
    for m, v in found.items():
        print(f"        {'+' if v else '-'} marker '{m}'")
    for m, v in anti.items():
        if v: print(f"        ! ANTI-marker '{m}' PRESENT")
