# 6. The weapon is a force-driven jointed body

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

Clash is left emergent: two heads meet and the drives contest. **Max drive
force** is what resolves it, so that a weaker weapon loses ground rather than
jittering in a deadlock.

The player body is hard rotation-locked.

### Engine support, verified against Godot 4.6.2

The drives are hand-written, not the engine's joint motors.

`PinJoint2D` does expose `motor_enabled` and `motor_target_velocity` in 4.6.2,
but the complete pin-joint parameter set is softness, the two angular limits and
the target velocity — there is **no force or torque cap**. An engine motor
therefore has unlimited authority: it reaches its target velocity regardless of
what resists it, which is precisely the property the clash rule needs to be
able to lose. `GrooveJoint2D` has no actuation at all (`length` and
`initial_offset` only), so the slider half of Foddy's rig has no engine
equivalent either.

So: use `PinJoint2D` as the constraint with its motor left disabled, and drive
the weapon with `RigidBody2D.apply_torque` for angle and `apply_force` along the
haft for extension, each clamped per weapon. Max drive force is then the clamp
rather than a missing engine property, which is the stat the weapon roster is
built on anyway. `DampedSpringJoint2D` is the fallback for extension if a direct
force proves unstable: driving its `rest_length` gives a moving setpoint, and
its `stiffness` supplies the force ceiling.

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
- Because the drives are hand-written, the per-frame controller is ours to get
  right: the input vector gives a target angle, and a target *angle* has to be
  converted into torque through a proportional-derivative term. Expect that
  controller, not the joint, to be where the feel lives.
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
- The tunnelling this ADR flagged as the spike's main risk did happen, on the
  arena's 24 px platforms, and is closed without taking the fallback. It is not
  a CCD gap: the head's motion is partly produced by the joints inside the
  constraint solve, after Godot's 2D continuous detection has taken its
  motion estimate from the body's velocity, so no CCD setting can see it.
  `WeaponHead` instead sweeps the head's shape along the displacement each step
  actually produced and puts the head back at the contact point when that path
  crossed something solid. The jointed rig stands; nothing here changes the
  decision above.
- The aim is *near*-1:1, not exactly 1:1. Playtesting the built rig, the
  operator reported the head "slightly lags behind finger, but not by too
  much", and asked to keep that residual lag rather than tune it out: it is
  what a heavy weapon and a light weapon will differ by. Foddy's rig tracks
  the cursor exactly; ours deliberately does not. The lag is the visible
  consequence of `max_drive_force` and `drive_speed` being real physical caps
  (`WeaponStats`), so the same numbers that decide who wins a clash also
  decide how far behind the finger a weapon sits. That coupling is the point,
  and it is why a weapon's feel is not a separate tuning surface.

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
