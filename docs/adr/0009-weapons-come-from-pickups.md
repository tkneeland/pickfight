# 9. Weapons other than the pickaxe come only from pickups

- Status: Accepted
- Date: 2026-09-23

## Context

ADR-0005 makes the weapon the player's only appendage and says the round's
winner keeps theirs while everyone else respawns with a pickaxe. It never says
how anyone comes to hold something other than a pickaxe. With a roster of five
weapons (pickaxe, staff, sword, axe, dagger) that now has to be decided.

Alternatives considered:

- **Random loadout at spawn.** Removes all choice; the winner-keeps rule
  becomes the only way a weapon matters beyond one round.
- **Mid-round crate drops only.** Long stretches with nothing to fight over,
  and a single contested moment per round.
- **Pickups on the stage.** Something to move toward and fight over, which a
  swing-based moveset rewards.

## Decision

A **pickup** is a weapon lying on the stage during a round. It is the only way
to get a weapon other than the pickaxe.

- One pickup appears at round start, then one more roughly every 10 seconds,
  with at most two on the stage at once. (Amended by #36 and #152: the cap is
  one fewer than the players, one per player from five players up; the
  interval is 12 seconds, and 60% of that from five players up.) Its weapon is random and never the
  pickaxe.
- A player collects a pickup by touching it with their **body**, not their
  weapon's head. Their previous weapon vanishes: nothing is dropped.
- Stages declare where pickups may appear, alongside their spawn points
  (ADR-0008's `Marker2D` convention, as `PickupSpawn*`). A stage without any
  falls back to a point above its centre.
- Pickups still on the stage when a round ends are cleared.

## Consequences

- Picking a weapon up is a commitment, as CONTEXT.md intends: there is no way
  back to the pickaxe until you die or someone else wins the round.
- Combined with ADR-0005's winner-keeps rule, a winner can snowball a strong
  weapon across rounds. Accepted for now; tune spawn rate or roster if
  playtesting shows it dominating.
- Body-only collection means a player must physically reach a pickup, which
  makes reach and movement matter for acquisition, not just combat.

## Amendment (2026-09-24, issue #36)

With up to four players, "at most two on the stage at once" becomes **at most
one fewer than the players on the roster, and never fewer than two**:
`max(2, players - 1)`, so two for two or three players and three for four.
`RoundManager.max_pickups` stays as the floor. This is an agent default the
owner can override. A stage that declares only two `PickupSpawn*` markers
still holds at most two, since a pickup never shares a spot.
