#!/usr/bin/env python3
"""Build the WuxiaBox TAG_SEARCH_INDEX and splice it into the plugin.

Pipeline:
 1. Load research/wuxiabox/tags_raw.json (harvested from /browsetags/ pages).
 2. Dedup by tag id (first occurrence wins).
 3. Unescape HTML entities iteratively (the site double-escapes some labels).
 4. Expand truncated 10-char labels to full spaced names using the WTR-Lab
    tag index (same NovelUpdates-derived taxonomy): a wuxiabox label is
    matched against every wtrlab name whose de-spaced form starts with it;
    exactly one candidate → use the full name, ambiguous → keep the site's
    truncated label.
 5. Sort by label (case-insensitive).
 6. Splice "id|Label" lines into download/wuxiaworld_site.lua between the
    BEGIN_TAG_INDEX / END_TAG_INDEX markers.

Usage: python3 scripts/build_wuxiabox_tag_index.py [--dry]
"""
import html
import json
import re
import sys

RAW = "/home/z/my-project/research/wuxiabox/tags_raw.json"
WTRLAB = "/home/z/my-project/download/wtrlab.lua"
PLUGIN = "/home/z/my-project/download/wuxiaworld_site.lua"

DRY = "--dry" in sys.argv


def unescape(s):
    for _ in range(3):
        if "&" not in s:
            break
        u = html.unescape(s)
        if u == s:
            break
        s = u
    return s


def flat(s):
    return re.sub(r"\s+", "", s).lower()


def load_wtrlab_names():
    src = open(WTRLAB, encoding="utf-8", errors="replace").read()
    m = re.search(r"TAG_SEARCH_INDEX = \[==\[(.*?)\]==\]", src, re.S)
    if not m:
        return []
    names = []
    for line in m.group(1).splitlines():
        parts = line.strip().split("|")
        if len(parts) >= 2 and parts[0].isdigit():
            names.append(parts[1])
    return names


def main():
    raw = json.load(open(RAW, encoding="utf-8"))
    # dedup by id
    by_id = {}
    for t in raw:
        if t["id"] not in by_id:
            by_id[t["id"]] = unescape(t["label"]).strip()
    tags = [(tid, label) for tid, label in by_id.items() if label]

    wtrlab = load_wtrlab_names()
    wtrlab_flats = {}
    for name in wtrlab:
        wtrlab_flats.setdefault(flat(name), []).append(name)

    expanded, kept = 0, 0
    out = []
    letters = {}  # tag id -> letter page it was harvested from
    for t in raw:
        if t["id"] not in letters:
            letters[t["id"]] = t.get("letter", "")
    for tid, label in tags:
        if "|" in label:
            continue  # would break the "id|label" format
        lf = flat(label)
        cands = set()
        for wf, names in wtrlab_flats.items():
            if wf.startswith(lf) and lf:
                cands.update(names)
        if len(cands) == 1:
            out.append((tid, next(iter(cands)), letters.get(tid, "")))
            expanded += 1
        else:
            out.append((tid, label, letters.get(tid, "")))
            kept += 1

    out.sort(key=lambda x: x[1].lower())

    lines = [f"{tid}|{label}|{ltr}" for tid, label, ltr in out]
    block = ("-- BEGIN_TAG_INDEX (auto-generated — do not edit)\n"
             + "\n".join(lines)
             + "\n-- END_TAG_INDEX")

    print(f"raw entries : {len(raw)}")
    print(f"unique tags : {len(out)}")
    print(f"expanded    : {expanded} (full names via WTR-Lab cross-reference)")
    print(f"site labels : {kept}")
    print(f"letters     : {len(set(ltr for _, _, ltr in out))}")

    if DRY:
        print("dry run — plugin not modified")
        return

    src = open(PLUGIN, encoding="utf-8").read()
    new_src, n = re.subn(
        r"-- BEGIN_TAG_INDEX \(auto-generated — do not edit\).*?-- END_TAG_INDEX",
        lambda m: block,
        src, count=1, flags=re.S)
    if n != 1:
        sys.exit("TAG_INDEX markers not found in plugin!")
    open(PLUGIN, "w", encoding="utf-8").write(new_src)
    print(f"spliced into {PLUGIN} ({len(lines)} tags)")


if __name__ == "__main__":
    main()
