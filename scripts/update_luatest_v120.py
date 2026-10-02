#!/usr/bin/env python3
"""Update testenv/LuaTest.java for wtrlab v1.2.0 semantics."""
import re, sys

T = "/home/z/my-project/testenv/LuaTest.java"
src = open(T, encoding="utf-8").read()

def rep(old, new, label):
    global src
    if old not in src:
        print(f"!! MISS: {label}")
        sys.exit(1)
    src = src.replace(old, new, 1)
    print(f"ok: {label}")

# 1. version check
rep('check("version 1.1.9", "1.1.9".equals(plugin.get("version").optjstring("")), plugin.get("version").optjstring("?"));',
    'check("version 1.2.0", "1.2.0".equals(plugin.get("version").optjstring("")), plugin.get("version").optjstring("?"));',
    "version check")

# 2. TEST 2: checkbox groups
rep("""        // v1.1.9: 17 finder filters + 11 "Tags: <category>" dropdown pickers.
        // The 882-chip wall (11 grouped tag TRISTATES) stays gone — the tag
        // pickers are compact selects (one dropdown row each), and the tag
        // list is visible again after 1.1.8's keyword-only fields.
        check("28 filters (17 finder + 11 tag pickers)", nFilters == 28, "n=" + nFilters);""",
    """        // v1.2.0: 17 finder filters + 11 "Tags: <category>" multi-select
        // checkbox chip groups — several tags per category can be picked.
        check("28 filters (17 finder + 11 tag chip groups)", nFilters == 28, "n=" + nFilters);""",
    "TEST 2 header comment")

rep("""        int tagPicks = 0, tagPickOptions = 0;
        boolean allSelectsWithAny = true;
        for (int i = 1; i <= 11; i++) {
            String key = "tag_pick_" + i;
            if (!optionCounts.containsKey(key) || !"select".equals(filterTypes.get(key))) { allSelectsWithAny = false; continue; }
            tagPicks++;
            tagPickOptions += optionCounts.get(key);
        }
        check("11 tag_pick_N dropdowns present (tags visible again)", tagPicks == 11, "found=" + tagPicks);
        // 888 site tags + one "Any" (empty value) option per picker = 899
        check("tag pickers carry 888 tags + 11 Any (899 options)", tagPickOptions == 899, "total=" + tagPickOptions);""",
    """        int tagPicks = 0, tagPickOptions = 0;
        for (int i = 1; i <= 11; i++) {
            String key = "tag_pick_" + i;
            if (!optionCounts.containsKey(key) || !"checkbox".equals(filterTypes.get(key))) continue;
            tagPicks++;
            tagPickOptions += optionCounts.get(key);
        }
        check("11 tag_pick_N checkbox groups present (multi-select per category)", tagPicks == 11, "found=" + tagPicks);
        // 888 site tags, no "Any" placeholder (empty selection = no filter)
        check("tag chip groups carry all 888 tags (no Any placeholders)", tagPickOptions == 888, "total=" + tagPickOptions);""",
    "TEST 2 tag_pick checks")

# remove the Any-first inspection block
any_block = """        // every picker must lead with an "Any" option whose value is ""
        boolean anyFirst = true;
        for (Map.Entry<String, Integer> e : optionCounts.entrySet()) {
            if (!e.getKey().startsWith("tag_pick_")) continue;
            // find the picker in fl again to inspect its first option
            LuaValue kk = LuaValue.NIL;
            outer:
            while (true) {
                Varargs nx = fl.checktable().next(kk);
                if (nx.arg1().isnil()) break;
                kk = nx.arg1();
                LuaTable f = fl.checktable().get(kk).checktable();
                if (!e.getKey().equals(f.get("key").optjstring("?"))) continue;
                LuaTable opts = f.get("options").opttable(new LuaTable());
                if (opts.length() == 0 || !"".equals(opts.get(1).checktable().get("value").optjstring("?"))
                        || !"Any".equals(opts.get(1).checktable().get("label").optjstring("?"))) {
                    anyFirst = false; break outer;
                }
                break;
            }
        }
        check("each tag picker starts with an 'Any' (empty) option", anyFirst);
"""
rep(any_block, "", "Any-first check removal")

