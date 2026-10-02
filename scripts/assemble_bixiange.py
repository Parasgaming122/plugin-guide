#!/usr/bin/env python3
"""Assemble bixiange.lua from parts and syntax-check with luaj."""
import subprocess

PARTS = ["part1.lua", "part2.lua", "part3.lua", "part4.lua"]
SRC = "/home/z/my-project/scripts/bixiange_plugin"
OUT = "/home/z/my-project/download/bixiange.lua"

chunks = []
for p in PARTS:
    with open(f"{SRC}/{p}", encoding="utf-8") as f:
        chunks.append(f.read().rstrip("\n"))
plugin = "\n\n".join(chunks) + "\n"

with open(OUT, "w", encoding="utf-8") as f:
    f.write(plugin)

print(f"assembled {OUT}: {len(plugin)} chars, {plugin.count(chr(10))} lines")

# syntax check with luaj (test-harness has luaj-jse jar)
cmd = ["java", "-cp", "/home/z/my-project/test-harness/luaj-jse-3.0.1.jar",
       "luaj.compiler.LuaC", OUT]
r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
if r.returncode != 0:
    print("SYNTAX CHECK FAILED:")
    print(r.stdout[-2000:])
    print(r.stderr[-2000:])
else:
    print("syntax OK (luaj LuaC)")
