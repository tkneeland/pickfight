extends Node2D

## The grappling hook's hook, out of the launcher and on its rope (issue
## #150). `Player` fires one when a player holding the grapple flicks, and
## tells it every tick whether the drag is still held.
##
## - **Flying**: out along the flick at `projectile_speed` until it meets
##   something or runs out of rope (`launch_range`, measured as distance
##   travelled). Straight when `projectile_gravity` is 0 (the grapple); with
##   gravity the velocity gains it every tick, so the line arcs (the fishing
##   rod, #625), and the hook faces along its velocity.
## - **Stuck**: it met terrain further off than the arm reaches (terrain
##   closer than that the arm can plant on itself, so the hook comes home)
##   and holds on to it -- to the spot on that body, so a moving or
##   rotating platform carries it. While the drag is held the rope hauls
##   in at `reel_speed`, pulling the body toward the hook with at most
##   `reel_force`, down to `reel_min_length`, where it holds and the player
##   hangs and swings. The rope only ever pulls.
## - **A player (grapple, #630)**: a hook with `hook_anchors_to_players`
##   deals `projectile_damage` (nothing to a teammate) and then sticks to that
##   player's body exactly as to terrain, so the thrower zips to them. The
##   rope pulls only the thrower; the anchor feels nothing. It lets go on
##   release or when either player is KO'd, with no time limit.
## - **A player (other hooks)**: a hook that meets another player takes a light, flat
##   `projectile_damage` off them and tugs them toward the thrower
##   (`projectile_knockback`), then comes home. It is a traversal tool, not a
##   gun.
## - **Reeling** (the fishing rod, `hook_reels_players`, #629): the rod moves
##   what it hits to you. It never sticks to terrain (it comes home empty); a
##   player it meets takes the flat damage and is pulled toward the thrower by
##   `reel_force` on their body each tick, the hook riding on them. The reel
##   breaks when the drag is released, the victim arrives within
##   `reel_min_length`, either player is KO'd, or `hook_reel_limit` passes. A
##   hit on the holder does not break it. A teammate is reeled, undamaged.
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

enum State { FLYING, STUCK, HOME, REELING }

## Player.LAYER_WORLD, repeated so this script need not preload the player.
const LAYER_WORLD: int = 1
## Every live hook is in this group, which is how scenarios find them.
const GROUP: StringName = &"grapple_hooks"
## How fast a released hook reels home, and how close it has to get.
const HOME_SPEED: float = 2600.0
const HOME_REACHED: float = 12.0
## How far past the arm's `max_reach` terrain has to be for the hook to hold.
const STICK_MARGIN: float = 16.0
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
## The flight velocity, px/s. Starts at `direction * projectile_speed`.
var _velocity: Vector2 = Vector2.ZERO
var _origin: Vector2 = Vector2.ZERO
var _shape: CircleShape2D
var _held: bool = true
var _reeled: RigidBody2D
var _reel_time: float = 0.0
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
	_velocity = direction * float(stats.projectile_speed)

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

func is_reeling() -> bool:
	return state == State.REELING

## The player being reeled in, or null.
func reeled_player() -> RigidBody2D:
	return _reeled if state == State.REELING and is_instance_valid(_reeled) else null

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
		State.REELING:
			_reel(delta)
		State.HOME:
			_go_home(delta)
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _fly(delta: float) -> void:
	var left: float = float(_stats.launch_range) - travelled
	if left <= 0.0:
		state = State.HOME
		return
	var gravity: float = float(_stats.projectile_gravity)
	if gravity != 0.0:
		_velocity.y += gravity * delta
		if _velocity.length_squared() > 0.0:
			direction = _velocity.normalized()
			rotation = direction.angle()
	var motion: Vector2 = (_velocity * delta).limit_length(left)
	if _shield_holder_blocking(global_position, global_position + motion, _shape.radius) != null:
		state = State.HOME
		return
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
		if bool(_stats.hook_anchors_to_players) and node != shooter and bool(node.get("alive")) and node is Node2D:
			# Zipping (#630): the grapple moves *you* to what it hits, so a
			# player is an anchor like a wall, even inside arm's reach (a
			# player is not a surface the arm plants on). Teammates are
			# anchored too; `land_projectile_hit` deals them nothing.
			shooter.land_projectile_hit(node, float(_stats.projectile_damage), point)
			_stuck_to = node as Node2D
			_stuck_local = _stuck_to.to_local(global_position)
			state = State.STUCK
			rope_length = maxf((global_position - shooter.global_position).length(), float(_stats.reel_min_length))
			return
		if node != shooter and bool(node.get("alive")):
			if bool(_stats.hook_reels_players) and node is RigidBody2D:
				shooter.land_projectile_hit(node, float(_stats.projectile_damage), point)
				if bool(node.get("alive")):
					_reeled = node as RigidBody2D
					_reel_time = 0.0
					state = State.REELING
				else:
					state = State.HOME
				return
			if node is RigidBody2D:
				var toward: Vector2 = (shooter.global_position - (node as Node2D).global_position).normalized()
				(node as RigidBody2D).apply_central_impulse(toward * float(_stats.projectile_knockback))
			shooter.land_projectile_hit(node, float(_stats.projectile_damage), point)
		state = State.HOME
		return
	# Terrain inside the arm's own reach is somewhere the arm can already
	# plant, so a hook there does not hold: it would only fight the plant (a
	# flick down to vault fires the hook into the floor underfoot).
	if bool(_stats.hook_reels_players):
		state = State.HOME
		return
	var close: bool = (global_position - shooter.global_position).length() <= float(_stats.max_reach) + STICK_MARGIN
	if node is Node2D and _solid(node) and not close:
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
	# An anchored player who is KO'd (or rung out) lets go; no time limit.
	if _stuck_to.is_in_group("players") and not bool(_stuck_to.get("alive")):
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

func _reel(delta: float) -> void:
	if not is_instance_valid(_reeled) or not bool(_reeled.get("alive")) or not _held:
		state = State.HOME
		return
	_reel_time += delta
	var to_holder: Vector2 = shooter.global_position - _reeled.global_position
	var distance: float = to_holder.length()
	if _reel_time >= float(_stats.hook_reel_limit) or distance <= float(_stats.reel_min_length):
		state = State.HOME
		return
	global_position = _reeled.global_position
	rotation = (-to_holder).angle()
	_reeled.apply_central_force(to_holder / distance * float(_stats.reel_force))

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
