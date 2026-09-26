# Issue #150: grappling hook, flail and boomerang (pickups only)

Branch `feat/issue-150-new-weapons` at dc37fba, rebased onto main `33cb339` (#183 game clock, #185 harness statics, #184 bots read hazards). Everything below was run on that commit.

## Full suite (`full-suite.txt`)

`psuite.sh` does a fresh-clone boot check, then runs all of `SCENARIO_NAMES` as 4 parallel shards under `--fixed-fps 60`.

Result: **231 passed, 0 failed, 231 total.** The boot is clean: no `ERROR`, `SCRIPT ERROR` or failed script load.

The existing weapons are unchanged. The clash, tunnel, clipping and `weapon_responsiveness_matches_roster` scenarios all pass with the three new weapons in the roster. Each new weapon answers the 50 px drag in 4 ticks, and each has `max_drive_force` 5500 (the cap is 6000).

## New scenarios

| Scenario | What it measured |
|---|---|
| `grapple_fires_sticks_reels_and_releases` | Hook stuck 255 px up, reeled in to 44 px (the rope's minimum), fell away on release |
| `grapple_hook_hits_player_lightly` | 6 damage and a tug toward the thrower, one strike |
| `flail_whip_damage_scales_with_speed` | Ball scale 0 / 19 / 38 / 76 at 600 / 1450 / 2200 / 3700 px/s; a slow spin (4 rad/s, 697 px/s) did 0, a whip (15 rad/s, 2492 px/s) did 37.5 |
| `flail_ball_does_not_tunnel_thin_platform` | 12 whips at a 12 px slab, fastest ball 2761 px/s, 0 crossings |
| `flail_ball_does_not_clip_head` | 10 whips at a held sword: the ball went at most 2.1 px into the blade |
| `boomerang_hits_on_the_way_out_and_back` | Flew 391 px (range 380); one hit on each leg, 28 total; caught |
| `boomerang_turns_at_terrain_and_ghosts_home` | Turned at a wall 150 px away; a wall dropped in its way home made it ghost, and it was still caught |
| `new_weapons_are_pickups_only` | In the pickup pool (8) and the roulette pool (9); never starting gear |
| `bots_wield_new_weapons` | A `Bot.gd` bot moved each new weapon's head 1227 to 1525 px in 5 s and threw or fired the launchers |
| `new_weapon_hits_credit_the_thrower` | Hits reach `strike_landed`, so the kill feed, awards and announcer get them |
| `roster_heads_do_not_clip_platform_in_play_new_weapons` | 48 seeded trials per weapon, 0 head crossings |
| `flail_built_clear_of_neighbours` | 4 flails handed out at once, 120 px apart: every ball built clear, and after 2 s of spinning no ball was more than 200 px from its player (limit 225) |

`roster_traversal_is_measured` now covers the new weapons too:

| Weapon | Vault height | Ledge climbs | Median time |
|---|---|---|---|
| Grapple | 109.9 px | 6/10 | 102 ticks |
| Flail | 83.2 px | 4/10 | never (most runs hit the 600-tick cap) |
| Boomerang | 103.2 px | 7/10 | 73 ticks |

## Perf (`perf-probe.txt`)

`tools/perf_probe.gd` ran 3600 frames with eight bots, interleaved. It has a new `--weapon=<name>` option that gives every player the same weapon each round.

| Run | Frame mean | Frame p99 | Frame max | Physics mean |
|---|---|---|---|---|
| Default roster | 1.81 / 1.84 ms | 4.16 ms | 8.1 ms | 1.02 / 1.04 ms |
| Eight flails | 1.36 / 1.35 ms | 3.29 / 3.26 ms | 14.6 / 13.5 ms | 0.63 / 0.62 ms |

No frame went over the 16.7 ms budget. With eight flails, the worst frames are round starts (stage swap plus eight rigs built). Physics in those frames is under 1 ms.

Found and fixed with this probe: eight flails handed out at a round start built their balls inside neighbouring players' bodies. The chains then blew up to NaN within two ticks. This is now covered by `flail_built_clear_of_neighbours`.
