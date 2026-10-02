#!/usr/bin/env python3
"""Add the 69shubaTw column to MAINTENANCE.md's quick-reference card and
append Part 0.9 + gotchas #54-#56."""
import re

P = "/home/z/my-project/download/MAINTENANCE.md"
src = open(P, encoding="utf-8").read()

# ── 1. Quick-reference card: append a 6th cell to each table row ──────────
NEW_CELLS = {
    "| WTR-Lab | Novel543 | WuxiaBox | Bixiange | OOP": " 69書吧 tw |",
    "mtl/wtrlab.lua": " `69shubaTw.lua` (1,368 lines, NEW 2026-09-20) |",
    "poster fix on 1.2.0": " **1.0.0 (2026-09-20)** — initial release (EdgeOne trigger_markers, layout-agnostic TOC, translator, direct covers) |",
    "https://www.oop.tw/ (R18 wing": " https://69shuba.tw/ (NOT the `shuba69` plugin's 69shuba.com — different DB/encoding/URLs) |",
    "zh-TW + built-in Translator mode (queries → zh-TW) |": " zh-TW (UTF-8) + built-in Translator mode (queries → zh-TW, zh-CN retry) |",
    "article#article <p> only (ad DIVs inside skipped); ch1 TXT header kept-if-only-content |":
        " HTML `div#nr1` <p> only (`.reader-ad` between paragraphs skipped); `(cur / total)` sub-page fetch `/read/{bid}/{cid}/{n}` |",
    "wsrv.nl proxy default** (1.0.0; nocover.jpg passthrough) |":
        " **DIRECT from p.69shuba.tw** (open CDN, no proxy; deterministic `p.69shuba.tw/{id÷1000}/{id}/{id}s.jpg`) |",
    "test-harness/OopTest.java (**97 mock**":
        " `test-harness/S69TwTest.java` (**101 mock**, cleaned proxy fixtures + synthesized 2-layout TOC battery + per-target translator mocks) |",
    "/home/z/my-project/download/oop.lua |": " `/home/z/my-project/download/69shubaTw.lua` |",
    "CF managed challenge on EVERYTHING from datacenter**; WebView bypass kept enabled; wsrv.nl covers |":
        " **Tencent EdgeOne aegis captcha (NOT CF)** — `cf_options.trigger_markers` route it into the same WebView ladder; `/indexlist/*` is the WAF-hard path |",
}

lines = src.split("\n")
out = []
in_card = False
patched = 0
for i, ln in enumerate(lines):
    if ln.startswith("| | WTR-Lab |"):
        in_card = True
        out.append(ln.replace("| OOP 小說網 |", "| OOP 小說網 | 69書吧 tw |"))
        continue
    if in_card:
        if ln.startswith("|---"):
            out.append("|---|---|---|---|---|---|---|")
            continue
        if ln.startswith("|"):
            cell = None
            for anchor, newcell in NEW_CELLS.items():
                if anchor in ln:
                    cell = newcell
                    break
            if cell is None:
                print(f"WARN: no cell for row: {ln[:70]}")
                out.append(ln)
            else:
                out.append(ln.rstrip()[:-1].rstrip() + " " + cell)
                patched += 1
            continue
        else:
            in_card = False
    out.append(ln)
src = "\n".join(out)
print(f"card rows patched: {patched}")

