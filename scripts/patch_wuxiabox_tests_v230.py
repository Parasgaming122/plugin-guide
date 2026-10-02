#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Patch WuxiaboxTest.java for wuxiabox.lua v2.3.0 (smart mirror switcher).

- T0 version 2.2.0 -> 2.3.0
- reloadPlugin() helper (fresh Lua state reading current prefs — simulates
  an engine restart; the health state persists via set_preference)
- T13/T13b/T15/T15b/T16: hermetic health resets + T13 timing threshold
  (the pre-attempt sleep is gone in 2.3.0)
- NEW T17 family: health tracking, cooldown steering, persistence across
  restart, cooldown expiry, success reset, junk-body failover, 404 neutrality
- NEW T18: mirror-native search pagination (searchid's own base)
- NEW T19: both-sites-dead chapter failure raises a clear error
- T14: smart-switcher label check
"""
import sys

PATH = "/home/z/my-project/testenv/WuxiaboxTest.java"

with open(PATH, "r", encoding="utf-8") as f:
    src = f.read()

def replace_once(text, old, new, what):
    n = text.count(old)
    if n != 1:
        print(f"ANCHOR FAIL ({what}): {n} occurrences", file=sys.stderr)
        sys.exit(1)
    return text.replace(old, new, 1)

# ── helper: reloadPlugin ─────────────────────────────────────────────────────
src = replace_once(
    src,
    """    static int urlHits(String substr) {
        int c = 0;
        for (String u : requestedUrls) if (u.contains(substr)) c++;
        return c;
    }
""",
    """    static int urlHits(String substr) {
        int c = 0;
        for (String u : requestedUrls) if (u.contains(substr)) c++;
        return c;
    }
    static void reloadPlugin() throws Exception {
        // Fresh Lua state reading the CURRENT prefs — simulates an engine
        // restart. The 2.3.0 health state persists via set_preference, so
        // a reload must still honour cooldowns (T17b) and clear expired
        // ones (T17c).
        plugin = globals.load(new FileReader("/home/z/my-project/download/wuxiabox.lua"), "wuxiabox.lua").call();
        plugin = globals; // functions are globals (the chunk returns nothing)
    }
""",
    "reloadPlugin helper")

# ── T0 version ──────────────────────────────────────────────────────────────
src = replace_once(
    src,
    'check("version is 2.2.0", globals.get("version").tojstring().equals("2.2.0"), globals.get("version").tojstring());',
    'check("version is 2.3.0", globals.get("version").tojstring().equals("2.3.0"), globals.get("version").tojstring());',
    "T0 version")

# ── T13: hermetic reset + timing ────────────────────────────────────────────
src = replace_once(
    src,
    """        System.out.println("\\n== T13: getChapterText 502 recovery (mirror alternation) ==");
        String gateway502 = "<html><head><title>502 Bad Gateway</title></head><body><center><h1>502 Bad Gateway</h1></center><hr><center>cloudflare</center></body></html>";
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        prefs.put("wuxiabox_chapter_retries", "2");
""",
    """        System.out.println("\\n== T13: getChapterText 502 recovery (smart switcher) ==");
        String gateway502 = "<html><head><title>502 Bad Gateway</title></head><body><center><h1>502 Bad Gateway</h1></center><hr><center>cloudflare</center></body></html>";
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        prefs.put("wuxiabox_chapter_retries", "2");
        prefs.put("wuxiabox_site_preference", "auto");
        prefs.put("wuxiabox_site_health", "");
        reloadPlugin(); // hermetic health slate (2.3.0)
""",
    "T13 reset")

src = replace_once(
    src,
    '        check("backoff delays applied (>= 4s total)", elapsed >= 4000, "elapsed=" + elapsed + "ms");',
    '        check("backoff delays applied (>= 3.4s total — 2.3.0 dropped the pre-attempt sleep)", elapsed >= 3400, "elapsed=" + elapsed + "ms");',
    "T13 timing")

# ── T13b: hermetic reset ────────────────────────────────────────────────────
src = replace_once(
    src,
    """        System.out.println("\\n== T13b: 502 recovery, box-only preference ==");
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        prefs.put("wuxiabox_site_preference", "box");
""",
    """        System.out.println("\\n== T13b: 502 recovery, box-only preference ==");
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        prefs.put("wuxiabox_site_preference", "box");
        prefs.put("wuxiabox_site_health", "");
        reloadPlugin(); // hermetic health slate (2.3.0)
""",
    "T13b reset")

# ── T15: hermetic reset ─────────────────────────────────────────────────────
src = replace_once(
    src,
    """        System.out.println("\\n== T15: catalog mirror fallback (auto) ==");
        prefs.put("wuxiabox_site_preference", "auto");
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
""",
    """        System.out.println("\\n== T15: catalog mirror fallback (auto) ==");
        prefs.put("wuxiabox_site_preference", "auto");
        prefs.put("wuxiabox_site_health", "");
        reloadPlugin(); // hermetic health slate (2.3.0)
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
""",
    "T15 reset")

# ── T15b: hermetic reset ────────────────────────────────────────────────────
src = replace_once(
    src,
    """        System.out.println("\\n== T15b: wuxiaspot-first preference ==");
        prefs.put("wuxiabox_site_preference", "spot");
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
""",
    """        System.out.println("\\n== T15b: wuxiaspot-first preference ==");
        prefs.put("wuxiabox_site_preference", "spot");
        prefs.put("wuxiabox_site_health", "");
        reloadPlugin(); // hermetic health slate (2.3.0)
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
""",
    "T15b reset")

# ── T16: hermetic reset ─────────────────────────────────────────────────────
src = replace_once(
    src,
    """        System.out.println("\\n== T16: search mirror fallback ==");
        prefs.put("wuxiabox_site_preference", "auto");
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
""",
    """        System.out.println("\\n== T16: search mirror fallback ==");
        prefs.put("wuxiabox_site_preference", "auto");
        prefs.put("wuxiabox_site_health", "");
        reloadPlugin(); // hermetic health slate (2.3.0)
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
""",
    "T16 reset")

# ── NEW TESTS: T17 family + T18 + T19, inserted before T14 ──────────────────
NEW_TESTS = """        // ── T17: smart switcher — health tracking + cooldown steering ────
        System.out.println("\\n== T17: smart switcher (health + cooldown) ==");
        prefs.put("wuxiabox_site_preference", "auto");
        prefs.put("wuxiabox_site_health", "");
        reloadPlugin();
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        Rule catFailX = on("wuxiabox.com/list/all/all-onclick-0.html");
        catFailX.code = 502; catFailX.body = gateway502;
        Rule catMirX = on("wuxiaspot.com/list/all/all-onclick-0.html");
        catMirX.file = "list_newstime.html";
        LuaValue catS1 = call("getCatalogList", 0);
        check("1st 502: catalog still served (mirror failover)", len(catS1.get("items")) == 30, "got " + len(catS1.get("items")));
        check("1st 502: primary hit once, mirror hit once",
                urlHits("GET https://www.wuxiabox.com/list/all/all-onclick-0.html") == 1
                        && urlHits("GET https://www.wuxiaspot.com/list/all/all-onclick-0.html") == 1);
        String h1 = prefs.get("wuxiabox_site_health");
        check("health persisted via set_preference (fails=1, no cooldown yet)", h1 != null && h1.contains("box=1,0"), h1);
        requestedUrls.clear();
        LuaValue catS2 = call("getCatalogList", 0);
        check("fails=1 below threshold: primary still tried first",
                urlHits("GET https://www.wuxiabox.com/list/all/all-onclick-0.html") == 1
                        && len(catS2.get("items")) == 30);
        requestedUrls.clear();
        LuaValue catS3 = call("getCatalogList", 0);
        check("2 fails → cooldown: primary SKIPPED entirely (0 hits)",
                urlHits("GET https://www.wuxiabox.com/list/all/all-onclick-0.html") == 0,
                "hits=" + urlHits("GET https://www.wuxiabox.com/list/all/all-onclick-0.html"));
        check("cooldown fetch served straight from the mirror",
                len(catS3.get("items")) == 30 && urlHits("GET https://www.wuxiaspot.com/list/all/all-onclick-0.html") == 1);
        String h2 = prefs.get("wuxiabox_site_health");
        check("cooldown recorded in persisted health (box=2,<future ms>)", h2 != null && h2.contains("box=2,1"), h2);

        // ── T17b: cooldown persists across an engine restart ───────────
        System.out.println("\\n== T17b: cooldown survives a restart ==");
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        on("wuxiabox.com/list/all/all-onclick-0.html").file = "list_newstime.html"; // primary is FINE now
        on("wuxiaspot.com/list/all/all-onclick-0.html").file = "list_newstime.html";
        reloadPlugin();
        LuaValue catS4 = call("getCatalogList", 0);
        check("after restart: cooling primary still skipped (persistent circuit breaker)",
                urlHits("GET https://www.wuxiabox.com/list/all/all-onclick-0.html") == 0
                        && len(catS4.get("items")) == 30);

        // ── T17c: cooldown expiry re-admits the primary (half-open) ────
        System.out.println("\\n== T17c: cooldown expiry ==");
        prefs.put("wuxiabox_site_health", "box=2," + (System.currentTimeMillis() - 1000) + ";spot=0,0");
        reloadPlugin();
        requestedUrls.clear();
        LuaValue catS5 = call("getCatalogList", 0);
        check("expired cooldown: primary retried first (self-healing half-open)",
                urlHits("GET https://www.wuxiabox.com/list/all/all-onclick-0.html") == 1
                        && len(catS5.get("items")) == 30);

        // ── T17d: success resets health ────────────────────────────────
        System.out.println("\\n== T17d: success resets health ==");
        prefs.put("wuxiabox_site_health", "box=1,0;spot=0,0");
        reloadPlugin();
        requestedUrls.clear();
        LuaValue catS6 = call("getCatalogList", 0);
        check("healthy primary serves the catalog", len(catS6.get("items")) == 30);
        String h3 = prefs.get("wuxiabox_site_health");
        check("success resets the fail counter (box=0,0)", h3 != null && h3.contains("box=0,0"), h3);

        // ── T17e: 200-but-junk body is a failure ───────────────────────
        System.out.println("\\n== T17e: 200-but-junk body failover ==");
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        Rule junk200 = on("wuxiabox.com/list/all/all-onclick-0.html");
        junk200.code = 200;
        junk200.body = "<html><head><title>502 Bad Gateway</title></head><body><center><h1>502 Bad Gateway</h1></center></body></html>";
        on("wuxiaspot.com/list/all/all-onclick-0.html").file = "list_newstime.html";
        LuaValue catS7 = call("getCatalogList", 0);
        check("200-but-junk body: failover to the mirror (2.3.0 junk gate)",
                len(catS7.get("items")) == 30 && urlHits("GET https://www.wuxiaspot.com/list/all/all-onclick-0.html") == 1);
        String h4 = prefs.get("wuxiabox_site_health");
        check("junk body charged to primary health", h4 != null && h4.contains("box=1,"), h4);

        // ── T17f: 404 is not a health failure ──────────────────────────
        System.out.println("\\n== T17f: 404 is not a health failure ==");
        prefs.put("wuxiabox_site_health", "box=0,0;spot=0,0");
        reloadPlugin();
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        Rule nf = on("wuxiabox.com/list/all/all-onclick-0.html");
        nf.code = 404; nf.body = "<html>404</html>";
        LuaValue catS8 = call("getCatalogList", 0);
        check("404 → empty result (no items anywhere)", len(catS8.get("items")) == 0);
        String h5 = prefs.get("wuxiabox_site_health");
        check("404 did NOT charge primary health (site answered, page missing)",
                h5 != null && h5.contains("box=0,0"), h5);

        // ── T18: search pagination from a mirror-created searchid ──────
        System.out.println("\\n== T18: mirror-native search pagination ==");
        prefs.put("wuxiabox_site_preference", "spot");
        prefs.put("wuxiabox_site_health", "");
        reloadPlugin();
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        Rule mPost = on("wuxiaspot.com/e/search/index.php");
        mPost.code = 302;
        mPost.headers.put("Location", "/e/search/result?searchid=77");
        on("wuxiaspot.com/e/search/result?searchid=77").file = "searchresult_34.html";
        on("wuxiaspot.com/e/search/result/index.php?page=1&searchid=").file = "searchresult_34.html";
        on("wuxiabox.com/e/search/index.php").code = 302; // must NOT be used
        on("wuxiabox.com/e/search/index.php").headers.put("Location", "/e/search/result?searchid=34");
        on("wuxiabox.com/e/search/result?searchid=34").file = "searchresult_34.html";
        on("wuxiabox.com/e/search/result/index.php?page=1&searchid=34").file = "searchresult_34.html";
        LuaValue mS1 = call("getCatalogSearch", 0, "pokemon");
        check("spot search runs on the mirror",
                len(mS1.get("items")) == 20 && urlHits("POST https://www.wuxiaspot.com/e/search/index.php") == 1);
        check("mirror search URLs canonicalized to wuxiabox.com",
                str(mS1.get("items").get(1), "url").startsWith("https://www.wuxiabox.com/novel/"));
        LuaValue mS2 = call("getCatalogSearch", 1, "pokemon");
        check("page 1 paginates ON THE MIRROR (the searchid's own base, 2.3.0)",
                len(mS2.get("items")) == 20
                        && urlHits("GET https://www.wuxiaspot.com/e/search/result/index.php?page=1&searchid=") >= 1);
        check("primary search pages never touched", urlHits("wuxiabox.com/e/search/result") == 0);

        // ── T19: both sites dead → clear error, mirror tried ───────────
        System.out.println("\\n== T19: both sites dead → clear error ==");
        prefs.put("wuxiabox_site_preference", "auto");
        prefs.put("wuxiabox_chapter_retries", "2");
        prefs.put("wuxiabox_site_health", "");
        reloadPlugin();
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        Rule deadP = on("wuxiabox.com/novel/trxs11010_9.html");
        deadP.code = 502; deadP.body = gateway502;
        Rule deadM = on("wuxiaspot.com/novel/trxs11010_9.html");
        deadM.code = 502; deadM.body = gateway502;
        boolean raisedTotal = false; String totalMsg = "";
        try {
            call("getChapterText", gateway502, "https://www.wuxiabox.com/novel/trxs11010_9.html");
        } catch (LuaError le) {
            raisedTotal = true;
            totalMsg = String.valueOf(le.getMessage());
        }
        check("both sites dead → clear error naming both sites (2.3.0)",
                raisedTotal && totalMsg.contains("wuxiaspot.com"), totalMsg);
        check("rescue tried the mirror too",
                urlHits("GET https://www.wuxiaspot.com/novel/trxs11010_9.html") >= 1);

"""

src = replace_once(
    src,
    """        // ── T14: settings ────────────────────────────────────────────────────
        System.out.println("\\n== T14: getSettingsSchema ==");
""",
    NEW_TESTS + """        // ── T14: settings ────────────────────────────────────────────────────
        System.out.println("\\n== T14: getSettingsSchema ==");
""",
    "new tests insert")

# ── T14: smart-switcher label check ─────────────────────────────────────────
src = replace_once(
    src,
    '        check("defaults: pace=1500 when unset", str(ss.get(4), "current").equals("1500"), str(ss.get(4), "current"));',
    """        check("defaults: pace=1500 when unset", str(ss.get(4), "current").equals("1500"), str(ss.get(4), "current"));
        check("site option 1 label mentions the smart switcher (2.3.0)",
                ss.get(1).get("options").get(1).get("label").tojstring().toLowerCase().contains("smart"),
                ss.get(1).get("options").get(1).get("label").tojstring());""",
    "T14 label check")

with open(PATH, "w", encoding="utf-8") as f:
    f.write(src)

print(f"OK — patched WuxiaboxTest.java: {src.count(chr(10)) + 1} lines")
