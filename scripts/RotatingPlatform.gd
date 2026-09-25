extends AnimatableBody2D

## Rotating platform stage part (issue #52): a slab turning about its centre,
## either spinning slowly at a set rate or tipping like a see-saw under the
## weight on it. One part, mode chosen per instance (owner, issue #52), so a
## stage author picks.
##
## **Why an `AnimatableBody2D` for both modes.** Same reasoning as
## `MovingPlatform`: a kinematic body moved by script, with `sync_to_physics`
## on, so each turn reaches the physics engine as a swept, velocity-carrying
## move. A player resting on it is carried round with it instead of the slab
## turning out from under them, and a weapon head meets it as solid ground: the
## head's own sweep (`WeaponHead`) stops a fast head at its surface, as it
## does on any terrain on the world layer, and the slab's own turning is
## reported as motion rather than as a teleport a head could end up inside.
##
## **Why the see-saw is kinematic too, not a `RigidBody2D` on a `PinJoint2D`.**
## A rigid see-saw would get its torque from the solver for free, but it is a
## dynamic body a player can shove. Its pin is soft, so a hard landing or a
## head swung into it knocks the slab off its pivot, and a light slab under a
## heavy player jitters. It would also make this one part two different root
## types depending on its mode. Kept kinematic, the slab stays exactly on its
## pivot and turns only by the angle this script gives it. The physics feel
## comes from reading the real load on it: every tick it sums the contact
## impulses the solver just applied between the slab and each rigid body
## touching it, and the moment of that load about the pivot sets which way,
## and how far, the slab wants to tip. Those impulses are the bodies' real
## weight and landings, not an estimate from their masses. So two players at
## opposite ends balance, a player at the middle does nothing, a landing
## kicks it harder than standing does, and a player standing on their own
## weapon counts the same as one standing on their feet. The tilt the load
## asks for is proportional to that moment, full at `max_tilt_deg` for one
## player's weight at the very tip, and the slab eases toward it through a
## critically damped spring (`tilt_sec`). With nothing on it, that target is
## level, which is how it returns.
##
## **Heads.** A head is solid against this slab both ways: it plants and
## pushes off like any ground, and in see-saw mode its contact counts toward
## the load. That is deliberate. A player balanced on their pickaxe at one end
## puts all their weight through the head, and a see-saw that ignored it would
## hold level under a player visibly standing on it. Pushing off a planted head
## kicks the slab the other way, which is the honest reaction to a push.
##
## `_ready()` builds the collision, the visual and the load detector from the
## exports, so a stage author places this scene, sets `mode` and a few
## numbers, and never opens a sub-resource.

enum Mode { SPIN, SEESAW }

## The slab's collision and visual box, centred on the pivot.
@export var size: Vector2 = Vector2(260, 20)
## SPIN turns at `spin_deg_per_sec` forever; SEESAW tips under weight.
@export var mode: Mode = Mode.SPIN
## SPIN only: turn rate in degrees per second. Positive is clockwise on
## screen (Godot's y points down).
@export var spin_deg_per_sec: float = 30.0
## SEESAW only: the furthest the slab tips either way from its authored angle.
@export var max_tilt_deg: float = 25.0
## SEESAW only: roughly how long, in seconds, the slab takes to settle on the
## tilt its load asks for, and to settle back to level once unloaded.
@export var tilt_sec: float = 0.6

## Purple: a colour no other part uses, so "this one turns" reads apart from
## static grey-blue terrain and the blue of a moving platform.
const SLAB_COLOR: Color = Color(0.62, 0.48, 0.85, 1)
## The hub drawn over the pivot, so a player can see where it turns about.
const HUB_COLOR: Color = Color(0.3, 0.2, 0.45, 1)
## Stripes along the slab: on a spinning slab they are what shows it turning.
const STRIPE_COLOR: Color = Color(0.5, 0.36, 0.72, 1)

## One player's weight: body plus the pickaxe's head and haft (1.3) under the
## player's gravity scale (1.5) and the project gravity. The load a player
## standing at the very tip puts on the slab, and so the moment that asks for
## the full `max_tilt_deg`. Approximate on purpose: it is a scale for "how
## heavy is a player", not a number any behaviour depends on exactly.
const _PLAYER_MASS: float = 1.3
const _PLAYER_GRAVITY_SCALE: float = 1.5
## How far past the slab's surface the load detector reaches, so a body
## touching it is always inside it.
const _DETECTOR_MARGIN: float = 12.0

## The authored angle: SEESAW tilts about it, SPIN starts from it.
var _rest_rotation: float = 0.0
## SEESAW state: tilt from rest, and its rate, in radians and rad/s.
var _tilt: float = 0.0
var _tilt_velocity: float = 0.0
## The moment of the load about the pivot last tick, for scenarios and the
## screenshot tool.
var _load_moment: float = 0.0
var _detector: Area2D

