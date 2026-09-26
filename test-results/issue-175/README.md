# Issue #175: split RoundManager.gd

A refactor that changes no behaviour. RoundManager.gd, 1865 lines, is split into StageRotation, PickupDirector, NameTags and LobbyScreen, and its @exports are gathered at the top. The result is 1355 lines.

## What was run

- **After each piece's commit:** the scenarios covering that piece.
  - Rotation: 10
  - Pickups: 17
  - Name tags: 7
  - Lobby, pause, title and awards: 20

  All of them passed.
- **Full suite:** the whole scenario suite in 5 shards (`shard.sh 175 5`), on branch `refactor/issue-175-split-roundmanager` off main `d62ad2b`. Its output is in `full-suite.txt`.
- **Fresh-clone boot:** `godot --headless --path <fresh clone> --quit`.

## Result

**212 passed, 2 failed, 214 total.** This matches main `d62ad2b`. Both failures are already failing on main:

- `controller_page_look_picker_after_name` fails because of CRLF line endings in the checkout.
- `round_modifier_double_damage_applies_and_undoes` fails because `modifier_rolls_enabled` leaks between scenarios when they run in a shard.

The fresh-clone boot printed no SCRIPT ERROR and no "Failed to load script". The only error in the boot line is the qrencode one below.

## Note

`ERROR: Could not create child process: qrencode ...` is expected on this Windows host. qrencode isn't installed there, so the join QR falls back.
