#!/usr/bin/env python3
"""OopTest.java — add the v1.1.0 TOC test battery (early-abort / parsePage /
persistent cache / stale serve / translate purity / LRU) and bump the
version check. Applied to BOTH harness copies (working + download sync).
"""
import sys

PATHS = [
    "/home/z/my-project/test-harness/OopTest.java",
    "/home/z/my-project/download/test-harness/OopTest.java",
]

HELPERS = """    static LuaTable callStr(String name, String a) {
        return globals.get(name).call(LuaValue.valueOf(a)).checktable();
    }
"""

NEW_HELPERS = """    static LuaValue parsePageRaw(String bookUrl, int page) {
        return globals.get("parsePage").call(
            LuaValue.valueOf(bookUrl), LuaValue.valueOf((double) page));
    }
    static int tocPrefNonEmpty(String id) {
        String v = prefs.getOrDefault("oop_toc_" + id, "");
        return v == null || v.isEmpty() ? 0 : 1;
    }
"""

T0_OLD = 'check(globals.get("version").tojstring().equals("1.0.0"), "version = 1.0.0");'
T0_NEW = 'check(globals.get("version").tojstring().equals("1.1.0"), "version = 1.1.0");'

REQUIRED_OLD = """check(!globals.get("getCatalogList").isnil()
           && !globals.get("getCatalogSearch").isnil()
           && !globals.get("getChapterText").isnil()
           && !globals.get("getChapterList").isnil()
           && !globals.get("getBookTitle").isnil(), "required functions present");"""
REQUIRED_NEW = """check(!globals.get("getCatalogList").isnil()
           && !globals.get("getCatalogSearch").isnil()
           && !globals.get("getChapterText").isnil()
           && !globals.get("getChapterList").isnil()
           && !globals.get("parsePage").isnil()
           && !globals.get("getBookTitle").isnil(), "required functions present (incl. parsePage)");"""

# Insert the new battery right after T6's last assertion.
T6_LAST = '        check(ordered, "chapters in ascending order 001→044");\n'

NEW_TESTS = '''
        section("T6b EARLY ABORT — the solver-storm fix (5-page book, p3 fails)");
        String genBook = "https://www.oop.tw/abooka/a9990001a/";
        freshPlugin();
        rules.clear(); resetMockState();
        Rule p3fail = new Rule();
        p3fail.urlContains = "a9990001a/?p=3"; p3fail.code = 403; p3fail.rawBody = "error code: 403";
        rules.add(p3fail);
        mock("a9990001a/?p=2", "oop_tocgen_p2.html");
        mock("/abooka/a9990001a/", "oop_tocgen_p1.html");
        LuaTable ab = callStr("getChapterList", genBook);
        check(ab.len().toint() == 60, "walk stops at failed p3: 60 chapters (not 150): " + ab.len().toint());
        boolean fetchedP4 = false;
        for (String u : fetchedUrls) if (u.contains("a9990001a/?p=4")) fetchedP4 = true;
        check(!fetchedP4, "p4 NEVER fetched after p3 failed (no solver storm)");
        check(urlHitCount.getOrDefault("a9990001a/?p=2", 0) == 1, "p2 fetched once");
        check(tocPrefNonEmpty("9990001") == 1, "progress cached persistently (oop_toc_9990001)");

        section("T6c RESUME — cached interior pages skip the network");
        freshPlugin();
        rules.clear(); resetMockState();
        mock("a9990001a/?p=2", "oop_tocgen_p2.html");
        mock("a9990001a/?p=3", "oop_tocgen_p3.html");
        mock("a9990001a/?p=4", "oop_tocgen_p4.html");
        mock("a9990001a/?p=5", "oop_tocgen_p5.html");
        mock("/abooka/a9990001a/", "oop_tocgen_p1.html");
        LuaTable full = callStr("getChapterList", genBook);
        check(full.len().toint() == 150, "resumed walk completes: 150 chapters: " + full.len().toint());
        check(urlHitCount.getOrDefault("/abooka/a9990001a/", 0) == 1, "page 1 fetched once (fresh)");
        check(urlHitCount.getOrDefault("a9990001a/?p=2", 0) == 0, "interior page 2 served from persistent cache (0 network)");
        check(urlHitCount.getOrDefault("a9990001a/?p=3", 0) == 1, "missing p3 fetched");
        check(urlHitCount.getOrDefault("a9990001a/?p=4", 0) == 1, "missing p4 fetched");
        check(urlHitCount.getOrDefault("a9990001a/?p=5", 0) == 1, "last page 5 always fetched fresh");
        boolean ordered150 = true;
        for (int i = 1; i <= 150; i++) {
            String t = full.get(i).checktable().get("title").tojstring();
            if (!t.equals(String.format("%03d", i))) { ordered150 = false; break; }
        }
        check(ordered150, "all 150 chapters ascending 001→150");

        section("T6d parsePage contract (engine paginated TOC API)");
        freshPlugin();
        rules.clear(); resetMockState();
        mock("a9990001a/?p=2", "oop_tocgen_p2.html");
        mock("a9990001a/?p=3", "oop_tocgen_p3.html");
        mock("a9990001a/?p=4", "oop_tocgen_p4.html");
        mock("a9990001a/?p=5", "oop_tocgen_p5.html");
        mock("/abooka/a9990001a/", "oop_tocgen_p1.html");
        LuaValue pp2 = parsePageRaw(genBook, 2);
        check(pp2.istable(), "parsePage(2) returns a table");
        LuaTable pp2t = pp2.checktable();
        check(pp2t.get("chapters").checktable().len().toint() == 30, "parsePage(2): 30 chapters");
        check(pp2t.get("totalPages").toint() == 5, "parsePage(2): totalPages=5 (from any page's select)");
        check("031".equals(pp2t.get("chapters").checktable().get(1).checktable().get("title").tojstring())
           && "032".equals(pp2t.get("chapters").checktable().get(2).checktable().get("title").tojstring()),
              "swapped-adjacent quirk re-sorted (031,032 — not 031,033)");
        check(urlHitCount.getOrDefault("a9990001a/?p=2", 0) == 0, "parsePage(2) interior: 0 network");
        LuaValue pp1 = parsePageRaw(genBook, 1);
        check(pp1.istable() && pp1.checktable().get("chapters").checktable().len().toint() == 30
              && pp1.checktable().get("totalPages").toint() == 5, "parsePage(1): 30 chapters, totalPages=5");
        check(urlHitCount.getOrDefault("/abooka/a9990001a/", 0) == 1, "parsePage(1) fetched the book page");
        parsePageRaw(genBook, 5); parsePageRaw(genBook, 5);
        check(urlHitCount.getOrDefault("a9990001a/?p=5", 0) == 2, "parsePage(last) always fresh: 2 calls = 2 fetches");
        // failure contract: nil + show_error ONLY for page 1
        rules.clear(); resetMockState();
        String deadBook = "https://www.oop.tw/abooka/a9990002a/";
        LuaValue d2 = parsePageRaw(deadBook, 2);
        check(!d2.istable(), "parsePage(2) unreachable → non-table (engine stops the walk)");
        check(showErrorCalls.isEmpty(), "no show_error for pages > 1 (partial progress stays silent)");
        LuaValue d1 = parsePageRaw(deadBook, 1);
        check(!d1.istable(), "parsePage(1) unreachable → non-table");
        check(showErrorCalls.size() == 1 && showErrorCalls.get(0)[0].contains("unreachable"),
              "parsePage(1) unreachable → show_error with guidance");

        section("T6e STALE SERVE — dead site still shows the cached TOC");
        freshPlugin();
        rules.clear(); resetMockState();
        LuaTable stale = callStr("getChapterList", genBook);
        check(stale.len().toint() == 150, "fully-cached book serves 150 chapters with NO site access: " + stale.len().toint());
        check(showErrorCalls.isEmpty(), "no error when a stale copy exists");

        section("T6f translation never pollutes the persistent cache");
        freshPlugin();
        prefs.put("oop_mode", "translate");
        cannedTranslate = "tr-";
        rules.clear(); resetMockState();
        String singleBook = "https://www.oop.tw/abooka/a9990003a/";
        mock("/abooka/a9990003a/", "oop_tocgen_single.html");
        LuaTable trs = callStr("getChapterList", singleBook);
        check(trs.len().toint() == 12, "single-page book: 12 chapters");
        check(trs.get(1).checktable().get("title").tojstring().startsWith("tr-"),
              "returned titles translated: " + trs.get(1).checktable().get("title").tojstring());
        String rawCache = prefs.getOrDefault("oop_toc_9990003", "");
        check(rawCache.contains("001" + (char) 31), "cache stores RAW titles (001)");
        check(!rawCache.contains("tr-1"), "cache NOT polluted by translated titles");
        cannedTranslate = null;
        prefs.remove("oop_mode");
'''

