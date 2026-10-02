#!/usr/bin/env python3
"""Update WuxiaboxTest.java for wuxiabox.lua v2.2.0 expectations."""
import sys

P = "/home/z/my-project/testenv/WuxiaboxTest.java"
src = open(P, encoding="utf-8").read()

def rep(old, new, tag):
    global src
    if old not in src:
        print(f"[MISS] {tag}")
        sys.exit(1)
    if src.count(old) != 1:
        print(f"[DUP] {tag} ({src.count(old)})")
        sys.exit(1)
    src = src.replace(old, new, 1)
    print(f"[ok] {tag}")

# ── T0: version + UA preset ────────────────────────────────────────────────
rep('''        check("version is 2.1.0", globals.get("version").tojstring().equals("2.1.0"), globals.get("version").tojstring());''',
    '''        check("version is 2.2.0", globals.get("version").tojstring().equals("2.2.0"), globals.get("version").tojstring());
        check("getUserAgentPreset registered (2.2.0 CF improvement)", !globals.get("getUserAgentPreset").isnil()
                && call("getUserAgentPreset").tojstring().equals("Chrome Mobile"),
                luaIds(globals.get("getUserAgentPreset")));''',
    "T0 version/UA")

# ── T1: filters — 5 filters, tag_input ─────────────────────────────────────
rep('''        check("6 filters", len(fl) == 6, "got " + len(fl));''',
    '''        check("5 filters (2.2.0: popular_tags + tag_search merged into one tag_input)", len(fl) == 5, "got " + len(fl));''',
    "T1 count")

rep('''        check("popular_tags is a checkbox group (2.1.0)", str(popF, "type").equals("checkbox") && str(popF, "key").equals("popular_tags"), str(popF, "type") + "/" + str(popF, "key"));
        check("popular_tags has 27 options", len(popF.get("options")) == 27, "got " + len(popF.get("options")));''',
    '''        LuaValue tagInF = null;
        for (int i = 1; i <= len(fl); i++) if (str(fl.get(i), "key").equals("tags")) tagInF = fl.get(i);
        check("tags is a tag_input (2.2.0 searchable picker)", tagInF != null && str(tagInF, "type").equals("tag_input"), tagInF == null ? "nil" : str(tagInF, "type"));
        check("tags picker has 756 options (755 curated + honghuang keyword)", tagInF != null && len(tagInF.get("options")) == 756, "got " + (tagInF == null ? "?" : len(tagInF.get("options"))));
        check("tags picker allowCustom=false (options only)", tagInF != null && !tagInF.get("allowCustom").toboolean());''',
    "T1 tag_input")

rep('''        check("popular_tags includes the honghuang family keyword", hasHonghuang);''',
    '''        boolean hasHonghuang2 = false;
        if (tagInF != null) for (int i = 1; i <= len(tagInF.get("options")); i++)
            if (tagInF.get("options").get(i).get("value").tojstring().equals("honghuang")) hasHonghuang2 = true;
        check("tags picker includes the honghuang family keyword", hasHonghuang2);''',
    "T1 honghuang keyword")

rep('''        check("tag_search text filter", str(tagF, "type").equals("text") && str(tagF, "key").equals("tag_search"));''',
    '''        check("tag_search text filter removed (2.2.0 — tag_input replaces it)", tagF.isnil() || !str(tagF, "key").equals("tag_search"));''',
    "T1 no tag_search")

# ── T2: resolver expectations for the curated index ────────────────────────
rep('''        check("'1079,225' resolves both popular-tag ids", len(r2f) == 2, luaIds(r2f));''',
    '''        check("'12,225' resolves both canonical popular-tag ids (2.2.0: 1079 is a duplicate id, not curated)", len(r2f) == 2, luaIds(r2f));''',
    "T2 dup id")

rep('''        LuaValue r2f = call("tagSearchResolve", "1079,225", "");''',
    '''        LuaValue r2f = call("tagSearchResolve", "12,225", "");''',
    "T2 dup id call")

# ── T3: covers via proxy ───────────────────────────────────────────────────
rep('''        check("item cover absolute", str(item0, "cover").startsWith("https://"));''',
    '''        check("item cover routed via wsrv.nl proxy (2.2.0 poster fix)",
                str(item0, "cover").startsWith("https://wsrv.nl/?url=https%3A%2F%2Fwww.wuxiabox.com%2F")
                        && str(item0, "cover").contains("w=450"),
                str(item0, "cover"));''',
    "T3 cover proxy")

