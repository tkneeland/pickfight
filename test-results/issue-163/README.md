# Issue #163: round flow fixes

Tested on this branch, on main `3a6db34`.

## Findings and fixes

| # | Finding | Fix | Scenario (fails on main, passes here) |
|---|---|---|---|
| 1 | Spawns were indexed by slot number. Stages pair their spawns left/right, so a roster of slots 0 and 2 started both players on the left (Flatlands x -60 and -520). | `_spawn_for_slot(slot)` became `_spawn_point(place)`. `_try_start_round()` passes the player's place in the round's roster. The stale Stage.gd comment and the stale #137 note are fixed, and `_show_scoreboard`'s doc comment is back on it. | `gap_roster_spawns_in_roster_order` |
| 2 | The stage bag was filtered by player count only when it was refilled, and it survived across matches. Three players and then seven left no large stage until the three-player bag had run out. | The bag is re-dealt when the count crosses `large_stage_min_players` in either direction. This only applies to a rotation that has a large stage, so a rotation without one deals exactly as before. `_begin_match()` also clears the bag. | `stage_bag_redeals_when_player_count_crosses_large` |
| 3 | The last round's stage kept running under the podium and the lobby, with rocks and collapsing floors still ticking and playing sounds. | `_enter_lobby()` and `_enter_victory()` free it with `_clear_stage()`. `_stage_index` is kept, so the next round still does not repeat the stage. | `stage_freed_under_victory_and_lobby` |
| 4 | Round end was checked only in `_process`. With two physics ticks in one frame, the last survivor could die a tick after the deciding KO, and the round then scored nobody. | When an elimination leaves one player alive, that player's slot is recorded (with the physics frame). `_check_round_end()` gives them the round if nobody is left. If the survivor falls on the same tick, the round is still a draw. | `last_survivor_scores_when_falling_a_tick_later` |
| 5 | Hitmarkers and damage numbers shrank on large stages. | Both are scaled by 1 / camera zoom, like the name tags. The number stays centred over the hit, and the marker's pop applies on top of the new scale. | `hit_feedback_scales_with_camera_zoom` |
| 6 | The `lobby_phase()` doc left out "round_end". | Doc fixed. | none (doc only) |

## Red on main

These are the five new scenarios run against main's `scripts/` with this branch's runner:

```
FAIL  gap_roster_spawns_in_roster_order
      - slot 2 started at x -520, not on Spawn1 at x 60
      - slots 0 and 2 both started on the same side (x -60 and -520)
FAIL  stage_bag_redeals_when_player_count_crosses_large
      - seed 1: large stage 10 was not dealt in the 12 rounds after seven joined
      - (7 more missing large stages over seeds 2, 3, 5, 7)
      - a new match kept the last match's bag (7 stage(s) left in it)
FAIL  stage_freed_under_victory_and_lobby
      - StubA kept running under the victory screen
      - StubB kept running under the lobby screen
FAIL  last_survivor_scores_when_falling_a_tick_later
      - P2 outlived P1 by a tick and should have scored the round; scores moved by [0, 0]
FAIL  hit_feedback_scales_with_camera_zoom
      - zoom 0.50: hitmarker scaled 1.000, expected 2.000
      - zoom 0.50: damage number scaled 1.000, expected 2.000
0 passed, 5 failed, 5 total
```

## Full suite

The boot check was clean, and all 189 scenarios passed in 4 shards (48 + 48 + 48 + 45). The log is in [full-suite.txt](full-suite.txt).

The existing `spawns_shared_when_stage_has_fewer_than_players` now calls `_spawn_point()` instead of `_spawn_for_slot()`. Its assertions are unchanged.
