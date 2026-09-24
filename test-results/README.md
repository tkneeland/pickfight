# Proof of work -- issue #12, roster and round-loop fixes

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. Produced on
`fix/issue-12-roster-round-loop` (rebased onto `main` at `2e97d23`, after #10 merged), local
headless Godot 4.6.2.

| Criterion | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| A claim that disconnects while waiting is released, and no round starts on it | `waiting_expires_disconnected_claims` | `issue-12/scenario-all.log` | PASS |
| A round with no connected survivor ends with no winner after the grace period; a reconnect inside it keeps the round going; the claims are then released | `abandoned_round_ends_without_winner` | `issue-12/scenario-all.log` | PASS |
| Both new scenarios fail against the pre-fix `RoundManager.gd` | same two scenarios, run with `main`'s `RoundManager.gd` swapped back in | `issue-12/new-scenarios-before-fix.log` | PASS (both FAIL as expected) |
| No regressions | `--all`, 26/26 | `issue-12/scenario-all.log` | PASS |
| The project boots | `godot --headless --path . --quit` | `issue-12/boot-check.log` | PASS |
| Fresh clone parses (CLAUDE.md `class_name` rule) | this checkout has no `.godot/` class cache at all, so the `--all` run above is a fresh-clone run | `issue-12/scenario-all.log` | PASS |

Doc and comment corrections (README, CLAUDE.md, ADR-0007 amendment, stale
"respawn" comments, the qrencode hint) are prose only; review them in the diff.

The `CapsuleShape2D` warning during `weapon_silhouette_matches_head_shape` and
the qrencode warning at boot are expected: the first is the scenario proving
the fallback silhouette fires, and the second is `qrencode` not being installed
on this machine.
