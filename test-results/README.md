# Test results

Evidence for the latest work package only: issue #83 (the boomstick's head ending up behind its own
body). The previous package (#86, the charge sweep's dependence on suite history) is in commit `6debdd7`:
`git show 6debdd7:test-results/README.md`.

## Finding

This is a real bug, not a test artefact. A bounce pad launches a body at 2000 px/s, so a player aiming
the boomstick straight up under a ceiling gets there in normal play. The muzzle stops on the ceiling
and the body keeps coming. The joint chain holding `min_reach` (body, pin, haft of 0.05, groove, head
of 0.1) gives way, and the body runs 22.9 px past its own anchor. For 7 ticks the gun points up through
the body and the haft line runs backwards to the anchor. With the head's world sweep turned off it
still goes 10 px behind, so the cause is the joint and not the sweep.

The fix is `Player._hold_min_reach()`, which runs between steps. Once the anchor is more than 2 px
inside `min_reach` and the head is stopped on something (touching it, or caught by the world sweep
that tick), it takes out only the part of the body's velocity that is still carrying it onto its head.
It never pushes the body back or speeds it up. A head in clear air is left to the joint. A first
version without that condition also stopped bodies in clear air, and in the full suite it failed
`weapon_damage_matches_roster` (axe 85.3 against 90) and `roster_heads_do_not_tunnel_head_reversed`.
With the condition, both pass.

The #77 forced charge sets both bodies' velocity every tick, which overrides any fix, and it does
nothing that happens in play. It is unchanged, and no test relies on it.

## Evidence

All measurements are taken on `Player.weapon_head_circles_world()`: the anchor's reach along the
direction the gun's physics circles run.

| File | What it shows |
| --- | --- |
| `issue-83/red-new-scenario-on-main-code.txt` | Red: `pad_launch_keeps_head_ahead_of_body` with `scripts/Player.gd` from `main`. The body is 22.9 px past the anchor for 7 ticks |
| `issue-83/green-new-scenario.txt` | Green: on this branch the anchor stays at least 7.2 px ahead of the body |
| `issue-83/triage-midair-charge-probe.txt` | Triage probe, not committed as a scenario: mid-air boomstick charges. With the speed set once, as play does, the worst case goes from 34 px behind for 7 ticks to 10 px for 1 to 2 ticks. Held every tick, as in the #77 charge, nothing changes |
| `issue-83/full-suite.txt` | Full suite, `-- --all`, on the branch rebased onto `origin/main` at `ffb46a5` |
| `issue-83/boot-check.txt` | Fresh-clone boot check |
