# Proof of work -- issue #22, rising kill zone

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. #20's evidence is in
history at `2d1a18e:test-results/issue-20/`.

Branch `feat/issue-22-rising-kill-zone`, macOS, local Godot 4.6.2.

| Criterion (issue #22 decision) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| The floor kill zone holds still through the grace period | `kill_zone_holds_during_grace` | `issue-22/scenario-suite.txt` | PASS |
| Then rises steadily at the derived per-stage rate | `kill_zone_rises_after_grace` | `issue-22/scenario-suite.txt` | PASS |
| A holdout on the highest spawn is eventually eliminated (Flatlands and Cascade, short test timings) | `rising_kill_zone_eliminates_holdout` | `issue-22/scenario-suite.txt` | PASS |
| Hazard parts never rise (Furnace and Gauntlet) | `hazard_never_rises` | `issue-22/scenario-suite.txt` | PASS |
| Every round starts fresh | `rising_kill_zone_resets_each_round` | `issue-22/scenario-suite.txt` | PASS |
| Ring-out still means "before the mechanic": the rise never starts outside a round | `every_stage_can_ring_out` unchanged | `issue-22/scenario-suite.txt` | PASS |
| Nothing else regressed | full suite, 64 of 65 after the rebase onto #20 | `issue-22/scenario-suite.txt` | PASS, except the one pre-existing macOS failure `roster_heads_do_not_tunnel_head_reversed`, which also fails on clean main (#38) |
| Boots on a fresh clone | `git clone` of the branch, `godot --headless --path <clone> --quit`, grep for `SCRIPT ERROR` / `Failed to load script` | `issue-22/boot-check.txt` | PASS |

The visible surface and its pulsing warning have no screenshot yet. A
windowed playtest is the check for those.
