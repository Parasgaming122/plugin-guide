import org.luaj.vm2.*;
import org.luaj.vm2.lib.*;
import org.luaj.vm2.lib.jse.JsePlatform;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Element;
import com.google.gson.Gson;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/**
 * Test harness for oop.lua v1.1.0 (NoveLA API emulation — same semantics as
 * BixiangeTest, UTF-8 site so no charset gymnastics).
 *
 * oop.tw is Cloudflare-challenged from datacenter IPs (cf-mitigated: challenge
 * on every path), so ALL tests run against fixtures captured through the
 * Google-Translate proxy and cleaned (font wrappers stripped, links restored
 * to relative site paths, reversed CJK paragraphs un-reversed) — see
 * scripts/clean_oop_fixtures.py. The fixtures are in SIMPLIFIED Chinese (the
 * translate proxy converted them); selectors are class-based so this is
 * faithful. On-device the app's WebView CF-bypass fetches the real pages.
 */
public class OopTest {

    static final Gson gson = new Gson();
    static Globals globals;
    static LuaValue plugin;
    static Map<String, String> prefs = new HashMap<>();
    static String UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36";
    static final String SITE = "https://www.oop.tw";
    static final String FIXTURES = "/home/z/my-project/research/newsites/";

    // ── mock rule engine (same as BixiangeTest, UTF-8) ─────────────────
    static class Rule {
        String urlContains;
        String file;
        int code = 200;
        Map<String, String> headers = new LinkedHashMap<>();
        String rawBody;
    }
    static final List<Rule> rules = new ArrayList<>();

    static void mock(String urlContains, String file) {
        Rule r = new Rule(); r.urlContains = urlContains; r.file = file; rules.add(r);
    }

    static final Map<String, Integer> urlHitCount = new LinkedHashMap<>();
    static final List<String> fetchedUrls = new ArrayList<>();
    static List<String[]> showErrorCalls = new ArrayList<>();

    static boolean blockTranslate = false;
    static String cannedTranslate = null;

    static boolean isTranslateHost(String url) {
        return url.contains("translate.googleapis.com") || url.contains("clients5.google.com")
            || url.contains("mymemory.translated.net");
    }

    static class HttpResp { boolean success; String body; int code; Map<String, List<String>> headers; }

    static String lastGetUrl = null;
    static String lastSearchUrl = null;

