#!/usr/bin/env python3
"""Verify WTR-Lab AES-256-GCM decryption with captured samples."""
import base64
import json
import glob

KEY = b"IJAFUUxjM25hyzL2AZrn0wl7cESED6Ru"  # 32 bytes

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    HAVE_CRYPTO = True
except ImportError:
    HAVE_CRYPTO = False
    print("cryptography lib missing, trying pure python...")

def decrypt_body(body_str):
    """Decrypt arr:/str: body. Returns (kind, plaintext)."""
    is_arr = body_str.startswith("arr:")
    is_str = body_str.startswith("str:")
    if is_arr:
        rest = body_str[4:]
    elif is_str:
        rest = body_str[4:]
    else:
        return ("plain", body_str)
    parts = rest.split(":")
    assert len(parts) == 3, f"expected 3 parts, got {len(parts)}"
    s, n, a = parts
    iv = base64.b64decode(s)
    tag = base64.b64decode(n)
    ct = base64.b64decode(a)
    # d = ct ++ tag  (WebCrypto format)
    data = ct + tag
    plain = AESGCM(KEY).decrypt(iv, data, None)
    if is_arr:
        return ("arr", json.loads(plain.decode("utf-8")))
    return ("str", plain.decode("utf-8"))

for fn in sorted(glob.glob("/home/z/my-project/wtrlab-analysis/enc_*.json")):
    print(f"\n=== {fn}")
    d = json.load(open(fn))
    inner = d["data"]["data"]
    body = inner["body"]
    print(f"encrypted flag: {inner.get('encrypted')}")
    print(f"body starts: {body[:80]}")
    if HAVE_CRYPTO:
        try:
            kind, plain = decrypt_body(body)
            if kind == "arr":
                print(f"DECRYPTED as JSON array! {len(plain)} paragraphs")
                for p in plain[:4]:
                    print(f"   | {p[:100]}")
            else:
                print(f"DECRYPTED as string: {str(plain)[:200]}")
        except Exception as e:
            print(f"DECRYPT FAILED: {e}")
            # try alternative order: tag ++ ct
            try:
                parts = body[4:].split(":")
                iv = base64.b64decode(parts[0])
                o = base64.b64decode(parts[1])
                c = base64.b64decode(parts[2])
                plain = AESGCM(KEY).decrypt(iv, o + c, None)
                print(f"ALT ORDER (o++c) WORKS: {plain[:100]}")
            except Exception as e2:
                print(f"ALT also failed: {e2}")
