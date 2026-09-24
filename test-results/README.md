# Issue #8 evidence — stage rotation

Cleared and recaptured in full per the evidence policy in
`docs/agents/testing.md`: this root holds only the latest work package's
evidence. Captured on `feat/issue-8-stage-rotation`, local headless
Godot 4.6.2.2 (`Godot_v4.6.2-stable_win64_console.exe`), the only run surface
this project has.

| Criterion (issue #8 Outcome) | Proven by | Evidence |
| --- | --- | --- |
| At least 3 stages with distinct geometry | `scenes/stages/{Flatlands,Highrise,Gauntlet}.tscn` (reviewed in the PR diff) | boot-check.log parses all three cleanly |
| Every new round swaps in the next stage | `stage_rotates_each_round` | `issue-8/scenario-stage_rotates_each_round.log`, `issue-8/scenario-all.log` |
| Each stage declares its own spawns and death boundary; RoundManager reads them | `stage_rotates_each_round` (rotation identity) + `stage_spawns_are_safe` (spawn safety per real stage) | `issue-8/scenario-stage_spawns_are_safe.log`, `issue-8/scenario-all.log` |
| Headless coverage: stage swap between rounds; spawns land on solid ground and survive 60 ticks idle | both new scenarios above | same two files |
| No regressions in existing combat/physics suite | `--all`, 24/24 (21 pre-existing + the 2 new + none removed) | `issue-8/scenario-all.log` |
| Project boots clean | `godot --headless --path . --quit` | `issue-8/boot-check.log` |

All 24 scenarios + boot-check: **PASS**.

Notes:

- This checkout has no `.godot/` directory at all (never opened in the
  editor), so every run above was already a fresh-clone run in the sense
  CLAUDE.md's `class_name` rule cares about — there was no global class cache
  to strip. Confirmed by `ls .godot` finding nothing. No separate
  fresh-clone log is included; `boot-check.log` and `scenario-all.log` are
  that check.
- `scenes/Arena.tscn` and its ~20 dependent scenarios (`aim_angle` through
  `weapon_silhouette_matches_head_shape`) are unchanged by this work — see
  ADR-0008 for why the stage roster deliberately doesn't reuse that fixture.
- No human-gated criteria captured here: the issue's outcomes are all
  headless-observable. A live two-phone smoke test (stage visibly changes
  each round) is optional and wasn't run in this pass.