# ── T4: search pagination, add total-only + param-order cases ─────────────
rep('''        LuaValue sr2 = call("getCatalogSearch", 1, "pokemon");
        check("search page 1 loads via searchid", len(sr2.get("items")) == 20, "got " + len(sr2.get("items")));
        check("page 1 url used", urlHits("page=1&searchid=34") >= 1);''',
    '''        LuaValue sr2 = call("getCatalogSearch", 1, "pokemon");
        check("search page 1 loads via searchid", len(sr2.get("items")) == 20, "got " + len(sr2.get("items")));
        check("page 1 url used", urlHits("page=1&searchid=34") >= 1);

        // ── T4c: hasNext via total when the next-page LINK is absent ──────
        // (listTotal was dead in 2.1.0 — the Lua pattern could not cross the
        //  newline after <ul class="pagination">. Fixture has the REAL shape.)
        System.out.println("\\n== T4c: search hasNext via 总数 total (listTotal fix) ==");
        String pagerBody = file("searchresult_34.html");
        check("fixture has the real newline-after-ul pager shape",
                pagerBody.contains("<ul class=\\"pagination\\">\\n") || pagerBody.contains("<ul class=\\"pagination\\">\\r\\n"),
                "fixture shape changed?");
        LuaValue tot = call("tagSearchResolve", "34", ""); // warm: unrelated but keeps call() shape honest
        // direct unit-test of listTotal via a synthetic page: 1008 total, NO page links
        Rule totSearch = on("/e/search/result?searchid=777");
        totSearch.body = pagerBody
                .replaceAll("href=\\"/e/search/result/index.php\\?page=[0-9]+&amp;searchid=34\\"", "href=\\"#\\"")
                .replace("<b>37</b>", "<b>1008</b>");
        // (if the fixture total marker differs, fall back to a synthetic pager)
        if (!totSearch.body.contains("1008")) {
            totSearch.body = "<html><body><ul class=\\"novel-list\\">" +
                    "<li class=\\"novel-item\\"><a href=\\"/novel/x1.html\\" title=\\"X1\\"></a></li>" +
                    "</ul><div class=\\"pagination-container\\"><ul class=\\"pagination\\">\\n" +
                    "<a title=\\"总数\\">&#160;<b>1008</b> </a>\\n</ul></div></body></html>";
        }
        Rule totPost = on("/e/search/index.php");
        totPost.bodyMatch = "keyboard=manypages";
        totPost.code = 302;
        totPost.headers.put("Location", "/e/search/result?searchid=777");
        LuaTable manyPick = filt("browse", "catalog");
        LuaValue srT = call("getCatalogSearch", 0, "manypages");
        check("search hasNext=true from the 总数 total alone (dead pattern fixed)", boolOf(srT, "hasNext"));
        LuaValue srT2 = call("getCatalogSearch", 50, "manypages"); // page=50 -> last page (1008/20 -> pages 0..50)
        check("last page hasNext=false via total math", !boolOf(srT2, "hasNext"));''',
    "T4 search + total")

# ── T5/T5b/T6/T7/T7e: filt() with tags_included instead of tag_search ─────
rep('''        LuaValue tg = call("getCatalogFiltered", 0, filt("browse", "catalog", "category", "all", "status", "all", "sort", "newstime", "tag_search", "34", "tag_letter", ""));''',
    '''        LuaTable tgF = filt("browse", "catalog", "category", "all", "status", "all", "sort", "newstime");
        LuaTable tgPicks = new LuaTable(); tgPicks.insert(1, LuaValue.valueOf("34"));
        tgF.set("tags_included", tgPicks);
        LuaValue tg = call("getCatalogFiltered", 0, tgF);''',
    "T7 tag filt")

