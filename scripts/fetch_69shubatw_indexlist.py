#!/usr/bin/env python3
"""Battery of proxy strategies to capture the REAL /indexlist/342441/ markup."""
import subprocess, os, time, hashlib

OUT = "/home/z/my-project/research/69shubatw"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
TARGET = "https://69shuba.tw/indexlist/342441/"

CAPTCHA_MARKS = ["aegis_captcha_verify", "recaptcha-v3-container",
                 "Please complete human verification"]

def probe(name, url, extra=None, timeout=45):
    dest = os.path.join(OUT, name)
    cmd = ["curl", "-s", "-L", "--max-time", str(timeout), "-A", UA,
           "-o", dest, "-w", "%{http_code}|%{size_download}|%{url_effective}", url]
    if extra:
        cmd = cmd[:-1] + extra + [url] if False else ["curl", "-s", "-L", "--max-time", str(timeout), "-A", UA] + extra + ["-o", dest, "-w", "%{http_code}|%{size_download}|%{url_effective}", url]
    r = subprocess.run(cmd, capture_output=True, text=True)
    parts = r.stdout.strip().split("|")
    code, size, final = (parts + ["", "", ""])[:3]
    size = os.path.getsize(dest) if os.path.exists(dest) else 0
    head = ""
    try:
        head = open(dest, encoding="utf-8", errors="ignore").read(3000)
    except Exception:
        pass
    captcha = any(m in head for m in CAPTCHA_MARKS)
    real = ("indexlist" in head or "read/342441" in head) and not captcha and size > 5000
    verdict = "CAPTCHA" if captcha else ("REAL PAGE?" if real else "other")
    print(f"[{name}] http={code} size={size} final={final[:90]} -> {verdict}", flush=True)
    if real:
        print(f"    *** WINNER: {url}", flush=True)
    return real

# Strategy 1: Google Translate proxy variants (worked for every path except /indexlist/)
gt = lambda qs: "https://69shuba-tw.translate.goog/indexlist/342441/?" + qs
cands = [
    ("p_gt_a.html", gt("_x_tr_sl=zh&_x_tr_tl=en&_x_tr_hl=zh-CN")),
    ("p_gt_b.html", gt("_x_tr_sl=auto&_x_tr_tl=en&_x_tr_hl=en")),
    ("p_gt_c.html", gt("_x_tr_sl=zh-CN&_x_tr_tl=zh-TW&_x_tr_hl=zh-TW")),
    ("p_gt_d.html", gt("_x_tr_sl=zh&_x_tr_tl=ja&_x_tr_hl=ja")),
    ("p_gt_e.html", "https://69shuba-tw.translate.goog/indexlist/342441?_x_tr_sl=zh&_x_tr_tl=en&_x_tr_hl=zh-CN"),
    # page-2 shape via proxy (also reveals the pagination URL if it 200s)
    ("p_gt_p2.html", "https://69shuba-tw.translate.goog/indexlist/342441/2/?_x_tr_sl=zh&_x_tr_tl=en&_x_tr_hl=zh-CN"),
    # Strategy 2: alternate GT hosts
    ("p_gt_h2.html", "https://69shuba-tw-translate.goog/indexlist/342441/?_x_tr_sl=zh&_x_tr_tl=en&_x_tr_hl=zh-CN"),
    # Strategy 3: classic translate redirect form
    ("p_tredir.html", "https://translate.google.com/translate?sl=zh&tl=en&u=https://69shuba.tw/indexlist/342441/"),
    # Strategy 4: r.jina.ai reader proxy
    ("p_jina.html", "https://r.jina.ai/https://69shuba.tw/indexlist/342441/"),
    # Strategy 5: allorigins
    ("p_allorig.html", "https://api.allorigins.win/raw?url=" + TARGET.replace(":", "%3A").replace("/", "%2F")),
    # Strategy 6: codetabs
    ("p_codetabs.html", "https://api.codetabs.com/v1/proxy?quest=" + TARGET),
    # Strategy 7: corsproxy
    ("p_cors.html", "https://corsproxy.io/?url=" + TARGET.replace(":", "%3A").replace("/", "%2F")),
    # Strategy 8: direct with browser-ish headers (verify current WAF state)
    ("p_direct.html", TARGET),
    # Strategy 9: mobile subdomain guess
    ("p_m_dot.html", "https://m.69shuba.tw/indexlist/342441/"),
]

winners = []
for name, url in cands:
    try:
        if probe(name, url):
            winners.append((name, url))
    except Exception as e:
        print(f"[{name}] EXC {e}", flush=True)
    time.sleep(8)

print("\nWINNERS:", winners if winners else "none")
