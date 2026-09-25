extends StaticBody2D

## Collapsing floor section (issue #53): solid ground that gives way partway
## through a round and is gone for the rest of it.
##
## Two triggers, picked per instance by `trigger`:
##   "timed"    -- gives way `collapse_after_sec` after the round starts,
##                 whether anyone is on it or not: the stage shrinking on a
##                 schedule everyone can learn.
##   "stood_on" -- gives way once players have stood on it for `stand_sec`
##                 in total: ground that wears out under whoever camps it.
##                 Total rather than unbroken, so hopping on and off does not
##                 reset the wear.
##
## Either way there is a `warn_sec` warning -- amber, and the slab shakes --
## during which it still holds, then collision goes off and the slab is gone
## until the next round's fresh stage. It never comes back.
##
## **A sibling of `CrumblingLedge`, not an extension of it.** The ledge's
## whole shape is a cycle that returns to SOLID, triggered by the first
## touch; this has two different triggers and a terminal state. Subclassing
## would mean overriding both its contact handler and its state machine --
## everything but `_ready()` -- and CrumblingLedge's behaviour and scenarios
## must not move, so a change to share more code there is not worth the
## risk. What *is* shared is how it looks: the solid and warning colours are
## read off `CrumblingLedge.gd`'s constants, so a stage's two kinds of
## failing ground speak one visual language (grey holds, amber is about to
## go), and the same detector-band trick finds who is standing on it.
##
## Round time is counted in physics ticks from `_ready()`. A stage is
## instanced fresh every round (ADR-0012), so "since this part entered the
## tree" is "since the round started" without asking `RoundManager`, and a
## new round brings a new, solid floor with no reset code.
##
## Never freed and re-instanced -- a stage part must not churn nodes
## mid-round. "Gone" is this same node with its `CollisionShape2D` disabled
## and its `Polygon2D` hidden.
##
## Exports, and only these: a stage author sets numbers and never edits the
## sub-resources `_ready()` builds from them.
@export var size: Vector2 = Vector2(240, 24)
@export_enum("timed", "stood_on") var trigger: String = "stood_on"
## "timed": seconds after round start at which the floor gives way. The
## warning starts `warn_sec` before that.
@export var collapse_after_sec: float = 30.0
## "stood_on": total seconds players must stand on it before the warning
## starts.
@export var stand_sec: float = 1.0
## Seconds of warning, still solid, before the floor is gone.
@export var warn_sec: float = 1.0

## Preloaded for its palette only; see the header.
const LedgeType := preload("res://scripts/CrumblingLedge.gd")

enum _FloorState { SOLID, WARNING, GONE }

const SOLID_COLOR: Color = LedgeType.SOLID_COLOR
const WARNING_COLOR: Color = LedgeType.WARNING_COLOR
## How far the slab's visual (not its collision) shakes during the warning,
## and how fast. Collision stays put: a shaking floor that also moved its
## collider would jostle whoever is standing on it, which is not a warning,
## it is an attack.
const SHAKE_PX: float = 2.5
const SHAKE_HZ: float = 20.0

## Same band CrumblingLedge uses, for the same reason: see its constants.
const _DETECTOR_ABOVE: float = 10.0
const _DETECTOR_BELOW: float = 2.0
const _PLAYERS_GROUP: StringName = &"players"

var _state: _FloorState = _FloorState.SOLID
var _round_elapsed: float = 0.0
var _stood_for: float = 0.0
var _warn_remaining: float = 0.0
var _warn_elapsed: float = 0.0
var _collision_shape: CollisionShape2D
var _visual: Polygon2D
var _detector: Area2D

