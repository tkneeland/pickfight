# #749 Phone vibration switch: verification

Windows 11, Godot 4.6.2. Branch `feat/issue-749-vibration-switch`, based on `origin/main` at `2e8adae`.

## Behaviour

- A **Vibration: on / off** button in the controller page's lobby panel, under "Hat & colour", styled like it.
- Default on. The choice is remembered per phone in `localStorage` (`pickfight-vibration`), read and written through the page's existing try/catch helpers `stored()` / `store()`.
- Off means `buzz()` makes **no** `navigator.vibrate()` call at all (not even a cancelling `vibrate(0)`); the colour flash still plays. The host is unchanged and keeps sending buzzes.
- Hidden on browsers with no `navigator.vibrate` (iOS Safari), where the flash is the only buzz.
- Labels in all nine language tables of the page (`PHONE_VIBRATION_ON` / `PHONE_VIBRATION_OFF`; the page keeps its own `STRINGS`, not `translations/strings.csv`). The eight non-English ones are drafts for the volunteer proofreaders.

## Evidence

### Real host, real page, in a browser (throwaway probe, not committed)

The probe ran the real game host and sent a real `hit` buzz to the connected page every 1.5 s. The page was loaded from the host in the in-app browser, with `navigator.vibrate` replaced by a counter.

| Step | `vibrate` calls | Label | `localStorage` |
|---|---|---|---|
| Fresh phone, default | 4 in 6.5 s | Vibration: on | not set |
| Switched off | **0** in 6.5 s | Vibration: off | `"0"` |
| Page reloaded | **0** in 6.5 s | Vibration: off (remembered) | `"0"` |
| Switched back on | 3 in 5 s | Vibration: on | `"1"` |

At a 375x812 phone viewport the button sits under "Hat & colour" with no overflow (bottom edge 739 px of 812). See `phone_lobby_vibration_switch.png`.

### Checks

| Check | Result |
|---|---|
| `phone_vibration_switch_749` | PASS |
| Mutation checks on the page (each must fail the scenario; page restored exactly after each) | guard removed: FAILS. Default flipped to off: FAILS. Choice not saved: FAILS. Second unguarded vibrate call added: FAILS. German label missing: FAILS (8 of 9 entries) |
| Runner parse check | no output (pass) |
| Fresh-clone boot check of the committed branch (no `.godot/`) | no output (pass) |
| Full suite | **916 passed, 3 failed, 919 total** |

The 3 failures are the same ones that fail identically on untouched `origin/main` on this machine and pass on Linux CI; not from this change:

- `flail_ball_does_not_clip_head` (ball goes 6.9 px into a held sword)
- `online_bots_only_match_starts_offline_and_says_so` (link stays on "connecting")
- `career_phone_page_shows_compact_line_and_expands_503` (expected HTML snippet not found on Windows)

### A note on the scenario

The scenario reads the shipped page, so it counts only **executable** `navigator.vibrate(` calls: two comments mention it too (the buzz-table comment and the switch's own), and the first version of the scenario counted those and failed. It checks that the button is in the lobby panel, that the one real call sits directly under the `vibrationOn` guard, the default and the saving, and that both labels exist in all nine tables.

## Screenshot

- `phone_lobby_vibration_switch.png`: the controller page's lobby at phone size, "Vibration: on" under "Hat & colour".
