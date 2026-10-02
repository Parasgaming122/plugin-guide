#!/usr/bin/env python3
"""Diagnose WTR-Lab slowness: reproduce the plugin's exact request chain & time each step."""
import time, json, ssl, sys, urllib.request, urllib.error, gzip, io

BASE = "https://wtr-lab.com/"
UA_MOBILE = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
OLD_BUILD = "OoG9KKvLPC8OYCWg0hTyr"  # buildId from 2026-08-25 research

ctx = ssl.create_default_context()

def req(url, method="GET", body=None, headers=None, timeout=30):
    h = {"User-Agent": UA_MOBILE, "Accept": "*/*", "Accept-Encoding": "gzip"}
    if headers: h.update(headers)
    data = body.encode() if isinstance(body, str) else body
    r = urllib.request.Request(url, data=data, method=method, headers=h)
    t0 = time.time()
    try:
        with urllib.request.urlopen(r, timeout=timeout, context=ctx) as resp:
            raw = resp.read()
            dt = time.time() - t0
            if resp.headers.get("Content-Encoding") == "gzip":
                try: raw = gzip.decompress(raw)
                except Exception: pass
            return {"ok": True, "code": resp.status, "dt": dt, "len": len(raw),
                    "headers": dict(resp.headers), "body": raw[:400].decode("utf-8", "replace"),
                    "server": resp.headers.get("Server", ""), "cf_ray": resp.headers.get("cf-ray", "")}
    except urllib.error.HTTPError as e:
        raw = e.read()
        dt = time.time() - t0
        if e.headers.get("Content-Encoding") == "gzip":
            try: raw = gzip.decompress(raw)
            except Exception: pass
        return {"ok": False, "code": e.code, "dt": dt, "len": len(raw),
                "headers": dict(e.headers), "body": raw[:400].decode("utf-8", "replace"),
                "server": e.headers.get("Server", ""), "cf_ray": e.headers.get("cf-ray", "")}
    except Exception as e:
        return {"ok": False, "code": -1, "dt": time.time() - t0, "len": 0, "headers": {},
                "body": f"EXC {type(e).__name__}: {e}", "server": "", "cf_ray": ""}

def p(label, r, show_body=200):
    cf = " CF!" if "cloudflare" in (r.get("server") or "").lower() else ""
    print(f"  [{r['dt']*1000:7.0f} ms] HTTP {r['code']}{cf} {r['len']:>8} B  {label}")
    if r["code"] not in (200, 307, 308, 404) or r["code"] == -1:
        print(f"      body: {r['body'][:show_body]}")
    return r

print("=== 1. Plugin cold-start chain (stale persisted buildId scenario) ===")
print("--- 1a. _next/data novel-list.json with OLD (persisted) buildId ---")
r_old = p("GET /_next/data/{OLD}/en/novel-list.json?page=1&orderBy=reader",
          req(BASE + f"_next/data/{OLD_BUILD}/en/novel-list.json?page=1&orderBy=reader"))
if r_old["code"] == 404:
    print(f"      404 body: {r_old['body'][:300]}")
    loc = r_old["headers"].get("Location") or r_old["headers"].get("location")
    print(f"      Location header: {loc}")

print("--- 1b. _next/data with GARBAGE buildId (what a fresh install does) ---")
p("GET /_next/data/000000000000/en/novel-list.json?...",
  req(BASE + "_next/data/000000000000/en/novel-list.json?page=1&orderBy=reader"))

print("--- 1c. novel-finder HTML (the plugin's buildId refresh fetch, 240KB?) ---")
r_html = req(BASE + "en/novel-finder")
p("GET /en/novel-finder (HTML)", r_html)
import re
m = re.search(r'"buildId":"([^"]+)"', r_html["body"] if r_html["ok"] else "")
# need full body to find buildId — refetch keeping full body
if r_html["ok"]:
    full = req(BASE + "en/novel-finder")
    m = re.search(r'"buildId":"([^"]+)"', (full.get("full") or ""))
# simpler: fetch again and keep raw
def req_full(url):
    h = {"User-Agent": UA_MOBILE, "Accept-Encoding": "gzip"}
    r = urllib.request.Request(url, headers=h)
    with urllib.request.urlopen(r, timeout=30, context=ctx) as resp:
        raw = resp.read()
        if resp.headers.get("Content-Encoding") == "gzip":
            try: raw = gzip.decompress(raw)
            except Exception: pass
        return resp.status, raw
