#!/usr/bin/env python3
"""Emit the Phase A results as a CSV alongside the markdown report."""
import csv
import os

rows = [
    # phase, sample, mode, raw_id, chapter, body_kind, outcome, char_count, sample_text
    ("A_offline", "enc_raw_2_1_web.json", "web", "2", 1, "arr:string (13834B)",
     "SUCCESS_DECRYPTED", 3545,
     "《东都赋》有云：四海之内，学校如林，庠序盈门。这句话说的是元朔国的教育盛况。自元帝以来，元朔国便在全国上下设立官学…"),
    ("A_offline", "enc_raw_93574_1_web.json", "web", "93574", 1, "arr:string (8762B)",
     "SUCCESS_DECRYPTED", 2330,
     "（老作者、纯手打、无ai，放心观看）… 漫威、纽约、正午。"),
    ("A_offline", "enc_raw_93618_1_web.json", "web", "93618", 1, "arr:string (9034B)",
     "SUCCESS_DECRYPTED", 2345,
     "混沌，紫霄宫。\"通天！你截教门下尽是些披毛戴角、湿生卵化之辈，不识天数，不明大道！\""),
    ("A_offline", "enc_webplus.json", "webplus", "2", 10, "arr:string (10978B)",
     "SUCCESS_DECRYPTED", 2815,
     "云海苍茫，渺渺无尽。白云苍狗，变化莫测。云海之中，一座座仙山高台漂浮在其中…"),
    ("A_offline", "reader1.json", "ai", "93618", 1, "array of 96 paragraphs",
     "SUCCESS_PLAIN", 2345,
     "混沌，紫霄宫。\"通天！你截教门下尽是些披毛戴角、湿生卵化之辈，不识天数，不明大道！\""),
    # Phase B live probe results
    ("B_live", "ai ch1", "ai", "93618", 1, "n/a",
     "TURNSTILE_BLOCKED", 0, "count=100, threshold=15; 'Please complete the Turnstile challenge to continue reading'"),
    ("B_live", "web ch1", "web", "93618", 1, "n/a",
     "TURNSTILE_BLOCKED", 0, "count=101, threshold=15"),
    ("B_live", "webplus ch1", "webplus", "93618", 1, "n/a",
     "TURNSTILE_BLOCKED", 0, "count=70, threshold=15"),
]

csv_path = "/home/z/my-project/download/wtrlab_50ch_test.csv"
with open(csv_path, "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f)
    w.writerow(["phase", "sample", "mode", "raw_id", "chapter",
                "body_kind", "outcome", "char_count", "sample_text"])
    for r in rows:
        w.writerow(r)
print(f"Wrote {len(rows)} rows to {csv_path}")