    static HttpResp http(String method, String url, String body, Map<String, String> headers) {
        HttpResp r = new HttpResp();

        if (isTranslateHost(url)) {
            if (cannedTranslate != null && cannedTranslate.startsWith("raw:")) {
                if (url.contains("/translate_a/t")) {
                    String src = "POST".equals(method) ? (body != null ? body : "") : url;
                    int qn = 0, idx = 0;
                    while ((idx = src.indexOf("q=", idx)) >= 0) { qn++; idx += 2; }
                    if (qn > 0) {
                        String val = cannedTranslate.substring(4);
                        StringBuilder sb = new StringBuilder("[");
                        for (int i = 0; i < qn; i++) {
                            if (i > 0) sb.append(',');
                            sb.append('"').append(val).append('"');
                        }
                        sb.append(']');
                        r.success = true; r.body = sb.toString(); r.code = 200; r.headers = new HashMap<>();
                        return r;
                    }
                }
                if (url.contains("/translate_a/single")) {
                    r.success = true; r.body = "[[[\"" + cannedTranslate.substring(4) + "\",\"原文\"]],null,\"zh-TW\"]";
                    r.code = 200; r.headers = new HashMap<>();
                    return r;
                }
            }
            if (cannedTranslate != null) {
                if (url.contains("/translate_a/t")) {
                    String src = "POST".equals(method) ? (body != null ? body : "") : url;
                    int qn = 0, idx = 0;
                    while ((idx = src.indexOf("q=", idx)) >= 0) { qn++; idx += 2; }
                    if (qn > 0) {
                        StringBuilder sb = new StringBuilder("[");
                        for (int i = 0; i < qn; i++) {
                            if (i > 0) sb.append(',');
                            sb.append('"').append(cannedTranslate).append(i + 1).append('"');
                        }
                        sb.append(']');
                        r.success = true; r.body = sb.toString(); r.code = 200; r.headers = new HashMap<>();
                        return r;
                    }
                }
            }
            if (blockTranslate) {
                r.success = false; r.body = "injected failure"; r.code = -1; r.headers = new HashMap<>();
                return r;
            }
        }

        if (url.contains("/search/")) lastSearchUrl = url;
        lastGetUrl = url;

        for (Rule rule : rules) {
            if (url.contains(rule.urlContains)) {
                urlHitCount.merge(rule.urlContains, 1, Integer::sum);
                fetchedUrls.add(url);
                HttpResp resp = new HttpResp();
                resp.code = rule.code;
                resp.success = rule.code >= 200 && rule.code < 300;
                resp.headers = new LinkedHashMap<>();
                for (Map.Entry<String, String> e : rule.headers.entrySet())
                    resp.headers.computeIfAbsent(e.getKey().toLowerCase(), x -> new ArrayList<>()).add(e.getValue());
                if (rule.file != null) {
                    try {
                        resp.body = new String(Files.readAllBytes(Paths.get(FIXTURES + rule.file)), StandardCharsets.UTF_8);
                    } catch (Exception e) { resp.body = "fixture missing: " + rule.file; resp.success = false; resp.code = 500; }
                } else if (rule.rawBody != null) {
                    resp.body = rule.rawBody;
                } else {
                    resp.body = "";
                }
                return resp;
            }
        }
        fetchedUrls.add(url);
        r.success = false; r.body = "no mock rule for " + url; r.code = -1; r.headers = new HashMap<>();
        return r;
    }

    static LuaTable responseTable(HttpResp r) {
        LuaTable t = new LuaTable();
        t.set("success", LuaValue.valueOf(r.success));
        t.set("body", LuaValue.valueOf(r.body));
        t.set("code", LuaValue.valueOf(r.code));
        LuaTable h = new LuaTable();
        if (r.headers != null) for (Map.Entry<String, List<String>> e : r.headers.entrySet()) {
            if (e.getKey() == null) continue;
            LuaTable vt = new LuaTable();
            if (e.getValue() != null) for (int i = 0; i < e.getValue().size(); i++) vt.set(i + 1, LuaValue.valueOf(e.getValue().get(i)));
            h.set(e.getKey().toLowerCase(), vt);
        }
        t.set("headers", h);
        return t;
    }

    static Map<String, String> convertHeaders(LuaTable t) {
        Map<String, String> m = new LinkedHashMap<>();
        LuaValue k = LuaValue.NIL;
        while (true) {
            Varargs n = t.next(k);
            if (n.arg1().isnil()) break;
            k = n.arg1();
            m.put(k.tojstring(), t.get(k).optjstring(""));
        }
        return m;
    }

    static Element elementFromValue(LuaValue v) {
        if (v.istable()) {
            LuaValue user = v.checktable().get("__element");
            if (user.isuserdata(Element.class)) return (Element) user.touserdata(Element.class);
        }
        return null;
    }