# ── 2. Part 0.9 quick map ──────────────────────────────────────────────────
PART09 = """
## Part 0.9 — 69shubaTw plugin (`69shubaTw.lua` v1.0.0) — quick map (2026-09-20)

**Site:** https://69shuba.tw/ — 69書巴, the Traditional-Chinese portal of the 69shuba
family. NOT the `shuba69` plugin's www.69shuba.com (Simplified/GBK/`/book/{id}.htm`
/ different DB — book 342441 exists on .tw, 404s on .com).

- **Anti-bot:** Tencent **EdgeOne aegis captcha** (`Server: Edge/1.1.28`,
  reCAPTCHA-v3 checkbox + Turnstile, token → `/aegis_captcha_verify?rule_uuid=…`,
  cookies `__ct_ac_cpg`+`__ct_cya_ckt` after solving). The stock CF detector
  can't see it → the plugin registers **`cf_options.trigger_markers`**
  (`aegis_captcha_verify`, `recaptcha-v3-container`,
  `Please complete human verification`) so the interceptor's WebView ladder
  handles it (solve checkbox once → cookies carry to the retry). WAF is
  path-asymmetric: `/indexlist/*` (the catalog) is challenged even via the
  Google-Translate proxy, while `/`, `/book/*`, `/read/*`, `/search/*`,
  `/fenlei/*`, `/quanben/*` pass.
- **Covers:** open CDN `p.69shuba.tw` — DIRECT, no wsrv.nl (user requirement;
  the CDN simply isn't WAF'd). Deterministic
  `https://p.69shuba.tw/{floor(id/1000)}/{id}/{id}s.jpg` → synthesized when
  the book page is unreachable.
- **URLs:** book `/book/{id}/`, TOC `/indexlist/{id}/[N/]`, chapter
  `/read/{bid}/{cid}`, category `/fenlei/{slug}/{N}/`, all-novels ranking
  `/quanben/fenlei/{N}/`, search `/search/?searchkey={q}&searchtype=all` (p1)
  and `/search/{N}?searchkey={q}` (pN). All 1-based. UTF-8, mixed-script
  (titles zh-TW, nav/pager literals Simplified, synopses sometimes zh-CN).
- **TOC parser is layout-agnostic** (the `/indexlist/` markup was
  uncapturable — every research route WAF'd): scans ALL anchors matching
  `/read/{bookId}/{cid}`, dedupes + sorts by cid (cid == reading order,
  verified ch1 890315 → ch2 890316 → … → ch450 4001259); the page-N URL
  template is learned from page 1's 下一页 link and persisted in the TOC
  cache entry (`"1|totalPages|urlBase|pages…"` format).
- **Solver-safe walks:** parsePage + early-abort getChapterList + persistent
  interior-page cache + cross-page dedupe (all the oop v1.1.0 patterns).
- **Chapter text:** `div#nr1` <p> only (`.reader-ad` ad divs sit BETWEEN the
  paragraphs inside the content div); `(cur / total)` title suffix drives the
  defensive sub-page fetch `/read/{bid}/{cid}/{n}`; domain watermarks +
  (本章完) stripped; never returns empty.
- **Translator:** novel543 core, source `zh-TW`; search queries → zh-TW with
  a zh-CN retry when the first finds nothing (site titles are mixed-script).
- **Tests:** `test-harness/S69TwTest.java` — **101/101 mock** (fixtures:
  cleaned translate-proxy captures + synthesized TOC layout variants ×2 +
  captcha + split-chapter + watermark + empty-search).
"""

anchor = "## Part 1 — WTR-Lab Plugin"
idx = src.find(anchor)
assert idx > 0
src = src[:idx] + PART09.strip() + "\n\n" + src[idx:]
print("Part 0.9 inserted")

# ── 3. Gotchas #54-#56 ─────────────────────────────────────────────────────
end_idx = src.find("*(assembled 2026-09-19")
if end_idx < 0:
    end_idx = len(src)
GOTCHAS = """
**#54 — non-Cloudflare WAFs are INVISIBLE to the engine's CF detector**
(69shubaTw): `isNotCloudflare` requires a cloudflare/ddos-guard `Server`
header (or `cf-mitigated: challenge`), so Tencent EdgeOne / other custom
captcha walls pass straight through to the plugin as {success=false} 403s.
`cf_options = { trigger_markers = { … } }` (LuaSourceAdapter →
LuaCfOptionsRegistry) makes the interceptor treat ANY body containing a
marker as a challenge on ANY status code → the WebView ladder runs, and the
post-solve retry carries ALL WebView cookies (not just cf_clearance). Pick
markers unique to the challenge page (the verify endpoint path, the widget
class, the page title) — never anything that can appear on real pages.

**#55 — WAF rules can be path-asymmetric** (69shubaTw): probe MORE than the
homepage before concluding a site is (in)accessible — 69shuba.tw challenges
`/indexlist/*` even for the Google-Translate proxy while serving `/book/*`,
`/read/*`, `/search/*` happily. The practical consequence: a plugin's
chapter-catalog fetch is the surface most likely to need the one-time
WebView solve, and mock fixtures for that surface may be impossible to
capture (synthesize them + make the parser layout-agnostic instead).

**#56 — layout-agnostic TOC parsing when the catalog markup is unknown**
(69shubaTw): when a site's chapter list cannot be captured, don't guess
containers — scan every `<a>` for the site's chapter-URL shape
(`/read/{bookId}/{cid}`), filter by the SAME book id (kills recommendation
links), dedupe by the id and sort by it (global article ids follow reading
order on Jieqi-family sites — verify with ch1→ch2→latest samples first).
Cross-page dedupe by URL in the walk guards against a wrong page-N URL
soft-serving page 1 again.
"""
src = src[:end_idx].rstrip() + "\n" + GOTCHAS.strip() + "\n\n" + src[end_idx:].lstrip()
print("gotchas #54-#56 appended")

open(P, "w", encoding="utf-8").write(src)
print("saved", P)
