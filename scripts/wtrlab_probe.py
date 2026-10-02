#!/usr/bin/env python3
"""Live probe of wtr-lab.com: refresh tags, verify finder API params, measure latencies."""
import json, time, re, urllib.request, urllib.parse, ssl

UA = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
ctx = ssl.create_default_context()

def fetch(url, data=None, headers=None, timeout=25):
    h = {"User-Agent": UA, "Accept": "*/*", "Accept-Language": "en-US,en;q=0.9"}
    if headers: h.update(headers)
    req = urllib.request.Request(url, data=data, headers=h)
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            body = r.read().decode("utf-8", "replace")
            return r.status, body, time.time() - t0
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")[:2000], time.time() - t0
    except Exception as e:
        return -1, str(e), time.time() - t0

BASE = "https://wtr-lab.com"

print("=== 1. novel-finder page (tags + buildId) ===")
code, finder_html, dt = fetch(BASE + "/en/novel-finder")
print(f"status={code} len={len(finder_html)} time={dt:.2f}s")
if code != 200:
    print("BLOCKED:", finder_html[:300])

if code == 200:
    m = re.search(r'"buildId":"([^"]+)"', finder_html)
    build_id = m.group(1) if m else None
    print("buildId:", build_id)

    # extract tags from __NEXT_DATA__ pageProps finder tags
    m2 = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', finder_html, re.S)
    if m2:
        try:
            nd = json.loads(m2.group(1))
            pp = nd.get("pageProps", {})
            print("pageProps keys:", list(pp.keys())[:15])
            tags = pp.get("tags") or pp.get("allTags") or []
            print("tags found via pageProps.tags:", len(tags))
            if tags:
                print("sample:", json.dumps(tags[:3]))
                with open("/home/z/my-project/research/real_tags_live.json", "w") as f:
                    json.dump(tags, f)
            else:
                # search for any array of objects with label+category
                for k, v in pp.items():
                    if isinstance(v, list) and v and isinstance(v[0], dict) and "label" in v[0]:
                        print(f"  candidate list '{k}': {len(v)} items, sample:", json.dumps(v[0]))
                        with open(f"/home/z/my-project/research/pp_{k}.json", "w") as f:
                            json.dump(v, f)
        except Exception as e:
            print("NEXT_DATA parse fail:", e)

print("\n=== 2. _next/data novel-finder.json (text search param) ===")
if code == 200 and build_id:
    for params in ["text=martial&page=1", "orderBy=update&order=desc&status=all&text=martial&page=1"]:
        url = f"{BASE}/_next/data/{build_id}/en/novel-finder.json?{params}"
        c, b, dt = fetch(url)
        print(f"params='{params}' status={c} time={dt:.2f}s len={len(b)}")
        if c == 200:
            try:
                j = json.loads(b)
                pp = j.get("pageProps", {})
                print("   count:", pp.get("count"), "series:", len(pp.get("series", [])))
                if pp.get("series"):
                    print("   first:", pp["series"][0].get("data", {}).get("title", "?"))
            except Exception as e:
                print("   parse fail", e, b[:200])

print("\n=== 3. api/chapters latency ===")
c, b, dt = fetch(BASE + "/api/chapters/37118", headers={"Referer": BASE + "/en/novel/37118"})
print(f"status={c} time={dt:.2f}s len={len(b)}")
if c == 200:
    try:
        j = json.loads(b)
        print("chapters:", len(j.get("chapters", [])))
    except Exception as e:
        print("parse fail", e, b[:200])

print("\n=== 4. api/reader/get latency (AI + raw) ===")
for mode in ("ai", "web"):
    body = json.dumps({"translate": mode, "language": "none", "raw_id": "37118", "chapter_no": 1, "retry": False, "force_retry": False}).encode()
    c, b, dt = fetch(BASE + "/api/reader/get", data=body,
                     headers={"Content-Type": "application/json", "Referer": BASE + "/en/novel/37118/super-god-chapter-1", "Origin": BASE})
    print(f"mode={mode} status={c} time={dt:.2f}s len={len(b)}")
    if c == 200:
        try:
            j = json.loads(b)
            keys = list(j.keys())
            print("   keys:", keys, "success:", j.get("success"), "requireTurnstile:", j.get("requireTurnstile"))
            d = j.get("data", {})
            dd = d.get("data", d) if isinstance(d, dict) else {}
            bodyv = dd.get("body", "") if isinstance(dd, dict) else ""
            print("   body type:", type(bodyv).__name__, "arr/str prefix:", str(bodyv)[:8])
        except Exception as e:
            print("   parse fail", e, b[:200])
    else:
        print("   resp head:", b[:200])
