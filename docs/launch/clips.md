# Gameplay clips for the trailer and social (#743)

`tools/capture_clips.gd` records full-resolution gameplay with Godot's Movie Maker: 1920x1080, 60 fps, MJPEG `.avi`. The owner cuts the trailer from `trailer-shot-list.md`; these clips are raw material for it and for TikTok, Shorts, Reels and Reddit. The in-game replay key (F9, #329) only saves 256x144 at 12 fps, so it is for finding moments, not for footage.

Every clip is eight seats on Hard bots (the host seat idles), daylight, no round modifier, the HUD as in game. Clips are **never committed** (`*.avi` is gitignored; one is 50 to 100 MB for 10 seconds).

## Run it

```
tools/capture_clips.sh <out-dir>              # every clip, one window at a time
tools/capture_clips.sh <out-dir> brawl lava   # only these
CLIP_SECONDS=3 FRAME_PNG=2 tools/capture_clips.sh <out-dir> soccer   # quick check
```

Run it windowed, by hand (headless Godot does not render). Run `godot --headless --path . --import` once in a fresh checkout first, or the picture is blank grey. The wrapper runs each clip under a 180 second `perl alarm`, checks no capture window is left open, and prints the `.avi` size. Movie Maker renders slower than real time: expect about a minute per clip, and close other heavy apps.

Direct form for one clip:

```
perl -e 'alarm 180; exec @ARGV' godot --path . --write-movie <out>/brawl.avi --fixed-fps 60 --resolution 1920x1080 -s tools/capture_clips.gd -- --only=brawl
```

Movie Maker records at the project's viewport size, not `--resolution`, so the wrapper writes a temporary, gitignored `override.cfg` (1920x1080) for the run and removes it after. Running the direct form alone gives 1600x900 unless you add that file yourself.

Flags after `--`: `--only=<clip>` (required), `--seconds=<n>` (shorter clip), `--frame-png=<sec>[,<sec>]` plus `--out=<dir>` (also save 1920x1080 PNGs at those seconds, to inspect a frame without a video player). The script quits on its own after the clip, or after a hard timeout of clip length + 25 s (exit 1).

The recording starts with the process, so the first few seconds are the stage card and countdown; the clip length counts from the first frame of play. Trim in the edit. Any lobby frame would use a sample join address, never the machine's own (as in #723); none of these clips shows the lobby.

## Clips

| Clip | Stage and mode | Length | Shot-list beat |
|---|---|---|---|
| `brawl` | Bowl, Classic, free-for-all | 12 s | 2 (title brawl), 5 (Classic) |
| `lava` | Furnace, Classic | 10 s | 1 (hook), 7 (hazards) |
| `soccer` | Pitch, Soccer, teams | 12 s | 5 (Soccer) |
| `ctf` | Stronghold, Capture the Flag, teams | 12 s | 5 (Capture the Flag) |
| `weapons` | Colosseum, Classic, a different weapon in each hand | 10 s | 6 (weapons) |
| `podium` | Flatlands, then the victory podium for eight | 8 s | 9 (payoff) |

Not covered (film or capture by hand): the phone and join shots, the Online lobby, King of the Hill. Add a clip by adding a row to `CLIPS` in `tools/capture_clips.gd` and its name to the default list in `tools/capture_clips.sh`.
