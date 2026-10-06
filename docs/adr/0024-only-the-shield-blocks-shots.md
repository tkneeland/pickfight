# 24. Only the shield's face blocks player shots

- Status: Accepted
- Date: 2026-10-06
- Amends: ADR-0014's "Weapons do not block bullets" (#92)

## Context

#92 made bullets fly through every weapon head. #61 had let any opposing head
parry a shot, and playtest found that blocked too much. Since then the game has
gained more shots a player fires: the grapple's and fishing rod's hooks, and
the thrown boomerang. While splitting the grapple's and fishing rod's roles
(2026-10-06), the owner wanted one weapon that is the deliberate answer to all
of them, so that picking up the shield means something.

## Decision

The **shield's face** is the only thing that blocks a shot another player
fires: boomstick bullets, grapple and fishing rod hooks, and the boomerang. A
blocked shot does nothing: a bullet vanishes, a hook reels home empty, and a
boomerang turns back. Every other head, and the shield's back and edges, lets
shots through, as #92 decided.

Stage hazards are not shots. The umbrella's open canopy still turns falling
rocks and meteors (#569), and the shield's face still blocks head strikes
(#275).

## Consequences

- #92's "nothing blocks a bullet" now holds for every weapon except the shield.
  Because only one weapon can block, and only on its face, parrying stays rare.
- The shield becomes the anti-projectile pick. If playtests find it
  oppressive against the boomstick, tune its face width or the bullet speed
  rather than reopening which weapons block.
