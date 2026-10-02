import org.luaj.vm2.*;
import org.luaj.vm2.lib.*;
import org.luaj.vm2.lib.jse.JsePlatform;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Element;
import org.jsoup.nodes.Node;
import org.jsoup.nodes.TextNode;

import java.io.*;
import java.nio.file.*;
import java.text.Normalizer;
import java.util.*;

/**
 * NoveLA-faithful harness for the WuxiaBox plugin (en/wuxiabox.lua v2+,
 * upgraded from the community wuxiabox.lua v1.0.1 base).
 * All HTTP is MOCKED from fixture files under research/wuxiabox/.
 * html_text is a faithful port of NoveLA's TextExtractor (<p> → "\n\n",
 * <br> → "\n") — the paragraph-preservation guarantee is under test.
 */
public class WuxiaboxTest {

    static final String FIX = "/home/z/my-project/research/wuxiabox/";
    static Globals globals;
    static LuaValue plugin;
    static Map<String, String> prefs = new HashMap<>();

    // ── mock HTTP layer ──────────────────────────────────────────────────────
    static List<String> requestedUrls = new ArrayList<>();
    // request headers per hit (parallel to requestedUrls)
    static List<Map<String, String>> requestHeaderLog = new ArrayList<>();

    static Map<String, String> optsHeaders(LuaValue opts) {
        Map<String, String> out = new HashMap<>();
        if (opts != null && opts.istable()) {
            LuaValue h = opts.checktable().get("headers");
            if (h != null && h.istable()) {
                LuaValue k = LuaValue.NIL;
                while (true) {
                    Varargs n = h.checktable().next(k);
                    if (n.arg1().isnil()) break;
                    k = n.arg1();
                    out.put(n.arg1().tojstring().toLowerCase(), n.arg(2).tojstring());
                }
            }
        }
        return out;
    }

    static boolean headerSeen(String urlSubstr, String headerKey, String expected) {
        for (int i = 0; i < requestedUrls.size() && i < requestHeaderLog.size(); i++) {
            if (requestedUrls.get(i).contains(urlSubstr)) {
                String v = requestHeaderLog.get(i).get(headerKey.toLowerCase());
                if (v != null && v.equalsIgnoreCase(expected)) return true;
            }
        }
        return false;
    }

    static class Rule {
        String match; int code = 200; String body = ""; String file;
        String bodyMatch; // optional: rule only applies when the REQUEST body contains this
        Map<String, String> headers = new HashMap<>();
        LinkedList<String[]> seq; // {"code","bodyOrFileMarker"} polled per hit
        java.util.function.UnaryOperator<String> transform;
        Rule(String match) { this.match = match; }
    }
    static List<Rule> rules = new ArrayList<>();

    static String file(String name) {
        try { return new String(Files.readAllBytes(Paths.get(FIX + name)), "UTF-8"); }
        catch (Exception e) { return "<html><body>MISSING FIXTURE " + name + "</body></html>"; }
    }

    static Rule on(String match) { Rule r = new Rule(match); rules.add(r); return r; }

    static String[] pollSeq(Rule r) {
        if (r.seq == null || r.seq.isEmpty()) return null;
        String[] first = r.seq.poll();
        if (r.seq.isEmpty()) r.seq.add(first); // stick on last
        return first;
    }

    static LuaTable http(String method, String url, String body, Map<String, String> headers) {
        requestedUrls.add(method + " " + url);
        requestHeaderLog.add(headers == null ? new HashMap<>() : headers);
        for (Rule r : rules) {
            if (!url.contains(r.match)) continue;
            if (r.bodyMatch != null && (body == null || !body.contains(r.bodyMatch))) continue;
            int code = r.code; String respBody = r.body;
            if (r.file != null) respBody = file(r.file);
            if (r.seq != null) {
                String[] hit = pollSeq(r);
                if (hit != null) {
                    code = Integer.parseInt(hit[0]);
                    respBody = hit[1].startsWith("@") ? file(hit[1].substring(1)) : hit[1];
                }
            }
            if (r.transform != null) respBody = r.transform.apply(respBody);
            LuaTable t = new LuaTable();
            t.set("success", LuaValue.valueOf(code >= 200 && code < 300));
            t.set("body", LuaValue.valueOf(respBody));
            t.set("code", LuaValue.valueOf(code));
            LuaTable h = new LuaTable();
            for (Map.Entry<String, String> e : r.headers.entrySet()) {
                LuaTable vt = new LuaTable();
                vt.set(1, LuaValue.valueOf(e.getValue()));
                h.set(e.getKey().toLowerCase(), vt);
            }
            t.set("headers", h);
            return t;
        }
        LuaTable t = new LuaTable();
        t.set("success", LuaValue.FALSE);
        t.set("body", LuaValue.valueOf("no mock for " + url));
        t.set("code", LuaValue.valueOf(404));
        t.set("headers", new LuaTable());
        return t;
    }

    // ── NoveLA API (faithful ports) ─────────────────────────────────────────

