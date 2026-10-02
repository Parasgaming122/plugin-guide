#!/usr/bin/env python3
"""Clean 69shuba.tw fixtures fetched through the Google-Translate proxy:
- rewrite https://69shuba-tw.translate.goog{path}?_x_tr_... → {path} (relative)
- drop <base> (injected by the proxy — real pages resolve against baseUrl)
- strip Google-translate injected scripts/elements
- normalize the doctype/format

Fixtures (all fetched 2026-09-20, UTF-8 Traditional Chinese):
  book_gt.html      /book/342441/        (book details)
  chapter_1.html    /read/342441/890315  (chapter 1, (1 / 1))
  chapter_2.html    /read/342441/890316  (chapter 2, (1 / 1))
  home_full.html    /                    (homepage + search form)
  fenlei_lishi.html /fenlei/lishi/1/     (category listing)
  quanben.html      /quanben/fenlei/     (all/completed listing)
  search_test.html  /search/?searchkey=大明&searchtype=all
"""
import re, os, sys

SRC = "/home/z/my-project/research/69shubatw"
OUT = "/home/z/my-project/research/69shubatw/fixtures"
os.makedirs(OUT, exist_ok=True)

GOOG_SCRIPT_PATTERNS = [
    r'<script id="google-translate-element-script">[\s\S]*?</script>',
    r'<script[^>]*src="https://www\.gstatic\.com[^"]*"[^>]*>\s*</script>',
    r'<script[^>]*src="https://www\.googletagmanager\.com[^"]*"[^>]*>\s*</script>',
    r'<link[^>]*href="https://www\.gstatic\.com[^"]*"[^>]*/?>',
    r'<link[^>]*href="https://www\.google\.com[^"]*"[^>]*/?>',
]

def clean(name, out_name):
    raw = open(os.path.join(SRC, name), encoding='utf-8').read()
    n0 = len(raw)
    # 1. rewrite translate-proxy URLs back to relative site paths
    raw = re.sub(r'https://69shuba-tw\.translate\.goog(/[^"?]*)?(?:\?[^"]*)?',
                 lambda m: m.group(1) or '/', raw)
    # also unescape &amp; leftovers inside rewritten hrefs
    raw = raw.replace('&amp;_x_tr_sl', '')  # safety (shouldn't remain)
    # 2. drop injected <base>
    raw = re.sub(r'<base href="[^"]*">\s*', '', raw)
    # 3. strip google injections
    for pat in GOOG_SCRIPT_PATTERNS:
        raw = re.sub(pat, '', raw)
    # gtElInit + _DumpException inline blocks
    raw = re.sub(r'<script>\s*function gtElInit[\s\S]*?</script>', '', raw)
    raw = re.sub(r'<script>\s*\(function\(\)\s*\{\s*if\(!window\[\'_DumpException\'\][\s\S]*?</script>', '', raw)
    raw = re.sub(r'<script>\s*window\.dataLayer[\s\S]*?</script>', '', raw)
    # 4. drop leftover _x_tr_ query fragments anywhere
    raw = re.sub(r'\?_x_tr_sl=zh&amp;_x_tr_tl=en&amp;_x_tr_hl=zh-CN', '', raw)
    raw = re.sub(r'\?_x_tr_sl=zh&_x_tr_tl=en&_x_tr_hl=zh-CN', '', raw)
    out = os.path.join(OUT, out_name)
    open(out, 'w', encoding='utf-8').write(raw)
    print(f"{name:22s} → {out_name:26s} {n0} → {len(raw)} bytes")
    return out

if __name__ == "__main__":
    clean("book_gt.html",       "book_342441.html")
    clean("chapter_1.html",     "chapter_1.html")
    clean("chapter_2.html",     "chapter_2.html")
    clean("home_full.html",     "home.html")
    clean("fenlei_lishi.html",  "fenlei_lishi_1.html")
    clean("quanben.html",       "quanben_fenlei_1.html")
    clean("search_test.html",   "search_daming_1.html")
    print("done")
