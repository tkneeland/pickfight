# #755 verification

Commit 030faf5 on `feat/issue-755`.

- **Fix:** the per-weapon loop skips `PickupWeaponsScript.RETIRED_PATHS`, the game's own list of retired weapons (spear and pogo, #642 and #655). Players can no longer meet those weapons in a clash. No weapon stats changed.
- **Clashes measured:** in every in-rotation clash the axe gave between -0.6 and 3.8 px, and the other weapon gave 25.8 to 31.6 px.

| Check | Result |
|---|---|
| `--scenario=axe_wins_clash_against_every_weapon` | 1 passed, 0 failed |
| Full suite `--fixed-fps 60 --all` on macOS | 911 passed, 0 failed |
| Fresh clone boot grep | no output (clean) |
