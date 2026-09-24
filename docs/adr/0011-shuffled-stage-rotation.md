# 11. Shuffled stage rotation with a fixed opener

- Status: Accepted
- Date: 2026-09-24

## Context

ADR-0008 rotated stages sequentially, wrapping through `stage_scenes`, and
named its own revisit condition directly: "worth revisiting once the roster
grows past a handful of stages where sequential order becomes noticeably
predictable." Since #19 the roster has grown from 3 stages to 11, well past
that handful -- ADR-0008's own condition has now been met.

Issue #20 asked what rotation should replace it. [DECISION] From the owner
(tkneeland), 2026-09-24: **shuffle, not sequential**, with one caveat: the
first stage of a session is always the same, and it must be a simple stage
with no special gimmicks or mechanics. Starting on familiar, gimmick-free
ground means the first round of a session -- often the first thing a new
group of players ever sees -- never opens on a moving platform, a crumbling
ledge, or a hazard zone (ADR-0009's on-stage parts). `stage_scenes[0]` in
`scenes/Main.tscn` is already Flatlands: ground plus two static platforms,
nothing else. The opener rule is "`stage_scenes[0]` opens", not "Flatlands
opens" by name, so `scenes/Main.tscn` needed no change.

Pure random-each-round selection was not on the table: with an 11-stage
roster it can repeat a stage twice in a row, or go many rounds without
revisiting one at all, which is the predictability problem's mirror image --
players stop trusting the rotation to be fair over a session.

## Decision

`RoundManager._swap_stage()` now rotates stages as: **the fixed opener, then
shuffled bags**.

- Round 1 of every session plays `stage_scenes[0]`.
- After the opener, stages are drawn from a shuffled bag covering the whole
  roster (`stage_scenes[0]` included), refilled with a fresh shuffle once
  exhausted.
- **A stage never plays twice in a row** -- not within a bag (impossible
  anyway, since a bag is a permutation), not across a bag boundary, and not
  from the opener into the first bag. A bag that would open with the stage
  that just played has that entry swapped with another position in the same
  bag before it is used.
- Edge cases: a 1-stage roster has no way to avoid a repeat and just repeats
  that stage every round; a 2-stage roster's only valid bag order alternates
  it strictly; an empty `stage_scenes` keeps today's behaviour --
  `_swap_stage()` returns early and plays nothing.

The shuffle is driven by an **injectable RNG**: an exported `rotation_seed:
int` on `RoundManager` (default `-1`, meaning randomized) seeds an instance
`RandomNumberGenerator` in `_ready()`. The bag is built with a Fisher-Yates
shuffle over that RNG -- never `randi()` or `Array.shuffle()`, both of which
draw from the global RNG and cannot be seeded per instance. A scenario can
set `rotation_seed` before the round loop starts and assert an exact
sequence; two `RoundManager`s given the same seed produce the same sequence,
and a different seed produces a different one.

This supersedes ADR-0008's rotation clause ("rotates through them
**sequentially**, wrapping around"). Nothing else in ADR-0008 -- the stage
authoring format, spawn markers, kill zone, or the Arena/stage-roster
decoupling -- is affected.

## Consequences

- Session-to-session variety returns without breaking the "always starts
  somewhere gimmick-free" property new and casual groups rely on.
- `tools/scenario_runner.gd`'s `stage_rotates_each_round` now asserts the
  shuffled-bag properties (opener first, no back-to-back repeat, each stage
  exactly once per bag) instead of exact sequential order, and three new
  scenarios cover the determinism seam, the opener rule across seeds, and the
  no-repeat rule including both edge cases.
- Rotation is no longer fully predictable to players within a bag, but is
  still fair over any complete bag -- every stage plays exactly once before
  any repeats, same as ADR-0008's sequential order, just not in a fixed
  order.
- A stage left out of `tools/scenario_runner.gd`'s `STAGE_PATHS` still rotates
  in play but is never swept by `stage_spawns_are_safe` /
  `every_stage_can_ring_out` -- unchanged from ADR-0008's own consequence.

## Alternatives considered

**Random each round, no bag.** Simplest to implement, but can repeat a stage
back-to-back or skip one for many rounds, undermining the same fairness
sequential rotation gave players. Rejected in favor of bags, which guarantee
every stage plays before any repeats.

**No fixed opener -- shuffle from round 1.** Matches "fully random" more
purely, but a new group's very first round could land on a moving platform,
a crumbling ledge, or a hazard zone before anyone has seen the base game.
The owner's decision was explicit that the opener stay fixed and simple.
