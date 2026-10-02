# test/ — suites, harness, fixtures

## What's here

| File | Suite | Plugin |
|---|---|---|
| `LuaTest.java` | live API flow + mock decryption/translation | wtrlab |
| `Novel543Test.java` | live site + translator fault-injection | novel543 |
| `WuxiaboxTest.java` | 147 fixture tests incl. mirror breaker restarts | wuxiabox |
| `OopTest.java` | 97 checks: catalog/cards/TOC pagination/caches | oop |
| `BixiangeTest.java` | 90 checks incl. the 2026-09-30 URL-scheme capture | bixiange |
| `S69TwTest.java` | 127 checks: real /Indexlist/ fixtures, budgets | 69shubaTw |
| `S69RealSeed.java` | 20 real-capture end-to-end checks | 69shubaTw |
| `FanqietcTest.lua` | 86 live checks: rankings/search/4051-ch book/translator/mirror failover | fanqietc |
| `NoveLaHarness.java` | faithful NoveLA sandbox harness (luaj + gson + jsoup + real networking) — runs `.lua` test scripts against plugins | all |
| `SyntaxCheck.java` | load + function-surface check for any plugin | all |

`lib/` — luaj-jse, jsoup, gson, and the ecj compiler jar.
`fixtures/` — the recorded HTML/JSON trees the offline suites read.

## Paths (IMPORTANT)

The Java suites were authored inside `/home/z/my-project`; several read
fixtures and plugins via absolute paths such as
`/home/z/my-project/research/newsites/…`. Two options:

1. **Restore-and-run**: unpack this archive so that `research/` maps to
   `/home/z/my-project/research/` (the fixtures here are copies of those
   trees) and `plugins/*.lua` to `/home/z/my-project/download/…`.
2. **Re-path**: `sed -i 's#/home/z/my-project/research#<abs path to>/test/fixtures#g' *.java`
   then compile.

`FanqietcTest.lua` has no absolute-path dependencies — it loads the plugin
path you pass it and talks to the live API.

## Run

```bash
bash run_all.sh          # compile + run everything
# fanqietc alone:
java -cp "lib/*:bin" NoveLaHarness ../plugins/fanqietc.lua FanqietcTest.lua
```

Last green run: 2026-09-30 — LuaTest 66/66 · Novel543Test 197/197 ·
WuxiaboxTest 147/147 · OopTest 97/97 · BixiangeTest 90/90 · S69TwTest 127/127 ·
S69RealSeed 20/20 · **FanqietcTest 86/86**.
