extends Node2D

## The grappling hook's hook, out of the launcher and on its rope (issue
## #150). `Player` fires one when a player holding the grapple flicks, and
## tells it every tick whether the drag is still held.
##
## - **Flying**: straight out along the flick at `projectile_speed`, no
##   gravity, until it meets something or runs out of rope (`launch_range`).
## - **Stuck**: it met terrain and holds on to it -- to the spot on that body,
##   so a moving or rotating platform carries it. While the drag is held the
##   rope hauls in at `reel_speed`, pulling the body toward the hook with at
##   most `reel_force`, down to `reel_min_length`, where it holds and the
##   player hangs and swings. The rope only ever pulls.
## - **A player**: a hook that meets another player takes a light, flat
##   `projectile_damage` off them and tugs them toward the thrower
##   (`projectile_knockback`), then comes home. It is a traversal tool, not a
##   gun.
## - **Home**: releasing the drag lets go at once: the hook stops pulling and
##   reels back into the launcher, colliding with nothing.
##
## **Swept, never discretely collided**, like the boomstick's bullet
## (`Projectile.gd`): each tick it shape-casts its circle along the motion it
## is about to make and stops at the first contact, so it cannot pass through
## a thin platform however fast it flies. Weapon heads do not stop it.
##
## Damage goes through the thrower (`Player.land_projectile_hit`), so a hook
## hit is a `strike_landed` like any other: hitmarker, buzz, kill feed credit
## and awards all see it.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

enum State { FLYING, STUCK, HOME }

## Player.LAYER_WORLD, repeated so this script need not preload the player.
const LAYER_WORLD: int = 1
## Every live hook is in this group, which is how scenarios find them.
const GROUP: StringName = &"grapple_hooks"
## How fast a released hook reels home, and how close it has to get.
const HOME_SPEED: float = 2600.0
const HOME_REACHED: float = 12.0
const ROPE_WIDTH: float = 2.0
const ROPE_COLOR: Color = Color(0.85, 0.8, 0.65, 0.9)
const OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.8)

## The hook met `collider` (terrain or a player) at `point`. A sound hook
## (ADR-0016), the same signal a bullet has; gameplay ignores it.
signal impacted(collider: Object, point: Vector2)

var shooter: RigidBody2D
var direction: Vector2 = Vector2.RIGHT
var state: State = State.FLYING
## How long the rope is allowed to be right now, once the hook has stuck.
var rope_length: float = 0.0
## Pixels flown so far on the way out.
var travelled: float = 0.0

var _stats: Resource
var _origin: Vector2 = Vector2.ZERO
var _shape: CircleShape2D
var _held: bool = true
var _stuck_to: Node2D
var _stuck_local: Vector2 = Vector2.ZERO
var _colour: Color = Color.WHITE
var _art: PackedVector2Array = PackedVector2Array()

func setup(from_shooter: RigidBody2D, origin: Vector2, flight: Vector2, stats: Resource) -> void:
	shooter = from_shooter
	_origin = origin
	_stats = stats
	direction = flight.normalized() if flight != Vector2.ZERO else Vector2.RIGHT
	var identity: Variant = from_shooter.get("identity_color") if from_shooter != null else null
	_colour = identity if identity is Color else Color.WHITE
	_art = _centred(stats.loaded_art)

func _ready() -> void:
	add_to_group(GROUP)
	z_index = 45
	global_position = _origin
	rotation = direction.angle()
	reset_physics_interpolation()
	_shape = CircleShape2D.new()
	_shape.radius = maxf(0.5, float(_stats.projectile_radius))

## Whether the player is still holding the drag. Releasing it lets go.
func set_held(held: bool) -> void:
	_held = held
	if not held and state != State.HOME:
		state = State.HOME

func is_stuck() -> bool:
	return state == State.STUCK

func is_flying() -> bool:
	return state == State.FLYING

func is_going_home() -> bool:
	return state == State.HOME

