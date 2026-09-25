# Proof of work: issue #73, parallel scenario runs collide on the controller port

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. The previous package
(#52) is in history at `cb30530:test-results/`.

Branch `fix/issue-73-parallel-port` (rebased on origin/main `9ed7319`), macOS, local Godot 4.6.2.

| Criterion | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| Two `--all` runs started at the same time (04:20:15Z, one in the worktree, one in a fresh clone) both pass `four_phones_claim_four_slots` and `buzz_reaches_only_its_phone`, each on its own OS-picked port (A: 64997/65010, B: 64995/65012) | full suite x2, run in parallel | `issue-73/parallel-run-A.txt`, `issue-73/parallel-run-B.txt` | PASS |
| The collision was real: two parallel runs forced onto one port (`--port=18480`, what every run did before) fail both scenarios with `cannot listen ... (error 22)` | the two scenarios x2, run in parallel | `issue-73/fixed-port-collides.txt` | PASS |
| `--port=<n>` still works (HTTP n, WebSocket n+1) | same file: run A binds 18480 and passes `buzz_reaches_only_its_phone` | `issue-73/fixed-port-collides.txt` | PASS |
| Game behaviour unchanged: ControllerServer defaults stay 8080/8081; port read-back only happens when a port is 0 | code review of `scripts/ControllerServer.gd` diff | PR diff | PASS |
| Boots from a fresh clone | `git clone -q . <scratch> && godot --headless --path <scratch> --quit 2>&1 \| grep -E "SCRIPT ERROR\|Failed to load script"` prints nothing | `issue-73/boot-check.txt` | PASS |

Full suite, each parallel run: 107 of 109. The two failures are not #73's and
fail the same way on untouched origin/main `9ed7319` run alone
(`issue-73/baseline-origin-main-alone.txt`, also 107 of 109):

- `axe_head_holds_side_near_vertical`: order-dependent, tracked in #71.
- `roster_heads_do_not_tunnel_head_reversed`: one boomstick charge at
  45 deg / 1800 px/s tunnels on this machine; it passes when run alone.