    static LuaTable elementToTable(Element el) {
        LuaTable tab = new LuaTable();
        tab.set("__element", new LuaUserdata(el));
        LuaTable mt = new LuaTable();
        mt.set(LuaValue.INDEX, new TwoArgFunction() {
            @Override public LuaValue call(LuaValue table, LuaValue key) {
                String keyStr = key.optjstring(null);
                if (keyStr == null) return LuaValue.NIL;
                LuaValue value;
                switch (keyStr) {
                    case "text": value = LuaValue.valueOf(el.text()); break;
                    case "html": value = LuaValue.valueOf(el.html()); break;
                    case "href": value = LuaValue.valueOf(el.attr("abs:href").isEmpty() ? el.attr("href") : el.attr("abs:href")); break;
                    case "src": value = LuaValue.valueOf(el.attr("abs:src").isEmpty() ? el.attr("src") : el.attr("abs:src")); break;
                    case "title": value = LuaValue.valueOf(el.attr("title")); break;
                    case "class": value = LuaValue.valueOf(el.attr("class")); break;
                    case "id": value = LuaValue.valueOf(el.attr("id")); break;
                    case "attr": value = new OneArgFunction() { @Override public LuaValue call(LuaValue a) { return LuaValue.valueOf(el.attr(a.checkjstring())); } }; break;
                    case "select": value = new OneArgFunction() { @Override public LuaValue call(LuaValue a) {
                        LuaTable rt = new LuaTable(); int i = 1;
                        for (Element e : el.select(a.checkjstring())) rt.set(i++, elementToTable(e));
                        return rt;
                    } }; break;
                    default: value = LuaValue.NIL;
                }
                if (!value.isnil()) table.set(key, value);
                return value;
            }
        });
        tab.setmetatable(mt);
        return tab;
    }

