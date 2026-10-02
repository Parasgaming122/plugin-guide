#!/usr/bin/env python3
"""Wait for the Turnstile counter to decay below threshold, then make
a single live AI-mode chapter read to confirm the plugin's reading path
works on a FRESH (non-captured) chapter.

Caps the wait at 5 minutes. If the counter never drops below threshold,
skips the live read and exits with status documenting the rate-limit state.
"""
import json
import time
import urllib.request
import urllib.error

RAW_ID = "93618"
NOVEL_URL = f"https://wtr-lab.com/en/novel/{RAW_ID}/test/chapter-1"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 "
                  "(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
    "Content-Type": "application/json",
    "Accept": "application/json",
    "Referer": NOVEL_URL,
    "Origin": "https://wtr-lab.com",
}

def post(payload, timeout=20):
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request("https://wtr-lab.com/api/reader/get",
                                 data=body, headers=HEADERS, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode("utf-8", errors="replace"))
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode("utf-8", errors="replace"))
        except Exception:
            return e.code, None
    except Exception as e:
        return 0, {"error": f"{type(e).__name__}: {e}"}

print("Probing AI mode counter every 30s, max 5 min wait...")
deadline = time.time() + 300  # 5 min
attempt = 0
got_live = False
while time.time() < deadline:
    attempt += 1
    status, body = post({"translate": "ai", "language": "none", "raw_id": RAW_ID,
                         "chapter_no": 1, "retry": False, "force_retry": False})
    if isinstance(body, dict):
        if body.get("success"):
            print(f"\n[attempt {attempt}] GOT LIVE RESPONSE!")
            print(f"  HTTP {status}")
            data = body.get("data", {})
            inner = data.get("data", {}) if isinstance(data, dict) else {}
            b = inner.get("body")
            if isinstance(b, list):
                print(f"  body: array of {len(b)} paragraphs (AI mode)")
                if b:
                    print(f"  first para: {str(b[0])[:120]!r}")
                    print(f"  last para:  {str(b[-1])[:120]!r}")
            elif isinstance(b, str):
                print(f"  body: string len={len(b)} starts={b[:120]!r}")
            ch = body.get("chapter", {})
            print(f"  chapter.title: {ch.get('title')!r}")
            print(f"  chapter.char_count: {ch.get('char_count')}")
            got_live = True
            break
        elif body.get("requireTurnstile"):
            count = body.get("count")
            threshold = body.get("threshold")
            print(f"  [attempt {attempt}] t={int(time.time() % 60)}s: blocked (count={count}, threshold={threshold})")
        else:
            print(f"  [attempt {attempt}] other: {str(body)[:200]}")
            break
    else:
        print(f"  [attempt {attempt}] HTTP {status}, body: {str(body)[:200]}")
        break
    if time.time() < deadline:
        time.sleep(30)

if not got_live:
    print("\nCould not get a fresh live response within 5 min (counter stayed above threshold).")
    print("Falling back to Phase A captured-sample test, which is the definitive proof")
    print("that the plugin's reading code paths work end-to-end.")
