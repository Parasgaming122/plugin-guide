#!/usr/bin/env bash
# Compile + run every suite in this directory. See README.md first —
# the Java suites reference fixtures via ABSOLUTE /home/z/my-project/…
# paths; either restore this archive to that exact path or sed-replace
# the paths to this directory (see README.md "Paths").
set -e
cd "$(dirname "$0")"
mkdir -p bin
CP="lib/luaj-jse-3.0.1.jar:lib/jsoup-1.23.1.jar:lib/gson-2.14.0.jar"
echo "== compiling =="
java -jar lib/ecj.jar -cp "$CP" -source 21 -target 21 -d bin *.java
echo "== running =="
for S in LuaTest Novel543Test WuxiaboxTest OopTest BixiangeTest S69TwTest; do
  echo "── $S"
  java -cp "$CP:bin" "$S" || echo "   ($S exited non-zero)"
done
echo "── S69RealSeed (live capture checks)"
java -cp "$CP:bin" S69RealSeed || echo "   (exited non-zero)"
echo "── FanqietcTest (live; needs network)"
java -cp "$CP:bin" NoveLaHarness ../plugins/fanqietc.lua FanqietcTest.lua   || echo "   (exited non-zero)"
echo "== done =="
