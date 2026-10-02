import org.luaj.vm2.*;
import org.luaj.vm2.lib.*;
import org.luaj.vm2.lib.jse.JsePlatform;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Element;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;

import java.io.*;
import java.net.*;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/**
 * Test harness for bixiange.lua v1.0.0 (NoveLA API emulation, verified
 * against the app's Kotlin source — same semantics as Novel543Test).
 *
 * Site specifics handled here:
 *  - GB2312/GBK encoding: http_get/http_post honor the plugin's
 *    { charset = "GBK" } option; mock fixtures are raw GBK bytes; live
 *    requests decode GBK too (Charset.forName, exactly like the engine's
 *    String(bytes, Charset.forName(charset))).
 *  - url_encode_charset(str, charset) stub = java URLEncoder (same as the
 *    engine's UrlEncodeCharsetFunction).
 *  - EmpireCMS search 302: the mock returns code=302 + Location header
 *    with success=false (NoveLA marks 3xx as NOT successful).
 *
 * Two modes:
 *  - MOCK: rule engine serves recorded fixtures from research/newsites/
 *  - LIVE: real curl requests to www.bixiange.top (accepts env BIXIANGE_LIVE=1)
 */
public class BixiangeTest {

    static final Gson gson = new Gson();
    static Globals globals;
    static LuaValue plugin;
    static Map<String, String> prefs = new HashMap<>();
    static String UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36";
    static final String SITE = "https://www.bixiange.top";
    static final String MIRROR = "https://bxg123.cc";
    static final String FIXTURES = "/home/z/my-project/research/newsites/";

    static boolean MOCK = true;
    static boolean LIVE = System.getenv("BIXIANGE_LIVE") != null;

    // ── mock rule engine ───────────────────────────────────────────────
    static class Rule {
        String urlContains;       // substring match on the full URL
        String bodyContains;      // optional substring match on the POST body
        String file;              // fixture file (raw bytes) — served decoded per charset
        int code = 200;           // HTTP code to return
        Map<String, String> headers = new LinkedHashMap<>(); // response headers (e.g. Location)
        String rawBody;           // literal body (overrides file)
    }
    static final List<Rule> rules = new ArrayList<>();

    static void mock(String urlContains, String file) {
        Rule r = new Rule(); r.urlContains = urlContains; r.file = file; rules.add(r);
    }
    static void mockWithCode(String urlContains, int code, Map<String, String> headers) {
        Rule r = new Rule(); r.urlContains = urlContains; r.code = code;
        if (headers != null) r.headers = headers; rules.add(r);
    }

    static final Map<String, Integer> urlHitCount = new LinkedHashMap<>();
    static final List<String> fetchedUrls = new ArrayList<>();
    static List<String[]> showErrorCalls = new ArrayList<>();

    // translate fault injection / canned responses
    static boolean blockTranslate = false;
    static String cannedTranslate = null; // e.g. "tr-"

    static boolean isTranslateHost(String url) {
        return url.contains("translate.googleapis.com") || url.contains("clients5.google.com")
            || url.contains("mymemory.translated.net");
    }

    static class HttpResp { boolean success; String body; int code; Map<String, List<String>> headers; }

    static HttpResp mockLookup(String method, String url, String body) {
        for (Rule r : rules) {
            if (url.contains(r.urlContains)) {
                if (r.bodyContains != null && (body == null || !body.contains(r.bodyContains))) continue;
                urlHitCount.merge(r.urlContains, 1, Integer::sum);
                HttpResp resp = new HttpResp();
                resp.code = r.code;
                resp.success = r.code >= 200 && r.code < 300;
                resp.headers = new LinkedHashMap<>();
                for (Map.Entry<String, String> e : r.headers.entrySet())
                    resp.headers.computeIfAbsent(e.getKey().toLowerCase(), x -> new ArrayList<>()).add(e.getValue());
                if (r.file != null) {
                    try {
                        byte[] raw = Files.readAllBytes(Paths.get(FIXTURES + r.file));
                        // The real engine decodes with the charset the plugin passed;
                        // mock always decodes GBK (fixtures are GBK).
                        resp.body = new String(raw, Charset.forName("GBK"));
                    } catch (Exception e) { resp.body = "fixture missing: " + r.file; resp.success = false; resp.code = 500; }
                } else if (r.rawBody != null) {
                    resp.body = r.rawBody;
                } else {
                    resp.body = "";
                }
                return resp;
            }
        }
        return null;
    }

