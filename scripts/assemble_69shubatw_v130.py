#!/usr/bin/env python3
"""Assemble 69shubaTw.lua v1.3.0 from the v1.2.0 base:
1. splice: replace the whole TOC engine region (parseTocChapters …
   getChapterList) with part_toc_v130.lua (lazy pages, capital-I
   /Indexlist/ URLs, protected-span parsing, no batch/chase/walk/seed)
2. small edits: VERSION, header comment block, cf_options markers,
   case-insensitive bookIdFromUrl, Accept-Language header
"""
import re, sys

BASE = "/home/z/my-project/download/69shubaTw.lua"
TOC  = "/home/z/my-project/scripts/69shubatw_plugin/part_toc_v130.lua"
OUT  = "/home/z/my-project/download/69shubaTw.lua"

src = open(BASE, encoding='utf-8').read()
toc = open(TOC, encoding='utf-8').read()

# ── 1. splice the TOC engine ────────────────────────────────────────────────
start_marker = "-- Collect chapters from an /indexlist/ page. Returns an array of"
end_marker = "-- ═══════════════════════════════════════════════════════════════════════════\n-- Chapter text — /read/{bid}/{cid}"

si = src.find(start_marker)
ei = src.find(end_marker)
assert si > 0, "start marker not found"
assert ei > si, "end marker not found"
src = src[:si] + toc + src[ei:]

# ── 2. small edits ──────────────────────────────────────────────────────────

# 2a. VERSION
src = src.replace('local VERSION = "1.2.0"', 'local VERSION = "1.3.0"', 1)

# 2b. bookIdFromUrl — case-insensitive (accept /Indexlist/ pastes too)
old_fn = '''local function bookIdFromUrl(bookUrl)
  local u = bookUrl or ""
  local n = tonumber(string.match(u, "/book/(%d+)"))
  if n then return n end
  n = tonumber(string.match(u, "/indexlist/(%d+)"))
  if n then return n end
  return tonumber(string.match(u, "/read/(%d+)/%d+"))
end'''
new_fn = '''local function bookIdFromUrl(bookUrl)
  local u = string.lower(bookUrl or "")
  local n = tonumber(string.match(u, "/book/(%d+)"))
  if n then return n end
  n = tonumber(string.match(u, "/indexlist/(%d+)"))
  if n then return n end
  return tonumber(string.match(u, "/read/(%d+)/%d+"))
end'''
assert old_fn in src, "bookIdFromUrl not found"
src = src.replace(old_fn, new_fn, 1)

# 2c. httpGetPage — Accept-Language (a real TW reader's header)
old_h = '''  return http_get(url, {
    headers = {
      ["Referer"] = SITE .. "/",
      ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    }
  })'''
new_h = '''  return http_get(url, {
    headers = {
      ["Referer"] = SITE .. "/",
      ["Accept"]  = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      ["Accept-Language"] = "zh-TW,zh;q=0.9,en-US;q=0.8"
    }
  })'''
assert old_h in src, "httpGetPage headers not found"
src = src.replace(old_h, new_h, 1)

# 2d. cf_options — richer EdgeOne markers (docs-verified field; harmless on
# builds without it). Keep them in the same order: strongest first.
old_cf = '''cf_options = {
  trigger_markers = {
    "aegis_captcha_verify",              -- the challenge's POST endpoint
    "recaptcha-v3-container",            -- the checkbox widget markup
    "Please complete human verification" -- the challenge page <title>
  }
}'''
new_cf = '''cf_options = {
  trigger_markers = {
    "aegis_captcha_verify",              -- the challenge's POST endpoint
    "recaptcha-v3-container",            -- the checkbox widget markup
    "Please complete human verification",-- the challenge page <title>
    "challenges.cloudflare.com/turnstile"-- the challenge's Turnstile script
  }
}'''
assert old_cf in src, "cf_options not found"
src = src.replace(old_cf, new_cf, 1)

