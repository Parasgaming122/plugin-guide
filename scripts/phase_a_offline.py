#!/usr/bin/env python3
"""Phase A only: offline verification of plugin's getChapterText on captured
arr:/str:/array samples. Fast — no network, no waiting.

Loads the plugin in lupa with stubbed NoveLA globals. http_post returns the
captured JSON sample for /api/reader/get calls. Calls getChapterText and
verifies the returned text is readable.
"""
import json
import os
import re
import sys
import urllib.parse

import lupa.luajit21

PLUGIN_PATH = "/home/z/my-project/download/wtrlab.lua"
SAMPLES_DIR_A = "/home/z/my-project/wtrlab-analysis"
SAMPLES_DIR_B = "/home/z/my-project/research"
SAMPLES = {
    "enc_raw_2_1_web.json":       {"mode": "web",     "raw_id": "2",     "chapter_no": 1},
    "enc_raw_93574_1_web.json":   {"mode": "web",     "raw_id": "93574", "chapter_no": 1},
    "enc_raw_93618_1_web.json":   {"mode": "web",     "raw_id": "93618", "chapter_no": 1},
    "enc_webplus.json":           {"mode": "webplus", "raw_id": "2",     "chapter_no": 10},
    "reader1.json":               {"mode": "ai",      "raw_id": "93618", "chapter_no": 1},
}


def is_readable_text(s):
    if not s or len(s) < 50:
        return False
    if isinstance(s, (bytes, bytearray)):
        try:
            s = s.decode("utf-8", errors="replace")
        except Exception:
            return False
    cjk = sum(1 for c in s if 0x4e00 <= ord(c) <= 0x9fff)
    ascii_print = sum(1 for c in s if c.isascii() and (c.isalpha() or c.isspace() or c in ".,!?;:'\"-—※"))
    return (cjk + ascii_print) / len(s) > 0.5


