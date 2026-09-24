# 12. A rising kill zone puts a deadline on every round

- Status: Accepted
- Date: 2026-09-24

## Context

A round ends only when one player is left standing (ADR-0004). Nothing forced
that to happen. Two careful players could each find a safe perch, usually the
highest spawn, and the round would stall: no ring-out, no damage, and nobody
scoring. The rotation (ADR-0008) promises short rounds on varied geometry, and
a stalled round breaks that promise.

Issue #22 set out three options:

- **A. Rising kill zone.** The stage's floor death boundary climbs after a grace
  period, taking the safe ground with it.
- **B. Sudden death.** After a time limit, damage is multiplied or any hit
  kills. Players can still sit apart and never touch.
- **C. Hard round timer.** The round ends with no winner when time runs out.
  This makes stalling a valid strategy rather than removing it.

## Decision

**Option A, applied across the whole rotation** (owner, 2026-09-24).

- Only the floor rises: the node named `KillZone` directly under a stage's
  root. `scenes/parts/Hazard.tscn` reuses `KillZone.gd` and **must never
  rise**. The rise is therefore opt-in. The script is idle until
  `start_rising(grace, speed)` is called, and `RoundManager` calls it at round
  start on that one node only. It freezes the zone with `stop_rising()` when
  the round ends, so a surface never climbs over the scoreboard or the waiting
  text.
- **The rise is a deadline, not a speed.** `RoundManager.kill_zone_grace_sec`
  (default 40 s) is how long the zone holds still. `kill_zone_rise_sec`
  (default 28 s) is how long it then takes to reach the stage's highest spawn.
  The speed is derived per stage as the distance from the kill zone to the
  highest spawn divided by `kill_zone_rise_sec`. Stages differ a lot in height:
  Flatlands climbs 480 px, and Cascade climbs 912 px to spawns at y=-352. A
  fixed speed would give Cascade's holdouts twice the time Flatlands' get.
  After the highest spawn, the zone keeps climbing at the same speed.
- **Players see it coming.** `KillZone.gd` draws its own translucent
  red-orange band (the hazard colour) from the zone's top edge downward, so no
  stage scene is edited. The band flashes for the last `rise_warning_sec`
  (default 4 s) of the grace period.
- The rise advances on physics ticks, not wall-clock time, so it stays in step
  with the bodies it rises into. The node's position is moved, so
  `body_entered` fires for a body the zone rises into just as it does for one
  that falls in.
- Each round instances a fresh stage, so every round's zone starts at its
  authored height with a new grace period. No reset code is needed.

## Consequences

- `every_stage_can_ring_out` keeps its meaning: a stage can be rung out of
  *before* the rise does it for you. That scenario and every other stage
  scenario load stages without a `RoundManager`, so the rise is never started.
- The deadline measures to the highest spawn *point*, and spawns are drop
  points. A player idling on Flatlands' floor stands 276 px below its spawns,
  so the zone reaches them about a third of the way into the rise, roughly
  50 s into the round. On Cascade it takes about nine tenths of the rise.
  Retune the two exports if playtests want flat stages to last longer.
- A stage with no floor `KillZone`, no spawns, or a kill zone above its highest
  spawn does not rise, and pushes a warning in the last case.
- A future stage that wants a different pace can only change it through the
  rotation-wide exports. A per-stage override is left to be added when a stage
  needs one.
