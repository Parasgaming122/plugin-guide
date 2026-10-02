#!/usr/bin/env python3
"""Patch S69TwTest.java for 69shubaTw v1.3.0:
- T0: version 1.3.0, 4 EdgeOne trigger markers
- T9-T15: rewritten for the lazy /Indexlist/ (capital-I) engine using the
  REAL captured fixtures (idx_p1..p5 = book 342441, 450 chapters; idx_small_p1
  = 40-chapter single-page novel; idx_chal = EdgeOne challenge page)
"""
import re

P = "/home/z/my-project/testenv/S69TwTest.java"
src = open(P, encoding='utf-8').read()

# ── T0 updates ──────────────────────────────────────────────────────────────
src = src.replace(
    'check("1.0.0".equals(globals.get("version").tojstring()), "version = 1.0.0");',
    'check("1.3.0".equals(globals.get("version").tojstring()), "version = 1.3.0");')

src = src.replace(
    '''        check(!cf.isnil() && cf.get("trigger_markers").istable(), "cf_options present with trigger_markers");''',
    '''        check(!cf.isnil() && cf.get("trigger_markers").istable(), "cf_options present with trigger_markers");
        LuaTable tm = cf.get("trigger_markers").checktable();
        check(tm.len().toint() == 4, "4 EdgeOne trigger markers: " + tm.len().toint());''')

src = src.replace(
    '        check(hasAegis && hasRecaptcha && hasTitle, "all 3 EdgeOne captcha markers registered");',
    '''        boolean hasTurnstile = false;
        for (int i = 1; i <= tm.len().toint(); i++)
            if (tm.get(i).tojstring().contains("challenges.cloudflare.com/turnstile")) hasTurnstile = true;
        check(hasAegis && hasRecaptcha && hasTitle && hasTurnstile, "all 4 EdgeOne captcha markers registered");''')

# ── replace T9..T15 with the v1.3.0 TOC suite ────────────────────────────────
start = src.find('        // ════════ T9 TOC')
end = src.find('        // ════════ T16 chapter text')
assert start > 0 and end > start, (start, end)

