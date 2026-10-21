# #756 verification

Commit 7bf0266 on `feat/issue-756`.

| Check | Result |
|---|---|
| `--scenarios=name_echo_756,name_filter_732` | 2 passed, 0 failed |
| Full suite `--fixed-fps 60 --all` | 911 passed, 1 failed (`axe_wins_clash_against_every_weapon`, #755) |
| Fresh clone boot grep | no output (clean) |

Echo goes to phones and to Online PC seats. RemoteClient's frame `match` has no `name` arm, so the client ignores the frame safely; it does not update its saved name. The echo from `_fresh_claim` rarely fires for phones, since the nickname is empty at claim time. The later `name` frame is echoed.
