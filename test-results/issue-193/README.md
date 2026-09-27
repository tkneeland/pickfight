# Issue #193: ControllerServer hardening

**What was run:** the full scenario list (246 scenarios) from `tools/scenario_runner.gd`, split round-robin across 5 parallel headless Godot 4.6.2 processes with `--fixed-fps 60`, on Windows 11. The branch was based on main `6d4ec9d`. The raw log is in `full-suite.txt`.

**Result:** 246 passed, 0 failed, 246 total.

**New scenarios.** Each one failed when run against main's `ControllerServer.gd`, `BotDirector.gd` and `RoundManager.gd`, and passes with the fix:
- `phone_oversized_frames_dropped_cheaply`: `clean_name` of a 60k-character name took 399 ms before the fix and 0.1 ms after. A 2 KB frame is dropped unread, the inbound buffer is 16 KB, and ids are cut to 64 characters.
- `host_reload_in_lobby_keeps_host_and_colour`
- `kicking_last_opponent_scores_nobody`
- `solo_double_press_adds_bots_once`
- `solo_bot_yields_slot_to_phone`

**Fresh-clone boot check:** the only ERROR is qrencode "Could not create child process". qrencode is not installed on this machine, so that error comes from the environment, not the code.
