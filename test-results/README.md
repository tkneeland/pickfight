# Proof of work -- issue #38, head tunnelling on macOS

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. #34's evidence is in
history at `844725e:test-results/issue-34/`.

Branch `fix/issue-38-tunnel-graze`, macOS 15.7.7, local Godot 4.6.2.

**Root cause:** a world contact stops a head partway through a physics step,
and the head-vs-head sweep had assumed the head travelled the whole step. So
a pair that "met after the world contact" was deferred, and the other head
then ran straight through the seated one. The fix (`3ef5ffd`) re-sweeps the
rest of the step, with this head held where the world stopped it. The
scenario's breach test (`80bd086`) now allows the same
`PAIR_OVERLAP_ALLOWANCE` the physics does, so a 0.03 px graze (#16's axe) is
not a tunnel.

| Criterion | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| The failure reproduces on clean main | both roster tunnel scenarios at `136061d` | `issue-38/red-on-main.txt` | RED, as expected |
| The new breach criterion alone does not hide it | new criterion, `WeaponHead.gd` reverted | `issue-38/red-without-fix.txt` | RED, as expected |
| With the fix, both scenarios pass standalone | 3 runs each | `issue-38/standalone-x3.txt` | PASS |
| Independent of test history | 25 weapon-order histories before the dagger sweep | `issue-38/history-sweep.txt` | PASS, 0 of 25 red (main: red) |
| Nothing else regressed | full suite on the original base `136061d`, 57 of 57 | `issue-38/scenario-suite.txt` | PASS |
| Still passes after the rebase onto main `844725e` | both roster tunnel scenarios | run at rebase | PASS |
| #16's axe graze no longer counts as a breach | #16 tip without the fix | `issue-38/issue-16-crosscheck.txt` | RED without the fix. The run with the fix is #16's own full suite on top of this branch (#42) |
| Boots on a fresh clone | throwaway clone, grep for `SCRIPT ERROR` / `Failed to load script` | `issue-38/boot-check.txt` | PASS |
