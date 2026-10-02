#!/usr/bin/env python3
"""Probe wtr-lab rate limit on api/reader/get + chapters API timestamps."""
import json, time, urllib.request, ssl

UA = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
ctx = ssl.create_default_context()
BASE = "https://wtr-lab.com"

def post(url, data, headers=None, timeout=25):
    h = {"User-Agent": UA, "Content-Type": "application/json", "Origin": BASE,
         "Referer": BASE + "/en/novel/37118/", "Accept": "*/*"}
    if headers: h.update(headers)
    req = urllib.request.Request(url, data=data.encode(), headers=h)
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            return r.status, json.loads(r.read().decode()), time.time() - t0
    except urllib.error.HTTPError as e:
        try: body = json.loads(e.read().decode())
        except Exception: body = {}
        return e.code, body, time.time() - t0
    except Exception as e:
        return -1, {"err": str(e)}, time.time() - t0

def get(url, headers=None, timeout=25):
    h = {"User-Agent": UA, "Accept": "*/*"}
    if headers: h.update(headers)
    req = urllib.request.Request(url, headers=h)
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            return r.status, r.read().decode("utf-8", "replace"), time.time() - t0
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")[:500], time.time() - t0
    except Exception as e:
        return -1, str(e), time.time() - t0

print("=== chapters API shape (timestamps for update detection?) ===")
c, b, dt = get(BASE + "/api/chapters/37118")
if c == 200:
    j = json.loads(b)
    chs = j.get("chapters", [])
    print("keys:", list(j.keys()), "n:", len(chs))
    print("chapter keys:", list(chs[0].keys()) if chs else "-")
    print("first chapter:", json.dumps(chs[0])[:300])
    print("last chapter:", json.dumps(chs[-1])[:300])
print()

print("=== rapid-fire reader/get (rate limit threshold) ===")
results = []
for i in range(18):
    body = {"translate": "web", "language": "none", "raw_id": "93618", "chapter_no": (i % 40) + 1, "retry": False, "force_retry": False}
    c, j, dt = post(BASE + "/api/reader/get", json.dumps(body))
    rt = j.get("requireTurnstile")
    cnt = j.get("count")
    ok = j.get("success")
    results.append((c, ok, rt, cnt, round(dt, 2)))
    print(f"  call {i+1:2d}: code={c} success={ok} turnstile={rt} count={cnt} t={dt:.2f}s")
    if rt:
        print("  ^ RATE LIMITED — stopping probe")
        break
    time.sleep(0.15)

print("\n=== chapter page GET (does it reset?) ===")
c, b, dt = get(BASE + "/en/novel/37118")
print(f"page fetch: code={c} t={dt:.2f}s len={len(b)}")
body = {"translate": "web", "language": "none", "raw_id": "93618", "chapter_no": 2, "retry": False, "force_retry": False}
c, j, dt = post(BASE + "/api/reader/get", json.dumps(body))
print(f"after page GET: code={c} success={j.get('success')} turnstile={j.get('requireTurnstile')} count={j.get('count')}")