# 3. TEST 2b: all-match semantics
rep("""        // ── 2b. Tag Search resolver semantics (v1.1.9, offline) ───────────────
        // Site-autocomplete-like feedback: exact match wins, ids pass through,
        // a single substring match resolves, an AMBIGUOUS keyword raises an
        // error that lists the matching tag names, and "keyword*" includes
        // every substring match at once.""",
    """        // ── 2b. Tag Search resolver semantics (v1.2.0, offline) ───────────────
        // A partial keyword now INCLUDES every matching tag (search-like):
        // "sys" → System + System Misunderstanding + every other tag
        // containing it. Exact match still wins for full names, ids pass
        // through, "keyword*" is an explicit include-all wildcard.""",
    "TEST 2b header")

rep("""            r = resolver.invoke(LuaValue.valueOf("vampir"), LuaValue.valueOf("0")).arg1();
            check("single substring: 'vampir' → [740] (Vampires)", luaIds(r).equals("[740]"), luaIds(r));""",
    """            r = resolver.invoke(LuaValue.valueOf("vampir"), LuaValue.valueOf("0")).arg1();
            check("substring incl. multi-match: 'vampir' → all Vampires* tags", luaIds(r).startsWith("[740") || luaIds(r).contains("740"), luaIds(r));
            r = resolver.invoke(LuaValue.valueOf("sys"), LuaValue.valueOf("0")).arg1();
            check("v1.2.0 all-match: 'sys' → [298,390,696,890] (no ambiguity error)", luaIds(r).equals("[298,390,696,890]"), luaIds(r));""",
    "TEST 2b all-match")

rep("""        // error paths — each must RAISE with a descriptive message
        String[][] errCases = {
            {"sys", "0"},      // ambiguous: lists the 4 matching tag names
            {"zzzqqq", "0"},   // no match at all
            {"zzz*", "0"},     // wildcard with no match
            {"system", "1"},   // valid tag, wrong category
            {"801", "1"}       // valid id, wrong category
        };""",
    """        // error paths — each must RAISE with a descriptive message.
        // (v1.2.0: multiple matches are NO LONGER errors — only zero-match
        // keywords and wrong-category ids raise.)
        String[][] errCases = {
            {"zzzqqq", "0"},   // no match at all
            {"zzz*", "0"},     // wildcard with no match
            {"system", "1"},   // valid tag, wrong category
            {"801", "1"}       // valid id, wrong category
        };""",
    "TEST 2b error cases")

rep("""        // the ambiguous error must LIST the matching tag names (display case)
        try {
            resolver.invoke(LuaValue.valueOf("sys"), LuaValue.valueOf("0")).arg1();
            check("ambiguous error raised", false, "no error");
        } catch (Exception e) {
            String msg = String.valueOf(e.getMessage());
            check("ambiguous error lists tag names in display case",
                    msg.contains("System (#696)") && msg.contains("System Misunderstanding (#890)") && msg.contains("ambiguous"),
                    msg.substring(0, Math.min(160, msg.length())));
        }
""",
    "",
    "ambiguous error check removal")

