import org.jsoup.Jsoup;
import org.jsoup.nodes.Element;
import org.luaj.vm2.*;
import org.luaj.vm2.lib.*;
import java.nio.file.*;
import java.util.*;

/**
 * S69RealSeed — v1.3.0 REAL-DATA end-to-end proof. Every input is a live
 * capture of 69shuba.tw (fetched 2026-09-26 through the clean-IP translate
 * proxy, de-proxied by scripts/gen_69shubatw_v130_fixtures.py):
 *   /Indexlist/342441/{1..5}/  the real 450-chapter catalog (5 pages × 100,
 *                              98 anchors + 2 protected spans per page)
 *   /book/342441/              the real book page
 *   /read/342441/890315,890316 the real chapters 1-2 (890316 is a
 *                              protected-chapter-link chapter)
 * Flow: book details → parsePage(1..5) → getChapterList → getChapterText.
 */
public class S69RealSeed {
    static Map<String, String> prefs = new HashMap<>();
    static List<String> fetched = new ArrayList<>();
    static final String FIX = "/home/z/my-project/research/69shubatw/fixtures/";

    static int pass = 0, fail = 0;
    static void check(boolean cond, String name) {
        if (cond) { pass++; System.out.println("  PASS  " + name); }
        else { fail++; System.out.println("  FAIL  " + name); }
    }

    static HttpResp http(String url) {
        HttpResp r = new HttpResp();
        // real catalog pages (capital I) + real book + real chapters
        String file = null;
        if (url.equals("https://69shuba.tw/Indexlist/342441/")) file = "idx_p1.html";
        else if (url.equals("https://69shuba.tw/Indexlist/342441/2/")) file = "idx_p2.html";
        else if (url.equals("https://69shuba.tw/Indexlist/342441/3/")) file = "idx_p3.html";
        else if (url.equals("https://69shuba.tw/Indexlist/342441/4/")) file = "idx_p4.html";
        else if (url.equals("https://69shuba.tw/Indexlist/342441/5/")) file = "idx_p5.html";
        else if (url.contains("/book/342441")) file = "book_342441.html";
        else if (url.contains("/read/342441/890315")) file = "chapter_1.html";
        else if (url.contains("/read/342441/890316")) file = "chapter_2.html";
        if (file != null) {
            try {
                r.success = true; r.code = 200;
                r.body = new String(Files.readAllBytes(Paths.get(FIX + file)), "UTF-8");
                return r;
            } catch (Exception e) { }
        }
        // everything else (incl. any lowercase /indexlist/ attempt) = the real
        // EdgeOne challenge capture, 403
        r.success = false; r.code = 403;
        try { r.body = new String(Files.readAllBytes(Paths.get(FIX + "idx_chal.html")), "UTF-8"); }
        catch (Exception e) { r.body = "blocked"; }
        return r;
    }

    static class HttpResp { boolean success; String body; int code; }