func _physics_process(delta: float) -> void:
	if not _shooter_in_play():
		queue_free()
		return
	match state:
		State.FLYING:
			_fly(delta)
		State.STUCK:
			_hold(delta)
		State.HOME:
			_go_home(delta)
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _fly(delta: float) -> void:
	var step: float = float(_stats.projectile_speed) * delta
	var left: float = float(_stats.launch_range) - travelled
	if left <= 0.0:
		state = State.HOME
		return
	var motion: Vector2 = direction * minf(step, left)
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape
	query.transform = Transform2D(0.0, global_position)
	query.motion = motion
	query.collision_mask = LAYER_WORLD
	query.exclude = [shooter.get_rid()]
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var fractions: PackedFloat32Array = space.cast_motion(query)
	var unsafe: float = fractions[1] if fractions.size() >= 2 else 1.0
	if unsafe >= 1.0:
		global_position += motion
		travelled += motion.length()
		return
	global_position += motion * unsafe
	travelled += motion.length() * unsafe
	query.transform = Transform2D(0.0, global_position)
	query.motion = Vector2.ZERO
	var collider: Object = null
	var point: Vector2 = global_position + direction * _shape.radius
	var rest: Dictionary = space.get_rest_info(query)
	if not rest.is_empty():
		collider = instance_from_id(rest["collider_id"])
		point = rest["point"]
	else:
		var overlaps: Array[Dictionary] = space.intersect_shape(query, 1)
		if not overlaps.is_empty():
			collider = overlaps[0]["collider"]
	_meet(collider, point)

func _meet(collider: Object, point: Vector2) -> void:
	impacted.emit(collider, point)
	var node: Node = collider as Node
	if node != null and node.is_in_group("players"):
		if node != shooter and bool(node.get("alive")):
			if node is RigidBody2D:
				var toward: Vector2 = (shooter.global_position - (node as Node2D).global_position).normalized()
				(node as RigidBody2D).apply_central_impulse(toward * float(_stats.projectile_knockback))
			shooter.land_projectile_hit(node, float(_stats.projectile_damage), point)
		state = State.HOME
		return
	if node is Node2D and _solid(node):
		_stuck_to = node as Node2D
		_stuck_local = _stuck_to.to_local(global_position)
		state = State.STUCK
		rope_length = maxf((global_position - shooter.global_position).length(), float(_stats.reel_min_length))
		return
	state = State.HOME

func _hold(delta: float) -> void:
	if not is_instance_valid(_stuck_to) or not _stuck_to.is_inside_tree() or not _solid(_stuck_to):
		state = State.HOME
		return
	global_position = _stuck_to.to_global(_stuck_local)
	if not _held:
		state = State.HOME
		return
	var to_hook: Vector2 = global_position - shooter.global_position
	var distance: float = to_hook.length()
	var shortest: float = float(_stats.reel_min_length)
	# A reel takes up slack as well as hauling in: the rope is never longer
	# than the player is from the hook, so it pulls from wherever they are.
	rope_length = minf(rope_length, maxf(distance, shortest))
	rope_length = maxf(rope_length - float(_stats.reel_speed) * delta, shortest)
	var excess: float = distance - rope_length
	if excess <= 0.0 or distance <= 0.0:
		return
	var along: Vector2 = to_hook / distance
	var toward: float = shooter.linear_velocity.dot(along)
	var wanted: float = minf(excess / delta, float(_stats.reel_speed))
	var force: float = clampf((wanted - toward) * shooter.mass / delta, 0.0, float(_stats.reel_force))
	shooter.apply_central_force(along * force)

func _go_home(delta: float) -> void:
	var home: Vector2 = shooter.weapon_head_position()
	var to_home: Vector2 = home - global_position
	var step: float = HOME_SPEED * delta
	if to_home.length() <= maxf(step, HOME_REACHED):
		queue_free()
		return
	global_position += to_home.normalized() * step
	rotation = (-to_home).angle()

## Whether `node` is something a hook can hold: terrain that is still there.
## A breakable wall that has broken is not.
func _solid(node: Node) -> bool:
	if node.has_method("is_solid"):
		return bool(node.call("is_solid"))
	return true

func _shooter_in_play() -> bool:
	return is_instance_valid(shooter) and bool(shooter.get("alive"))

func _draw() -> void:
	if not is_instance_valid(shooter):
		return
	var from: Vector2 = to_local(shooter.weapon_head_position())
	draw_line(from, Vector2.ZERO, OUTLINE_COLOR, ROPE_WIDTH + 1.5)
	draw_line(from, Vector2.ZERO, ROPE_COLOR, ROPE_WIDTH)
	if _art.size() >= 3:
		draw_colored_polygon(_art, _colour)
		var edge: PackedVector2Array = _art.duplicate()
		edge.append(_art[0])
		draw_polyline(edge, OUTLINE_COLOR, 1.0)
	else:
		draw_circle(Vector2.ZERO, _shape.radius if _shape != null else 4.0, _colour)

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
