#!/usr/bin/env python3
"""Test proxy reliability and rate limit recovery."""
import json
import time
import urllib.request

PROXY = "https://wtr-lab-proxy.fly.dev/chapter"
API = "https://wtr-lab.com/api/reader/get"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36"


def proxy_decrypt(payload):
    req = urllib.request.Request(PROXY, data=json.dumps({"payload": payload}).encode(),
                                 headers={"Content-Type": "application/json"}, method="POST")
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, time.time() - t0, r.read().decode()[:80]
    except Exception as e:
        return getattr(e, 'code', -1), time.time() - t0, str(e)[:80]


def api_fetch(novel_id, ch, translate="ai"):
    payload = json.dumps({"translate": translate, "language": "none", "raw_id": str(novel_id),
                          "chapter_no": ch, "retry": False, "force_retry": False}).encode()
    req = urllib.request.Request(API, data=payload, headers={
        "Content-Type": "application/json", "Origin": "https://wtr-lab.com",
        "Referer": f"https://wtr-lab.com/en/novel/{novel_id}/x/chapter-{ch}", "User-Agent": UA}, method="POST")
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())


print("=== Proxy reliability (10 rapid requests) ===")
enc = json.load(open('/home/z/my-project/wtrlab-analysis/enc_raw_2_1_web.json'))["data"]["data"]["body"]
for i in range(10):
    status, dt, info = proxy_decrypt(enc)
    print(f"  #{i+1}: HTTP {status} {dt:.2f}s {info[:60]}")

print("\n=== Rate limit recovery test ===")
# hammer until 1401
limited = False
for ch in range(30, 60):
    d = api_fetch("93618", ch)
    if not d.get("success"):
        print(f"  rate limited at ch{ch} after attempt: {d.get('error')}")
        limited = True
        break
if not limited:
    print("  no rate limit hit in 30 requests")

if limited:
    for wait in [10, 30, 60, 120]:
        time.sleep(wait)
        try:
            d = api_fetch("93618", 50)
            ok = d.get("success")
            print(f"  after {wait}s wait: success={ok}" + ("" if ok else f" err={d.get('error')}"))
            if ok:
                break
        except Exception as e:
            print(f"  after {wait}s wait: EXC {e}")
