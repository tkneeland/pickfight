# Issue #23 — heads tunnel through other heads

## The defect

`WeaponHead` is `lock_rotation = true`. Its facing does not live in the body
transform at all: `Player._update_weapon_visual` rewrites every swept circle's
local `position` and `rotation` from the aim, once a tick.

Both sweeps reconstructed the pose the head held at the *start* of the step by
taking the anchor from the start (`_previous_position`) and the circle offsets
from `node.transform` — which, by the time `_integrate_forces` runs, is
*this* tick's facing. That describes a pose the head never held.

Invisible before ADR-0010, when a head was one circle centred on its anchor:
that circle sits in the same place at every facing. The axe crescent reaches
about 50 px off its anchor, so a head that swung 0.4 rad during a step had its
circles reconstructed some 20 px from where they actually were — comparable to
the whole 16 px at which two heads touch. `_first_circle_contact` then looked
for a crossing along a path the head did not take, and missed real ones.

That is why it showed up on the axe crescent and the sword blade and never on
the single-circle staff.

## The fix

`_previous_shape_xforms` snapshots the circle offsets at the same instant as
`_previous_position`, and `_first_circle_contact` sweeps from the snapshot.
Both sides of the pair use it — the partner's offsets come over in
`pair_step_snapshot()` — since the partner's start pose has the same problem.

`_undo_any_tunnelling` (head against the world) deliberately keeps reading the
live offsets. `cast_motion` translates and cannot rotate, so for a head that
swung during the step only one end of the step can be right, and the two
sweeps want different ends:

| sweep | question it asks | end that must be right |
| --- | --- | --- |
| world | did the step carry the head past something? | the **end** — the pose it is reseated from |
| pair | where did two heads first *meet*? | the **start** — where the crossing began |

Measured, not assumed: switching the world sweep to the snapshot too ends the
cast on a pose the head never reaches, and cost `head_strike_damage_scales`
its 0.90 rad swing outright ("a 0.90 rad swing never reached the victim at
all").

## Scenario corrections made while measuring

The scenario `roster_heads_do_not_tunnel_head` over-reported before this work.
Three corrections, each of which made it claim *less*:

1. A charge cut short by an elimination is **void**, not passed — counted and
   reported separately, kept out of both `met` and `breaches`.
2. A crossing alone is not a breach. Two heads that simply *missed* each other
   also cross the along-axis; the pickaxe was flagged at 14.9 px and the staff
   at 29.8 px of clear air between them. A breach requires the clusters to
   have been overlapping on the step that crossed.
3. A crossing the correction **puts back** is not a breach either.
   `_undo_any_head_crossing` works from the motion that actually happened, so
   it can only run on the step *after* the one that made the crossing. A head
   found on the far side is either a breach or a crossing about to be undone,
   and the two are told apart by whether the ordering comes back.

## Hypotheses ruled out, so nobody repeats them

- **The per-circle-pair "already touching at step start" exclusion.** Disabling
  it does not remove the breaches; the count held at 4 and merely
  redistributed — the sword got worse, the axe better, and the dagger newly
  failed. Less predictable, not more correct.
- **Circle size.** The worst offender had a *larger* minimum circle than a
  clean weapon: pickaxe min 2.01 px (0 breaches), staff 2.93 (0), sword 1.93
  (1), axe 2.87 (2), dagger 1.44 (0).
- **Speed alone.** One axe breach was at 600 px/s each — 20 px of closing per
  tick against a crescent tens of pixels across.
- **The `_closest_approach` early-out.** Instrumented: `ca 13.1 > sum 12.0` is
  geometry correctly saying no circle could touch.
- **`PAIR_OVERLAP_ALLOWANCE` and the degenerate normal/offset guard.** Neither
  fired on the failing steps.

## Verification

Godot v4.6.2.stable.official.71f334935.

    $ ls -d .godot          # fresh-clone condition: no class cache present
    ls: .godot: No such file or directory

    $ godot --headless --path . --quit
    exit: 0
    # headless still does not create .godot, so this run *is* the fresh clone

    $ godot --headless --path . -s tools/scenario_runner.gd -- --all
    33 passed, 0 failed, 33 total

`roster_heads_do_not_tunnel_head`: 0 breaches across all five weapons
(pickaxe, staff, sword, axe, dagger), 12 charges each at 0/45/90/135 degrees
and 600/1200/1800 px/s. Before the fix: sword 1/12, axe 2/12.
