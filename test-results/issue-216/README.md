# Issue #216: evidence

- **What was run:** the full scenario list (260 scenarios), split across 5 parallel headless shards under `--fixed-fps 60`, followed by a fresh-clone boot check. The full output is in `full-suite.txt`.
- **Base:** main `4f51b61`. The branch started on `546f9b7`, and main moved while the work was in progress, so it was rebased and the suite was run again on the new base.
- **Result:** 260 passed, 0 failed, 260 total.
- **Fresh-clone boot:** the only ERROR is qrencode "Could not create child process". It comes from this machine, not the project: qrencode isn't on PATH here.
- **New scenario:** `settings_toggle_clicks_mid_round`. It passes on this branch and fails on main's `SfxSettings.gd`. On main, a mouse-catching Control above the menu swallows the click.
