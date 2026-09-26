# Issue #176: bots read stage hazards

Branch `feat/issue-176-bots-read-hazards`. I started it off main `d62ad2b` and rebased it onto main `e91ab17` (#175, the RoundManager split, and #136, responsive weapons). Everything below was run on the rebased branch.

## Full suite

`bash shard.sh 176 5` runs the whole `SCENARIO_NAMES` list (216 scenarios) as 5 parallel shards of `tools/scenario_runner.gd -- --scenarios=...`. The log is in `full-suite.txt`.

Result: **215 passed, 1 failed, 216 total**. The one failure, `controller_page_look_picker_after_name`, is already on main: it is the known CRLF issue with a Windows checkout.

Fresh-clone boot (`godot --headless --path <fresh clone> --quit`): the only ERROR is qrencode "Could not create child process". That is environment-only, because qrencode is not installed on this machine.

## New scenario

`bots_survive_hazard_stages` puts a seeded bot on a stage's first spawn and an idle rival on the second, with the stage's hazard between them. The bot must still be alive after 10 s.

| Case | This branch | main's `Bot.gd` |
|---|---|---|
| Ferry: across the barge's route over the water | alive after 10 s, waiting on its landing | died after 3.0 s (walked into the water) |
| Updraft: across the gap between the ledges | alive after 10 s, waiting on its ledge | died after 2.2 s (walked off its ledge) |

- **This branch:** 3 runs on its own and 1 in the full list's shard order; it passed every time, and the bots ended at the same positions.
- **main's `Bot.gd`:** 3 runs, using `git checkout origin/main -- scripts/Bot.gd`, then the run, then `git checkout HEAD -- scripts/Bot.gd` (no `git stash`). It failed every time, with the times above.
- **Choosing the cases:** I checked them first with a lab script, starting the bot anywhere from 45 px left to 45 px right of the spawn (14 starts). This branch's bot survived from every start. main's bot died within 4 s from all of them on Ferry and from 13 of 14 on Updraft. An earlier version of the scenario used Rockfall's bridge and Mill's sails. It passed alone but failed once in a shard, where physics after other scenarios comes out slightly differently. Those cases hung on a single chaotic throw, so I replaced them.

The existing bot scenarios pass unchanged: `bots_flag_fills_lobby_and_bots_fight`, `solo_practice_button_adds_and_removes_bots`, `solo_ignored_mid_match_and_removed_bots_leave_round`, `bots_stop_thinking_while_paused`, `solo_bots_go_when_the_last_phone_leaves` and `bot_upkeep_cached_and_names_unique`.

## Before and after: time to first stage death

`tools/ringout_probe.gd --brain=bot` runs the real game (Main.tscn, one stage in the rotation, lobby off, modifiers off) with four real `Bot.gd` bots. Their input goes through the phone's `InputSmoother`. Each stage ran for 300 s at `--fixed-fps 60`, with seeds 1, 2 and 3.

- **Before:** main's `Bot.gd` at `e91ab17`.
- **After:** this branch.

Both used the same probe on the same main.

- A **stage death** is an elimination before the lava's grace ends, with no strike from another player in the 2 s before it. A rival's knock-off is therefore not counted against the stage.
- **Mean time to first stage death** is averaged over rounds. A round with no stage death counts as the whole grace (50 s), so the figure is a lower bound.

The raw lines are in `probe-before.txt` and `probe-after.txt`.

| Stage | Hazard | Mean time to first stage death, before -> after (s) | Stage deaths per bot-minute, before -> after | Stage deaths (rounds), before -> after |
|---|---|---|---|---|
| Carousel | rotating platforms | 10.6 -> 18.2 | 1.26 -> 0.47 | 32 (18) -> 8 (9) |
| Erosion | crumbling ledges | 5.4 -> 9.7 | 3.03 -> 2.25 | 87 (47) -> 77 (46) |
| Ferry | moving barge | 4.6 -> 7.2 | 4.41 -> 1.42 | 149 (64) -> 29 (18) |
| Flatlands | none (control) | 37.8 -> 24.4 | 0.15 -> 0.50 | 5 (12) -> 15 (16) |
| Furnace | hazard columns | 18.7 -> 16.5 | 1.09 -> 0.86 | 42 (31) -> 31 (39) |
| Mill | see-saw sails, collapsing edges | 4.9 -> 6.3 | 4.09 -> 1.03 | 149 (67) -> 19 (14) |
| Overpass | bounce pads, crumbling ledges | 17.8 -> 27.2 | 0.93 -> 0.28 | 33 (25) -> 7 (9) |
| Pistons | pistons (moving platforms) | 21.2 -> 16.0 | 0.53 -> 0.88 | 20 (22) -> 30 (22) |
| Quarry | falling rocks, lifts | 6.2 -> 10.3 | 1.88 -> 1.05 | 48 (24) -> 18 (14) |
| Reactor | hazard zone, moving platform, breakable wall | 22.2 -> 13.2 | 0.71 -> 0.74 | 19 (13) -> 12 (14) |
| Rockfall | falling rocks | 1.8 -> 11.8 | 7.91 -> 1.30 | 151 (54) -> 27 (20) |
| Sinkhole | collapsing floor | 13.3 -> 13.8 | 1.45 -> 0.91 | 55 (43) -> 24 (15) |
| Updraft | wind zones, crumbling ledges | 7.1 -> 24.2 | 0.87 -> 0.27 | 18 (12) -> 5 (9) |
| Ziggurat | collapsing throne, falling rocks | 26.4 -> 14.9 | 0.52 -> 0.73 | 14 (13) -> 21 (23) |

These runs are noisy. Physics throws are chaotic: two 300 s runs of main's same `Bot.gd` gave Quarry 2.59 and 1.75 stage deaths per bot-minute. Read small differences as noise.

**Better**, where the bots now read the hazard. Figures are stage deaths per bot-minute unless stated.

| Stage | Before -> after |
|---|---|
| Rockfall | 7.9 -> 1.3; first death 1.8 s -> 11.8 s |
| Ferry | 4.4 -> 1.4 |
| Mill | 4.1 -> 1.0 |
| Carousel | 1.3 -> 0.5 |
| Overpass | 0.9 -> 0.3 |
| Updraft | 0.9 -> 0.3; first death 7.1 s -> 24.2 s |
| Quarry | 1.9 -> 1.1 |
| Sinkhole | 1.5 -> 0.9 |
| Erosion | 3.0 -> 2.3 |
| Furnace | 1.1 -> 0.9 |

**Worse**: Flatlands (0.15 -> 0.50), Pistons (0.53 -> 0.88) and Ziggurat (0.52 -> 0.73). Reactor is about level. The likely reason is that the bots now fight on these stages:

- On main, a bot "worried" about the lava for the whole grace, because `KillZone.is_rising()` is true from round start. Flatlands' floor, and Ziggurat's base tier, are within `LAVA_WORRY` (280 px) of the lava's surface. So main's bots there never swung and kept trying to climb.
- Now they worry only in the last 2 s of the grace, so they close in and fight.
- A bot's own swing throws it back. Near an edge (Ziggurat's base, Flatlands' ends), that throw can put it off.
- When no strike landed on the bot, the probe counts that as a stage death.

Flatlands has no hazard at all; it is the control.
