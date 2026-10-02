#!/usr/bin/env python3
"""Probe 2: HTML-route catalog viability (pagination + filters), chapter/reader latency, encryption key check."""
import time, json, ssl, gzip, re, urllib.request, urllib.error, base64

BASE = "https://wtr-lab.com/"
UA = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
ctx = ssl.create_default_context()

def get(url, headers=None, timeout=35):
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
        if e.headers.get("Content-Encoding") == "gzip":
            try: raw = gzip.decompress(raw)
            except Exception: pass
        return e.code, raw, time.time() - t0
    except Exception as e:
        return -1, str(e).encode(), time.time() - t0

def post(url, body, headers=None, timeout=35):
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
        if e.headers.get("Content-Encoding") == "gzip":
            try: raw = gzip.decompress(raw)
            except Exception: pass
        return e.code, raw, time.time() - t0
    except Exception as e:
        return -1, str(e).encode(), time.time() - t0

def nextdata(html):
    m = re.search(rb'<script id="__NEXT_DATA__" type="application/json"[^>]*>(.*?)</script>', html, re.S)
    if not m: return None
    try: return json.loads(m.group(1).decode("utf-8", "replace"))
    except Exception as e: return {"__err": str(e)}

print("=== A. HTML catalog route: pagination + props (interleaved timing) ===")
for i in range(3):
    for label, url in [
        ("HTML /en/novel-list?page=1", BASE + "en/novel-list?page=1&orderBy=reader"),
        ("HTML /en/novel-list?page=2", BASE + "en/novel-list?page=2&orderBy=reader"),
    ]:
        code, body, dt = get(url)
        d = nextdata(body) or {}
        pp = d.get("props", {}).get("pageProps", {})
        n = len(pp.get("series") or [])
        print(f"  [{dt*1000:6.0f} ms] {code} {len(body):>7} B  {label}: series={n} count={pp.get('count')}")
        if i == 0 and "page=2" in label and n:
            print(f"      page2 first title: {pp['series'][0].get('data',{}).get('title','')[:40]} raw_id={pp['series'][0].get('raw_id')}")

print("=== B. HTML finder route with filters ===")
for label, url in [
    ("finder?ti=696 (System)", BASE + "en/novel-finder?ti=696&tc=or&page=1"),
    ("finder?text=martial", BASE + "en/novel-finder?text=martial&page=1"),
    ("finder?ti=696&status=completed", BASE + "en/novel-finder?ti=696&status=completed&tc=and&page=1"),
]:
    code, body, dt = get(url)
    d = nextdata(body) or {}
    pp = d.get("props", {}).get("pageProps", {})
    n = len(pp.get("series") or [])
    tags = pp.get("tags", {})
    print(f"  [{dt*1000:6.0f} ms] {code} {len(body):>7} B  {label}: series={n} count={pp.get('count')} tags={len(tags.get('ungrouped') or [])}")

print("=== C. Interleaved HTML vs JSON latency (3 rounds) ===")
BUILD = None
code, body, dt = get(BASE + "en/novel-list?page=1")
d = nextdata(body)
BUILD = (d or {}).get("buildId")
print(f"  buildId = {BUILD}")
for i in range(3):
    code, b1, dt1 = get(BASE + f"en/novel-finder?page=1")          # HTML
    code2, b2, dt2 = get(BASE + f"_next/data/{BUILD}/en/novel-finder.json?page=1")  # JSON
    print(f"  round {i+1}: HTML {dt1*1000:6.0f} ms ({len(b1)} B)   JSON {dt2*1000:6.0f} ms ({len(b2)} B)")

print("=== D. Chapters API latency ===")
for i in range(3):
    code, body, dt = get(BASE + "api/chapters/93618", headers={"Referer": BASE + "en/novel/93618/x"})
    try:
        j = json.loads(body)
        nc = len(j.get("chapters", []))
    except Exception:
        nc = "?"
    print(f"  [{dt*1000:6.0f} ms] {code} {len(body):>7} B  api/chapters/93618: {nc} chapters")

