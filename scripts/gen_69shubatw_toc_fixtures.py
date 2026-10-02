#!/usr/bin/env python3
"""Synthesize 69shuba.tw TOC fixtures (the /indexlist/ path is WAF-challenged
from every research route, so the TOC markup cannot be captured — fixtures
follow the site's established pager/card patterns). Two layout variants test
the parser's anchor-catch-all strategy:
  toc_a_p1/p2.html   ul-list layout, 2 pages × 30 chapters (cid ascending,
                     duplicate-title repost pair, foreign-book /read/ links
                     that must be filtered, pager with indexselect)
  toc_b_single.html  table layout, single page, DOM order shuffled (cid sort)
  toc_c_captcha.html the real EdgeOne challenge page (failure path)
  chapter_split_1/2.html  "(1 / 2)" chapter + sub-page 2 at /read/{bid}/{cid}/{n}
"""
import re, os

OUT = "/home/z/my-project/research/69shubatw/fixtures"
os.makedirs(OUT, exist_ok=True)

BOOK = 342441

def page_shell(title, body, base=""):
    return f"""<!doctype html>
<html lang="zh">
 <head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{title}</title>
  <style>.nr_title {{ font-size:16px; text-align:center; }} #nr1 p {{ text-indent:2rem; }}</style>
 </head>
 <body>
{body}
 </body>
</html>
"""

def pager(cur, total):
    opts = []
    for n in range(1, total + 1):
        sel = " selected" if n == cur else ""
        opts.append(f'<option{sel} value="/indexlist/{BOOK}/{n}/">第{n}页</option>')
    prev = ('<span class="index-container-btn disabled-btn">上一页</span>' if cur == 1
            else f'<a class="index-container-btn" href="/indexlist/{BOOK}/{cur-1}/">上一页</a>')
    nxt = ('<span class="index-container-btn disabled-btn">下一页</span>' if cur == total
           else f'<a class="index-container-btn" href="/indexlist/{BOOK}/{cur+1}/">下一页</a>')
    return (f'<div class="index-container">{prev}'
            f'<select id="indexselect" aria-label="頁面導航" '
            f'onchange="self.location.href=options[selectedIndex].value">'
            f'{"".join(opts)}</select>{nxt}</div>')

def ch(cid, title):
    return f'<li><a href="/read/{BOOK}/{cid}">{title}</a></li>'

