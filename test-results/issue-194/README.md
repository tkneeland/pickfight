# Issue #194: test evidence

- **What ran:** the full scenario list (245 scenarios) under `--fixed-fps 60`, split across 5 parallel Godot 4.6.2 headless processes, plus the fresh-clone boot check. The full log is in `full-suite.txt`.
- **Base:** branch `feat/issue-194-phone-ux` on top of main `6d4ec9d` (rebased).
- **Result:** 245 passed, 0 failed, 245 total.
- **Fails before the fix:** the four new page checks were also run against main's `controller/index.html`, and all four failed.
- **Browser hit test:** headless Chrome tapped the centre of `#name` with the lobby showing. On main the tap landed on `lobby`; on this branch it lands on `name`.
- **Boot:** the fresh clone booted with one ERROR, qrencode "Could not create child process". qrencode isn't installed on this machine, so this is an environment issue, not a code one.
