#!/usr/bin/env python3
"""Headless bot-vs-bot balance sweep (issue #404). REPORT ONLY: changes no stats.

One command reruns the sweep and regenerates the report:

    python3 tools/balance_sweep.py                  # full profile, ~35-45 min on a 12-core Mac
    python3 tools/balance_sweep.py --profile quick  # smoke run, a few minutes
    python3 tools/balance_sweep.py --analyse-only   # rebuild the report from the raw JSONL

Each job is one `godot --headless ... -s tools/balance_probe.gd` process: the
real game scene with bots on fixed weapons for R rounds (see the probe's
header). Jobs run in parallel. Raw per-run records go to
docs/balance/bot-sweep-<date>-runs.jsonl, tables to sibling CSVs, and the
write-up to docs/balance/bot-sweep-<date>.md.
"""
import argparse
import csv
import itertools
import json
import math
import os
import random
import subprocess
import sys
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROFILES = {
    # 1v1: every unordered pair, `runs` processes of `rounds` rounds each.
    # FFA: `ffa_runs` four-bot matches per mode on a balanced random lineup.
    "full": {"runs_1v1": 2, "rounds_1v1": 5, "ffa_runs": 30, "ffa_rounds": 6},
    "quick": {"runs_1v1": 1, "rounds_1v1": 2, "ffa_runs": 4, "ffa_rounds": 3},
}
FFA_MODES = ["classic", "king_of_the_hill", "hot_potato", "stock"]
WALL_LIMIT_SEC = 900


def weapons_list():
    d = os.path.join(ROOT, "resources")
    return sorted(f[:-5] for f in os.listdir(d) if f.endswith(".tres") and not f.startswith("_"))


def build_jobs(profile, seed0):
    ws = weapons_list()
    jobs = []
    for a, b in itertools.combinations(ws, 2):
        for r in range(profile["runs_1v1"]):
            jobs.append({"format": "1v1", "mode": "classic", "weapons": [a, b],
                         "rounds": profile["rounds_1v1"], "seed": seed0 + len(jobs)})
    rng = random.Random(seed0)
    for mode in FFA_MODES:
        deck = []
        for r in range(profile["ffa_runs"]):
            lineup = []
            while len(lineup) < 4:  # a shuffled deck keeps every weapon equally used
                if not deck:
                    deck = ws[:]
                    rng.shuffle(deck)
                w = deck.pop()
                if w not in lineup:
                    lineup.append(w)
            jobs.append({"format": "ffa4", "mode": mode, "weapons": lineup,
                         "rounds": profile["ffa_rounds"], "seed": seed0 + len(jobs)})
    return jobs


def run_job(job, godot):
    cmd = ["perl", "-e", "alarm %d; exec @ARGV" % WALL_LIMIT_SEC, godot, "--headless",
           "--path", ROOT, "--fixed-fps", "60", "-s", "tools/balance_probe.gd", "--",
           "--weapons=" + ",".join(job["weapons"]), "--mode=" + job["mode"],
           "--rounds=%d" % job["rounds"], "--seed=%d" % job["seed"],
           "--bots=%d" % len(job["weapons"])]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    for line in out.splitlines():
        if line.startswith("BALANCE {"):
            rec = json.loads(line[len("BALANCE "):])
            rec["format"] = job["format"]
            return rec
    return None


def wilson(k, n, z=1.96):
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = p + z * z / (2 * n)
    m = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return ((c - m) / d, (c + m) / d)


def pct(x):
    return "%.1f%%" % (100 * x)


class Tally:
    def __init__(self):
        self.score = 0.0   # wins, draws count half (1v1) / zero (ffa)
        self.rounds = 0
        self.damage = 0.0
        self.hits = 0
        self.kos = 0
        self.self_kos = 0
        self.deaths = 0
        self.sec = 0.0
        self.first_elim = []

    def ci(self):
        return wilson(self.score, self.rounds)

    def rate(self):
        return self.score / self.rounds if self.rounds else 0.0


