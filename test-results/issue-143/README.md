# Issue #143: four new normal-size stages

Tested on this branch, based on main `9102999`.

## Stages

Each new stage combines existing parts (ADR-0008) in a way none of the current 17 does. Each also follows the #137 conventions and has its own #117 backdrop.

| Stage | Layout | Gimmick (parts) | Backdrop |
|---|---|---|---|
| Updraft | A low core with two higher banks and two 260 px shafts between them | Upward gusts in each shaft, half a cycle apart (WindZone pointed up). Crumbling perches sit above the shafts (CrumblingLedge). | Cold teal, mountains and clouds |
| Quarry | Two yards with a 600 px pit between them and a small roof high in the middle | Two lifts in opposite phase run up to the roof (vertical MovingPlatform). A rock chute drops onto the roof (FallingRock). | Ochre dusk, mountains and rocks |
| Mill | Two fields with a 520 px gap | Two crossed sails spin on one hub and bridge the gap (RotatingPlatform x2). The outer edges collapse at 20 s (timed CollapsingFloor). | Olive harvest evening, clouds and hills |
| Reactor | One unbroken floor | A molten core in the middle (Hazard x2) sits behind breakable shield walls (BreakableWall). A moving bridge crosses over it (MovingPlatform). | Magenta haze, mountains and city |

## Screenshots

These are windowed, not headless, taken with the Compatibility renderer at 1920x1080. Each one shows a real body on each of the 8 spawns, labelled S0..S7, and a yellow ring on each pickup spot. They were made with `godot --path . -s tools/capture_stage_screenshots.gd -- --out=<dir> --stages=Updraft,Quarry,Mill,Reactor`.

- [Updraft.png](Updraft.png)
- [Quarry.png](Quarry.png)
- [Mill.png](Mill.png)
- [Reactor.png](Reactor.png)

## Per-stage scenarios

The stages are appended to `STAGE_PATHS` and to Main's `stage_scenes`. Every per-stage scenario sweeps them, and all pass. Here is what each scenario reported for the new stages:

- `every_stage_terrain_spans_the_view`: Updraft, Quarry and Mill span 93% of the view, and Reactor spans 90%.
- `every_stage_has_eight_safe_spawns`: 8 of 8 settled together on each stage.
- `every_stage_can_ring_out`: each stage has an open end.
- `stage_pickup_spawns_are_safe` and `every_stage_has_pickup_spot_clear_of_spawns`: every spot is clear. Updraft has 5 spots and the others have 3.
- `stage_backgrounds_draw_behind_everything`: 2 or 3 layers, brightest 0.14-0.25.
- `stage_spawns_are_safe`, `stage_four_spawns_settle_together`, `kill_zone_holds_during_grace`, `rising_kill_zone_eliminates_holdout` and `stage_rotates_each_round` all pass.

No existing scenario hard-codes a stage count of 17, so none needed updating.

## Ring-out probe (sanity check)

`tools/ringout_probe.gd` ran 4 bots for 300 s with seed 1. The table counts falls before the lava rises, per bot-minute. Gale was run in the same batch for comparison.

| Stage | falls/bot-min | hazard deaths | median s to first elim | rounds |
|---|---|---|---|---|
| Updraft | 8.76 | 0 | 1.7 | 28 |
| Quarry | 6.89 | 0 | 2.8 | 18 |
| Mill | 6.56 | 0 | 3.5 | 22 |
| Reactor | 2.47 | 8 | 4.6 | 10 |
| Gale | 3.90 | 0 | 3.2 | 13 |

All four stages fall within the range of the existing 17, which is 1.2 to 15.8 falls per bot-minute after #137.

## Full suite

`full-suite.txt` has the full scenario list, run as 5 parallel shards, plus the fresh-clone boot check. The result is **168 passed, 0 failed, 168 total**. The only boot ERROR is qrencode's "Could not create child process". That comes from this environment, not from the change.
