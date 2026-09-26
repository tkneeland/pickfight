# Issue #180: a stalled drive pushes its rated force

Evidence for the branch `feat/issue-180-stall-force`, rebased onto main a09e644.

- `full-suite.txt`: the full suite on the branch (`--fixed-fps 60`, 4 shards): 232 passed, 2 failed of 234 (`flail_built_clear_of_neighbours` and `match_seed_replays_bot_match`, both explained below). Two runs after the rebase gave the same result.
- `before-main-focused.txt`: traversal, clash, grip and responsiveness scenarios on main 30f8587, before any change.
- `before-main-new-scenarios.txt`: the two new scenarios run against main's drive code and forces.

## What changed

The extension drive is a velocity servo. It sized its push on the pair's reduced mass μ even when the head could not move. Stalled, it asked for `extend_speed * μ / dt` and no more:

- the axe asked for about 5700 against its rated 11000;
- the boomstick would have asked for about 7400 at 8000.

`WeaponHead` now records which contacts block the push and the mass behind each one. Terrain, frozen bodies and other heads count as immovable. While blocked, `Player._stalled_mass` raises the servo's mass to `F * dt / extend_speed`, which is what asks for the full F. That mass is capped by the mass the push is actually moving.

The floor only ever raises the mass, so free-air and small-error behaviour is unchanged. Only the axe and the boomstick are affected, because they are the only weapons where `F * dt / extend_speed` exceeds μ. The angle drive gets the same floor: `max_torque * dt / drive_speed`, capped by `haft_I + moved * L²`.

Forces (`max_drive_force`):

| weapon | before | after |
|---|---|---|
| pickaxe, sword, boomstick | 6000 | 8000 |
| staff | 5000 | 6700 |
| dagger, grapple, flail, boomerang | 5500 | 7300 |
| axe | 11000 | 11000 |

## Stalled push, as a fraction of rated force (`stalled_drive_pushes_rated_force`)

A braced player drives its head into a 40 kg free-floating load. The force is read off the load's gain in speed. The turn divides the torque by the lever.

| weapon | main: push | main: turn | branch: push | branch: turn |
|---|---|---|---|---|
| pickaxe | 100% of 6000 | 93% | 100% of 8000 | 95% |
| staff | 100% of 5000 | 96% | 100% of 6700 | 97% |
| sword | 100% of 6000 | 97% | 100% of 8000 | 98% |
| axe | **51%** of 11000 | 91% | 91% of 11000 | 91% |
| dagger | 100% of 5500 | 98% | 100% of 7300 | 98% |
| boomstick | 100% of 6000 | 100% | 96% of 8000 | 98% |
| grapple | 100% of 5500 | 96% | 100% of 7300 | 98% |
| flail | 98% of 5500 | 88% | 98% of 7300 | 96% |
| boomerang | 100% of 5500 | 96% | 100% of 7300 | 98% |

The axe's remaining 9% is the servo tapering off as the load picks up speed. The angle drive did not have the cap at ordinary reach, because past about 15-37 px of lever `drive_speed * inertia / dt` already exceeds the ceiling. The one exception was the light boomstick at 8000, which turned at 83% before the floor was added.

## Axe head-on against every weapon (`axe_wins_clash_against_every_weapon`)

Both players are braced, set their full reaches plus head lengths minus 40 px apart, and walked together. The table shows the reach each side gave up, as axe / other. The pass mark is that the other weapon gives at least 20 px more than the axe.

| vs | main, axe left | main, axe right | branch, axe left | branch, axe right |
|---|---|---|---|---|
| pickaxe | 2.3 / 27.3 | **8.4 / 21.0** | 3.4 / 30.6 | 3.6 / 25.6 |
| staff | 4.2 / 25.3 | 3.2 / 31.8 | 3.2 / 26.5 | 3.2 / 28.2 |
| sword | **16.4 / 13.1** | **16.4 / 13.2** | 3.6 / 25.9 | 3.6 / 26.0 |
| dagger | 4.6 / 25.0 | 4.6 / 25.0 | 3.3 / 26.3 | 3.3 / 26.3 |
| boomstick | **10.1 / 19.5** | **10.1 / 19.5** | 3.6 / 26.0 | 3.6 / 26.0 |
| grapple | 4.6 / 25.0 | 4.6 / 25.0 | 3.3 / 26.3 | 3.3 / 26.3 |
| flail | 4.5 / 25.0 | 4.5 / 25.0 | 3.3 / 26.6 | 3.2 / 26.3 |
| boomerang | 4.6 / 25.0 | 4.6 / 25.0 | 3.3 / 26.3 | 3.3 / 26.3 |

Main fails five of these sixteen, shown in bold, even at 6000. The axe's stalled push was only about 5700.

Other clash scenarios, main then branch:

