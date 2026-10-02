#!/usr/bin/env python3
"""v1.2.0 TOC fixtures for 69shubaTw — family-accurate markup.

Modeled on the LIVE wcshuba.com /chapterlist/ captures (the same CMS
generation as 69shuba.tw's /indexlist/, NOT WAF'd there — see
research/69shubatw/wc_chapterlist.html) and the .tw list-pager markup
(quanben_fenlei_1.html):
  - h3  "…章節目錄【共N章】"          (total chapter count)
  - one or two <select id="indexselect[-top/-bottom]"> whose option VALUES
    are the page URLs (/indexlist/{id}/{N}/)
  - 上一页 <a> / disabled span, 下一页 <a class="index-container-btn">
  - <ul><li><a href="/read/{bid}/{cid}"> chapter list, rendered TWICE
    (the site duplicates the main list — same-URL dedupe applies)
  - 100 chapters per page (user-verified on the real /indexlist/342441/)

Fixture battery:
  toc2_p1..p5     book 342441, 450 ch @ 100/page, .tw-style single select,
                  numbered option values, heading 【共450章】
  toc2b_p1..p2    wcshuba-style: div.listpage, DUAL selects (-top/-bottom),
                  trailing-slash chapter hrefs
  toc2c_p1        book-id-option trap: page-1 option value "/indexlist/342441/"
                  (unnumbered) + options 2..5 numbered
  toc2d_p1,p15    10-option window book (1450 ch, 15 pages) — heading hint chase
  toc2e_p1        NO pager signals at all (blind page-2 probe → fail → tp=1)
  toc2f_p1,p2     NO pager signals, page 2 exists (blind probe → tp=2)
  toc2g_p1,p6soft 6-page select but the site soft-serves page-1 content for
                  /6/ (loop guard)
  toc2h_p1,p2     .html-suffixed pagination (/indexlist/{id}/{N}.html)
"""
import os

OUT = "/home/z/my-project/research/69shubatw/fixtures"

def chapters(bid, first_ch, count, first_cid, trailing=""):
    out = []
    for i in range(count):
        n = first_ch + i
        cid = first_cid + i
        out.append(
            f'<li><a href="/read/{bid}/{cid}{trailing}" title="第{n}章 測試章節{n}" rel="chapter">第{n}章 測試章節{n}</a></li>'
        )
    return "\n".join(out)

def options(bid, pages, page=1, suffix="/", labels=None, unnumbered_first=False):
    out = []
    for p in range(1, pages + 1):
        if p == 1 and unnumbered_first:
            val = f"/indexlist/{bid}/{suffix if suffix != '.html' else ''}"
            val = f"/indexlist/{bid}/"
        else:
            val = f"/indexlist/{bid}/{p}{suffix}"
        lab = labels(p) if labels else (f"第{p}页" if suffix != ".html" else f"{(p-1)*100+1} - {p*100}章")
        sel = " selected" if p == page else ""
        out.append(f'<option value="{val}"{sel}>{lab}</option>')
    return "\n".join(out)

def page(bid, page_no, total_pages, total_chapters, ch_html, opts_html,
         wrapper="index-container", sel_ids=("indexselect",),
         prev_disabled=False, prev_href=None, next_href=None,
         heading=True, ul_class="chapter-list"):
    prev = (f'<span class="index-container-btn disabled-btn">没有了</span>' if prev_disabled
            else f'<a class="index-container-btn" href="{prev_href}">上一页</a>')
    nxt = (f'<span class="index-container-btn disabled-btn">没有了</span>' if next_href is None
           else f'<a class="index-container-btn" href="{next_href}">下一页</a>')
    selects = "\n".join(
        f'<select id="{sid}" aria-label="頁面導航" onchange="self.location.href=options[selectedIndex].value">{opts_html}</select>'
        for sid in sel_ids)
    h3 = (f'<h3><a href="/book/{bid}/">大明：老四，帶咱一起修仙！</a>章節目錄【共{total_chapters}章】</h3>'
          if heading else '<h3><a href="/book/{bid}/">大明：老四，帶咱一起修仙！</a>章節目錄</h3>')
    return f"""<!doctype html>
<html lang="zh-Hant">
 <head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>大明：老四，帶咱一起修仙！章節目錄 第{page_no}页_69書吧</title>
 </head>
 <body>
<nav><a href="/">首頁</a> <a href="/bookcase/" rel="nofollow">書架</a> <a href="/book/{bid}/">返回書頁</a></nav>
{h3}
<div class="listpage">
 {prev}
 {selects}
 {nxt}
</div>
<ul class="{ul_class}">
{ch_html}
</ul>
<ul class="{ul_class}">
{ch_html}
</ul>
<div class="{wrapper}"></div>
<div id="foot" class="foot"><a href="/">69書吧</a> <a href="/DMCA.html">DMCA</a></div>
</body>
</html>
"""

def write(name, html):
    with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
        f.write(html)
    print(f"{name}: {len(html)} bytes")

# ── toc2: the primary .tw-style battery — book 342441, 450 ch, 5 pages ──────
BID = 342441
BASE_CID = 890314  # ch n → cid 890314+n  (ch1 = 890315, real value)
for p in range(1, 6):
    first = (p - 1) * 100 + 1
    cnt = 100 if p < 5 else 50
    ch = chapters(BID, first, cnt, BASE_CID + first)
    opts = options(BID, 5, page=p,
                   labels=lambda n: f"{(n-1)*100+1} - {min(n*100, 450)}章")
    write(f"toc2_p{p}.html", page(BID, p, 5, 450, ch, opts,
        wrapper="index-container", sel_ids=("indexselect",),
        prev_disabled=(p == 1), prev_href=f"/indexlist/{BID}/{p-1}/" if p > 1 else None,
        next_href=f"/indexlist/{BID}/{p+1}/" if p < 5 else None))

