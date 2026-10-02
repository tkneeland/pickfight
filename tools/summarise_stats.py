#!/usr/bin/env python3
"""Summarise the relay's anonymous match telemetry (issue #372).

Usage: tools/summarise_stats.py PATH_TO_JSONL

Each line is one match: {"t": hour, "mode", "format", "length_sec", "stages",
"winner_weapon", "weapons": {id: {"damage", "hits", "kos"}}}. Prints per-weapon
damage per hit, win rate by weapon (matches won with it / matches it landed a
hit in), mode popularity and the average match length. Bad lines are skipped.
"""
import json
import sys
from collections import Counter, defaultdict


def load(path):
    records = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except ValueError:
                continue
            if isinstance(record, dict) and isinstance(record.get("weapons"), dict):
                records.append(record)
    return records


def summarise(records):
    damage = defaultdict(float)
    hits = Counter()
    kos = Counter()
    appeared = Counter()
    wins = Counter()
    modes = Counter()
    lengths = []
    for rec in records:
        modes[rec.get("mode") or "classic"] += 1
        if isinstance(rec.get("length_sec"), (int, float)):
            lengths.append(rec["length_sec"])
        for weapon, row in rec["weapons"].items():
            damage[weapon] += float(row.get("damage", 0))
            hits[weapon] += int(row.get("hits", 0))
            kos[weapon] += int(row.get("kos", 0))
            appeared[weapon] += 1
        if rec.get("winner_weapon"):
            wins[rec["winner_weapon"]] += 1
    return damage, hits, kos, appeared, wins, modes, lengths


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    records = load(argv[1])
    if not records:
        print("No records.")
        return 0
    damage, hits, kos, appeared, wins, modes, lengths = summarise(records)
    print("Matches: %d" % len(records))
    print("Average match length: %.0f s" % (sum(lengths) / len(lengths) if lengths else 0))
    print("\nWeapon        dmg/hit   hits    KOs  win rate (wins/matches)")
    for weapon in sorted(appeared, key=lambda w: -hits[w]):
        per_hit = damage[weapon] / hits[weapon] if hits[weapon] else 0.0
        rate = 100.0 * wins[weapon] / appeared[weapon]
        print("%-12s %8.1f %6d %6d  %5.1f%% (%d/%d)" % (weapon, per_hit, hits[weapon], kos[weapon], rate, wins[weapon], appeared[weapon]))
    print("\nMode popularity")
    for mode, count in modes.most_common():
        print("%-18s %4d  %5.1f%%" % (mode, count, 100.0 * count / len(records)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