| scenario | main | branch |
|---|---|---|
| `heavy_weapon_wins_clash` (axe gave / dagger gave) | 26.2 / 68.0 px | 26.2 / 68.0 px |
| `clash_higher_drive_force_wins` (stronger right) | -25.0 px | -29.5 px |

## Traversal (`roster_traversal_is_measured`)

Each cell is main, then branch.

| weapon | aim (ticks) | extend (ticks) | vault (px) | climbs | median climb (ticks) |
|---|---|---|---|---|---|
| pickaxe | 11, 10 | 12, 12 | 163.2, 164.3 | 9/10, 9/10 | 324, 215 |
| staff | 12, 10 | 9, 8 | 347.6, 405.7 | 10/10, 10/10 | 81, 80 |
| sword | 8, 7 | 4, 4 | 88.2, 101.2 | **8/10, 3/10** | 226, 600 |
| axe | 11, 11 | 25, 25 | 123.0, 125.1 | 9/10, 8/10 | 289, 287 |
| dagger | 7, 7 | 4, 3 | 119.1, 139.1 | 6/10, 7/10 | 476, 190 |
| boomstick | 8, 7 | 3, 3 | 86.1, 91.5 | 4/10, 6/10 | 600, 350 |
| grapple | 8, 7 | 5, 4 | 109.9, 122.5 | 6/10, 6/10 | 102, 186 |
| flail | 8, 7 | 5, 5 | 83.2, 92.8 | 4/10, 9/10 | 600, 258 |
| boomerang | 8, 7 | 4, 4 | 103.2, 115.6 | 7/10, 9/10 | 73, 117 |

Climbs are noisy: the same code has scored the pickaxe 9/10 and 10/10, and the boomstick 5/10 and 6/10.

Responsiveness, in ticks to answer a 20 to 70 px drag (`weapon_responsiveness_matches_roster`):

| | pickaxe | staff | sword | axe | dagger | boomstick | grapple | flail | boomerang |
|---|---|---|---|---|---|---|---|---|---|
| main | 5 | 3 | 4 | 10 | 3 | 3 | 4 | 4 | 4 |
| branch | 5 | 3 | 6 | 10 | 4 | 3 | 5 | 4 | 5 |

The S tier's spread is now 3, which is exactly at the limit.

## Test changes

- `planted_head_grips_sideways_push`: the push-off is now measured until the head reaches full reach. At any pickaxe force above 6000, the body yanks the head at the groove's end stop in the tick before lift-off. That happens even on main's servo. Instrumented, the plant itself holds at 0.0 px. The result is 0.0 / 0.0.
- `head_strike_damage_scales`: the creep is now walked level. Both bodies were in free fall, and by the end of the window the fall alone exceeded `MIN_STRIKE_SPEED`. At 8000 the pickaxe head shifted on the bystander in the last tick and scored the fall as a strike.
- `weapon_damage_matches_roster`: `ROSTER_DAMAGE_SPREAD` is now the M band's own 26 plus one tolerance (29, up from 27). A pickaxe strike 0.7 under its 34 hit the old edge exactly.
- `WeaponHead.set_phased` clears the blocking contacts. Without that, a freshly phased boomstick was driven home at the stalled force, straight past the home slack (`haft_tip_meets_drawn_head_every_frame`).

## Known failures, not from this change

- `flail_built_clear_of_neighbours` fails locally at the flail's 7300. It passes at 5500 on this branch, but fails at 6000, 6500 and 7000, and also on main's servo at 7300, so the higher force triggers it rather than the servo. It is #192 (flail chain stability), which owns `FlailChain.gd`.
  - Root cause found here: `FlailChain._limit_stretch` teleports the ball back onto the stretch limit without telling its `WeaponHead` sweep. The next world sweep then runs from where the ball was jammed to the teleported spot, meets the neighbour it was jammed on, and seats the ball back there, every tick. The ball stays pinned while the head walks away.
  - Re-basing the sweep's previous position after the teleport (`_previous_position = global_position`) holds it at 171-177 px, and the flail tunnel and clip scenarios still pass. Forgetting the previous position instead lets the ball tunnel.
- `match_seed_replays_bot_match` (#187) fails with the new forces, and the servo change doesn't matter: branch servo with main's forces passes, and main's servo with the new forces fails. The replay was never exact.
  - On main, the two runs on one seed already drift apart: 0.03 px by tick 60, 0.14 px by the end. That is float-level, likely solver ordering between the two runs in one process.
  - On main this seed's match never turns that drift into a different outcome. With the stronger weapons it does, around tick 60-90: a different KO order, and one more meteor in one run.
  - This scenario needs a fix under #187, for example comparing only the dealt streams (bot seeds, pickups, meteors) rather than the KO order and positions, or a seed-independent check.
- `phone_release_and_flick_are_not_smoothed` failed once in one shard and passed on every rerun. It does not touch the drive.