def main():
    print("=== Phase A: offline test on captured samples ===\n")

    # Load captured samples
    sample_lookup = {}
    for filename, info in SAMPLES.items():
        for d in (SAMPLES_DIR_A, SAMPLES_DIR_B):
            path = os.path.join(d, filename)
            if os.path.exists(path):
                with open(path, encoding="utf-8") as f:
                    sample_lookup[filename] = (json.load(f), info, path)
                break
    print(f"Loaded {len(sample_lookup)} samples")
    for fn, (data, info, path) in sample_lookup.items():
        # Try to find body in nested data
        inner = data.get("data", {})
        if isinstance(inner, dict):
            inner2 = inner.get("data", {})
            if isinstance(inner2, dict):
                body = inner2.get("body")
            else:
                body = None
        else:
            body = None
        body_kind = ("array" if isinstance(body, list) else
                    "arr:string" if isinstance(body, str) and body.startswith("arr:") else
                    "plain string" if isinstance(body, str) else "None")
        print(f"  {fn:35s} mode={info['mode']:7s} raw_id={info['raw_id']:7s} body={body_kind} (len={len(body) if body else 0})")
    print()

    # Load plugin with stubs
    with open(PLUGIN_PATH, encoding="utf-8") as f:
        src = f.read()
    lua = lupa.luajit21.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    for k in ("log_error", "log_info", "log_warn", "log_debug"):
        g[k] = lambda *a, **kw: None
    g["url_encode"] = lambda s: urllib.parse.quote(str(s)) if s else ""

    # http_post stub: return captured sample by raw_id match
    def http_post_stub(url, body=None, opts=None):
        url = str(url) if url else ""
        if "api/reader/get" in url:
            try:
                if body is None:
                    payload = {}
                elif isinstance(body, str):
                    payload = json.loads(body) if body else {}
                elif isinstance(body, (dict, list)):
                    payload = body
                else:
                    payload = {}
            except Exception:
                payload = {}
            raw_id_req = str(payload.get("raw_id", ""))
            ch_req = int(payload.get("chapter_no", 0))
            translate_req = payload.get("translate", "ai")
            # Find best match: same raw_id + chapter_no preferred; else same raw_id
            best = None
            for fn, (data, info, path) in sample_lookup.items():
                if info["raw_id"] == raw_id_req and info["chapter_no"] == ch_req:
                    best = data
                    break
            if not best:
                for fn, (data, info, path) in sample_lookup.items():
                    if info["raw_id"] == raw_id_req:
                        best = data
                        break
            if not best:
                # Fall back to any sample (for raw_id mismatch testing)
                best = list(sample_lookup.values())[0][0]
            return {"success": True, "body": json.dumps(best),
                    "code": 200, "headers": {"content-type": "application/json"}}
        # Decrypt proxy fallback (should not be hit)
        return {"success": False, "body": "", "code": 0, "headers": {}}
    g["http_post"] = http_post_stub
    g["http_get"] = lambda *a, **kw: {"success": False, "body": "", "code": 0, "headers": {}}
    g["http_request"] = http_post_stub

    g["string_split"] = lambda s, sep: str(s).split(sep) if s else []
    g["string_trim"] = lambda s: s and s.strip() or ""
    g["string_starts_with"] = lambda s, p: bool(s) and s.startswith(p) or False
    g["string_normalize"] = lambda s: s or ""  # NFC normalization stub (returns as-is)
    g["string_clean"] = lambda s: s or ""  # whitespace cleanup stub
    g["string_lower"] = lambda s: s.lower() if isinstance(s, str) else s
    g["string_upper"] = lambda s: s.upper() if isinstance(s, str) else s
    g["string_replace"] = lambda s, pat, repl: re.sub(pat, repl, s) if s else s
    g["string_find"] = lambda s, pat: s.find(pat) if isinstance(s, str) else -1
    g["string_sub"] = lambda s, i, j=None: s[i-1:(j if j is not None else len(s))] if isinstance(s, str) else s
    g["string_len"] = lambda s: len(s) if isinstance(s, str) else 0
    g["string_format"] = lambda *a: a[0] % a[1:] if a else ""
    g["regex_match"] = lambda s, pat: re.findall(pat, s) if s else []
    g["regex_replace"] = lambda s, pat, repl: re.sub(pat, repl, s) if s else s
    g["regex_find"] = lambda s, pat: re.findall(pat, s) if s else []
    g["sha1"] = lambda s: "stub"
    g["sha256"] = lambda s: "stub"
    g["base64_decode"] = lambda s: "stub"
    g["settings_get_string"] = lambda k, d: d
    g["settings_put_string"] = lambda k, v: None
    g["sleep_ms"] = lambda ms: None
    g["sleep"] = lambda ms: None
    g["get_preference"] = lambda k: ""
    g["html_select"] = lambda *a: []
    g["html_select_first"] = lambda *a: None
    g["html_text"] = lambda *a: ""
    g["html_attr"] = lambda html, sel, attr: ""

    def lua_to_py(o):
        """Convert lupa Lua table to native Python list/dict (recursively)."""
        if o is None or isinstance(o, (str, int, float, bool)):
            return o
        try:
            if hasattr(o, "items") and callable(o.items):
                items = list(o.items())
                if not items:
                    return {}
                int_keys = [k for k, _ in items if isinstance(k, int)]
                if int_keys and sorted(int_keys) == list(range(1, len(int_keys) + 1)) and len(int_keys) == len(items):
                    return [lua_to_py(v) for _, v in sorted(items, key=lambda kv: kv[0])]
                return {str(k): lua_to_py(v) for k, v in items}
        except Exception:
            pass
        try:
            return [lua_to_py(x) for x in o]
        except Exception:
            return str(o)

    def py_to_lua(o, _lua=lua):
        """Convert Python list/dict to lupa LuaTable (recursively)."""
        if o is None or isinstance(o, (str, int, float, bool)):
            return o
        if isinstance(o, list):
            return _lua.table_from([py_to_lua(x) for x in o])
        if isinstance(o, dict):
            return _lua.table_from({str(k): py_to_lua(v) for k, v in o.items()})
        return str(o)

    def json_parse(s):
        if not s:
            return None
        try:
            parsed = json.loads(s) if isinstance(s, str) else s
        except Exception:
            return None
        # Return as Lua table so the plugin's `t.key` accesses return nil
        # (native Lua semantics) instead of lupa raising KeyError on
        # missing keys.
        return py_to_lua(parsed)
    def json_stringify(o):
        if o is None:
            return "null"
        try:
            return json.dumps(lua_to_py(o))
        except Exception as e:
            import sys as _sys
            print(f"DBG json_stringify: {type(o).__name__} err={e}", file=_sys.stderr)
            return "null"
    g["json_parse"] = json_parse
    g["json_stringify"] = json_stringify

    try:
        lua.execute(src)
        print("Plugin loaded successfully.")
    except lupa.luajit21.LuaError as e:
        print(f"FATAL: plugin load failed: {e}")
        sys.exit(1)

    # Smoke check
    lua.execute("function _resolve_str(t) return table.concat(tagSearchResolve(t) or {}, ',') end")
    r = str(lua.globals()._resolve_str("Honghuang") or "")
    assert r == "801", f"tagSearchResolve('Honghuang') returned {r!r}"
    print(f"Smoke: tagSearchResolve('Honghuang') = '801'  ✓\n")

    # Run each sample through the plugin's getChapterText
    results = []
    for fn, (data, info, path) in sample_lookup.items():
        mode = info["mode"]
        raw_id = info["raw_id"]
        ch_no = info["chapter_no"]

        # Set mode preference
        if mode == "web":
            lua.globals()["get_preference"] = lambda k: "raw" if k == "wtrlab_mode" else ""
        else:
            lua.globals()["get_preference"] = lambda k: "ai" if k == "wtrlab_mode" else ""

        chapter_url = f"https://wtr-lab.com/en/novel/{raw_id}/test-slug/chapter-{ch_no}"
        html = f"<html><head><link rel='canonical' href='{chapter_url}'/></head></html>"

        try:
            text = lua.globals().getChapterText(html, chapter_url)
        except lupa.luajit21.LuaError as e:
            results.append((fn, mode, "LUA_ERROR", str(e)[:200], ""))
            print(f"  {fn:35s} ({mode:7s}): LUA_ERROR: {str(e)[:120]}")
            continue

        if not text or (isinstance(text, str) and text == ""):
            results.append((fn, mode, "EMPTY", "plugin returned empty", ""))
            print(f"  {fn:35s} ({mode:7s}): EMPTY")
            continue

        text_str = str(text)
        if is_readable_text(text_str):
            results.append((fn, mode, "SUCCESS",
                          f"{len(text_str)} chars readable",
                          text_str[:120].replace('\n', ' ')))
            print(f"  {fn:35s} ({mode:7s}): SUCCESS ({len(text_str)} chars)  sample: {text_str[:80].replace(chr(10),' ')}")
        else:
            results.append((fn, mode, "GIBBERISH",
                          f"unreadable (first 200: {text_str[:200]!r})",
                          text_str[:120]))
            print(f"  {fn:35s} ({mode:7s}): GIBBERISH  first200={text_str[:200]!r}")

    # Summary
    print("\n=== Phase A summary ===")
    n_success = sum(1 for r in results if r[2] == "SUCCESS")
    n_gibberish = sum(1 for r in results if r[2] == "GIBBERISH")
    n_error = sum(1 for r in results if r[2] in ("LUA_ERROR", "EMPTY"))
    print(f"  {len(results)} samples tested: {n_success} SUCCESS, {n_gibberish} GIBBERISH, {n_error} ERROR")
    if n_gibberish == 0 and n_error == 0:
        print(f"  VERDICT: PASS — plugin's getChapterText works on all captured samples")
    elif n_gibberish > 0:
        print(f"  VERDICT: FAIL — {n_gibberish} samples produced gibberish (regression)")
    else:
        print(f"  VERDICT: PARTIAL — {n_error} samples errored at the plugin level")

    return results


if __name__ == "__main__":
    main()
