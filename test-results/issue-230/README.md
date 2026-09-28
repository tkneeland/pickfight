# Issue #230 evidence

- `full-suite.txt`: the full scenario list (267 scenarios) run headless with `--fixed-fps 60` as 5 parallel shards, on this branch off main `f4e5982`. **267 passed, 0 failed, 267 total.** The fresh-clone boot check (`godot --headless --path <fresh clone> --quit`) printed no ERROR, SCRIPT ERROR or "Failed to load script" lines. There is no qrencode since #224.
- `lobby-settings-1280x720.png` and `lobby-settings-1920x1080.png` show the host lobby with the Settings panel open. They were taken with a windowed (non-headless) run at `--resolution 1280x720` and `--resolution 1920x1080`, reading `get_root().get_texture().get_image()` (headless has no renderer). The small in-round join QR and URL are hidden, and the panel sits below the last how-to-play caption.
