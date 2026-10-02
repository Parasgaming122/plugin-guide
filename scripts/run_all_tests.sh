#!/bin/bash
# run_all_tests.sh — compile + run ALL plugin test suites, print a summary.
# Usage: bash /home/z/my-project/scripts/run_all_tests.sh [filter]
# Suites: LuaTest(wtrlab) Novel543Test WuxiaboxTest OopTest BixiangeTest S69TwTest S69RealSeed(69shubaTw)
set -u
cd /home/z/my-project/testenv

CP=$(ls lib/*.jar lib2/*.jar | tr '\n' ':').

# Copy the two suites that live in download/test-harness into the run dir (fresh each run)
for f in OopTest BixiangeTest; do
  if [ -f /home/z/my-project/download/test-harness/$f.java ]; then
    cp /home/z/my-project/download/test-harness/$f.java /home/z/my-project/testenv/$f.java
  fi
done

SUITES="LuaTest Novel543Test WuxiaboxTest OopTest BixiangeTest S69TwTest S69RealSeed"
FILTER="${1:-all}"

echo "=== Compiling all suites (ecj) ==="
rm -f OopTest.class BixiangeTest.class 'OopTest$'*.class 'BixiangeTest$'*.class 2>/dev/null
java -jar lib/ecj.jar -source 19 -nowarn -cp "$CP" \
  LuaTest.java Novel543Test.java WuxiaboxTest.java OopTest.java BixiangeTest.java S69TwTest.java S69RealSeed.java \
  -d . 2>&1 | grep -iv "^Warning\|^ *Note\|^1 problem" | head -20
if [ ! -f S69TwTest.class ]; then echo "COMPILE FAILED"; exit 1; fi
echo "Compile OK"

declare -A RESULT
for s in $SUITES; do
  if [ "$FILTER" != "all" ] && [ "$FILTER" != "$s" ]; then continue; fi
  echo ""
  echo "=== Running $s ==="
  OUT=$(java -cp "$CP" "$s" 2>&1)
  TAIL=$(echo "$OUT" | tail -3)
  echo "$TAIL"
  # capture the pass/fail line
  PF=$(echo "$OUT" | grep -iE "PASS|FAIL|passed|failed|OK\b" | tail -1)
  RESULT[$s]="$PF"
  echo "$OUT" > /home/z/my-project/tool-results/test_$s.log
done

echo ""
echo "================= SUMMARY ================="
for s in $SUITES; do
  if [ "$FILTER" != "all" ] && [ "$FILTER" != "$s" ]; then continue; fi
  printf "%-16s %s\n" "$s:" "${RESULT[$s]:-no-result-line}"
done