# ── toc2b: wcshuba-style — dual selects + trailing-slash hrefs (2 pages) ────
for p in range(1, 3):
    first = (p - 1) * 100 + 1
    cnt = 100 if p < 2 else 50
    ch = chapters(BID, first, cnt, BASE_CID + first, trailing="/")
    opts = options(BID, 5, page=p,
                   labels=lambda n: f"{(n-1)*100+1} - {min(n*100, 450)}章")
    write(f"toc2b_p{p}.html", page(BID, p, 5, 450, ch, opts,
        wrapper="listpage2", sel_ids=("indexselect-top", "indexselect-bottom"),
        prev_disabled=(p == 1), prev_href=f"/indexlist/{BID}/{p-1}/" if p > 1 else None,
        next_href=f"/indexlist/{BID}/{p+1}/" if p < 5 else None))

# ── toc2c: book-id-option trap (page-1 option value unnumbered) ──────────────
ch = chapters(BID, 1, 100, BASE_CID + 1)
opts = options(BID, 5, page=1, unnumbered_first=True,
               labels=lambda n: "章節目錄" if n == 1 else f"{(n-1)*100+1} - {min(n*100, 450)}章")
write("toc2c_p1.html", page(BID, 1, 5, 450, ch, opts,
    wrapper="index-container", sel_ids=("indexselect",),
    prev_disabled=True, next_href=f"/indexlist/{BID}/2/"))

# ── toc2d: 10-option window, 1450 chapters / 15 pages (book 777010) ─────────
WID = 777010
ch = chapters(WID, 1, 100, 5000000)
opts = options(WID, 10, page=1, labels=lambda n: f"第{n}页")
write("toc2d_p1.html", page(WID, 1, 10, 1450, ch, opts,
    wrapper="index-container", sel_ids=("indexselect",),
    prev_disabled=True, next_href=f"/indexlist/{WID}/2/"))
ch15 = chapters(WID, 1401, 50, 5000000 + 1400)
opts15 = options(WID, 15, page=15,
                 labels=lambda n: f"第{n}页")
write("toc2d_p15.html", page(WID, 15, 15, 1450, ch15, opts15,
    wrapper="index-container", sel_ids=("indexselect",),
    prev_href=f"/indexlist/{WID}/14/", next_href=None))

# ── toc2e: NO pager signals at all, single page (blind probe fails) ─────────
EID = 777011
ch = chapters(EID, 1, 100, 6000000)
write("toc2e_p1.html", page(EID, 1, 1, 100, ch, "", heading=False,
    wrapper="index-container", sel_ids=(), prev_disabled=True, next_href=None))

# ── toc2f: NO pager signals, but page 2 exists (blind probe finds it) ───────
FID = 777012
ch = chapters(FID, 1, 100, 6100000)
write("toc2f_p1.html", page(FID, 1, 2, 150, ch, "", heading=False,
    wrapper="index-container", sel_ids=(), prev_disabled=True, next_href=None))
ch2 = chapters(FID, 101, 50, 6100000 + 100)
write("toc2f_p2.html", page(FID, 2, 2, 150, ch2, "", heading=False,
    wrapper="index-container", sel_ids=(), prev_disabled=False,
    prev_href=f"/indexlist/{FID}/1/", next_href=None))

# ── toc2g: soft-serve trap — select says 6 pages, /6/ re-serves page 1 ──────
ch = chapters(BID, 1, 100, BASE_CID + 1)
opts = options(BID, 6, page=1, labels=lambda n: f"第{n}页")
write("toc2g_p1.html", page(BID, 1, 6, 550, ch, opts,
    wrapper="index-container", sel_ids=("indexselect",),
    prev_disabled=True, next_href=f"/indexlist/{BID}/2/"))
# the soft-serve: identical content to page 1
write("toc2g_p6soft.html", page(BID, 6, 6, 550, ch, opts,
    wrapper="index-container", sel_ids=("indexselect",),
    prev_href=f"/indexlist/{BID}/5/", next_href=None))

# ── toc2h: .html-suffixed pagination (wcshuba family URL shape) ─────────────
HID = 777014
ch = chapters(HID, 1, 100, 7000000)
opts = options(HID, 2, page=1, suffix=".html",
               labels=lambda n: f"{(n-1)*100+1} - {n*100}章")
write("toc2h_p1.html", page(HID, 1, 2, 200, ch, opts,
    wrapper="listpage", sel_ids=("indexselect",),
    prev_disabled=True, next_href=f"/indexlist/{HID}/2.html"))
ch2 = chapters(HID, 101, 100, 7000000 + 100)
opts2 = options(HID, 2, page=2, suffix=".html",
                labels=lambda n: f"{(n-1)*100+1} - {n*100}章")
write("toc2h_p2.html", page(HID, 2, 2, 200, ch2, opts2,
    wrapper="listpage", sel_ids=("indexselect",),
    prev_href=f"/indexlist/{HID}/1.html", next_href=None))

print("\nAll v1.2.0 TOC fixtures generated.")
