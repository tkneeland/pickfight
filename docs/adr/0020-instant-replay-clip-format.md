# 20. Instant replay clip format and memory cap

- Status: Accepted
- Date: 2026-10-01

## Context

Issue #329: the host presses a key and the last ~10 s of play is saved for the
trailer and for sharing. Godot 4.6 cannot write GIF or video from script, and
viewport textures can be empty in headless runs.

## Decision

- `scripts/ReplayBuffer.gd` keeps a ring of viewport frames, grabbed at 12 per
  second and downscaled to 256x144 RGB8.
- **Memory cap:** 120 frames (10 s) x 256x144x3 = 13,271,040 bytes (about
  13 MB). Older frames are dropped; the cost does not grow with match length.
  Runtime cost is one grab and resize per 5 frames at 60 fps.
- **Format:** a PNG frame sequence in `user://clips/clip_<timestamp>/frame_NNNN.png`.
  PNG is the one image format Godot writes natively, and a folder of frames
  imports straight into any editor or `ffmpeg -framerate 12 -i frame_%04d.png`.
- **Key:** F9 (unbound elsewhere), handled in `RoundManager._unhandled_input`.
  A toast shows the saved path.
- `push_frame()` is public, so scenarios feed synthetic images to test the
  bound and the save path. Capture is skipped under the headless display
  driver.

## Consequences

Clips are low resolution and 12 fps, enough for sharing, not for broadcast.
