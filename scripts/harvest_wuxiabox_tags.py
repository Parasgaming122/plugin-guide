#!/usr/bin/env python3
"""WuxiaBox tag harvester — paced fetch of /browsetags/{A..Z}-{page}.html via r.jina.ai.

- Queue starts with the misc probe URLs + letter page-0 for A..Z.
- After a letter's page 0 is fetched, its real page count is parsed and extra
  pages are enqueued.
- Every page's <li><a href="/tags/{id}-0.html">{label}</a></li> entries are
  appended to tags_raw.json (id, label, letter, page).
- 401 "bad IP reputation" responses trigger exponential backoff retries.
- Progress markers in research/wuxiabox/harvest_done/ make the run resumable.
"""
import json, os, re, subprocess, sys, time, random

BASE = "/home/z/my-project/research/wuxiabox"
DONE = os.path.join(BASE, "harvest_done")
os.makedirs(DONE, exist_ok=True)

# optional time budget (seconds) — lets the script run in foreground chunks
MAX_SECONDS = float(sys.argv[1]) if len(sys.argv) > 1 else None
STARTED = time.time()

def save():
    # dedup by tag id (first occurrence wins)
    seen = {}
    for t in tags:
        if t["id"] not in seen:
            seen[t["id"]] = t
    json.dump(list(seen.values()), open(RAW, "w"), ensure_ascii=False, indent=0)

RAW = os.path.join(BASE, "tags_raw.json")
if os.path.exists(RAW):
    _seen = {}
    for t in json.load(open(RAW)):
        _seen[t["id"]] = t
    tags = list(_seen.values())
else:
    tags = []

def fetch(url, outfile, retries=4):
    """Fetch via r.jina.ai with backoff. Returns True on success.

    Success = HTTP 200 AND size >= 800 bytes (jina's 401 block page is ~343
    bytes; small error pages fall through to retry logic).
    """
    for attempt in range(retries):
        try:
            r = subprocess.run(
                ["curl", "-s", "--max-time", "90",
                 "-H", "X-Return-Format: html",
                 "-o", outfile, "-w", "%{http_code}",
                 "https://r.jina.ai/" + url],
                capture_output=True, text=True, timeout=100)
            code = r.stdout.strip()
            size = os.path.getsize(outfile) if os.path.exists(outfile) else 0
            if code == "200" and size >= 800:
                return True
            if code == "401":
                wait = 60 if attempt < 2 else 120
                print(f"    401 blocked, backoff {wait}s (attempt {attempt+1})", flush=True)
                time.sleep(wait)
                continue
            # 200-but-tiny (maintenance page) or other codes: two quick retries
            print(f"    code={code} size={size}, retrying", flush=True)
            time.sleep(30)
        except Exception as e:
            print(f"    error: {e}", flush=True)
            time.sleep(20)
    return False

def parse_tags(html):
    out = []
    for m in re.finditer(r'<li><a href="/tags/(\d+)-\d+\.html">(.*?)</a></li>', html):
        out.append((m.group(1), m.group(2)))
    return out

def parse_max_page(html, letter):
    pages = [int(p) for p in re.findall(rf'href="/browsetags/{letter}-(\d+)\.html"', html)]
    return max(pages) if pages else 0

def done_marker(key):
    return os.path.join(DONE, key.replace("/", "_") + ".done")

# ── build initial queue ────────────────────────────────────────────────
queue = []  # (key, url, outfile)

# misc probes first (needed for plugin design decisions)
probes = [
    ("misc_comma_tags", "https://www.wuxiabox.com/tags/34,229-0.html", "tags_comma_test.html"),
    ("misc_updates",    "https://www.wuxiabox.com/updates/",            "updates.html"),
    ("misc_search_get", "https://www.wuxiabox.com/e/search/?searchget=1&keyboard=hongmeng&show=title&tbname=news&tempid=1", "search_get_test.html"),
]
for k, u, f in probes:
    if not os.path.exists(done_marker(k)):
        queue.append((k, u, os.path.join(BASE, f)))

for L in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
    k = f"tags_{L}_0"
    if not os.path.exists(done_marker(k)):
        queue.append((k, f"https://www.wuxiabox.com/browsetags/{L}-0.html",
                      os.path.join(BASE, f"letter_{L}_0.html")))

# re-discover extra pages from previously saved letter page-0 files
# (multi-run resume: page 0 was fetched in an earlier run, its pagination
# revealed pages 1..N which must be queued now)
for L in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
    p0 = os.path.join(BASE, f"letter_{L}_0.html")
    if not os.path.exists(p0) or not os.path.exists(done_marker(f"tags_{L}_0")):
        continue
    html0 = open(p0, encoding="utf-8", errors="replace").read()
    maxp = parse_max_page(html0, L)
    for p in range(1, maxp + 1):
        pk = f"tags_{L}_{p}"
        if not os.path.exists(done_marker(pk)) and not any(q[0] == pk for q in queue):
            queue.append((pk, f"https://www.wuxiabox.com/browsetags/{L}-{p}.html",
                          os.path.join(BASE, f"letter_{L}_{p}.html")))

print(f"initial queue: {len(queue)}", flush=True)

# ── run queue ──────────────────────────────────────────────────────────
base_pace = 22.0
for i, (key, url, outfile) in enumerate(queue):
    if os.path.exists(done_marker(key)):
        continue
    if MAX_SECONDS and time.time() - STARTED > MAX_SECONDS:
        print(f"TIME BUDGET REACHED — resume with another run", flush=True)
        break
    print(f"[{i+1}/{len(queue)}] {key}", flush=True)
    ok = fetch(url, outfile)
    if not ok:
        print(f"    FAILED permanently: {key}", flush=True)
        continue
    open(done_marker(key), "w").write("ok")

    if key.startswith("tags_"):
        L = key.split("_")[1]
        html = open(outfile, encoding="utf-8", errors="replace").read()
        entries = parse_tags(html)
        if not entries and "Maintenance" in html[:2000]:
            # transient site maintenance — requeue at the end
            os.remove(done_marker(key))
            queue.append((key, url, outfile))
            print("    site in maintenance mode, requeued", flush=True)
            time.sleep(120)
            continue
        for tid, label in entries:
            tags.append({"id": tid, "label": label, "letter": L})
        save()
        print(f"    +{len(entries)} tags (total {len(tags)})", flush=True)
        # enqueue remaining pages of this letter
        maxp = parse_max_page(html, L)
        for p in range(1, maxp + 1):
            pk = f"tags_{L}_{p}"
            if not os.path.exists(done_marker(pk)) and not any(q[0] == pk for q in queue):
                queue.append((pk, f"https://www.wuxiabox.com/browsetags/{L}-{p}.html",
                              os.path.join(BASE, f"letter_{L}_{p}.html")))
                print(f"    enqueued page {p} for {L} (letter has {maxp+1} pages)", flush=True)

    time.sleep(base_pace + random.uniform(0, 8))

print(f"HARVEST COMPLETE — {len(tags)} tags", flush=True)
save()
