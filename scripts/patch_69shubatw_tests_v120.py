#!/usr/bin/env python3
"""Patch S69TwTest.java for 69shubaTw v1.2.0:
   - header + T0 version 1.2.0
   - http_get_batch mock (sequential over the same rule engine) + tracking
   - NEW test battery T13n..T13u (real 100/page TOC, batch prefetch, pager
     variants, soft-serve guard, URL-shape canonicalization)
"""
import re

PATH = "/home/z/my-project/download/test-harness/S69TwTest.java"
src = open(PATH, encoding="utf-8").read()
orig = src

# ── 1. header + version ──────────────────────────────────────────────────────
src = src.replace("S69TwTest — mock harness for 69shubaTw.lua v1.1.0.",
                  "S69TwTest — mock harness for 69shubaTw.lua v1.2.0.")
src = src.replace('check("1.1.0".equals(globals.get("version").tojstring()), "version = 1.1.0");',
                  'check("1.2.0".equals(globals.get("version").tojstring()), "version = 1.2.0");')

# ── 2. http_get_batch mock + tracking ────────────────────────────────────────
src = src.replace(
    """    static boolean blockTranslate = false;""",
    """    static boolean blockTranslate = false;
    static int batchCalls = 0;
    static final List<String> batchUrls = new ArrayList<>();""")

src = src.replace(
    """        g.set("http_post", new ThreeArgFunction() {""",
    """        g.set("http_get_batch", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2) {
                LuaTable urlsT = a1.checktable();
                batchCalls++;
                LuaTable out = new LuaTable();
                int n = urlsT.length();
                for (int i = 1; i <= n; i++) {
                    String url = urlsT.get(i).checkjstring();
                    batchUrls.add(url);
                    out.set(i, responseTable(http("GET", url, null, new LinkedHashMap<>())));
                }
                return out;
            }
        });
        g.set("http_post", new ThreeArgFunction() {""")

src = src.replace(
    """    static void resetMockState() {
        urlHitCount.clear(); fetchedUrls.clear(); showErrorCalls.clear();
        lastGetUrl = null; lastSearchUrl = null;
    }""",
    """    static void resetMockState() {
        urlHitCount.clear(); fetchedUrls.clear(); showErrorCalls.clear();
        lastGetUrl = null; lastSearchUrl = null;
        batchCalls = 0; batchUrls.clear();
    }""")

