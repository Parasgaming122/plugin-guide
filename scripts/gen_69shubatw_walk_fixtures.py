#!/usr/bin/env python3
"""Synthesize v1.1.0 test fixtures: walk chains, seed book pages, window-TOC.

Book 342441 walk universe (mini):
  ch1..ch10 = cids 890315..890324; every chapter page carries #nr_title with
  a "(1 / 1)" suffix and #pb_next → the next chapter (ch10's → the book page
  = end of book).
Seed book pages:
  mini       last9 = [ch5, ch4]           startread = ch1
  grow_adj   last9 = [ch7, ch6]           startread = ch1   (adjacent growth)
  grow_gap   last9 = [ch10, ch9]          startread = ch1   (gap growth: ch8)
  empty      no last9, no startread                            (dead seed)
Window TOC (book 777001, 15 pages × 30 chapters, cids 6000001+):
  p1  select options 1..10 + 下一页
  p10 select options 6..15 + 下一页
  p15 select options 11..15, NO next
No-select TOC (book 777002):
  p1 no select + 下一页 → p2 ; p2 no select, NO next (2 pages total)
Query-select TOC (book 777003): options "/search/N?x" shapes, no next.
"""
import os

OUT = "/home/z/my-project/research/69shubatw/fixtures"

def chapter_page(n, cid, next_href):
    return f"""<!doctype html><html lang="zh"><head><base href="https://69shuba.tw/read/342441/{cid}">
<meta charset="UTF-8"><title>大明：老四，帶咱一起修仙！_第{n}章 測試章節{n}</title></head>
<body><main>
<h1 class="nr_title" id="nr_title">第{n}章 測試章節{n}(1 / 1)</h1>
<div id="nr1"><p>第{n}章的第一段。</p><p>第{n}章的第二段。</p>
<div class="reader-ad"><script>loadAdv(1, 2);</script></div>
<p>第{n}章的第三段。</p></div>
<nav class="nr_page"><table><tbody><tr>
<td class="prev"><a id="pb_prev" href="/book/342441/">上一章</a></td>
<td class="mulu"><a id="pb_mulu" href="/indexlist/342441/">目錄</a></td>
<td class="next"><a id="pb_next" href="{next_href}">下一章</a></td>
</tr></tbody></table></nav>
</main></body></html>"""

def seed_book(last9, startread):
    lis = "\n".join(
        f'     <li class="{"" if i % 2 == 0 else "even"}"><a href="/read/342441/{cid}">{title}</a></li>'
        for i, (cid, title) in enumerate(last9))
    sr = f'<td><a id="startread" href="/read/342441/{startread}">立即閱讀</a></td>' if startread else "<td></td>"
    latest = (f'<p id="lastchapter-row">最新：<a href="/read/342441/{last9[0][0]}">{last9[0][1]}</a></p>'
              if last9 else '<p id="lastchapter-row">最新：<a href="/indexlist/342441/">目錄</a></p>')
    return f"""<!doctype html><html lang="zh"><head><base href="https://69shuba.tw/book/342441/">
<meta charset="UTF-8"><title>測試書_69書吧</title></head><body><main>
<div class="bookinfo"><table><tbody><tr>
<td><img src="//p.69shuba.tw/342/342441/342441s.jpg" alt="測試書"></td>
<td valign="top" class="info"><h1>測試書</h1><p>作者：<a>測試作者</a></p>
<p>狀態：連載 / 字數：1 萬字</p>{latest}</td>
</tr></tbody></table>
<table class="book-op"><tbody><tr><td><a href="javascript:;">加入書架</a></td>
<td><a href="/indexlist/342441/">章節目錄</a></td>{sr}</tr></tbody></table></div>
<div class="lb_mulu"><div class="book-itemtitle">最新章節預覽</div><div class="cc"></div>
<ul class="last9">
{lis}
     <li class="more"><a href="/indexlist/342441/">更多章節&gt;&gt;</a></li>
</ul></div>
</main></body></html>"""

def toc_page(book_id, page_no, options, next_url, ch_from, ch_to, ch_cid_base):
    """options: list of option page numbers; next_url: str or None"""
    opts = "\n".join(
        f'<option{" selected" if o == page_no else ""} value="/indexlist/{book_id}/{o}/">第{o}页</option>'
        for o in options)
    nxt = (f'<a class="index-container-btn" href="/indexlist/{book_id}/{next_url}/">下一页</a>'
           if next_url else '<span class="index-container-btn disabled-btn">下一页</span>')
    rows = "\n".join(
        f'   <li><a href="/read/{book_id}/{ch_cid_base + i}">第{ch_from + i}章 視窗章節{ch_from + i}</a></li>'
        for i in range(ch_to - ch_from + 1))
    return f"""<!doctype html><html lang="zh"><head><base href="https://69shuba.tw/indexlist/{book_id}/{page_no}/">
<meta charset="UTF-8"><title>目錄 第{page_no}页</title></head><body><main>
<div class="book-itemtitle">章節目錄</div>
<ul class="chapter-list">
{rows}
</ul>
<div class="index-container">
   <span class="index-container-btn disabled-btn">上一页</span><select id="indexselect" aria-label="頁面導航" onchange="self.location.href=options[selectedIndex].value">{opts}</select>{nxt}
  </div>
</main></body></html>"""

