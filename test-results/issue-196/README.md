# Issue #196 evidence

Three new scenarios, at the end of `SCENARIO_NAMES`:

| Scenario | Checks |
|---|---|
| `juice_trail_draws_every_swing` | Three short swings in a row, each shorter than `TRAIL_POINTS` frames, each leave a full trail (item 1) |
| `settings_esc_mid_drag_saves` | Esc closing the settings panel mid-drag saves the dragged value and ends the drag (item 2) |
| `hat_parts_stay_in_their_box` | Every hat part, stroke included, stays under its `HEIGHTS` entry and within `HALF_WIDTH`, and each entry is within 2 px of the drawn top (item 3) |

- `new-scenarios-without-fix.txt`: the three run with `scripts/Juice.gd`, `scripts/SfxSettings.gd` and `scripts/Hat.gd` reverted to `origin/main`. All three FAIL; the trail lengths per swing are `[5, 2, 0]`.
- `new-scenarios-with-fix.txt`: the same run on this branch. All three PASS; the trail lengths per swing are `[5, 5, 5]`.
- `full-suite.txt`: the whole suite on this branch, in 4 contiguous shards under `--fixed-fps 60`.

Command: `godot --headless --fixed-fps 60 --path . -s tools/scenario_runner.gd -- --scenarios=juice_trail_draws_every_swing,settings_esc_mid_drag_saves,hat_parts_stay_in_their_box`
