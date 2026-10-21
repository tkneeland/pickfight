# #718 Quit game: verification

Windows 11, Godot 4.6.2. Branch `feat/issue-718-quit-game`, based on `origin/main` at `55bd13a`.

## Behaviour

- **Title screen:** a **Quit (Q)** button under the cards, and the Q key. One D-pad step past Solo reaches it; the existing Down walk Couch, Online, Solo is untouched. It quits at once (nobody is seated yet).
- **Settings panel (also the PC client's):** a **Quit game** button at the bottom.
  - Only the host and bots seated (Solo, a lone Online host, a PC client): quits at once.
  - Another human seated (a phone, a gamepad, a remote player): the first press swaps the button for "Quit? This ends the match for everyone" with Yes / No. No has the pad focus; B, Esc, or closing the panel is No.
- **What quitting does:** closes an open Online room first (remote players see "host left"), a PC client hangs up on its room, then the game quits through `Music`'s existing clean path (the one closing the window takes: audio freed, a finished match gets to send its record). All of it lives in the new `scripts/QuitGame.gd`, with a seam (`quit_action`) so the scenario runner never really quits.

## Evidence

| Check | Result |
|---|---|
| `quit_title_button_and_key_718`, `quit_settings_confirms_only_with_others_718`, `quit_game_pc_client_leaves_room_718` | PASS |
| Mutation checks (each breaks one behaviour; the matching scenario must fail, then the file is restored and it passes again) | no confirm: settings scenario FAILS on 4 assertions. Q key off: title scenario FAILS on 2. PC client does not leave: its scenario FAILS. Script-loop guard removed: the runner dies before printing PASS (exit 0, no summary line) |
| Real quit, no seam (throwaway probe, not committed; run before the script-loop guard was added): real `Main` scene, Solo, real Quit game | the process exited by itself with code 0 about 2.6 s after the press |
| Runner parse check | no output (pass) |
| Fresh-clone boot check of the final commit (no `.godot/`) | no output (pass) |
| Full suite | **910 passed, 3 failed, 913 total** |

The 3 failures are the same ones that fail identically on untouched `origin/main` on this machine and pass on Linux CI; not from this change:

- `flail_ball_does_not_clip_head` (ball goes 6.9 px into a held sword)
- `online_bots_only_match_starts_offline_and_says_so` (link stays on "connecting")
- `career_phone_page_shows_compact_line_and_expands_503` (expected HTML snippet not found on Windows)

### What the full suite caught in the first version

- Pointing every title card's Down at Quit broke `title_screen_offers_couch_online_and_solo_and_no_pc_seat_control` (Down walks Couch, Online, Solo). Fixed: Quit sits one step past the last card and the chain is untouched.
- That test then pressed A on Quit, which really quit the scenario runner: the run ended mid-suite with exit code 0 and no summary line. `quit_game` now returns without quitting when the main loop is a `-s` script (the runner). The game's own main loop has no script, so the real quit is unchanged.

**Possible runner follow-up for the owner:** a suite run can end silently with exit code 0 and no summary line if anything quits the process mid-run. That reads as green to anything that checks only the exit code. A check that the summary line exists would close that gap.

## Screenshots (1600x900)

- `title_quit_button.png`: the title screen with Quit (Q)
- `settings_quit_game.png`: the Settings panel with Quit game at the bottom (the panel is one row taller, so it covers a little more of the lobby's right column)

## Translations

`SETTINGS_QUIT_GAME`, `QUIT_CONFIRM_TEXT`, `QUIT_YES`, `QUIT_NO` and `TITLE_QUIT` have all nine columns. The eight non-English ones are drafts for the volunteer proofreaders.
