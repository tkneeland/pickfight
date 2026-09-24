# Proof of work -- issue #14, weapon pickups

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. #29's evidence is in
history at `b5c9d36:test-results/issue-29/`.

Built on `feat/issue-14-weapon-pickups`: tkneeland's test-first scenarios
(`83f7820`), handed off to agage-JG after the 2026-09-24 playtest. Main was
merged in and the feature implemented against those scenarios. Windows,
local Godot 4.6.2.

| Criterion (issue #14) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| US1/4: one pickup at round start, never the pickaxe | `pickup_appears_at_round_start` | `issue-14/scenario-suite.txt` | PASS |
| US2/3/20: more arrive on the interval, capped at 2 | `pickups_arrive_on_interval_and_cap` | `issue-14/scenario-suite.txt` | PASS |
| US4/5: uniformly random, never the pickaxe | `pickup_weapon_is_random_never_pickaxe` | `issue-14/scenario-suite.txt` | PASS |
| US6/8/9/12: body touch swaps immediately, old weapon gone, one winner per pickup | `body_touch_swaps_weapon` | `issue-14/scenario-suite.txt` | PASS |
| US7: a weapon head does nothing | `weapon_head_does_not_collect_pickup` | `issue-14/scenario-suite.txt` | PASS |
| US19: an eliminated player can't collect | `eliminated_player_cannot_collect` | `issue-14/scenario-suite.txt` | PASS |
| US13: cleared at round end | `pickups_cleared_at_round_end` | `issue-14/scenario-suite.txt` | PASS |
| US16/17: markers used, with a fallback when none | `pickup_spawn_points_and_fallback` | `issue-14/scenario-suite.txt` | PASS |
| US18: every stage's spots are clear of geometry and the kill zone, for the largest pickup | `stage_pickup_spawns_are_safe` (all 11 stages) | `issue-14/scenario-suite.txt` | PASS |
| US14/15: the winner keeps a pickup's weapon, the loser resets | `pickup_weapon_carries_to_winner_next_round` | `issue-14/scenario-suite.txt` | PASS |
| US10: drawn with the weapon's art | `pickup_drawn_with_weapon_art` | `issue-14/scenario-suite.txt` | PASS |
| Works in the real game | windowed smoke run of the real `Main.tscn` with two WebSocket clients: pickups on every stage at their markers, grabs swap, the winner carries the weapon | `issue-14/smoke.txt` | PASS |
| Boots on a fresh clone | `godot --headless --path . --quit`, no `.godot` present | `issue-14/boot-check.txt` | PASS |

## Test changes to tkneeland's scenarios

These were written against stubs before #13 landed. Three needed adjusting
to what `main` is now; in each case the property under test is unchanged:
- `body_touch_swaps_weapon`: the racers now start clear of the contested
  pickup. With a real trigger, one of them was collecting it during setup.
- `pickups_cleared_at_round_end`: a typed-array assignment to the stub
  roster.
- `pickup_drawn_with_weapon_art`: the no-art case uses the file's own
  `_ArtWeapon` with an empty outline, because since #13 a blank `WeaponStats`
  draws its default circle.

`stage_pickup_spawns_are_safe` now sweeps `STAGE_PATHS` (all 11 stages) and
measures against the largest pickup the roster produces, not a blank
weapon's.

## Known failure, not from this work

`roster_heads_do_not_tunnel_head` (#27): see `issue-14/tunnel-comparison.txt`.
