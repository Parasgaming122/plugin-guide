#!/usr/bin/env python3
"""Generate synthetic oop.tw catalog fixtures for the v1.1.0 TOC tests.

The real fixtures (oop_book.html / oop_book_p2.html) only cover a 2-page
book. The v1.1.0 tests need:
  - a 5-page book (early-abort, resume, interior-cache, LRU)
  - a single-page book (LRU + 1-page-book behavior)
Pages are minimal: only .chap-pager select + #ul_all_chapters list —
exactly what the plugin parses from catalog pages. Chapter ids mimic the
site's global-article-id URLs. Page 2 embeds the site's swapped-adjacent-
chapters quirk (031,033,032,034…) to exercise the numeric re-sort.
"""
import os

OUT = "/home/z/my-project/research/newsites"
BOOK = "9990001"
SINGLE_BOOK = "9990003"
TOTAL_PAGES = 5
PER = 30

def options(cur):
    opts = []
    for p in range(1, TOTAL_PAGES + 1):
        lo = (p - 1) * PER + 1
        hi = p * PER
        sel = ' selected=""' if p == cur else ""
        opts.append(f'<option value="{p}"{sel}>第{lo}～{hi}章</option>')
    return " ".join(opts)

def chapter_items(nums, quirk=False):
    lis = []
    order = list(nums)
    if quirk:
        # swap adjacent pairs: 031,033,032,035,034... (site quirk)
        swapped = []
        i = 0
        while i < len(order):
            if i + 2 < len(order):
                swapped.extend([order[i], order[i + 2], order[i + 1]])
                i += 3
            else:
                swapped.append(order[i])
                i += 1
        order = swapped
    for n in order:
        art = 9100000 + n
        lis.append(
            f'<li class="chapter-item"><a href="/areada/a{BOOK}a/a{art}a.html" '
            f'title="测试小说{n:03d}">{n:03d}</a></li>'
        )
    return "\n".join(lis)

def page(cur):
    lo = (cur - 1) * PER + 1
    hi = cur * PER
    nums = range(lo, hi + 1)
    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>测试小说 - 短篇小說</title></head><body>
<div class="novel-main"><h1 class="novel-title">测试小说</h1></div>
<div class="latest-chapter"><span class="update-time">2026-09-01</span></div>
<div id="catalog-content" class="content-section">
 <div class="chapter-list">
  <div class="chap-pager"><select class="cp-select">{options(cur)}</select></div>
  <div class="chap-pager chap-pager-bottom"><select class="cp-select">{options(cur)}</select></div>
  <ul class="chapter-grid" id="ul_all_chapters">
{chapter_items(nums, quirk=(cur == 2))}
  </ul>
 </div>
</div>
</body></html>
"""

def single():
    nums = range(1, 13)
    lis = []
    for n in nums:
        art = 9200000 + n
        lis.append(
            f'<li class="chapter-item"><a href="/areada/a{SINGLE_BOOK}a/a{art}a.html" '
            f'title="单页书{n:03d}">{n:03d}</a></li>'
        )
    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>单页书 - 短篇小說</title></head><body>
<div class="novel-main"><h1 class="novel-title">单页书</h1></div>
<div class="latest-chapter"><span class="update-time">2026-09-02</span></div>
<div id="catalog-content" class="content-section">
 <div class="chapter-list">
  <div class="chap-pager"><select class="cp-select"><option value="1" selected="">第1～12章</option></select></div>
  <ul class="chapter-grid" id="ul_all_chapters">
{chr(10).join(lis)}
  </ul>
 </div>
</div>
</body></html>
"""

os.makedirs(OUT, exist_ok=True)
for p in range(1, TOTAL_PAGES + 1):
    fn = f"{OUT}/oop_tocgen_p{p}.html"
    with open(fn, "w", encoding="utf-8") as f:
        f.write(page(p))
    print("wrote", fn)

fn = f"{OUT}/oop_tocgen_single.html"
with open(fn, "w", encoding="utf-8") as f:
    f.write(single())
print("wrote", fn)