    static void registerApi(Globals g) {
        g.set("http_get", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2) {
                return http("GET", a1.checkjstring(), null, optsHeaders(a2));
            }
        });
        g.set("http_post", new ThreeArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2, LuaValue a3) {
                return http("POST", a1.checkjstring(), a2.checkjstring(), optsHeaders(a3));
            }
        });
        g.set("get_preference", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) { return LuaValue.valueOf(prefs.getOrDefault(a.checkjstring(), "")); }
        });
        g.set("set_preference", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a, LuaValue b) { prefs.put(a.checkjstring(), b.tojstring()); return LuaValue.NIL; }
        });
        g.set("html_select", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2) {
                try {
                    Element el = elementFromValue(a1);
                    org.jsoup.select.Elements elems = el != null
                        ? el.select(a2.checkjstring())
                        : Jsoup.parse(a1.checkjstring()).select(a2.checkjstring());
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
                    Element first = el != null
                        ? el.selectFirst(a2.checkjstring())
                        : Jsoup.parse(a1.checkjstring()).selectFirst(a2.checkjstring());
                    return first != null ? elementToTable(first) : LuaValue.NIL;
                } catch (Exception e) { return LuaValue.NIL; }
            }
        });
        g.set("html_attr", new ThreeArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2, LuaValue a3) {
                try {
                    Element el = elementFromValue(a1);
                    Element target = el != null
                        ? el.selectFirst(a2.checkjstring())
                        : Jsoup.parse(a1.checkjstring()).selectFirst(a2.checkjstring());
                    return LuaValue.valueOf(target != null ? target.attr(a3.checkjstring()) : "");
                } catch (Exception e) { return LuaValue.valueOf(""); }
            }
        });
        // Faithful port of NoveLA TextExtractor.get()
        g.set("html_text", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) {
                try {
                    Element el = elementFromValue(a);
                    org.jsoup.nodes.Node node = el;
                    if (node == null) {
                        org.jsoup.nodes.Document doc = Jsoup.parseBodyFragment(a.tojstring());
                        node = doc.body();
                    }
                    return LuaValue.valueOf(textExtract(node));
                } catch (Exception e) { return LuaValue.NIL; }
            }
        });
        g.set("html_remove", new VarArgFunction() {
            @Override public Varargs invoke(Varargs args) {
                try {
                    Element el = elementFromValue(args.arg(1));
                    org.jsoup.nodes.Document doc = Jsoup.parse(args.arg(1).checkjstring());
                    for (int i = 2; i <= args.narg(); i++) {
                        String sel = args.arg(i).optjstring(null);
                        if (sel != null && !sel.isBlank()) doc.select(sel).remove();
                    }
                    return LuaValue.valueOf(doc.body().html());
                } catch (Exception e) { return args.arg(1); }
            }
        });
        g.set("url_encode", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) {
                try { return LuaValue.valueOf(java.net.URLEncoder.encode(a.checkjstring(), "UTF-8")); }
                catch (Exception e) { return LuaValue.NIL; }
            }
        });
        g.set("url_resolve", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2) {
                try { return LuaValue.valueOf(new java.net.URI(a1.checkjstring()).resolve(a2.checkjstring()).toString()); }
                catch (Exception e) { return a2; }
            }
        });
        g.set("regex_replace", new ThreeArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2, LuaValue a3) {
                try { return LuaValue.valueOf(a1.checkjstring().replaceAll(a2.checkjstring(), a3.checkjstring())); }
                catch (Exception e) { return a1; }
            }
        });
        g.set("regex_match", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2) {
                try {
                    LuaTable t = new LuaTable();
                    java.util.regex.Matcher m = java.util.regex.Pattern.compile(a2.checkjstring()).matcher(a1.checkjstring());
                    int i = 1;
                    while (m.find()) t.set(i++, LuaValue.valueOf(m.group()));
                    return t;
                } catch (Exception e) { return new LuaTable(); }
            }
        });
        g.set("string_normalize", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) {
                return LuaValue.valueOf(Normalizer.normalize(a.optjstring(""), Normalizer.Form.NFKC));
            }
        });
        g.set("string_trim", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) { return LuaValue.valueOf(a.optjstring("").trim()); }
        });
        g.set("string_starts_with", new TwoArgFunction() {
            @Override public LuaValue call(LuaValue a1, LuaValue a2) { return LuaValue.valueOf(a1.optjstring("").startsWith(a2.optjstring(""))); }
        });
        g.set("string_clean", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) {
                String s = a.optjstring("");
                String n = Normalizer.normalize(s, Normalizer.Form.NFKC).replaceAll("\\s+", " ").trim();
                return LuaValue.valueOf(n);
            }
        });
        g.set("json_parse", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) { return LuaValue.NIL; }
        });
        g.set("json_stringify", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) { return LuaValue.valueOf("{}"); }
        });
        g.set("sleep", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) {
                try { Thread.sleep(a.isnil() ? 500 : (long) a.todouble()); } catch (InterruptedException ignored) {}
                return LuaValue.NIL;
            }
        });
        g.set("log_info", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) { System.out.println("[INFO] " + a.optjstring("")); return LuaValue.NIL; }
        });
        g.set("log_error", new OneArgFunction() {
            @Override public LuaValue call(LuaValue a) { System.out.println("[ERROR] " + a.optjstring("")); return LuaValue.NIL; }
        });
        g.set("os_time", new ZeroArgFunction() {
            @Override public LuaValue call() { return LuaValue.valueOf(System.currentTimeMillis()); }
        });
    }

    // TextExtractor port ─────────────────────────────────────────────────────
    static String textExtract(Node node) {
        List<Node> children = node.childNodes();
        if (children.isEmpty()) return "";
        StringBuilder sb = new StringBuilder();
        for (Node child : children) {
            String name = child.nodeName();
            if (name.equals("p")) sb.append(pTraverse(child));
            else if (name.equals("br")) sb.append("\n");
            else if (name.equals("hr")) sb.append("\n\n");
            else if (name.equals("img")) sb.append("");
            else if (child instanceof TextNode) sb.append(((TextNode) child).text().trim());
            else sb.append(nodeTextTraverse(child));
        }
        return sb.toString();
    }
    static String pTraverse(Node node) {
        StringBuilder inner = new StringBuilder();
        for (Node child : node.childNodes()) {
            if (child.nodeName().equals("br")) inner.append("\n");
            else if (child instanceof TextNode) inner.append(((TextNode) child).text());
            else if (child.nodeName().equals("img")) { /* skip */ }
            else inner.append(pTraverseInner(child));
        }
        String paragraph = inner.toString().trim();
        return paragraph.isEmpty() ? "" : paragraph + "\n\n";
    }
    static String pTraverseInner(Node node) {
        StringBuilder inner = new StringBuilder();
        for (Node child : node.childNodes()) {
            if (child.nodeName().equals("br")) inner.append("\n");
            else if (child instanceof TextNode) inner.append(((TextNode) child).text());
            else inner.append(pTraverseInner(child));
        }
        return inner.toString();
    }
    static String nodeTextTraverse(Node node) {
        List<Node> children = node.childNodes();
        if (children.isEmpty()) return "";
        StringBuilder sb = new StringBuilder();
        for (Node child : children) {
            String name = child.nodeName();
            if (name.equals("p")) sb.append(pTraverse(child));
            else if (name.equals("br")) sb.append("\n");
            else if (name.equals("hr")) sb.append("\n\n");
            else if (name.equals("img")) sb.append("");
            else if (child instanceof TextNode) {
                String text = ((TextNode) child).text().trim();
                if (!text.isEmpty()) sb.append(text).append("\n\n");
            } else sb.append(nodeTextTraverse(child));
        }
        return sb.toString();
    }

    // element ⇄ Lua ──────────────────────────────────────────────────────────
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
                    case "get_text": value = new ZeroArgFunction() { @Override public LuaValue call() { return LuaValue.valueOf(el.text()); } }; break;
                    case "get_html": value = new ZeroArgFunction() { @Override public LuaValue call() { return LuaValue.valueOf(el.html()); } }; break;
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
    static Element elementFromValue(LuaValue v) {
        if (v.istable()) {
            LuaValue user = v.checktable().get("__element");
            if (user.isuserdata(Element.class)) return (Element) user.touserdata(Element.class);
        }
        return null;
    }

    // ── test helpers ────────────────────────────────────────────────────────
    static int passed = 0, failed = 0;
    static List<String> failures = new ArrayList<>();

    static void check(String name, boolean cond) { check(name, cond, null); }
    static void check(String name, boolean cond, String detail) {
        if (cond) { passed++; System.out.println("  PASS: " + name); }
        else { failed++; failures.add(name + (detail != null ? " — " + detail : "")); System.out.println("  FAIL: " + name + (detail != null ? " — " + detail : "")); }
    }
    static LuaValue call(String fn, Object... args) {
        LuaValue f = plugin.get(fn);
        if (f.isnil()) return LuaValue.NIL;
        LuaValue[] ls = new LuaValue[args.length];
        for (int i = 0; i < args.length; i++) {
            Object a = args[i];
            if (a == null) ls[i] = LuaValue.NIL;
            else if (a instanceof String) ls[i] = LuaValue.valueOf((String) a);
            else if (a instanceof Integer) ls[i] = LuaValue.valueOf((Integer) a);
            else if (a instanceof LuaTable) ls[i] = (LuaTable) a;
            else ls[i] = LuaValue.valueOf(String.valueOf(a));
        }
        return f.invoke(ls).arg1();
    }
    static int len(LuaValue t) { return t.checktable().length(); }
    static String str(LuaValue t, String k) { return t.checktable().get(k).optjstring(""); }
    static int intOf(LuaValue t, String k) {
        LuaValue v = t.checktable().get(k);
        try { return v.isnumber() ? v.toint() : Integer.parseInt(v.optjstring("0").trim()); }
        catch (Exception e) { return 0; }
    }
    static boolean boolOf(LuaValue t, String k) { return t.checktable().get(k).toboolean(); }
    static int count(String s, String needle) {
        int c = 0, i = 0;
        while ((i = s.indexOf(needle, i)) >= 0) { c++; i += needle.length(); }
        return c;
    }
    static int urlHits(String substr) {
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
    static LuaTable filt(Object... kv) {
        LuaTable t = new LuaTable();
        for (int i = 0; i + 1 < kv.length; i += 2) t.set((String) kv[i], LuaValue.valueOf(String.valueOf(kv[i + 1])));
        return t;
    }

    // ── tests ───────────────────────────────────────────────────────────────
    public static void main(String[] args) throws Exception {
        prefs.put("wuxiabox_chapter_pace_ms", "0"); // fast tests
        globals = JsePlatform.standardGlobals();
        registerApi(globals);
        plugin = globals.load(new FileReader("/home/z/my-project/download/wuxiabox.lua"), "wuxiabox.lua").call();
        plugin = globals; // functions are globals (the chunk returns nothing)
        System.out.println("plugin loaded. id=" + globals.get("id") + " v" + globals.get("version"));

        // ── T0: identity — must upgrade the community wuxiabox slot in place ──
        System.out.println("\n== T0: identity ==");
        check("id is wuxiabox (updates base v1.0.1 in place)", globals.get("id").tojstring().equals("wuxiabox"), globals.get("id").tojstring());
        check("version is 2.3.0", globals.get("version").tojstring().equals("2.3.0"), globals.get("version").tojstring());
        check("getUserAgentPreset registered (2.2.0 CF improvement)", !globals.get("getUserAgentPreset").isnil()
                && call("getUserAgentPreset").tojstring().equals("Chrome Mobile"),
                luaIds(globals.get("getUserAgentPreset")));
        check("baseUrl is wuxiabox.com", globals.get("baseUrl").tojstring().contains("wuxiabox.com"));

        final String NOVEL = "https://www.wuxiabox.com/novel/royal-gold-medal-county-magistrate.html";
        final String NOVEL2 = "https://www.wuxiabox.com/novel/trxs11010.html";

        // ── T1: filter list structure ────────────────────────────────────────
        System.out.println("\n== T1: getFilterList ==");
        LuaValue fl = call("getFilterList");
        check("5 filters (2.2.0: popular_tags + tag_search merged into one tag_input)", len(fl) == 5, "got " + len(fl));
        LuaValue f1 = fl.get(1);
        check("filter[1] browse select", str(f1, "type").equals("select") && str(f1, "key").equals("browse"));
        LuaValue catF = fl.get(2);
        check("category has 57 options", len(catF.get("options")) == 57, "got " + len(catF.get("options")));
        LuaValue tagInF = null;
        for (int i = 1; i <= len(fl); i++) if (str(fl.get(i), "key").equals("tags")) tagInF = fl.get(i);
        check("tags is a tag_input (2.2.0 searchable picker)", tagInF != null && str(tagInF, "type").equals("tag_input"), tagInF == null ? "nil" : str(tagInF, "type"));
        check("tags picker has 756 options (755 curated + honghuang keyword)", tagInF != null && len(tagInF.get("options")) == 756, "got " + (tagInF == null ? "?" : len(tagInF.get("options"))));
        check("tags picker allowCustom=false (options only)", tagInF != null && !tagInF.get("allowCustom").toboolean());
        boolean hasHonghuang2 = false;
        if (tagInF != null) for (int i = 1; i <= len(tagInF.get("options")); i++)
            if (tagInF.get("options").get(i).get("value").tojstring().equals("honghuang")) hasHonghuang2 = true;
        check("tags picker includes the honghuang family keyword", hasHonghuang2);
        boolean noTagSearchText = true;
        for (int i = 1; i <= len(fl); i++) if (str(fl.get(i), "key").equals("tag_search")) noTagSearchText = false;
        check("tag_search text filter removed (2.2.0 — tag_input replaces it)", noTagSearchText);
        boolean noPopularCheckbox = true;
        for (int i = 1; i <= len(fl); i++) if (str(fl.get(i), "key").equals("popular_tags")) noPopularCheckbox = false;
        check("popular_tags checkbox removed (2.2.0)", noPopularCheckbox);
        boolean noLetterFilter = true;
        for (int i = 1; i <= len(fl); i++) {
            if (str(fl.get(i), "key").equals("tag_letter")) { noLetterFilter = false; break; }
        }
        check("A-Z tag_letter filter removed (2.1.0)", noLetterFilter);

        // ── T2: tagSearchResolve (real 6723-tag index) ────────────────────────
        System.out.println("\n== T2: tagSearchResolve ==");
        LuaValue r2 = call("tagSearchResolve", "ancient china", "");
        check("'ancient china' resolves (space-insensitive) and includes tag 34", luaIds(r2).contains(",34") || luaIds(r2).startsWith("[34"), luaIds(r2));
        LuaValue r2a = call("tagSearchResolve", "maleprot", "");
        check("'maleprot' resolves (squashed name)", len(r2a) >= 1, luaIds(r2a));
        LuaValue r2b = call("tagSearchResolve", "34", "");
        check("numeric id '34' resolves to itself", len(r2b) == 1 && r2b.get(1).tojstring().equals("34"), luaIds(r2b));
        LuaValue r2c = call("tagSearchResolve", "ancient", "A");
        check("'ancient' scoped to letter A resolves", len(r2c) >= 1, luaIds(r2c));
        LuaValue r2d = call("tagSearchResolve", "adapted*", "");
        check("'adapted*' wildcard resolves the Adapted-to-* family (curated: exactly 3)", len(r2d) == 3, luaIds(r2d));
        boolean err = false;
        try { call("tagSearchResolve", "zzz-no-such-tag", ""); } catch (LuaError e) { err = true; }
        check("unknown token raises error", err);
        boolean unionErr = false;
        try { call("tagSearchResolve", "e", ""); } catch (LuaError e) { unionErr = e.getMessage().contains("parallel requests"); }
        check("huge substring match raises union-cap error", unionErr);
        LuaValue r2e = call("tagSearchResolve", "honghuang", "");
        check("'honghuang' expands to the whole truncated Honghuang* family (picker value)", len(r2e) >= 4, luaIds(r2e));
        LuaValue r2f = call("tagSearchResolve", "12,225", "");
        check("'12,225' resolves both canonical popular-tag ids (2.2.0: 1079 is a duplicate id, not curated)", len(r2f) == 2, luaIds(r2f));

        // ── mocks for catalog tests ──────────────────────────────────────────
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        Rule onclick0 = on("/list/all/all-onclick-0.html");
        onclick0.file = "list_newstime.html";
        onclick0.transform = b -> b.replace("newstime", "onclick");
        Rule onclick1 = on("/list/all/all-onclick-1.html");
        onclick1.file = "list_newstime.html";
        onclick1.transform = b -> b.replace("newstime", "onclick");
        on("/list/comedy/all-newstime-0.html").file = "list_newstime.html";
        on("/updates/").file = "updates.html";
        on("/tags/34-0.html").file = "tag_34.html";
        // single-result search: RELATIVE Location + result page WITHOUT any
        // searchid (the exact live shape that broke v2.0.0's search gate).
        // NOTE: must be registered BEFORE the generic POST rule — the mock
        // takes the FIRST matching rule, and bodyMatch narrows this one.
        Rule singlePost = on("/e/search/index.php");
        singlePost.bodyMatch = "keyboard=Hongmeng";
        singlePost.code = 302;
        singlePost.headers.put("Location", "/e/search/result?searchid=58137"); // relative!
        on("/e/search/result?searchid=58137").file = "search_single.html";
        Rule searchPost = on("/e/search/index.php");
        searchPost.code = 302;
        searchPost.headers.put("Location", "https://www.wuxiabox.com/e/search/result?searchid=34");
        on("/e/search/result?searchid=34").file = "searchresult_34.html";
        on("/e/search/result/index.php?page=1&searchid=34").file = "searchresult_34.html";
        on("/novel/royal-gold-medal-county-magistrate.html").file = "novel_with_tags.html";
        on("/novel/trxs11010.html").file = "novel_page.html";
        on("/novel/trxs11010_1.html").file = "chapter_1.html";
        on("/e/extend/fy.php").file = "fy_page1.html";
        // synthetic variants for base-integration tests
        // (novel_with_tags.html already carries an EMPTY <p class="description">\n</p>
        //  in its tab pane — exactly the shape that made base v1.0.1 return
        //  empty descriptions; inject the preferred text INTO that node)
        Rule descPref = on("/novel/synthetic-desc-pref.html");
        descPref.file = "novel_with_tags.html";
        descPref.transform = b -> b.replaceAll("<p class=\"description\">\\s*</p>",
                "<p class=\"description\">PREFERRED synopsis from the p.description node.</p>");
        Rule coverDiv = on("/novel/synthetic-cover.html");
        coverDiv.file = "novel_page.html";
        coverDiv.transform = b -> b.replace("<figure class=\"cover\">", "<div class=\"cover\">").replace("</figure>", "</div>");
        on("/list/comedy/Completed-newstime-0.html").file = "list_newstime.html";

        // ── T3: catalog list ─────────────────────────────────────────────────
        System.out.println("\n== T3: getCatalogList ==");
        LuaValue cat = call("getCatalogList", 0);
        check("catalog page 0 has 30 items", len(cat.get("items")) == 30, "got " + len(cat.get("items")));
        check("hasNext true", boolOf(cat, "hasNext"));
        LuaValue item0 = cat.get("items").get(1);
        check("item title non-empty", !str(item0, "title").isEmpty());
        check("item url is novel page", str(item0, "url").contains("https://www.wuxiabox.com/novel/"));
        check("item cover routed via wsrv.nl proxy (2.2.0 poster fix)",
                str(item0, "cover").startsWith("https://wsrv.nl/?url=https%3A%2F%2Fwww.wuxiabox.com%2F")
                        && str(item0, "cover").contains("w=450"),
                str(item0, "cover"));

        // ── T4: search (POST → 302 → result) ────────────────────────────────
        System.out.println("\n== T4: getCatalogSearch ==");
        LuaValue sr = call("getCatalogSearch", 0, "pokemon");
        check("search page 0 has 20 items", len(sr.get("items")) == 20, "got " + len(sr.get("items")));
        check("search hasNext true (37 results)", boolOf(sr, "hasNext"));
        check("POST to /e/search/index.php happened", urlHits("POST https://www.wuxiabox.com/e/search/index.php") >= 1);
        check("redirect Location followed", urlHits("GET https://www.wuxiabox.com/e/search/result?searchid=34") >= 1);
        LuaValue sr2 = call("getCatalogSearch", 1, "pokemon");
        check("search page 1 loads via searchid", len(sr2.get("items")) == 20, "got " + len(sr2.get("items")));
        check("page 1 url used", urlHits("page=1&searchid=34") >= 1);

        // ── T4c: hasNext via total when the next-page LINK is absent ──────
        // (listTotal was dead in 2.1.0 — the Lua pattern could not cross the
        //  newline after <ul class="pagination">. Fixture has the REAL shape.)
        System.out.println("\n== T4c: search hasNext via 总数 total (listTotal fix) ==");
        String pagerBody = file("searchresult_34.html");
        check("fixture has the real newline-after-ul pager shape",
                pagerBody.contains("<ul class=\"pagination\">\n") || pagerBody.contains("<ul class=\"pagination\">\r\n"),
                "fixture shape changed?");
        // swap the page=1&searchid=34 mock body to a STRIPPED page: no next
        // links at all, only the 总数=1008 marker + current-page bold
        for (Rule r : rules) {
            if (r.match.equals("/e/search/result/index.php?page=1&searchid=34")) {
                r.file = null;
                r.body = "<html><body><ul class=\"novel-list\">" +
                        "<li class=\"novel-item\"><a href=\"/novel/x1.html\" title=\"X1\"></a></li>" +
                        "</ul><div class=\"pagination-container\"><ul class=\"pagination\">\n" +
                        "<a title=\"总数\">&#160;<b>1008</b> </a>\n<b>2</b>\n" +
                        "</ul></div></body></html>";
            }
        }
        LuaValue sr2b = call("getCatalogSearch", 1, "pokemon"); // sid=34 cached by T4
        check("search hasNext=true from the 总数 total alone (dead pattern fixed)", boolOf(sr2b, "hasNext"));
        check("stripped page items parsed", len(sr2b.get("items")) == 1, "got " + len(sr2b.get("items")));
        // last page (page=50): current page rendered bold (no self-link), no
        // page=51 link anywhere — total math alone must set hasNext=false
        Rule lastPage = on("/e/search/result/index.php?page=50&searchid=34");
        lastPage.body = "<html><body><ul class=\"novel-list\">" +
                "<li class=\"novel-item\"><a href=\"/novel/x999.html\" title=\"LastOne\"></a></li>" +
                "</ul><div class=\"pagination-container\"><ul class=\"pagination\">\n" +
                "<a title=\"总数\">&#160;<b>1008</b> </a>\n<b>51</b>\n" +
                "<a href=\"/e/search/result/index.php?page=49&searchid=34\">&lt;</a>" +
                "</ul></div></body></html>";
        LuaValue srT2 = call("getCatalogSearch", 50, "pokemon"); // page=50 -> last page (1008/20 -> pages 0..50)
        check("last page hasNext=false via total math", !boolOf(srT2, "hasNext"));
        check("last page still returns its items", len(srT2.get("items")) == 1, "got " + len(srT2.get("items")));

        // ── T4d: searchid pages are PRIMARY-ONLY + retryable error (2.2.0) ─
        System.out.println("\n== T4d: searchid pages primary-only ==");
        requestedUrls.clear(); requestHeaderLog.clear();
        rules.clear();
        Rule p1Fail = on("wuxiabox.com/e/search/result/index.php?page=1&searchid=34");
        p1Fail.code = 502; p1Fail.body = "<html>502</html>";
        on("wuxiaspot.com/e/search/result/index.php?page=1&searchid=34").file = "searchresult_34.html"; // must NOT be used
        Rule retryPost = on("wuxiabox.com/e/search/index.php");
        retryPost.code = 302;
        retryPost.headers.put("Location", "/e/search/result?searchid=34");
        on("wuxiabox.com/e/search/result?searchid=34").file = "searchresult_34.html";
        // restore base mocks wiped by rules.clear()
        on("/list/all/all-onclick-0.html").file = "list_newstime.html";
        boolean raisedRetryable = false;
        try {
            call("getCatalogSearch", 1, "pokemon");
        } catch (LuaError le) {
            raisedRetryable = le.getMessage() != null && le.getMessage().contains("search page 2");
        }
        check("primary failure on a searchid page raises a retryable error (not silent empty)", raisedRetryable);
        check("mirror NEVER used for searchid pages (site-specific ids)", urlHits("wuxiaspot.com/e/search/result") == 0, "hits=" + urlHits("wuxiaspot.com/e/search/result"));

        // ── T4b: single-result search (THE v2.1.0 fix) ─────────────────────
        // A pasted exact title returns ONE novel-item and NO searchid in the
        // body (no pager) — v2.0.0 rejected this page and showed nothing.
        System.out.println("\n== T4b: single-result search (v2.1.0 fix) ==");
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        Rule singlePost2 = on("/e/search/index.php");
        singlePost2.bodyMatch = "keyboard=Hongmeng";
        singlePost2.code = 302;
        singlePost2.headers.put("Location", "/e/search/result?searchid=58137");
        on("/e/search/result?searchid=58137").file = "search_single.html";
        LuaValue single = call("getCatalogSearch", 0, "Hongmeng Heavenly Book");
        check("single-result search returns the 1 novel (v2.0.0 returned nothing)", len(single.get("items")) == 1, "got " + len(single.get("items")));
        check("single-result item url is canonical", str(single.get("items").get(1), "url").equals("https://www.wuxiabox.com/novel/kks31307.html"), str(single.get("items").get(1), "url"));
        check("single-result item title", str(single.get("items").get(1), "title").equals("Hongmeng Heavenly Book"), str(single.get("items").get(1), "title"));
        check("hasNext false (no pager on single result)", !boolOf(single, "hasNext"));
        check("relative Location resolved against the request base", urlHits("GET https://www.wuxiabox.com/e/search/result?searchid=58137") >= 1);

        // re-register the base browse mocks (T4d cleared the rule set)
        Rule onclick0r = on("/list/all/all-onclick-0.html");
        onclick0r.file = "list_newstime.html";
        onclick0r.transform = b -> b.replace("newstime", "onclick");
        Rule onclick1r = on("/list/all/all-onclick-1.html");
        onclick1r.file = "list_newstime.html";
        onclick1r.transform = b -> b.replace("newstime", "onclick");
        on("/list/comedy/all-newstime-0.html").file = "list_newstime.html";
        on("/list/comedy/Completed-newstime-0.html").file = "list_newstime.html";
        on("/updates/").file = "updates.html";
        on("/tags/34-0.html").file = "tag_34.html";
        on("/novel/royal-gold-medal-county-magistrate.html").file = "novel_with_tags.html";
        on("/novel/trxs11010.html").file = "novel_page.html";
        on("/novel/trxs11010_1.html").file = "chapter_1.html";
        on("/e/extend/fy.php").file = "fy_page1.html";
        Rule descPrefR = on("/novel/synthetic-desc-pref.html");
        descPrefR.file = "novel_with_tags.html";
        descPrefR.transform = b -> b.replaceAll("<p class=\"description\">\\s*</p>",
                "<p class=\"description\">PREFERRED synopsis from the p.description node.</p>");
        Rule coverDivR = on("/novel/synthetic-cover.html");
        coverDivR.file = "novel_page.html";
        coverDivR.transform = b -> b.replace("<figure class=\"cover\">", "<div class=\"cover\">").replace("</figure>", "</div>");

        // ── T5: filtered — category mode ─────────────────────────────────────
        System.out.println("\n== T5: getCatalogFiltered category ==");
        LuaValue fc = call("getCatalogFiltered", 0, filt("category", "comedy", "status", "all", "sort", "newstime", "browse", "catalog"));
        check("category browse returns 30 items", len(fc.get("items")) == 30, "got " + len(fc.get("items")));
        check("category URL requested", urlHits("/list/comedy/all-newstime-0.html") >= 1);

        // ── T5b: capitalized status (base v1.0.1 sent lowercase — fixed) ────
        System.out.println("\n== T5b: status casing ==");
        LuaValue fcs = call("getCatalogFiltered", 0, filt("category", "comedy", "status", "Completed", "sort", "newstime", "browse", "catalog"));
        check("capitalized status reaches the site URL (base lowercase bug fixed)", urlHits("/list/comedy/Completed-newstime-0.html") >= 1);
        check("capitalized status browse returns 30 items", len(fcs.get("items")) == 30, "got " + len(fcs.get("items")));

        // ── T6: filtered — updates mode ──────────────────────────────────────
        System.out.println("\n== T6: getCatalogFiltered updates ==");
        LuaValue up = call("getCatalogFiltered", 0, filt("browse", "updates", "category", "all", "status", "all", "sort", "newstime"));
        check("updates returns 50 items", len(up.get("items")) == 50, "got " + len(up.get("items")));
        boolean allNovelUrls = true;
        for (int i = 1; i <= len(up.get("items")); i++) {
            if (!str(up.get("items").get(i), "url").matches("https://www\\.wuxiabox\\.com/novel/[^_]+\\.html")) { allNovelUrls = false; break; }
        }
        check("updates chapter urls rewritten to novel urls", allNovelUrls);

        // ── T7: filtered — tag mode (numeric id → single tag) ────────────────
        System.out.println("\n== T7: getCatalogFiltered tag ==");
        LuaTable tgF = filt("browse", "catalog", "category", "all", "status", "all", "sort", "newstime");
        LuaTable tgPicks = new LuaTable(); tgPicks.insert(1, LuaValue.valueOf("34"));
        tgF.set("tags_included", tgPicks);
        LuaValue tg = call("getCatalogFiltered", 0, tgF);
        check("tag browse returns 483 items", len(tg.get("items")) == 483, "got " + len(tg.get("items")));
        check("tag listing URL used", urlHits("/tags/34-0.html") >= 1);
        check("tag hasNext true (646 total > 500)", boolOf(tg, "hasNext"));

        // ── T7b: Popular Tags chips (checkbox marshalling, 2.1.0) ────────
        System.out.println("\n== T7b: getCatalogFiltered popular_tags ==");
        requestedUrls.clear(); requestHeaderLog.clear();
        on("/tags/12-0.html").file = "tag_34.html";
        on("/tags/225-0.html").file = "tag_34.html";
        LuaTable picks = new LuaTable();
        picks.insert(1, LuaValue.valueOf("12"));   // Male Protagonist (canonical id)
        picks.insert(2, LuaValue.valueOf("225")); // Revenge
        LuaTable fpop = filt("browse", "catalog", "category", "all", "status", "all", "sort", "newstime");
        fpop.set("tags_included", picks);
        LuaValue pop = call("getCatalogFiltered", 0, fpop);
        check("tag_input chips drive a union browse", len(pop.get("items")) == 483, "got " + len(pop.get("items")));
        check("canonical tag 12 listing requested", urlHits("/tags/12-0.html") >= 1);
        check("tag 225 listing requested", urlHits("/tags/225-0.html") >= 1);

        // ── T7c: Popular Tags + Tag Search merge ─────────────────────
        System.out.println("\n== T7c: popular_tags + tag_search merge ==");
        requestedUrls.clear(); requestHeaderLog.clear();
        LuaTable fmerge = filt("browse", "catalog", "category", "all", "status", "all", "sort", "newstime");
        LuaTable picks2 = new LuaTable();
        picks2.insert(1, LuaValue.valueOf("34"));
        picks2.insert(2, LuaValue.valueOf("225"));
        picks2.insert(3, LuaValue.valueOf("honghuang")); // family keyword chip
        fmerge.set("tags_included", picks2);
        LuaValue merged = call("getCatalogFiltered", 0, fmerge);
        check("multi-chip union browse (34 + 225 + honghuang family)", len(merged.get("items")) == 483, "got " + len(merged.get("items")));
        check("tag listings requested for every chip", urlHits("/tags/34-0.html") >= 1 && urlHits("/tags/225-0.html") >= 1 && urlHits("/tags/5779-0.html") >= 1);

        // ── T7d: every picker id is canonical (label matches the chip) ────
        System.out.println("\n== T7d: tags picker id/label consistency (all 756 options) ==");
        boolean allCanonical = true;
        String canonicalFail = "";
        for (int i = 1; i <= len(tagInF.get("options")); i++) {
            String val = tagInF.get("options").get(i).get("value").tojstring();
            String label = tagInF.get("options").get(i).get("label").tojstring();
            if (val.equals("honghuang")) continue; // keyword by design
            LuaValue byId = call("tagSearchResolve", val, "");
            if (len(byId) != 1) { allCanonical = false; canonicalFail = val + " → " + luaIds(byId); break; }
            // the chip label must resolve to a set that CONTAINS the picker id
            String labelText = label.replaceAll("\\s*\\(.*\\)$", ""); // strip "(all …)" suffixes
            LuaValue byLabel = call("tagSearchResolve", labelText, "");
            boolean contains = false;
            for (int j = 1; j <= len(byLabel); j++) if (byLabel.get(j).tojstring().equals(val)) { contains = true; break; }
            if (!contains) { allCanonical = false; canonicalFail = label + " resolves to " + luaIds(byLabel) + " — picker id " + val + " not included"; break; }
        }
        check("every picker value resolves to exactly one tag AND its label resolves back to it", allCanonical, canonicalFail);

        // ── T7e: tag browse is PRIMARY-ONLY (mirror tag ids differ!) ─────
        System.out.println("\n== T7e: tag browse primary-only ==");
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        prefs.put("wuxiabox_site_preference", "auto");
        Rule tagFail = on("wuxiabox.com/tags/34-0.html");
        tagFail.code = 502; tagFail.body = "<html>502</html>";
        on("wuxiaspot.com/tags/34-0.html").file = "tag_34.html"; // must NOT be used — mirror id 34 is a different tag
        LuaTable tgFailF = filt("browse", "catalog", "category", "all", "status", "all", "sort", "newstime");
        LuaTable tgFailPicks = new LuaTable(); tgFailPicks.insert(1, LuaValue.valueOf("34"));
        tgFailF.set("tags_included", tgFailPicks);
        LuaValue tgFail = call("getCatalogFiltered", 0, tgFailF);
        check("tag browse returns empty when the primary fails (no wrong-tag mirror fetch)", len(tgFail.get("items")) == 0, "got " + len(tgFail.get("items")));
        check("mirror NEVER used for tag listings", urlHits("wuxiaspot.com/tags/34-0.html") == 0, "hits=" + urlHits("wuxiaspot.com/tags/34-0.html"));

        // restore the book-fixture mocks for T8+ (T7e cleared the rule set)
        on("/novel/royal-gold-medal-county-magistrate.html").file = "novel_with_tags.html";
        on("/novel/trxs11010.html").file = "novel_page.html";
        on("/novel/trxs11010_1.html").file = "chapter_1.html";
        on("/e/extend/fy.php").file = "fy_page1.html";
        Rule descPref2 = on("/novel/synthetic-desc-pref.html");
        descPref2.file = "novel_with_tags.html";
        descPref2.transform = b -> b.replaceAll("<p class=\"description\">\\s*</p>",
                "<p class=\"description\">PREFERRED synopsis from the p.description node.</p>");
        Rule coverDiv2 = on("/novel/synthetic-cover.html");
        coverDiv2.file = "novel_page.html";
        coverDiv2.transform = b -> b.replace("<figure class=\"cover\">", "<div class=\"cover\">").replace("</figure>", "</div>");

        // ── T8: book getters ─────────────────────────────────────────────────
        System.out.println("\n== T8: book getters ==");
        LuaValue bt = call("getBookTitle", NOVEL);
        check("title", bt.tojstring().equals("Royal Gold Medal County Magistrate"), bt.tojstring());
        LuaValue bc = call("getBookCoverImageUrl", NOVEL);
        check("cover url via wsrv.nl proxy with the site path encoded",
                bc.tojstring().startsWith("https://wsrv.nl/?url=https%3A%2F%2Fwww.wuxiabox.com%2Fd%2Ffile%2Fcover123%2F")
                        && bc.tojstring().contains("w=450") && bc.tojstring().contains("output=jpg"),
                bc.tojstring());
        LuaValue bd = call("getBookDescription", NOVEL);
        check("description > 100 chars", bd.tojstring().length() > 100, "len=" + bd.tojstring().length());
        check("description contains Fang Zhengyi", bd.tojstring().contains("Fang Zhengyi"));
        LuaValue bg = call("getBookGenres", NOVEL);
        List<String> genres = new ArrayList<>();
        for (int i = 1; i <= len(bg); i++) genres.add(bg.get(i).tojstring());
        check("genres contain categories", genres.contains("Comedy") && genres.contains("Historical"), genres.toString());
        boolean tagLeak = false;
        for (String g : genres) if (g.contains("AncientChina") || g.contains("MaleProtagonist") || g.contains("Farming") || g.contains("Transmigration")) tagLeak = true;
        check("genres carry ONLY categories — no tag chips (2.1.0)", !tagLeak, genres.toString());
        LuaValue bs = call("getBookStatus", NOVEL);
        check("status Completed", bs.tojstring().equals("Completed"), bs.tojstring());

        // ── T8b: description — p.description preference kept from base ─────
        System.out.println("\n== T8b: description selector chain ==");
        LuaValue bdPref = call("getBookDescription", "https://www.wuxiabox.com/novel/synthetic-desc-pref.html");
        check("non-empty p.description is preferred (base behavior kept)", bdPref.tojstring().equals("PREFERRED synopsis from the p.description node."), bdPref.tojstring());
        LuaValue bdFall = call("getBookDescription", NOVEL2); // novel_page.html: EMPTY p.description
        check("empty p.description falls through to .summary .content (base bug fixed)", bdFall.tojstring().contains("transmigrated"), bdFall.tojstring().substring(0, Math.min(60, bdFall.tojstring().length())));

        // ── T8c: cover — .cover img fallback for non-figure markup ──────
        System.out.println("\n== T8c: cover fallback ==");
        LuaValue bc2 = call("getBookCoverImageUrl", "https://www.wuxiabox.com/novel/synthetic-cover.html");
        check(".cover img fallback when figure.cover is absent (proxy keeps the path)", bc2.tojstring().contains("%2Fd%2Ffile%2F"), bc2.tojstring());
        // ── T8d: direct mode (covers setting) ─────────────────────────────
        prefs.put("wuxiabox_covers", "direct");
        LuaValue bcd = call("getBookCoverImageUrl", NOVEL);
        check("direct cover mode returns the bare site url", bcd.tojstring().startsWith("https://www.wuxiabox.com/d/file/cover123/"), bcd.tojstring());
        prefs.put("wuxiabox_covers", "proxy");
        LuaValue bcp = call("getBookCoverImageUrl", NOVEL);
        check("proxy cover mode back on", bcp.tojstring().startsWith("https://wsrv.nl/"), bcp.tojstring());
        prefs.remove("wuxiabox_covers");

        // ── T9: last update ──────────────────────────────────────────────────
        System.out.println("\n== T9: getBookLastUpdate ==");
        LuaValue bu = call("getBookLastUpdate", NOVEL);
        check("last update is YYYY-MM-DD", bu.tojstring().matches("\\d{4}-\\d{2}-\\d{2}"), bu.tojstring());
        check("fy last page fetched for long novel", urlHits("fy.php?page=12") >= 1);

        // ── T10/T11: parsePage ───────────────────────────────────────────────
        System.out.println("\n== T10/T11: parsePage ==");
        LuaValue pp1 = call("parsePage", NOVEL, 1);
        check("page 1 → 100 chapters", len(pp1.get("chapters")) == 100, "got " + len(pp1.get("chapters")));
        check("page 1 totalPages = 13", intOf(pp1, "totalPages") == 13, "got " + intOf(pp1, "totalPages"));
        String firstCh = str(pp1.get("chapters").get(1), "url");
        check("first chapter is chapter 1", firstCh.endsWith("/royal-gold-medal-county-magistrate_1.html"), firstCh);
        String firstChTitle = str(pp1.get("chapters").get(1), "title");
        check("chapter 1 title non-empty", !firstChTitle.isEmpty(), firstChTitle);
        requestedUrls.clear(); requestHeaderLog.clear();
        LuaValue pp2 = call("parsePage", NOVEL, 2);
        check("page 2 → fy.php?page=1 fetched", urlHits("fy.php?page=1") >= 1);
        check("page 2 chapters 100", len(pp2.get("chapters")) == 100, "got " + len(pp2.get("chapters")));
        String ch101 = str(pp2.get("chapters").get(1), "url");
        check("page 2 first chapter is _101", ch101.endsWith("_101.html"), ch101);
        check("page 2 totalPages = 3 (from fragment pager)", intOf(pp2, "totalPages") == 3, "got " + intOf(pp2, "totalPages"));
        check("fy.php fragment sent as XHR (kept from base v1.0.1)", headerSeen("fy.php?page=1", "X-Requested-With", "XMLHttpRequest"));

        // ── T12: chapter text — normal path ─────────────────────────────────
        System.out.println("\n== T12: getChapterText normal ==");
        String chapterHtml = file("chapter_1.html");
        LuaValue ct = call("getChapterText", chapterHtml, "https://www.wuxiabox.com/novel/trxs11010_1.html");
        String text = ct.tojstring();
        check("chapter text non-empty", text.length() > 400, "len=" + text.length());
        int paras = count(text, "\n\n") + 1;
        check("paragraphs preserved (>10)", paras > 10, "paras=" + paras);
        check("no title echo at start", !text.startsWith("Bengtie"), text.substring(0, Math.min(60, text.length())));
        check("no 'Author:' echo line", !text.contains("Author: Shang Li"));
        check("no 'Synopsis:' echo line", !text.contains("Synopsis:"));
        check("content present (Lin Yi)", text.contains("Lin Yi transmigrated"));
        check("no ad scripts", !text.contains("acscdn") && !text.contains("pubfuture"));

        // ── T12b: chapter text — base v1.0.1 cleaning rules (merged) ───────
        System.out.println("\n== T12b: chapter text cleaning (base merge) ==");
        final String baseCh = file("chapter_1.html");
        final int lastP = baseCh.lastIndexOf("</p>");
        java.util.function.UnaryOperator<String> inject = extra ->
                baseCh.substring(0, lastP + 4) + extra + baseCh.substring(lastP + 4);
        String chUrl1 = "https://www.wuxiabox.com/novel/trxs11010_1.html";
        String tMarker = call("getChapterText", inject.apply("\n<p>(End of this chapter)</p>"), chUrl1).tojstring();
        check("trailing (End of this chapter) removed (kept from base)", !tMarker.contains("End of this chapter"));
        String tNote = call("getChapterText", inject.apply("\n<p>(a note from the translator)(End of this chapter)</p>"), chUrl1).tojstring();
        check("author-note + end marker removed (kept from base)", !tNote.contains("End of this chapter") && !tNote.contains("a note from the translator"));
        String tBrand = call("getChapterText", inject.apply("\n<p>WuxiaBox - bookmark our site for daily chapters</p>"), chUrl1).tojstring();
        check("bare WuxiaBox branding line removed (kept from base)", !tBrand.contains("bookmark our site"));
        String tEcho = call("getChapterText", inject.apply("\n<p>Chapter 12</p>"), chUrl1).tojstring();
        check("mid-text standalone Chapter-echo line removed (kept from base)", !tEcho.contains("Chapter 12"));
        String tTn = call("getChapterText", inject.apply("\n<p>T/N: thanks for reading</p>"), chUrl1).tojstring();
        check("T/N credit line removed (kept from base)", !tTn.contains("T/N"));
        check("content intact after all cleaning", tTn.contains("Lin Yi transmigrated") && tTn.length() > 400, "len=" + tTn.length());

        // ── T13: chapter text — 502 recovery, alternating WuxiaBox → WuxiaSpot ─
        System.out.println("\n== T13: getChapterText 502 recovery (smart switcher) ==");
        String gateway502 = "<html><head><title>502 Bad Gateway</title></head><body><center><h1>502 Bad Gateway</h1></center><hr><center>cloudflare</center></body></html>";
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        prefs.put("wuxiabox_chapter_retries", "2");
        prefs.put("wuxiabox_site_preference", "auto");
        prefs.put("wuxiabox_site_health", "");
        reloadPlugin(); // hermetic health slate (2.3.0)
        Rule seqRule = on("wuxiabox.com/novel/trxs11010_2.html");
        seqRule.seq = new LinkedList<>();
        seqRule.seq.add(new String[]{"502", gateway502});
        on("wuxiaspot.com/novel/trxs11010_2.html").file = "chapter_1.html";
        on("/novel/trxs11010.html").file = "novel_page.html";
        long t0 = System.currentTimeMillis();
        LuaValue ct2 = call("getChapterText", gateway502, "https://www.wuxiabox.com/novel/trxs11010_2.html");
        long elapsed = System.currentTimeMillis() - t0;
        String text2 = ct2.tojstring();
        check("502 → recovered text non-empty (attempt 2 = the mirror)", text2.length() > 400, "len=" + text2.length());
        check("recovered content correct", text2.contains("Lin Yi transmigrated"));
        check("attempt 1 hit the primary site", urlHits("GET https://www.wuxiabox.com/novel/trxs11010_2.html") == 1, "hits=" + urlHits("GET https://www.wuxiabox.com/novel/trxs11010_2.html"));
        check("attempt 2 hit the MIRROR site (alternation, 2.1.0)", urlHits("GET https://www.wuxiaspot.com/novel/trxs11010_2.html") == 1, "hits=" + urlHits("GET https://www.wuxiaspot.com/novel/trxs11010_2.html"));
        check("backoff delays applied (>= 3.4s total — 2.3.0 dropped the pre-attempt sleep)", elapsed >= 3400, "elapsed=" + elapsed + "ms");

        // ── T13b: 502 recovery with "WuxiaBox only" preference ─────────────
        System.out.println("\n== T13b: 502 recovery, box-only preference ==");
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        prefs.put("wuxiabox_site_preference", "box");
        prefs.put("wuxiabox_site_health", "");
        reloadPlugin(); // hermetic health slate (2.3.0)
        Rule seqRule2 = on("wuxiabox.com/novel/trxs11010_2.html");
        seqRule2.seq = new LinkedList<>();
        seqRule2.seq.add(new String[]{"502", gateway502});
        seqRule2.seq.add(new String[]{"200", "@chapter_1.html"});
        on("wuxiaspot.com/novel/trxs11010_2.html").file = "chapter_1.html"; // must NOT be used
        LuaValue ct3 = call("getChapterText", gateway502, "https://www.wuxiabox.com/novel/trxs11010_2.html");
        String text3 = ct3.tojstring();
        check("box-only: recovered from the primary on attempt 2", text3.contains("Lin Yi transmigrated"));
        check("box-only: mirror never touched", urlHits("wuxiaspot.com/novel/trxs11010_2.html") == 0, "hits=" + urlHits("wuxiaspot.com/novel/trxs11010_2.html"));
        check("box-only: primary hit twice", urlHits("GET https://www.wuxiabox.com/novel/trxs11010_2.html") == 2);

        // ── T15: mirror fallback for catalog (auto mode) ──────────────────
        System.out.println("\n== T15: catalog mirror fallback (auto) ==");
        prefs.put("wuxiabox_site_preference", "auto");
        prefs.put("wuxiabox_site_health", "");
        reloadPlugin(); // hermetic health slate (2.3.0)
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        Rule catFail = on("wuxiabox.com/list/all/all-onclick-0.html");
        catFail.code = 502; catFail.body = gateway502;
        Rule catMirror = on("wuxiaspot.com/list/all/all-onclick-0.html");
        catMirror.file = "list_newstime.html";
        LuaValue catM = call("getCatalogList", 0);
        check("catalog served from the mirror when the primary 502s", len(catM.get("items")) == 30, "got " + len(catM.get("items")));
        check("mirror request happened", urlHits("GET https://www.wuxiaspot.com/list/all/all-onclick-0.html") == 1);
        check("item URLs stay canonical wuxiabox.com (no library fragmentation)",
                str(catM.get("items").get(1), "url").startsWith("https://www.wuxiabox.com/novel/"),
                str(catM.get("items").get(1), "url"));

        // ── T15b: "WuxiaSpot first" preference (mirror as default) ────────
        System.out.println("\n== T15b: wuxiaspot-first preference ==");
        prefs.put("wuxiabox_site_preference", "spot");
        prefs.put("wuxiabox_site_health", "");
        reloadPlugin(); // hermetic health slate (2.3.0)
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        Rule catMirror2 = on("wuxiaspot.com/list/all/all-onclick-0.html");
        catMirror2.file = "list_newstime.html";
        LuaValue catS = call("getCatalogList", 0);
        check("spot preference: catalog served from the mirror first", len(catS.get("items")) == 30, "got " + len(catS.get("items")));
        check("spot preference: no primary request at all", urlHits("GET https://www.wuxiabox.com/list/all/all-onclick-0.html") == 0);
        check("spot preference: item URLs still canonical", str(catS.get("items").get(1), "url").startsWith("https://www.wuxiabox.com/novel/"));

        // ── T16: mirror fallback for search ───────────────────────────────
        System.out.println("\n== T16: search mirror fallback ==");
        prefs.put("wuxiabox_site_preference", "auto");
        prefs.put("wuxiabox_site_health", "");
        reloadPlugin(); // hermetic health slate (2.3.0)
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        Rule sPostFail = on("wuxiabox.com/e/search/index.php");
        sPostFail.code = 502; sPostFail.body = gateway502;
        Rule sGetFail = on("wuxiabox.com/e/search/?searchget");
        sGetFail.code = 502; sGetFail.body = gateway502;
        Rule sPostMirror = on("wuxiaspot.com/e/search/index.php");
        sPostMirror.code = 302;
        sPostMirror.headers.put("Location", "https://www.wuxiaspot.com/e/search/result?searchid=58137");
        on("wuxiaspot.com/e/search/result?searchid=58137").file = "search_single.html";
        LuaValue srM = call("getCatalogSearch", 0, "Hongmeng Heavenly Book");
        check("search recovered via the mirror", len(srM.get("items")) == 1, "got " + len(srM.get("items")));
        check("mirror POST happened", urlHits("POST https://www.wuxiaspot.com/e/search/index.php") >= 1);
        check("search result URLs stay canonical", str(srM.get("items").get(1), "url").startsWith("https://www.wuxiabox.com/novel/"), str(srM.get("items").get(1), "url"));

        // ── T17: smart switcher — health tracking + cooldown steering ────
        System.out.println("\n== T17: smart switcher (health + cooldown) ==");
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
        System.out.println("\n== T17b: cooldown survives a restart ==");
        rules.clear(); requestedUrls.clear(); requestHeaderLog.clear();
        on("wuxiabox.com/list/all/all-onclick-0.html").file = "list_newstime.html"; // primary is FINE now
        on("wuxiaspot.com/list/all/all-onclick-0.html").file = "list_newstime.html";
        reloadPlugin();
        LuaValue catS4 = call("getCatalogList", 0);
        check("after restart: cooling primary still skipped (persistent circuit breaker)",
                urlHits("GET https://www.wuxiabox.com/list/all/all-onclick-0.html") == 0
                        && len(catS4.get("items")) == 30);

        // ── T17c: cooldown expiry re-admits the primary (half-open) ────
        System.out.println("\n== T17c: cooldown expiry ==");
        prefs.put("wuxiabox_site_health", "box=2," + (System.currentTimeMillis() - 1000) + ";spot=0,0");
        reloadPlugin();
        requestedUrls.clear();
        LuaValue catS5 = call("getCatalogList", 0);
        check("expired cooldown: primary retried first (self-healing half-open)",
                urlHits("GET https://www.wuxiabox.com/list/all/all-onclick-0.html") == 1
                        && len(catS5.get("items")) == 30);

        // ── T17d: success resets health ────────────────────────────────
        System.out.println("\n== T17d: success resets health ==");
        prefs.put("wuxiabox_site_health", "box=1,0;spot=0,0");
        reloadPlugin();
        requestedUrls.clear();
        LuaValue catS6 = call("getCatalogList", 0);
        check("healthy primary serves the catalog", len(catS6.get("items")) == 30);
        String h3 = prefs.get("wuxiabox_site_health");
        check("success resets the fail counter (box=0,0)", h3 != null && h3.contains("box=0,0"), h3);

        // ── T17e: 200-but-junk body is a failure ───────────────────────
        System.out.println("\n== T17e: 200-but-junk body failover ==");
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
        System.out.println("\n== T17f: 404 is not a health failure ==");
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
        System.out.println("\n== T18: mirror-native search pagination ==");
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
        System.out.println("\n== T19: both sites dead → clear error ==");
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

        // ── T14: settings ────────────────────────────────────────────────────
        System.out.println("\n== T14: getSettingsSchema ==");
        prefs.clear(); // defaults only — pace pref intentionally unset
        LuaValue ss = call("getSettingsSchema");
        check("4 settings (covers added, 2.2.0)", len(ss) == 4, "got " + len(ss));
        check("site setting present and first", str(ss.get(1), "key").equals("wuxiabox_site_preference"), str(ss.get(1), "key"));
        check("covers setting present (2.2.0)", str(ss.get(2), "key").equals("wuxiabox_covers"), str(ss.get(2), "key"));
        check("retry setting present", str(ss.get(3), "key").equals("wuxiabox_chapter_retries"));
        check("pace setting present", str(ss.get(4), "key").equals("wuxiabox_chapter_pace_ms"));
        check("defaults: site=auto when unset", str(ss.get(1), "current").equals("auto"), str(ss.get(1), "current"));
        check("defaults: covers=proxy (posters fix)", str(ss.get(2), "current").equals("proxy"), str(ss.get(2), "current"));
        check("defaults: retries=4", str(ss.get(3), "current").equals("4"), str(ss.get(3), "current"));
        check("defaults: pace=1500 when unset", str(ss.get(4), "current").equals("1500"), str(ss.get(4), "current"));
        check("site option 1 label mentions the smart switcher (2.3.0)",
                ss.get(1).get("options").get(1).get("label").tojstring().toLowerCase().contains("smart"),
                ss.get(1).get("options").get(1).get("label").tojstring());

        // ── summary ──────────────────────────────────────────────────────────
        System.out.println("\n════════════════════════════════");
        System.out.println("PASSED: " + passed + "   FAILED: " + failed);
        if (!failures.isEmpty()) { System.out.println("Failures:"); for (String f : failures) System.out.println("  - " + f); }
        System.out.println(failed == 0 ? "ALL TESTS PASSED" : "SOME TESTS FAILED");
        System.exit(failed == 0 ? 0 : 1);
    }

    static String luaIds(LuaValue v) {
        if (v == null || v.isnil() || !v.istable()) return String.valueOf(v);
        StringBuilder sb = new StringBuilder("[");
        LuaValue k = LuaValue.NIL;
        while (true) {
            Varargs n = v.checktable().next(k);
            if (n.arg1().isnil()) break;
            k = n.arg1();
            if (sb.length() > 1) sb.append(",");
            sb.append(n.arg(2).tojstring());
        }
        return sb.append("]").toString();
    }
}
