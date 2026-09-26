# Issue #167 evidence

**What ran:** the full scenario list (204 scenarios), split into 5 parallel shards of `--scenarios=`, plus the fresh-clone boot check. Run on branch `fix/issue-167-audio-settings`, based on main `3c38982`. Log: `full-suite.txt`.

**Result:** 202 passed, 2 failed, 204 total. Both failures are known and already on main:

- `controller_page_look_picker_after_name`: the CRLF checkout issue. It passes in an LF clone (`git clone -c core.autocrlf=false`).
- `round_modifier_double_damage_applies_and_undoes`: fails only inside a shard, because an earlier scenario leaves `RoundManager.modifier_rolls_enabled = true`. It passes on its own.

An earlier full run also failed `bots_flag_fills_lobby_and_bots_fight` once ("no bot landed a damaging strike in 40 s"). That scenario is timing-dependent. Afterwards it passed 5 of 6 targeted runs on this branch, passed 4 of 4 on main, and passed in this full run. It uses no code this change touches.

**New scenarios, each failing on main's code and passing here:**

- `settings_fullscreen_follows_the_real_window`
- `settings_slider_drag_saves_once_on_release`
- `audio_release_out_of_tree_returns`
- `announcer_said_capped_and_lengths_from_decode`
- `music_loops_have_no_silent_seam`: extended, and fails on main

**Fresh-clone boot:** the only ERROR is qrencode "Could not create child process". It comes from this environment (no qrencode on PATH), not from the code.
