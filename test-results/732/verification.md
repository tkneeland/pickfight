# #732 verification

Branch `feat/issue-732`, final commit on top of fe4eba7 (join-path masking added in `_fresh_claim`).

| Check | Command | Result |
|---|---|---|
| Targeted | `godot --headless --fixed-fps 60 --path . -s tools/scenario_runner.gd -- name_filter_732` | PASS |
| Full suite (after merging main) | `godot --headless --fixed-fps 60 --path . -s tools/scenario_runner.gd -- --all` | 910 passed, 1 failed (`axe_wins_clash_against_every_weapon`, known macOS-only, unrelated) |
| Fresh clone | clone + `godot --headless --quit` grep for script errors | no output (clean) |

Coverage: both name intake paths are masked when "Filter player names" is on — the `"name"` frame and the nickname sent with a claim (phone join, Online client join). A returning leaver's stored name was already masked on intake.

Not done: no masked-name echo to the phone; the controller has no name echo path, so the phone shows what the player typed while the shared screen shows the masked name.
