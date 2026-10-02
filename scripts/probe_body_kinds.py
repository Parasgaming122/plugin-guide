#!/usr/bin/env python3
"""Broad probe: many novels, both modes, looking for body-format variants (str: bodies,
single-string bodies, no-newline bodies) that could cause paragraph mashups."""
import json, time, urllib.request, base64

BASE = "https://wtr-lab.com"
UA = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
KEY = b'IJAFUUxjM25hyzL2AZrn0wl7cESED6Ru'

def post_reader(nid, ch, tr):
    body = json.dumps({"translate": tr, "language": "none", "raw_id": str(nid), "chapter_no": ch,
                       "retry": False, "force_retry": False}).encode()
    req = urllib.request.Request(BASE + "/api/reader/get", data=body, method="POST", headers={
        "Content-Type": "application/json", "User-Agent": UA,
        "Referer": f"{BASE}/novel/{nid}/chapter-{ch}", "Origin": BASE})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except Exception as e:
        return 0, str(e)

def decrypt(payload):
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    parts = payload.split(":")
    iv = base64.b64decode(parts[1]); tag = base64.b64decode(parts[2]); ct = base64.b64decode(":".join(parts[3:]))
    d = Cipher(algorithms.AES(KEY), modes.GCM(iv, tag)).decryptor()
    return (d.update(ct) + d.finalize()).decode("utf-8", "replace")

# novels from the site's top lists + various
NOVELS = [93618, 2, 93574, 1, 5, 10, 100, 200, 555, 1000, 5000, 20000, 60000, 90000, 93000]

seen_kinds = {}
for nid in NOVELS:
    for mode in ("ai", "web"):
        code, body = post_reader(nid, 1, mode)
        time.sleep(1.2)
        if code != 200:
            print(f"novel {nid} {mode}: HTTP {code}")
            continue
        try:
            d = json.loads(body)
        except Exception:
            print(f"novel {nid} {mode}: non-JSON body ({body[:60]!r})")
            continue
        if d.get("success") is False:
            print(f"novel {nid} {mode}: success=false ({str(d.get('message'))[:60]})")
            continue
        b = (d.get("data", {}) or {}).get("data", d.get("data", {})).get("body")
        if b is None:
            print(f"novel {nid} {mode}: NO BODY, top keys={list(d.keys())}")
            continue
        if isinstance(b, list):
            nls = sum(1 for x in b if isinstance(x, str) and "\n" in x)
            kind = f"array[{len(b)}]"
            det = f"elements w/ embedded newlines: {nls}"
        else:
            if b.startswith(("arr:", "str:")):
                try:
                    pt = decrypt(b)
                except Exception as e:
                    print(f"novel {nid} {mode}: {b[:4]} DECRYPT FAIL: {e}")
                    continue
                nln = pt.count("\n")
                starts_json = pt.lstrip().startswith("[")
                if starts_json:
                    arr = json.loads(pt)
                    kind = f"{b[:4]}->jsonarray[{len(arr)}]"
                    det = f"decrypted array, {len(arr)} paras"
                else:
                    kind = f"{b[:4]}->string({len(pt)}ch)"
                    det = f"decrypted string: newlines={nln}, dbl={pt.count(chr(10)*2)}"
                    print(f"  *** STR body decrypted sample: {pt[:200]!r}")
            else:
                kind = f"plain-string({len(b)}ch)"
                det = f"newlines={b.count(chr(10))}, dbl={b.count(chr(10)*2)}"
                print(f"  *** PLAIN STRING body sample: {b[:200]!r}")
        seen_kinds[kind] = seen_kinds.get(kind, 0) + 1
        print(f"novel {nid} {mode}: {kind} — {det}")

print("\n=== SUMMARY ===")
for k, v in sorted(seen_kinds.items()):
    print(f"  {v}x {k}")
