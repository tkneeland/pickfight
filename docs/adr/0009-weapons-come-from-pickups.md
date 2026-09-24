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
  with at most two on the stage at once. Its weapon is random and never the
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