def toc_noselect(book_id, page_no, next_url, ch_from, ch_to, ch_cid_base):
    nxt = (f'<a class="index-container-btn" href="/indexlist/{book_id}/{next_url}/">下一页</a>'
           if next_url else '<span class="index-container-btn disabled-btn">下一页</span>')
    rows = "\n".join(
        f'   <li><a href="/read/{book_id}/{ch_cid_base + i}">第{ch_from + i}章 無選章節{ch_from + i}</a></li>'
        for i in range(ch_to - ch_from + 1))
    return f"""<!doctype html><html lang="zh"><head><base href="https://69shuba.tw/indexlist/{book_id}/{page_no}/">
<meta charset="UTF-8"><title>目錄 第{page_no}页</title></head><body><main>
<ul class="chapter-list">
{rows}
</ul>
<div class="index-container">
   <span class="index-container-btn disabled-btn">上一页</span>{nxt}
  </div>
</main></body></html>"""

def toc_querysel(book_id, options, ch_count, ch_cid_base):
    opts = "\n".join(
        f'<option value="/search/{o}?searchkey=x">第{o}页</option>' for o in options)
    rows = "\n".join(
        f'   <li><a href="/read/{book_id}/{ch_cid_base + i}">第{i + 1}章 查詢章節{i + 1}</a></li>'
        for i in range(ch_count))
    return f"""<!doctype html><html lang="zh"><head><base href="https://69shuba.tw/indexlist/{book_id}/">
<meta charset="UTF-8"><title>目錄</title></head><body><main>
<ul class="chapter-list">
{rows}
</ul>
<div class="index-container">
   <span class="index-container-btn disabled-btn">上一页</span><select id="indexselect">{opts}</select><span class="index-container-btn disabled-btn">下一页</span>
  </div>
</main></body></html>"""

def main():
    os.makedirs(OUT, exist_ok=True)
    # ── walk universe: ch1..ch10, cids 890315..890324 ────────────────────
    for n in range(1, 11):
        cid = 890314 + n
        nxt = f"/read/342441/{cid + 1}" if n < 10 else "/book/342441/"
        open(f"{OUT}/walk_ch{n}.html", "w", encoding="utf-8").write(
            chapter_page(n, cid, nxt))

    # ── seed book pages ──────────────────────────────────────────────────
    ch = lambda n: (890314 + n, f"第{n}章 測試章節{n}")
    open(f"{OUT}/book_mini.html", "w", encoding="utf-8").write(
        seed_book([ch(5), ch(4)], 890315))
    open(f"{OUT}/book_grow_adj.html", "w", encoding="utf-8").write(
        seed_book([ch(7), ch(6)], 890315))
    open(f"{OUT}/book_grow_gap.html", "w", encoding="utf-8").write(
        seed_book([ch(10), ch(9)], 890315))
    open(f"{OUT}/book_noseed.html", "w", encoding="utf-8").write(
        seed_book([], None))
    open(f"{OUT}/book_nostart.html", "w", encoding="utf-8").write(
        seed_book([ch(5), ch(4)], None))

    # ── window TOC: book 777001, 15 pages × 30, cids 6000001+ ────────────
    for p in (1, 10, 15):
        options = {1: list(range(1, 11)), 10: list(range(6, 16)), 15: list(range(11, 16))}[p]
        nxt = {1: 2, 10: 11, 15: None}[p]
        open(f"{OUT}/toc_win_p{p}.html", "w", encoding="utf-8").write(
            toc_page(777001, p, options, nxt, (p - 1) * 30 + 1, p * 30, 6000000 + (p - 1) * 30))

    # ── no-select TOC: book 777002, 2 pages × 5, cids 6100001+ ───────────
    for p, nxt in ((1, 2), (2, None)):
        open(f"{OUT}/toc_noselect_p{p}.html", "w", encoding="utf-8").write(
            toc_noselect(777002, p, nxt, (p - 1) * 5 + 1, p * 5, 6100000 + (p - 1) * 5))

    # ── query-select TOC: book 777003, 7 options, no next, 10 chapters ──
    open(f"{OUT}/toc_querysel_p1.html", "w", encoding="utf-8").write(
        toc_querysel(777003, list(range(1, 8)), 10, 6200000))

    print("fixtures written:")
    for f in sorted(os.listdir(OUT)):
        if any(k in f for k in ("walk_", "book_mini", "book_grow", "book_noseed",
                                "toc_win", "toc_noselect", "toc_querysel")):
            print(" ", f, os.path.getsize(os.path.join(OUT, f)))

if __name__ == "__main__":
    main()
