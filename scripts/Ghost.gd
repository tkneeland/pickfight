extends Node2D

## A knocked-out player's ghost (issues #324, #660). Their controller still
## drives it, but it only shows while they are actually touching their controls
## (or carrying something): it fades in within a moment of input and out again
## `HOLD_SEC + FADE_OUT_SEC` after the last touch, so an idle KO'd player leaves
## nothing on screen.
##
## Harmless by construction: no collision shape, layer or mask, and it never
## damages a player. Its one button is a context action: near a loose pickup
## and empty-handed it grabs it (the pickup rides along, attached); carrying,
## it drops it (the pickup falls); otherwise it Boos, a short shove on the
## nearest living rival, never a teammate, on a cooldown. A boo is not a hit:
## no damage, no KO credit.
##
## Input comes from the owning `Player`: `input_vector` (phone joystick, gamepad
## stick: zero means not touching), `take_ghost_mouse()` (a mouse's raw motion,
## which moves the ghost like a cursor, 1:1, and stops when the mouse stops)
## and `take_ghost_actions()`.

const PickupGroup: StringName = &"pickups"
const PlayerGroup: StringName = &"players"
## Input shorter than this is not a touch.
const TOUCH_THRESHOLD: float = 0.1
const SPEED: float = 260.0
## Floaty: slow to get going, slow to stop.
const ACCEL: float = 500.0
const DRAG: float = 350.0
const FADE_IN_SEC: float = 0.15
## Fully visible this long after the last touch, then gone over FADE_OUT_SEC.
const HOLD_SEC: float = 1.0
const FADE_OUT_SEC: float = 0.5
const MAX_ALPHA: float = 0.5
const RADIUS: float = 16.0
## An action within this of a loose pickup grabs it.
const GRAB_RADIUS: float = 60.0
## A carried pickup hangs this far off the ghost's centre.
const CARRY_OFFSET: Vector2 = Vector2(0.0, -26.0)
## A boo reaches this far, shoves with this impulse, then waits this long.
const BOO_RADIUS: float = 120.0
const BOO_IMPULSE: float = 450.0
const BOO_COOLDOWN_SEC: float = 3.0
const BOO_PUFF_SEC: float = 0.4

var slot: int = -1
var colour: Color = Color.WHITE
## Where the ghost may roam (world space).
var bounds: Rect2 = Rect2(-100000, -100000, 200000, 200000)
var _player: Node = null
var _velocity: Vector2 = Vector2.ZERO
var _alpha: float = 0.0
var _idle_sec: float = 0.0
## Once a seat's mouse has moved the ghost, the mouse owns it: a mouse's drag
## vector never returns to zero, so reading it would keep the ghost flying.
var _mouse_driven: bool = false
var _carried: Node2D = null
var _boo_cooldown: float = 0.0
var _puff_age: float = BOO_PUFF_SEC

func setup(for_player: Node, for_slot: int, at: Vector2, area: Rect2, tint: Color) -> void:
	_player = for_player
	slot = for_slot
	colour = tint
	bounds = area
	z_as_relative = false
	z_index = 0
	global_position = _clamped(at)
	if _player != null and _player.has_method("take_ghost_mouse"):
		_player.take_ghost_mouse() # nothing queued before the ghost existed counts
		_player.take_ghost_actions()

## Whether the ghost can be seen right now.
func is_shown() -> bool:
	return _alpha > 0.01

func alpha() -> float:
	return _alpha

func velocity() -> Vector2:
	return _velocity

## The pickup it is carrying, or null.
func carried() -> Node2D:
	return _carried if _carried != null and is_instance_valid(_carried) else null

func boo_cooldown_left() -> float:
	return _boo_cooldown

func _clamped(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, bounds.position.x, bounds.end.x), clampf(p.y, bounds.position.y, bounds.end.y))

## World units per screen pixel: a mouse's `relative` is in viewport pixels.
func _world_per_px() -> float:
	var zoom: Vector2 = get_viewport().get_canvas_transform().get_scale() if is_inside_tree() else Vector2.ONE
	var factor: float = (zoom.x + zoom.y) * 0.5
	if not is_finite(factor) or factor <= 0.0001:
		return 1.0
	return 1.0 / factor

