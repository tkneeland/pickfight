extends Node2D

## A thrown boomerang (issue #150). `Player` throws one when a player holding
## the boomerang flicks; the boomerang leaves the head (which is left with
## just its grip) until it comes back.
##
## **The flight.** It leaves along the flick at `projectile_speed` and slows
## evenly so that it stops `launch_range` out, drifting a little to one side
## as it goes, which is the arc. Then it turns for home: it steers toward the
## thrower wherever they now are, speeding up to `return_speed`, and is
## caught when it reaches their body. If it has not been caught after
## MAX_FLIGHT_SEC it is back in their hands anyway, so nobody is left without
## a weapon for long.
##
## **Hits, out and back.** It flies through players rather than stopping at
## them, and each player can be hit once on the way out and once on the way
## back: a flat `projectile_damage` and a shove along its flight of
## `projectile_knockback`, through the thrower (`Player.land_projectile_hit`)
## so the hit reaches the hitmarker, the buzz, the kill feed and the awards
## like any strike.
##
## **Terrain.** On the way out, terrain turns it round where it meets it (a
## breakable wall takes its damage first). On the way home a boomerang whose
## path is blocked by terrain ghosts through it rather than being lost behind
## it: it is drawn faded, passes through everything and hurts no one for the
## rest of the trip. It is still caught as usual.
##
## **Swept, never discretely collided**, like the boomstick's bullet: each
## tick its circle is cast along the motion it is about to make, so it cannot
## pass through a thin platform on the way out. Weapon heads do not stop it.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

enum Leg { OUT, BACK }

const LAYER_WORLD: int = 1
## Every live boomerang is in this group, which is how scenarios find them.
const GROUP: StringName = &"boomerangs"
## Sideways acceleration on the way out, as a fraction of the slowing-down
## one: how much it arcs.
const ARC_FRACTION: float = 0.12
## How hard it steers for home, px/s^2.
const RETURN_ACCEL: float = 3600.0
## Caught within this far of the thrower's centre (the body is 48 px across).
const CATCH_RADIUS: float = 34.0
const MAX_FLIGHT_SEC: float = 3.0
## Players it can pass through in one tick before the rest of the tick's motion
## is simply taken.
const MAX_PASSES: int = 4
const SPIN_SPEED: float = 22.0
const GHOST_ALPHA: float = 0.4
const OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.8)

## It met `collider` at `point`: a sound hook (ADR-0016); gameplay ignores it.
signal impacted(collider: Object, point: Vector2)

var shooter: RigidBody2D
var leg: Leg = Leg.OUT
var velocity: Vector2 = Vector2.ZERO
## Ghosting home through terrain: harmless, passes through everything.
var ghost: bool = false
var age: float = 0.0
## Whether it ended in the thrower's hands (rather than with them leaving play).
var caught: bool = false
## Players hit on each leg, by instance id.
var hits_out: Dictionary = {}
var hits_back: Dictionary = {}

var _stats: Resource
var _origin: Vector2 = Vector2.ZERO
var _throw: Vector2 = Vector2.RIGHT
var _arc: Vector2 = Vector2.ZERO
var _slowing: float = 0.0
var _shape: CircleShape2D
var _colour: Color = Color.WHITE
var _art: PackedVector2Array = PackedVector2Array()
var _spin: float = 0.0

func setup(from_shooter: RigidBody2D, origin: Vector2, flight: Vector2, stats: Resource) -> void:
	shooter = from_shooter
	_origin = origin
	_stats = stats
	_throw = flight.normalized() if flight != Vector2.ZERO else Vector2.RIGHT
	var speed: float = float(stats.projectile_speed)
	velocity = _throw * speed
	_slowing = speed * speed / (2.0 * maxf(1.0, float(stats.launch_range)))
	# Arcs upward whichever way it is thrown, unless thrown straight up or
	# down, where it arcs to the side it was turned from.
	var side: Vector2 = _throw.rotated(-PI * 0.5)
	if side.y > 0.0:
		side = -side
	_arc = side * _slowing * ARC_FRACTION
	var identity: Variant = from_shooter.get("identity_color") if from_shooter != null else null
	_colour = identity if identity is Color else Color.WHITE
	_art = _centred(stats.loaded_art)

func _ready() -> void:
	add_to_group(GROUP)
	z_index = 45
	global_position = _origin
	reset_physics_interpolation()
	_shape = CircleShape2D.new()
	_shape.radius = maxf(0.5, float(_stats.projectile_radius))

func _physics_process(delta: float) -> void:
	if not is_instance_valid(shooter):
		queue_free()
		return
	age += delta
	_spin = wrapf(_spin + SPIN_SPEED * delta, -PI, PI)
	if age >= MAX_FLIGHT_SEC:
		_catch()
		return
	if leg == Leg.OUT:
		velocity += (-_throw * _slowing + _arc) * delta
		if velocity.dot(_throw) <= 0.0:
			_turn_back()
	else:
		var to_home: Vector2 = shooter.global_position - global_position
		if to_home.length() <= CATCH_RADIUS:
			_catch()
			return
		var wanted: Vector2 = to_home.normalized() * float(_stats.return_speed)
		velocity = velocity.move_toward(wanted, RETURN_ACCEL * delta)
	_move(velocity * delta)
	if leg == Leg.BACK and (shooter.global_position - global_position).length() <= CATCH_RADIUS:
		_catch()
		return
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _turn_back() -> void:
	leg = Leg.BACK

