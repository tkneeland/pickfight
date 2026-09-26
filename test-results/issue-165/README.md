# Issue #165: host drop while paused, bots vs pause/solo/remove, bot upkeep

Tested on this branch, rebased on main `1e97a2a`. Full suite: 194 passed, 0 failed, boot clean (`full-suite.txt`).

| # | Finding | Fix | Scenario |
|---|---|---|---|
| 1 | Host phone drops while paused: nobody is told they are host, so nobody can Resume | `ControllerServer.host_changed` (checked every frame, paused or not); RoundManager republishes the lobby state on it | `host_drop_while_paused_hands_menu_to_next_phone` |
| 2 | "Remove bots" mid-round leaves live bot bodies | Solo heeded only in `lobby`/`countdown`; `BotDirector.remove_bot()` takes a bot in the round out of it (`leave_round()`) | `solo_ignored_mid_match_and_removed_bots_leave_round` |
| 3 | Bots keep thinking while paused | `BotDirector` is `PROCESS_MODE_PAUSABLE` | `bots_stop_thinking_while_paused` |
| 4 | After the Solo host leaves, bots play forever | Solo bots alone never make a ready lobby (`_everyone_ready`); after `orphan_grace_sec` (10 s) with no phone connected they go, mid-round included. `--bots=N` bots are unaffected | `solo_bots_go_when_the_last_phone_leaves` |
| 5 | Bot perf/quality | Ray exclusion list built once a tick; lava looked up once a life; rng seeded in `_init`; "Bot N" takes the lowest free N; mid-round the lobby state is built only when roster/alive/host/round changed, or every 250 ms | `bot_upkeep_cached_and_names_unique` |

## Red on main

The five scenarios run against main's game code (main `3a6db34`, scenarios from this branch):

```
FAIL  host_drop_while_paused_hands_menu_to_next_phone
      - phone 2 was never told it is host of the paused game (last lobby state: host 0.0, paused true)
FAIL  solo_ignored_mid_match_and_removed_bots_leave_round
      - Remove bots mid-round was heeded: 0 bots left of 3, roster [0]
      - removed bots' bodies stayed in the round in slots [1, 2, 3]
FAIL  bots_stop_thinking_while_paused
      - bots in slots [1, 2, 3] kept thinking while the game was paused
FAIL  solo_bots_go_when_the_last_phone_leaves
      - the bots started a match with the solo host gone (phases ["lobby", "countdown", "playing"])
      - the solo bots stayed with no phone connected: 3 bots, roster [1, 2, 3]
      - the second Solo practice never started a match (phase 'playing')
      - --bots style bots went away with no phone connected (6 left)
FAIL  bot_upkeep_cached_and_names_unique
      - a bot's rng seed set before it entered the tree was replaced (8290182404167362329, expected 165)
      - the ray exclusion list is rebuilt for every ray, not once a tick
      - the bot searched the tree for the lava <null> times in one life, expected once
      - bot names after a kick and an add were ["Bot 2", "Bot 3", "Bot 3"], expected Bot 1..3, no repeats
      - the lobby state was built -1 times in 60 frames of a round (at most 12 allowed)
0 passed, 5 failed, 5 total
```
