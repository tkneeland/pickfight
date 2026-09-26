# Issue #187: one match seed for every gameplay RNG

Run on branch `feat/issue-187-match-seed`, based on main `33cb339`.

## Full suite

`full-suite.txt`: every scenario in `SCENARIO_NAMES`, run as 5 parallel shards of
`--scenarios=` under `--fixed-fps 60`.

Result: **220 passed, 0 failed, 220 total**.

The fresh-clone boot check (`godot --headless --path <clone> --quit`) prints one
ERROR, qrencode "Could not create child process". That is environment-only: this
machine has no `qrencode` on PATH.

## New scenario: `match_seed_replays_bot_match`

It runs the same short bot match twice on seed 187187: `--bots=3` on Flatlands,
Meteor Shower forced, pickups every 3 s and a quick lava. The global RNG is
stirred before each run. Both runs must give the same KO order, KO ticks within
30, positions within 48 px at every 30-tick sample, and the same bot seeds,
pickups and meteors. It also checks `--seed=N` parsing, and that the derived
streams repeat per seed and differ per subsystem.

- It passed 3 times run on its own, and once more in the full suite. Every run
  gave KOs `[[0, 335], [2, 382]]` both times, with a worst position gap of
  0.05 to 0.07 px.
- Against main's gameplay scripts, it fails. The main scripts were checked out
  over the branch, and the scenario was edited to set `match_seed` duck-typed
  and skip the unit checks. Result: KO order `[[2, 355], [0, 355]]` then
  `[[2, 354], [1, 370]]`, different bot seeds, pickups and meteors, and a
  356.7 px worst gap.

The positions need a tolerance because Godot's physics solver is not bit-exact
between two copies of a scene in one process. The runs agree exactly until the
first contact between two players (around tick 40). After that they differ by
float rounding.

`test-results/issue-176/` is still here. The permission policy blocked `git rm`
of it, so it was left in place.
