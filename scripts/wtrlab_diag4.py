#!/usr/bin/env python3
"""Probe 4: correct-slug book HTML + data route, redirect behavior."""
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
            return resp.status, raw, time.time() - t0, dict(resp.headers)
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, raw, time.time() - t0, dict(e.headers)
    except Exception as e:
        return -1, str(e).encode(), time.time() - t0, {}

def nextdata(html):
    m = re.search(rb'<script id="__NEXT_DATA__" type="application/json"[^>]*>(.*?)</script>', html, re.S)
    if not m: return None
    try: return json.loads(m.group(1).decode("utf-8", "replace"))
    except Exception as e: return {"__err": str(e)}

# 1. find real (raw_id, slug) pairs from catalog HTML
code, body, dt, _ = get(BASE + "en/novel-list?page=1&orderBy=reader")
d = nextdata(body) or {}
series = (d.get("props", {}).get("pageProps", {}) or {}).get("series") or []
pairs = [(s.get("raw_id"), s.get("slug")) for s in series[:3]]
print("catalog pairs:", pairs)
rid, slug = pairs[0]

# 2. book HTML with correct slug
url = BASE + f"en/novel/{rid}/{slug}"
code, body, dt, hd = get(url)
print(f"\nbook HTML correct slug: [{dt*1000:.0f} ms] {code} {len(body)} B  {url}")
if code == 200:
    d = nextdata(body) or {}
    pp = (d.get("props", {}).get("pageProps") or {})
    sd = ((pp.get("serie") or {}).get("serie_data") or {})
    print(f"  pageProps keys: {sorted(pp.keys())[:15]}")
    print(f"  serie_data.title: {sd.get('title')!r}  updated_at: {sd.get('updated_at')!r}")

# 3. same URL without slug → redirect?
code, body, dt, hd = get(BASE + f"en/novel/{rid}")
loc = hd.get("Location") or hd.get("location")
print(f"\nbook HTML id-only: [{dt*1000:.0f} ms] {code} len={len(body)} Location={loc}")

# 4. data route with correct slug
code, body, dt, _ = get(BASE + f"_next/data/{BUILD}/en/novel/{rid}/{slug}.json")
print(f"\nbook data route correct slug: [{dt*1000:.0f} ms] {code} {len(body)} B")
if code == 200:
    try:
        j = json.loads(body)
        pp = (j.get("props") or {}).get("pageProps") or {}
        sd = ((pp.get("serie") or {}).get("serie_data") or {})
        print(f"  pageProps keys: {sorted(pp.keys())[:15]}")
        print(f"  title: {sd.get('title')!r}, genres: {(pp.get('serie') or {}).get('genres')}")
    except Exception as e:
        print(f"  json err: {e}, head={body[:200]}")

# 5. WRONG slug (stale) → does it redirect?
code, body, dt, hd = get(BASE + f"en/novel/{rid}/wrong-slug-xyz")
loc = hd.get("Location") or hd.get("location")
print(f"\nbook HTML wrong slug: [{dt*1000:.0f} ms] {code} len={len(body)} Location={loc}")

# 6. novel 93618 — does it still exist? search it
import urllib.request as u
req = u.Request(BASE + "api/search", data=json.dumps({"text": "93618"}).encode(),
                headers={"User-Agent": UA, "Content-Type": "application/json", "Origin": BASE}, method="POST")
try:
    with u.urlopen(req, timeout=20, context=ctx) as resp:
        j = json.loads(resp.read())
        print(f"\napi/search '93618': {len(j.get('data') or [])} results")
except Exception as e:
    print(f"\napi/search 93618 err: {e}")
