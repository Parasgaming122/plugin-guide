#!/usr/bin/env python3
"""Probe live WTR-Lab reader/get body structure for paragraph-regression diagnosis."""
import json, urllib.request, sys, time

BASE = "https://wtr-lab.com"
UA = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"

def post_reader(novel_id, ch_no, translate):
    body = json.dumps({"translate": translate, "language": "none", "raw_id": str(novel_id),
                       "chapter_no": ch_no, "retry": False, "force_retry": False}).encode()
    req = urllib.request.Request(BASE + "/api/reader/get", data=body, method="POST", headers={
        "Content-Type": "application/json",
        "User-Agent": UA,
        "Referer": f"{BASE}/novel/{novel_id}/chapter-{ch_no}",
        "Origin": BASE,
        "Accept": "*/*",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    except Exception as e:
        return 0, str(e)

def analyze(tag, raw_id, ch, translate):
    code, body = post_reader(raw_id, ch, translate)
    print(f"\n=== {tag}: novel {raw_id} ch {ch} translate={translate} -> HTTP {code} ===")
    try:
        d = json.loads(body)
    except Exception as e:
        print("  JSON parse failed:", e, "| body head:", body[:200])
        return None
    if d.get("success") is False:
        print("  success=false:", {k: v for k, v in d.items() if k != "data"})
        return d
    data = d.get("data", {}).get("data") or d.get("data") or {}
    b = data.get("body")
    if b is None:
        print("  no body; keys:", list(d.keys()), list(data.keys())[:20])
        return d
    if isinstance(b, list):
        lens = [len(x) if isinstance(x, str) else -1 for x in b]
        nl = [x.count("\n") if isinstance(x, str) else -1 for x in b]
        big = sum(1 for L in lens if L > 2000)
        print(f"  body: ARRAY of {len(b)} elements; elements >2000 chars: {big}")
        print(f"  first 12 lens: {lens[:12]}")
        print(f"  elements containing newlines: {sum(1 for n in nl if n > 0)}")
        if b:
            s0 = b[0] if isinstance(b[0], str) else str(b[0])
            print(f"  elem[0][:150]: {s0[:150]!r}")
            if len(b) > 1 and isinstance(b[1], str):
                print(f"  elem[1][:150]: {b[1][:150]!r}")
            longest = max(lens)
            print(f"  longest element: {longest} chars (index {lens.index(longest)})")
    else:
        print(f"  body: STRING len={len(b)}; newlines={b.count(chr(10))}; double-nl={b.count(chr(10)*2)}")
        print(f"  body[:300]: {b[:300]!r}")
        print(f"  body[-200:]: {b[-200:]!r}")
    # save sample
    fn = f"/home/z/my-project/research/probe_{tag}.json"
    with open(fn, "w") as f:
        f.write(body)
    print(f"  saved -> {fn} ({len(body)} bytes)")
    return d

if __name__ == "__main__":
    analyze("ai_93618_c1", 93618, 1, "ai")
    time.sleep(2)
    analyze("web_93618_c1", 93618, 1, "web")
    time.sleep(2)
    analyze("ai_93618_c5", 93618, 5, "ai")
    time.sleep(2)
    analyze("web_2_c1", 2, 1, "web")
