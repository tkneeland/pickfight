#!/usr/bin/env python3
"""Summarise the relay's anonymous match telemetry (issue #372).

Usage: tools/summarise_stats.py PATH_TO_JSONL

Each line is one match: {"t": hour, "mode", "format", "length_sec", "stages",
"winner_weapon", "weapons": {id: {"damage", "hits", "kos"}}}. Prints per-weapon
damage per hit, win rate by weapon (matches won with it / completed matches it landed
a hit in), mode popularity and the average match length. A match the host
abandoned (#643) has "completed": false and "rounds_played" and no winner
weapon; a record without "completed" counts as completed. Completed and
abandoned matches are counted separately, and abandoned ones still count toward
damage and hits. An Online match (#1195) may carry "ping": per remote seat
{"avg", "p95", "max", "n", "felt", "host_leg"} in ms (-1 not measured); their
means are printed last. Bad lines are skipped.
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
    appeared_completed = Counter()
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
            if rec.get("completed") is not False:
                appeared_completed[weapon] += 1
        if rec.get("winner_weapon"):
            wins[rec["winner_weapon"]] += 1
    return damage, hits, kos, appeared, appeared_completed, wins, modes, lengths


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    records = load(argv[1])
    if not records:
        print("No records.")
        return 0
    damage, hits, kos, appeared, appeared_completed, wins, modes, lengths = summarise(records)
    abandoned = sum(1 for rec in records if rec.get("completed") is False)
    print("Matches: %d (completed %d, abandoned %d)" % (len(records), len(records) - abandoned, abandoned))
    print("Average match length: %.0f s" % (sum(lengths) / len(lengths) if lengths else 0))
    print("\nWeapon        dmg/hit   hits    KOs  win rate (wins/matches)")
    for weapon in sorted(appeared, key=lambda w: -hits[w]):
        per_hit = damage[weapon] / hits[weapon] if hits[weapon] else 0.0
        rate = 100.0 * wins[weapon] / appeared_completed[weapon] if appeared_completed[weapon] else 0.0
        print("%-12s %8.1f %6d %6d  %5.1f%% (%d/%d)" % (weapon, per_hit, hits[weapon], kos[weapon], rate, wins[weapon], appeared_completed[weapon]))
    print("\nMode popularity")
    for mode, count in modes.most_common():
        print("%-18s %4d  %5.1f%%" % (mode, count, 100.0 * count / len(records)))
    print_ping(records)
    return 0


PING_FIELDS = ("avg", "p95", "max", "felt", "host_leg")


def ping_summary(records):
    """Issue #1195: the ping fields of each remote seat over every record with a
    "ping" list; -1 (not measured) values are left out. avg and p95 are means
    weighted by the seat's sample count "n" (an entry without a usable n counts
    once; the p95 mean is not a true pooled p95); max is the largest max; felt is
    an unweighted mean per seat; host_leg is one value per record (every seat of a
    record shares the host's leg), averaged over records. Returns
    (seats, {field: value or None})."""
    weighted = defaultdict(list)  # field -> [(value, weight)]
    plain = defaultdict(list)  # field -> [value]
    seats = 0
    for rec in records:
        entries = rec.get("ping")
        if not isinstance(entries, list):
            continue
        leg_seen = False
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            seats += 1
            weight = entry.get("n")
            if not isinstance(weight, (int, float)) or weight < 1:
                weight = 1
            for field in ("avg", "p95"):
                value = entry.get(field)
                if isinstance(value, (int, float)) and value >= 0:
                    weighted[field].append((value, weight))
            value = entry.get("max")
            if isinstance(value, (int, float)) and value >= 0:
                plain["max"].append(value)
            value = entry.get("felt")
            if isinstance(value, (int, float)) and value >= 0:
                plain["felt"].append(value)
            value = entry.get("host_leg")
            if not leg_seen and isinstance(value, (int, float)) and value >= 0:
                plain["host_leg"].append(value)
                leg_seen = True

    def combine(field):
        if field in ("avg", "p95"):
            pairs = weighted[field]
            return sum(v * w for v, w in pairs) / sum(w for _, w in pairs) if pairs else None
        values = plain[field]
        if not values:
            return None
        return max(values) if field == "max" else sum(values) / len(values)

    return seats, {f: combine(f) for f in PING_FIELDS}


def print_ping(records):
    seats, means = ping_summary(records)
    if not seats:
        return
    shown = ["%.0f" % means[f] if means[f] is not None else "-" for f in PING_FIELDS]
    print("\nOnline ping (remote seats): %d seats" % seats)
    print("avg (n-weighted) / p95 (n-weighted mean) / max (largest) / felt / host leg (ms): %s" % " / ".join(shown))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
