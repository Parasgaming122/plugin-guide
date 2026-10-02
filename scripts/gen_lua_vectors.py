#!/usr/bin/env python3
"""Generate Lua test vectors from captured WTR-Lab encrypted responses."""
import base64
import glob
import json

out = []
for fn in sorted(glob.glob('/home/z/my-project/wtrlab-analysis/enc_*.json')):
    d = json.load(open(fn))
    body = d['data']['data']['body']
    if not body.startswith(('arr:', 'str:')):
        continue
    rest = body[4:]
    parts = rest.split(':')
    if len(parts) != 3:
        continue
    iv = base64.b64decode(parts[0])
    tag = base64.b64decode(parts[1])
    ct = base64.b64decode(parts[2])
    # data = ct ++ tag (last 16 bytes of concatenated = tag)
    data = ct + tag
    # expected plaintext via cryptography lib
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    KEY = b"IJAFUUxjM25hyzL2AZrn0wl7cESED6Ru"
    plain = AESGCM(KEY).decrypt(iv, data, None)

    def luastr(b):
        # escape for Lua string with \ escapes
        parts = []
        for ch in b:
            c = chr(ch)
            if ch == 92: parts.append("\\\\")
            elif ch == 34: parts.append('\\"')
            elif ch == 10: parts.append("\\n")
            elif ch == 13: parts.append("\\r")
            elif ch == 9: parts.append("\\t")
            elif 32 <= ch < 127: parts.append(c)
            else: parts.append("\\%03d" % ch)
        return '"' + "".join(parts) + '"'

    out.append({
        "name": fn.split('/')[-1],
        "iv": luastr(iv),
        "data": luastr(data),
        "expected": luastr(plain),
    })

with open('/home/z/my-project/test-harness/wtrlab_vectors.lua', 'w') as f:
    f.write("-- auto-generated WTR-Lab decrypt test vectors\n")
    f.write("return {\n")
    for v in out:
        f.write("  { name = %s, iv = %s, data = %s, expected = %s },\n" % (
            '"' + v['name'] + '"', v['iv'], v['data'], v['expected']))
    f.write("}\n")
print(f"wrote {len(out)} vectors")