# 2e. header comment block: replace the "WHAT'S NEW IN v1.2.0" section and
# the anti-bot preamble with the v1.3.0 story.
old_news = src[src.find("-- WHAT'S NEW IN v1.2.0"):src.find("-- WHAT'S IN THE PLUGIN:")]
new_news = '''-- WHAT'S NEW IN v1.3.0 (the "solver storm + chapters never loaded" fix):
--   • WAF DISCOVERY: EdgeOne's path rule challenges lowercase /indexlist/*
--     from EVERY IP (clean or not; the __ct pass cookie lasts 5 minutes) —
--     that is why the solver kept opening and chapters never loaded. The
--     rule is case-sensitive, the router is not: ALL catalog fetches now go
--     to /Indexlist/{id}/{N}/ (capital I) — WAF-free, zero solver.
--   • THE REAL MARKUP (captured live 2026-09-26 via the clean-IP translate
--     proxy, book 342441 = 450 chapters on 5 pages): chapters live in
--     div#alllist as <li><a href=/read/{bid}/{cid}> … AND as anti-scrape
--     <li><span class=protected-chapter-link data-cid-url=…> (~2 per page —
--     both forms are collected now; the old parser silently dropped the
--     spans). Pager = select#indexselect-top with ALL page URLs as option
--     values ("/indexlist/{id}/", "/indexlist/{id}/2/" … "401 - 450章") +
--     下一页/上一页 anchors + a "没有了" disabled span on the last page.
--   • ZERO SPECULATIVE REQUESTS: the v1.2.0 batch prefetch (pages 2..8 in
--     parallel), the blind page-2 probe, the window chase and the
--     /book/-seed + per-chapter #pb_next walk are ALL removed — each was
--     another solver ladder when the WAF bit. Page 1 = ONE fetch; page N =
--     ONE fetch each, engine-driven and lazy; a ≤100-chapter novel costs
--     exactly one catalog request.
--   • TOC cache format v3 (drops the walk fields; v1/v2 entries discarded).
--     Interior pages serve offline; the last page re-fetches for growth.
--   • Early-stop safe: the engine keeps every page collected before a
--     failure (verified in DownloaderRepository: "FAILED page N, stopping
--     early") — a failed page 4/5 still leaves 300 readable chapters.
--
'''
src = src.replace(old_news, new_news, 1)

# 2f. fix the header's TOC line + anti-bot note to match v1.3.0 reality
src = src.replace(
  '''--   • TOC:            /indexlist/{id}/ (+ /{N}/ pages — the site-wide
--                     pager shape, CONFIRMED by the wcshuba.com sibling
--                     (same CMS generation): /chapterlist/{id}/{N}.html,
--                     100 chapters per page, select options carry every
--                     page URL, 下一页 link until the last page).''',
  '''--   • TOC:            /Indexlist/{id}/ + /{N}/ pages (capital I — the
--                     WAF-exempt form; 100 chapters per page, user-verified;
--                     markup live-captured: div#alllist list, protected
--                     chapter spans, select#indexselect-top page options).''', 1)

src = src.replace(
  '''-- ANTI-BOT — Tencent EdgeOne "aegis" captcha, NOT Cloudflare:
--   Server: Edge/1.1.28. From datacenter IPs every path answers 403 with a
--   custom human-verification page (reCAPTCHA v3 checkbox + Turnstile
--   script; the token POSTs to /aegis_captcha_verify?rule_uuid=…; verified
--   cookies __ct_ac_cpg + __ct_cya_ckt follow). The engine's stock CF
--   detector does NOT recognize it (Server ≠ cloudflare) — so this plugin
--   registers cf_options.trigger_markers. With those, the app's interceptor
--   runs its WebView bypass ladder on the challenge page: solve the
--   "I'm not a robot" checkbox once in the WebView (it auto-passes on real
--   devices), tap Done, and the retry carries the __ct_* cookies. On
--   residential IPs (typical phones) the site usually serves pages with no
--   challenge at all.
--   Path asymmetry (verified via the Google-Translate proxy): /, /book/*,
--   /read/*, /search/*, /fenlei/*, /quanben/* pass from Google's IPs while
--   /indexlist/* (the chapter catalog) is challenged even there — expect the
--   catalog to be the first surface to need the WebView solve.''',
  '''-- ANTI-BOT — Tencent EdgeOne "aegis" captcha, NOT Cloudflare:
--   Server: Edge/1.1.28. Challenges serve a custom human-verification page
--   (reCAPTCHA v3 checkbox + Turnstile script; the token POSTs to
--   /aegis_captcha_verify?rule_uuid=…; cookies __ct_ac_cpg + __ct_cya_ckt
--   follow — the pass cookie lasts only 5 MINUTES, so re-challenges were
--   the norm on the old lowercase catalog path).
--   THE v1.3.0 FIX: EdgeOne's rule matches lowercase /indexlist/* ONLY
--   (verified: /indexlist/342441/ → 403 challenge even from Google's clean
--   translate-proxy IPs, /Indexlist/342441/ → 200 real page from the same
--   IPs, same session, seconds apart). The plugin fetches every catalog
--   page through the capital form — no challenge, no solver, from any IP
--   reputation the site otherwise tolerates. /book/*, /read/*, /search/*,
--   /fenlei/*, /quanben/* have no such rule (verified from clean IPs).
--   cf_options.trigger_markers stays registered (a documented field on
--   current builds) so that IF another surface ever challenges, the app's
--   WebView ladder still engages; the plugin also detects the challenge
--   body itself and fails with a guided message instead of parsing it.''')

open(OUT, 'w', encoding='utf-8').write(src)
lines = src.count('\n') + 1
print(f"assembled {OUT}: {len(src)} bytes, {lines} lines, v1.3.0")