# ── 3. new test battery — inserted before the summary ───────────────────────
NEW_TESTS = r'''
        // ════════ T13n REAL TOC — family-accurate 100/page, batch prefetch ════════
        section("T13n REAL TOC — .tw-style 5 pages x 100ch, parallel batch");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        for (int p = 1; p <= 5; p++) mock("/indexlist/342441/" + p + "/", "toc2_p" + p + ".html");
        mock("/indexlist/342441/", "toc2_p1.html");
        resetMockState();
        LuaValue ppR1 = parsePageRaw(BOOK_URL, 1);
        check(ppR1.istable(), "parsePage(1) table");
        LuaTable ppR1T = ppR1.checktable();
        LuaTable r1ch = ppR1T.get("chapters").checktable();
        check(r1ch.len().toint() == 100, "page 1 = 100 chapters (100/page, family-verified): " + r1ch.len().toint());
        check(ppR1T.get("totalPages").toint() == 5, "totalPages = 5 (select + 【共450章】): " + ppR1T.get("totalPages").toint());
        check("第1章 測試章節1".equals(r1ch.get(1).checktable().get("title").tojstring()), "page 1 starts at 第1章");
        check("https://69shuba.tw/read/342441/890315".equals(r1ch.get(1).checktable().get("url").tojstring()),
            "canonical chapter URL (no trailing slash)");
        check(batchCalls >= 1, "pages 2..5 prefetched via ONE http_get_batch (calls: " + batchCalls + ")");
        check(batchUrls.size() == 4, "batch carried exactly 4 page URLs: " + batchUrls.size());
        // the engine's walk: pages 2..4 interior-cached (zero network), 5 via page cache
        long netAfterP1 = fetchedUrls.stream().filter(u -> u.contains("/indexlist/")).count();
        LuaTable r2 = parsePageRaw(BOOK_URL, 2).checktable().get("chapters").checktable();
        check(r2.len().toint() == 100 && r2.get(1).checktable().get("title").tojstring().contains("第101章"),
            "page 2 = chapters 101..200 from the batch cache");
        LuaTable r5 = parsePageRaw(BOOK_URL, 5).checktable().get("chapters").checktable();
        check(r5.len().toint() == 50 && r5.get(50).checktable().get("title").tojstring().contains("第450章"),
            "page 5 = last 50 chapters (401..450)");
        long netAfterWalk = fetchedUrls.stream().filter(u -> u.contains("/indexlist/")).count();
        check(netAfterWalk == netAfterP1, "the whole 450-chapter TOC cost 5 fetches + 1 batch, ZERO extra: "
            + netAfterP1 + " -> " + netAfterWalk);

        // full legacy walk
        reloadPlugin();
        clearTocPrefs();
        resetMockState();
        LuaTable tocFull = callStr("getChapterList", BOOK_URL);
        check(tocFull.len().toint() == 450, "getChapterList = all 450 chapters: " + tocFull.len().toint());
        HashSet<String> uniq = new HashSet<>();
        boolean allUniq = true, asc = true; long prevCid = 0;
        for (int i = 1; i <= tocFull.len().toint(); i++) {
            LuaTable c = tocFull.get(i).checktable();
            if (!uniq.add(c.get("url").tojstring())) allUniq = false;
            long cid = Long.parseLong(c.get("url").tojstring().replaceAll(".*/", ""));
            if (cid <= prevCid) asc = false;
            prevCid = cid;
        }
        check(allUniq, "450 unique chapter URLs (duplicated list markup deduped)");
        check(asc, "cid-ascending reading order");
        check(tocFull.get(450).checktable().get("title").tojstring().contains("第450章"), "ends at 第450章");

        // engine double-call: parsePage(1) again — pure cache replay
        resetMockState();
        LuaTable again1 = parsePageRaw(BOOK_URL, 1).checktable().get("chapters").checktable();
        check(again1.len().toint() == 100, "second parsePage(1) replay: 100 chapters");
        check(batchUrls.isEmpty() && fetchedUrls.stream().noneMatch(u -> u.contains("/indexlist/")),
            "double call: ZERO network, ZERO batch");

        // ════════ T13o wcshuba-style variant — dual selects, trailing slashes ════════
        section("T13o REAL TOC — wcshuba-style (indexselect-top/-bottom, trailing-slash hrefs)");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        mock("/indexlist/342441/2/", "toc2b_p2.html");
        mock("/indexlist/342441/", "toc2b_p1.html");
        resetMockState();
        LuaValue ppWc = parsePageRaw(BOOK_URL, 1);
        check(ppWc.istable(), "wcshuba-style parsePage(1)");
        LuaTable wcT = ppWc.checktable();
        check(wcT.get("totalPages").toint() == 5,
            "dual selects (indexselect-top + -bottom) both enumerated: " + wcT.get("totalPages").toint());
        LuaTable wcCh = wcT.get("chapters").checktable();
        check(wcCh.len().toint() == 100, "100 chapters from the duplicated trailing-slash list: " + wcCh.len().toint());
        check("https://69shuba.tw/read/342441/890315".equals(wcCh.get(1).checktable().get("url").tojstring()),
            "trailing-slash href canonicalized to no-slash URL");
        LuaValue ppWc2 = parsePageRaw(BOOK_URL, 2);
        check(ppWc2.istable() && ppWc2.checktable().get("chapters").checktable().len().toint() == 50,
            "page 2 (50 ch) served from the batch cache");

        // ════════ T13p book-id-option trap — page-1 option value unnumbered ════════
        section("T13p REAL TOC — unnumbered page-1 option must not inflate totalPages");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        for (int p = 2; p <= 5; p++) mock("/indexlist/342441/" + p + "/", "toc2_p" + p + ".html");
        mock("/indexlist/342441/", "toc2c_p1.html");
        resetMockState();
        LuaValue ppTrap = parsePageRaw(BOOK_URL, 1);
        check(ppTrap.istable(), "trap parsePage(1)");
        check(ppTrap.checktable().get("totalPages").toint() == 5,
            "option '/indexlist/342441/' rejected — totalPages 5, not 342441: "
                + ppTrap.checktable().get("totalPages").toint());

        // ════════ T13q window + 【共N章】 heading chase ════════
        section("T13q REAL TOC — 10-option window + heading hint jumps to page 15");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        String wUrl = "https://69shuba.tw/book/777010/";
        mock("/indexlist/777010/15", "toc2d_p15.html");
        mock("/indexlist/777010/", "toc2d_p1.html");
        resetMockState();
        LuaValue ppW = parsePageRaw(wUrl, 1);
        check(ppW.istable(), "window parsePage(1)");
        check(ppW.checktable().get("totalPages").toint() == 15,
            "select says 10, heading 共1450章 → chase lands on 15: "
                + ppW.checktable().get("totalPages").toint());
        check(fetchedCount("/indexlist/777010/15") == 1, "the heading hint probed page 15 directly (1 fetch)");
        check(fetchedCount("/indexlist/777010/10") == 0, "no wasted probe of page 10");

        // ════════ T13r soft-serve loop guard ════════
        section("T13r REAL TOC — soft-served page 6 never pollutes the TOC");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        for (int p = 2; p <= 5; p++) mock("/indexlist/342441/" + p + "/", "toc2_p" + p + ".html");
        mock("/indexlist/342441/6/", "toc2g_p6soft.html");
        mock("/indexlist/342441/", "toc2g_p1.html");
        resetMockState();
        LuaTable tocSoft = callStr("getChapterList", BOOK_URL);
        HashSet<String> su = new HashSet<>();
        boolean sUniq = true;
        for (int i = 1; i <= tocSoft.len().toint(); i++)
            if (!su.add(tocSoft.get(i).checktable().get("url").tojstring())) sUniq = false;
        check(tocSoft.len().toint() == 500 && sUniq,
            "select over-reports 6 pages, /6/ re-serves page 1 → walk stops clean at 500 unique: "
                + tocSoft.len().toint());

        // ════════ T13s blind page-2 probe (no pager signals at all) ════════
        section("T13s REAL TOC — no select/heading/next: blind probe decides");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        String eUrl = "https://69shuba.tw/book/777011/";
        mock("/indexlist/777011/", "toc2e_p1.html");
        resetMockState();
        LuaValue ppE = parsePageRaw(eUrl, 1);
        check(ppE.istable(), "signal-less parsePage(1)");
        check(ppE.checktable().get("totalPages").toint() == 1,
            "blind probe of page 2 fails → single-page book (tp=1): " + ppE.checktable().get("totalPages").toint());
        check(ppE.checktable().get("chapters").checktable().len().toint() == 100, "100 chapters intact");
        // and when page 2 exists with no signals of its own
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        String fUrl = "https://69shuba.tw/book/777012/";
        mock("/indexlist/777012/2", "toc2f_p2.html");
        mock("/indexlist/777012/", "toc2f_p1.html");
        resetMockState();
        LuaValue ppF = parsePageRaw(fUrl, 1);
        check(ppF.checktable().get("totalPages").toint() == 2,
            "blind probe finds the signal-less page 2 (tp=2): " + ppF.checktable().get("totalPages").toint());

        // ════════ T13t .html-suffixed pagination (wcshuba URL shape) ════════
        section("T13t REAL TOC — .html-suffixed page URLs");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        String hUrl = "https://69shuba.tw/book/777014/";
        mock("/indexlist/777014/2.html", "toc2h_p2.html");
        mock("/indexlist/777014/", "toc2h_p1.html");
        resetMockState();
        LuaValue ppH = parsePageRaw(hUrl, 1);
        check(ppH.istable(), ".html pagination parsePage(1)");
        check(ppH.checktable().get("totalPages").toint() == 2, "totalPages = 2 from .html options");
        LuaValue ppH2 = parsePageRaw(hUrl, 2);
        check(ppH2.istable() && ppH2.checktable().get("chapters").checktable().len().toint() == 100,
            "page 2 fetched via its .html option value (batch) and served");

        // ════════ T13u URL-shape canonicalization ════════
        section("T13u book URLs — /indexlist/{id}/ and /read/{bid}/{cid} shapes");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        for (int p = 1; p <= 5; p++) mock("/indexlist/342441/" + p + "/", "toc2_p" + p + ".html");
        mock("/indexlist/342441/", "toc2_p1.html");
        mock("/book/342441", "book_342441.html");
        resetMockState();
        // /indexlist/ shape as the stored book URL
        LuaValue ppI = parsePageRaw("https://69shuba.tw/indexlist/342441/", 1);
        check(ppI.istable() && ppI.checktable().get("chapters").checktable().len().toint() == 100
            && ppI.checktable().get("totalPages").toint() == 5,
            "book added via /indexlist/342441/ — full TOC works");
        String titleFromIndexlist = g("getBookTitle", "https://69shuba.tw/indexlist/342441/");
        check(titleFromIndexlist != null && titleFromIndexlist.contains("大明"),
            "getBookTitle fetches the CANONICAL /book/ page: " + titleFromIndexlist);
        check(fetchedContains("/book/342441/"), "the /book/342441/ page was fetched for details");
        // /read/ shape
        String titleFromRead = g("getBookTitle", "https://69shuba.tw/read/342441/890315");
        check(titleFromRead != null && titleFromRead.contains("大明"),
            "book added via a chapter link — details still work: " + titleFromRead);
        // shared TOC cache across shapes (same pref key s69tw_toc_342441)
        resetMockState();
        mockClear(); // no rules: everything must come from the persistent cache
        LuaValue ppShared = parsePageRaw(BOOK_URL, 2);
        check(ppShared.istable() && ppShared.checktable().get("chapters").checktable().len().toint() == 100,
            "TOC cache keyed by BOOK ID — /book/ URL serves what /indexlist/ URL cached, zero network");
        check(fetchedUrls.isEmpty(), "zero network across URL shapes: " + fetchedUrls.size());
'''

src = src.replace(
    """        // ════════ summary ════════""",
    NEW_TESTS + """
        // ════════ summary ════════""")

open(PATH, "w", encoding="utf-8").write(src)
print("patched:", PATH)
print("changed:", len(src) != len(orig), "| new size:", len(src))
