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

## Addendum (2026-10-29, #1128): a separate sharp ring for Play of the round

Play of the round (#704) played the 256x144, 12 fps F9 ring full-screen, which
looked pixelated (about 6x upscaled) and choppy (6 fps at half speed).

Options weighed: a separate short high-res ring; compressed in-memory frames;
a state replay re-rendered by the game. Chosen: **a separate short high-res
ring** inside `ReplayBuffer.gd`. Compression costs CPU on the hot path and a
state replay needs a deterministic re-sim the game does not have.

- **What it holds:** the last 5 s (120 frames) at 640x360 and 24 fps, packed
  as RGB565 (2 bytes a pixel). Frames are shown at half speed, so 12 distinct
  frames a second, drawn with linear filtering.
- **Memory cap:** 120 x 640 x 360 x 2 = 55,296,000 bytes (52.7 MiB, under the
  64 MB target), fixed whatever the match does. While a grab is being shrunk
  at most 2 resize jobs run, so at most 2 window-sized source frames are alive on
  top (transient). When both are busy the next grab is dropped, never waited
  for (#1138), and a buffer freed outside the tree finishes its jobs on
  predelete.
- **Shape:** frames fit inside 640x360 with the window's aspect kept (a 16:10
  window is 576x360, an ultrawide 640x274), so no shape holds more pixels than
  640x360 and the cap above stands (#1137).
- **Selection:** the replay window is cut by each frame's grab time, not by
  index, so a host below 24 fps or one that dropped grabs still ends the clip
  half a second after the KO (#1139).
- **Cost:** the viewport grab runs at 24 a second (it ran at 12); the resize and
  RGB565 pack run on `WorkerThreadPool`, not the main thread. Every second grab
  also feeds the F9 ring as before.
- **Unchanged:** the F9 ring (120 frames of 256x144 RGB8, 13 MB), its PNGs and
  `clip.gif` (12 fps, 8 cs delay).
- **Online:** `RemoteEffects` owns a `ReplayBuffer` too, so the joiner's replay
  is the same code, size and fps as the host's.