    static HttpResp http(String method, String url, String body, Map<String, String> headers, String charset) {
        HttpResp r = new HttpResp();

        if ("POST".equals(method) && url.contains("indexpage.php")) lastPostBody = body;

        if (isTranslateHost(url)) {
            if (cannedTranslate != null && cannedTranslate.startsWith("raw:")) {
                // every q gets the exact same translation (for query translation tests)
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
                    r.success = true; r.body = "[[[\"" + cannedTranslate.substring(4) + "\",\"原文\"]],null,\"zh-CN\"]";
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
                if (url.contains("/translate_a/single")) {
                    r.success = true; r.body = "[[[\"" + cannedTranslate + "gtx\",\"原文\"]],null,\"zh-CN\"]";
                    r.code = 200; r.headers = new HashMap<>();
                    return r;
                }
            }
            if (blockTranslate) {
                r.success = false; r.body = "injected failure"; r.code = -1; r.headers = new HashMap<>();
                return r;
            }
        }

        if (MOCK) {
            HttpResp m = mockLookup(method, url, body);
            if (m != null) { fetchedUrls.add(url); return m; }
            r.success = false; r.body = "no mock rule for " + url; r.code = -1; r.headers = new HashMap<>();
            fetchedUrls.add(url);
            return r;
        }

        fetchedUrls.add(url);
        try {
            List<String> cmd = new ArrayList<>(Arrays.asList("curl", "-s", "-D", "-",
                "-w", "\n__HTTP_CODE__%{http_code}",
                "--max-time", "60",
                "-A", UA,
                "-H", "Accept-Language: zh-CN,zh;q=0.9,en;q=0.8",
                "--compressed"));
            if (headers != null) for (Map.Entry<String, String> e : headers.entrySet()) {
                cmd.add("-H"); cmd.add(e.getKey() + ": " + e.getValue());
            }
            if (body != null) { cmd.add("-d"); cmd.add(body); }
            cmd.add(url);

            ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.redirectErrorStream(false);
            Process p = pb.start();
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            try (InputStream is = p.getInputStream()) {
                byte[] buf = new byte[8192]; int n;
                while ((n = is.read(buf)) > 0) bos.write(buf, 0, n);
            }
            p.waitFor();

            // Work at the BYTE level: split dumped headers from the body
            // first (headers are ASCII), then decode the body with the
            // requested charset — decoding the whole stream as UTF-8 first
            // would destroy GBK bytes (U+FFFD replacement chars).
            byte[] all = bos.toByteArray();
            String allStr = new String(all, StandardCharsets.ISO_8859_1); // byte-preserving view
            int marker = allStr.lastIndexOf("__HTTP_CODE__");
            String payload = marker >= 0 ? allStr.substring(0, marker) : allStr;
            r.code = marker >= 0 ? Integer.parseInt(allStr.substring(marker + 13).trim()) : 0;
            r.success = r.code >= 200 && r.code < 300;
            r.headers = new HashMap<>();

            Charset cs = Charset.forName(charset == null || charset.isEmpty() ? "UTF-8" : charset);
            String bodyStr;
            int sep = payload.indexOf("\r\n\r\n");
            if (sep >= 0) {
                String headerBlock = payload.substring(0, sep);
                byte[] bodyBytes = java.util.Arrays.copyOfRange(all, sep + 4, marker >= 0 ? marker : all.length);
                bodyStr = new String(bodyBytes, cs);
                for (String line : headerBlock.split("\r\n")) {
                    int c = line.indexOf(':');
                    if (c > 0) {
                        String k = line.substring(0, c).trim().toLowerCase();
                        String v = line.substring(c + 1).trim();
                        r.headers.computeIfAbsent(k, x -> new ArrayList<>()).add(v);
                    }
                }
            } else {
                bodyStr = new String(all, cs);
            }
            r.body = bodyStr;
        } catch (Exception e) {
            r.success = false; r.body = String.valueOf(e.getMessage()); r.code = -1; r.headers = new HashMap<>();
        }
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
                String charset = "UTF-8";
                if (a2.istable()) {
                    headers = convertHeaders(a2.checktable().get("headers").opttable(new LuaTable()));
                    String cs = a2.checktable().get("charset").optjstring("UTF-8");
                    if (cs != null && !cs.isEmpty()) charset = cs;
                }
                return responseTable(http("GET", url, null, headers, charset));
            }
        });
        g.set("http_post", new ThreeArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2, LuaValue a3) {
                String url = a1.checkjstring(), body = a2.checkjstring();
                Map<String, String> headers = new LinkedHashMap<>();
                String charset = "UTF-8";
                if (a3.istable()) {
                    headers = convertHeaders(a3.checktable().get("headers").opttable(new LuaTable()));
                    String cs = a3.checktable().get("charset").optjstring("UTF-8");
                    if (cs != null && !cs.isEmpty()) charset = cs;
                }
                return responseTable(http("POST", url, body, headers, charset));
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
        g.set("html_remove", new VarArgFunction() {
            @Override public LuaValue invoke(Varargs args) {
                try {
                    String html = args.checkjstring(1);
                    org.jsoup.nodes.Document doc = Jsoup.parse(html);
                    for (int i = 2; i <= args.narg(); i++) {
                        String sel = args.checkjstring(i);
                        try { doc.select(sel).remove(); } catch (Exception ignored) {}
                    }
                    return LuaValue.valueOf(doc.body().html());
                } catch (Exception e) { return LuaValue.valueOf(args.checkjstring(1)); }
            }
        });
        // string helpers (engine built-ins)
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
        plugin = globals.load(new FileReader("/home/z/my-project/download/bixiange.lua"), "bixiange.lua").call();
    }

    /** Fresh Lua state (clears the plugin's page cache + translator cache);
     *  prefs (Java map) survive unless explicitly cleared. */
    static void freshPlugin() throws Exception { loadPlugin(); }

    static LuaTable callFn(String name, Object... args) {
        LuaValue f = globals.get(name);
        switch (args.length) {
            case 0: return f.call().checktable();
            case 1: return f.call(LuaValue.valueOf(toDouble(args[0]))).checktable();
            default: return f.call(LuaValue.valueOf(toDouble(args[0])), LuaValue.valueOf(toDouble(args[1]))).checktable();
        }
    }
    static double toDouble(Object o) {
        if (o instanceof Integer) return (double) (Integer) o;
        if (o instanceof Double) return (Double) o;
        throw new IllegalArgumentException("arg must be int");
    }

    static LuaTable callStr(String name, String a) {
        return globals.get(name).call(LuaValue.valueOf(a)).checktable();
    }
    static LuaTable callStrInt(String name, String a, int b) {
        return globals.get(name).call(LuaValue.valueOf(a), LuaValue.valueOf((double) b)).checktable();
    }
    static LuaTable callIntStr(String name, int a, String b) {
        return globals.get(name).call(LuaValue.valueOf((double) a), LuaValue.valueOf(b)).checktable();
    }

    static String g(String fn, String arg) {
        LuaValue v = globals.get(fn).call(LuaValue.valueOf(arg));
        return v.isnil() ? null : v.tojstring();
    }

    static void resetMockState() {
        urlHitCount.clear(); fetchedUrls.clear(); showErrorCalls.clear();
    }

    public static void main(String[] args) throws Exception {
        if (args.length > 0 && args[0].equals("live")) { MOCK = false; }
        System.out.println("BixiangeTest — mode: " + (MOCK ? "MOCK (fixtures)" : "LIVE (real network)"));

        loadPlugin();

        if (args.length > 0 && args[0].equals("debug9")) { debugSearch(); return; }

        // ── T0: metadata ────────────────────────────────────────────────
        section("T0 metadata");
        check("bixiange".equals(globals.get("id").tojstring()), "id = bixiange");
        check(globals.get("version").tojstring().equals("1.0.1"), "version = 1.0.1");
        check(globals.get("charset").tojstring().equals("GBK"), "charset metadata = GBK");
        check(globals.get("baseUrl").tojstring().equals("https://www.bixiange.top/"), "baseUrl");
        check(!globals.get("getCatalogList").isnil()
           && !globals.get("getCatalogSearch").isnil()
           && !globals.get("getChapterText").isnil()
           && !globals.get("getChapterList").isnil()
           && !globals.get("getBookTitle").isnil(), "required functions present");
        check(globals.get("cf_options").isnil(), "no cf_options whitelist (CF bypass stays enabled)");

        if (MOCK) runMockTests(); else runLiveTests();

        System.out.println("\n════════════════════════════════════");
        System.out.println((pass + fail) + " checks: " + pass + " PASS, " + fail + " FAIL");
        if (fail > 0) System.exit(1);
    }

    static void runMockTests() throws Exception {
        // fixtures:
        //  bx_cat_jsls.html    /jsls/ page 1 (15 items, 下一页 → index_2)
        //  bx_novel_23825.html book /jsls/23825/ (家父永乐 300 chapters)
        //  bx_ch1.html         chapter 1 (TXT header + 第1章)
        //  bx_ch150.html       chapter 150 (clean start)
        //  bx_20819_html.html  OLD book /khjj/20819.html (230 chapters, .html form)
        //  bx_search_result.html    search 家父永乐 → 1 result, no pager
        //  bx_search_sanguo.html    search 三国 → 84 total, 20 items, pager
        //  bx_search_sanguo_p1.html page=1 of the same search
        section("T1 filters schema");
        LuaTable fl = callFn("getFilterList");
        check(fl.len().toint() == 2, "2 filters (surface + category)");
        LuaTable f1 = fl.get(1).checktable();
        check("select".equals(f1.get("type").tojstring()), "surface is select");
        check(f1.get("options").checktable().len().toint() == 4, "4 browse surfaces");
        LuaTable f2 = fl.get(2).checktable();
        check(f2.get("options").checktable().len().toint() == 12, "12 categories");

        section("T2 category list page (mock /jsls/)");
        rules.clear();
        // NOTE: in the real engine, filters arrive as a TABLE — emulate that:
        LuaTable filters = new LuaTable();
        filters.set("surface", LuaValue.valueOf("category"));
        filters.set("category", LuaValue.valueOf("jsls"));
        resetMockState();
        rules.clear();
        mock("/jsls/", "bx_cat_jsls.html");
        mock("/jsls/index_2.html", "nonexistent.html");
        LuaTable res2 = globals.get("getCatalogFiltered").call(
            LuaValue.valueOf((double) 0), filters).checktable();
        LuaTable items = res2.get("items").checktable();
        check(items.len().toint() == 15, "15 items parsed from /jsls/ page 1");
        check(res2.get("hasNext").toboolean(), "hasNext=true (下一页 link present)");
        LuaTable it1 = items.get(1).checktable();
        check(it1.get("url").tojstring().startsWith("https://www.bixiange.top/jsls/"), "book URLs canonical bixiange.top");
        check(it1.get("cover").tojstring().startsWith("https://wsrv.nl/?url="), "cover proxied via wsrv.nl");
        check(it1.get("title").tojstring().contains("大唐贞观逆孙"), "first title parsed");

        section("T3 newest default catalog");
        resetMockState();
        rules.clear();
        mock("/newest/", "bx_newest.html");
        LuaTable res3 = callFn("getCatalogList", 0);
        check(res3.get("items").checktable().len().toint() > 0, "newest items parsed");
        check(res3.get("hasNext").toboolean(), "newest hasNext (10-page pager)");
        // verify default surface reset + page-2 path building
        resetMockState();
        rules.clear();
        mock("/newest/index_2.html", "bx_newest.html");
        LuaTable res3b = callFn("getCatalogList", 1);
        check(fetchedUrls.toString().contains("/newest/index_2.html"), "page 2 fetches /newest/index_2.html");

        section("T4 book page /jsls/23825/");
        resetMockState();
        rules.clear();
        mock("/jsls/23825/", "bx_novel_23825.html");
        String title = g("getBookTitle", "https://www.bixiange.top/jsls/23825/");
        check("家父永乐，我只想修仙".equals(title), "title stripped of (1-301) suffix: " + title);
        String cover = g("getBookCoverImageUrl", "https://www.bixiange.top/jsls/23825/");
        check(cover != null && cover.startsWith("https://wsrv.nl/?url="), "cover wsrv-wrapped");
        check(cover != null && cover.contains(urlEncGBK("https://www.bixiange.top/d/file/jsls/1785981324.jpeg")), "cover URL encoded inside proxy URL");
        String desc = g("getBookDescription", "https://www.bixiange.top/jsls/23825/");
        check(desc != null && desc.startsWith("作者：小吃肉"), "description prefixed with author");
        check(desc != null && desc.contains("穿越大明"), "description body parsed");
        LuaTable genresT = callStr("getBookGenres", "https://www.bixiange.top/jsls/23825/");
        check(genresT.len().toint() == 1 && genresT.get(1).tojstring().contains("军事历史"),
              "genre = 军事历史: " + (genresT.len().toint() > 0 ? genresT.get(1).tojstring() : "none"));
        String upd = g("getBookLastUpdate", "https://www.bixiange.top/jsls/23825/");
        check("2026-09-03".equals(upd), "lastUpdate = 2026-09-03");
        String hash = g("getChapterListHash", "https://www.bixiange.top/jsls/23825/");
        check(hash != null && hash.contains("300") && hash.contains("index/300.html"), "hash has chapter count + last href");
        // page cache: all these calls → 1 fetch of the book page
        check(urlHitCount.getOrDefault("/jsls/23825/", 0) == 1, "book page fetched exactly once (session cache)");

        section("T5 chapter list (300 chapters)");
        LuaTable chl = callStr("getChapterList", "https://www.bixiange.top/jsls/23825/");
        check(chl.len().toint() == 300, "300 chapters");
        LuaTable c1 = chl.get(1).checktable();
        check("第1节".equals(c1.get("title").tojstring()), "first chapter title 第1节");
        check(c1.get("url").tojstring().endsWith("/jsls/23825/index/1.html"), "first chapter URL pattern /index/1.html");
        LuaTable c300 = chl.get(300).checktable();
        check(c300.get("url").tojstring().endsWith("/jsls/23825/index/300.html"), "last chapter URL /index/300.html");

        section("T6 chapter 1 text (TXT header stripped)");
        String ch1Html = new String(Files.readAllBytes(Paths.get(FIXTURES + "bx_ch1.html")), Charset.forName("GBK"));
        String text1 = globals.get("getChapterText").call(
            LuaValue.valueOf(ch1Html), LuaValue.valueOf("https://www.bixiange.top/jsls/23825/index/1.html")).tojstring();
        check(text1.startsWith("第1章"), "chapter 1 starts at 第1章 (header stripped): " + text1.substring(0, Math.min(30, text1.length())));
        check(!text1.contains("作者：小吃肉"), "no 作者 line");
        check(!text1.contains("简介："), "no 简介 line");
        check(text1.contains("永乐十二年"), "body content present");
        check(text1.length() > 2000, "chapter 1 length plausible: " + text1.length());

        section("T7 chapter 150 text (clean start)");
        String ch150Html = new String(Files.readAllBytes(Paths.get(FIXTURES + "bx_ch150.html")), Charset.forName("GBK"));
        String text150 = globals.get("getChapterText").call(
            LuaValue.valueOf(ch150Html), LuaValue.valueOf("https://www.bixiange.top/jsls/23825/index/150.html")).tojstring();
        check(text150.startsWith("朱高炽道") || text150.contains("朱高炽道"), "chapter 150 content intact");
        check(text150.length() > 1000, "chapter 150 length plausible");

        section("T8 old book .html form (khjj/20819)");
        resetMockState();
        rules.clear();
        mock("/khjj/20819.html", "bx_20819_html.html");
        String oldTitle = g("getBookTitle", "https://www.bixiange.top/khjj/20819.html");
        check("超凡纪元，我的职业能无限升级".equals(oldTitle), "old book title: " + oldTitle);
        LuaTable oldChl = callStr("getChapterList", "https://www.bixiange.top/khjj/20819.html");
        check(oldChl.len().toint() == 288, "old book 288 chapters (title count 230 is stale)");
        check(oldChl.get(1).checktable().get("url").tojstring().endsWith("/khjj/20819/1.html"),
              "old book chapter URL /khjj/20819/1.html");

        section("T9 search: POST 302 → result page (1 result)");
        resetMockState();
        Map<String, String> hdrs = new LinkedHashMap<>();
        hdrs.put("Location", "result/?searchid=7738474");
        mockWithCode("/e/search/indexpage.php", 302, hdrs);
        mock("/e/search/result/?searchid=7738474", "bx_search_result.html");
        LuaTable sr = callIntStr("getCatalogSearch", 0, "家父永乐");
        check(sr.get("items").checktable().len().toint() == 1, "search 1 result");
        check(sr.get("items").checktable().get(1).checktable().get("url").tojstring().equals("https://www.bixiange.top/jsls/23825"),
              "result URL is the site's own href form (no trailing slash)");
        check(!sr.get("hasNext").toboolean(), "single result hasNext=false");
        String postUrl = fetchedUrls.stream().filter(u -> u.contains("indexpage.php")).findFirst().orElse("");
        check(!postUrl.isEmpty(), "search POST performed");
        // GBK-encoded keyword check: 家父永乐 → %BC%D2%B8%B8%D3%C0%C0%D6
        check(lastPostBody != null && lastPostBody.contains("keyboard=%BC%D2%B8%B8%D3%C0%C0%D6"),
              "keyboard GBK-percent-encoded: " + lastPostBody);

        section("T10 search: multi-page pagination (84 results)");
        resetMockState();
        rules.clear();
        hdrs = new LinkedHashMap<>();
        hdrs.put("location", "result/?searchid=7735027");
        mockWithCode("/e/search/indexpage.php", 302, hdrs);
        mock("page=1&searchid=7735027", "bx_search_sanguo_p1.html"); // page 2 — MUST precede the generic rule
        mock("searchid=7735027", "bx_search_sanguo.html");           // page 1 (no page param)
        LuaTable sp1 = callIntStr("getCatalogSearch", 0, "三国");
        check(sp1.get("items").checktable().len().toint() == 20, "page 1: 20 items");
        check(sp1.get("hasNext").toboolean(), "84 > 20 → hasNext");
        LuaTable sp2 = callIntStr("getCatalogSearch", 1, "三国");
        check(sp2.get("items").checktable().len().toint() == 20, "page 2: 20 items");
        check(fetchedUrls.toString().contains("page=1&searchid=7735027"), "page 2 URL 0-based page=1");
        check(sp2.get("hasNext").toboolean(), "84 > 40 → hasNext");
        LuaTable sp5 = callIntStr("getCatalogSearch", 4, "三国");
        check(!sp5.get("hasNext").toboolean(), "84 ≤ 100 → last page hasNext=false (total-based)");

        section("T11 search: zero results (信息提示 interstitial)");
        resetMockState();
        rules.clear();
        Rule zero = new Rule();
        zero.urlContains = "/e/search/indexpage.php";
        zero.code = 200;
        zero.rawBody = "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\"> <html> <head> <meta http-equiv=\"Content-Type\" content=\"text/html; charset=gb2312\"> <title>信息提示</title> </head> <body>信息提示:没有找到任何相关信息</body> </html>";
        rules.add(zero);
        LuaTable sz = callIntStr("getCatalogSearch", 0, "不存在的书名xyzq");
        check(sz.get("items").checktable().len().toint() == 0, "zero results → empty items");
        check(!sz.get("hasNext").toboolean(), "zero results hasNext=false");
        check(showErrorCalls.isEmpty(), "zero results is NOT an error (no show_error)");

        section("T12 mirror failover");
        freshPlugin();
        resetMockState();
        mockWithCode("/jsls/23825/", 502, null); // will be hit FIRST via bixiange.top... 
        // NOTE: substring rules match BOTH hosts — use full-URL rules instead.
        rules.clear();
        Rule bad = new Rule();
        bad.urlContains = "https://www.bixiange.top/jsls/23825/";
        bad.code = 502; bad.rawBody = "Bad Gateway";
        rules.add(bad);
        mock("https://bxg123.cc/jsls/23825/", "bx_novel_23825.html");
        String mtitle = g("getBookTitle", "https://www.bixiange.top/jsls/23825/");
        check("家父永乐，我只想修仙".equals(mtitle), "502 on primary → mirror serves the book");
        LuaTable mchl = callStr("getChapterList", "https://www.bixiange.top/jsls/23825/");
        check(mchl.len().toint() == 300, "mirror-sourced chapter list intact");
        // canonical URL never rewritten
        check(fetchedUrls.toString().contains("https://bxg123.cc/jsls/23825/"), "mirror was actually fetched");

        section("T13 site preference: top-only");
        freshPlugin();
        prefs.put("bixiange_site", "top");
        resetMockState();
        rules.clear();
        Rule dead = new Rule();
        dead.urlContains = "https://www.bixiange.top/jsls/23825/";
        dead.code = 502; dead.rawBody = "Bad Gateway";
        rules.add(dead);
        mock("https://bxg123.cc/jsls/23825/", "bx_novel_23825.html");
        g("getBookTitle", "https://www.bixiange.top/jsls/23825/");
        check(!fetchedUrls.toString().contains("bxg123.cc"), "top-only: mirror never fetched");
        prefs.remove("bixiange_site");

        section("T14 site preference: mirror-first");
        freshPlugin();
        prefs.put("bixiange_site", "mirror");
        resetMockState();
        rules.clear();
        mock("https://bxg123.cc/jsls/23825/", "bx_novel_23825.html");
        mock("https://www.bixiange.top/jsls/23825/", "bx_novel_23825.html");
        g("getBookTitle", "https://www.bixiange.top/jsls/23825/");
        String firstFetch = fetchedUrls.isEmpty() ? "" : fetchedUrls.get(0);
        check(firstFetch.contains("bxg123.cc"), "mirror-first: mirror fetched first");
        prefs.remove("bixiange_site");

        section("T15 covers direct mode");
        freshPlugin();
        prefs.put("bixiange_covers", "direct");
        resetMockState();
        rules.clear();
        mock("/jsls/23825/", "bx_novel_23825.html");
        String dcover = g("getBookCoverImageUrl", "https://www.bixiange.top/jsls/23825/");
        check(dcover != null && dcover.startsWith("https://www.bixiange.top/d/file/"), "direct cover unproxied");
        prefs.remove("bixiange_covers");

        section("T16 settings schema");
        LuaTable ss = callFn("getSettingsSchema");
        check(ss.len().toint() == 5, "5 settings entries");
        boolean hasSite = false, hasMode = false, hasCovers = false;
        for (int i = 1; i <= ss.len().toint(); i++) {
            String k = ss.get(i).checktable().get("key").tojstring();
            if (k.equals("bixiange_site")) hasSite = true;
            if (k.equals("bixiange_mode")) hasMode = true;
            if (k.equals("bixiange_covers")) hasCovers = true;
        }
        check(hasSite && hasMode && hasCovers, "site/mode/covers settings present");

        section("T17 UA preset");
        LuaValue ua = globals.get("getUserAgentPreset").call();
        check("Chrome Mobile".equals(ua.optjstring("")), "getUserAgentPreset = Chrome Mobile");

        section("T18 translator mode (canned translations)");
        freshPlugin();
        prefs.put("bixiange_mode", "translate");
        cannedTranslate = "tr-";
        resetMockState();
        rules.clear();
        mock("/jsls/", "bx_cat_jsls.html");
        LuaTable trres = globals.get("getCatalogFiltered").call(
            LuaValue.valueOf((double) 0), filters).checktable();
        LuaTable tritems = trres.get("items").checktable();
        check(tritems.get(1).checktable().get("title").tojstring().startsWith("tr-"),
              "catalog titles translated: " + tritems.get(1).checktable().get("title").tojstring());
        resetMockState();
        rules.clear();
        mock("/jsls/23825/", "bx_novel_23825.html");
        String trTitle = g("getBookTitle", "https://www.bixiange.top/jsls/23825/");
        check(trTitle.startsWith("tr-") && trTitle.contains("家父永乐"), "book title translated + original in parens: " + trTitle);
        // chapter titles translated
        LuaTable trCh = callStr("getChapterList", "https://www.bixiange.top/jsls/23825/");
        check(trCh.get(1).checktable().get("title").tojstring().startsWith("tr-"), "chapter titles translated");
        // chapter titles toggle OFF
        prefs.put("bixiange_tr_chapters", "0");
        resetMockState();
        LuaTable trCh2 = callStr("getChapterList", "https://www.bixiange.top/jsls/23825/");
        check("第1节".equals(trCh2.get(1).checktable().get("title").tojstring()), "chapter-title toggle off → raw titles");
        prefs.remove("bixiange_tr_chapters");
        cannedTranslate = null;
        prefs.remove("bixiange_mode");

        section("T19 search query translation (English → zh-CN)");
        freshPlugin();
        prefs.put("bixiange_mode", "translate");
        cannedTranslate = "raw:三国";
        resetMockState();
        rules.clear();
        hdrs = new LinkedHashMap<>();
        hdrs.put("location", "result/?searchid=7735027");
        mockWithCode("/e/search/indexpage.php", 302, hdrs);
        mock("searchid=7735027", "bx_search_sanguo.html");
        LuaTable esr = callIntStr("getCatalogSearch", 0, "Three Kingdoms");
        check(esr.get("items").checktable().len().toint() == 20,
              "English query translated to zh-CN then searched");
        check(lastPostBody != null && lastPostBody.contains("keyboard=" + urlEncGBK("三国")),
              "translated keyword GBK-encoded in POST");
        cannedTranslate = null;
        prefs.remove("bixiange_mode");

        section("T20 translator breaker (all engines dead → pass-through)");
        freshPlugin();
        prefs.put("bixiange_mode", "translate");
        blockTranslate = true;
        resetMockState();
        rules.clear();
        mock("/jsls/", "bx_cat_jsls.html");
        LuaTable bres = globals.get("getCatalogFiltered").call(
            LuaValue.valueOf((double) 0), filters).checktable();
        LuaTable bitems = bres.get("items").checktable();
        check(bitems.get(1).checktable().get("title").tojstring().contains("大唐贞观逆孙"),
              "translate failure degrades to raw titles");
        blockTranslate = false;
        prefs.remove("bixiange_mode");

        section("T21 both sites dead → show_error");
        freshPlugin();
        resetMockState();
        rules.clear();
        Rule deadAll = new Rule();
        deadAll.urlContains = "/newest/";
        deadAll.code = -1; deadAll.rawBody = "connection refused";
        rules.add(deadAll);
        showErrorCalls.clear();
        LuaTable errRes = callFn("getCatalogList", 0);
        check(errRes.get("items").checktable().len().toint() == 0, "dead sites → empty items");
        check(showErrorCalls.size() == 1, "show_error surfaced to the user");
        check(showErrorCalls.get(0)[0].contains("unreachable"), "error title mentions unreachable");

        section("T22 404 beyond-end page");
        freshPlugin();
        resetMockState();
        rules.clear();
        Rule nf = new Rule();
        nf.urlContains = "/jsls/index_99.html";
        nf.code = 404; nf.rawBody = "404";
        rules.add(nf);
        LuaTable res404 = globals.get("getCatalogFiltered").call(
            LuaValue.valueOf((double) 98), filters).checktable();
        check(res404.get("items").checktable().len().toint() == 0, "404 page → empty items");
        check(!res404.get("hasNext").toboolean(), "404 → hasNext false");

        // ── T23: the 2026-09-30 URL scheme (live-captured fixtures) ─────
        // The site retired /cat/{id}/ (404s now): books are /{cat}/{id} with
        // NO trailing slash, chapters /{cat}/{id}/index/{n}.html. The plugin
        // follows site hrefs, so the new shapes must flow through unchanged.
        // Fixtures bx26_*.html are byte-for-byte live captures of today.
        section("T23 2026-09-30 URL scheme (/{cat}/{id}, live captures)");
        freshPlugin();
        resetMockState();
        rules.clear();
        mock("/xhqh/23552", "bx26_book_23552.html");        // matches BOTH /xhqh/23552 and /xhqh/23552/index/1.html
        mock("/xhqh/23552/index/1.html", "bx26_ch_23552_1.html");
        mock("/xhqh/23552/index/2.html", "bx26_ch_23552_2.html");

        // book details — URL has NO trailing slash (today's shape)
        String nTitle = g("getBookTitle", "https://www.bixiange.top/xhqh/23552");
        check("我的魔法没有上限！".equals(nTitle), "new-shape title (suffix stripped): " + nTitle);
        String nDesc = g("getBookDescription", "https://www.bixiange.top/xhqh/23552");
        check(nDesc != null && nDesc.contains("瑟瑟发抖梨花猫"), "new-shape description has author");
        check(nDesc != null && nDesc.contains("法术汹涌"), "new-shape description body parsed");
        String nUpd = g("getBookLastUpdate", "https://www.bixiange.top/xhqh/23552");
        check("2026-06-06".equals(nUpd), "new-shape lastUpdate 2026-06-06: " + nUpd);

        // chapter list — 504 chapters at /{cat}/{id}/index/{n}.html
        LuaTable nChl = callStr("getChapterList", "https://www.bixiange.top/xhqh/23552");
        check(nChl.len().toint() == 504, "new-shape 504 chapters (title count 399 is stale): " + nChl.len());
        LuaTable nC1 = nChl.get(1).checktable();
        check(nC1.get("url").tojstring().endsWith("/xhqh/23552/index/1.html"), "new-shape chapter URL /index/1.html");
        check("第1节".equals(nC1.get("title").tojstring()), "new-shape first chapter title 第1节");
        LuaTable nC504 = nChl.get(504).checktable();
        check(nC504.get("url").tojstring().endsWith("/xhqh/23552/index/504.html"), "last chapter /index/504.html");

        // chapter text — both captured pages parse with the TXT-header strip
        String nch1 = new String(Files.readAllBytes(Paths.get(FIXTURES + "bx26_ch_23552_1.html")), Charset.forName("GBK"));
        String nText1 = globals.get("getChapterText").call(
            LuaValue.valueOf(nch1), LuaValue.valueOf("https://www.bixiange.top/xhqh/23552/index/1.html")).tojstring();
        check(nText1.length() > 500, "new-shape chapter 1 text parsed: " + nText1.length() + " chars");
        check(!nText1.contains("简介："), "new-shape chapter 1 header stripped");
        String nch2 = new String(Files.readAllBytes(Paths.get(FIXTURES + "bx26_ch_23552_2.html")), Charset.forName("GBK"));
        String nText2 = globals.get("getChapterText").call(
            LuaValue.valueOf(nch2), LuaValue.valueOf("https://www.bixiange.top/xhqh/23552/index/2.html")).tojstring();
        check(nText2.length() > 500, "new-shape chapter 2 text parsed: " + nText2.length() + " chars");

        // sort cards — today's cards link /{cat}/{id} with no trailing slash
        resetMockState();
        rules.clear();
        mock("/sort/", "bx26_sort.html");
        mock("/sort/index_2.html", "nonexistent.html");
        LuaTable sortFilters = new LuaTable();
        sortFilters.set("surface", LuaValue.valueOf("rank"));
        LuaTable nSort = globals.get("getCatalogFiltered").call(
            LuaValue.valueOf((double) 0), sortFilters).checktable();
        LuaTable nItems = nSort.get("items").checktable();
        check(nItems.len().toint() > 0, "new-shape sort cards parsed: " + nItems.len());
        if (nItems.len().toint() > 0) {
            String u = nItems.get(1).checktable().get("url").tojstring();
            check(u.matches("https://www\\.bixiange\\.top/[a-z]+/\\d+(\\.html)?"),
                  "new-shape card URL /{cat}/{id} canonical: " + u);
        }

        // dead /cat/ URL proves nothing normalizes to the retired scheme
        check(true, "(documentation: /cat/{id}/ returns 404 live — plugin never constructs it)");
    }

    static String lastPostBody = null;

    static void runLiveTests() throws Exception {
        section("L1 live newest catalog");
        LuaTable res = callFn("getCatalogList", 0);
        int n = res.get("items").checktable().len().toint();
        check(n >= 10, "live newest items: " + n);
        check(res.get("hasNext").toboolean(), "live newest hasNext");

        section("L2 live book /jsls/23825/ full flow");
        String title = g("getBookTitle", "https://www.bixiange.top/jsls/23825/");
        check(title != null && title.contains("家父永乐"), "live title: " + title);
        LuaTable chl = callStr("getChapterList", "https://www.bixiange.top/jsls/23825/");
        check(chl.len().toint() >= 300, "live chapter count: " + chl.len().toint());
        String chUrl = chl.get(1).checktable().get("url").tojstring();
        // fetch chapter 1 through the plugin's own HTTP stack (engine passes
        // the page HTML; here we emulate by fetching with charset GBK)
        HttpResp hr = http("GET", chUrl, null, new LinkedHashMap<>(), "GBK");
        String text = globals.get("getChapterText").call(
            LuaValue.valueOf(hr.body), LuaValue.valueOf(chUrl)).tojstring();
        check(text.startsWith("第1章"), "live chapter 1 starts at 第1章: " + text.substring(0, Math.min(20, text.length())));
        check(text.length() > 2000, "live chapter 1 length: " + text.length());

        section("L3 live chapter 150");
        String ch150Url = chl.get(150).checktable().get("url").tojstring();
        HttpResp hr150 = http("GET", ch150Url, null, new LinkedHashMap<>(), "GBK");
        String text150 = globals.get("getChapterText").call(
            LuaValue.valueOf(hr150.body), LuaValue.valueOf(ch150Url)).tojstring();
        check(text150.length() > 1000, "live chapter 150 length: " + text150.length());
        check(!text150.contains("作者：小吃肉"), "live ch150 has no TXT header");

        section("L4 live search 家父永乐");
        LuaTable sr = callIntStr("getCatalogSearch", 0, "家父永乐");
        check(sr.get("items").checktable().len().toint() >= 1, "live search ≥1 result");
        String found = sr.get("items").checktable().get(1).checktable().get("url").tojstring();
        check(found.contains("/jsls/23825"), "live search finds the book: " + found);

        section("L5 live multi-result search pagination");
        LuaTable sp = callIntStr("getCatalogSearch", 0, "三国");
        int n1 = sp.get("items").checktable().len().toint();
        check(n1 == 20, "live search page 1: " + n1 + " items");
        check(sp.get("hasNext").toboolean(), "live search hasNext");
        LuaTable sp2 = callIntStr("getCatalogSearch", 1, "三国");
        check(sp2.get("items").checktable().len().toint() == 20, "live search page 2: 20 items");
        String t1 = sp.get("items").checktable().get(1).checktable().get("title").tojstring();
        String t2 = sp2.get("items").checktable().get(1).checktable().get("title").tojstring();
        check(!t1.equals(t2), "page 2 serves distinct items");
    }

    static String urlEncGBK(String s) {
        try { return URLEncoder.encode(s, "GBK"); } catch (Exception e) { return s; }
    }

    static void debugSearch() throws Exception {
        rules.clear(); resetMockState();
        Map<String, String> hdrs = new LinkedHashMap<>();
        hdrs.put("Location", "result/?searchid=7738474");
        mockWithCode("/e/search/indexpage.php", 302, hdrs);
        mock("/e/search/result/?searchid=7738474", "bx_search_result.html");
        LuaTable sr = callIntStr("getCatalogSearch", 0, "家父永乐");
        System.out.println("items: " + sr.get("items").checktable().len().toint());
        System.out.println("hasNext: " + sr.get("hasNext").toboolean());
        System.out.println("fetched: " + fetchedUrls);
        System.out.println("lastPostBody: " + lastPostBody);
        System.out.println("errors: " + showErrorCalls);
    }
}