def analyse(records):
    one = defaultdict(Tally)       # weapon -> tally (1v1)
    ffa = defaultdict(lambda: defaultdict(Tally))  # mode -> weapon -> tally
    pair = defaultdict(lambda: [0.0, 0])  # (a, b) -> [a's score, rounds]
    cell = defaultdict(lambda: defaultdict(lambda: [0.0, 0]))  # (fmt, weapon) -> stage -> [score, n]
    stage_len = defaultdict(list)
    runs = defaultdict(int)
    for rec in records:
        fmt, mode = rec["format"], rec["mode"]
        runs[(fmt, mode)] += 1
        n = len(rec["weapons"])
        for rnd in rec["rounds"]:
            stage_len[rnd["stage"]].append(rnd["sec"])
        for s in rec["slots"]:
            w = s["weapon"]
            t = one[w] if fmt == "1v1" else ffa[mode][w]
            t.rounds += len(rec["rounds"])
            t.damage += s["damage"]
            t.hits += s["hits"]
            t.kos += s["kos"]
            t.self_kos += s["self_kos"]
            t.deaths += s["deaths"]
            t.sec += rec["round_seconds"]
            for rnd in rec["rounds"]:
                win = rnd["winner"] == s["slot"]
                draw = rnd["winner"] == -1
                score = 1.0 if win else (0.5 if (draw and fmt == "1v1") else 0.0)
                t.score += score
                if rnd["first_elim_sec"] >= 0:
                    t.first_elim.append(rnd["first_elim_sec"])
                c = cell[(fmt, w)][rnd["stage"]]
                c[0] += score
                c[1] += 1
                if fmt == "1v1":
                    other = rec["weapons"][1 - s["slot"]]
                    p = pair[(w, other)]
                    p[0] += score
                    p[1] += 1
    return one, ffa, pair, cell, stage_len, runs


def write_csvs(base, one, ffa, pair, cell):
    def row(w, t, fmt, mode):
        lo, hi = t.ci()
        return [fmt, mode, w, t.rounds, "%.4f" % t.rate(), "%.4f" % lo, "%.4f" % hi,
                "%.2f" % (t.damage / t.hits if t.hits else 0), "%.2f" % (t.hits / (t.sec / 60) if t.sec else 0),
                t.kos, t.self_kos, t.deaths,
                "%.1f" % (sum(t.first_elim) / len(t.first_elim) if t.first_elim else -1)]
    with open(base + "-weapons.csv", "w", newline="") as f:
        cw = csv.writer(f)
        cw.writerow(["format", "mode", "weapon", "rounds", "win_rate", "ci_lo", "ci_hi", "damage_per_hit",
                     "hits_per_min", "kos", "self_kos", "deaths", "avg_first_elim_sec"])
        for w in sorted(one):
            cw.writerow(row(w, one[w], "1v1", "classic"))
        for mode in ffa:
            for w in sorted(ffa[mode]):
                cw.writerow(row(w, ffa[mode][w], "ffa4", mode))
    with open(base + "-matrix-1v1.csv", "w", newline="") as f:
        cw = csv.writer(f)
        cw.writerow(["weapon", "opponent", "rounds", "score", "win_rate"])
        for (a, b), (s, n) in sorted(pair.items()):
            cw.writerow([a, b, n, s, "%.4f" % (s / n)])
    with open(base + "-weapon-stage.csv", "w", newline="") as f:
        cw = csv.writer(f)
        cw.writerow(["format", "weapon", "stage", "rounds", "score", "win_rate"])
        for (fmt, w), stages in sorted(cell.items()):
            for st, (s, n) in sorted(stages.items()):
                cw.writerow([fmt, w, st, n, s, "%.4f" % (s / n)])


def table(rows, t_by_w, baseline):
    out = ["| Weapon | Rounds | Win rate | 95% CI | Dmg/hit | Hits/min | KOs/round | Self-KOs/round | Avg first elim (s) |",
           "|---|---:|---:|---|---:|---:|---:|---:|---:|"]
    for w in rows:
        t = t_by_w[w]
        lo, hi = t.ci()
        flag = " (above)" if lo > baseline else (" (below)" if hi < baseline else "")
        # each round is counted once per slot; KOs/round is per this weapon's own slot-rounds
        out.append("| %s | %d | %s | %s-%s%s | %.1f | %.1f | %.2f | %.2f | %s |" % (
            w, t.rounds, pct(t.rate()), pct(lo), pct(hi), flag,
            t.damage / t.hits if t.hits else 0, t.hits / (t.sec / 60) if t.sec else 0,
            t.kos / t.rounds, t.self_kos / t.rounds,
            "%.1f" % (sum(t.first_elim) / len(t.first_elim)) if t.first_elim else "n/a"))
    return out


