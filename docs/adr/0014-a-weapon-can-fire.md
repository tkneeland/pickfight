# 14. A weapon can fire

- Status: Accepted
- Date: 2026-09-24 (amended for #61)
- Amends: [ADR-0005](0005-the-weapon-is-the-arm.md), "Weapons are melee"

## Context

ADR-0005 ruled that weapons are melee, with the roster set apart by weight and
responsiveness. After playtest 2 the owner asked for the boomstick (#55): a gun
on a stick that swings like the sword, does almost nothing in melee, and fires
on its own every 5 s. The owner settled the design on #55:

- It fires automatically, straight down the barrel. There is no new control.
  The phone still sends one relative vector (ADR-0003).
- The bullet flies straight and fast with no gravity. It hits once and vanishes
  on a player or on terrain, deals 35 and shoves the player it hits.
- Later (#61) the owner asked for bullets players can clearly see: 900 px/s
  and a 5 px radius, down from 1800 px/s and 3 px. Other players' weapon heads
  block bullets too.
- Each shot kicks the shooter back a moderate amount, one to two body widths.

This is the first thing in the game that deals damage without being a head,
and the first thing that moves fast enough to pass through terrain in one
physics tick.

## Decision

**A weapon may fire. Firing is data on `WeaponStats`, and the defaults mean it
never does.** The fields are `fire_interval`, `projectile_damage`,
`projectile_speed`, `projectile_knockback`, `projectile_radius` and
`recoil_impulse`. A `fire_interval` of 0 means the weapon never fires, so the
other weapons and every existing resource are untouched. The boomstick is the
only weapon that sets them.

- **The player fires, on a countdown.** `Player` counts the interval down only
  while it is alive with a live rig. The count starts over whenever a weapon is
  assigned or a rig is built, so the first shot comes a whole interval after a
  weapon is picked up or a round starts. The bullet leaves from the head's
  anchor along the haft's actual angle, which is the barrel as drawn. Each shot
  pushes the body the other way with `recoil_impulse`.
- **The bullet is swept, not simulated.** `scripts/Projectile.gd` is a plain
  `Node2D` rather than a physics body. Each tick it shape-casts its circle along
  that tick's motion (`cast_motion`) against the world layer (terrain and
  player bodies), bodies only. It moves to the first contact and resolves the
  hit there. However thin the terrain, or however fast the bullet, it cannot
  tunnel through (see `boomstick_bullet_stops_on_terrain`, an 8 px bar against
  15 px of travel per tick).
- **A bullet never hits its shooter.** The cast excludes the shooter's body
  and the shooter's own head, read afresh each tick so a weapon swapped
  mid-flight is still its own. A bullet fired from inside its own body at rest
  reach gets out, one leaves down its own barrel, and one that crosses its
  shooter or its shooter's head passes through
  (`boomstick_own_head_never_blocks`).
- **Weapons do not block bullets** (#92, owner, reversing #61). The cast
  leaves the head layer out, so a bullet flies through every weapon head, as
  it always has through hafts and pickups (`boomstick_own_head_never_blocks`
  checks a head fired past by its own holder and by another player). #61 had
  opposing heads stop bullets so a shot could be parried; playtest found it
  blocked too much.
- **A bullet hit is a strike, as far as anyone listening can tell.** The bullet
  applies its knockback and then calls the shooter's `land_projectile_hit()`.
  That goes through `take_damage()` and emits the shooter's existing
  `strike_landed`. The hitmarker (#33) and the phone buzz (ADR-0013) treat a
  bullet exactly as they treat a swing, and nothing new is wired.
- **Bullets end with the shooter's time in play.** The shared `_go_inert()`
  frees them, so eliminated players and survivors put through `leave_round()`
  both lose theirs. A bullet also frees itself once its shooter is out of play
  or after 4000 px of flight.

## Consequences

- ADR-0005's line that weapons are melee now reads "weapons are melee, except
  one that fires on a timer". The roster is still set apart by weight and
  responsiveness. The boomstick's sword handling and pitiful swing are part of
  its trade.
- Damage is no longer only "a head striking a player, scaled by head speed". A
  bullet deals a flat amount that does not depend on speed.
- The boomstick has no fire button, so how often it fires is a design number
  rather than a skill. Aiming is still a skill, because the barrel points
  wherever the player holds the weapon.
- Knockback (260) and recoil (150) were set by the agent to the owner's
  description ("shoves", "one to two body widths"). They are for the owner to
  tune in playtest. `boomstick_recoil_is_moderate` pins the recoil to one to
  two body widths.

## Alternatives considered

**A `RigidBody2D` bullet with continuous collision detection.** Godot's CCD is
per-body and still lets small, fast bodies through thin geometry in some cases.
It would also make the bullet a physics object other bodies push against, and
it would need contact monitoring to report hits. Sweeping the circle ourselves
is simpler and exact.

**A hitscan ray.** The owner asked for a bullet that flies, one players can see
and step out of.

**A fire control on the phone.** It was ruled out on #55. The controller sends
one vector, and a second input would reopen ADR-0003.
