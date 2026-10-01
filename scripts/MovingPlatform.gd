extends AnimatableBody2D

## Moving platform stage part (issue #18: US-1, US-2, US-7, US-8).
##
## AnimatableBody2D, not StaticBody2D or CharacterBody2D: it is a kinematic
## body moved entirely by script, and with `sync_to_physics` on it reports
## that motion to the physics engine as a swept, velocity-carrying move. That
## is what lets a resting player be carried along rather than sliding out
## from under them (US-2), and what keeps a fast weapon head from tunnelling
## through it the way an unswept teleport could (US-7).
##
## `_ready()` builds the `CollisionShape2D`'s `RectangleShape2D` and the
## `Polygon2D` from `size` so a stage author places this scene, sets a
## handful of exported numbers, and never opens a sub-resource (US-8).
##
## Motion is a ping-pong between the authored position (the "near end") and
## that position plus `travel` (the "far end"), driven every physics tick by
## assigning `global_position` directly -- no `Tween`, no `AnimationPlayer`,
## so a stage's patrol is fully described by the two exported vectors and a
## duration, readable off the platform itself rather than off a side asset.

## The platform's collision and visual box, centred on the node.
@export var size: Vector2 = Vector2(200, 24)
## Offset of the far end of the patrol from the node's authored position.
@export var travel: Vector2 = Vector2(400, 0)
## Time, in seconds, to cross one leg of the patrol (near end to far end, or
## back).
@export var one_way_sec: float = 2.0
## When false the platform sits at its near end -- the authored position --
## until something calls `start()`. Nothing in the stage rotation calls it
## yet; it exists so a stage can place a platform that waits for a cue.
@export var starts_moving: bool = true
## Optional loop path: offsets from the authored position. When non-empty the
## platform ignores `travel` and cycles origin -> each point -> origin, taking
## `one_way_sec` per leg, instead of ping-ponging.
@export var loop_points: PackedVector2Array = PackedVector2Array()

## The authored position, read once in `_ready()`. Never recomputed from the
## current position -- doing so would let floating-point drift or an
## external nudge walk the patrol's endpoints away from what the stage
## author set.
var _origin: Vector2
var _moving: bool = false
var _heading_to_far: bool = true
var _leg_elapsed: float = 0.0
var _leg_index: int = 0
var _visual: Polygon2D

func _ready() -> void:
	sync_to_physics = true
	_origin = global_position

	var collision_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	collision_shape.shape = rect
	add_child(collision_shape)

	var visual := Polygon2D.new()
	# The existing stages' terrain is Color(0.35, 0.35, 0.4, 1); lightened
	# and given a cool tint so a moving platform reads as distinct from
	# static ground at a glance.
	visual.color = Color(0.55, 0.6, 0.85, 1)
	var half: Vector2 = size / 2.0
	visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	add_child(visual)
	_visual = visual

	_moving = starts_moving

## Recolours the platform; Stage.gd calls this with the mood's platform colour.
func set_platform_color(color: Color) -> void:
	if _visual != null:
		_visual.color = color

func platform_color() -> Color:
	return _visual.color if _visual != null else Color.BLACK

## Starts the patrol for a platform authored with `starts_moving = false`.
## Safe to call more than once; a platform already moving just keeps going.
func start() -> void:
	_moving = true

func _physics_process(delta: float) -> void:
	if not _moving:
		return

	var duration: float = maxf(one_way_sec, 0.001)
	_leg_elapsed += delta
	if not loop_points.is_empty():
		while _leg_elapsed >= duration:
			_leg_elapsed -= duration
			_leg_index = (_leg_index + 1) % (loop_points.size() + 1)
		var count: int = loop_points.size() + 1
		var from: Vector2 = Vector2.ZERO if _leg_index == 0 else loop_points[_leg_index - 1]
		var next: int = (_leg_index + 1) % count
		var to: Vector2 = Vector2.ZERO if next == 0 else loop_points[next - 1]
		global_position = _origin + from.lerp(to, _leg_elapsed / duration)
		return
	while _leg_elapsed >= duration:
		_leg_elapsed -= duration
		_heading_to_far = not _heading_to_far

	var t: float = _leg_elapsed / duration
	var progress: float = t if _heading_to_far else 1.0 - t
	global_position = _origin + travel * progress