func _catch() -> void:
	caught = true
	queue_free()

func _move(motion: Vector2) -> void:
	if ghost:
		global_position += motion
		return
	# Issue #631: a shield's face turns the boomerang back with no damage; on
	# the way home it just flies on harmlessly, like terrain does.
	var blocker: Node = _shield_holder_blocking(global_position, global_position + motion, _shape.radius)
	if blocker != null and blocker != _shield_turned:
		_shield_turned = blocker
		impacted.emit(blocker, global_position)
		if leg == Leg.OUT:
			velocity = Vector2.ZERO
			_turn_back()
		else:
			ghost = true
			global_position += motion
		return
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape
	query.collision_mask = LAYER_WORLD
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var exclude: Array[RID] = [shooter.get_rid()]
	var left: Vector2 = motion
	for i in MAX_PASSES:
		if left.length_squared() == 0.0:
			return
		query.transform = Transform2D(0.0, global_position)
		query.motion = left
		query.exclude = exclude
		var fractions: PackedFloat32Array = space.cast_motion(query)
		var unsafe: float = fractions[1] if fractions.size() >= 2 else 1.0
		if unsafe >= 1.0:
			global_position += left
			return
		global_position += left * unsafe
		left *= (1.0 - unsafe)
		query.transform = Transform2D(0.0, global_position)
		query.motion = Vector2.ZERO
		var rest: Dictionary = space.get_rest_info(query)
		var collider: Object = instance_from_id(rest["collider_id"]) if rest.has("collider_id") else null
		var point: Vector2 = rest["point"] if rest.has("point") else global_position
		if rest.is_empty():
			# A graze can leave no rest info; an overlap query still finds
			# what was touched, so a player is not mistaken for terrain.
			var overlaps: Array[Dictionary] = space.intersect_shape(query, 1)
			if not overlaps.is_empty():
				collider = overlaps[0]["collider"]
		var node: Node = collider as Node
		if node != null and node.is_in_group("players"):
			_hit_player(node, point)
			exclude.append((node as CollisionObject2D).get_rid())
			continue
		# Terrain.
		impacted.emit(collider, point)
		if leg == Leg.OUT:
			if node != null and node.has_method("take_projectile_hit"):
				node.take_projectile_hit(float(_stats.projectile_damage))
			velocity = Vector2.ZERO
			_turn_back()
		else:
			ghost = true
			global_position += left
		return
	global_position += left

func _hit_player(victim: Node, point: Vector2) -> void:
	if victim == shooter or not bool(victim.get("alive")):
		return
	var hits: Dictionary = hits_out if leg == Leg.OUT else hits_back
	var id: int = victim.get_instance_id()
	if hits.has(id):
		return
	hits[id] = true
	impacted.emit(victim, point)
	if victim is RigidBody2D and velocity.length_squared() > 0.0:
		(victim as RigidBody2D).apply_central_impulse(velocity.normalized() * float(_stats.projectile_knockback))
	shooter.land_projectile_hit(victim, float(_stats.projectile_damage), point)

## The shield holder that turned this boomerang, so it is not turned twice.
var _shield_turned: Node = null

## Issue #631, ADR-0024: the player, other than the shooter, whose shield's
## face turns a shot flying `from` -> `to`, or null.
func _shield_holder_blocking(from: Vector2, to: Vector2, radius: float) -> Node:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node != shooter and node.has_method("shield_face_blocks") \
				and node.shield_face_blocks(from, to, radius):
			return node
	return null

func _shooter_in_play() -> bool:
	return is_instance_valid(shooter) and bool(shooter.get("alive"))

func _draw() -> void:
	var alpha: float = GHOST_ALPHA if ghost else 1.0
	var shape: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in _art:
		shape.append(p.rotated(_spin))
	if shape.size() >= 3:
		draw_colored_polygon(shape, Color(_colour, alpha))
		var edge: PackedVector2Array = shape.duplicate()
		edge.append(shape[0])
		draw_polyline(edge, Color(OUTLINE_COLOR, OUTLINE_COLOR.a * alpha), 1.0)
	else:
		draw_circle(Vector2.ZERO, _shape.radius if _shape != null else 6.0, Color(_colour, alpha))

## `art` moved so its bounding box is centred on the origin: the loaded art is
## authored where it sits on the head, and in flight it is drawn round the
## flying circle.
func _centred(art: PackedVector2Array) -> PackedVector2Array:
	if art.is_empty():
		return art
	var box := Rect2(art[0], Vector2.ZERO)
	for p: Vector2 in art:
		box = box.expand(p)
	var centre: Vector2 = box.get_center()
	var out := PackedVector2Array()
	for p: Vector2 in art:
		out.append(p - centre)
	return out
