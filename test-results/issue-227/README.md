# Issue #227 evidence

On main `56606fd` plus this branch's fix (Windows 11, Godot 4.6.2, `--fixed-fps 60`):

- Full suite, 5 parallel `--scenarios=` shards: **267 passed, 0 failed, 267 total** (`full-suite.txt`).
- Fresh-clone boot (`godot --headless --quit`): no ERROR lines.

## Failure rate of `bots_flag_fills_lobby_and_bots_fight`

| Run | Before (random match seed) | After (seed 152) |
|---|---|---|
| Scenario alone, 400 runs (8 processes x 50 repeats) | **4 failed** / 400 (seeds 3914890213, 2512663666, 4211818755, 2193658755; each fails again when replayed alone) | **0 failed** / 400, every run identical (first strike after 3.3 s) |
| CI shard 2/4 list (`tools/list_scenarios.sh 2 4`, cut at the scenario), 48 runs | 0 failed / 48 | - |
| CI shard 2/4 full list, 24 runs + 4 runs in reverse order | - | 0 failed / 28 |

The failing seeds show all three pickaxe bots heading for the two platform
pickups for the whole 40 s and never meeting each other: no strike at all.
Nothing depends on scenario order or on the #226 demos (the CI failure, run
36373863339 on #220's merge `546f9b7`, predates #226).
