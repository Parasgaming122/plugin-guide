import org.jsoup.Jsoup;
import org.jsoup.nodes.Element;
import org.luaj.vm2.*;
import org.luaj.vm2.lib.*;
import org.luaj.vm2.lib.jse.JsePlatform;
import com.google.gson.Gson;

import java.io.FileReader;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.*;

/**
 * S69TwTest — mock harness for 69shubaTw.lua v1.0.0.
 *
 * 69shuba.tw sits behind a Tencent EdgeOne "aegis" captcha from datacenter
 * IPs (every path 403s with a reCAPTCHA-v3 verification page; only the
 * Google-Translate proxy passes, and even it is challenged on /indexlist/*).
 * All tests therefore run against cleaned translate-proxy fixtures
 * (scripts/clean_69shubatw_fixtures.py) plus synthesized TOC fixtures
 * (scripts/gen_69shubatw_toc_fixtures.py) — the /indexlist/ markup could
 * not be captured, so the TOC parser is layout-agnostic (anchor scan +
 * cid sort) and is tested against BOTH plausible layouts.
 */
public class S69TwTest {

    static final Gson gson = new Gson();
    static Globals globals;
    static LuaValue plugin;
    static Map<String, String> prefs = new HashMap<>();
    static final String SITE = "https://69shuba.tw";
    static final String FIXTURES = "/home/z/my-project/research/69shubatw/fixtures/";

    // ── mock rule engine ────────────────────────────────────────────────
    static class Rule {
        String urlContains; String file; int code = 200;
    }
    static final List<Rule> rules = new ArrayList<>();

    static void mock(String urlContains, String file) {
        Rule r = new Rule(); r.urlContains = urlContains; r.file = file; rules.add(r);
    }
    static void mockCode(String urlContains, String file, int code) {
        Rule r = new Rule(); r.urlContains = urlContains; r.file = file; r.code = code; rules.add(r);
    }
    static void mockClear() { rules.clear(); }

    static final Map<String, Integer> urlHitCount = new LinkedHashMap<>();
    static final List<String> fetchedUrls = new ArrayList<>();
    static List<String[]> showErrorCalls = new ArrayList<>();

    static boolean blockTranslate = false;
    // canned translator: per-target single word (query translation) and an
    // indexed marker for batch translation ("TR" → TR1, TR2, …)
    static String cannedTw = null, cannedCn = null, cannedList = null;

    static boolean isTranslateHost(String url) {
        return url.contains("translate.googleapis.com") || url.contains("clients5.google.com")
            || url.contains("mymemory.translated.net");
    }

    static class HttpResp { boolean success; String body; int code; Map<String, List<String>> headers; }

    static String lastGetUrl = null, lastSearchUrl = null;

