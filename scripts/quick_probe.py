#!/usr/bin/env python3
"""quick_probe.py <url> [marker ...] — fetch a URL (direct), print code/size/marker hits."""
import subprocess, sys

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36"

def curl(url, timeout=25):
    cmd = ["curl", "-s", "-L", "-m", str(timeout), "-A", UA,
           "-H", "Accept-Language: zh-TW,zh;q=0.9,en;q=0.8", "--compressed",
           "-w", "\n__HTTP_CODE__%{http_code}"]
    cmd.append(url)
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout+10).stdout
        if "__HTTP_CODE__" in out:
            body, code = out.rsplit("__HTTP_CODE__", 1)
            return int(code.strip()), body
        return -1, out
    except Exception as e:
        return -1, str(e)

if __name__ == "__main__":
    url = sys.argv[1]
    markers = sys.argv[2:]
    code, body = curl(url)
    print(f"HTTP {code}, {len(body)} bytes")
    for m in markers:
        print(f"  {'+' if m in body else '-'} '{m}'")
    if code != 200:
        print("BODY HEAD:", body[:500].replace("\n", " ")[:400])