def write_report(path, date, profile_name, profile, records, one, ffa, pair, cell, stage_len, runs, wall):
    ws = sorted(one)
    stalled = set()
    for mode in FFA_MODES:
        rs = [x for r in records if r["format"] == "ffa4" and r["mode"] == mode for x in r["rounds"]]
        if rs and sum(1 for x in rs if x.get("timeout")) / len(rs) > 0.25:
            stalled.add(mode)
    L = []
    L.append("# Bot-vs-bot balance sweep, %s" % date)
    L.append("")
    L.append("**Report only.** Nothing here changes a weapon stat; the owner reads it and picks any tweaks (issue #404). "
             "A weapon that wins 1v1 is not therefore overpowered: 1v1 strength says nothing about how a weapon fares "
             "in a crowd, how hard it is for a human to use, or how much fun it is to fight against. Read the FFA tables "
             "beside the 1v1 ones, and treat every number as one bot's play, not a player's.")
    L.append("")
    L.append("## Context (read this before the numbers)")
    L.append("")
    L.append("- **Bots:** the game's own `Bot.gd`, the only skill level (\"decent\"), driven straight into `Player.set_input_vector` "
             "(no phone smoothing). Bots are seeded per run. Bots use weapons the same way for all 15 weapons; if the bot "
             "plays a weapon badly, that weapon looks weak here.")
    L.append("- **Harness:** the real `Main.tscn` + `RoundManager` (stage rotation over all stages, rising lava, modifiers off, "
             "pickups off so nobody changes weapon, a fixed weapon per slot every round), headless at `--fixed-fps 60`. "
             "Win = last one standing in a round; the unit of every sample is **one round**. Stats come from the game's "
             "`MatchStats`.")
    L.append("- **Profile:** `%s` (%s). Wall time %.0f min over %d processes." % (
        profile_name, ", ".join("%s=%s" % kv for kv in profile.items()), wall / 60, len(records)))
    n1 = sum(v for (f, m), v in runs.items() if f == "1v1")
    L.append("- **1v1 (format `1v1`, mode Classic):** every unordered pair of the %d weapons, %d processes x %d rounds each = "
             "%d rounds per pair, %d rounds total (%d runs). Mirror matches are not included. A drawn round counts half a win."
             % (len(ws), profile["runs_1v1"], profile["rounds_1v1"], profile["runs_1v1"] * profile["rounds_1v1"],
                sum(t.rounds for t in one.values()) // 2, n1))
    L.append("- **FFA (format `ffa4`):** four bots, each on a different weapon, lineups from a shuffled deck so every weapon is "
             "used about equally; %d processes x %d rounds per mode. A weapon's expected win rate in a fair 4-way is 25%%. "
             "A drawn round counts as a win for nobody." % (profile["ffa_runs"], profile["ffa_rounds"]))
    L.append("- **Confidence intervals** are Wilson 95% intervals on rounds treated as independent. Rounds inside one run "
             "share a seed and a lineup, so the true uncertainty is somewhat wider. `(above)` / `(below)` marks an interval "
             "that excludes the fair-share rate (50% in 1v1, 25% in FFA).")
    L.append("- Columns: Dmg/hit = damage dealt / landed hits; Hits/min = landed hits per minute of round time; KOs/round = "
             "kills credited to that weapon's last hit; Self-KOs = lava, ring-out and hazard deaths; first elim = seconds "
             "from round start to the first death of any cause (rounds with a death only).")
    L.append("- Raw data: `bot-sweep-%s-runs.jsonl` (one line per process), `-weapons.csv`, `-matrix-1v1.csv`, `-weapon-stage.csv`." % date)
    L.append("")
    L.append("## Read this first")
    L.append("")
    L.append("- Only **Classic** and **Hot Potato** have usable FFA samples. In %s the bots stall (no lava; the hill or the last "
             "life is never settled inside 300 s of game time), so those modes have almost no rounds. That is a bot gap, not a "
             "weapon result, and is worth a follow-up ticket if per-mode balance matters." % (" and ".join(sorted(stalled)) or "no mode"))
    L.append("- Every run's first round is Flatlands (the rotation's first stage), so Flatlands has about 4x the rounds of "
             "other stages and dominates the stage table below. Weapon-by-stage numbers beyond Flatlands are too sparse to read.")
    L.append("- Many rounds in Classic are decided by the rising lava rather than by a fight (the Self-KOs column): a weapon that "
             "moves well wins by outliving the other bot. Win rate here is partly a measure of mobility under bot control.")
    L.append("")
    L.append("## 1v1 (Classic, all pairs)")
    L.append("")
    order = sorted(ws, key=lambda w: -one[w].rate())
    L += table(order, one, 0.5)
    L.append("")
    L.append("### 1v1 matrix (row weapon's win rate against column weapon)")
    L.append("")
    L.append("Each cell is %d rounds. Read with the CI table above in mind: a single cell has a wide interval (about +/-%.0f points)."
             % (profile["runs_1v1"] * profile["rounds_1v1"], 100 * (wilson(profile["runs_1v1"] * profile["rounds_1v1"] / 2, profile["runs_1v1"] * profile["rounds_1v1"])[1] - 0.5)))
    L.append("")
    L.append("| row \\ col | " + " | ".join(w[:5] for w in order) + " |")
    L.append("|---|" + "---:|" * len(order))
    for a in order:
        cells = []
        for b in order:
            if a == b:
                cells.append("-")
            else:
                s, n = pair[(a, b)]
                cells.append("%d" % round(100 * s / n))
        L.append("| %s | %s |" % (a, " | ".join(cells)))
    L.append("")
    for mode in FFA_MODES:
        if mode not in ffa:
            continue
        L.append("## FFA, 4 bots, %s" % mode)
        L.append("")
        n_runs = runs[("ffa4", mode)]
        tos = sum(1 for r in records if r["format"] == "ffa4" and r["mode"] == mode for x in r["rounds"] if x.get("timeout"))
        L.append("%d runs, %d rounds, %d timed out (a round still going at 300 s of game time ends the run and counts as a draw)."
                 % (n_runs, sum(t.rounds for t in ffa[mode].values()) // 4, tos))
        if mode in stalled:
            L.append("**The bots do not finish rounds in this mode** (more than a quarter of rounds hit the 300 s cap, and each "
                     "such run stops there, so few rounds were played). Treat this table as noise; it says the bots cannot play "
                     "%s, not anything about the weapons. It is left out of the pooled FFA table." % mode)
        L.append("")
        o = sorted(ffa[mode], key=lambda w: -ffa[mode][w].rate())
        L += table(o, ffa[mode], 0.25)
        L.append("")
    # all-modes FFA pooled
    pooled = defaultdict(Tally)
    for mode in ffa:
        if mode in stalled:
            continue
        for w, t in ffa[mode].items():
            p = pooled[w]
            p.score += t.score; p.rounds += t.rounds; p.damage += t.damage; p.hits += t.hits
            p.kos += t.kos; p.self_kos += t.self_kos; p.deaths += t.deaths; p.sec += t.sec
            p.first_elim += t.first_elim
    if pooled:
        L.append("## FFA, 4 bots, pooled over the modes the bots can finish (%s)" % ", ".join(m for m in FFA_MODES if m in ffa and m not in stalled))
        L.append("")
        o = sorted(pooled, key=lambda w: -pooled[w].rate())
        L += table(o, pooled, 0.25)
        L.append("")
        L.append("### 1v1 versus FFA rank")
        L.append("")
        L.append("| Weapon | 1v1 win rate | 1v1 rank | FFA (pooled) win rate | FFA rank |")
        L.append("|---|---:|---:|---:|---:|")
        r1 = {w: i + 1 for i, w in enumerate(order)}
        rf = {w: i + 1 for i, w in enumerate(o)}
        for w in order:
            L.append("| %s | %s | %d | %s | %d |" % (w, pct(one[w].rate()), r1[w], pct(pooled[w].rate()) if w in pooled else "n/a", rf.get(w, 0)))
        L.append("")
        L.append("A weapon that ranks high in 1v1 but low in FFA (or the reverse) is the interesting case: it wins duels but "
                 "gets picked off by a third party, or it needs the crowd. A big rank gap is a prompt to look, not a verdict.")
        L.append("")
    L.append("## Stages")
    L.append("")
    L.append("Rounds are spread over every stage by the rotation, so each weapon-by-stage cell is small (a handful of rounds). "
             "The full table is in `-weapon-stage.csv`. Cells below have at least 10 rounds and a Wilson interval excluding the fair-share rate:")
    L.append("")
    notable = []
    for (fmt, w), stages in cell.items():
        base = 0.5 if fmt == "1v1" else 0.25
        for st, (s, n) in stages.items():
            if n >= 10:
                lo, hi = wilson(s, n)
                if lo > base or hi < base:
                    notable.append((fmt, w, st, n, s / n, lo, hi))
    if notable:
        L.append("| Format | Weapon | Stage | Rounds | Win rate | 95% CI |")
        L.append("|---|---|---|---:|---:|---|")
        for fmt, w, st, n, r, lo, hi in sorted(notable, key=lambda x: -abs(x[4] - (0.5 if x[0] == "1v1" else 0.25)))[:25]:
            L.append("| %s | %s | %s | %d | %s | %s-%s |" % (fmt, w, st, n, pct(r), pct(lo), pct(hi)))
    else:
        L.append("None: no weapon-by-stage cell has enough rounds to say anything. Rerun a larger profile to look at stages.")
    L.append("")
    L.append("Stages by average round length (seconds, all formats; short = a lot of early KOs, long = the lava decides):")
    L.append("")
    L.append("| Stage | Rounds | Avg round (s) |")
    L.append("|---|---:|---:|")
    for st in sorted(stage_len, key=lambda s: sum(stage_len[s]) / len(stage_len[s])):
        v = stage_len[st]
        L.append("| %s | %d | %.1f |" % (st, len(v), sum(v) / len(v)))
    L.append("")
    L.append("## Telemetry stayed off")
    L.append("")
    allowed = [r for r in records if r.get("telemetry_send_allowed")]
    senders = sum(r.get("telemetry_stats_sender_nodes", 0) for r in records)
    L.append("Every probe run asks `StatsSender.should_send` with and without `--bots`, calls `RoundManager.send_telemetry()` "
             "and counts `StatsSender` nodes in the tree, then records the answers in the raw JSONL. Across the %d runs: "
             "**%d** reported a send as allowed, **%d** `StatsSender` nodes were ever created. `should_send` is false for any "
             "`-s` script run (`StatsSender.is_scripted`) and for `--bots`; the sweep is both." % (len(records), len(allowed), senders))
    L.append("")
    L.append("## Rerun")
    L.append("")
    L.append("```")
    L.append("python3 tools/balance_sweep.py --profile %s --date %s" % (profile_name, date))
    L.append("```")
    L.append("")
    with open(path, "w") as f:
        f.write("\n".join(L))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", default="full", choices=sorted(PROFILES))
    ap.add_argument("--workers", type=int, default=max(1, (os.cpu_count() or 4) - 1))
    ap.add_argument("--date", default=time.strftime("%Y-%m-%d"))
    ap.add_argument("--seed", type=int, default=404)
    ap.add_argument("--godot", default="godot")
    ap.add_argument("--out", default=os.path.join(ROOT, "docs", "balance"))
    ap.add_argument("--analyse-only", action="store_true")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    base = os.path.join(args.out, "bot-sweep-" + args.date)
    raw = base + "-runs.jsonl"
    profile = PROFILES[args.profile]
    t0 = time.time()
    if not args.analyse_only:
        jobs = build_jobs(profile, args.seed)
        print("%d jobs on %d workers" % (len(jobs), args.workers), flush=True)
        failed = 0
        with open(raw, "w") as out, ThreadPoolExecutor(args.workers) as pool:
            futs = [pool.submit(run_job, j, args.godot) for j in jobs]
            for i, fut in enumerate(as_completed(futs), 1):
                rec = fut.result()
                if rec is None:
                    failed += 1
                else:
                    out.write(json.dumps(rec, sort_keys=True) + "\n")
                    out.flush()
                if i % 10 == 0 or i == len(jobs):
                    print("  %d/%d done (%d failed) %.0fs" % (i, len(jobs), failed, time.time() - t0), flush=True)
    records = [json.loads(l) for l in open(raw) if l.strip()]
    wall = time.time() - t0
    one, ffa, pair, cell, stage_len, runs = analyse(records)
    write_csvs(base, one, ffa, pair, cell)
    write_report(base + ".md", args.date, args.profile, profile, records, one, ffa, pair, cell, stage_len, runs, wall)
    print("wrote", base + ".md")


if __name__ == "__main__":
    sys.exit(main())