    static HttpResp http(String method, String url, String body, Map<String, String> headers) {
        HttpResp r = new HttpResp();

        if (isTranslateHost(url)) {
            String src = "POST".equals(method) ? (body != null ? body : "") : url;
            int qn = 0, idx = 0;
            while ((idx = src.indexOf("q=", idx)) >= 0) { qn++; idx += 2; }
            // per-target canned word (query translation)
            String canned = null;
            if (url.contains("tl=zh-TW")) canned = cannedTw;
            else if (url.contains("tl=zh-CN")) canned = cannedCn;
            if (canned != null && url.contains("/translate_a/t") && qn > 0) {
                StringBuilder sb = new StringBuilder("[");
                for (int i = 0; i < qn; i++) { if (i > 0) sb.append(','); sb.append('"').append(canned).append('"'); }
                sb.append(']');
                r.success = true; r.body = sb.toString(); r.code = 200; r.headers = new HashMap<>();
                return r;
            }
            // indexed canned list (catalog/title translation, tl=en etc.)
            if (cannedList != null && url.contains("/translate_a/t") && qn > 0) {
                StringBuilder sb = new StringBuilder("[");
                for (int i = 0; i < qn; i++) { if (i > 0) sb.append(','); sb.append('"').append(cannedList).append(i + 1).append('"'); }
                sb.append(']');
                r.success = true; r.body = sb.toString(); r.code = 200; r.headers = new HashMap<>();
                return r;
            }
            if (url.contains("/translate_a/single")) {
                String word = url.contains("tl=zh-TW") ? cannedTw : (url.contains("tl=zh-CN") ? cannedCn : cannedList);
                if (word != null) {
                    r.success = true; r.body = "[[[\"" + word + "\",\"原文\"]],null,\"zh-TW\"]";
                    r.code = 200; r.headers = new HashMap<>();
                    return r;
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
                try {
                    resp.body = new String(Files.readAllBytes(Paths.get(FIXTURES + rule.file)), StandardCharsets.UTF_8);
                } catch (Exception e) { resp.body = "fixture missing: " + rule.file; resp.success = false; resp.code = 500; }
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
        g.set("url_resolve", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2) {
                try { return LuaValue.valueOf(java.net.URI.create(a1.checkjstring()).resolve(a2.checkjstring()).toString()); }
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
            @Override public LuaValue call(LuaValue a) { return LuaValue.valueOf(a.optjstring("").trim()); }
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
        plugin = globals.load(new FileReader("/home/z/my-project/download/69shubaTw.lua"), "69shubaTw.lua").call();
    }
    static void reloadPlugin() throws Exception { loadPlugin(); }

    static LuaTable callIdx(String name, int idx) {
        return globals.get(name).call(LuaValue.valueOf((double) idx)).checktable();
    }
    static LuaTable callIdxStr(String name, int idx, String s) {
        return globals.get(name).call(LuaValue.valueOf((double) idx), LuaValue.valueOf(s)).checktable();
    }
    static LuaTable callStr(String name, String a) {
        return globals.get(name).call(LuaValue.valueOf(a)).checktable();
    }
    static LuaValue parsePageRaw(String bookUrl, int page) {
        return globals.get("parsePage").call(LuaValue.valueOf(bookUrl), LuaValue.valueOf((double) page));
    }
    static String g(String fn, String arg) {
        LuaValue v = globals.get(fn).call(LuaValue.valueOf(arg));
        return v.isnil() ? null : v.tojstring();
    }
    static String fixture(String name) throws Exception {
        return new String(Files.readAllBytes(Paths.get(FIXTURES + name)), StandardCharsets.UTF_8);
    }
    static boolean fetchedContains(String frag) {
        for (String u : fetchedUrls) if (u.contains(frag)) return true;
        return false;
    }
    static int fetchedCount(String frag) {
        int n = 0;
        for (String u : fetchedUrls) if (u.contains(frag)) n++;
        return n;
    }
    static void resetMockState() {
        urlHitCount.clear(); fetchedUrls.clear(); showErrorCalls.clear();
        lastGetUrl = null; lastSearchUrl = null;
    }
    static void clearTocPrefs() {
        for (Object k : new ArrayList<>(prefs.keySet()))
            if (((String) k).startsWith("s69tw_toc_")) prefs.remove(k);
    }

    static final String BOOK_URL = "https://69shuba.tw/book/342441/";

    public static void main(String[] args) throws Exception {
        System.out.println("S69TwTest — mode: MOCK (cleaned translate-proxy + synthesized fixtures)");
        loadPlugin();

        // ════════ T0 metadata ════════
        section("T0 metadata");
        check("69shubaTw".equals(globals.get("id").tojstring()), "id = 69shubaTw");
        check(globals.get("name").tojstring().contains("69shuba.tw"), "name mentions 69shuba.tw: " + globals.get("name").tojstring());
        check("1.3.0".equals(globals.get("version").tojstring()), "version = 1.3.0");
        check("https://69shuba.tw/".equals(globals.get("baseUrl").tojstring()), "baseUrl");
        check(globals.get("charset").isnil() || globals.get("charset").tojstring().isEmpty(), "no charset override (UTF-8 default)");
        LuaTable cf = globals.get("cf_options").opttable(new LuaTable());
        check(!cf.isnil() && cf.get("trigger_markers").istable(), "cf_options present with trigger_markers");
        LuaTable tm = cf.get("trigger_markers").checktable();
        check(tm.len().toint() == 4, "4 EdgeOne trigger markers: " + tm.len().toint());
        LuaTable markers = cf.get("trigger_markers").checktable();
        boolean hasAegis = false, hasRecaptcha = false, hasTitle = false;
        for (int i = 1; i <= markers.len().toint(); i++) {
            String m = markers.get(i).optjstring("");
            if (m.contains("aegis_captcha_verify")) hasAegis = true;
            if (m.contains("recaptcha-v3-container")) hasRecaptcha = true;
            if (m.contains("Please complete human verification")) hasTitle = true;
        }
        boolean hasTurnstile = false;
        for (int i = 1; i <= tm.len().toint(); i++)
            if (tm.get(i).tojstring().contains("challenges.cloudflare.com/turnstile")) hasTurnstile = true;
        check(hasAegis && hasRecaptcha && hasTitle && hasTurnstile, "all 4 EdgeOne captcha markers registered");
        check(!globals.get("getCatalogList").isnil() && !globals.get("parsePage").isnil()
            && !globals.get("getChapterList").isnil() && !globals.get("getChapterText").isnil()
            && !globals.get("getSettingsSchema").isnil() && !globals.get("getFilterList").isnil(),
            "all engine functions present");

        // ════════ T1 UA preset ════════
        section("T1 engine hooks");
        check("Chrome Mobile".equals(globals.get("getUserAgentPreset").call().tojstring()), "UA preset = Chrome Mobile");

        // ════════ T2 settings schema ════════
        section("T2 settings schema");
        LuaTable schema = globals.get("getSettingsSchema").call().checktable();
        check(schema.len().toint() == 3, "3 settings (no cover setting — direct CDN)");
        boolean keysOk = true;
        for (int i = 1; i <= 3; i++) {
            String k = schema.get(i).checktable().get("key").tojstring();
            if (!k.equals("s69tw_mode") && !k.equals("s69tw_tlang") && !k.equals("s69tw_tr_chapters")) keysOk = false;
        }
        check(keysOk, "setting keys: mode / tlang / tr_chapters");
        check("raw".equals(schema.get(1).checktable().get("current").tojstring()), "default mode = raw");
        check("en".equals(schema.get(2).checktable().get("current").tojstring()), "default target = en");

        // ════════ T3 catalog default (quanben) ════════
        section("T3 catalog — 全部小說 ranking");
        mockClear();
        mock("/quanben/fenlei/", "quanben_fenlei_1.html");
        resetMockState();
        LuaTable res = callIdx("getCatalogList", 0);
        LuaTable items = res.get("items").checktable();
        check(items.len().toint() == 30, "30 books on page 1");
        check(res.get("hasNext").toboolean(), "hasNext (下一页 link present)");
        check("https://69shuba.tw/quanben/fenlei/".equals(lastGetUrl), "page-1 URL: " + lastGetUrl);
        LuaTable it1 = items.get(1).checktable();
        check("鬥羅：壽元將盡，老祖我開始假死".equals(it1.get("title").tojstring()), "first title: " + it1.get("title").tojstring());
        check("https://69shuba.tw/book/398381/".equals(it1.get("url").tojstring()), "canonical book URL");
        check("https://p.69shuba.tw/398/398381/398381s.jpg".equals(it1.get("cover").tojstring()),
            "cover DIRECT from p.69shuba.tw: " + it1.get("cover").tojstring());
        boolean noWsrv = true;
        for (int i = 1; i <= items.len().toint(); i++)
            if (items.get(i).checktable().get("cover").tojstring().contains("wsrv.nl")) noWsrv = false;
        check(noWserv(noWsrv), "no wsrv.nl anywhere in covers");

        resetMockState();
        callIdx("getCatalogList", 1);
        check("https://69shuba.tw/quanben/fenlei/2/".equals(lastGetUrl), "page-2 URL (1-based): " + lastGetUrl);

        // ════════ T4 catalog filtered ════════
        section("T4 catalog — category filter");
        mockClear();
        mock("/fenlei/lishi/", "fenlei_lishi_1.html");
        mock("/quanben/fenlei/", "quanben_fenlei_1.html");
        resetMockState();
        // getCatalogFiltered takes (index, filters) — filters is a table
        LuaTable filt = new LuaTable(); filt.set("category", LuaValue.valueOf("lishi"));
        LuaTable resL = globals.get("getCatalogFiltered").call(LuaValue.valueOf(0.0), filt).checktable();
        check("https://69shuba.tw/fenlei/lishi/1/".equals(lastGetUrl), "lishi page-1 URL: " + lastGetUrl);
        check(resL.get("items").checktable().len().toint() == 30, "lishi page parsed (30)");
        check("大明：寒門輔臣".equals(resL.get("items").checktable().get(1).checktable().get("title").tojstring()),
            "lishi first title");
        globals.get("getCatalogFiltered").call(LuaValue.valueOf(1.0), filt);
        check("https://69shuba.tw/fenlei/lishi/2/".equals(lastGetUrl), "lishi page-2 URL: " + lastGetUrl);
        LuaTable filtQ = new LuaTable(); filtQ.set("category", LuaValue.valueOf("quanben"));
        globals.get("getCatalogFiltered").call(LuaValue.valueOf(0.0), filtQ);
        check("https://69shuba.tw/quanben/fenlei/1/".equals(lastGetUrl), "quanben filter URL: " + lastGetUrl);
        LuaTable resAll = callIdx("getCatalogFiltered", 0);
        check(resAll.get("items").checktable().len().toint() == 30, "all-filter falls back to quanben list");

        // ════════ T5 filter list ════════
        section("T5 filter list");
        LuaTable fl = globals.get("getFilterList").call().checktable();
        LuaTable opts = fl.get(1).checktable().get("options").checktable();
        check(opts.len().toint() == 10, "10 options (all + quanben + 8 categories)");
        boolean hasLishi = false, hasTongren = false;
        for (int i = 1; i <= opts.len().toint(); i++) {
            String v = opts.get(i).checktable().get("value").tojstring();
            if (v.equals("lishi")) hasLishi = true;
            if (v.equals("tongren")) hasTongren = true;
        }
        check(hasLishi && hasTongren, "lishi + tongren slugs present");

        // ════════ T6 search ════════
        section("T6 search — CJK query");
        mockClear();
        mock("searchkey=", "search_daming_1.html");
        resetMockState();
        LuaTable resS = callIdxStr("getCatalogSearch", 0, "大明");
        String expectUrl = "https://69shuba.tw/search/?searchkey=" + URLEncoder.encode("大明", "UTF-8") + "&searchtype=all";
        check(expectUrl.equals(lastSearchUrl), "search page-1 URL: " + lastSearchUrl);
        LuaTable sItems = resS.get("items").checktable();
        check(sItems.len().toint() == 30, "30 results");
        check("大明：從戰場撿屬性開創諸天大明".equals(sItems.get(1).checktable().get("title").tojstring()),
            "highlight spans merged: " + sItems.get(1).checktable().get("title").tojstring());
        check(resS.get("hasNext").toboolean(), "search hasNext (paginates)");
        check("https://69shuba.tw/book/338557/".equals(sItems.get(1).checktable().get("url").tojstring()), "canonical search URL");

        resetMockState();
        callIdxStr("getCatalogSearch", 1, "大明");
        String expectUrl2 = "https://69shuba.tw/search/2?searchkey=" + URLEncoder.encode("大明", "UTF-8");
        check(expectUrl2.equals(lastSearchUrl), "search page-2 URL: " + lastSearchUrl);

        // ════════ T7 book details ════════
        section("T7 book details — /book/342441/");
        mockClear();
        mock("/book/342441", "book_342441.html");
        resetMockState();
        check("大明：老四，帶咱一起修仙！".equals(g("getBookTitle", BOOK_URL)), "title");
        String cover = g("getBookCoverImageUrl", BOOK_URL);
        check("https://p.69shuba.tw/342/342441/342441s.jpg".equals(cover), "cover parsed direct: " + cover);
        String desc = g("getBookDescription", BOOK_URL);
        check(desc != null && desc.contains("作者：瑪了個瑪卡巴卡"), "desc has author header");
        check(desc != null && desc.contains("分類：歷史"), "desc has category header");
        check(desc != null && desc.contains("字數：66字"), "desc has word count");
        check(desc != null && desc.contains("一句話，主角是跟蹤讀書老爺寫出來的"), "desc has intro text");
        LuaTable genres = callStr("getBookGenres", BOOK_URL);
        check(genres.len().toint() == 1 && "歷史".equals(genres.get(1).tojstring()), "genres = [歷史]");
        check("連載".equals(g("getBookStatus", BOOK_URL)), "status = 連載");
        check("2026-05-12".equals(g("getBookLastUpdate", BOOK_URL)), "lastUpdate = 2026-05-12");
        String hash = g("getChapterListHash", BOOK_URL);
        check(hash != null && hash.equals("2026-05-12 14:49:47|第450章 老怪甦醒，大明的星門計劃"), "hash: " + hash);
        int bookFetches = fetchedCount("/book/342441");
        check(bookFetches == 1, "book page fetched ONCE for all detail calls (60s cache): " + bookFetches);

        // ════════ T8 cover synthesis ════════
        section("T8 cover synthesis when book page dead");
        mockClear();
        mockCode("/book/399999", "toc_c_captcha.html", 403);
        String cov2 = g("getBookCoverImageUrl", "https://69shuba.tw/book/399999/");
        check("https://p.69shuba.tw/399/399999/399999s.jpg".equals(cov2), "synthesized cover: " + cov2);

        // ════════ T9 TOC — parsePage(1) contract, REAL page (450-ch book) ════════
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
        check(fetchedUrls.size() == 2, "parsePage(2) makes exactly ONE growth-check fetch (no probe ladder): " + fetchedUrls.size());
        int nBefore = fetchedUrls.size();
        LuaTable tocB = callStr("getChapterList", bookB);
        check(tocB.len().toint() == 40, "getChapterList = 40 chapters");
        check(fetchedUrls.size() == nBefore, "getChapterList within the 60s window = ZERO network (page cache + totalPages=1): " + (fetchedUrls.size() - nBefore) + " extra");
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
        parsePageRaw(BOOK_URL, 1); // engine order: page 1 parsed (and cached) first
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

        // ════════ T16 chapter text — normal (1 / 1) ════════
        section("T16 chapter text — (1 / 1) single page");
        mockClear();
        resetMockState();
        String html1 = fixture("chapter_1.html");
        String txt1 = globals.get("getChapterText").call(LuaValue.valueOf(html1),
            LuaValue.valueOf("https://69shuba.tw/read/342441/890315")).tojstring();
        check(txt1.startsWith("永樂十二年，極北之地，萬年冰封。"), "starts with first paragraph");
        check(txt1.contains("龍紋白雪袍"), "content present");
        check(!txt1.contains("loadAdv"), "ad script skipped");
        check(fetchedUrls.isEmpty(), "no sub-page fetch for (1 / 1)");

        // ════════ T17 chapter text — split (1 / 2) ════════
        section("T17 chapter text — (1 / 2) sub-page concatenation");
        mockClear();
        mock("/read/342441/890415/2", "chapter_split_2.html");
        resetMockState();
        String htmlSp = fixture("chapter_split_1.html");
        String txtSp = globals.get("getChapterText").call(LuaValue.valueOf(htmlSp),
            LuaValue.valueOf("https://69shuba.tw/read/342441/890415")).tojstring();
        check(txtSp.contains("第一部分第1段"), "page-1 content present");
        check(txtSp.contains("第二部分第1段"), "page-2 content concatenated");
        check(!txtSp.contains("loadAdv"), "ad div between paragraphs skipped");
        check(lastGetUrl != null && lastGetUrl.equals("https://69shuba.tw/read/342441/890415/2"),
            "sub-page URL /read/{bid}/{cid}/2: " + lastGetUrl);

        // ════════ T18 chapter text — watermark strip ════════
        section("T18 chapter text — watermark lines");
        String htmlWm = fixture("chapter_wm.html");
        String txtWm = globals.get("getChapterText").call(LuaValue.valueOf(htmlWm),
            LuaValue.valueOf("https://69shuba.tw/read/342441/890315")).tojstring();
        check(!txtWm.contains("69shuba.tw"), "domain watermark stripped");
        check(!txtWm.contains("本章完"), "(本章完) stripped");
        check(txtWm.contains("永樂十二年"), "real content preserved");

        // ════════ T19 translator mode ════════
        section("T19 translator — mode/catalog/status/title");
        reloadPlugin();
        prefs.put("s69tw_mode", "translate");
        cannedList = "TR";
        mockClear();
        mock("/quanben/fenlei/", "quanben_fenlei_1.html");
        resetMockState();
        LuaTable resTr = callIdx("getCatalogList", 0);
        LuaTable trItems = resTr.get("items").checktable();
        check("TR1".equals(trItems.get(1).checktable().get("title").tojstring()), "catalog titles translated: " + trItems.get(1).checktable().get("title").tojstring());
        check("TR2".equals(trItems.get(2).checktable().get("title").tojstring()), "translation is per-item indexed");
        mockClear();
        mock("/book/342441", "book_342441.html");
        String trTitle = g("getBookTitle", BOOK_URL);
        check(trTitle != null && trTitle.equals("TR1 (大明：老四，帶咱一起修仙！)"), "book title: translated (original): " + trTitle);
        String trStatus = g("getBookStatus", BOOK_URL);
        check("Ongoing".equals(trStatus), "status 連載 → Ongoing via STATIC_EN: " + trStatus);
        String trGenre = callStr("getBookGenres", BOOK_URL).get(1).tojstring();
        check("History".equals(trGenre), "genre 歷史 → History: " + trGenre);

        // ════════ T20 translator — query translation + zh-CN retry ════════
        section("T20 translator — search query translation");
        cannedTw = "測試"; cannedCn = "测试";
        mockClear();
        mock("searchkey=" + URLEncoder.encode("測試", "UTF-8"), "search_empty.html");
        mock("searchkey=" + URLEncoder.encode("测试", "UTF-8"), "search_daming_1.html");
        resetMockState();
        LuaTable resQ = callIdxStr("getCatalogSearch", 0, "test query");
        String qUrl1 = "https://69shuba.tw/search/?searchkey=" + URLEncoder.encode("測試", "UTF-8") + "&searchtype=all";
        check(fetchedContains(qUrl1), "English query translated to zh-TW first");
        String qUrl2 = "https://69shuba.tw/search/?searchkey=" + URLEncoder.encode("测试", "UTF-8") + "&searchtype=all";
        check(fetchedContains(qUrl2), "zh-CN variant retried after zero results");
        check(resQ.get("items").checktable().len().toint() == 30, "retry returns the results");

        // raw mode: no translation calls at all
        prefs.put("s69tw_mode", "raw");
        resetMockState();
        callIdxStr("getCatalogSearch", 0, "test query");
        boolean noTranslateCall = true;
        for (String u : fetchedUrls) if (isTranslateHost(u)) noTranslateCall = false;
        check(noTranslateCall, "raw mode: zero translator requests");

        // ════════ T21 unreachable surfaces ════════
        section("T21 unreachable — show_error surfaces");
        prefs.put("s69tw_mode", "raw");
        cannedTw = null; cannedCn = null; cannedList = null;
        mockClear();
        mockCode("/quanben/", "toc_c_captcha.html", 403);
        resetMockState();
        showErrorCalls.clear();
        LuaTable resDead = callIdx("getCatalogList", 0);
        check(resDead.get("items").checktable().len().toint() == 0 && !resDead.get("hasNext").toboolean(),
            "dead catalog → empty result");
        check(showErrorCalls.size() == 1, "catalog show_error fired");
        check(showErrorCalls.get(0)[1].contains("robot") || showErrorCalls.get(0)[1].contains("verification"),
            "error text guides to the verification checkbox");

        // ════════ summary ════════
        System.out.println("\n════════════════════════════════════");
        System.out.println("RESULT: " + pass + " PASS, " + fail + " FAIL, " + (pass + fail) + " total");
        if (fail > 0) System.exit(1);
    }

    static boolean noWserv(boolean b) { return b; }
}
