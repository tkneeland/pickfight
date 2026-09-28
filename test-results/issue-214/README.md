# Issue #214: the join QR encoded in-game

Run on Windows 11, Godot 4.6.2, branch `feat/issue-214-qr-encoder` rebased onto main `4f51b61`.

- `full-suite.txt`: the full scenario list (261) in 5 parallel `--fixed-fps 60`
  shards: **261 passed, 0 failed, 261 total**.
- New scenarios: `qr_encoder_matches_reference_matrices` (10 fixture cases in
  `tools/qr_fixtures.txt`, from python-qrcode 8.2 via `tools/gen_qr_fixtures.py`,
  matched module for module and on the chosen mask) and
  `join_qr_shown_without_qrencode` (fails on main's ControllerServer.gd: no QR on
  a host without qrencode).
- `opencv-decode.txt`: QrEncoder PNGs decoded by OpenCV 5.0.0
  `cv2.QRCodeDetector`. Every EC M image (what the game draws) decodes to its
  URL as rendered; one EC L image needs a wider white border for OpenCV.
  `qr_longest_url_M.png` and `qr_192.168.1.42_M.png` are two of them.
- Fresh-clone boot check: **no ERROR lines at all**. The qrencode "Could not
  create child process" ERROR that main prints on a host without qrencode is
  gone.
- Not tested with a real phone camera here.