rep('''        LuaTable fpop = filt("browse", "catalog", "category", "all", "status", "all", "sort", "newstime", "tag_search", "");
        fpop.set("popular_tags_included", picks);
        LuaValue pop = call("getCatalogFiltered", 0, fpop);
        check("popular_tags chips drive a union browse", len(pop.get("items")) == 483, "got " + len(pop.get("items")));''',
    '''        LuaTable fpop = filt("browse", "catalog", "category", "all", "status", "all", "sort", "newstime");
        fpop.set("tags_included", picks);
        LuaValue pop = call("getCatalogFiltered", 0, fpop);
        check("tag_input chips drive a union browse", len(pop.get("items")) == 483, "got " + len(pop.get("items")));''',
    "T7b tags_included")

rep('''        LuaTable fmerge = filt("browse", "catalog", "category", "all", "status", "all", "sort", "newstime", "tag_search", "34");
        LuaTable picks2 = new LuaTable();
        picks2.insert(1, LuaValue.valueOf("225"));
        fmerge.set("popular_tags_included", picks2);
        LuaValue merged = call("getCatalogFiltered", 0, fmerge);
        check("chips + keywords merge into one union browse (dedup)", len(merged.get("items")) == 483, "got " + len(merged.get("items")));
        check("both tag listings requested (34 via keyword, 225 via chip)", urlHits("/tags/34-0.html") >= 1 && urlHits("/tags/225-0.html") >= 1);''',
    '''        LuaTable fmerge = filt("browse", "catalog", "category", "all", "status", "all", "sort", "newstime");
        LuaTable picks2 = new LuaTable();
        picks2.insert(1, LuaValue.valueOf("34"));
        picks2.insert(2, LuaValue.valueOf("225"));
        picks2.insert(3, LuaValue.valueOf("honghuang")); // family keyword chip
        fmerge.set("tags_included", picks2);
        LuaValue merged = call("getCatalogFiltered", 0, fmerge);
        check("multi-chip union browse (34 + 225 + honghuang family)", len(merged.get("items")) == 483, "got " + len(merged.get("items")));
        check("tag listings requested for every chip", urlHits("/tags/34-0.html") >= 1 && urlHits("/tags/225-0.html") >= 1 && urlHits("/tags/5779-0.html") >= 1);''',
    "T7c merge")

# ── T7d: consistency over the tag_input options ────────────────────────────
rep('''        System.out.println("\\n== T7d: popular_tags id/label consistency ==");
        boolean allCanonical = true;
        String canonicalFail = "";
        for (int i = 1; i <= len(popF.get("options")); i++) {
            String val = popF.get("options").get(i).get("value").tojstring();
            String label = popF.get("options").get(i).get("label").tojstring();''',
    '''        System.out.println("\\n== T7d: tags picker id/label consistency (all 756 options) ==");
        boolean allCanonical = true;
        String canonicalFail = "";
        for (int i = 1; i <= len(tagInF.get("options")); i++) {
            String val = tagInF.get("options").get(i).get("value").tojstring();
            String label = tagInF.get("options").get(i).get("label").tojstring();''',
    "T7d loop")

# ── T7e: tags_included marshalling ─────────────────────────────────────────
rep('''        LuaValue tgFail = call("getCatalogFiltered", 0, filt("browse", "catalog", "category", "all", "status", "all", "sort", "newstime", "tag_search", "34"));''',
    '''        LuaTable tgFailF = filt("browse", "catalog", "category", "all", "status", "all", "sort", "newstime");
        LuaTable tgFailPicks = new LuaTable(); tgFailPicks.insert(1, LuaValue.valueOf("34"));
        tgFailF.set("tags_included", tgFailPicks);
        LuaValue tgFail = call("getCatalogFiltered", 0, tgFailF);''',
    "T7e filt")

# ── T8: cover assertions (proxy) ───────────────────────────────────────────
rep('''        LuaValue bc = call("getBookCoverImageUrl", NOVEL);
        check("cover url", bc.tojstring().contains("/d/file/cover123/"), bc.tojstring());''',
    '''        LuaValue bc = call("getBookCoverImageUrl", NOVEL);
        check("cover url via wsrv.nl proxy with the site path encoded",
                bc.tojstring().startsWith("https://wsrv.nl/?url=https%3A%2F%2Fwww.wuxiabox.com%2Fd%2Ffile%2Fcover123%2F")
                        && bc.tojstring().contains("w=450") && bc.tojstring().contains("output=jpg"),
                bc.tojstring());''',
    "T8 cover proxy")

