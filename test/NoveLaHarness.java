import org.luaj.vm2.*;
import org.luaj.vm2.lib.*;
import org.luaj.vm2.lib.jse.JsePlatform;
import com.google.gson.*;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.jsoup.select.Elements;

import java.io.FileReader;
import java.io.InputStreamReader;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Faithful test harness that mimics NoveLA's LuaSourceLoader sandbox API.
 * Implements http_get/http_post with real networking, json_parse/json_stringify
 * with Gson, html_* with Jsoup — mirroring the Kotlin implementations.
 */
public class NoveLaHarness {

    static final Map<String, String> prefs = new ConcurrentHashMap<>();
    static final Gson gson = new Gson();
    static final HttpClient client = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(15))
            .followRedirects(HttpClient.Redirect.NORMAL)
            .build();
    static final String UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36";

    public static void main(String[] args) throws Exception {
        Globals g = JsePlatform.standardGlobals();
        // NoveLA sandbox removals
        g.set("luajava", LuaValue.NIL);
        g.set("io", LuaValue.NIL);
        g.set("load", LuaValue.NIL);
        g.set("loadfile", LuaValue.NIL);
        g.set("loadstring", LuaValue.NIL);
        g.set("dofile", LuaValue.NIL);
        g.set("require", LuaValue.NIL);
        g.set("package", LuaValue.NIL);
        g.set("debug", LuaValue.NIL);
        LuaTable os = (LuaTable) g.get("os");
        os.set("execute", LuaValue.NIL);
        os.set("exit", LuaValue.NIL);
        os.set("getenv", LuaValue.NIL);
        os.set("rename", LuaValue.NIL);
        os.set("remove", LuaValue.NIL);
        os.set("tmpname", LuaValue.NIL);

        registerApi(g);

        String file = args[0];
        LuaValue chunk = g.load(new FileReader(file), file);
        try {
            LuaValue result = chunk.call();
            if (!result.isnil()) {
                g.set("plugin", result);
            } else {
                g.set("plugin", g); // globals-based script
            }
        } catch (LuaError e) {
            System.err.println("PLUGIN LOAD ERROR: " + e.getMessage());
            System.exit(1);
        }

        // run test script
        java.io.File main = new java.io.File(args[1]);
        LuaValue test = g.load(new InputStreamReader(new java.io.FileInputStream(main)), main.getName());
        test.call();
    }

    static void registerApi(Globals g) {
        // ── HTTP ──────────────────────────────────────────────────────────
        g.set("http_get", new TwoArgFunction() {
            @Override
            public LuaValue call(LuaValue a1, LuaValue a2) {
                String url = a1.checkjstring();
                Map<String, String> headers = new LinkedHashMap<>();
                // default headers like NoveLA: Accept-Language + Referer
                headers.put("Accept-Language", "en-US,en;q=0.9");
                headers.put("Referer", origin(url));
                headers.put("User-Agent", UA);
                if (a2.istable()) {
                    LuaTable cfg = a2.checktable();
                    LuaTable h = cfg.get("headers").opttable(new LuaTable());
                    LuaValue k = LuaValue.NIL;
                    while (true) {
                        Varargs n = h.next(k);
                        if (n.arg1().isnil()) break;
                        k = n.arg1();
                        headers.put(k.tojstring(), n.arg(2).tojstring());
                    }
                }
                try {
                    HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(url))
                            .timeout(Duration.ofSeconds(60))
                            .GET();
                    headers.forEach(b::header);
                    HttpResponse<byte[]> resp = client.send(b.build(), HttpResponse.BodyHandlers.ofByteArray());
                    String body = new String(resp.body(), java.nio.charset.StandardCharsets.UTF_8);
                    return responseTable(resp.statusCode() >= 200 && resp.statusCode() < 300, body, resp.statusCode());
                } catch (Exception e) {
                    LuaTable t = new LuaTable();
                    t.set("success", LuaValue.FALSE);
                    t.set("body", LuaValue.valueOf(String.valueOf(e.getMessage())));
                    t.set("code", LuaValue.valueOf(-1));
                    return t;
                }
            }
        });

        g.set("http_post", new ThreeArgFunction() {
            @Override
            public LuaValue call(LuaValue a1, LuaValue a2, LuaValue a3) {
                String url = a1.checkjstring();
                String body = a2.checkjstring();
                Map<String, String> headers = new LinkedHashMap<>();
                headers.put("Accept-Language", "en-US,en;q=0.9");
                headers.put("Referer", origin(url));
                headers.put("User-Agent", UA);
                String contentType = (body.startsWith("{") || body.startsWith("[")) ?
                        "application/json" : "application/x-www-form-urlencoded";
                if (a3.istable()) {
                    LuaTable cfg = a3.checktable();
                    LuaTable h = cfg.get("headers").opttable(new LuaTable());
                    LuaValue k = LuaValue.NIL;
                    while (true) {
                        Varargs n = h.next(k);
                        if (n.arg1().isnil()) break;
                        k = n.arg1();
                        String key = k.tojstring();
                        String val = n.arg(2).tojstring();
                        if (key.equalsIgnoreCase("content-type")) contentType = val;
                        headers.put(key, val);
                    }
                }
                headers.put("Content-Type", contentType);
                try {
                    HttpRequest.Builder b = HttpRequest.newBuilder(URI.create(url))
                            .timeout(Duration.ofSeconds(60))
                            .POST(HttpRequest.BodyPublishers.ofByteArray(body.getBytes(java.nio.charset.StandardCharsets.UTF_8)));
                    headers.forEach(b::header);
                    HttpResponse<byte[]> resp = client.send(b.build(), HttpResponse.BodyHandlers.ofByteArray());
                    String respBody = new String(resp.body(), java.nio.charset.StandardCharsets.UTF_8);
                    return responseTable(resp.statusCode() >= 200 && resp.statusCode() < 300, respBody, resp.statusCode());
                } catch (Exception e) {
                    LuaTable t = new LuaTable();
                    t.set("success", LuaValue.FALSE);
                    t.set("body", LuaValue.valueOf(String.valueOf(e.getMessage())));
                    t.set("code", LuaValue.valueOf(-1));
                    return t;
                }
            }
        });

        // ── Preferences ──────────────────────────────────────────────────
        g.set("get_preference", new OneArgFunction() {
            @Override
            public LuaValue call(LuaValue a) {
                return LuaValue.valueOf(prefs.getOrDefault(a.checkjstring(), ""));
            }
        });
        g.set("set_preference", new TwoArgFunction() {
            @Override
            public LuaValue call(LuaValue a, LuaValue b) {
                prefs.put(a.checkjstring(), b.tojstring());
                return LuaValue.NIL;
            }
        });

        // ── JSON (Gson) ──────────────────────────────────────────────────
        g.set("json_parse", new OneArgFunction() {
            @Override
            public LuaValue call(LuaValue a) {
                try {
                    JsonElement el = JsonParser.parseString(a.checkjstring());
                    return jsonToLua(el);
                } catch (Exception e) {
                    return LuaValue.NIL;
                }
            }
        });
        g.set("json_stringify", new OneArgFunction() {
            @Override
            public LuaValue call(LuaValue a) {
                try {
                    JsonElement el = luaToJson(a);
                    return LuaValue.valueOf(gson.toJson(el));
                } catch (Exception e) {
                    return LuaValue.NIL;
                }
            }
        });

        // ── HTML (Jsoup) ─────────────────────────────────────────────────
        g.set("html_parse", new OneArgFunction() {
            @Override
            public LuaValue call(LuaValue a) {
                Document doc = Jsoup.parse(a.checkjstring());
                LuaTable t = new LuaTable();
                t.set("text", doc.text());
                t.set("html", doc.html());
                t.set("title", doc.title());
                t.set("body", doc.body() != null ? LuaValue.valueOf(doc.body().html()) : LuaValue.NIL);
                return t;
            }
        });

        g.set("html_select", new TwoArgFunction() {
            @Override
            public LuaValue call(LuaValue a, LuaValue b) {
                Elements els;
                if (a.isuserdata(Element.class)) {
                    els = ((Element) a.touserdata()).select(b.checkjstring());
                } else {
                    els = Jsoup.parse(a.checkjstring()).select(b.checkjstring());
                }
                LuaTable arr = new LuaTable();
                for (Element e : els) arr.set(arr.length() + 1, elementToTable(e));
                return arr;
            }
        });

        g.set("html_select_first", new TwoArgFunction() {
            @Override
            public LuaValue call(LuaValue a, LuaValue b) {
                Element el;
                if (a.isuserdata(Element.class)) {
                    el = ((Element) a.touserdata()).selectFirst(b.checkjstring());
                } else {
                    el = Jsoup.parse(a.checkjstring()).selectFirst(b.checkjstring());
                }
                return el != null ? elementToTable(el) : LuaValue.NIL;
            }
        });

        g.set("html_attr", new ThreeArgFunction() {
            @Override
            public LuaValue call(LuaValue a, LuaValue b, LuaValue c) {
                try {
                    Element el;
                    if (a.isuserdata(Element.class)) {
                        el = ((Element) a.touserdata()).selectFirst(b.checkjstring());
                    } else {
                        el = Jsoup.parse(a.checkjstring()).selectFirst(b.checkjstring());
                    }
                    if (el == null) return LuaValue.valueOf("");
                    String attr = c.checkjstring();
                    String val = el.hasAttr(attr) ? el.attr(attr) : (el.hasAttr("abs:" + attr) ? el.absUrl(attr) : "");
                    return LuaValue.valueOf(val != null ? val : "");
                } catch (Exception e) {
                    return LuaValue.valueOf("");
                }
            }
        });

        g.set("html_text", new OneArgFunction() {
            @Override
            public LuaValue call(LuaValue a) {
                if (a.isuserdata(Element.class)) {
                    return LuaValue.valueOf(((Element) a.touserdata()).text());
                }
                return LuaValue.valueOf(Jsoup.parse(a.checkjstring()).text());
            }
        });

        // ── URL / strings ────────────────────────────────────────────────
        g.set("url_encode", new OneArgFunction() {
            @Override
            public LuaValue call(LuaValue a) {
                return LuaValue.valueOf(java.net.URLEncoder.encode(a.checkjstring(),
                        java.nio.charset.StandardCharsets.UTF_8).replace("+", "%20"));
            }
        });
        g.set("url_resolve", new TwoArgFunction() {
            @Override
            public LuaValue call(LuaValue a, LuaValue b) {
                try {
                    return LuaValue.valueOf(java.net.URI.create(a.checkjstring())
                            .resolve(b.checkjstring()).toString());
                } catch (Exception e) {
                    return LuaValue.valueOf(b.checkjstring());
                }
            }
        });
        g.set("regex_match", new TwoArgFunction() {
            @Override
            public LuaValue call(LuaValue a, LuaValue b) {
                try {
                    java.util.regex.Matcher m = java.util.regex.Pattern.compile(b.checkjstring())
                            .matcher(a.checkjstring());
                    LuaTable t = new LuaTable();
                    if (m.find()) t.set(1, m.group());
                    return t;
                } catch (Exception e) {
                    return new LuaTable();
                }
            }
        });
        g.set("regex_replace", new ThreeArgFunction() {
            @Override
            public LuaValue call(LuaValue a, LuaValue b, LuaValue c) {
                try {
                    return LuaValue.valueOf(java.util.regex.Pattern.compile(b.checkjstring())
                            .matcher(a.checkjstring()).replaceAll(c.checkjstring()));
                } catch (Exception e) {
                    return a;
                }
            }
        });
        g.set("string_normalize", new OneArgFunction() {
            @Override
            public LuaValue call(LuaValue a) {
                return LuaValue.valueOf(java.text.Normalizer.normalize(a.checkjstring(),
                        java.text.Normalizer.Form.NFKC));
            }
        });
        g.set("string_split", new TwoArgFunction() {
            @Override
            public LuaValue call(LuaValue a, LuaValue b) {
                String[] parts = a.checkjstring().split(java.util.regex.Pattern.quote(b.checkjstring()), -1);
                LuaTable t = new LuaTable();
                for (String p : parts) t.set(t.length() + 1, p);
                return t;
            }
        });
        g.set("string_trim", new OneArgFunction() {
            @Override
            public LuaValue call(LuaValue a) {
                return LuaValue.valueOf(a.checkjstring().trim());
            }
        });
        g.set("string_starts_with", new TwoArgFunction() {
            @Override
            public LuaValue call(LuaValue a, LuaValue b) {
                return LuaValue.valueOf(a.checkjstring().startsWith(b.checkjstring()));
            }
        });
        g.set("string_ends_with", new TwoArgFunction() {
            @Override
            public LuaValue call(LuaValue a, LuaValue b) {
                return LuaValue.valueOf(a.checkjstring().endsWith(b.checkjstring()));
            }
        });
        g.set("string_clean", new OneArgFunction() {
            @Override
            public LuaValue call(LuaValue a) {
                String s = java.text.Normalizer.normalize(a.checkjstring(), java.text.Normalizer.Form.NFKC);
                s = s.replaceAll("\\s+", " ").trim();
                return LuaValue.valueOf(s);
            }
        });
        g.set("unescape_unicode", new OneArgFunction() {
            @Override
            public LuaValue call(LuaValue a) {
                String s = a.checkjstring();
                StringBuilder sb = new StringBuilder();
                java.util.regex.Matcher m = java.util.regex.Pattern.compile("\\\\u([0-9a-fA-F]{4})").matcher(s);
                int last = 0;
                while (m.find()) {
                    sb.append(s, last, m.start());
                    sb.append((char) Integer.parseInt(m.group(1), 16));
                    last = m.end();
                }
                sb.append(s.substring(last));
                return LuaValue.valueOf(sb.toString());
            }
        });
        g.set("base64_decode", new OneArgFunction() {
            @Override
            public LuaValue call(LuaValue a) {
                try {
                    return LuaValue.valueOf(new String(Base64.getDecoder().decode(a.checkjstring()),
                            java.nio.charset.StandardCharsets.UTF_8));
                } catch (Exception e) {
                    return LuaValue.NIL;
                }
            }
        });
        g.set("sleep", new OneArgFunction() {
            @Override
            public LuaValue call(LuaValue a) {
                try {
                    Thread.sleep(Math.max(0, (long) a.optdouble(500)));
                } catch (InterruptedException ignored) {
                }
                return LuaValue.NIL;
            }
        });
        g.set("os_time", new ZeroArgFunction() {
            @Override
            public LuaValue call() {
                return LuaValue.valueOf(System.currentTimeMillis());
            }
        });
        g.set("log_info", new OneArgFunction() {
            @Override
            public LuaValue call(LuaValue a) {
                System.out.println("[INFO] " + a.tojstring());
                return LuaValue.NIL;
            }
        });
        g.set("log_error", new OneArgFunction() {
            @Override
            public LuaValue call(LuaValue a) {
                System.out.println("[ERROR] " + a.tojstring());
                return LuaValue.NIL;
            }
        });
        g.set("get_cookies", new OneArgFunction() {
            @Override
            public LuaValue call(LuaValue a) {
                return new LuaTable();
            }
        });
        g.set("show_error", new TwoArgFunction() {
            @Override
            public LuaValue call(LuaValue title, LuaValue message) {
                System.out.println("[SHOW_ERROR] " + title.tojstring() + ": " + message.tojstring());
                return LuaValue.NIL;
            }
        });
    }

    static String origin(String url) {
        try {
            URI u = URI.create(url);
            return u.getScheme() + "://" + u.getHost() + "/";
        } catch (Exception e) {
            return "";
        }
    }

    static LuaTable responseTable(boolean success, String body, int code) {
        LuaTable t = new LuaTable();
        t.set("success", LuaValue.valueOf(success));
        t.set("body", LuaValue.valueOf(body));
        t.set("code", LuaValue.valueOf(code));
        return t;
    }

    static LuaTable elementToTable(Element el) {
        LuaTable t = new LuaTable();
        t.set("text", el.text());
        t.set("html", el.html());
        String href = el.hasAttr("href") ? el.attr("href") : "";
        if (href.isEmpty() && el.hasAttr("abs:href")) href = el.absUrl("href");
        t.set("href", href);
        String src = el.hasAttr("src") ? el.attr("src") : "";
        if (src.isEmpty()) src = el.absUrl("src");
        t.set("src", src);
        t.set("title", el.attr("title"));
        t.set("class", el.className());
        t.set("id", el.id());
        t.set("__element", new LuaUserdata(el));
        return t;
    }

    static LuaValue jsonToLua(JsonElement el) {
        if (el == null || el.isJsonNull()) return LuaValue.NIL;
        if (el.isJsonPrimitive()) {
            JsonPrimitive p = el.getAsJsonPrimitive();
            if (p.isBoolean()) return LuaValue.valueOf(p.getAsBoolean());
            if (p.isNumber()) {
                double d = p.getAsDouble();
                if (d == Math.floor(d) && !Double.isInfinite(d) && Math.abs(d) < 1e15) {
                    // NoveLA keeps numbers as doubles in Lua, but LuaJ prints
                    // integers without decimal point — match Gson->Lua conversion
                    return LuaValue.valueOf((long) d);
                }
                return LuaValue.valueOf(d);
            }
            return LuaValue.valueOf(p.getAsString());
        }
        if (el.isJsonArray()) {
            JsonArray arr = el.getAsJsonArray();
            LuaTable t = new LuaTable();
            for (int i = 0; i < arr.size(); i++) t.set(i + 1, jsonToLua(arr.get(i)));
            return t;
        }
        if (el.isJsonObject()) {
            JsonObject obj = el.getAsJsonObject();
            LuaTable t = new LuaTable();
            for (Map.Entry<String, JsonElement> e : obj.entrySet()) {
                t.set(e.getKey(), jsonToLua(e.getValue()));
            }
            return t;
        }
        return LuaValue.NIL;
    }

    static JsonElement luaToJson(LuaValue v) {
        if (v.isnil()) return JsonNull.INSTANCE;
        if (v.isboolean()) return new JsonPrimitive(v.toboolean());
        if (v.isnumber()) {
            double d = v.todouble();
            if (d == Math.floor(d) && Math.abs(d) < 1e15) return new JsonPrimitive((long) d);
            return new JsonPrimitive(d);
        }
        if (v.isstring()) return new JsonPrimitive(v.tojstring());
        if (v.istable()) {
            LuaTable t = v.checktable();
            // array?
            if (t.length() > 0) {
                JsonArray arr = new JsonArray();
                for (int i = 1; i <= t.length(); i++) arr.add(luaToJson(t.get(i)));
                return arr;
            }
            JsonObject obj = new JsonObject();
            LuaValue k = LuaValue.NIL;
            while (true) {
                Varargs n = t.next(k);
                if (n.arg1().isnil()) break;
                k = n.arg1();
                obj.add(k.tojstring(), luaToJson(n.arg(2)));
            }
            return obj;
        }
        return JsonNull.INSTANCE;
    }
}
