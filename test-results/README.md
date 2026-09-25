# Proof of work: issue #82, the turn guard and other heads

Cleared and recaptured per the evidence policy in `docs/agents/testing.md`:
this root holds only the latest work package's evidence. Earlier evidence is
in git history:

- #77 (with #71's integration run): `72669aa:test-results/issue-77/`
- #75: `5f163a0:test-results/issue-75/`
- #52: `cb30530:test-results/`
- #59: `d2fa0a7:test-results/`
- #47, #61 and damage-display: `8f32c86:test-results/`

Branch `fix/issue-82-turn-guard-heads`, from `origin/main` at `faeee6b`
(#71 and #77 merged). macOS, local Godot 4.6.2, headless.

## It was real

`WeaponHead.guard_turn` traced the per-tick turn against terrain only. The
pair sweep traces the anchor's translation at the facing the step *began*
with, so it cannot see the circles orbit the anchor either. Built
deterministically in `turn_does_not_carry_blade_through_head`: a player
stands on a floor, aimed just above level at minimum reach, and is commanded
straight up. On the first fast tick of the turn, a still head (real
`WeaponHead` script, on the head layer, with steps behind it) is parked just
ahead of a far blade circle. Measured on `Player.weapon_head_circles_world()`:

| Weapon | Before the tick | After one tick, on `main` |
| --- | --- | --- |
| sword (0.33 rad tick) | 7.62 px clear, ahead of the blade | 13.28 px on the **far** side, 7.80 px gap, never touched |
| boomstick (0.38 rad tick) | 12.07 px clear, ahead of the blade | 14.23 px on the **far** side, 8.43 px gap, never touched |

## The fix

`guard_turn` also traces each circle along its arc against other heads'
circles (whole circle against whole circle, falling back to the centre for a
pair already touching). It moves the head back to leave the first circle to
meet one just short of touching. After a head stop, it records that pose as
the step's start so the pair sweep catches the anchor's own travel through
the step. Two things were tried and dropped, both measured on this scenario:

- **Without the step-start hand-off**, both weapons still went through on the
  second tick.
- **With only the centre traced**, as for terrain, the heads were left 2.0 and
  2.3 px overlapped. That is at `PAIR_OVERLAP_ALLOWANCE`.

## Evidence

| Claim | Proven by | Evidence | Verdict |
| --- | --- | --- | --- |
| Red: on `main`'s `WeaponHead.gd`, the turn carries both blades through the parked head | `turn_does_not_carry_blade_through_head` | `issue-82/red-on-main.txt` | FAIL on main, as expected |
| Green: with the fix, the parked head stays on its side of the blade for all 6 watched ticks (pushed along, gap about 0 px) | `turn_does_not_carry_blade_through_head` | `issue-82/green-on-branch.txt` | PASS |
| Nothing else regressed | full suite: 129 of 129 | `issue-82/scenario-suite.txt` | PASS |
| A fresh clone (no `.godot/`) boots with no `SCRIPT ERROR` or `Failed to load script` | the CLAUDE.md boot check | `issue-82/fresh-clone-boot.txt` | PASS |
| How it feels to swing a sword into a blocking head | a playtest | none | NEEDS PLAYTEST |
