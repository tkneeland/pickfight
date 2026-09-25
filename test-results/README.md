# Proof of work: issue #71, axe_head_holds_side_near_vertical in full runs

Cleared and recaptured per `docs/agents/testing.md`: this root holds only the latest work package's evidence. The previous package (#59, stage traversal) is in commit `d2fa0a7`: `git show d2fa0a7:test-results/README.md`.

## Finding

No state leaks from `four_phones_claim_four_slots`. The axe scenario fails **alone** on `main` too. It has failed since #48 merged (`e6b0cc5`) and passed on the commit before (`3c192d4`), whether it ran alone or after `four_phones_claim_four_slots`.

The scenario runs about 13 s from `PARK_POSITION`, which is clear air for only about the first second. After that the player is standing on the arena. Aimed down, the axe rests on the floor, and #48's flip hold correctly keeps the side it has, because the flip would carry the bit through the floor. The fix gives the scenario a stage without the arena, which is what it was written for. No assertion changed.

## Evidence

| File | What it shows |
| --- | --- |
| `issue-71/red-pair-before-fix.txt` | Red: the pair on `main` (8118a72), before the fix |
| `issue-71/red-axe-alone-on-main.txt` | Red: the axe scenario alone on `main`. It does not need the pair |
| `issue-71/bisect-around-48.txt` | Passes before #48, alone and in the pair. Fails alone from #48 on |
| `issue-71/green-pair.txt` | Green: the pair after the fix |
| `issue-71/green-axe-alone.txt` | Green: the axe scenario alone after the fix |
| `issue-71/mutation-deadband-zero-goes-red.txt` | The test still bites: with `HEAD_FLIP_DEADBAND = 0` it fails with 39 to 40 flips per wobble |
| `issue-71/scenario-suite.txt` | Full suite, `-- --all`: **97/98**. The axe scenario passes |
| `issue-71/boot-check.txt` | Fresh-clone boot: clean |

The one suite failure is `roster_heads_do_not_tunnel_head_reversed`, which is **#77**. It fails on `main` with the same numbers (see #77), passes alone, and has nothing to do with this change.
