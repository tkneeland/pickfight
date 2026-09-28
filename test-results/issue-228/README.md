# Issue #228: test evidence

- **What ran:** the full scenario list (268 scenarios) in 5 parallel shards of
  `tools/scenario_runner.gd --scenarios=...` under `--fixed-fps 60`, then a
  fresh-clone headless boot. The full log is in `full-suite.txt`.
- **Base:** branch `feat/issue-228-flail-climb`, rebased onto main `cf506b1`.
- **Result:** 268 passed, 0 failed, 268 total. The fresh-clone boot printed
  no ERROR lines.
- **New scenario:** `flail_climbs_with_the_roster`. It fails on main's
  `flail.tres` (ratio 0.73) and passes with this branch's (ratio 0.92).
