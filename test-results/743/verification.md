# #743 verification

Commit d31fa68 on `feat/issue-743`.

| Check | Result |
|---|---|
| `tools/capture_clips.sh` lava (3 s) | `lava.avi` 55.9 MB, AVI header 1920x1080; frame `lava-2.0s.png` shows bots, HUD, lava, no overlay |
| soccer (3 s) | `soccer.avi` 54.8 MB, "Done recording movie" |
| podium (3 s) | `podium.avi` 81.5 MB; frame `podium-1.0s.png` shows the eight-player podium |
| Full suite `--fixed-fps 60 --all` | 909 passed, 1 failed (`axe_wins_clash_against_every_weapon`, known macOS-only) |
| Fresh clone boot grep | no output (clean) |
| `pgrep -fl "godot.*capture_clips"` after runs | nothing (no window left open) |

Not recorded this session: brawl/ctf/weapons at full length. Clips include the stage card and countdown; trim the start in an editor. `.avi` output is gitignored and not committed.
