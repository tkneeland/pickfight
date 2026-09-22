class_name WeaponHead
extends RigidBody2D

## The weapon's head: the only part of the weapon that collides, and so the
## part that plants, strikes and blocks (ADR-0005, ADR-0006). `Player` builds
## it as part of the weapon rig; this script exists for one job the engine
## will not do for us.
##
## **Why it is here.** The head is small, and a swing moves it fast: measured
## peak head speed in clear air is 2724 px/s, and the largest single-tick
## displacement measured is 45.4 px, against arena platforms that are 24 px
## thick. A single step can therefore finish with the head past the middle of a
## slab, and the shortest way out of that overlap is through the far side. That
## is
## the tunnelling ADR-0006 warned the spike would have to survive, and the
## operator hit it in real play: swinging straight down to boost upward
## occasionally put the head under a platform instead of planted on it.
##
## **Why `continuous_cd` does not cover it.** The head already runs
## `CCD_MODE_CAST_SHAPE`. Godot's 2D continuous detection estimates a step's
## motion from the body's velocity at the time the collision pair is set up,
## which is before the constraint solver runs. The head is not only integrated
## -- it is also dragged by the joints that tie it to the haft and the body,
## and that part of its motion is produced inside the solve. Measured on the
## boost move: the worst single tick displaced the head 36.2 px while its
## pre-step velocity accounted for only 21.0 px. The remaining 15.2 px, 42% of
## the motion, never appeared in the estimate CCD was working from. No CCD
## setting closes that, because there is nothing wrong with the CCD.
##
## **Why not the other two levers.** Raising `physics_ticks_per_second`
## shrinks the window without closing it, and re-times every tick-counted
## thing in the project. Clamping the head's per-tick displacement would close
## it, but guaranteeing safety against 24 px geometry at 60 Hz means capping
## the head near 720 px/s -- about a quarter of the speed the moveset actually
## reaches, which would cost the fast swing the operator says feels right.
##
## **What it does instead.** Each tick the head sweeps its own collision shape
## along the displacement the previous step actually produced -- whatever
## produced it, integration or solver. If that path crossed something solid,
## the head is placed at the contact point and the part of its velocity
## heading into the surface is removed. That is the same outcome the step
## would have had if the solver had seen the contact, and it is applied
## against the motion that really happened rather than against a prediction.

## Floor under the sweep gate, so a degenerate head shape cannot make the
## sweep run against every tick of ordinary contact.
const SWEEP_GATE_FLOOR: float = 4.0
## How far past the contact point the surface is probed for its normal. Just
## enough overlap to get an answer.
const NORMAL_PROBE_DEPTH: float = 1.0

## The collision shape node whose shape is swept. Set by `Player` when it
## builds the rig. Read for its local transform as well as its shape, because
## a non-circular head is turned to face along the haft each tick while the
## body itself stays rotation-locked.
var sweep_shape: CollisionShape2D

## Layers the sweep treats as solid, and bodies it ignores.
##
## Deliberately not the head's own `collision_mask`, which also contains other
## weapon heads: a clash is two driven heads contesting, and two heads each
## snapping the other back out of the contact would fight rather than resolve.
## The exclusion list carries the head's own player, whose body the head is
## allowed to pass through.
var sweep_mask: int = 1
var sweep_exclude: Array[RID] = []

var _previous_position: Vector2 = Vector2.ZERO
var _has_previous: bool = false
var _gate_shape: Shape2D
var _gate_distance: float = 0.0

## Called by `Player` whenever the head is moved by something other than the
## simulation -- a respawn, a scenario placing a player. Without it the next
## sweep would run along the teleport itself and snap the head back to the
## place it was teleported away from.
func forget_previous_position() -> void:
	_has_previous = false

## The shortest step worth sweeping: the head's own narrowest width.
##
## Below that, a step cannot have carried the head deeper into something than
## the head is wide, so the end-of-step contact check sees the overlap and
## pushes it out of the side it came in. Above it, the head can finish a step
## past the middle of thin geometry, and the shortest way out is then through
## the far side -- which is the failure this class exists for. The arena's
## thinnest platform is 24 px, comfortably above the pickaxe's 16 px head.
##
## This gate is load-bearing in the other direction too. Sweeping on every
## step instead cost a plant its settle: landing on another player bounces the
## head 4-11 px a tick for a while, and correcting each of those turned an
## ordinary settle into a limit cycle the player never came to rest out of.
## Small overlaps are the solver's, and it resolves them correctly.
func _sweep_gate(shape: Shape2D) -> float:
	if shape != _gate_shape:
		_gate_shape = shape
		var size: Vector2 = shape.get_rect().size
		_gate_distance = maxf(SWEEP_GATE_FLOOR, minf(size.x, size.y))
	return _gate_distance

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _has_previous:
		_undo_any_tunnelling(state)
	_previous_position = state.transform.origin
	_has_previous = true

func _undo_any_tunnelling(state: PhysicsDirectBodyState2D) -> void:
	if sweep_shape == null or sweep_shape.shape == null:
		return

	var motion: Vector2 = state.transform.origin - _previous_position
	var distance: float = motion.length()
	if distance < _sweep_gate(sweep_shape.shape):
		return

	# The shape is swept where it actually sits, not at the body's origin: the
	# body is rotation-locked, so a head that is not a circle carries its
	# facing on the shape node rather than on the body. The offset is constant
	# across a pure translation, so a safe fraction found for the shape is the
	# same safe fraction for the body's origin.
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = sweep_shape.shape
	params.transform = Transform2D(state.transform.get_rotation(), _previous_position) * sweep_shape.transform
	params.motion = motion
	params.collision_mask = sweep_mask
	params.exclude = sweep_exclude
	params.margin = 0.0

	var space: PhysicsDirectSpaceState2D = state.get_space_state()
	var fractions: PackedFloat32Array = space.cast_motion(params)
	if fractions.size() < 2:
		return
	var safe: float = fractions[0]
	# 1.0 means the path was clear. 0.0 means the head could not move at all
	# from where the step began -- it was already touching -- so it crossed
	# nothing this step and the contact is the solver's to resolve. Snapping a
	# head that is skimming along a surface back to where it started would pin
	# it to that surface, which would cost the moveset far more than the
	# tunnelling does.
	if safe <= 0.0 or safe >= 1.0:
		return

	var contact: Vector2 = _previous_position + motion * safe
	state.transform = Transform2D(state.transform.get_rotation(), contact)

	var travel: Vector2 = motion / distance
	var normal: Vector2 = _surface_normal(space, params, contact, travel)
	var into: float = state.linear_velocity.dot(normal)
	if into < 0.0:
		state.linear_velocity -= normal * into

## The normal of whatever the sweep stopped against, so that what is taken out
## of the velocity is the part driving the head through the surface and not
## the part sliding it along. Oriented against the direction of travel rather
## than trusted to arrive that way, and falling back to the direction of
## travel itself, which can be over-eager but can never be the wrong sign.
func _surface_normal(
		space: PhysicsDirectSpaceState2D,
		params: PhysicsShapeQueryParameters2D,
		contact: Vector2,
		travel: Vector2) -> Vector2:
	params.motion = Vector2.ZERO
	params.transform = params.transform.translated(
		contact - _previous_position + travel * NORMAL_PROBE_DEPTH)
	var rest: Dictionary = space.get_rest_info(params)
	if rest.has("normal"):
		var normal: Vector2 = rest["normal"]
		if normal.length_squared() > 0.0:
			return -normal if normal.dot(travel) > 0.0 else normal
	return -travel
