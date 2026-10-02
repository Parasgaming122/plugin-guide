#!/usr/bin/env python3
"""Assemble oop.lua from parts and syntax-check with the harness checker."""
import subprocess

PARTS = ["part1.lua", "part2.lua", "part3.lua", "part4.lua"]
SRC = "/home/z/my-project/scripts/oop_plugin"
OUT = "/home/z/my-project/download/oop.lua"

chunks = []
for p in PARTS:
    with open(f"{SRC}/{p}", encoding="utf-8") as f:
        chunks.append(f.read().rstrip("\n"))
plugin = "\n\n".join(chunks) + "\n"

with open(OUT, "w", encoding="utf-8") as f:
    f.write(plugin)

print(f"assembled {OUT}: {len(plugin)} chars, {plugin.count(chr(10))} lines")

r = subprocess.run(
    ["java", "-cp", ".:luaj-jse-3.0.1.jar", "SyntaxCheck2", OUT],
    cwd="/home/z/my-project/test-harness",
    capture_output=True, text=True, timeout=60)
print(r.stdout[:800])
