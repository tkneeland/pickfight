# 5. The weapon is the arm

- Status: Accepted
- Date: 2026-09-22
- Supersedes: the `CONTEXT.md` claim that knockback is the only damage model,
  and its definition of a weapon as a stage pickup

## Context

`CONTEXT.md` treated these as two separate things: an **arm**, the rigid pole
that is the only means of movement, and a **weapon**, an undesigned stage pickup
that modifies attack or movement.

They are one object. A player holds a pickaxe. They climb with it, kill with it,
and block with it. Swapping it for a heavier weapon changes how they move as
much as how much damage they do.

`CONTEXT.md` also stated that there are no health bars and that knockback is the
only damage model — players die by hazard or ring-out alone. Stick Fight, the
reference for the fight's structure, does have accumulating damage. That model
is adopted.

## Decision

**Arm** and **Weapon** collapse into one glossary term: **Weapon**. It carries
reach, weight, responsiveness, damage, and the shape of its head.

The weapon has a solid **head** and a non-colliding **haft**. The head's extent
is per weapon — a nub at a pickaxe's tip, most of a sword's blade.

Damage exists. It is dealt by a head striking a player, scaled by head speed.
Body-to-body collision keeps its knockback and deals no damage. Damage
accumulates within a round and resets at the round's end; a ring-out or hazard
still kills outright regardless of remaining health.

### Where the Stick Fight reference stops

Stick Fight governs the lifecycle, the presentation, and the existence of a
damage model. It does not govern the moveset. Specifically:

- Damage comes from the swing, never from body contact. Rewarding players for
  flailing their mass into opponents would undercut the one thing the game is
  about, which is that better movement beats worse movement.
- Stick Fight's damage pacing is built around guns doing most of the work; its
  unarmed punch is deliberately weak. With the weapon as the only damage source
  here, per-hit damage has to be tuned far higher than a punch or rounds will
  drag.
- Weapons are melee. The roster direction is variants distinguished by weight
  and responsiveness — a sluggish heavy hammer, a snappy short sword — not
  ranged weapons.

## Consequences

- The code's `Arm` node and `arm_*` parameters are now named after a concept the
  domain no longer has. Renaming is mechanical and should happen with the
  weapon rework, not before it.
- Player identity can no longer live in body fill colour, because damage is
  shown by reddening that fill. Identity moves to a persistent outline and to
  the weapon's colour, both of which stay constant. The phone's badge tint must
  keep matching whatever carries identity.
- Reach becomes a weapon property, so it is no longer a single global tuning
  constant.
- Weapons are stage pickups grabbed by body contact, which drops the one
  currently held. Body contact is the only unambiguous grab surface: the head is
  in near-constant contact with geometry while climbing, so grabbing with it
  would swap weapons by accident constantly.
- Weapons drop where a player dies and persist as physical objects.
- The round's winner keeps their weapon into the next round; everyone else
  respawns with a pickaxe. This is not inherited from Stick Fight, which appears
  to start players unarmed each level. It works here because weapons carry
  movement trade-offs rather than being pure upgrades: carrying a heavy hammer
  onto a tight vertical stage is a real cost, and the stage rotation is what
  applies it.

## Alternatives considered

**Keep arm and weapon separate.** Once reach, weight and responsiveness are all
weapon properties, nothing is left for "arm" to name.

**Body-collision damage, or damage from both sources.** Rewards mass over skill
and makes the swing optional.

**Pull weapons into scope now.** The pickaxe has to feel right before variants
mean anything; variants built on an unrefined baseline would be tuned against a
moving target.
