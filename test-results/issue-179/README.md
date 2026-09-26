# Issue #179 test evidence

Branch `fix/issue-179-harness-static-reset` on main `e91ab17`, run on Windows 11 with Godot 4.6.2 headless. The checkout has CRLF line endings (`core.autocrlf=true`).

| Run | Command | Result |
| --- | --- | --- |
| Serial | one process, `-s tools/scenario_runner.gd -- --all` (1309 s) | **217 passed, 0 failed, 217 total**, exit 0 ([full-suite-serial.txt](full-suite-serial.txt)) |
| Sharded | `shard.sh 179 5`: 5 parallel `--scenarios=` processes, round-robin | **217 passed, 0 failed, 217 total** ([full-suite.txt](full-suite.txt)) |

Before this fix, two scenarios failed in the serial Windows run. Both pass now:

- `round_modifier_double_damage_applies_and_undoes` failed because `modifier_rolls_enabled` leaked from earlier scenarios.
- `controller_page_look_picker_after_name` failed on the CRLF checkout.

The new pair `harness_static_left_flipped` and `harness_static_restored_for_next_scenario` fails when the `_restore_statics()` call in `_run_one()` is disabled. It then reports that `modifier_rolls_enabled` and `BotDirector.extra_args` leaked. With the call restored, the pair passes.

Fresh-clone boot check: the only ERROR is qrencode "Could not create child process". It is environment-only, because qrencode is not installed on this machine. The same line appears for each scenario that brings up the join QR.
