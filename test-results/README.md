# Proof of work -- issue #27, heads tunnelling through heads

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. #14's evidence is in
history at `a753c65:test-results/issue-14/`.

Branch `fix/issue-27-head-tunnelling`, Windows, local Godot 4.6.2.

| Criterion (issue #27) | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| No roster head passes through another head in one step | `roster_heads_do_not_tunnel_head` | `issue-27/scenario-suite.txt` | PASS |
| Same, under a different history (roster reversed) | `roster_heads_do_not_tunnel_head_reversed` (new) | `issue-27/scenario-suite.txt` | PASS |
| Both scenarios catch the bug | the same two scenarios against `main`'s `WeaponHead.gd` | `issue-27/red-on-main.txt` | FAIL on main, as expected |
| Holds across histories, not just the suite's one | 20 histories: every weapon as the verdict after 4 different prefixes | `issue-27/history-sweep.txt` | 0 / 20 red |
| Nothing else regressed | full suite, 52 scenarios | `issue-27/scenario-suite.txt` | PASS |
| Boots on a fresh clone | `godot --headless --path . --quit`, no `.godot` present | `issue-27/boot-check.txt` | PASS |

`issue-27/tunnel_loop.gd.txt` is the harness behind the history sweep. It
extends the scenario runner, so it has to sit in the scratchpad to run:
`-s <path>/tunnel_loop.gd -- --weapon=staff,sword,axe,dagger`.

## Cause

The breach was chaotic rather than a state leak. Earlier pairs change the
physics server's solver order, which moves sub-pixel timing. The same dagger
charge was green on a fresh pair and red after `staff,sword,axe`. Two defects
let a head through:

1. **The world sweep pre-empted the pair check.** `_integrate_forces` ran the
   head-vs-head check only when the world sweep found nothing. On the breach
   tick the world sweep fired against the other player's body, so the pair
   check was skipped with the other head 22 px away. Now both contacts are
   found and the earlier one is applied.
2. **Pairs that start a step touching were never checked.** After a
   correction, the next step starts with the heads in contact, and
   `_first_circle_contact` skipped any such pair. Being driven through the
   line of centres went unseen. A touching pair whose centre line flips
   during the step is now a contact at fraction 0.

Fixing only (1) moved the breach from dagger 135 deg to dagger 45 deg. It
took both fixes.
