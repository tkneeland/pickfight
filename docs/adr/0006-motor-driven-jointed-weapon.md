# 6. The weapon is a motor-driven jointed body

- Status: Accepted
- Date: 2026-09-22

## Context

The weapon is now one object used for movement, damage and blocking
(ADR-0005). Two of those three need it to be physically present, which it is
not: today it is a `Line2D` for visuals plus a single `RayCast2D` that probes
for a plant point. It cannot hit anyone and cannot stop anyone else's swing.

Blocking requires two weapons to actually obstruct each other. Weapon weight
mattering to movement requires mass that resists. Both point at giving the
weapon a real body.

The obvious objection is that a physical weapon with its own inertia fights the
player's input, which is exactly the frustration `CONTEXT.md` says to avoid.

That objection rests on a false premise. Getting Over It's hammer is fully
physical *and* fully precise: Foddy has described the rig as a hinge joint from
the pot to an invisible body and a slider joint from that to the hammer, with
motors on both driving the hammer to the cursor. The head tracks input 1:1. The
difficulty comes from the body hanging off the end, not from the hammer lagging
behind the player's hand. Only the head has collision.

## Decision

Build the weapon as a rigid body connected to the player by joints, with motors
driving it toward the angle and extension given by the input vector. Precision
of aim comes from the motors; physicality comes from the body.

Only the head collides. The haft passes through everything.

Per-weapon tuning is expressed as physical quantities — mass, motor speed, max
motor force, reach, head shape — rather than as feel fudges.

Clash is left emergent: two heads meet and the motors contest. **Max motor
force** is what resolves it, so that a weaker weapon loses ground rather than
jittering in a deadlock.

The player body is hard rotation-locked.

### Spike before committing

Jointed 2D physics is where prototypes stall: joint instability, a fast-moving
head tunnelling through thin platforms, motors fighting the ground. Prove the
rig against the existing arena before building the roster on it.

The named fallback, if it will not stabilise: keep the raycast plant, give the
head a collider for hits and clashes, and rate-limit how fast the weapon's
angle chases the input vector to stand in for inertia. That loses emergent clash
and honest weight, and both then need explicit rules.

## Consequences

- Clash, blocking, weapon weight and force transfer all come out of the physics
  engine instead of being special-cased.
- Weapon identity reduces to two numbers. High force with low motor speed is
  the heavy hammer: unstoppable once moving, hopeless at reacting. The inverse
  is the short sword: loses every head-on clash, wins every race to reposition.
- Rotation-locking the body fixes an input-fidelity bug as a side effect. `Arm`
  is a child of the `RigidBody2D` and the arm angle is set in local space, so
  the weapon's world angle has been `body.rotation + arm_angle` all along — the
  same drag pointed somewhere different depending on how the player happened to
  be spinning. Locked, the drag angle is the world angle.
- The body never tilts, which may look stiff. Cosmetic visual tilt that does not
  touch the input frame can be added later.
- This is the largest and riskiest piece of work in the plan, and it gates the
  rest of the combat package.

## Alternatives considered

**Free-swinging jointed body, no motors.** The weapon's own inertia fights the
player's aim. That is Gang Beasts, not Getting Over It, and it is the failure
mode `CONTEXT.md` explicitly rules out.

**Raycast plus collider with a rate-limited angle.** Cheap, precise, and
reversible — retained as the named fallback. Rejected as the first choice
because clash and weight both become invented rules rather than consequences.

**Solid haft.** Lets a player shove opponents off a ledge by extending slowly
sideways, which rewards none of the skill the swing expresses. A long thin fast
collider is also the shape most likely to tunnel.
