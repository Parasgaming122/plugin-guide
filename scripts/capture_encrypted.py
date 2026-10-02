#!/usr/bin/env python3
"""Try to capture an encrypted (arr:/str:) response from WTR-Lab API."""
import json
import time
import urllib.request

URL = "https://wtr-lab.com/api/reader/get"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36"


def fetch(novel_id, ch, translate="ai", extra=None, minimal_headers=False):
    payload = {"translate": translate, "language": "none", "raw_id": str(novel_id),
               "chapter_no": ch, "retry": False, "force_retry": False}
    if extra:
        payload.update(extra)
    hdrs = {"Content-Type": "application/json"}
    if not minimal_headers:
        hdrs.update({"Origin": "https://wtr-lab.com",
                     "Referer": f"https://wtr-lab.com/en/novel/{novel_id}/x/chapter-{ch}",
                     "User-Agent": UA})
    req = urllib.request.Request(URL, data=json.dumps(payload).encode(), headers=hdrs, method="POST")
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.status, r.read().decode("utf-8", errors="replace")


def analyze(tag, novel_id, ch, translate, **kw):
    try:
        status, body = fetch(novel_id, ch, translate, **kw)
        d = json.loads(body)
        if not d.get("success"):
            print(f"[{tag}] novel={novel_id} ch={ch} {translate}: API error {d.get('code')}: {str(d.get('error'))[:80]}")
            return None
        inner = d["data"]["data"]
        enc = inner.get("encrypted")
        b = inner.get("body")
        if isinstance(b, list):
            print(f"[{tag}] novel={novel_id} ch={ch} {translate}: PLAIN {len(b)}p encrypted={enc}")
            return None
        elif isinstance(b, str):
            print(f"[{tag}] novel={novel_id} ch={ch} {translate}: STRING encrypted={enc} prefix={b[:70]!r}")
            if b.startswith(("arr:", "str:")):
                fn = f"/home/z/my-project/wtrlab-analysis/enc_{tag}_{novel_id}_{ch}_{translate}.json"
                with open(fn, "w") as f:
                    f.write(body)
                print(f"   ^^^ SAVED: {fn}")
                return fn
        return None
    except Exception as e:
        print(f"[{tag}] novel={novel_id} ch={ch} {translate}: EXC {e}")
        return None


# Scenario 1: raw/web mode on various novels
for nid in ["93618", "93574", "1", "2"]:
    analyze("raw", nid, 1, "web")

# Scenario 2: AI mode minimal headers
analyze("minhdr", "93618", 2, "ai", minimal_headers=True)

# Scenario 3: retry flags
analyze("retry", "93618", 3, "ai", extra={"retry": True})
analyze("forceretry", "93618", 3, "ai", extra={"force_retry": True})

# Scenario 4: fresh novels at high chapter numbers (untranslated)
analyze("fresh", "93618", 60, "ai")

# Scenario 5: another language
try:
    payload = json.dumps({"translate": "ai", "language": "es", "raw_id": "93618",
                          "chapter_no": 4, "retry": False, "force_retry": False}).encode()
    req = urllib.request.Request(URL, data=payload, headers={
        "Content-Type": "application/json", "Origin": "https://wtr-lab.com",
        "Referer": "https://wtr-lab.com/es/novel/93618/x/chapter-4", "User-Agent": UA}, method="POST")
    with urllib.request.urlopen(req, timeout=120) as r:
        body = r.read().decode()
    d = json.loads(body)
    if d.get("success"):
        inner = d["data"]["data"]
        b = inner.get("body")
        print(f"[es] encrypted={inner.get('encrypted')} type={type(b).__name__}")
        if isinstance(b, str) and b.startswith(("arr:", "str:")):
            with open("/home/z/my-project/wtrlab-analysis/enc_es.json", "w") as f:
                f.write(body)
            print("   ^^^ SAVED enc_es.json")
    else:
        print(f"[es] error {d.get('code')}: {str(d.get('error'))[:100]}")
except Exception as e:
    print(f"[es] EXC {e}")
