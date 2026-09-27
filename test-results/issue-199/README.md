# Issue #199 test evidence

- **What was run:** the full scenario list (243 scenarios) via `tools/scenario_runner.gd` under `--headless --fixed-fps 60`, split into 5 parallel `--scenarios=` shards (Godot 4.6.2, Windows 11), plus a fresh-clone `--quit` boot check.
- **Base:** branch `feat/issue-199-stage-fixes` on origin/main `6d4ec9d` (rebased past #200's seeded spawn rotation; the balance check still holds since rotation only permutes the first N spawns among N players).
- **Result:** 243 passed, 0 failed, 243 total. Full log: `full-suite.txt`.
- **Before/after:** the two new scenarios (`crumbling_ledge_retriggers_on_reform`, `stage_spawns_balanced_left_right`) were also run against main's `scripts/CrumblingLedge.gd` and `scenes/stages/Islands.tscn` and both FAILED there (ledge stayed solid under a camper; Islands split 3/1 for four and 5/3 for eight).
- **Boot:** the only ERROR on a fresh clone is qrencode "Could not create child process" -- qrencode isn't installed on this machine (environment only).