    static void registerApi(Globals g) {
        g.set("http_get", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2) {
                String url = a1.checkjstring();
                Map<String, String> headers = new LinkedHashMap<>();
                if (a2.istable()) headers = convertHeaders(a2.checktable().get("headers").opttable(new LuaTable()));
                return responseTable(http("GET", url, null, headers));
            }
        });
        g.set("http_post", new ThreeArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2, LuaValue a3) {
                String url = a1.checkjstring(), body = a2.checkjstring();
                Map<String, String> headers = new LinkedHashMap<>();
                if (a3.istable()) headers = convertHeaders(a3.checktable().get("headers").opttable(new LuaTable()));
                return responseTable(http("POST", url, body, headers));
            }
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
            @Override public LuaValue call(LuaValue a) {
                try { return LuaValue.valueOf(URLEncoder.encode(a.checkjstring(), "UTF-8")); }
                catch (Exception e) { return a; }
            }
        });
        g.set("url_encode_charset", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2) {
                try { return LuaValue.valueOf(URLEncoder.encode(a1.checkjstring(), a2.checkjstring())); }
                catch (Exception e) { return LuaValue.NIL; }
            }
        });
        g.set("url_resolve", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2) {
                try { return LuaValue.valueOf(URI.create(a1.checkjstring()).resolve(a2.checkjstring()).toString()); }
                catch (Exception e) { return a2; }
            }
        });
        g.set("log_info", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) { return LuaValue.NIL; }
        });
        g.set("show_error", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a, LuaValue b) {
                showErrorCalls.add(new String[]{a.optjstring(""), b.optjstring("")});
                return LuaValue.NIL;
            }
        });
        g.set("html_select", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2) {
                try {
                    Element el = elementFromValue(a1);
                    org.jsoup.select.Elements elems = el != null ? el.select(a2.checkjstring()) : Jsoup.parse(a1.checkjstring()).select(a2.checkjstring());
                    LuaTable t = new LuaTable();
                    for (int i = 0; i < elems.size(); i++) t.set(i + 1, elementToTable(elems.get(i)));
                    return t;
                } catch (Exception e) { return new LuaTable(); }
            }
        });
        g.set("html_select_first", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2) {
                try {
                    Element el = elementFromValue(a1);
                    Element first = el != null ? el.selectFirst(a2.checkjstring()) : Jsoup.parse(a1.checkjstring()).selectFirst(a2.checkjstring());
                    return first != null ? elementToTable(first) : LuaValue.NIL;
                } catch (Exception e) { return LuaValue.NIL; }
            }
        });
        g.set("html_attr", new ThreeArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2, LuaValue a3) {
                try {
                    Element el = elementFromValue(a1);
                    Element target = el != null ? el.selectFirst(a2.checkjstring()) : Jsoup.parse(a1.checkjstring()).selectFirst(a2.checkjstring());
                    return LuaValue.valueOf(target != null ? target.attr(a3.checkjstring()) : "");
                } catch (Exception e) { return LuaValue.valueOf(""); }
            }
        });
        g.set("html_text", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) {
                try { return LuaValue.valueOf(Jsoup.parse(a.checkjstring()).text()); }
                catch (Exception e) { return LuaValue.valueOf(""); }
            }
        });
        g.set("string_clean", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) {
                return LuaValue.valueOf(a.optjstring("").replaceAll("[\\s\\u00A0\\u3000]+", " ").trim());
            }
        });
        g.set("string_trim", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) {
                return LuaValue.valueOf(a.optjstring("").trim());
            }
        });
        g.set("string_starts_with", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a, LuaValue b) {
                return LuaValue.valueOf(a.optjstring("").startsWith(b.optjstring("")));
            }
        });
        g.set("json_parse", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) {
                try {
                    Object o = gson.fromJson(a.checkjstring(), Object.class);
                    return jsonToLua(o);
                } catch (Exception e) { return LuaValue.NIL; }
            }
        });
    }

    static LuaValue jsonToLua(Object o) {
        if (o == null) return LuaValue.NIL;
        if (o instanceof String) return LuaValue.valueOf((String) o);
        if (o instanceof Boolean) return LuaValue.valueOf((Boolean) o);
        if (o instanceof Number) return LuaValue.valueOf(((Number) o).doubleValue());
        if (o instanceof Map) {
            LuaTable t = new LuaTable();
            for (Object e : ((Map<?, ?>) o).entrySet()) {
                Map.Entry<?, ?> en = (Map.Entry<?, ?>) e;
                t.set(LuaValue.valueOf(String.valueOf(en.getKey())), jsonToLua(en.getValue()));
            }
            return t;
        }
        if (o instanceof List) {
            LuaTable t = new LuaTable();
            int i = 1;
            for (Object v : (List<?>) o) t.set(i++, jsonToLua(v));
            return t;
        }
        return LuaValue.valueOf(String.valueOf(o));
    }

    static Globals createSandbox() {
        Globals g = JsePlatform.standardGlobals();
        g.set("luajava", LuaValue.NIL); g.set("io", LuaValue.NIL);
        g.set("load", LuaValue.NIL); g.set("loadfile", LuaValue.NIL);
        g.set("loadstring", LuaValue.NIL); g.set("dofile", LuaValue.NIL);
        g.set("require", LuaValue.NIL); g.set("package", LuaValue.NIL);
        g.set("debug", LuaValue.NIL);
        LuaTable os = (LuaTable) g.get("os");
        if (os != null) {
            os.set("execute", LuaValue.NIL); os.set("exit", LuaValue.NIL); os.set("getenv", LuaValue.NIL);
            os.set("rename", LuaValue.NIL); os.set("remove", LuaValue.NIL); os.set("tmpname", LuaValue.NIL);
        }
        return g;
    }

    // ── test scaffolding ───────────────────────────────────────────────
    static int pass = 0, fail = 0;
    static void check(boolean cond, String name) {
        if (cond) { pass++; System.out.println("  PASS  " + name); }
        else { fail++; System.out.println("  FAIL  " + name); }
    }
    static void section(String s) { System.out.println("\n== " + s + " =="); }

    static void loadPlugin() throws Exception {
        globals = createSandbox();
        registerApi(globals);
        plugin = globals.load(new FileReader("/home/z/my-project/download/oop.lua"), "oop.lua").call();
    }
    static void freshPlugin() throws Exception { loadPlugin(); }

    static LuaTable callFn(String name, Object... args) {
        LuaValue f = globals.get(name);
        return f.call(LuaValue.valueOf(toDouble(args[0]))).checktable();
    }
    static double toDouble(Object o) {
        if (o instanceof Integer) return (double) (Integer) o;
        if (o instanceof Double) return (Double) o;
        throw new IllegalArgumentException();
    }
    static LuaTable callIntStr(String name, int a, String b) {
        return globals.get(name).call(LuaValue.valueOf((double) a), LuaValue.valueOf(b)).checktable();
    }
    static LuaTable callStr(String name, String a) {
        return globals.get(name).call(LuaValue.valueOf(a)).checktable();
    }
    static LuaValue parsePageRaw(String bookUrl, int page) {
        return globals.get("parsePage").call(
            LuaValue.valueOf(bookUrl), LuaValue.valueOf((double) page));
    }
    static int tocPrefNonEmpty(String id) {
        String v = prefs.getOrDefault("oop_toc_" + id, "");
        return v == null || v.isEmpty() ? 0 : 1;
    }
    static String g(String fn, String arg) {
        LuaValue v = globals.get(fn).call(LuaValue.valueOf(arg));
        return v.isnil() ? null : v.tojstring();
    }
    static void resetMockState() {
        urlHitCount.clear(); fetchedUrls.clear(); showErrorCalls.clear();
        lastGetUrl = null; lastSearchUrl = null;
    }

    public static void main(String[] args) throws Exception {
        System.out.println("OopTest — mode: MOCK (cleaned translate-proxy fixtures)");
        loadPlugin();

        section("T0 metadata");
        check("oop".equals(globals.get("id").tojstring()), "id = oop");
        check(globals.get("version").tojstring().equals("1.1.0"), "version = 1.1.0");
        check(globals.get("baseUrl").tojstring().equals("https://www.oop.tw/"), "baseUrl");
        check(globals.get("charset").isnil() || globals.get("charset").tojstring().isEmpty(), "no charset override (UTF-8 default)");
        check(!globals.get("getCatalogList").isnil()
           && !globals.get("getCatalogSearch").isnil()
           && !globals.get("getChapterText").isnil()
           && !globals.get("getChapterList").isnil()
           && !globals.get("parsePage").isnil()
           && !globals.get("getBookTitle").isnil(), "required functions present (incl. parsePage)");
        check(globals.get("cf_options").isnil(), "no cf_options whitelist (CF WebView bypass stays ENABLED)");

        section("T1 filters schema");
        LuaTable fl = callFn("getFilterList", 0);
        check(fl.len().toint() == 1, "1 filter (category)");
        LuaTable opts = fl.get(1).checktable().get("options").checktable();
        check(opts.len().toint() == 15, "15 options (All + 14 categories)");
        check("10".equals(opts.get(11).checktable().get("value").tojstring()), "category 10 = 短篇");

        section("T2 sort page 1 (all books)");
        rules.clear(); resetMockState();
        mock("/sort/", "oop_sort.html");
        LuaTable res = callFn("getCatalogList", 0);
        LuaTable items = res.get("items").checktable();
        check(items.len().toint() == 10, "10 books per page: " + items.len().toint());
        check(res.get("hasNext").toboolean(), "hasNext (>> link present)");
        LuaTable it1 = items.get(1).checktable();
        check(it1.get("url").tojstring().startsWith("https://www.oop.tw/abooka/"), "book URL canonical oop.tw: " + it1.get("url").tojstring());
        check(it1.get("cover").tojstring().startsWith("https://wsrv.nl/?url="), "cover proxied via wsrv.nl");
        check(it1.get("title").tojstring().length() > 0, "title parsed: " + it1.get("title").tojstring());

        section("T3 sort page 2 URL building");
        rules.clear(); resetMockState();
        mock("/sort/2/", "oop_sort.html");
        callFn("getCatalogList", 1);
        check(lastGetUrl != null && lastGetUrl.equals("https://www.oop.tw/sort/2/"), "page 2 fetches /sort/2/: " + lastGetUrl);

        section("T4 category browse (短篇 = 10)");
        rules.clear(); resetMockState();
        mock("/sort/10/1/", "oop_sort.html");
        LuaTable filters = new LuaTable();
        filters.set("category", LuaValue.valueOf("10"));
        LuaTable res4 = globals.get("getCatalogFiltered").call(
            LuaValue.valueOf((double) 0), filters).checktable();
        check(res4.get("items").checktable().len().toint() == 10, "category page parsed");
        check(lastGetUrl != null && lastGetUrl.equals("https://www.oop.tw/sort/10/1/"), "category URL: " + lastGetUrl);
        // 'all' → /sort/{N}/
        rules.clear(); resetMockState();
        mock("/sort/2/", "oop_sort.html");
        filters.set("category", LuaValue.valueOf("all"));
        globals.get("getCatalogFiltered").call(LuaValue.valueOf((double) 1), filters);
        check(lastGetUrl != null && lastGetUrl.equals("https://www.oop.tw/sort/2/"), "all + index 1 → /sort/2/");

        section("T5 book page /abooka/a3292752a/");
        rules.clear(); resetMockState();
        mock("/abooka/a3292752a/?p=2", "oop_book_p2.html");
        mock("/abooka/a3292752a/", "oop_book.html");
        String title = g("getBookTitle", "https://www.oop.tw/abooka/a3292752a/");
        check("等你到三十岁末".equals(title), "title: " + title);
        String cover = g("getBookCoverImageUrl", "https://www.oop.tw/abooka/a3292752a/");
        check(cover != null && cover.contains(urlEnc("https://www.oop.tw/files/article/txt/files/article/image/29/29275/29275s.jpg")), "cover URL: " + cover);
        String desc = g("getBookDescription", "https://www.oop.tw/abooka/a3292752a/");
        check(desc != null && desc.startsWith("关键字："), "description prefixed with keywords");
        check(desc != null && desc.contains("周珩"), "description body");
        LuaTable genres = callStr("getBookGenres", "https://www.oop.tw/abooka/a3292752a/");
        check(genres.len().toint() >= 3, "genres from 关键字 tags: " + genres.len().toint());
        String status = g("getBookStatus", "https://www.oop.tw/abooka/a3292752a/");
        check("全本".equals(status), "status 全本 (raw mode): " + status);
        String upd = g("getBookLastUpdate", "https://www.oop.tw/abooka/a3292752a/");
        check("2025-08-14".equals(upd), "lastUpdate: " + upd);
        String hash = g("getChapterListHash", "https://www.oop.tw/abooka/a3292752a/");
        check(hash != null && hash.contains("2025-08-14"), "hash includes update time");
        check(urlHitCount.getOrDefault("/abooka/a3292752a/", 0) == 1, "book page fetched once (cache)");

        section("T6 chapter list walks catalog pages (?p=N)");
        rules.clear(); resetMockState();
        mock("/abooka/a3292752a/?p=2", "oop_book_p2.html");
        mock("/abooka/a3292752a/", "oop_book.html");
        LuaTable chl = callStr("getChapterList", "https://www.oop.tw/abooka/a3292752a/");
        check(chl.len().toint() == 44, "44 chapters across 2 catalog pages: " + chl.len().toint());
        check("001".equals(chl.get(1).checktable().get("title").tojstring()), "first chapter 001");
        check(chl.get(1).checktable().get("url").tojstring().endsWith("/areada/a3292752a/a1165075a.html"), "first chapter URL");
        check("044".equals(chl.get(44).checktable().get("title").tojstring()), "last chapter 044");
        check(chl.get(44).checktable().get("url").tojstring().endsWith("/areada/a3292752a/a1165206a.html"), "last chapter URL");
        check(fetchedUrls.toString().contains("abooka/a3292752a/?p=2"), "page 2 of the catalog fetched");
        // order: 001..044 ascending
        boolean ordered = true;
        for (int i = 1; i <= 44; i++) {
            String t = chl.get(i).checktable().get("title").tojstring();
            if (!t.equals(String.format("%03d", i))) { ordered = false; break; }
        }
        check(ordered, "chapters in ascending order 001→044");

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

        section("T7 chapter 1 text (TXT header-only chapter → KEPT)");
        String ch1Html = new String(Files.readAllBytes(Paths.get(FIXTURES + "oop_chapter.html")), StandardCharsets.UTF_8);
        String text1 = globals.get("getChapterText").call(
            LuaValue.valueOf(ch1Html), LuaValue.valueOf("https://www.oop.tw/areada/a3292752a/a1165075a.html")).tojstring();
        check(text1.length() > 100, "header-only chapter returns its content (not empty): " + text1.length() + " chars");
        check(text1.contains("周珩"), "contains the intro text");

        section("T8 chapter 2 text (clean story content)");
        String ch2Html = new String(Files.readAllBytes(Paths.get(FIXTURES + "oop_ch2.html")), StandardCharsets.UTF_8);
        String text2 = globals.get("getChapterText").call(
            LuaValue.valueOf(ch2Html), LuaValue.valueOf("https://www.oop.tw/areada/a3292752a/a1165079a.html")).tojstring();
        check(text2.startsWith("星城"), "chapter 2 starts with story text: " + text2.substring(0, Math.min(20, text2.length())));
        check(text2.length() > 1000, "chapter 2 length: " + text2.length());
        check(!text2.contains("mid-content-ad"), "no ad markup leaks");
        check(!text2.contains("作者: 长木") && !text2.contains("作者:長木"), "no TXT header in mid-chapter");

        section("T9 search (7 results, one page)");
        rules.clear(); resetMockState();
        mock("/search/", "oop_search.html");
        LuaTable sr = callIntStr("getCatalogSearch", 0, "等你到");
        LuaTable sitems = sr.get("items").checktable();
        check(sitems.len().toint() == 7, "7 results: " + sitems.len().toint());
        check(sitems.get(1).checktable().get("url").tojstring().startsWith("https://www.oop.tw/abooka/"), "search result URL canonical");
        check(sitems.get(1).checktable().get("title").tojstring().contains("等你到"), "highlight spans merged into title");
        check(!sr.get("hasNext").toboolean(), "search has no pagination");
        check(lastSearchUrl != null && lastSearchUrl.contains("searchkey="), "search URL has searchkey");

        section("T10 nocover placeholder passthrough");
        // search fixture has a book with /static/shipsay/nocover.jpg → not proxied
        boolean foundNocover = false;
        for (int i = 1; i <= sitems.len().toint(); i++) {
            String c = sitems.get(i).checktable().get("cover").tojstring();
            if (c.contains("nocover")) { foundNocover = c.startsWith("https://www.oop.tw/static"); }
        }
        check(foundNocover, "nocover.jpg stays direct (not proxied)");

        section("T11 English search query translated to zh-TW");
        freshPlugin();
        prefs.put("oop_mode", "translate");
        cannedTranslate = "raw:等你到";
        rules.clear(); resetMockState();
        mock("/search/", "oop_search.html");
        LuaTable esr = callIntStr("getCatalogSearch", 0, "wait till thirty");
        check(esr.get("items").checktable().len().toint() == 7, "English query → zh-TW → searched");
        check(lastSearchUrl != null && lastSearchUrl.contains(urlEnc("等你到")), "translated keyword in URL");
        cannedTranslate = null;
        prefs.remove("oop_mode");

        section("T12 covers direct mode");
        freshPlugin();
        prefs.put("oop_covers", "direct");
        rules.clear(); resetMockState();
        mock("/abooka/a3292752a/", "oop_book.html");
        String dcover = g("getBookCoverImageUrl", "https://www.oop.tw/abooka/a3292752a/");
        check(dcover != null && dcover.startsWith("https://www.oop.tw/files/"), "direct cover unproxied");
        prefs.remove("oop_covers");

        section("T13 settings schema");
        LuaTable ss = callFn("getSettingsSchema", 0);
        check(ss.len().toint() == 4, "4 settings entries");
        boolean hasCovers = false, hasMode = false;
        for (int i = 1; i <= ss.len().toint(); i++) {
            String k = ss.get(i).checktable().get("key").tojstring();
            if (k.equals("oop_covers")) hasCovers = true;
            if (k.equals("oop_mode")) hasMode = true;
        }
        check(hasCovers && hasMode, "covers/mode settings present");

        section("T14 UA preset");
        LuaValue ua = globals.get("getUserAgentPreset").call();
        check("Chrome Mobile".equals(ua.optjstring("")), "getUserAgentPreset = Chrome Mobile");

        section("T15 translator mode (canned)");
        freshPlugin();
        prefs.put("oop_mode", "translate");
        cannedTranslate = "tr-";
        rules.clear(); resetMockState();
        mock("/sort/", "oop_sort.html");
        LuaTable trres = callFn("getCatalogList", 0);
        check(trres.get("items").checktable().get(1).checktable().get("title").tojstring().startsWith("tr-"),
              "catalog titles translated");
        rules.clear(); resetMockState();
        mock("/abooka/a3292752a/", "oop_book.html");
        String trTitle = g("getBookTitle", "https://www.oop.tw/abooka/a3292752a/");
        check(trTitle.startsWith("tr-") && trTitle.contains("等你到三十岁末"), "book title translated + original: " + trTitle);
        cannedTranslate = null;
        prefs.remove("oop_mode");

        section("T16 translator breaker (all engines dead)");
        freshPlugin();
        prefs.put("oop_mode", "translate");
        blockTranslate = true;
        rules.clear(); resetMockState();
        mock("/sort/", "oop_sort.html");
        LuaTable bres = callFn("getCatalogList", 0);
        check(bres.get("items").checktable().get(1).checktable().get("title").tojstring().length() > 0,
              "translate failure degrades to raw titles");
        blockTranslate = false;
        prefs.remove("oop_mode");

        section("T17 dead site → show_error");
        freshPlugin();
        rules.clear(); resetMockState();
        Rule dead = new Rule();
        dead.urlContains = "/sort/";
        dead.code = -1; dead.rawBody = "connection refused";
        rules.add(dead);
        LuaTable errRes = callFn("getCatalogList", 0);
        check(errRes.get("items").checktable().len().toint() == 0, "dead site → empty items");
        check(showErrorCalls.size() == 1, "show_error surfaced");
        check(showErrorCalls.get(0)[0].contains("unreachable"), "error title mentions unreachable");

        section("T18 status fallback (连载 book)");
        // the sort fixture's first card shows 男频/ 连载 — the book page fixture
        // is 全本; verify the translator maps 全本 → Completed in translate mode
        freshPlugin();
        prefs.put("oop_mode", "translate");
        cannedTranslate = "raw:X"; // generic translations; STATIC_EN handles 全本
        rules.clear(); resetMockState();
        mock("/abooka/a3292752a/", "oop_book.html");
        String tstatus = g("getBookStatus", "https://www.oop.tw/abooka/a3292752a/");
        check("Completed".equals(tstatus), "全本 → Completed in translate mode: " + tstatus);
        cannedTranslate = null;
        prefs.remove("oop_mode");

        section("T6g LRU eviction — cache capped at 5 books");
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

        System.out.println("\n════════════════════════════════════");
        System.out.println((pass + fail) + " checks: " + pass + " PASS, " + fail + " FAIL");
        if (fail > 0) System.exit(1);
    }

    static String urlEnc(String s) {
        try { return URLEncoder.encode(s, "UTF-8"); } catch (Exception e) { return s; }
    }
}
