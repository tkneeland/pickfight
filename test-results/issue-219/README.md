# Issue #219 test evidence

- **What was run:** the full scenario list (265 scenarios) through `tools/scenario_runner.gd` with `--headless --fixed-fps 60`, split into 5 parallel `--scenarios=` shards (Godot 4.6.2, Windows 11). A fresh-clone `--quit` boot check followed.
- **Base:** branch `feat/issue-219-howto-demos`, rebased onto origin/main `80e2f7d`. It was started on `546f9b7`.
- **Result:** 265 passed, 0 failed, 265 total. The full log is in `full-suite.txt`.
- **Boot:** a fresh clone boots with no `ERROR`, `SCRIPT ERROR` or `Failed to load script` lines. Main dropped the qrencode shell-out in #214, so the old qrencode "Could not create child process" line no longer appears.
- **Fail on main:**
  - Run against main's `scripts/LobbyScreen.gd`, all three new scenarios fail: 0 demos.
  - Run against main's SfxHooks, Juice, HitFeedback and Announcer, `lobby_how_to_play_demos_leak_nothing` fails. Demo players' `strike_landed`, `eliminated` and `body_entered` connect to SfxHooks, 21 sounds play, and 8 hitmarkers appear.
- **Screenshot:** `lobby-1280x720.png` shows the lobby in a windowed 1280x720 run with 8 claimed phones. A stand-in join QR and URL were injected because the probe uses the stub roster and has no network.

## Lobby frame time, 8 claimed phones

The probe is a throwaway script, not committed. It loads `scenes/Main.tscn` in its lobby with the stub lobby roster (8 slots) and times the wall clock of each frame after warm-up, with the demos on and then with them stopped.

| run | demos | mean | p95 | p99 | budget |
|---|---|---|---|---|---|
| headless, 60 Hz | on | 1.59 ms | 1.98 ms | 2.47 ms | 16.7 ms |
| headless, 60 Hz | off | 0.09 ms | 0.10 ms | 0.14 ms | 16.7 ms |
| headless, 120 Hz (`--demo`) | on | 1.46 ms | 1.68 ms | 2.04 ms | 8.3 ms |
| headless, 120 Hz (`--demo`) | off | 0.09 ms | 0.10 ms | 0.13 ms | 8.3 ms |
| windowed 1280x720, vsync off | on | 4.80 ms | 6.00 ms | 12.2 ms | 16.7 ms |
| windowed 1280x720, vsync off | off | 1.04 ms | 1.35 ms | 1.92 ms | 16.7 ms |

The four demos cost about 1.5 ms of CPU per frame, which is the physics and scripts for six puppet players. Rendering them adds about 2.5 ms more. The first frames of the windowed runs include one-off spikes of about 50 ms for window setup, in both the on and off runs.