def patch(src):
    # doc header bump
    src = src.replace("Test harness for oop.lua v1.0.0", "Test harness for oop.lua v1.1.0")
    assert "v1.1.0" in src

    # helpers: parsePageRaw + tocPrefNonEmpty after callStr
    assert src.count(HELPERS) == 1, "callStr helper anchor"
    src = src.replace(HELPERS, HELPERS + NEW_HELPERS)

    # T0 version + required functions
    assert src.count(T0_OLD) == 1, "T0 version anchor"
    src = src.replace(T0_OLD, T0_NEW)
    assert src.count(REQUIRED_OLD) == 1, "T0 required anchor"
    src = src.replace(REQUIRED_OLD, REQUIRED_NEW)

    # new test battery after T6
    assert src.count(T6_LAST) == 1, "T6 tail anchor"
    src = src.replace(T6_LAST, T6_LAST + NEW_TESTS)

    # LRU battery goes right before the final summary (after T18)
    i = src.index('        System.out.println("\\n══')
    LRU_TESTS = '''        section("T6g LRU eviction — cache capped at 5 books");
        freshPlugin();
        rules.clear(); resetMockState();
        for (int b = 1; b <= 6; b++) {
            mock("/abooka/a999010" + b + "a/", "oop_tocgen_single.html");
        }
        for (int b = 1; b <= 6; b++) {
            LuaTable lru = callStr("getChapterList", "https://www.oop.tw/abooka/a999010" + b + "a/");
            check(lru.len().toint() == 12, "LRU book " + b + " walked (12 chapters)");
        }
        check("9990106,9990105,9990104,9990103,9990102".equals(prefs.getOrDefault("oop_toc_lru", "")),
              "LRU list = last 5 books: " + prefs.getOrDefault("oop_toc_lru", ""));
        check(tocPrefNonEmpty("9990106") == 1 && tocPrefNonEmpty("9990102") == 1,
              "newest 5 books cached");
        check(tocPrefNonEmpty("9990101") == 0 && tocPrefNonEmpty("9990001") == 0
              && tocPrefNonEmpty("3292752") == 0,
              "oldest entries evicted (9990101, 9990001, 3292752)");

'''
    src = src[:i] + LRU_TESTS + src[i:]
    return src

for p in PATHS:
    with open(p, encoding="utf-8") as f:
        s = f.read()
    s = patch(s)
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)
    print("patched", p)
print("OK")