def toc_a():
    # 90 chapters across 3 pages; cids ascending; repost pair at the end
    pages = [[], [], []]
    cid = 890315
    for i in range(1, 89):
        pages[(i - 1) // 30].append(ch(cid, f"第{i}章 測試章節{i}"))
        cid += 1
    # repost pair on the last page (site-verified duplicate-title pattern)
    pages[2].append(ch(cid, f"第57章 釣魚執法，火力即真理！"))
    pages[2].append(ch(cid + 1, f"第58章 老怪甦醒，大明的星門計劃"))
    # foreign-book read links that MUST be filtered out (same-book filter)
    foreign = ('<div class="tuijian"><a href="/read/337296/12345">推薦：大明：寒門輔臣最新章</a>'
               '<a href="/read/400577/99999">推薦：邊關第一悍刀最新章</a></div>')
    nav = ('<nav><a href="/">首頁</a> <a href="/bookcase/" rel="nofollow">書架</a> '
           f'<a href="/book/{BOOK}/">返回書頁</a></nav>')
    for idx, chs in enumerate(pages, start=1):
        p = page_shell(f"大明：老四，帶咱一起修仙！章節目錄 第{idx}页_69書吧",
            f'{nav}<h1 class="book-itemtitle">章節目錄</h1>'
            f'<ul class="mulu">{"".join(chs)}</ul>{pager(idx, 3)}{foreign}')
        open(f"{OUT}/toc_a_p{idx}.html", "w", encoding="utf-8").write(p)

def toc_b():
    # table layout, single page, shuffled DOM order → cid sort must fix
    # (uses its own book id 335001 — different from variant A)
    chs = []
    for i in range(1, 16):
        cid = 890314 + i
        chs.append((cid, f"第{i}章 表格章節{i}"))
    chs.reverse()  # newest-first DOM order (some 69shuba TOCs do this)
    rows = "".join(
        f'<tr><td><a href="/read/335001/{c}">{t}</a></td></tr>' for c, t in chs)
    open(f"{OUT}/toc_b_single.html", "w", encoding="utf-8").write(page_shell(
        "短篇書目錄_69書吧",
        f'<h1 class="book-itemtitle">章節目錄</h1>'
        f'<table class="list-item">{rows}</table>'))

def toc_c():
    # the REAL EdgeOne challenge page (6865 bytes, fetched direct)
    src = "/home/z/my-project/research/69shubatw/home.html"
    raw = open(src, encoding="utf-8").read()
    open(f"{OUT}/toc_c_captcha.html", "w", encoding="utf-8").write(raw)

def chapter_split():
    # "(1 / 2)" chapter + sub-page 2 — tests the defensive sub-page fetch
    p1_paras = "".join(f"<p>第一部分第{k}段。這是分頁章節的前半內容，用於驗證外掛能把第二頁接上。</p>"
                       for k in range(1, 9))
    p2_paras = "".join(f"<p>第二部分第{k}段。後半內容出現在子頁面，必須被拼接進來。</p>"
                       for k in range(1, 7))
    p1 = page_shell("大明：老四，帶咱一起修仙！_第100章 分頁測試(1 / 2)_69書吧",
        f'<h1 class="nr_title" id="nr_title">第100章 分頁測試(1 / 2)</h1>'
        f'<nav class="nr_page"><table><tbody><tr>'
        f'<td class="prev"><a id="pb_prev" href="/read/{BOOK}/890414">上一章</a></td>'
        f'<td class="mulu"><a id="pb_mulu" href="/indexlist/{BOOK}/">目錄</a></td>'
        f'<td class="next"><a id="pb_next" href="/read/{BOOK}/890415/2">下一页</a></td>'
        f'</tr></tbody></table></nav>'
        f'<div class="txtnav"><div class="nr_nr"><div id="nr1">{p1_paras}'
        f'<div class="reader-ad"><script>loadAdv(1, 2);</script></div></div></div></div>')
    p2 = page_shell("大明：老四，帶咱一起修仙！_第100章 分頁測試(2 / 2)_69書吧",
        f'<h1 class="nr_title" id="nr_title">第100章 分頁測試(2 / 2)</h1>'
        f'<div class="txtnav"><div class="nr_nr"><div id="nr1">{p2_paras}</div></div></div>')
    open(f"{OUT}/chapter_split_1.html", "w", encoding="utf-8").write(p1)
    open(f"{OUT}/chapter_split_2.html", "w", encoding="utf-8").write(p2)

def chapter_watermark():
    # real chapter 1 + injected watermark paragraphs
    raw = open(f"{OUT}/chapter_1.html", encoding="utf-8").read()
    wm = ('<p>69書吧（www.69shuba.tw）永久免費閱讀最新章節！</p>'
          '<p>請記住本站域名：69shuba.tw</p>'
          '<p>(本章完)</p>')
    raw = raw.replace("</div>\n</div>\n", wm + "</div>\n</div>\n", 1)  # best-effort
    # append before the last closing of nr1: insert after the LAST </p> in nr1
    i = raw.rfind("</p>", 0, raw.find('class="reader-ad"'))
    if i > 0:
        j = i + 4
        raw = raw[:j] + wm + raw[j:]
    open(f"{OUT}/chapter_wm.html", "w", encoding="utf-8").write(raw)

def empty_search():
    # zero-result search page (for the zh-CN retry test)
    p = page_shell("檢索《測試》的結果-69書吧",
        '<div class="page-head"><h1>檢索《測試》的結果</h1></div>'
        '<div class="s_m"><p>沒有找到相關小說</p></div>'
        '<div class="index-container">'
        '<span class="index-container-btn disabled-btn">上一页</span>'
        '<span class="index-container-btn disabled-btn">下一页</span></div>')
    open(f"{OUT}/search_empty.html", "w", encoding="utf-8").write(p)

if __name__ == "__main__":
    toc_a(); toc_b(); toc_c(); chapter_split(); chapter_watermark(); empty_search()
    for f in sorted(os.listdir(OUT)):
        print(f"  {f:28s} {os.path.getsize(os.path.join(OUT, f)):>7d} bytes")
