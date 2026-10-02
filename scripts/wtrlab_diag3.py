#!/usr/bin/env python3
"""Probe 3: book data route, full filter params on HTML route, api/search item count, ai-mode reader latency."""
import time, json, ssl, gzip, re, urllib.request, urllib.error

BASE = "https://wtr-lab.com/"
UA = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
BUILD = "mSxbXJZMcXIJw3sDZdeQb"
ctx = ssl.create_default_context()

def get(url, headers=None, timeout=30):
    h = {"User-Agent": UA, "Accept-Encoding": "gzip"}
    if headers: h.update(headers)
    r = urllib.request.Request(url, headers=h)
    t0 = time.time()
    try:
        with urllib.request.urlopen(r, timeout=timeout, context=ctx) as resp:
            raw = resp.read()
            if resp.headers.get("Content-Encoding") == "gzip":
                try: raw = gzip.decompress(raw)
                except Exception: pass
            return resp.status, raw, time.time() - t0
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, raw, time.time() - t0
    except Exception as e:
        return -1, str(e).encode(), time.time() - t0

def post(url, body, headers=None, timeout=30):
    h = {"User-Agent": UA, "Content-Type": "application/json", "Accept-Encoding": "gzip", "Origin": BASE}
    if headers: h.update(headers)
    r = urllib.request.Request(url, data=body.encode(), method="POST", headers=h)
    t0 = time.time()
    try:
        with urllib.request.urlopen(r, timeout=timeout, context=ctx) as resp:
            raw = resp.read()
            if resp.headers.get("Content-Encoding") == "gzip":
                try: raw = gzip.decompress(raw)
                except Exception: pass
            return resp.status, raw, time.time() - t0
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, raw, time.time() - t0
    except Exception as e:
        return -1, str(e).encode(), time.time() - t0

def nextdata(html):
    m = re.search(rb'<script id="__NEXT_DATA__" type="application/json"[^>]*>(.*?)</script>', html, re.S)
    if not m: return None
    try: return json.loads(m.group(1).decode("utf-8", "replace"))
    except Exception as e: return {"__err": str(e)}

print("=== A. Book detail data route ===")
for url in [BASE + f"_next/data/{BUILD}/en/novel/93618.json",
            BASE + f"_next/data/{BUILD}/en/novel/93618/slug.json"]:
    code, body, dt = get(url)
    print(f"  [{dt*1000:6.0f} ms] {code} {len(body):>7} B  {url.split('_next')[1][:60]}")
    if code == 200:
        try:
            j = json.loads(body)
            pp = (j.get("props") or {}).get("pageProps") or {}
            print(f"      pageProps keys: {list(pp.keys())[:12]}")
        except Exception as e:
            print(f"      json err {e}")

print("=== B. Book HTML timing ===")
for i in range(2):
    code, body, dt = get(BASE + "en/novel/93618")
    print(f"  [{dt*1000:6.0f} ms] {code} {len(body):>7} B  book HTML")

print("=== C. HTML finder with ALL plugin param shapes ===")
cases = [
    ("gi/ge/gc genres", "gi=9,16&ge=12&gc=and"),
    ("count_type/value", "count_type=chapter&count_filter=min&count_value=200"),
    ("minr/minrc", "minr=4&minrc=10"),
    ("addition_age", "addition_age=week"),
    ("orderBy weighted", "orderBy=weighted&minrc=5"),
    ("combined text+ti+status", "text=system&ti=696&tc=and&status=completed"),
    ("te exclude", "te=696&page=1"),
]
for label, q in cases:
    code, body, dt = get(BASE + "en/novel-finder?" + q + "&page=1")
    d = nextdata(body) or {}
    pp = d.get("props", {}).get("pageProps", {})
    n = len(pp.get("series") or [])
    print(f"  [{dt*1000:6.0f} ms] {code} {len(body):>7} B  {label}: series={n} count={pp.get('count')}")

print("=== D. api/search result count ===")
code, body, dt = post(BASE + "api/search", json.dumps({"text": "sys"}))
try:
    j = json.loads(body)
    items = j.get("data") or []
    print(f"  api/search 'sys': {len(items)} items, keys={list(items[0].keys()) if items else None}")
except Exception as e:
    print(f"  parse err: {e}")

print("=== E. ai-mode reader latency ===")
for i in range(2):
    code, body, dt = post(BASE + "api/reader/get",
        json.dumps({"translate": "ai", "language": "none", "raw_id": "93618", "chapter_no": 1, "retry": False, "force_retry": False}),
        headers={"Referer": BASE + "en/novel/93618/x"})
    snippet = body[:150].decode("utf-8", "replace")
    print(f"  [{dt*1000:6.0f} ms] {code} {len(body):>7} B  ai: {snippet[:100]}")

print("=== F. terms API ===")
code, body, dt = get(BASE + "api/v2/reader/terms/93618.json")
print(f"  [{dt*1000:6.0f} ms] {code} {len(body):>7} B  terms: {body[:120].decode('utf-8','replace')[:100]}")
