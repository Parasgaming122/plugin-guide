#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Update MAINTENANCE.md for wuxiabox v2.3.0 (smart mirror switcher)."""
import sys

PATH = "/home/z/my-project/download/MAINTENANCE.md"

with open(PATH, "r", encoding="utf-8") as f:
    src = f.read()

def replace_once(text, old, new, what):
    n = text.count(old)
    if n != 1:
        print(f"ANCHOR FAIL ({what}): {n} occurrences", file=sys.stderr)
        sys.exit(1)
    return text.replace(old, new, 1)

# 1. quick-reference card: version
src = replace_once(
    src,
    "**2.2.0 (2026-09-18)** — poster fix + search pagination + curated 755-tag searchable picker on 2.1.0 (search fix + mirror + popular tags)",
    "**2.3.0 (2026-09-19)** — smart mirror switcher (persistent circuit breaker, health-aware fetch order, mirror-native search pagination) on 2.2.0 (poster fix + search pagination + curated 755-tag searchable picker)",
    "card version")

# 2. quick-reference card: line count
src = replace_once(
    src,
    "`en/wuxiabox.lua` (3,053 lines)",
    "`en/wuxiabox.lua` (3,339 lines)",
    "card line count")

# 3. quick-reference card: harness count
src = replace_once(
    src,
    "`testenv/WuxiaboxTest.java` (**125 fixture tests**, header-capturing mocks)",
    "`testenv/WuxiaboxTest.java` (**147 fixture tests**, header-capturing mocks + plugin-reload restart simulation)",
    "card harness count")

# 4. Part 0.7 quick map: header + smart switcher facts
src = replace_once(
    src,
    """## Part 0.7 — WuxiaBox plugin (`en/wuxiabox.lua` v2.2.0) — quick map

Full documentation lives in `download/wuxiabox_pull_request.md` (v2.2.0 PR; site map, mirror portability table, curation pipeline, 125-test table). Key facts for maintenance:""",
    """## Part 0.7 — WuxiaBox plugin (`en/wuxiabox.lua` v2.3.0) — quick map

Full documentation lives in `download/wuxiabox_pull_request.md` (v2.3.0 PR; smart-switcher design, engine-fetch reality + optional patch, site map, mirror portability table, curation pipeline, 147-test table). Key facts for maintenance:""",
    "part 0.7 header")

# 5. Part 0.7: chapters line + new switcher bullet
src = replace_once(
    src,
    "- **Chapters**: novel page embeds ch 1–100; `/e/extend/fy.php?page=N-1&wjm={slug}` (XHR headers required) paginates the rest; `parsePage` chapter pagination; 502 self-heal with per-attempt site alternation + quadratic backoff; pacing setting.",
    """- **Chapters**: novel page embeds ch 1–100; `/e/extend/fy.php?page=N-1&wjm={slug}` (XHR headers required) paginates the rest; `parsePage` chapter pagination; 502 self-heal with health-aware attempt order + quadratic backoff (NO pre-attempt sleep in 2.3.0 — the engine's retry ladder already waited); pacing setting.
- **Smart switcher (v2.3.0)**: per-site health tracker persisted via `set_preference` key `wuxiabox_site_health` (`box=<fails>,<cooldownUntilMs>;spot=…`) — 2 consecutive fails → 10-min cooldown (skipped by `orderedBases()`), success resets, 404 neutral, expiry half-open. Every fetch path feeds it, INCLUDING the engine's own failed chapter fetch (getChapterText charges junk bodies to SITE before rescuing). Search records its searchid's base per query (`_searchBaseByQuery`) so mirror-started searches paginate on the mirror. `transformChapterUrl(url)` ships as a forward-compatible hook — inert on stock engines, active on builds that expose it (PR doc has the 10-line Kotlin patch).""",
    "part 0.7 chapters+switcher")

# 6. new gotchas 42-43
src = replace_once(
    src,
    "41. **Hardcoded `User-Agent` headers override the UA preset** — engine priority: plugin header > preset by source id > preset by host > global UA. If a plugin hardcodes a UA anywhere, `getUserAgentPreset()` stops applying to that request (and breaks UA-consistency with the baked cf_clearance). Use the preset; let the engine add headers.",
    """41. **Hardcoded `User-Agent` headers override the UA preset** — engine priority: plugin header > preset by source id > preset by host > global UA. If a plugin hardcodes a UA anywhere, `getUserAgentPreset()` stops applying to that request (and breaks UA-consistency with the baked cf_clearance). Use the preset; let the engine add headers.
42. **The engine's chapter fetch is canonical-host-first and NOT exposed to Lua** (wuxiabox 2.3.0 research): `DownloaderRepository.bookChapter` does TWO engine-side requests to the stored chapter URL (redirect-resolve + document fetch) before `getChapterText(html, url)` ever runs. `SourceInterface.transformChapterUrl` exists but `LuaSourceAdapter` does not implement it — a Lua plugin cannot steer that hop. If the engine request RETURNS a body (502 page after ServerErrorRetryInterceptor's 4 retries — the interceptor RETURNS the last 502 response, it does not throw), the plugin gets it and can rescue from the mirror; if it THROWS (connect timeout / unsolvable CF challenge), the chapter fails with the plugin never invoked. Also: source matching is HOST-prefix based (`url.startsWith(baseUrl + "/")`) — chapter/book URLs MUST stay canonical wuxiabox.com or the engine can no longer route them to the plugin ("Source not supported"). The plugin ships an inert `transformChapterUrl()` hook + the PR documents the 10-line adapter patch that activates it.
43. **`set_preference` is the plugin's persistent store, not just settings UI** (wuxiabox 2.3.0): keys written via `set_preference` land in SharedPreferences "lua_preferences" and survive app restarts; keys NOT listed in `getSettingsSchema()` never appear in the UI. Ideal for engine-restart-surviving state (the smart switcher's health/cooldown state lives in `wuxiabox_site_health`). BUT the engine's `http_get` cache is only 2 s — never assume HTTP-level caching across runs; and remember a RELOADED Lua state re-reads prefs lazily (per `get_preference` call), so persisted state must be parsed defensively (clamp absurd values — clock skew after reboot can make old cooldowns look future-dated; the plugin ignores cooldowns > 1 h ahead).""",
    "gotchas 42-43")

with open(PATH, "w", encoding="utf-8") as f:
    f.write(src)
print(f"OK — MAINTENANCE.md updated: {src.count(chr(10)) + 1} lines")