func _physics_process(delta: float) -> void:
	var v: Vector2 = Vector2.ZERO
	var mouse_px: Vector2 = Vector2.ZERO
	var actions: int = 0
	if _player != null and is_instance_valid(_player):
		v = _player.input_vector
		mouse_px = _player.take_ghost_mouse()
		actions = _player.take_ghost_actions()
	if mouse_px != Vector2.ZERO:
		_mouse_driven = true
	var touching: bool
	if _mouse_driven:
		touching = mouse_px != Vector2.ZERO
		_velocity = Vector2.ZERO
		global_position = _clamped(global_position + mouse_px * _world_per_px())
	else:
		touching = v.length() >= TOUCH_THRESHOLD
		_velocity = _velocity.move_toward(v * SPEED if touching else Vector2.ZERO, (ACCEL if touching else DRAG) * delta)
		global_position = _clamped(global_position + _velocity * delta)
	_boo_cooldown = maxf(0.0, _boo_cooldown - delta)
	_puff_age += delta
	for _i in actions:
		_act()
	if actions > 0:
		touching = true
	if carried() != null:
		carried().global_position = global_position + CARRY_OFFSET
	var active: bool = touching or carried() != null
	if active:
		_idle_sec = 0.0
		_alpha = minf(MAX_ALPHA, _alpha + MAX_ALPHA * delta / FADE_IN_SEC)
	else:
		_idle_sec += delta
		if _idle_sec > HOLD_SEC:
			_alpha = maxf(0.0, _alpha - MAX_ALPHA * delta / FADE_OUT_SEC)
	queue_redraw()

## The one button: drop what it carries, else grab a pickup in reach, else boo.
func _act() -> void:
	if carried() != null:
		_drop()
		return
	var pickup: Node2D = _nearest_pickup()
	if pickup != null:
		_carried = pickup
		pickup.carry_by(self)
		pickup.global_position = global_position + CARRY_OFFSET
		return
	_boo()

func _nearest_pickup() -> Node2D:
	var best: Node2D = null
	var best_dist: float = GRAB_RADIUS
	for node: Node in get_tree().get_nodes_in_group(PickupGroup):
		var pickup: Node2D = node as Node2D
		if pickup == null or not is_instance_valid(pickup) or pickup.is_queued_for_deletion() or not pickup.has_method("carry_by"):
			continue
		if pickup.is_carried():
			continue
		var dist: float = pickup.global_position.distance_to(global_position)
		if dist <= best_dist:
			best = pickup
			best_dist = dist
	return best

func _drop() -> void:
	var pickup: Node2D = carried()
	_carried = null
	if pickup != null and not pickup.is_queued_for_deletion():
		pickup.drop()

func _boo() -> void:
	if _boo_cooldown > 0.0:
		return
	var target: RigidBody2D = null
	var best_dist: float = BOO_RADIUS
	for node: Node in get_tree().get_nodes_in_group(PlayerGroup):
		var rival := node as RigidBody2D
		if rival == null or rival == _player or not rival.alive:
			continue
		if _player != null and _player.is_teammate(rival):
			continue
		var dist: float = rival.global_position.distance_to(global_position)
		if dist <= best_dist:
			target = rival
			best_dist = dist
	if target == null:
		return
	var away: Vector2 = (target.global_position - global_position).normalized()
	if away == Vector2.ZERO:
		away = Vector2.UP
	target.apply_central_impulse(away * BOO_IMPULSE)
	_boo_cooldown = BOO_COOLDOWN_SEC
	_puff_age = 0.0
	var sfx: Node = get_node_or_null(^"/root/Sfx")
	if sfx != null:
		sfx.play(&"ghost_boo", global_position, 0.7)

## The ghost going away (round end) lets go of what it carries.
func _exit_tree() -> void:
	if _carried != null and is_instance_valid(_carried) and not _carried.is_queued_for_deletion():
		_carried.drop()
	_carried = null

func _draw() -> void:
	if _puff_age < BOO_PUFF_SEC:
		var t: float = _puff_age / BOO_PUFF_SEC
		draw_arc(Vector2.ZERO, lerpf(RADIUS, BOO_RADIUS, t), 0.0, TAU, 32, Color(colour.r, colour.g, colour.b, 0.6 * (1.0 - t)), 3.0)
	if not is_shown():
		return
	var body := Color(colour.r, colour.g, colour.b, _alpha)
	draw_circle(Vector2.ZERO, RADIUS, body)
	# A little tail so it reads as a ghost, not a ball.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-RADIUS, 0.0), Vector2(RADIUS, 0.0), Vector2(RADIUS * 0.6, RADIUS * 1.3),
		Vector2(0.0, RADIUS * 0.8), Vector2(-RADIUS * 0.6, RADIUS * 1.3)]), body)
	var eye := Color(0.1, 0.1, 0.15, _alpha * 1.4)
	draw_circle(Vector2(-5.0, -3.0), 2.5, eye)
	draw_circle(Vector2(5.0, -3.0), 2.5, eye)