func _ready() -> void:
	var half: Vector2 = size / 2.0

	var rect := RectangleShape2D.new()
	rect.size = size
	_collision_shape = CollisionShape2D.new()
	_collision_shape.name = "CollisionShape2D"
	_collision_shape.shape = rect
	add_child(_collision_shape)

	_visual = Polygon2D.new()
	_visual.name = "Visual"
	_visual.color = SOLID_COLOR
	_visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	add_child(_visual)
	# Seams across the slab, so it reads as sections that can come apart
	# rather than as the permanent grey ground it shares a colour with.
	for i in range(1, 4):
		var seam := Line2D.new()
		seam.name = "Seam%d" % i
		seam.width = 2.0
		seam.default_color = Color(SOLID_COLOR.darkened(0.45), 1.0)
		var x: float = -half.x + size.x * float(i) / 4.0
		seam.points = PackedVector2Array([Vector2(x - 4.0, -half.y), Vector2(x + 4.0, half.y)])
		_visual.add_child(seam)

	_detector = Area2D.new()
	_detector.name = "Detector"
	# Monitors the world layer (`Player.LAYER_WORLD`) for player bodies,
	# exactly as CrumblingLedge's detector does.
	_detector.collision_layer = 0
	_detector.collision_mask = 1
	_detector.position = Vector2(0, -half.y - _DETECTOR_ABOVE / 2.0 + _DETECTOR_BELOW / 2.0)
	var detector_rect := RectangleShape2D.new()
	detector_rect.size = Vector2(size.x, _DETECTOR_ABOVE + _DETECTOR_BELOW)
	var detector_shape := CollisionShape2D.new()
	detector_shape.name = "DetectorShape"
	detector_shape.shape = detector_rect
	_detector.add_child(detector_shape)
	add_child(_detector)

# --- Observable seams for scenarios -----------------------------------------

## The colour the slab is currently showing; fully transparent once gone.
func visual_color() -> Color:
	return _visual.color if _visual.visible else Color(0, 0, 0, 0)

## "solid", "warning" or "gone".
func state_name() -> String:
	return ["solid", "warning", "gone"][_state]

## Whether the slab's collision is on. Reads the shape itself, so it reports
## what the physics server will do rather than what the state machine meant.
func is_solid() -> bool:
	return not _collision_shape.disabled

# --- Cycle ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	match _state:
		_FloorState.SOLID:
			_round_elapsed += delta
			if trigger == "timed":
				if _round_elapsed >= collapse_after_sec - warn_sec:
					_begin_warning(collapse_after_sec - _round_elapsed)
			elif _player_standing():
				_stood_for += delta
				if _stood_for >= stand_sec:
					_begin_warning(warn_sec)
		_FloorState.WARNING:
			_warn_remaining -= delta
			_warn_elapsed += delta
			_visual.position = Vector2(sin(_warn_elapsed * TAU * SHAKE_HZ) * SHAKE_PX, 0.0)
			if _warn_remaining <= 0.0:
				_give_way()

func _player_standing() -> bool:
	for body: Node2D in _detector.get_overlapping_bodies():
		if body.is_in_group(_PLAYERS_GROUP):
			return true
	return false

func _begin_warning(seconds: float) -> void:
	_state = _FloorState.WARNING
	_warn_remaining = maxf(seconds, 0.0)
	_sfx(&"floor_warning", global_position)
	_warn_elapsed = 0.0
	_visual.color = WARNING_COLOR

func _give_way() -> void:
	_state = _FloorState.GONE
	_sfx(&"floor_collapse", global_position)
	_visual.position = Vector2.ZERO
	_visual.visible = false
	# Deferred, as in CrumblingLedge: toggling collision mid-physics-step is
	# refused, and deferred is correct from anywhere.
	_collision_shape.set_deferred("disabled", true)
	_detector.set_deferred("monitoring", false)
	# Nothing left to count or animate for the rest of the round.
	set_physics_process(false)

## Asks the Sfx autoload for `sound` (issue #76). Looked up by path, never by
## name, so this part still works in a tree without the autoload.
func _sfx(sound: StringName, at: Vector2, strength: float = 1.0) -> void:
	var sfx: Node = get_node_or_null(^"/root/Sfx")
	if sfx != null:
		sfx.play(sound, at, strength)
