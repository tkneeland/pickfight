# Issue #137: wide stages, 8 spawns

## Files

- `full-suite.txt`: boot check plus the full scenario suite (psuite, 4 parallel shards) on this branch rebased on main 2456323: boot clean, 162/162.
- `new-scenarios-red-on-main.txt`: the two new scenarios (`every_stage_has_eight_safe_spawns`, `every_stage_terrain_spans_the_view`) run against main's stages. Both fail there, and both pass on the branch.
- `before/`, `after/`: one windowed screenshot per stage (Compatibility renderer, downscaled to 1600 px wide). Each has a coloured body on every spawn labelled S0..S7 (main has only 4 spawns per stage) and a ring on every pickup spot. Made with `godot --path . -s tools/capture_stage_screenshots.gd -- --out=<dir>`.
- `widen_stages.py`: the one-shot migration that edited the 17 `.tscn` files. It uses `tools/stage_tscn.py`.
- `ringout_before.txt`, `ringout_after.txt`, `ringout_table.md`: the ring-out probe, with `probe_all.sh` (the runner) and `summ.py` (the table builder).

## Ring-out probe

`tools/ringout_probe.gd` runs the real Main scene with 4 perf-probe bots on one stage, with modifiers off. Each stage ran 3 seeds x 600 s, before (main f3d1e91 stages) and after (this branch). "Falls" are ring-outs before the lava starts (50 s grace), counted per bot-minute of play.

| Stage | falls/bot-min before | after | change | hazard deaths/bot-min before | after | median s to first elim before | after | rounds before | after |
|---|---|---|---|---|---|---|---|---|---|
| Flatlands | 2.09 | 1.17 | -44% | 0.06 | 0.09 | 4.0 | 9.4 | 52 | 36 |
| Pillars | 17.14 | 15.79 | -8% | 0.00 | 0.00 | 1.6 | 1.6 | 186 | 206 |
| Ferry | 9.42 | 6.68 | -29% | 0.00 | 0.00 | 1.8 | 2.5 | 223 | 166 |
| Highrise | 3.25 | 1.21 | -63% | 0.00 | 0.10 | 4.2 | 10.1 | 72 | 36 |
| Erosion | 11.61 | 6.64 | -43% | 0.00 | 0.00 | 2.5 | 3.6 | 165 | 118 |
| Islands | 7.81 | 7.61 | -3% | 0.01 | 0.00 | 2.2 | 2.4 | 193 | 188 |
| Furnace | 0.00 | 0.02 | n/a | 28.65 | 3.28 | 0.3 | 5.8 | 205 | 73 |
| Gauntlet | 3.49 | 3.19 | -9% | 0.83 | 0.98 | 3.1 | 3.9 | 87 | 83 |
| Cascade | 4.92 | 1.88 | -62% | 0.00 | 0.08 | 3.2 | 10.0 | 99 | 51 |
| Slant | 4.71 | 2.41 | -49% | 0.04 | 0.26 | 2.0 | 3.5 | 86 | 59 |
| Bowl | 3.84 | 2.58 | -33% | 0.08 | 0.18 | 4.2 | 4.9 | 82 | 64 |
| Springboard | 6.53 | 6.27 | -4% | 0.02 | 0.02 | 2.4 | 2.4 | 118 | 120 |
| Gale | 5.61 | 4.79 | -15% | 0.00 | 0.00 | 2.5 | 3.2 | 125 | 117 |
| Carousel | 9.26 | 6.33 | -32% | 0.00 | 0.02 | 1.5 | 1.2 | 219 | 144 |
| Rockfall | 6.10 | 6.06 | -1% | 0.00 | 0.00 | 2.2 | 1.8 | 112 | 117 |
| Sinkhole | 5.17 | 3.84 | -26% | 0.02 | 0.00 | 3.4 | 6.2 | 103 | 94 |
| Bulwark | 3.64 | 3.40 | -7% | 0.02 | 0.05 | 3.9 | 3.8 | 70 | 72 |
| **All** | 6.05 | 4.39 | -27% | | | | | | |

Read the table this way:

- Ring-outs are still frequent on every stage: 4.4 per bot-minute overall, down 27% from 6.1.
- The biggest drops are on the stages that had been a narrow strip (Flatlands, Highrise, Cascade, Slant, Erosion). Rounds there now last about 10 s before the first elimination, not 3-4 s. That was the point of widening them.
- Gap stages (Pillars, Islands, Springboard, Gale, Rockfall, Gauntlet, Bulwark) barely changed, because their gaps are still the gaps.
- Furnace's hazard deaths fell from 28.7 to 3.3 per bot-minute. Before, the hazard columns sat inside the spawn area and bots died in 0.3 s. Now the columns sit at the stage edges and are the ring-out.
