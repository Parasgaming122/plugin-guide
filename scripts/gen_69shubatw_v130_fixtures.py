#!/usr/bin/env python3
"""v1.3.0 fixtures — the REAL /Indexlist/ markup, captured live 2026-09-26 via
the Google-Translate proxy (clean IPs pass; lowercase /indexlist/ is the
EdgeOne WAF path rule, capital /Indexlist/ bypasses it — the discovery that
fixes the solver storm).

Sources (research/69shubatw/):
  idx_p1_real.html  /Indexlist/342441/    page 1  (ch 1-100,  98 a + 2 span)
  idx_p2.html       /Indexlist/342441/2/  page 2  (ch 101-200)
  idx_p3.html       /Indexlist/342441/3/  page 3  (ch 201-300)
  idx_p4.html       /Indexlist/342441/4/  page 4  (ch 301-400)
  idx_p5.html       /Indexlist/342441/5/  page 5  (ch 401-450, last page)

De-GT-ification (same rules as clean_69shubatw_fixtures.py):
  - https://69shuba-tw.translate.goog{path}?_x_tr_...  →  {path} (relative)
  - drop the injected <base>
  - strip google-translate injected scripts

Also synthesizes:
  idx_small_p1.html   single-page novel (40 chapters, 1 select option,
                      no next link) — the user's "40-chapter novel" case
  idx_chal.html       the EdgeOne challenge page (detection path)
"""
import re, os

SRC = "/home/z/my-project/research/69shubatw"
OUT = os.path.join(SRC, "fixtures")
os.makedirs(OUT, exist_ok=True)

GOOG_SCRIPT_PATTERNS = [
    r'<script id="google-translate-element-script">[\s\S]*?</script>',
    r'<script[^>]*src="https://www\.gstatic\.com[^"]*"[^>]*>\s*</script>',
    r'<script[^>]*src="https://www\.googletagmanager\.com[^"]*"[^>]*>\s*</script>',
    r'<link[^>]*href="https://www\.gstatic\.com[^"]*"[^>]*/?>',
    r'<link[^>]*href="https://www\.google\.com[^"]*"[^>]*/?>',
]

def de_gt(raw):
    raw = re.sub(r'https://69shuba-tw\.translate\.goog(/[^"?]*)?(?:\?[^"]*)?',
                 lambda m: m.group(1) or '/', raw)
    raw = raw.replace('&amp;_x_tr_sl', '')
    raw = re.sub(r'<base href="[^"]*">\s*', '', raw)
    for pat in GOOG_SCRIPT_PATTERNS:
        raw = re.sub(pat, '', raw)
    raw = re.sub(r'<script>\s*function gtElInit[\s\S]*?</script>', '', raw)
    raw = re.sub(r'<script>\s*\(function\(\)\s*\{\s*if\(!window\[\'_DumpException\'\][\s\S]*?</script>', '', raw)
    raw = re.sub(r'<script>\s*window\.dataLayer[\s\S]*?</script>', '', raw)
    raw = re.sub(r'\?_x_tr_sl=[^"\s]*', '', raw)
    return raw

def analyze(name, html, book_id="342441"):
    title = re.search(r'<title>([^<]*)', html)
    anchors = re.findall(r'href="(/read/%s/\d+)"' % book_id, html)
    protected = re.findall(r'data-cid-url="(/read/%s/\d+)"' % book_id, html)
    opts = re.findall(r'<option[^>]*value="([^"]*)"[^>]*>([^<]*)</option>', html)
    nxt = re.search(r'<a[^>]*href="([^"]*)"[^>]*>\s*下一页\s*</a>', html)
    prev = re.search(r'<a[^>]*href="([^"]*)"[^>]*>\s*上一页\s*</a>', html)
    return {
        "file": name,
        "title": title.group(1) if title else "?",
        "unique_chapters": len(set(anchors) | set(protected)),
        "anchors": len(set(anchors)), "protected": len(set(protected)),
        "options": len(opts),
        "last_opt": opts[-1] if opts else None,
        "next": nxt.group(1) if nxt else None,
        "prev": prev.group(1) if prev else None,
    }