    public static void main(String[] args) throws Exception {
        Globals g = org.luaj.vm2.lib.jse.JsePlatform.standardGlobals();
        g.set("http_get", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2) {
                String url = a1.checkjstring();
                fetched.add(url);
                HttpResp r = http(url);
                LuaTable t = new LuaTable();
                t.set("success", LuaValue.valueOf(r.success));
                t.set("body", LuaValue.valueOf(r.body));
                t.set("code", LuaValue.valueOf(r.code));
                t.set("headers", new LuaTable());
                return t;
            }
        });
        g.set("http_post", new ZeroArgFunction() {
            @Override public LuaValue call() { LuaTable t = new LuaTable(); t.set("success", LuaValue.valueOf(false)); return t; }
        });
        g.set("get_preference", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) { return LuaValue.valueOf(prefs.getOrDefault(a.checkjstring(), "")); }
        });
        g.set("set_preference", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a, LuaValue b) { prefs.put(a.checkjstring(), b.tojstring()); return LuaValue.NIL; }
        });
        g.set("os_time", new ZeroArgFunction() {
            @Override public LuaValue call() { return LuaValue.valueOf((double) System.currentTimeMillis()); }
        });
        g.set("url_encode", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) { return LuaValue.valueOf(a.checkjstring().replace(" ", "%20")); }
        });
        g.set("url_resolve", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2) { return LuaValue.valueOf(a2.checkjstring()); }
        });
        g.set("log_info", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) { return LuaValue.NIL; }
        });
        g.set("log_error", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) { return LuaValue.NIL; }
        });
        g.set("show_error", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a, LuaValue b) { System.out.println("SHOW_ERROR: " + a.tojstring()); return LuaValue.NIL; }
        });
        g.set("html_select", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue body, LuaValue sel) {
                LuaTable out = new LuaTable();
                for (Element el : Jsoup.parse(body.checkjstring()).select(sel.checkjstring()))
                    out.set(out.len().toint() + 1, elementTable(el));
                return out;
            }
        });
        g.set("html_select_first", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue body, LuaValue sel) {
                Element el = Jsoup.parse(body.checkjstring()).select(sel.checkjstring()).first();
                return el == null ? LuaValue.NIL : elementTable(el);
            }
        });
        g.set("html_attr", new ThreeArgFunction() {
            @Override public LuaValue call(LuaValue body, LuaValue sel, LuaValue attr) {
                Element el = Jsoup.parse(body.checkjstring()).select(sel.checkjstring()).first();
                return (el == null || !el.hasAttr(attr.checkjstring())) ? LuaValue.NIL : LuaValue.valueOf(el.attr(attr.checkjstring()));
            }
        });
        g.set("html_text", new OneArgFunction() {
            @Override public LuaValue call(LuaValue body) { return LuaValue.valueOf(Jsoup.parse(body.checkjstring()).text()); }
        });
        g.set("string_clean", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) {
                String s = a.checkjstring().replaceAll("[\\s\\u00A0\\u3000]+", " ").trim();
                return LuaValue.valueOf(s);
            }
        });
        g.set("string_trim", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) { return LuaValue.valueOf(a.checkjstring().trim()); }
        });
        g.set("string_starts_with", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a, LuaValue b) {
                return LuaValue.valueOf(a.checkjstring().startsWith(b.checkjstring()));
            }
        });
        g.set("json_parse", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) { return new LuaTable(); }
        });

        g.load(new java.io.FileReader("/home/z/my-project/download/69shubaTw.lua"), "69shubaTw.lua").call();

        String BOOK = "https://69shuba.tw/book/342441/";

        System.out.println("== R1 book details (real /book/ page) ==");
        LuaValue title = g.get("getBookTitle").call(LuaValue.valueOf(BOOK));
        check("大明：老四，帶咱一起修仙！".equals(title.tojstring()), "real title: " + title.tojstring());
        LuaValue cov = g.get("getBookCoverImageUrl").call(LuaValue.valueOf(BOOK));
        check(cov.tojstring().equals("https://p.69shuba.tw/342/342441/342441s.jpg"), "real cover URL");

        System.out.println("== R2 catalog pages (real /Indexlist/ captures) ==");
        LuaValue pp = g.get("parsePage").call(LuaValue.valueOf(BOOK), LuaValue.valueOf(1));
        check(pp.istable(), "parsePage(1) → table");
        LuaTable t = pp.checktable();
        LuaTable chs = t.get("chapters").checktable();
        check(chs.len().toint() == 100, "page 1 = 100 real chapters: " + chs.len().toint());
        check(t.get("totalPages").toint() == 5, "totalPages = 5");
        check(chs.get(1).checktable().get("title").tojstring().equals("第1章 簽到！神獸蛋！"),
            "ch1 real title: " + chs.get(1).checktable().get("title").tojstring());
        check(chs.get(2).checktable().get("title").tojstring().equals("第2章 被逼婚離家出走的老四"),
            "ch2 (protected-chapter-link span) real title: " + chs.get(2).checktable().get("title").tojstring());
        check(fetched.size() >= 1 && fetched.get(fetched.size() - 1).equals("https://69shuba.tw/Indexlist/342441/"),
            "capital-I URL used: " + (fetched.isEmpty() ? "-" : fetched.get(fetched.size() - 1)));

        System.out.println("== R3 full TOC via getChapterList (450 real chapters) ==");
        LuaTable toc = g.get("getChapterList").call(LuaValue.valueOf(BOOK)).checktable();
        check(toc.len().toint() == 450, "450 chapters total: " + toc.len().toint());
        check(toc.get(1).checktable().get("title").tojstring().equals("第1章 簽到！神獸蛋！"), "starts at 第1章");
        String last = toc.get(450).checktable().get("title").tojstring();
        check(last.equals("第450章 老怪甦醒，大明的星門計劃"), "ends at real 第450章: " + last);
        boolean ascending = true; long prev = 0;
        for (int i = 1; i <= toc.len().toint(); i++) {
            long cid = Long.parseLong(toc.get(i).checktable().get("url").tojstring().replaceAll(".*/", ""));
            if (cid <= prev) ascending = false; prev = cid;
        }
        check(ascending, "cids ascending across all 5 real pages");
        int lowerTries = 0;
        for (String u : fetched) if (u.contains("/indexlist/")) lowerTries++;
        check(lowerTries == 0, "ZERO lowercase /indexlist/ requests (WAF path never touched): " + lowerTries);
        int capitalFetches = 0;
        for (String u : fetched) if (u.contains("/Indexlist/342441/")) capitalFetches++;
        check(capitalFetches == 5, "exactly 5 capital-I catalog fetches (one per page): " + capitalFetches);

        System.out.println("== R4 chapter text (real chapter pages) ==");
        // ch1 (normal anchor chapter)
        HttpResp c1 = http("https://69shuba.tw/read/342441/890315");
        LuaValue txt1 = g.get("getChapterText").call(LuaValue.valueOf(c1.body), LuaValue.valueOf("https://69shuba.tw/read/342441/890315"));
        String s1 = txt1.tojstring();
        check(s1.contains("永樂十二年，極北之地，萬年冰封。"), "ch1 real first paragraph");
        check(!s1.contains("69shuba.tw") || !s1.lines().anyMatch(l -> l.length() < 80 && l.contains("69shuba")), "ch1 watermarks stripped");
        // ch2 (the protected-span chapter — proves protected chapters are readable)
        HttpResp c2 = http("https://69shuba.tw/read/342441/890316");
        LuaValue txt2 = g.get("getChapterText").call(LuaValue.valueOf(c2.body), LuaValue.valueOf("https://69shuba.tw/read/342441/890316"));
        String s2 = txt2.tojstring();
        check(s2.contains("坤寧宮內，死寂沉沉"), "ch2 (protected) real first paragraph");
        check(s2.length() > 200, "ch2 substantial content: " + s2.length() + " chars");

        System.out.println("== R5 lowercase /indexlist/ fallback: NEVER attempted ==");
        // a book whose capital path fails: exactly ONE attempt then guided error
        String BOOK2 = "https://69shuba.tw/book/555555/";
        LuaValue ppX = g.get("parsePage").call(LuaValue.valueOf(BOOK2), LuaValue.valueOf(1));
        int before = fetched.size();
        ppX = g.get("parsePage").call(LuaValue.valueOf(BOOK2), LuaValue.valueOf(1));
        check(ppX.istable() && ppX.checktable().get("chapters").checktable().len().toint() == 0,
            "unknown book → empty table, never nil");
        check(fetched.size() - before == 1, "one retry attempt per parsePage(1) call (no storm): " + (fetched.size() - before));

        System.out.println("\nREAL-DATA RESULT: " + pass + " PASS, " + fail + " FAIL");
        if (fail > 0) System.exit(1);
    }

    static LuaTable elementTable(Element el) {
        LuaTable tab = new LuaTable();
        tab.set("__element", new LuaUserdata(el));
        LuaTable mt = new LuaTable();
        mt.set(LuaValue.INDEX, new TwoArgFunction() {
            @Override public LuaValue call(LuaValue table, LuaValue key) {
                String k = key.optjstring(null);
                if (k == null) return LuaValue.NIL;
                Element e = (Element) ((LuaUserdata) table.checktable().get("__element")).touserdata();
                switch (k) {
                    case "text": return LuaValue.valueOf(e.text());
                    case "html": return LuaValue.valueOf(e.html());
                    case "href": return LuaValue.valueOf(e.attr("abs:href").isEmpty() ? e.attr("href") : e.attr("abs:href"));
                    case "src": return LuaValue.valueOf(e.attr("abs:src").isEmpty() ? e.attr("src") : e.attr("abs:src"));
                    case "title": return LuaValue.valueOf(e.attr("title"));
                    case "class": return LuaValue.valueOf(e.attr("class"));
                    case "id": return LuaValue.valueOf(e.attr("id"));
                    case "attr": return new OneArgFunction() {
                        @Override public LuaValue call(LuaValue a) { return LuaValue.valueOf(e.attr(a.checkjstring())); }
                    };
                    default: return LuaValue.NIL;
                }
            }
        });
        tab.setmetatable(mt);
        return tab;
    }
}
