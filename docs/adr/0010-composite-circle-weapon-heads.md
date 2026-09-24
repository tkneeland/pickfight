# 10. Weapon heads are clusters of circles fitted to the art

- Status: Accepted
- Date: 2026-09-23

## Context

Each weapon's **head** is its solid region (CONTEXT.md); the haft collides with
nothing. Every weapon now gets drawn art: a crescent pickaxe, a knobbed staff,
a sword blade, a crescent axe, a dagger blade. Players read hits off that art,
so the head's collision has to line up with it.

The obvious move, colliding with the traced outline as a single polygon, has
already been tried and reverted for the pickaxe (see `resources/pickaxe.tres`):
the head-vs-head interpenetration and tunnelling correction in
`WeaponHead.gd` is tuned around a circle's uniform radius, and pointed or
asymmetric polygons broke several combat scenarios. Fixing that means
reworking the shape-dependent correction math.

Alternatives considered:

- **Single traced polygon per head.** Most accurate; blocked on the correction
  rework above.
- **One stand-in circle or capsule per head, art drawn separately.** Cheap,
  but players would get hit by things they cannot see.
- **A cluster of circles filling the art outline.** Keeps every collision
  primitive a circle, which the existing correction math already handles,
  while following the drawn shape closely.

## Decision

A weapon head is a **cluster of circles** placed to fill that weapon's drawn
outline. The drawn outline is the head's visual; the circles are its collision.

The existing guarantee that the visual matches the collision changes from
"silhouette equals the head shape" to "every head circle lies inside the drawn
outline, within a small tolerance".

## Consequences

- Hitboxes follow the art closely but not exactly: crescent tips and blade
  points are slightly rounded off. Accepted as the cost of not reworking the
  correction math now.
- A single traced polygon remains a possible later upgrade; if the correction
  math is ever reworked, this ADR is superseded.
- The pickaxe loses its round nub and gets a crescent head like the others.
