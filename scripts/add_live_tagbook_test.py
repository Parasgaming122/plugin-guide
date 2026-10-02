#!/usr/bin/env python3
"""Insert live tag-book end-to-end test (TEST 11) into LuaTest.java live mode."""

T = "/home/z/my-project/testenv/LuaTest.java"
src = open(T, encoding="utf-8").read()

anchor = """        // ── Summary ────────────────────────────────────────────────────────────
        System.out.println("\\n========================================");
        System.out.println("PASSED: " + passed + "  FAILED: " + failed);"""

live_test = r"""
        // ── 11. LIVE tag-book end-to-end: search → tag item → browse novels ──
        System.out.println("\n=== TEST 11: tag discovery + tag book (live) ===");
        try {
            LuaValue sr = call("getCatalogSearch", 0, "honghuang");
            LuaTable sItems = sr.checktable().get("items").opttable(new LuaTable());
            String tagItemUrl = null;
            for (int i = 1; i <= Math.min(3, sItems.length()); i++) {
                String t = sItems.get(i).checktable().get("title").optjstring("");
                System.out.println("  search item " + i + ": " + t);
                if (t.contains("\uD83C\uDFF7") && t.contains("Honghuang")) {
                    tagItemUrl = sItems.get(i).checktable().get("url").optjstring("");
                }
            }
            check("11: search lists the Honghuang tag result", tagItemUrl != null, "first items: " +
                    (sItems.length() > 0 ? sItems.get(1).checktable().get("title").optjstring("?") : "none"));
            if (tagItemUrl != null) {
                System.out.println("  tag url: " + tagItemUrl);
                LuaValue bt = call("getBookTitle", tagItemUrl);
                System.out.println("  tag book title: " + bt);
                check("11: tag book title contains Honghuang", bt != null && !bt.isnil() && bt.tojstring().contains("Honghuang"), String.valueOf(bt));
                LuaValue bd = call("getBookDescription", tagItemUrl);
                String bds = bd == null || bd.isnil() ? "" : bd.tojstring();
                check("11: tag book description (novel count from live finder)",
                        bds.contains("tag browse view") && bds.matches("(?s).*\\(\\d+ novels total\\).*"), bds.substring(0, Math.min(100, bds.length())));
                LuaValue bh = call("getChapterListHash", tagItemUrl);
                System.out.println("  tag book hash: " + bh);
                check("11: tag book hash = tags:801|N", bh != null && !bh.isnil() && bh.tojstring().startsWith("tags:801"), String.valueOf(bh));
                LuaValue cl = call("getChapterList", tagItemUrl);
                int nCh = cl != null && cl.istable() ? cl.checktable().length() : 0;
                System.out.println("  tag book chapters: " + nCh);
                check("11: tag book chapter list has novels (live)", nCh > 0, "n=" + nCh);
                if (nCh > 0) {
                    String c1t = cl.checktable().get(1).checktable().get("title").optjstring("?");
                    String c1u = cl.checktable().get(1).checktable().get("url").optjstring("?");
                    System.out.println("  ch1: " + c1t + " @ " + c1u);
                    check("11: chapters are novels with chapter-1 preview urls",
                            c1u.matches("https://wtr-lab\\.com/en/novel/\\d+/[^/]+/chapter-1"), c1u);
                }
            }
        } catch (Exception e) { check("tag book live no crash", false, e.getMessage()); }

"""

src = src.replace(anchor, live_test + anchor, 1)
open(T, "w", encoding="utf-8").write(src)
print("TEST 11 (live tag book) inserted")