new_tests = '''        // ════════ T9 TOC — parsePage(1) contract, REAL page (450-ch book) ════════
        section("T9 TOC — parsePage(1) on the real /Indexlist/ page 1");
        clearTocPrefs();
        mockClear();
        mock("/Indexlist/342441/", "idx_p1.html");
        resetMockState();
        LuaValue pp1 = parsePageRaw(BOOK_URL, 1);
        check(pp1.istable(), "parsePage(1) returns a table");
        LuaTable pp1t = pp1.checktable();
        LuaTable ch1list = pp1t.get("chapters").checktable();
        check(ch1list.len().toint() == 100, "page 1 = 100 chapters (98 anchors + 2 protected spans): " + ch1list.len().toint());
        check(pp1t.get("totalPages").toint() == 5, "totalPages = 5 (select lists every page)");
        check("第1章 簽到！神獸蛋！".equals(ch1list.get(1).checktable().get("title").tojstring()),
            "first chapter title: " + ch1list.get(1).checktable().get("title").tojstring());
        check(ch1list.get(1).checktable().get("url").tojstring().equals("https://69shuba.tw/read/342441/890315"),
            "first chapter canonical URL");
        // the two PROTECTED (span) chapters must be present — the v1.2.0 bug
        check("第2章 被逼婚離家出走的老四".equals(ch1list.get(2).checktable().get("title").tojstring()),
            "protected span chapter 2 (data-cid-url) collected: " + ch1list.get(2).checktable().get("title").tojstring());
        check(ch1list.get(2).checktable().get("url").tojstring().endsWith("/read/342441/890316"), "protected ch2 URL");
        check("第99章 國運之力，取之於民，用之於民".equals(ch1list.get(99).checktable().get("title").tojstring()),
            "protected span chapter 99 collected: " + ch1list.get(99).checktable().get("title").tojstring());
        check(ch1list.get(100).checktable().get("url").tojstring().endsWith("/read/342441/890414"), "ch100 URL cid 890414");
        boolean noForeign = true;
        for (int i = 1; i <= ch1list.len().toint(); i++)
            if (!ch1list.get(i).checktable().get("url").tojstring().contains("/read/342441/")) noForeign = false;
        check(noForeign, "foreign-book /read/ links excluded (same-book filter)");
        check(fetchedUrls.size() == 1 && fetchedUrls.get(0).equals("https://69shuba.tw/Indexlist/342441/"),
            "fetched the CAPITAL-I WAF-exempt URL exactly once: " + fetchedUrls);
        parsePageRaw(BOOK_URL, 1); // engine calls parsePage(1) twice
        check(fetchedCount("/Indexlist/342441/") == 1, "second parsePage(1) served from the 60s page cache");

        // pages 2..5 (lazy, one each)
        mockClear();
        mock("/Indexlist/342441/2", "idx_p2.html");
        mock("/Indexlist/342441/3", "idx_p3.html");
        mock("/Indexlist/342441/4", "idx_p4.html");
        mock("/Indexlist/342441/5", "idx_p5.html");
        mock("/Indexlist/342441/", "idx_p1.html");
        LuaValue pp2 = parsePageRaw(BOOK_URL, 2);
        check(pp2.istable() && pp2.checktable().get("chapters").checktable().len().toint() == 100, "page 2 = 100 chapters");
        check(pp2.checktable().get("totalPages").toint() == 5, "page 2 totalPages = 5");
        check(pp2.checktable().get("chapters").checktable().get(1).checktable().get("url").tojstring().endsWith("/read/342441/890415"),
            "page 2 starts at ch101 (cid 890415)");
        check(fetchedUrls.get(fetchedUrls.size() - 1).equals("https://69shuba.tw/Indexlist/342441/2/"),
            "page 2 fetched via capital-I URL: " + fetchedUrls.get(fetchedUrls.size() - 1));

        // ════════ T10 TOC — full lazy walk via getChapterList (450 chapters) ════════
        section("T10 TOC — full walk (getChapterList, 450 chapters)");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        mock("/Indexlist/342441/2", "idx_p2.html");
        mock("/Indexlist/342441/3", "idx_p3.html");
        mock("/Indexlist/342441/4", "idx_p4.html");
        mock("/Indexlist/342441/5", "idx_p5.html");
        mock("/Indexlist/342441/", "idx_p1.html");
        resetMockState();
        LuaTable toc = callStr("getChapterList", BOOK_URL);
        check(toc.len().toint() == 450, "full walk = 450 chapters (100+100+100+100+50): " + toc.len().toint());
        check("第1章 簽到！神獸蛋！".equals(toc.get(1).checktable().get("title").tojstring()), "walk starts at 第1章");
        check(toc.get(450).checktable().get("title").tojstring().contains("老怪甦醒，大明的星門計劃"),
            "walk ends at 第450章: " + toc.get(450).checktable().get("title").tojstring());
        check(toc.get(450).checktable().get("url").tojstring().endsWith("/read/342441/4001259"), "ch450 URL cid 4001259");
        boolean ascending = true;
        long prev = 0;
        for (int i = 1; i <= toc.len().toint(); i++) {
            String u = toc.get(i).checktable().get("url").tojstring();
            long cid = Long.parseLong(u.replaceAll(".*/read/342441/", ""));
            if (cid <= prev) ascending = false;
            prev = cid;
        }
        check(ascending, "cids strictly ascending across all 5 pages (page order = reading order)");
        for (int p = 2; p <= 5; p++)
            check(fetchedCount("/Indexlist/342441/" + p + "/") == 1, "page " + p + " fetched exactly once");
        // re-walk within the page-cache window: ZERO new network
        int before = fetchedUrls.size();
        callStr("getChapterList", BOOK_URL);
        check(fetchedUrls.size() == before, "immediate re-walk = zero network (60s cache + TOC cache)");

        // ════════ T11 TOC — early abort on page failure (solver-storm defense) ════════
        section("T11 TOC — early abort (challenge on page 2)");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        mockCode("/Indexlist/342441/2", "idx_chal.html", 403);
        mock("/Indexlist/342441/", "idx_p1.html");
        resetMockState();
        LuaTable tocAb = callStr("getChapterList", BOOK_URL);
        check(tocAb.len().toint() == 100, "abort keeps page-1 chapters: " + tocAb.len().toint());
        check(fetchedCount("/Indexlist/342441/3/") == 0, "page 3 NEVER fetched after page-2 failure");
        check(fetchedCount("/Indexlist/342441/2/") == 1, "page 2 attempted exactly once");

        // ════════ T12 TOC — single-page 40-chapter novel (the user's case) ════════
        section("T12 TOC — 40-chapter novel, ONE page, ONE request");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        mock("/Indexlist/777777/", "idx_small_p1.html");
        resetMockState();
        String bookB = "https://69shuba.tw/book/777777/";
        LuaValue ppB1 = parsePageRaw(bookB, 1);
        check(ppB1.istable() && ppB1.checktable().get("chapters").checktable().len().toint() == 40,
            "40 chapters on the single page: " + ppB1.checktable().get("chapters").checktable().len().toint());
        check(ppB1.checktable().get("totalPages").toint() == 1, "totalPages = 1 (one select option)");
        check(fetchedUrls.size() == 1, "exactly ONE catalog request for the whole novel: " + fetchedUrls.size());
        LuaValue ppB2 = parsePageRaw(bookB, 2);
        check(ppB2.isnil(), "parsePage(2) on single-page book → nil (engine stops)");
        check(fetchedUrls.size() == 1, "parsePage(2) issued NO network request (no blind probes)");
        LuaTable tocB = callStr("getChapterList", bookB);
        check(tocB.len().toint() == 40, "getChapterList = 40 chapters");
        // added via the lowercase /indexlist/ URL paste (bookIdFromUrl is case-insensitive)
        reloadPlugin();
        clearTocPrefs();
        resetMockState();
        String bookB2 = "https://69shuba.tw/indexlist/777777/";
        LuaValue ppB3 = parsePageRaw(bookB2, 1);
        check(ppB3.istable() && ppB3.checktable().get("chapters").checktable().len().toint() == 40,
            "book added via lowercase /indexlist/ URL works identically");
        // …and via the capital paste
        reloadPlugin();
        clearTocPrefs();
        resetMockState();
        LuaValue ppB4 = parsePageRaw("https://69shuba.tw/Indexlist/777777/", 1);
        check(ppB4.istable() && ppB4.checktable().get("chapters").checktable().len().toint() == 40,
            "book added via capital /Indexlist/ URL works identically");

        // ════════ T12b TOC — soft-serve guard (wrong page-N URL re-serves page 1) ════════
        section("T12b TOC — soft-serve guard");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        mock("/Indexlist/342441/2", "idx_p1.html"); // wrong URL → page-1 content again
        mock("/Indexlist/342441/", "idx_p1.html");
        resetMockState();
        LuaValue ppSs = parsePageRaw(BOOK_URL, 2);
        check(ppSs.isnil(), "page 2 re-serving page 1 → nil (walk stops, TOC not polluted)");
        LuaTable tocDd = callStr("getChapterList", BOOK_URL);
        boolean noDup = true;
        HashSet<String> urls = new HashSet<>();
        for (int i = 1; i <= tocDd.len().toint(); i++) {
            String u = tocDd.get(i).checktable().get("url").tojstring();
            if (!urls.add(u)) noDup = false;
        }
        check(tocDd.len().toint() == 100 && noDup, "soft-served duplicates never reach the TOC: " + tocDd.len().toint() + " unique chapters");

        // ════════ T13 TOC — challenge blocks page 1, no cache ════════
        section("T13 TOC — challenge page 1, no cache");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        mockCode("/Indexlist/342441", "idx_chal.html", 403);
        resetMockState();
        showErrorCalls.clear();
        LuaValue ppDead = parsePageRaw(BOOK_URL, 1);
        check(ppDead.istable() && ppDead.checktable().get("chapters").checktable().len().toint() == 0,
            "parsePage(1) → EMPTY TABLE (never nil — the v1.0.0 lesson)");
        check(ppDead.checktable().get("totalPages").toint() == 1, "totalPages = 1 on failure");
        check(showErrorCalls.size() == 1, "show_error fired once (page 1 only)");
        check(fetchedUrls.size() == 1, "NO fallback fetches after the challenge (no seed/walk storm): " + fetchedUrls.size());
        showErrorCalls.clear();
        LuaTable tocDead = callStr("getChapterList", BOOK_URL);
        check(tocDead.len().toint() == 0, "getChapterList → {} when challenged");
        check(showErrorCalls.size() >= 1, "getChapterList surfaces show_error");
        check(fetchedUrls.size() == 2, "getChapterList retried page 1 exactly once more: " + fetchedUrls.size());
        // challenge served with HTTP 200 is detected via the body markers too
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        mock("/Indexlist/342441/", "idx_chal.html"); // 200 + challenge body
        resetMockState();
        showErrorCalls.clear();
        LuaValue pp200 = parsePageRaw(BOOK_URL, 1);
        check(pp200.istable() && pp200.checktable().get("chapters").checktable().len().toint() == 0,
            "challenge body with HTTP 200 also detected (body markers)");

        // ════════ T14 TOC — persistent cache (v3 format) ════════
        section("T14 TOC — persistent cache (set_preference, v3 format)");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        mock("/Indexlist/342441/2", "idx_p2.html");
        mock("/Indexlist/342441/3", "idx_p3.html");
        mock("/Indexlist/342441/4", "idx_p4.html");
        mock("/Indexlist/342441/5", "idx_p5.html");
        mock("/Indexlist/342441/", "idx_p1.html");
        resetMockState();
        callStr("getChapterList", BOOK_URL); // warm the cache
        String pref = prefs.getOrDefault("s69tw_toc_342441", "");
        check(!pref.isEmpty(), "TOC persisted to preferences");
        check(pref.startsWith("3|5|"), "v3 format with totalPages: " + pref.substring(0, Math.min(10, pref.length())));
        check(pref.contains("第1章 簽到！神獸蛋！"), "raw titles cached");
        reloadPlugin(); // fresh Lua state — only the persistent prefs survive
        resetMockState();
        mockClear(); // NO mock rules: any fetch would fail
        LuaValue pp2cached = parsePageRaw(BOOK_URL, 2);
        check(pp2cached.istable() && pp2cached.checktable().get("chapters").checktable().len().toint() == 100,
            "interior page 2 served from persistent cache, ZERO network");
        check(fetchedUrls.isEmpty(), "no network requests at all: " + fetchedUrls.size());
        LuaValue pp5cached = parsePageRaw(BOOK_URL, 5);
        check(pp5cached.istable() && pp5cached.checktable().get("chapters").checktable().len().toint() == 50,
            "last page 5: live fetch fails, STALE cache serves 50 chapters");
        check(fetchedUrls.size() == 1, "exactly one (failed) fresh attempt for the last page: " + fetchedUrls.size());

        // ════════ T15 TOC — stale serve when site unreachable ════════
        section("T15 TOC — stale serve (challenge + cache)");
        mockClear();
        mockCode("/Indexlist/342441", "idx_chal.html", 403);
        resetMockState();
        LuaTable tocStale = callStr("getChapterList", BOOK_URL);
        check(tocStale.len().toint() == 450, "stale cache serves the full 450-chapter TOC: " + tocStale.len().toint());

'''
src = src[:start] + new_tests + src[end:]
open(P, 'w', encoding='utf-8').write(src)
print(f"patched {P}: {src.count(chr(10))+1} lines")