try:
    code, html = req_full(BASE + "en/novel-finder")
    m = re.search(r'"buildId":"([^"]+)"', html.decode("utf-8", "replace"))
    NEW_BUILD = m.group(1) if m else None
    print(f"      current buildId: {NEW_BUILD}  (html {len(html)} B, HTTP {code})")
except Exception as e:
    NEW_BUILD = None
    print(f"      FAILED to fetch finder HTML: {e}")

print("=== 2. Fresh-buildId data fetches (the normal path) ===")
if NEW_BUILD:
    for i in range(3):
        p(f"GET novel-list.json (fresh, try {i+1})",
          req(BASE + f"_next/data/{NEW_BUILD}/en/novel-list.json?page=1&orderBy=reader"))
    p("GET novel-finder.json?text=martial (search)",
      req(BASE + f"_next/data/{NEW_BUILD}/en/novel-finder.json?text=martial&page=1"))
    p("GET novel-finder.json ti=696 (System tag)",
      req(BASE + f"_next/data/{NEW_BUILD}/en/novel-finder.json?ti=696&tc=or&page=1"))
    p("GET novel-finder.json ti=696,890 tc=and (both System tags AND)",
      req(BASE + f"_next/data/{NEW_BUILD}/en/novel-finder.json?ti=696,890&tc=and&page=1"))
    p("GET novel-finder.json ti=696,890 tc=or (either)",
      req(BASE + f"_next/data/{NEW_BUILD}/en/novel-finder.json?ti=696,890&tc=or&page=1"))

print("=== 3. Light buildId sources (cheaper than 240KB finder HTML) ===")
for path in ["nonexistent-page-xyz", "en/novel/nonexistent", "robots.txt", "en"]:
    r = req(BASE + path)
    body_has_bid = False
    if r["ok"]:
        try:
            code, b = req_full(BASE + path)
            body_has_bid = bool(re.search(r'"buildId":"', b.decode("utf-8", "replace")))
            print(f"  /{path}: HTTP {code}, {len(b)} B, hasBuildId={body_has_bid}, {r['dt']*1000:.0f} ms")
        except Exception as e:
            print(f"  /{path}: full-fetch failed: {e}")
    else:
        print(f"  /{path}: HTTP {r['code']}, {r['len']} B, {r['dt']*1000:.0f} ms")

print("=== 4. Book detail as JSON data route? ===")
if NEW_BUILD:
    p("GET /_next/data/{B}/en/novel/93618/-sid.json (book detail route probe)",
      req(BASE + f"_next/data/{NEW_BUILD}/en/novel/93618/slug.json"))
print("--- 4b. book page HTML (what fetchPage does on every book open) ---")
p("GET /en/novel/93618 (book HTML)", req(BASE + "en/novel/93618"))

print("=== 5. Chapters + reader API ===")
p("GET /api/chapters/93618", req(BASE + "api/chapters/93618",
  headers={"Referer": BASE + "en/novel/93618/x"}))
r = req(BASE + "api/reader/get", method="POST",
        body=json.dumps({"translate": "web", "language": "none", "raw_id": "93618", "chapter_no": 1, "retry": False, "force_retry": False}),
        headers={"Content-Type": "application/json", "Referer": BASE + "en/novel/93618/x", "Origin": BASE})
p("POST /api/reader/get (web mode)", r)
body = r["body"]
print(f"      resp snippet: {body[:250]}")

print("=== 6. /api/search quick-search (tag autocomplete source?) ===")
p("POST /api/search {text:sys}", req(BASE + "api/search", method="POST", body=json.dumps({"text": "sys"}),
   headers={"Content-Type": "application/json", "Origin": BASE}))
r = req(BASE + "api/search", method="POST", body=json.dumps({"text": "system"}),
   headers={"Content-Type": "application/json", "Origin": BASE})
p("POST /api/search {text:system}", r)
print(f"      resp: {r['body'][:300]}")

print("=== 7. Tag list from finder JSON (count check) ===")
if NEW_BUILD:
    code, js = req_full(BASE + f"_next/data/{NEW_BUILD}/en/novel-finder.json?page=1")
    try:
        d = json.loads(js)
        tags = d.get("pageProps", {}).get("tags", {})
        un = tags.get("ungrouped", [])
        gr = tags.get("groups", [])
        print(f"      tags ungrouped={len(un)} groups={len(gr)}")
    except Exception as e:
        print(f"      parse error: {e}; body head: {js[:200]}")