rep('''        LuaValue bc2 = call("getBookCoverImageUrl", "https://www.wuxiabox.com/novel/synthetic-cover.html");
        check(".cover img fallback when figure.cover is absent", bc2.tojstring().contains("/d/file/"), bc2.tojstring());''',
    '''        LuaValue bc2 = call("getBookCoverImageUrl", "https://www.wuxiabox.com/novel/synthetic-cover.html");
        check(".cover img fallback when figure.cover is absent (proxy keeps the path)", bc2.tojstring().contains("%2Fd%2Ffile%2F"), bc2.tojstring());
        // ── T8d: direct mode (covers setting) ─────────────────────────────
        prefs.put("wuxiabox_covers", "direct");
        LuaValue bcd = call("getBookCoverImageUrl", NOVEL);
        check("direct cover mode returns the bare site url", bcd.tojstring().startsWith("https://www.wuxiabox.com/d/file/cover123/"), bcd.tojstring());
        prefs.put("wuxiabox_covers", "proxy");
        LuaValue bcp = call("getBookCoverImageUrl", NOVEL);
        check("proxy cover mode back on", bcp.tojstring().startsWith("https://wsrv.nl/"), bcp.tojstring());
        prefs.remove("wuxiabox_covers");''',
    "T8c/T8d covers")

# ── T14: settings (4 entries) ──────────────────────────────────────────────
rep('''        check("3 settings (site preference added, 2.1.0)", len(ss) == 3, "got " + len(ss));
        check("site setting present and first", str(ss.get(1), "key").equals("wuxiabox_site_preference"), str(ss.get(1), "key"));
        check("retry setting present", str(ss.get(2), "key").equals("wuxiabox_chapter_retries"));
        check("pace setting present", str(ss.get(3), "key").equals("wuxiabox_chapter_pace_ms"));
        check("defaults: site=auto when unset", str(ss.get(1), "current").equals("auto"), str(ss.get(1), "current"));
        check("defaults: retries=4", str(ss.get(2), "current").equals("4"), str(ss.get(2), "current"));
        check("defaults: pace=1500 when unset", str(ss.get(3), "current").equals("1500"), str(ss.get(3), "current"));''',
    '''        check("4 settings (covers added, 2.2.0)", len(ss) == 4, "got " + len(ss));
        check("site setting present and first", str(ss.get(1), "key").equals("wuxiabox_site_preference"), str(ss.get(1), "key"));
        check("covers setting present (2.2.0)", str(ss.get(2), "key").equals("wuxiabox_covers"), str(ss.get(2), "key"));
        check("retry setting present", str(ss.get(3), "key").equals("wuxiabox_chapter_retries"));
        check("pace setting present", str(ss.get(4), "key").equals("wuxiabox_chapter_pace_ms"));
        check("defaults: site=auto when unset", str(ss.get(1), "current").equals("auto"), str(ss.get(1), "current"));
        check("defaults: covers=proxy (posters fix)", str(ss.get(2), "current").equals("proxy"), str(ss.get(2), "current"));
        check("defaults: retries=4", str(ss.get(3), "current").equals("4"), str(ss.get(3), "current"));
        check("defaults: pace=1500 when unset", str(ss.get(4), "current").equals("1500"), str(ss.get(4), "current"));''',
    "T14 settings")

# ── T5/T5b/T6 filt cleanup (drop dead tag_search/tag_letter keys) ──────────
src = src.replace('''filt("category", "comedy", "status", "all", "sort", "newstime", "browse", "catalog", "tag_search", "", "tag_letter", "")''',
                  '''filt("category", "comedy", "status", "all", "sort", "newstime", "browse", "catalog")''')
src = src.replace('''filt("category", "comedy", "status", "Completed", "sort", "newstime", "browse", "catalog", "tag_search", "", "tag_letter", "")''',
                  '''filt("category", "comedy", "status", "Completed", "sort", "newstime", "browse", "catalog")''')
src = src.replace('''filt("browse", "updates", "category", "all", "status", "all", "sort", "newstime", "tag_search", "", "tag_letter", "")''',
                  '''filt("browse", "updates", "category", "all", "status", "all", "sort", "newstime")''')
print("[ok] filt cleanup (x3)")

open(P, "w", encoding="utf-8").write(src)
print("written", P)