print("=== E. Reader API latency + encryption format ===")
arrs = []
for i in range(3):
    code, body, dt = post(BASE + "api/reader/get",
        json.dumps({"translate": "web", "language": "none", "raw_id": "93618", "chapter_no": 1, "retry": False, "force_retry": False}),
        headers={"Referer": BASE + "en/novel/93618/x"})
    snippet = body[:200].decode("utf-8", "replace")
    print(f"  [{dt*1000:6.0f} ms] {code} {len(body):>7} B  reader/get: {snippet[:120]}")
    try:
        j = json.loads(body)
        bd = ((j.get("data") or {}).get("data") or {}).get("body")
        if isinstance(bd, str) and bd.startswith(("arr:", "str:")):
            arrs.append(bd)
    except Exception: pass

print("=== F. Decrypt check (key unchanged?) ===")
KEY = b"IJAFUUxjM25hyzL2AZrn0wl7cESED6Ru"
try:
    import cryptography.hazmat.primitives.ciphers as C
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    ok = True
except Exception:
    ok = False
    print("  (cryptography lib missing — manual GCM not run)")
if arrs:
    payload = arrs[0]
    print(f"  payload format: {payload[:60]}...")
    parts = payload.split(":")
    fmt = parts[0]; iv = base64.b64decode(parts[1]); tag = base64.b64decode(parts[2]); ct = base64.b64decode(parts[3])
    print(f"  fmt={fmt} iv={len(iv)}B tag={len(tag)}B ct={len(ct)}B")
    if ok:
        try:
            aes = AESGCM(KEY)
            # GCM with non-96-bit IV: J0 = GHASH-derived; python cryptography rejects non-12B IVs for AESGCM.
            # Fallback: CTR mode with J0 computed manually is complex — try AESGCM anyway:
            pt = aes.decrypt(iv, ct + tag, None)
            print(f"  DECRYPT OK (AESGCM direct): {pt[:60]!r}")
        except Exception as e:
            print(f"  AESGCM direct failed (expected if IV != 12B): {e}")
            try:
                from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
                # J0 for non-96-bit IV: J0 = GHASH(IV padded to 128-bit multiple || [len(IV)]64 || 0^64) — implement minimal GHASH
                def ghash(h, data):
                    R = int.from_bytes(h, 'big')
                    y = 0
                    for i in range(0, len(data), 16):
                        blk = int.from_bytes(data[i:i+16].ljust(16, b'\x00'), 'big')
                        y = (y ^ blk)
                        # multiply in GF(2^128)
                        z = 0; v = y
                        for bit in range(127, -1, -1):
                            if (R >> bit) & 1: z ^= v
                            v = (v << 1) ^ (0xE1000000000000000000000000000000 if v >> 127 else 0)
                        y = z
                    return y.to_bytes(16, 'big')
                cipher = Cipher(algorithms.AES(KEY), modes.ECB())
                enc = cipher.encryptor()
                H = enc.update(b'\x00' * 16)
                ivpad = iv + b'\x00' * ((16 - len(iv) % 16) % 16) + (len(iv) * 8).to_bytes(8, 'big') + b'\x00' * 8
                J0 = ghash(H, ivpad)
                ctr = int.from_bytes(J0, 'big') + 1
                ctrbytes = ctr.to_bytes(16, 'big')
                c2 = Cipher(algorithms.AES(KEY), modes.CTR(ctrbytes, initial_value=ctr))
                dec = c2.decryptor()
                pt = dec.update(ct) + dec.finalize()
                print(f"  DECRYPT via CTR(J0): {pt[:80]!r}")
            except Exception as e2:
                print(f"  manual CTR failed: {e2}")
else:
    print("  no arr: payload captured")

print("=== G. /api/search quick search ===")
for q in ["sys", "system", "martial"]:
    code, body, dt = post(BASE + "api/search", json.dumps({"text": q}))
    print(f"  [{dt*1000:6.0f} ms] {code} {len(body):>6} B  api/search '{q}': {body[:200].decode('utf-8','replace')[:180]}")

print("=== H. /en (homepage) as light buildId source, repeated ===")
for i in range(3):
    code, body, dt = get(BASE + "en")
    print(f"  [{dt*1000:6.0f} ms] {code} {len(body):>7} B  /en hasBuildId={b'buildId' in body}")
