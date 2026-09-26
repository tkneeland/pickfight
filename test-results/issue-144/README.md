# Issue #144: large stages for 5+ players

- `Pistons.png`, `Overpass.png`, `Ziggurat.png`: the three new large stages, windowed, under the camera Main gives them (zoomed out to each stage's `view_size`), with a real body on each of the 8 spawns after 90 ticks. `Flatlands.png` is a normal stage under the same tool, still at zoom 1.
  Captured with `godot --path . -s tools/capture_stage_screenshots.gd -- --out=$PWD/test-results/issue-144 --stages=Pistons,Overpass,Ziggurat,Flatlands`.
- `stage-scenarios.txt`: every stage, rotation, lava and background scenario, plus the two new ones (`large_stages_only_with_five_or_more_players`, `large_stage_camera_fits_view_with_eight_players`).
- `ringout.txt`: `tools/ringout_probe.gd` with 8 random bots (new `--players`). The large stages fall in the same range as Flatlands with 8 players (about 1.6 to 2.7 falls per bot-minute), and well under an existing small stage packed with 8 (Bulwark, 5.5).
- `full-suite.txt`: the full suite via psuite (fresh-clone boot check plus every scenario).
- `gen_large_stages.py`: the generator the three .tscn files were written with (`python3 gen_large_stages.py <repo>`); kept here as evidence, not part of the build.
