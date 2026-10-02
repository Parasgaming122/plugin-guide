#!/usr/bin/env python3
"""Clean the Google-Translate-proxy fixtures into faithful oop.tw fixtures:
- strip <font> wrappers and the GT iframe/widgets
- rewrite www-oop-tw.translate.goog URLs back to RELATIVE site paths
  (as the original site would serve), drop the injected <base>
- un-reverse the CJK paragraphs that Google's translation reversed
- synthesize the ?p=2 catalog page for the book fixture
"""
import re

SRC = "/home/z/my-project/research/newsites"
GT_PARAMS = r"\?_x_tr_sl=[^\"'\s>]*"


def clean(html_in):
    h = html_in
    # 1. strip translate font wrappers
    h = re.sub(r'<font[^>]*>', '', h)
    h = h.replace('</font>', '')
    # 2. remove GT scaffolding
    h = re.sub(r'<iframe[^>]*id="gt-nvframe"[\s\S]*?</iframe>', '', h)
    h = re.sub(r'<div id="goog-gt-tt"[\s\S]*$', '</body></html>', h)
    h = re.sub(r'<md-dialog[\s\S]*?</body>', '</body>', h)
    h = h.replace(' style="margin-top: 56px;"', '')
    h = h.replace('<base href="https://www.oop.tw/">', '')
    # 3. links: https://www-oop-tw.translate.goog{path}?_x_tr_... → {path}
    h = re.sub(r'https://www-oop-tw\.translate\.goog(' + GT_PARAMS + ')', '', h)
    h = re.sub(r'https://www-oop-tw\.translate\.goog', '', h)
    # javascript:void(0);?_x_tr_... → javascript:void(0);
    h = re.sub(r'javascript:void\(0\);' + GT_PARAMS, 'javascript:void(0);', h)
    # remaining stray params
    h = re.sub(GT_PARAMS, '', h)
    # 4. class="translated-ltr" artifacts
    h = h.replace(' class="translated-ltr"', '')
    return h


def unreverse_paragraphs(html_in):
    """Google's proxy reversed some CJK paragraphs (direction artifact):
    a paragraph whose text ENDS with '介簡'/'介简' or '：者作' is a reversed
    TXT-header line — reverse the text back."""
    def fix(m):
        text = m.group(2)
        if re.search(r'(介簡|介简|：者作|:者作)$', text.strip()):
            text = text[::-1]  # exact character reversal restores the original
        return m.group(1) + text + m.group(3)
    return re.sub(r'(<p[^>]*>)([\s\S]*?)(</p>)', fix, html_in)


def main():
    for name in ["oop_sort_gt", "oop_book_gt", "oop_chapter_gt", "oop_search_gt"]:
        raw = open(f"{SRC}/{name}.html", encoding="utf-8").read()
        out = clean(raw)
        if name == "oop_chapter_gt":
            out = unreverse_paragraphs(out)
        out_name = name.replace("_gt", "")
        with open(f"{SRC}/{out_name}.html", "w", encoding="utf-8") as f:
            f.write(out)
        print(f"{out_name}.html: {len(out)} chars")

    # synthesize catalog page 2 (chapters 031-044) for the book fixture
    # real chapter ids seen on the book page (latest-12 list):
    ids = {
        "044": "a1165206a", "043": "a1165204a", "042": "a1165201a",
        "041": "a1165199a", "040": "a1165196a", "039": "a1165193a",
        "038": "a1165191a", "037": "a1165188a", "036": "a1165181a",
        "035": "a1165179a", "034": "a1165176a", "033": "a1165172a",
        "032": "a1165170a", "031": "a1165168a",  # 031/032 plausible ids
    }
    lis = "".join(
        f'<li class="chapter-item"><a href="/areada/a3292752a/{ids[n]}.html" '
        f'title="等你到三十歲末{n}">{n}</a></li>'
        for n in sorted(ids)
    )
    page2 = f"""<!DOCTYPE html><html><head><meta charset="UTF-8"><title>等你到三十歲末-短篇小說</title></head>
<body>
<div id="catalog-content" class="content-section">
 <div class="chapter-list">
  <h2 class="chapter-title">《等你到三十歲末》完整目錄</h2>
  <div class="chap-pager"><span class="cp-btn">‹</span>
   <select class="cp-select" onchange="location.href='/abooka/a3292752a/?p='+this.value">
    <option value="1">第1～30章</option><option value="2" selected>第31～44章</option>
   </select> <span class="cp-btn cp-disabled">›</span>
  </div>
  <ul class="chapter-grid" id="ul_all_chapters">{lis}</ul>
 </div>
</div>
</body></html>
"""
    with open(f"{SRC}/oop_book_p2.html", "w", encoding="utf-8") as f:
        f.write(page2)
    print(f"oop_book_p2.html: {len(page2)} chars (14 chapters 031-044)")


if __name__ == "__main__":
    main()
