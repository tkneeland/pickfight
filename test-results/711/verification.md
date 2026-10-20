# #711 verification — Steam on-screen keyboard

Commit bf7c01c.

| Check | Result |
|---|---|
| `pf-atlas.sh run '711|deck|remote_client|feedback|settings'` | 73/73 |
| Full suite | 907 passed, 1 failed, 908 total (only known macOS-only axe) |
| Fresh-clone boot | no output (pass) |

Calls `showFloatingGamepadTextInput(0,x,y,w,h)`, falling back to `showGamepadTextInput` + `gamepad_text_input_dismissed`/`getEnteredGamepadTextInput`. Accepted deviation: a pad-active flag in the SteamPlatform autoload, because the existing `HostControls._pad_active` is per-lobby and unreachable from RemoteClient and the feedback box. Real Deck unverified.