# 4. TEST 5d: checkbox arrays
rep("""        // ── 5d. v1.1.9: tag_pick dropdown merges with keyword ids ────────────
        System.out.println("\\n=== TEST 5d: getCatalogFiltered (tag_pick_10='801' + tag_search_inc='naruto') ===");
        try {
            LuaTable filters = new LuaTable();
            filters.set("tag_search_inc", LuaValue.valueOf("naruto"));
            filters.set("tag_pick_10", LuaValue.valueOf("801"));   // Honghuang (Adaptations)
            filters.set("tag_pick_1", LuaValue.valueOf("999999")); // junk id from a stale sheet — skipped
            LuaValue r = call("getCatalogFiltered", 0, filters);
            LuaTable items = r.checktable().get("items").opttable(new LuaTable());
            String url = lastUrlFor("novel-finder");
            check("picked + keyword tags merge into one request", items.length() >= 0, "n=" + items.length());
            check("ti= carries keyword id 769 AND picked id 801",
                    url.contains("ti=769,801") || url.contains("ti=801,769"), url);
            check("junk picked id 999999 skipped", !url.contains("999999"), url);
            System.out.println("  url: " + url);
        } catch (Exception e) { check("tag_pick merge no crash", false, e.getMessage()); }""",
    """        // ── 5d. v1.2.0: checkbox chip multi-select merges with keyword ids ──
        System.out.println("\\n=== TEST 5d: getCatalogFiltered (tag_pick_10=[801,769] + tag_search_inc='naruto' + legacy junk) ===");
        try {
            LuaTable filters = new LuaTable();
            filters.set("tag_search_inc", LuaValue.valueOf("naruto"));
            // checkbox group selections arrive as filters["tag_pick_N_included"]
            LuaTable picks10 = new LuaTable();
            picks10.set(1, LuaValue.valueOf("801"));   // Honghuang (Adaptations)
            picks10.set(2, LuaValue.valueOf("769"));   // Naruto (Adaptations)
            filters.set("tag_pick_10_included", picks10);
            LuaTable picks1 = new LuaTable();
            picks1.set(1, LuaValue.valueOf("999999")); // junk id from a stale sheet — skipped
            filters.set("tag_pick_1_included", picks1);
            filters.set("tag_pick_5", LuaValue.valueOf("696")); // v1.1.9 legacy string form — still honored
            LuaValue r = call("getCatalogFiltered", 0, filters);
            LuaTable items = r.checktable().get("items").opttable(new LuaTable());
            String url = lastUrlFor("novel-finder");
            check("chips + keyword + legacy tags merge into one request", items.length() >= 0, "n=" + items.length());
            check("ti= carries keyword id 769 AND both chip ids (801)",
                    url.contains("ti=769,801") || url.contains("ti=801,769"), url);
            check("legacy single-value form (tag_pick_5='696') honored", url.contains("696"), url);
            check("junk picked id 999999 skipped", !url.contains("999999"), url);
            System.out.println("  url: " + url);
        } catch (Exception e) { check("tag_pick merge no crash", false, e.getMessage()); }""",
    "TEST 5d")

# 5. TEST 5e: zero-match error (was: ambiguity error)
rep("""        // ── 5e. v1.1.9: ambiguous keyword surfaces as a clear filter error ──
        // Typing "sys" must NOT silently AND four tags (≈0 novels) — the
        // resolver error propagates so the user sees the matching names.
        System.out.println("\\n=== TEST 5e: getCatalogFiltered (tag_search_inc='sys' → ambiguity error) ===");
        try {
            LuaTable filters = new LuaTable();
            filters.set("tag_search_inc", LuaValue.valueOf("sys"));
            call("getCatalogFiltered", 0, filters);
            check("ambiguous keyword raises", false, "no error raised");
        } catch (Exception e) {
            String msg = String.valueOf(e.getMessage());
            System.out.println("  error: " + msg.substring(0, Math.min(160, msg.length())));
            check("ambiguous keyword error lists matching tags",
                    msg.contains("ambiguous") && msg.contains("System (#696)"), msg);
        }""",
    """        // ── 5e. v1.2.0: a zero-match keyword surfaces as a clear error ──────
        // 'sys' now resolves silently (all matches included); only a keyword
        // matching NOTHING raises, so typos never silently filter nothing.
        System.out.println("\\n=== TEST 5e: getCatalogFiltered (tag_search_inc='zzzqqq' → zero-match error) ===");
        try {
            LuaTable filters = new LuaTable();
            filters.set("tag_search_inc", LuaValue.valueOf("zzzqqq"));
            call("getCatalogFiltered", 0, filters);
            check("zero-match keyword raises", false, "no error raised");
        } catch (Exception e) {
            String msg = String.valueOf(e.getMessage());
            System.out.println("  error: " + msg.substring(0, Math.min(160, msg.length())));
            check("zero-match error is descriptive",
                    msg.contains("no tag name contains"), msg);
        }""",
    "TEST 5e")

open(T, "w", encoding="utf-8").write(src)
print("LuaTest.java updated")