func _ready() -> void:
	sync_to_physics = true
	_rest_rotation = rotation

	var half: Vector2 = size / 2.0
	var rect := RectangleShape2D.new()
	rect.size = size
	var collision_shape := CollisionShape2D.new()
	collision_shape.name = "CollisionShape2D"
	collision_shape.shape = rect
	add_child(collision_shape)

	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.color = SLAB_COLOR
	visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	add_child(visual)

	# Diagonal stripes every so often along the slab, so its turning shows.
	var stripe_step: float = maxf(size.y * 2.0, 24.0)
	var x: float = -half.x + stripe_step / 2.0
	var i: int = 0
	while x < half.x - size.y / 2.0:
		var stripe := Polygon2D.new()
		stripe.name = "Stripe%d" % i
		stripe.color = STRIPE_COLOR
		var w: float = size.y * 0.35
		stripe.polygon = PackedVector2Array([
			Vector2(x - w, half.y), Vector2(x, half.y),
			Vector2(x + w, -half.y), Vector2(x, -half.y),
		])
		add_child(stripe)
		x += stripe_step
		i += 1

	var hub := Polygon2D.new()
	hub.name = "Hub"
	hub.color = HUB_COLOR
	var hub_r: float = maxf(size.y * 0.45, 5.0)
	var hub_points := PackedVector2Array()
	for k in 16:
		hub_points.append(Vector2.RIGHT.rotated(TAU * float(k) / 16.0) * hub_r)
	hub.polygon = hub_points
	add_child(hub)

	# Load detector for SEESAW: finds the rigid bodies that might be touching
	# the slab; their own contact reports then say what they are doing to it.
	# World and head layers (`Player.LAYER_WORLD | Player.LAYER_HEAD`), so a
	# head planted on the slab is found too -- see the header.
	_detector = Area2D.new()
	_detector.name = "LoadDetector"
	_detector.collision_layer = 0
	_detector.collision_mask = 1 | 2
	var detector_rect := RectangleShape2D.new()
	detector_rect.size = size + Vector2(_DETECTOR_MARGIN, _DETECTOR_MARGIN) * 2.0
	var detector_shape := CollisionShape2D.new()
	detector_shape.name = "LoadDetectorShape"
	detector_shape.shape = detector_rect
	_detector.add_child(detector_shape)
	add_child(_detector)

## How far the slab has turned from its authored angle, in radians. For
## SEESAW this is its tilt; positive is clockwise on screen, which is the right
## end going down. An observable seam for scenarios.
func tilt() -> float:
	return wrapf(rotation - _rest_rotation, -PI, PI)

## The moment of the load about the pivot measured on the last tick, in the
## same sign as `tilt()`: positive means the load is pushing the right end
## down.
func load_moment() -> float:
	return _load_moment

func _physics_process(delta: float) -> void:
	match mode:
		Mode.SPIN:
			rotation += deg_to_rad(spin_deg_per_sec) * delta
		Mode.SEESAW:
			_step_seesaw(delta)

func _step_seesaw(delta: float) -> void:
	_load_moment = _measure_load_moment(delta)
	var max_tilt: float = deg_to_rad(maxf(max_tilt_deg, 0.0))
	var full_moment: float = _player_weight() * size.x / 2.0
	var target: float = clampf(_load_moment / full_moment, -1.0, 1.0) * max_tilt
	# Critically damped: settles on the target in about `tilt_sec` without
	# ringing, so the slab feels weighty rather than springy. Semi-implicit
	# Euler, stable at any tick rate the project would use for this.
	var omega: float = 4.0 / maxf(tilt_sec, 0.05)
	var accel: float = omega * omega * (target - _tilt) - 2.0 * omega * _tilt_velocity
	_tilt_velocity += accel * delta
	_tilt += _tilt_velocity * delta
	if absf(_tilt) > max_tilt:
		_tilt = clampf(_tilt, -max_tilt, max_tilt)
		_tilt_velocity = 0.0
	rotation = _rest_rotation + _tilt

## Sums the moment about the pivot of every contact impulse the last physics
## step applied between this slab and a rigid body touching it, divided by
## the step to give the force each contact put through the slab.
##
## Only a body with its contact monitor on reports contacts: a player's body
## and a weapon head both do. Anything else resting here is ignored, which is
## nothing in this game today.
func _measure_load_moment(delta: float) -> float:
	var pivot: Vector2 = global_position
	var my_id: int = get_instance_id()
	var moment: float = 0.0
	for body: Node2D in _detector.get_overlapping_bodies():
		if not body is RigidBody2D:
			continue
		var state: PhysicsDirectBodyState2D = PhysicsServer2D.body_get_direct_state((body as RigidBody2D).get_rid())
		if state == null:
			continue
		for c in state.get_contact_count():
			if state.get_contact_collider_id(c) != my_id:
				continue
			# Oriented by the contact normal, not by the impulse's own sign.
			# On 4.6.2 the sign of `get_contact_impulse()` depends on which
			# body the engine put first in the pair -- measured, a player's
			# body resting here reports it pointing up and its weapon head
			# reports it pointing down -- while the normal always points from
			# the slab out into the body. A contact can only push, so the load
			# on the slab is along minus that normal, with the impulse's size
			# along it. Friction along the surface is left out: it barely
			# turns a slab about its own middle.
			var normal: Vector2 = state.get_contact_local_normal(c)
			var push: float = absf(state.get_contact_impulse(c).dot(normal)) / delta
			var arm: Vector2 = state.get_contact_collider_position(c) - pivot
			moment += arm.cross(-normal * push)
	return moment

func _player_weight() -> float:
	var g: float = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	return _PLAYER_MASS * _PLAYER_GRAVITY_SCALE * g
