# #748 Gamepad stick deadzone setting: verification

Windows 11, Godot 4.6.2. Branch `feat/issue-748-stick-deadzone`, based on `origin/main` at `5b9944f` and merged up to `437931c`.

## Behaviour

- **Settings > More options > Stick deadzone: 0.20** (a dropdown): 0.05 to 0.40 in 0.05 steps, default 0.20, which is what the game always used.
- Saved with the host settings (`user://audio.cfg`, key `pad_deadzone`). A value off the list snaps to the nearest step; a junk saved value falls back to 0.20.
- Read for every seated gamepad (`ControllerServer._pad_axis`) and for the PC client's gamepad (`RemoteClient._pad_input`), through `ControllerServer.pad_deadzone()`.
- `stick_vector()` and `pad_stick()` take the deadzone as an optional last argument that defaults to the old `PAD_DEADZONE` constant, so every existing caller and test behaves as before.

## Evidence

| Check | Result |
|---|---|
| `stick_deadzone_setting_748` (settings object: default, eight steps, snapping, saved and reloaded, a junk value; the radial helper; a seated pad reading the setting at 0.2 / 0.4 / 0.05; the Settings dropdown: 8 items, 0.20 selected, picking the sixth sets 0.30 and the panel shows it) | PASS |
| Mutation checks (each breaks one thing; the scenario must fail; the file is restored exactly and it passes again) | helper ignores the argument: FAILS on 2 assertions. Seated pads ignore the setting: FAILS on 2. A value is not snapped: FAILS on 4. Not saved: FAILS (reloaded 0.2, expected 0.35). Dropdown not wired: FAILS on 2 |
| Runner parse check | no output (pass) |
| Fresh-clone boot check of the merged head (no `.godot/`) | no output (pass) |
| Full suite | **918 passed, 3 failed, 921 total** |

The 3 failures are the same ones that fail identically on untouched `origin/main` on this machine and pass on Linux CI; not from this change:

- `flail_ball_does_not_clip_head` (ball goes 6.9 px into a held sword)
- `online_bots_only_match_starts_offline_and_says_so` (link stays on "connecting")
- `career_phone_page_shows_compact_line_and_expands_503` (expected HTML snippet not found on Windows)

### What the first full run caught in the scenario (not in the feature)

`stick_deadzone_setting_748` passed alone but failed in the first full run ("picking the sixth item set the deadzone to 0.2, expected 0.3"). The Settings panel is a singleton that keeps the settings object it was built with; in the full suite an earlier scenario had built it, and it held a different object from the shared one the scenario was changing. The scenario now drives and reads the panel through its own settings object (`ui.host`). The second full run (above) passes.

## Not covered by a screenshot

The dropdown sits in the "More options" scrolling list (a fixed height), so the panel does not grow; the suite's layout checks (`deck_text_is_legible_at_1280x800` and the lobby fit tests) pass.

## Translations

`SETTINGS_STICK_DEADZONE` has all nine columns (the label takes the value, e.g. "Stick deadzone: 0.20"). The eight non-English ones are drafts for the volunteer proofreaders.
