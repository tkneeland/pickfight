extends Node2D

## A knocked-out player's ghost (issue #324). Their phone still drives it, but
## it only shows while they are actually touching their controls: it fades in
## within a moment of input and out again `HOLD_SEC + FADE_OUT_SEC` after the
## last touch, so an idle KO'd player leaves nothing on screen.
##
## Harmless by construction: no collision shape, layer or mask, and it never
## touches a player. All it can do is nudge loose pickups, a little and never
## far from where they spawned, so a ghost cannot kingmake.
##
## The input is the owning player's `input_vector`, which `ControllerServer`
## keeps writing to an eliminated player exactly as to a live one (zero means
## not touching).

const PickupGroup: StringName = &"pickups"
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
## A pickup within this of the ghost is carried along at NUDGE_FRACTION of the
## ghost's velocity, and never further than MAX_NUDGE from where it started.
const NUDGE_RADIUS: float = 40.0
const NUDGE_FRACTION: float = 0.2
const MAX_NUDGE: float = 60.0
const HOME_META: StringName = &"ghost_home"

var slot: int = -1
var colour: Color = Color.WHITE
## Where the ghost may roam (world space).
var bounds: Rect2 = Rect2(-100000, -100000, 200000, 200000)
var _player: Node = null
var _velocity: Vector2 = Vector2.ZERO
var _alpha: float = 0.0
var _idle_sec: float = 0.0

func setup(for_player: Node, for_slot: int, at: Vector2, area: Rect2, tint: Color) -> void:
	_player = for_player
	slot = for_slot
	colour = tint
	bounds = area
	z_as_relative = false
	z_index = 0
	global_position = Vector2(clampf(at.x, area.position.x, area.end.x), clampf(at.y, area.position.y, area.end.y))

## Whether the ghost can be seen right now.
func is_shown() -> bool:
	return _alpha > 0.01

func alpha() -> float:
	return _alpha

func velocity() -> Vector2:
	return _velocity

func _physics_process(delta: float) -> void:
	var v: Vector2 = Vector2.ZERO
	if _player != null and is_instance_valid(_player):
		v = _player.input_vector
	var touching: bool = v.length() >= TOUCH_THRESHOLD
	if touching:
		_idle_sec = 0.0
		_alpha = minf(MAX_ALPHA, _alpha + MAX_ALPHA * delta / FADE_IN_SEC)
		_velocity = _velocity.move_toward(v * SPEED, ACCEL * delta)
	else:
		_idle_sec += delta
		_velocity = _velocity.move_toward(Vector2.ZERO, DRAG * delta)
		if _idle_sec > HOLD_SEC:
			_alpha = maxf(0.0, _alpha - MAX_ALPHA * delta / FADE_OUT_SEC)
	var next: Vector2 = global_position + _velocity * delta
	next = Vector2(clampf(next.x, bounds.position.x, bounds.end.x), clampf(next.y, bounds.position.y, bounds.end.y))
	global_position = next
	if is_shown() and _velocity != Vector2.ZERO:
		_nudge_pickups(delta)
	queue_redraw()

func _nudge_pickups(delta: float) -> void:
	for node: Node in get_tree().get_nodes_in_group(PickupGroup):
		var pickup: Node2D = node as Node2D
		if pickup == null or not is_instance_valid(pickup) or pickup.is_queued_for_deletion():
			continue
		if pickup.global_position.distance_to(global_position) > NUDGE_RADIUS:
			continue
		if not pickup.has_meta(HOME_META):
			pickup.set_meta(HOME_META, pickup.global_position)
		var home: Vector2 = pickup.get_meta(HOME_META)
		var moved: Vector2 = pickup.global_position + _velocity * NUDGE_FRACTION * delta
		pickup.global_position = home + (moved - home).limit_length(MAX_NUDGE)

func _draw() -> void:
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
