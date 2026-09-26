# Issue #161 evidence

## What was run
The full scenario list (202 scenarios), run as 5 parallel shards of `--scenarios=` with Godot 4.6.2 headless on Windows 11. The branch is rebased onto main `3c38982`. The ticket was cut from `3a6db34`, and main moved three times (#163, #165, #164) while this work was in progress. The log is in `full-suite.txt`.

## Result
200 passed, 2 failed, 202 total. Both failures are known issues on main that this change does not touch:

- `controller_page_look_picker_after_name` is the known CRLF issue: the Windows checkout has CRLF line endings. It passes in an LF clone (`git clone -c core.autocrlf=false`, then import, then run the scenario).
- `round_modifier_double_damage_applies_and_undoes` is the known shard-order leak. Earlier scenarios, such as `name_tags_on_for_every_living_player_all_round`, leave `RoundManager.modifier_rolls_enabled = true`, so this scenario draws random modifiers. It passes when run on its own.

New scenarios: `mid_match_joiner_starts_with_fresh_slot` and `pause_keeps_ko_credit_and_survival_time`. Both fail against main's `scripts/MatchStats.gd` and `scripts/RoundManager.gd`, and both pass with the fix.

## Fresh-clone boot
The only ERROR is qrencode "Could not create child process". It is environment-only: qrencode is not installed on this machine.
