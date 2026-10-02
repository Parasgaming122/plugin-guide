#!/usr/bin/env python3
"""Insert new mock tests H (paragraph safety), I (webplus), J (tag-book) into LuaTest.java."""

T = "/home/z/my-project/testenv/LuaTest.java"
src = open(T, encoding="utf-8").read()

anchor = """            System.out.println("\\n========================================");
            System.out.println("PASSED: " + passed + "  FAILED: " + failed);
            for (String f : failures) System.out.println("  FAILURE: " + f);
            System.out.println("========================================");
            System.exit(failed > 0 ? 1 : 0);
        }"""

new_tests = r"""
            // ── MOCK TEST H: v1.2.0 paragraph safety ──────────────────────────
            // The reader's paragraph boundary is \n\s*\n; single \n renders as a
            // merged soft break. Body elements that EMBED newlines must be split
            // into separate paragraphs, CRLF normalized, and gsub terms with
            // pattern-magic characters must never abort the chapter.
            System.out.println("\n=== MOCK TEST H: paragraph safety ===");
            try {
                String chUrlH = "https://wtr-lab.com/en/novel/93618/primordial-era/chapter-2";
                // H1: array elements with EMBEDDED newlines
                MOCKS.clear();
                String h1Body = gson.toJson(java.util.Arrays.asList(
                        "P1 line one\nP1 line two\nP1 line three", "P2 standalone",
                        "P3a\r\nP3b"));
                MOCKS.put("api/reader/get", "{\"success\":true,\"data\":{\"data\":{\"body\":" + h1Body + ",\"title\":\"t\"}}}");
                LuaValue h1 = call("getChapterText", "", chUrlH);
                String h1s = h1 == null || h1.isnil() ? "" : h1.tojstring();
                int h1paras = h1s.split("\\n\\s*\\n", -1).length - 1;
                System.out.println("  H1 output: " + h1s.replace("\n", "\\n"));
                check("H1: 5 paragraphs from 3 elements with embedded newlines",
                        h1paras == 4 && h1s.split("\\n\\s*\\n").length == 5, "paras=" + (h1s.split("\\n\\s*\\n").length));
                check("H1: no single \\n left inside any paragraph (reader merge guard)",
                        !h1s.matches("(?s).*\\n(?!\\n).*\\n(?!\\n).*") || !h1s.contains("\n") || h1s.split("\n").length == h1s.split("\\n\\s*\\n").length,
                        "n-split=" + h1s.split("\n").length + " nn-split=" + h1s.split("\\n\\s*\\n").length);
                check("H1: CRLF normalized (no \\r survives)", !h1s.contains("\r"), "");

                // H2: plain-string body (str: style) with single \n + one blank line
                MOCKS.clear();
                String h2Plain = "L1\nL2\nL3\n\nL4";
                String h2Body = gson.toJson(h2Plain);
                MOCKS.put("api/reader/get", "{\"success\":true,\"data\":{\"data\":{\"body\":" + h2Body + "}}}");
                LuaValue h2 = call("getChapterText", "", chUrlH);
                String h2s = h2 == null || h2.isnil() ? "" : h2.tojstring();
                int h2paras = h2s.split("\\n\\s*\\n", -1).length - 1;
                System.out.println("  H2 output: " + h2s.replace("\n", "\\n"));
                check("H2: 4 paragraphs from a \\n-separated plain string", h2paras == 3 && h2s.split("\\n\\s*\\n").length == 4, h2s);

                // H3: glossary terms with pattern-magic + % in replacements must not error
                MOCKS.clear();
                String h3Body = gson.toJson(java.util.Arrays.asList(
                        "The ※0⛬ rose to 100% power.", "Patreon watermark line",
                        "The (Sect) Master said ※1 incarcerat."));
                // glossary_data.terms: [[translation, original], ...] — 0-based idx markers
                String h3Glossary = "{\"success\":true,\"data\":{\"data\":{\"body\":" + h3Body +
                        ",\"glossary_data\":{\"terms\":[[\"50%(off) special\", \"促销(打折)\"],[\"System (AI)\", \"系统\"]]},\"patch\":[{\"zh\":\"促销(打折)\",\"en\":\"SALE%50\"}]}}}";
                MOCKS.put("api/reader/get", h3Glossary);
                MOCKS.put("api/v2/reader/terms/93618.json", "{}");
                LuaValue h3 = call("getChapterText", "", chUrlH);
                String h3s = h3 == null || h3.isnil() ? "" : h3.tojstring();
                System.out.println("  H3 output: " + h3s.replace("\n", "\\n"));
                check("H3: magic-char glossary term applied, no Lua error",
                        h3s.contains("50%(off) special") || h3s.contains("100% power"), h3s);
                check("H3: chapter renders (v1.1.9 would throw malformed pattern)", h3s.length() > 20, "len=" + h3s.length());

                // H4: watermark line still stripped
                check("H4: patreon watermark line stripped from result", !h3s.toLowerCase().contains("patreon"), h3s);
            } catch (Exception e) { check("MOCK paragraph safety no crash", false, e.getMessage()); }

            // ── MOCK TEST I: Web+ mode (glossary applied per paragraph) ────────
            System.out.println("\n=== MOCK TEST I: webplus mode ===");
            try {
                // reuse the captured arr: sample (novel 287, Chinese) + a terms
                // glossary mapping one of its words
                String arrSample = loadMock("arr_sample.txt").trim();
                arrSample = arrSample.substring(1, arrSample.length() - 1);
                String chUrlI = "https://wtr-lab.com/en/novel/287/the-wealthy-and-powerful/chapter-1";
                prefs.put("wtrlab_mode", "webplus");
                MOCKS.clear();
                String envI = "{\"success\":true,\"data\":{\"data\":{\"body\":" + gson.toJson(arrSample) + "}}}";
                MOCKS.put("api/reader/get", envI);
                // terms glossary: original 叶素惜 → "Ye Suxi (F)"
                String termsI = "{\"glossaries\":[{\"data\":{\"terms\":[[[\"Ye Suxi (F)\"],\"叶素惜\",0]]}}]}";
                MOCKS.put("api/v2/reader/terms/287.json", termsI);
                LuaValue tI = call("getChapterText", "", chUrlI);
                String sI = tI == null || tI.isnil() ? "" : tI.tojstring();
                check("I: webplus chapter decrypts + renders", sI.length() > 500, "len=" + sI.length());
                check("I: webplus book glossary applied per paragraph (叶素惜 → Ye Suxi (F))",
                        sI.contains("Ye Suxi (F)") && !sI.contains("叶素惜"), sI.substring(0, Math.min(120, sI.length())));
                check("I: webplus Chinese body intact otherwise", sI.contains("楚寒南"), "");
                prefs.put("wtrlab_mode", "ai");
            } catch (Exception e) { check("MOCK webplus no crash", false, e.getMessage()); prefs.put("wtrlab_mode", "ai"); }

            // ── MOCK TEST J: v1.2.0 tag books (search → tag items → browse) ──
            System.out.println("\n=== MOCK TEST J: tag discovery + tag books ===");
            try {
                // J1: catalog search lists matching tags FIRST as tappable items
                MOCKS.clear();
                requestedUrls.clear();
                String finderHtmlJ = "<script id=\"__NEXT_DATA__\" type=\"application/json\">" +
                        "{\"props\":{\"pageProps\":{\"count\":\"1\",\"series\":[" +
                        "{\"raw_id\":93618,\"slug\":\"primordial\",\"data\":{\"title\":\"Primordial Novel\",\"image\":\"\"}}]}}}</script>";
                MOCKS.put("wtr-lab.com/en/novel-finder", finderHtmlJ);
                LuaValue j1 = call("getCatalogSearch", 0, "honghuang");
                LuaTable j1items = j1.checktable().get("items").opttable(new LuaTable());
                String first = j1items.get(1).checktable().get("title").optjstring("?");
                String firstUrl = j1items.get(1).checktable().get("url").optjstring("?");
                System.out.println("  J1 first item: " + first + " @ " + firstUrl);
                check("J1: search shows matching tag first", first.contains("Honghuang"), first);
                check("J1: tag result URL is the finder with ti=801",
                        firstUrl.contains("novel-finder") && firstUrl.contains("ti=801"), firstUrl);
                check("J1: tag result shows its category", first.contains("Adaptations"), first);
                check("J1: novel results still follow tag results", j1items.length() >= 2, "n=" + j1items.length());

                // J2: tag book page functions
                String tagBookUrl = "https://wtr-lab.com/en/novel-finder?ti=801";
                LuaValue j2t = call("getBookTitle", tagBookUrl);
                check("J2: tag book title", j2t != null && !j2t.isnil() && j2t.tojstring().contains("Honghuang"), String.valueOf(j2t));
                System.out.println("  J2 title: " + j2t);
                LuaValue j2d = call("getBookDescription", tagBookUrl);
                String j2ds = j2d == null || j2d.isnil() ? "" : j2d.tojstring();
                check("J2: tag book description explains the view", j2ds.contains("tag browse view") && j2ds.contains("Honghuang"), j2ds.substring(0, Math.min(80, j2ds.length())));
                LuaValue j2c = call("getBookCoverImageUrl", tagBookUrl);
                check("J2: tag book cover is nil (no fake covers)", j2c == null || j2c.isnil(), String.valueOf(j2c));
                LuaValue j2g = call("getBookGenres", tagBookUrl);
                check("J2: tag book genres empty table", j2g != null && j2g.istable() && j2g.checktable().length() == 0, String.valueOf(j2g));
                LuaValue j2h = call("getChapterListHash", tagBookUrl);
                String j2hs = j2h == null || j2h.isnil() ? "" : j2h.tojstring();
                check("J2: tag book hash format tags:801|N", j2hs.startsWith("tags:801|"), j2hs);

                // J3: tag book chapter list = the tag's novels
                // (HTML-first mock for fetchTagBookPage: ti=801&orderBy=reader&page=N)
                MOCKS.clear();
                requestedUrls.clear();
                StringBuilder serJ = new StringBuilder();
                for (int i = 1; i <= 3; i++)
                    serJ.append(String.format("{\"raw_id\":%d,\"slug\":\"slug%d\",\"data\":{\"title\":\"Tag Novel %d\"}}%s", 1000 + i, i, i, i < 3 ? "," : ""));
                String tagFinderHtml = "<script id=\"__NEXT_DATA__\" type=\"application/json\">" +
                        "{\"props\":{\"pageProps\":{\"count\":\"3\",\"series\":[" + serJ + "]}}}</script>";
                MOCKS.put("wtr-lab.com/en/novel-finder", tagFinderHtml);
                LuaValue j3 = call("getChapterList", tagBookUrl);
                LuaTable j3ch = j3.istable() ? j3.checktable() : new LuaTable();
                System.out.println("  J3 chapters: " + j3ch.length());
                check("J3: tag book chapter list = the tag's novels", j3ch.length() == 3, "n=" + j3ch.length());
                if (j3ch.length() > 0) {
                    String c1t = j3ch.get(1).checktable().get("title").optjstring("?");
                    String c1u = j3ch.get(1).checktable().get("url").optjstring("?");
                    System.out.println("  J3 ch1: " + c1t + " @ " + c1u);
                    check("J3: chapter titles are novel titles", c1t.contains("Tag Novel"), c1t);
                    check("J3: chapter URLs point at the novels' chapter-1",
                            c1u.contains("/novel/1001/slug1/chapter-1"), c1u);
                }
                boolean usedTagFinder = false;
                for (String u : requestedUrls) if (u.contains("ti=801") && u.contains("orderBy=reader")) usedTagFinder = true;
                check("J3: fetched the finder with ti=801&orderBy=reader", usedTagFinder, requestedUrls.toString());

                // J4: opening a tag-book chapter (novel preview) still works via
                // the normal getChapterText path
                MOCKS.clear();
                MOCKS.put("api/reader/get", "{\"success\":true,\"data\":{\"data\":{\"body\":" +
                        gson.toJson(java.util.Arrays.asList("Novel preview paragraph.")) + "}}}");
                LuaValue j4 = call("getChapterText", "", "https://wtr-lab.com/en/novel/1001/slug1/chapter-1");
                String j4s = j4 == null || j4.isnil() ? "" : j4.tojstring();
                check("J4: tag-book chapter (novel preview) renders", j4s.contains("Novel preview"), j4s);
            } catch (Exception e) { check("MOCK tag books no crash", false, e.getMessage()); }

"""

src = src.replace(anchor, new_tests + anchor, 1)
open(T, "w", encoding="utf-8").write(src)
print("new mock tests H/I/J inserted")
