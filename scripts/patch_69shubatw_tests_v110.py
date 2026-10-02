#!/usr/bin/env python3
"""Patch S69TwTest.java for 69shubaTw.lua v1.1.0:
- T0 version 1.0.0 → 1.1.0
- T13: parsePage(1) now returns an EMPTY TABLE (never nil) when everything
  is blocked + show_error
- T14: assert the v2 cache serialization header
- NEW sections after T15: T13b seed+walk, T13c continuation/termination,
  T13d abort+resume, T13e zero-network guard, T13f replay memo,
  T13g adjacent growth (union), T13h gap growth (resume), T13i walk→real
  recovery (cache purge), T13j no-startread seed-only, T13k window-chase,
  T13l no-select chase, T13m query-shape options, T22 getChapterList walk.
"""
import re

P = "/home/z/my-project/download/test-harness/S69TwTest.java"
src = open(P, encoding="utf-8").read()

def rep(old, new, count=1):
    global src
    assert src.count(old) >= count, f"marker not found: {old[:80]!r}"
    src = src.replace(old, new, count)

# ── header comment ──────────────────────────────────────────────────────────
rep(""" * S69TwTest — mock harness for 69shubaTw.lua v1.0.0.""",
    """ * S69TwTest — mock harness for 69shubaTw.lua v1.1.0.""")

# ── T0 version ──────────────────────────────────────────────────────────────
rep('check("1.0.0".equals(globals.get("version").tojstring()), "version = 1.0.0");',
    'check("1.1.0".equals(globals.get("version").tojstring()), "version = 1.1.0");')

# ── T13: empty table instead of nil ────────────────────────────────────────
rep("""        LuaValue ppDead = parsePageRaw(BOOK_URL, 1);
        check(ppDead.isnil(), "parsePage(1) → nil when captcha blocks");
        check(showErrorCalls.size() == 1, "show_error fired once (page 1 only)");""",
    """        LuaValue ppDead = parsePageRaw(BOOK_URL, 1);
        check(ppDead.istable(), "parsePage(1) → EMPTY TABLE (never nil!) when everything is blocked");
        LuaTable ppDeadT = ppDead.checktable();
        check(ppDeadT.get("chapters").checktable().len().toint() == 0, "blocked → empty chapters");
        check(ppDeadT.get("totalPages").toint() == 1, "blocked → totalPages 1");
        check(showErrorCalls.size() == 1, "show_error fired once (page 1 only)");""")

# ── T14: v2 serialization format ────────────────────────────────────────────
rep("""        check(!pref.isEmpty(), "TOC persisted to preferences");""",
    """        check(!pref.isEmpty(), "TOC persisted to preferences");
        check(pref.startsWith("2|3|/indexlist/342441|r|||"), "v2 real-mode serialization header: " + pref.substring(0, Math.min(40, pref.length())));""")

