# #689 verification: 18 Steam achievements

- `pf-atlas.sh run '689'`: 25 passed, 0 failed. That covers 18 trigger scenarios, each with a negative control, plus bots never unlocking, Solo excluding Untouchable and Last Life, idempotent unlock calling the Steam stub, persistence off in tests, the remote PC seat message, the toast, and names, docs and 9-locale translations.
- Full suite: 879 passed, 1 failed of 880. The failure is `axe_wins_clash_against_every_weapon`, the known macOS-only one.
- Fresh-clone boot check: no output (clean).
- Steam path is tested against a stub only, because GodotSteam isn't present in tests. The owner enters the 18 achievements in Steamworks from `docs/steam-achievements.md`.
- Gone Fishing and Boo! are tested with stamped reel/boo events, the real ghost boo and a real hazard part. The real rod hook is not fired end to end.
