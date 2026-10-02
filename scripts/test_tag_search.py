#!/usr/bin/env python3
"""Verify tag_search_index.lua.txt logic via lupa (LuaJIT 5.1-compatible).

Uses an in-Lua wrapper that returns the result as a comma-joined string,
to dodge a lupa quirk where iterating a single-element Lua table returned
from a function returns stale/wrong data. The plugin itself uses native
luaj-jse inside NoveLA, where this quirk does not exist.
"""
import sys
import lupa.luajit21

LUA_BLOCK = "/home/z/my-project/scripts/tag_search_index.lua.txt"


def main():
    lua = lupa.luajit21.LuaRuntime(unpack_returned_tuples=True)
    with open(LUA_BLOCK, encoding="utf-8") as f:
        block_src = f.read()

    # Append a string-returning wrapper for test purposes
    block_src += """
function _resolve_to_str(text)
    local out = tagSearchResolve(text)
    return table.concat(out, ",")
end
"""
    lua.execute(block_src)
    resolve_str = lua.globals()._resolve_to_str

    def call(text):
        s = resolve_str(text)
        s = str(s) if s else ""
        return sorted([x for x in s.split(",") if x])

    tests = [
        ("nil input", None, []),
        ("empty string", "", []),
        ("whitespace only", "   ", []),
        ("'Honghuang' substring", "Honghuang", ["801"]),
        ("'honghuang' lowercase", "honghuang", ["801"]),
        ("direct id '801'", "801", ["801"]),
        ("'801,Honghuang' dedup", "801,Honghuang", ["801"]),
        ("'Naruto,Honkai' comma", "Naruto,Honkai", ["769", "818"]),
        ("'Naruto Honkai' space", "Naruto Honkai", ["769", "818"]),
        ("'Naruto;Honkai' semicolon", "Naruto;Honkai", ["769", "818"]),
        ("'Naruto\\nHonkai' newline", "Naruto\nHonkai", ["769", "818"]),
        ("'Naruto\\tHonkai' tab", "Naruto\tHonkai", ["769", "818"]),
        ("'adapted' matches 12 tags",
         "adapted", ["10", "11", "12", "13", "14", "15", "16", "17", "18", "8", "846", "9"]),
        ("garbage 'zzzzznothing'", "zzzzznothing", []),
        ("'zzzzznothing,Naruto' mixed", "zzzzznothing,Naruto", ["769"]),
        ("',,Naruto,,Honkai,'", ",,Naruto,,Honkai,", ["769", "818"]),
    ]

    pass_n = fail_n = 0
    for label, inp, expected in tests:
        got = call(inp)
        if got == expected:
            pass_n += 1
            print(f"PASS: {label}  =>  {got}")
        else:
            fail_n += 1
            print(f"FAIL: {label}\n  expected: {expected}\n  got:      {got}")

    # Performance sanity: 1000 lookups of "protagonist" (broad match)
    import time
    t0 = time.time()
    for _ in range(1000):
        resolve_str("protagonist")
    t1 = time.time()
    elapsed_ms = (t1 - t0) * 1000
    print(f"\n1000x 'protagonist' lookups: {elapsed_ms:.1f}ms")
    if elapsed_ms < 1000:
        pass_n += 1
        print("PASS: performance under 1s for 1000 lookups")
    else:
        fail_n += 1
        print("FAIL: performance too slow")

    print(f"\n=== {pass_n} passed, {fail_n} failed ===")
    if fail_n > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
