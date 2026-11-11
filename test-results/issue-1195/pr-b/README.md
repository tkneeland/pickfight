# #1195 PR B evidence (#1232: adaptive interpolation delay, 60 Hz snapshots)

Godot 4.6.2-stable, macOS, headless, `--fixed-fps 60`, local in-process relay,
a checkout with no `.godot/` import cache. Commands are in
`docs/plans/1195-online-latency.md` section 5 (branch `plan/issue-1195`).

| # | Criterion | Evidence | Verdict |
|---|---|---|---|
| V5 | 60 Hz within the per-seat budget: 60.0 Hz, 3 fulls in 3 s, 17,695 B/s (budget 40,960) | `scenario-bandwidth.txt` | PASS |
| V6 | Host capture + delta + encode, 8 players: mean 1,610 us (bound 4,000), so D4's stay-at-30 fallback is not needed | `capture-cost.txt` | PASS |
| S5/S6 | Delay settles at 40 ms for 16 ms gaps, 66 for 33 ms, stays 100 with 10 gaps, snaps to 100 on a 600 ms gap, effects follow; 500 ms of slew moves it 30.00 ms; the two INTERP_MSEC scenarios pass unchanged | `scenario-S5-S6.txt`, `scenario-S9.txt` | PASS |
| V16 | Game-added budget: 116.7 ms before, 48.3 after, difference 68.3 (>= 50) | `scenario-S9.txt` | PASS |
| V7 | Real-network felt delay drops >= 50 ms | human-gated; PR A's "before" run was not done either (no `pr-a/real-network.md` to copy) | BLOCKED (human) |
| V8 | Input-on-change decision (D5) | human-gated; `send_input_on_change` ships off, per D5 | BLOCKED (human) |
| V9 | Full suite | `scenario-all.txt`: 1249 passed, 13 failed of 1262 on the first run. 11 are font, preview and music import failures that fail identically on unmodified `origin/main` in the same un-imported checkout (listed at the end). 2 were this branch's and are fixed: `remote_client_reports_felt_delay_1195`'s floor read the fixed `INTERP_MSEC`, now the drawn `interp_msec()`; `online_client_enter_readies` reset Ready locally and the next snapshot's mirror of the host's ready (every frame at 60 Hz) undid it, now it un-readies as a click does. Re-runs pass. CI (imported) is the full check | PASS (no new failure) |
| V10 | Runner parse, dispatcher arm count, list check | `runner-parse.txt` | PASS |
| V11 | Fresh-clone parse | `fresh-clone.txt` | PASS |
| V14 | FEATURES | PR diff | PASS |

Deviation from the plan's "one in-place edit": two more existing scenarios were
edited in place (above), each because PR B's behaviour change made its old
assumption wrong; neither weakens what it checks.
