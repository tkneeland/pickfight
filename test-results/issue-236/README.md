# Issue #236 evidence: Teams mode

Branch `feat/issue-236-teams`, on main `94e55de`.

## What was run

- **Full suite.** Every scenario in `SCENARIO_NAMES` was run as 5 parallel shards of `--scenarios=`, with `--fixed-fps 60`, on Godot 4.6.2 headless. The result was **279 passed, 0 failed, 279 total** (`full-suite.txt`).
- **Fresh-clone boot check.** `godot --headless --path <clone> --quit` shows no `ERROR`, `SCRIPT ERROR` or `Failed to load script` lines.
- **New scenarios on main's code.** The 9 new scenarios were run with `origin/main`'s versions of the changed sources checked out into the worktree, then those files were restored with `git checkout HEAD -- ...`. No `git stash` was used. On main's code, all 9 fail (`new-scenarios-on-main.txt`, 0 passed, 9 failed). With this branch's code, all 9 pass.
  - The sources swapped in were `scripts/Player.gd`, `RoundManager.gd`, `ControllerServer.gd`, `LobbyScreen.gd`, `NameTags.gd`, `Announcer.gd`, `Sfx.gd`, `Bot.gd`, `controller/index.html` and `tools/stub_lobby_roster.gd`.
  - `teams_ffa_unchanged_when_off` fails on main only because main's players have no `team` or `is_teammate()`. Its free-for-all assertions are what main already does.

## Screenshot

`lobby-teams.png` is a windowed 1280×720 run of `scenes/Main.tscn` in a Teams lobby, "first to 3". The roster was a stub, with a stand-in QR code.

- There are 5 players. Alex picked Red, and Sam and Kim picked Blue. Jo and Lee had not picked, so they were auto-balanced onto Red and are marked "(auto)".
- It shows the two rosters in the team colours, and each player's swatch in their own colour.