# ── NEW sections: insert before T16 ────────────────────────────────────────
NEW = '''
        // ════════ T13b seed + walk (v1.1.0 core) ════════
        section("T13b TOC — /indexlist/ blocked → seed + #pb_next walk");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        mockCode("/indexlist/342441", "toc_c_captcha.html", 403);
        mock("/book/342441", "book_mini.html");
        for (int i = 1; i <= 4; i++) mock("/read/342441/" + (890314 + i), "walk_ch" + i + ".html");
        resetMockState();
        showErrorCalls.clear();
        LuaValue ppSeed = parsePageRaw(BOOK_URL, 1);
        check(ppSeed.istable(), "parsePage(1) returns a table (seed path)");
        LuaTable ppSeedT = ppSeed.checktable();
        LuaTable seedChs = ppSeedT.get("chapters").checktable();
        check(seedChs.len().toint() == 3, "page 1 = first walk chunk ch1..ch3: " + seedChs.len().toint());
        check("第1章 測試章節1".equals(seedChs.get(1).checktable().get("title").tojstring()),
            "walk chunk starts at 第1章 with its REAL title (from #nr_title)");
        check(ppSeedT.get("totalPages").toint() == 9999, "totalPages = 9999 (forces full reparse)");
        check(showErrorCalls.isEmpty(), "no show_error — a readable TOC exists");
        check(fetchedCount("/indexlist/342441") == 1, "/indexlist/ attempted exactly once");
        check(fetchedCount("/book/342441") == 1, "book page fetched once for the seed");
        check(fetchedCount("/read/342441/890318") == 0, "ch4 NEVER fetched — walk stops at the seed boundary");

        // T13c continuation: seed page emitted as the FINAL page, then stop
        LuaValue ppSeed2 = parsePageRaw(BOOK_URL, 2);
        check(ppSeed2.istable(), "parsePage(2) returns the next walk page");
        LuaTable ppSeed2T = ppSeed2.checktable();
        LuaTable seed2Chs = ppSeed2T.get("chapters").checktable();
        check(seed2Chs.len().toint() == 2, "final page = the seed chapters ch4..ch5: " + seed2Chs.len().toint());
        check(seed2Chs.get(1).checktable().get("title").tojstring().contains("第4章"),
            "seed page carries ch4 (last9 title)");
        check(parsePageRaw(BOOK_URL, 3).isnil(), "parsePage(3) → nil — the walk is complete");
        String walkPref = prefs.getOrDefault("s69tw_toc_342441", "");
        check(walkPref.contains("|w|"), "walk-mode entry persisted: " + walkPref.substring(0, Math.min(30, walkPref.length())));

        // T13c2 full re-walk is served from the persistent cache, zero network
        resetMockState();
        mockClear(); // nothing mockable: any fetch fails
        reloadPlugin();
        LuaValue ppSeedCached = parsePageRaw(BOOK_URL, 1);
        check(ppSeedCached.istable() && ppSeedCached.checktable().get("chapters").checktable().len().toint() == 3,
            "re-walk page 1 served from the persistent walk cache");
        LuaValue ppSeed2Cached = parsePageRaw(BOOK_URL, 2);
        check(ppSeed2Cached.istable() && ppSeed2Cached.checktable().get("chapters").checktable().len().toint() == 2,
            "re-walk final page (seed) served from cache");
        check(fetchedUrls.isEmpty(), "fully-walked book re-served with ZERO network: " + fetchedUrls.size());

        // ════════ T13d walk abort + resume ════════
        section("T13d TOC — walk aborts at first failure, resumes after");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        mockCode("/indexlist/342441", "toc_c_captcha.html", 403);
        mock("/book/342441", "book_mini.html");
        mock("/read/342441/890315", "walk_ch1.html");
        mockCode("/read/342441/890316", "toc_c_captcha.html", 403);
        resetMockState();
        LuaValue ppAb1 = parsePageRaw(BOOK_URL, 1);
        check(ppAb1.istable() && ppAb1.checktable().get("chapters").checktable().len().toint() == 2,
            "ch1 walked then ch2 fails → page 1 falls back to the SEED (ch4..ch5)");
        check(fetchedCount("/read/342441/890317") == 0, "ch3 never attempted after the ch2 failure");
        LuaValue ppAb2 = parsePageRaw(BOOK_URL, 2);
        check(ppAb2.isnil(), "walk page 2 aborts too (ch2 still failing)");
        // site recovers: the walk resumes exactly where it stopped
        mockClear();
        mockCode("/indexlist/342441", "toc_c_captcha.html", 403);
        mock("/book/342441", "book_mini.html");
        for (int i = 1; i <= 4; i++) mock("/read/342441/" + (890314 + i), "walk_ch" + i + ".html");
        resetMockState();
        LuaValue ppRs1 = parsePageRaw(BOOK_URL, 1);
        check(ppRs1.istable() && ppRs1.checktable().get("chapters").checktable().len().toint() == 3,
            "resumed walk refills page 1 to ch1..ch3");
        check(fetchedCount("/read/342441/890315") >= 1, "ch1 re-fetched during refill (partial page was unserved)");
        LuaValue ppRs2 = parsePageRaw(BOOK_URL, 2);
        check(ppRs2.istable() && ppRs2.checktable().get("chapters").checktable().len().toint() == 2,
            "final page (seed) emitted after the resumed walk");

        // ════════ T13e zero-network guard (solver-storm defense) ════════
        section("T13e TOC — page>1 with no data answers nil with ZERO network");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        resetMockState();
        check(parsePageRaw(BOOK_URL, 5).isnil(), "parsePage(5) with no cache → nil");
        check(parsePageRaw("https://69shuba.tw/book/123456/", 2).isnil(), "parsePage(2) other book → nil");
        check(fetchedUrls.isEmpty(), "no network requests at all: " + fetchedUrls.size());

        // ════════ T13f replay memo ════════
        section("T13f TOC — replay memo collapses the engine's double parsePage(1)");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        mockCode("/indexlist/342441", "toc_c_captcha.html", 403);
        mock("/book/342441", "book_mini.html");
        for (int i = 1; i <= 4; i++) mock("/read/342441/" + (890314 + i), "walk_ch" + i + ".html");
        resetMockState();
        parsePageRaw(BOOK_URL, 1);
        parsePageRaw(BOOK_URL, 1); // engine's second call (chaptersLastPage save)
        check(fetchedCount("/indexlist/342441") == 1, "/indexlist/ attempted ONCE across both calls (no second solver ladder)");
        check(fetchedCount("/book/342441") == 1, "book page fetched once");

        // ════════ T13g adjacent growth (union refresh) ════════
        section("T13g TOC — adjacent growth: seed page unions the fresh seed");
        // state: complete walk (ch1..ch3 + seed page ch4..ch5) from T13f
        mockClear();
        mockCode("/indexlist/342441", "toc_c_captcha.html", 403);
        mock("/book/342441", "book_grow_adj.html"); // last9 = ch6, ch7
        mock("/read/342441/890319", "walk_ch5.html"); // ch5's page: #pb_next → ch6
        resetMockState();
        LuaValue ppAdj = parsePageRaw(BOOK_URL, 1);
        check(ppAdj.istable(), "adjacent growth: parsePage(1) still returns the cached chunk 1");
        LuaValue ppAdj2 = parsePageRaw(BOOK_URL, 2);
        LuaTable adj2 = ppAdj2.checktable().get("chapters").checktable();
        check(adj2.len().toint() == 4, "seed page = union(old ch4..ch5, fresh ch6..ch7): " + adj2.len().toint());
        boolean adjOrder = adj2.get(4).checktable().get("url").tojstring().endsWith("/read/342441/890320");
        check(adjOrder, "union is cid-sorted (ch7 last)");
        check(parsePageRaw(BOOK_URL, 3).isnil(), "walk complete after the union");

        // ════════ T13h gap growth (resume from #pb_next) ════════
        section("T13h TOC — gap growth: walk resumes from last chapter's #pb_next");
        // state: ch1..ch3 walked + seed page ch4..ch7 (T13g); fresh seed = ch9, ch10
        mockClear();
        mockCode("/indexlist/342441", "toc_c_captcha.html", 403);
        mock("/book/342441", "book_grow_gap.html"); // last9 = ch9, ch10
        mock("/read/342441/890320", "walk_ch7.html"); // ch7 (seed page tail): #pb_next → ch8
        mock("/read/342441/890321", "walk_ch8.html"); // ch8: #pb_next → ch9
        resetMockState();
        LuaValue ppGap1 = parsePageRaw(BOOK_URL, 1);
        check(ppGap1.istable() && ppGap1.checktable().get("chapters").checktable().len().toint() == 3,
            "gap growth: page 1 still the cached chunk (ch1..ch3)");
        LuaValue ppGap2 = parsePageRaw(BOOK_URL, 2);
        LuaTable gap2 = ppGap2.checktable().get("chapters").checktable();
        check(gap2.len().toint() == 5, "seed page refilled: ch4..ch7 + walked ch8: " + gap2.len().toint());
        boolean gapHasCh8 = false;
        for (int i = 1; i <= gap2.len().toint(); i++)
            if (gap2.get(i).checktable().get("url").tojstring().endsWith("/read/342441/890321")) gapHasCh8 = true;
        check(gapHasCh8, "gap chapter ch8 walked in via the resume");
        LuaValue ppGap3 = parsePageRaw(BOOK_URL, 3);
        check(ppGap3.istable(), "the fresh seed page is emitted after the resumed walk");
        LuaTable gap3 = ppGap3.checktable().get("chapters").checktable();
        check(gap3.len().toint() == 2 && gap3.get(2).checktable().get("url").tojstring().endsWith("/read/342441/890324"),
            "fresh seed = ch9..ch10");
        check(parsePageRaw(BOOK_URL, 4).isnil(), "walk complete after the gap fill");

        // ════════ T13i walk → real recovery (cache purge) ════════
        section("T13i TOC — /indexlist/ recovers → walk state purged");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        mockCode("/indexlist/342441", "toc_c_captcha.html", 403);
        mock("/book/342441", "book_mini.html");
        for (int i = 1; i <= 4; i++) mock("/read/342441/" + (890314 + i), "walk_ch" + i + ".html");
        parsePageRaw(BOOK_URL, 1); // enter walk mode
        parsePageRaw(BOOK_URL, 2); // seed page emitted
        // the site clears the WAF for /indexlist/ — the REAL toc appears
        mockClear();
        mock("/indexlist/342441/2", "toc_a_p2.html");
        mock("/indexlist/342441/3", "toc_a_p3.html");
        mock("/indexlist/342441/", "toc_a_p1.html");
        resetMockState();
        LuaValue ppRec1 = parsePageRaw(BOOK_URL, 1);
        check(ppRec1.istable() && ppRec1.checktable().get("chapters").checktable().len().toint() == 30,
            "real TOC page 1 (30 chapters) replaces the walk");
        check(ppRec1.checktable().get("totalPages").toint() == 3, "real totalPages = 3");
        LuaValue ppRec2 = parsePageRaw(BOOK_URL, 2);
        check(ppRec2.istable(), "real page 2 loads");
        LuaTable rec2 = ppRec2.checktable().get("chapters").checktable();
        boolean recIsReal = rec2.len().toint() == 30 &&
            rec2.get(1).checktable().get("title").tojstring().contains("第31章");
        check(recIsReal, "page 2 is the REAL toc page (walk chunks dropped, not served): " +
            (rec2.len().toint() > 0 ? rec2.get(1).checktable().get("title").tojstring() : "empty"));
        String recPref = prefs.getOrDefault("s69tw_toc_342441", "");
        check(recPref.startsWith("2|3|/indexlist/342441|r|"), "cache back in real mode: " + recPref.substring(0, Math.min(30, recPref.length())));

        // ════════ T13j seed without #startread ════════
        section("T13j TOC — book page without #startread → seed-only");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        mockCode("/indexlist/342441", "toc_c_captcha.html", 403);
        mock("/book/342441", "book_nostart.html");
        resetMockState();
        LuaValue ppNs = parsePageRaw(BOOK_URL, 1);
        check(ppNs.istable() && ppNs.checktable().get("chapters").checktable().len().toint() == 2,
            "no #startread → the seed itself is page 1 (ch4..ch5)");
        check(parsePageRaw(BOOK_URL, 2).isnil(), "nothing more to walk → nil");
        check(fetchedUrls.stream().noneMatch(u -> u.contains("/read/342441/")),
            "zero /read/ fetches without a walk start");

        // ════════ T13k window-chase totalPages ════════
        section("T13k TOC — 10-page select window chased to the true total");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        String winUrl = "https://69shuba.tw/book/777001/";
        mock("/indexlist/777001/10", "toc_win_p10.html");
        mock("/indexlist/777001/15", "toc_win_p15.html");
        mock("/indexlist/777001/", "toc_win_p1.html");
        resetMockState();
        LuaValue ppWin = parsePageRaw(winUrl, 1);
        check(ppWin.istable(), "window TOC parsePage(1)");
        check(ppWin.checktable().get("totalPages").toint() == 15,
            "page 1 select says 10, chase discovers 15: " + ppWin.checktable().get("totalPages").toint());
        check(ppWin.checktable().get("chapters").checktable().len().toint() == 30, "page 1 = 30 chapters");
        check(fetchedCount("/indexlist/777001/10") == 1 && fetchedCount("/indexlist/777001/15") == 1,
            "two probe fetches (page 10 then page 15)");
        resetMockState();
        mockClear();
        mock("/indexlist/777001/2", "toc_win_p10.html"); // any 200 page
        LuaValue ppWin10 = parsePageRaw(winUrl, 10);
        check(ppWin10.istable() && ppWin10.checktable().get("chapters").checktable().len().toint() == 30,
            "probed page 10 served from cache (0 network)");
        check(fetchedUrls.isEmpty(), "page-10 serve made ZERO network calls: " + fetchedUrls.size());

        // ════════ T13l no-select pager chase ════════
        section("T13l TOC — no select at all: chase from the next link");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        String nsUrl = "https://69shuba.tw/book/777002/";
        mock("/indexlist/777002/2", "toc_noselect_p2.html");
        mock("/indexlist/777002/", "toc_noselect_p1.html");
        resetMockState();
        LuaValue ppNs2 = parsePageRaw(nsUrl, 1);
        check(ppNs2.istable(), "no-select TOC parsePage(1)");
        check(ppNs2.checktable().get("totalPages").toint() == 2,
            "no options (tp=1) + next link → probe finds page 2 = last: " + ppNs2.checktable().get("totalPages").toint());
        check(ppNs2.checktable().get("chapters").checktable().len().toint() == 5, "page 1 = 5 chapters");

        // ════════ T13m query-shape select options ════════
        section("T13m TOC — query-string option values parse");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        String qUrl = "https://69shuba.tw/book/777003/";
        mock("/indexlist/777003/", "toc_querysel_p1.html");
        resetMockState();
        LuaValue ppQ = parsePageRaw(qUrl, 1);
        check(ppQ.istable(), "query-select TOC parsePage(1)");
        check(ppQ.checktable().get("totalPages").toint() == 7,
            "options /search/N?x → totalPages 7: " + ppQ.checktable().get("totalPages").toint());
        check(ppQ.checktable().get("chapters").checktable().len().toint() == 10, "10 chapters parsed");

        // ════════ T22 getChapterList — walk mode end-to-end ════════
        section("T22 getChapterList — walk mode, legacy engine");
        reloadPlugin();
        clearTocPrefs();
        mockClear();
        mockCode("/indexlist/342441", "toc_c_captcha.html", 403);
        mock("/book/342441", "book_mini.html");
        for (int i = 1; i <= 4; i++) mock("/read/342441/" + (890314 + i), "walk_ch" + i + ".html");
        resetMockState();
        LuaTable tocWalk = callStr("getChapterList", BOOK_URL);
        check(tocWalk.len().toint() == 5, "walk TOC = 5 chapters (ch1..ch5): " + tocWalk.len().toint());
        boolean walkAsc = true;
        long wprev = 0;
        for (int i = 1; i <= tocWalk.len().toint(); i++) {
            long cid = Long.parseLong(tocWalk.get(i).checktable().get("url").tojstring().replaceAll(".*/read/342441/", ""));
            if (cid <= wprev) walkAsc = false;
            wprev = cid;
        }
        check(walkAsc, "cid-ascending order (walk chunk 1, then the seed page)");
        check("第1章 測試章節1".equals(tocWalk.get(1).checktable().get("title").tojstring()), "starts at 第1章");
        check(tocWalk.get(5).checktable().get("title").tojstring().contains("第5章"), "ends at the seed's ch5");

'''
marker = "        // ════════ T16 chapter text — normal (1 / 1) ════════"
rep(marker, NEW + marker)

open(P, "w", encoding="utf-8").write(src)
print(f"patched {P}: {src.count(chr(10))} lines")
