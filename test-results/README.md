# Proof of work -- issue #29, playtest readiness

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. #19's evidence is in
history at `4d44b34:test-results/issue-19/`.

Produced on `fix/issue-29-playtest-readiness` (stacked on #19's branch), on
Windows with local Godot 4.6.2.

| Criterion | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| No single strike kills from full health, for any roster weapon | `no_single_strike_kills` (new) | `issue-29/scenario-suite.txt` | PASS |
| ...and that scenario catches the bug | same scenario with the cap disabled: axe deals 110 and kills | `issue-29/strike-cap-before-fix.txt` | PASS (FAILs as expected) |
| Highrise and Furnace still spawn safely and still ring out | `stage_spawns_are_safe`, `every_stage_can_ring_out` | `issue-29/scenario-suite.txt` | PASS |
| No regressions | `--all`, 40/40 | `issue-29/scenario-suite.txt` | PASS |
| The real game runs a full rotation with two network controllers, including `--random-weapons` | windowed smoke harness (scratch, not committed): real `Main.tscn`, two WebSocket clients, HTTP fetch of the controller page | `issue-29/smoke-random-weapons.txt` | PASS: 12 rounds, all 5 weapons seen, no script errors |

Reviewed but not machine-provable here, so check them in the first real
session:
- The join label shows one reachable URL; `169.254.*` is filtered out.
- A second finger on the phone no longer scrambles the drag.
- The firewall and binary-name steps in the README match what you see.
