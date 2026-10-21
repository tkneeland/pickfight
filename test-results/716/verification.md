# #716 Leave lobby: verification

Windows 11, Godot 4.6.2. Branch `feat/issue-716-leave-lobby`, rebased onto `origin/main` at `8dada63`.

## Behaviour

A **Leave lobby** button sits inside the Stages & Rules box in the host lobby, directly under that button, and is in the gamepad host menu's focus chain.

- Only the host and bots seated (Solo, or an Online host nobody has joined): one press leaves.
- Another human seated (a phone, a gamepad, a remote player): the first press turns the caption into "Sure? This ends it for all" for 5 s; a second press leaves. Pressing any other lobby control disarms it.
- Leaving closes the relay room first (remote seats are told the host left), then reloads the main scene, which is what the PC client's Leave match already does. The action goes through a seam (`leave_to_title`) so the scenario runner is not carried off to a new scene.

## Evidence

| Check | Result |
|---|---|
| Scenario `lobby_leave_button_716` | PASS. Mutation check: with the confirm removed it FAILS on four assertions; restored, it PASSES |
| Runner parse check (`--check-only`) | no output (pass) |
| Fresh-clone boot check of the committed branch (no `.godot/`) | no output (pass) |
| Real reload, no seam (throwaway probe, not committed): real `Main` scene, Solo, real Leave | scene replaced, old scene freed, controller page served again on :8080 |
| Full suite after the rebase | **907 passed, 3 failed, 910 total** |

The 3 failures are the same ones that fail identically on untouched `origin/main` on this machine (checked at `0e59e9d`), and are not from this change:

- `flail_ball_does_not_clip_head` (ball goes 6.9 px into a held sword)
- `online_bots_only_match_starts_offline_and_says_so` (link stays on "connecting")
- `career_phone_page_shows_compact_line_and_expands_503` (expected HTML snippet not found on Windows)

CI on Linux is the authority for those; they were not investigated here.

### A regression the suite caught, and its fix

The first full run showed a new failure, `lobby_eight_seats_with_pad_picker_fit_the_viewport_couch_and_online_547`: one more full-size button pushed the 8-seat Online lobby 7 px past the window at 1600x900 (8.4 px at 1920x1080). Fixed by putting the button inside the Stages & Rules box (a 6 px gap instead of the column's 14) and making it a step smaller (18 px, like Kick, above the 16 px Deck floor). That scenario passes again.

## Screenshots (1600x900)

- `lobby_solo_leave_button.png`: Solo lobby
- `lobby_online_8_leave_button.png`: Online lobby with eight seats, the tightest case

## Translations

`LOBBY_LEAVE` and `LOBBY_LEAVE_CONFIRM` have all nine columns. The eight non-English ones are drafts for the volunteer proofreaders.
