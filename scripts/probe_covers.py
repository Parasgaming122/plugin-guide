#!/usr/bin/env python3
"""Probe live cover-image URLs for wtr-lab, novel543, wuxiabox — diagnose poster loading."""
import json, subprocess, sys, re

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

def curl(url, headers=None, method="GET", body=None, max_time=25):
    cmd = ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}|%{content_type}|%{size_download}|%{url_effective}|%{num_redirects}",
           "--max-time", str(max_time), "-A", UA, "-L"]
    if method == "HEAD":
        cmd.append("-I")
    for k, v in (headers or {}).items():
        cmd += ["-H", f"{k}: {v}"]
    if body:
        cmd += ["--data", body]
    cmd.append(url)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=max_time + 10)
    return r.stdout.strip()

def curl_body(url, headers=None, max_time=25):
    cmd = ["curl", "-s", "--max-time", str(max_time), "-A", UA]
    for k, v in (headers or {}).items():
        cmd += ["-H", f"{k}: {v}"]
    cmd.append(url)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=max_time + 10)
    return r.stdout

print("=" * 70)
print("1) WTR-LAB — find cover URL shape from live finder JSON")
print("=" * 70)
try:
    body = curl_body("https://wtr-lab.com/en/novel-finder",
                     {"Accept": "text/html,application/xhtml+xml", "Accept-Language": "en-US,en;q=0.9",
                      "Sec-Fetch-Dest": "document", "Sec-Fetch-Mode": "navigate", "Sec-Fetch-Site": "none"})
    m = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', body, re.S)
    if m:
        data = json.loads(m.group(1))
        series = data["props"]["pageProps"].get("series") or []
        for s in series[:3]:
            img = (s.get("data") or {}).get("image", "")
            print(f"  title={(s.get('data') or {}).get('title','?')!r}")
            print(f"  image={img!r}")
        # probe the first image URL with/without Referer
        img = (series[0].get("data") or {}).get("image", "") if series else ""
        if img:
            url = img if img.startswith("http") else "https://wtr-lab.com" + img
            print(f"  -- GET image (no referer): {curl(url)}")
            print(f"  -- GET image (referer={url.split('/').__class__ and 'scheme://host/'})")
            ref = "/".join(url.split("/")[:3]) + "/"
            print(f"     referer={ref}: {curl(url, {'Referer': ref})}")
            print(f"  -- GET image (referer=https://wtr-lab.com/): {curl(url, {'Referer': 'https://wtr-lab.com/'})}")
    else:
        print("  ! no __NEXT_DATA__ in finder HTML (len=%d)" % len(body))
        print("  body head:", body[:300].replace("\n", " "))
except Exception as e:
    print("  ERROR:", e)

print()
print("=" * 70)
print("2) NOVEL543 — find cover URL shape from live bookstack")
print("=" * 70)
try:
    body = curl_body("https://www.novel543.com/bookstack/?page=1")
    imgs = re.findall(r'div class="media-left"[^>]*>\s*<a[^>]*>\s*<img[^>]*src="([^"]+)"', body)
    if not imgs:
        imgs = re.findall(r'<img[^>]+src="(https?://[^"]*(?:cover|image)[^"]*)"', body)
    for u in imgs[:3]:
        print(f"  cover={u!r}")
    if imgs:
        u = imgs[0]
        if not u.startswith("http"):
            u = "https://www.novel543.com" + u
        print(f"  -- GET image (no referer):  {curl(u)}")
        print(f"  -- GET image (referer=https://www.novel543.com/): {curl(u, {'Referer': 'https://www.novel543.com/'})}")
        print(f"  -- GET image (same-origin referer): {curl(u, {'Referer': '/'.join(u.split('/')[:3]) + '/'})}")
except Exception as e:
    print("  ERROR:", e)

print()
print("=" * 70)
print("3) WUXIABOX — cover URL from fixtures + live attempt")
print("=" * 70)
import glob, os
fx = sorted(glob.glob("/home/z/my-project/research/wuxiabox/*novel*.html") + glob.glob("/home/z/my-project/research/wuxiabox/**/*novel*.html", recursive=True))
print("  fixture files:", [os.path.basename(f) for f in fx][:6])
for f in fx[:2]:
    body = open(f, encoding="utf-8", errors="replace").read()
    m = re.search(r'figure class="cover"[^>]*>\s*<img[^>]*(?:data-src|src)="([^"]+)"', body)
    if not m:
        m = re.search(r'<img[^>]+(?:data-src|src)="([^"]+(?:cover|/files/)[^"]*)"', body)
    if m:
        u = m.group(1)
        print(f"  {os.path.basename(f)}: cover={u!r}")
        if u.startswith("http"):
            full = u
        else:
            full = "https://wuxiabox.com" + u
        print(f"  -- GET image live (no referer):  {curl(full)}")
        print(f"  -- GET image live (referer=https://wuxiabox.com/): {curl(full, {'Referer': 'https://wuxiabox.com/'})}")
        break