def main():
    print("── real /Indexlist/ pages (de-GT-ified) ─────────────────────────")
    results = {}
    for src, out, page in [
        ("idx_p1_real.html", "idx_p1.html", 1),
        ("idx_p2.html",      "idx_p2.html", 2),
        ("idx_p3.html",      "idx_p3.html", 3),
        ("idx_p4.html",      "idx_p4.html", 4),
        ("idx_p5.html",      "idx_p5.html", 5),
    ]:
        raw = open(os.path.join(SRC, src), encoding='utf-8').read()
        cleaned = de_gt(raw)
        open(os.path.join(OUT, out), 'w', encoding='utf-8').write(cleaned)
        r = analyze(out, cleaned)
        results[page] = r
        print(f"  p{page}: {r['unique_chapters']:3d} ch ({r['anchors']} a + {r['protected']} span), "
              f"{r['options']} opts, next={r['next']}, prev={r['prev']}")
        print(f"        title: {r['title'][:46]}")

    # sanity: totals must match the select labels
    total = sum(r["unique_chapters"] for r in results.values())
    print(f"  TOTAL across 5 pages: {total} (expected 450)")
    assert total == 450, "chapter total mismatch!"

    # challenge page fixture
    raw = open(os.path.join(SRC, "p_direct.html"), encoding='utf-8').read()
    open(os.path.join(OUT, "idx_chal.html"), 'w', encoding='utf-8').write(raw)
    print(f"  idx_chal.html: {len(raw)} bytes (EdgeOne aegis challenge)")

    # ── synthesized: single-page 40-chapter novel (book 777777) ─────────
    # built from the REAL page-5 template: same li/option/pager shapes,
    # cids 5550001..5550040 (ascending), a couple of protected spans,
    # select with ONE option (page 1), NO next link, NO prev link.
    p5 = open(os.path.join(OUT, "idx_p5.html"), encoding='utf-8').read()
    lis = re.findall(r'<li[^>]*>.*?</li>', p5, re.S)
    assert lis, "no li items found in p5 template"
    # build the 40 items, alternating plain/protected like the real pages
    items = []
    for i in range(1, 41):
        cid = 5550000 + i
        if i % 7 == 3:  # protected span form (like 第2章/第99章 on the real pages)
            items.append(
                f'<li class="{"even" if i % 2 == 0 else ""}">'
                f'<span class="protected-chapter-link" data-cid-url="/read/777777/{cid}" '
                f'data-title="測試小說 第{i}章 測試章節{i}"> 第{i}章 測試章節{i} </span></li>')
        else:
            items.append(
                f'<li class="{"even" if i % 2 == 0 else ""}">'
                f'<a href="/read/777777/{cid}" title="測試小說 第{i}章 測試章節{i}">第{i}章 測試章節{i}</a></li>')
    small = p5
    # replace the chapter <li> block (between the first <ul class="last9"> and </ul>)
    small = re.sub(r'(<ul class="last9">)[\s\S]*?(</ul>)',
                   lambda m: m.group(1) + "\n      " + "\n      ".join(items) + "\n    " + m.group(2),
                   small, count=1)
    # title / headings
    small = re.sub(r'<title>.*?</title>',
                   '<title>《測試小說》章節目錄_第1頁_69書吧</title>', small, count=1)
    # select: single option = page 1
    small = re.sub(r'<select[^>]*>[\s\S]*?</select>',
                   '<select id="indexselect-top" aria-label="章節目錄選擇" '
                   'onchange="self.location.href=options[selectedIndex].value">'
                   '<option value="/indexlist/777777/" selected>1 - 40章</option></select>',
                   small, count=1)
    # pager: single page — drop the prev anchor (page 1 has none), the
    # "没有了" disabled next span stays (copied from the p5 template)
    # book id in pager/prev/next links + back link FIRST, then strip prev
    small = small.replace('/indexlist/342441/', '/indexlist/777777/')
    small = small.replace('/Indexlist/342441/', '/Indexlist/777777/')
    small = small.replace('/book/342441/', '/book/777777/')
    small = re.sub(r'<a[^>]*href="/indexlist/777777/\d+/"[^>]*>\s*上一页\s*</a>', '', small)
    small = small.replace('《大明：老四，帶咱一起修仙！》', '《測試小說》')
    # remove any remaining 下一页 anchor (p5 had none — it had 没有了 span; ensure it stays)
    open(os.path.join(OUT, "idx_small_p1.html"), 'w', encoding='utf-8').write(small)
    r = analyze("idx_small_p1.html", small, book_id="777777")
    print(f"  idx_small_p1.html: {r['unique_chapters']} ch ({r['anchors']} a + {r['protected']} span), "
          f"{r['options']} opts, next={r['next']}, prev={r['prev']}")
    assert r["unique_chapters"] == 40, "small fixture should have exactly 40 chapters"
    assert r["next"] is None and r["options"] == 1

    print("\nAll v1.3.0 fixtures written to", OUT)

if __name__ == "__main__":
    main()
