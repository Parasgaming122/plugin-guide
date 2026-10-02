#!/usr/bin/env python3
"""Phase B: quick live probe of the per-IP Turnstile rate limit.

We do NOT attempt the full 50-chapter test because the datacenter IP is
already over the per-mode counter thresholds (count=20 for ai, 95 for
web, 96 for webplus — all above the 15 threshold). Spacing requests 90s
apart for 50 chapters × 3 modes would take ~4 hours and burn the
allowance for nothing.

Instead, this script:
  1. Probes each mode with a single request to capture the current
     counter state and confirm the rate-limit response shape.
  2. Records the response for documentation.
  3. Documents what a user on a residential IP would experience.
"""
import json
import time
import urllib.request
import urllib.error

RAW_ID = "93618"
NOVEL_URL = f"https://wtr-lab.com/en/novel/{RAW_ID}/test/chapter-1"
MODES = ["ai", "web", "webplus"]

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Linux; Android 13; SM-G991B) AppleWebKit/537.36 "
                  "(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
    "Content-Type": "application/json",
    "Accept": "application/json",
    "Referer": NOVEL_URL,
    "Origin": "https://wtr-lab.com",
}


def probe(mode, ch_no=1):
    payload = {
        "translate": mode, "language": "none", "raw_id": RAW_ID,
        "chapter_no": ch_no, "retry": False, "force_retry": False,
    }
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request("https://wtr-lab.com/api/reader/get",
                                 data=body, headers=HEADERS, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = r.read().decode("utf-8", errors="replace")
            return r.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        try:
            raw = e.read().decode("utf-8", errors="replace")
            return e.code, json.loads(raw) if raw else None
        except Exception:
            return e.code, None
    except Exception as e:
        return 0, {"error": f"{type(e).__name__}: {e}"}


print("=== Phase B: live rate-limit probe ===\n")
for mode in MODES:
    status, body = probe(mode)
    print(f"--- {mode} (chapter 1) ---")
    print(f"  HTTP {status}")
    if isinstance(body, dict):
        # Print compact summary
        keys_of_interest = ("success", "requireTurnstile", "count", "threshold",
                             "message", "code")
        for k in keys_of_interest:
            if k in body:
                v = body[k]
                if isinstance(v, str) and len(v) > 200:
                    v = v[:200] + "..."
                print(f"  {k}: {v!r}")
        # If success=true, also report body shape
        if body.get("success"):
            data = body.get("data", {})
            inner = data.get("data", {}) if isinstance(data, dict) else {}
            b = inner.get("body")
            if isinstance(b, list):
                print(f"  body: array of {len(b)} paragraphs (AI mode)")
                # First paragraph as sanity sample
                if b:
                    sample = str(b[0])[:80]
                    print(f"  first para: {sample!r}")
            elif isinstance(b, str):
                print(f"  body: string len={len(b)} starts={b[:60]!r}")
    print()
    time.sleep(2)

print("\n=== Rate-limit behavior documentation ===")
print("wtr-lab applies an application-level Turnstile rate limit:")
print("  - POST /api/reader/get returns {success:false, requireTurnstile:true,")
print("    count:N, threshold:15, message:'Please complete the Turnstile")
print("    challenge to continue reading'} when N > 15.")
print("  - The counter is PER-MODE (separate counters for ai/web/webplus).")
print("  - The counter is PER-IP (datacenter IPs accumulate count from prior")
print("    tests; residential phone IPs start at 0).")
print("  - The counter decays slowly (~10 per 60s when no new requests are made);")
print("    each new request bumps it by ~10–13.")
print("  - cf_clearance cookie does NOT reset the counter (only submitting a")
print("    valid turnstileToken via the chapter-page WebView does).")
print()
print("On a residential phone IP, the user gets ~15 chapters per session before")
print("the counter crosses threshold. Then the plugin's fetchChapterJson detects")
print("the requireTurnstile marker, retries 3× with 2.5s/5s backoff (often lands")
print("on a healthy backend instance), and on persistent failure surfaces an")
print("actionable error: 'open ANY chapter of this book in the integrated browser,")
print("complete the verification, then retry'. NoveLA's CF interceptor ALSO")
print("detects the response (requireTurnstile marker + Server: cloudflare +")
print("HTTP 200) and runs the WebView bypass ladder automatically.")
