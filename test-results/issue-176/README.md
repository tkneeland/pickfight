# Issue #176: bots read stage hazards

Branch `feat/issue-176-bots-read-hazards`, off main `d62ad2b`.

## Full suite

`bash shard.sh 176 5`: the whole `SCENARIO_NAMES` list (215 scenarios) run as 5 parallel shards of `tools/scenario_runner.gd -- --scenarios=...`. The log is `full-suite.txt`.

Result: **213 passed, 2 failed, 215 total**. Both failures are already on main and are not from this change:

- `controller_page_look_picker_after_name`: the known CRLF issue with a Windows checkout.
- `round_modifier_double_damage_applies_and_undoes`: fails in a shard because of the `modifier_rolls_enabled` leak. Run alone it passes (1 passed, 0 failed).

Fresh-clone boot (`godot --headless --path <fresh clone> --quit`): the only ERROR is qrencode "Could not create child process". That is environment-only: qrencode is not installed on this machine.

## New scenario

`bots_survive_hazard_stages`: a lone bot, seeded, set down on the hazard itself, must still be alive after 20 s.

| Case | This branch | main's `Bot.gd` |
|---|---|---|
| Rockfall, on the bridge under the falling rock (0, 320) | alive after 20 s | died after 10.2 s |
| Mill, on the see-saw sails (-120, 260) | alive after 20 s | died after 8.0 s |

I ran it 4 times on this branch: it passed every time, and the bots ended at the same positions each run. I ran it 3 times with main's `Bot.gd` (`git checkout origin/main -- scripts/Bot.gd`, run, then `git checkout HEAD -- scripts/Bot.gd`; no `git stash`). It failed every time, with the times above.

The existing bot scenarios pass unchanged: `bots_flag_fills_lobby_and_bots_fight`, `solo_practice_button_adds_and_removes_bots`, `solo_ignored_mid_match_and_removed_bots_leave_round`, `bots_stop_thinking_while_paused`, `solo_bots_go_when_the_last_phone_leaves` and `bot_upkeep_cached_and_names_unique`.

## Before and after: time to first stage death

`tools/ringout_probe.gd --brain=bot` runs the real game (Main.tscn, one stage in the rotation, lobby off, modifiers off) with four real `Bot.gd` bots. Their input goes through the phone's `InputSmoother`. Each stage ran for 300 s at `--fixed-fps 60` with seeds 1, 2 and 3. Before is main's `Bot.gd` at `d62ad2b`; after is this branch. Both used the same probe.

A **stage death** is an elimination before the lava's grace ends with no strike from another player in the 2 s before it, so a rival's knock-off is not counted against the stage. **Mean time to first stage death** is averaged over rounds; a round with none counts as the whole grace (50 s), so it is a lower bound. The raw lines are in `probe-before.txt` and `probe-after.txt`.

| Stage | Hazard | Mean time to first stage death, before -> after (s) | Stage deaths per bot-minute, before -> after | Stage deaths (rounds), before -> after |
|---|---|---|---|---|
| Carousel | rotating platforms | 7.5 -> 19.9 | 1.70 -> 0.40 | 40 (22) -> 7 (9) |
| Erosion | crumbling ledges | 7.9 -> 8.3 | 2.32 -> 1.97 | 65 (42) -> 67 (46) |
| Ferry | moving barge | 4.3 -> 6.4 | 4.43 -> 1.65 | 141 (65) -> 40 (23) |
| Flatlands | none (control) | 37.0 -> 26.1 | 0.13 -> 0.50 | 4 (12) -> 15 (16) |
| Furnace | hazard columns | 23.0 -> 16.0 | 0.63 -> 0.81 | 23 (27) -> 29 (39) |
| Mill | see-saw sails, collapsing edges | 4.9 -> 11.0 | 4.05 -> 1.11 | 143 (63) -> 22 (19) |
| Overpass | bounce pads, crumbling ledges | 15.7 -> 34.3 | 1.08 -> 0.16 | 40 (27) -> 4 (9) |
| Pistons | pistons (moving platforms) | 20.2 -> 18.2 | 0.49 -> 0.56 | 16 (18) -> 19 (20) |
| Quarry | falling rocks, lifts | 4.7 -> 7.3 | 1.75 -> 1.49 | 41 (24) -> 28 (19) |
| Reactor | hazard zone, moving platform, breakable wall | 20.7 -> 12.4 | 0.76 -> 1.08 | 19 (12) -> 21 (17) |
| Rockfall | falling rocks | 1.7 -> 11.8 | 9.18 -> 0.91 | 157 (56) -> 17 (16) |
| Sinkhole | collapsing floor | 14.0 -> 14.8 | 1.63 -> 1.10 | 61 (37) -> 32 (18) |
| Updraft | wind zones, crumbling ledges | 2.9 -> 21.0 | 0.66 -> 0.32 | 14 (10) -> 6 (9) |
| Ziggurat | collapsing throne, falling rocks | 18.0 -> 14.8 | 0.48 -> 0.87 | 12 (12) -> 25 (24) |

The runs are noisy. Physics throws are chaotic, and a 300 s × 3-seed run of the same code can move a stage's rate by ±30%, so read small differences as noise.

- **Big wins**, where the bots now read the hazard:
  - Rockfall: 9.2 → 0.9 stage deaths per bot-minute; the first death went from 1.7 s to 11.8 s.
  - Mill: 4.1 → 1.1.
  - Ferry: 4.4 → 1.7.
  - Carousel: 1.7 → 0.4.
  - Overpass: 1.1 → 0.2.
  - Updraft: the first death went from 2.9 s to 21 s.
  - Quarry and Sinkhole improved more modestly.
- **Worse, and why**: Flatlands, Ziggurat, Reactor and Furnace. On main, a bot on a low stage "worried" about the lava for the whole grace, because the lava counts as rising from round start. So on these stages main's bots never swung, climbed away from each other, and rarely came near an edge. Now they worry only in the last 2 s of the grace, so they close in and fight. A bot's own swing throws it back, and near an edge (Ziggurat's base, Flatlands' ends) that throw can put it off. When no strike landed on it, the probe counts that as a stage death. More rounds also ended by elimination on these stages, a sign that the bots fight at all. Flatlands has no hazard; it is the control.
