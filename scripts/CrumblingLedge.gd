extends StaticBody2D

## Crumbling ledge (issue #18, "Crumbling ledge" bullet; US-3, US-4, US-7,
## US-8): solid ground until a player rests on it, then it falls away and
## comes back on its own.
##
## Never freed and re-instanced -- a stage part must not churn nodes
## mid-round. "Away" is this same node with its `CollisionShape2D` disabled
## and its `Polygon2D` dimmed, not a different node.
##
## A `StaticBody2D` does not report contacts on its own, so detection is a
## child `Area2D` sitting just above the ledge's top surface. It only cares
## about bodies in the `players` group -- `KillZone.gd` is the prior art for
## that check -- so a player's own body triggers it, exactly as a player's
## own body is what any other terrain in this game already collides with.
##
## Three states, one cycle, run to completion once started:
##   SOLID    -- normal terrain colour, collision on.
##   WARNING  -- entered on first player contact. Still solid (US-3: the
##               warning is time to react, not an instant drop), visual
##               changes so the player sees it coming.
##   AWAY     -- collision off, visual dimmed. Returns to SOLID on its own
##               after `away_sec`; a body touching it again mid-cycle does
##               not restart anything -- the cycle runs to completion once
##               it starts.
##
## Exports, and only these: a stage author sets numbers and never edits the
## sub-resources `_ready()` builds from them.
@export var size: Vector2 = Vector2(200, 24)
@export var warn_sec: float = 0.8
@export var away_sec: float = 3.0

enum _LedgeState { SOLID, WARNING, AWAY }

const SOLID_COLOR: Color = Color(0.35, 0.35, 0.4, 1)
## Amber: visibly distinct from the terrain grey-blue above, read as
## "caution" rather than "danger" -- the ledge is still holding.
const WARNING_COLOR: Color = Color(0.85, 0.6, 0.15, 1)
## Same hue as SOLID_COLOR, low alpha: reads as the same ledge, just not
## there right now, rather than a different piece of geometry.
const AWAY_COLOR: Color = Color(0.35, 0.35, 0.4, 0.25)

## How far above the ledge's top surface the detector's band starts, and how
## far it dips below that surface. A resting player's collision circle
## touches the surface at a single point in the ideal case, so the band dips
## a couple of pixels below the surface to keep catching it once the solver
## has settled the small penetration real contact leaves behind.
const _DETECTOR_ABOVE: float = 10.0
const _DETECTOR_BELOW: float = 2.0

var _state: _LedgeState = _LedgeState.SOLID
var _timer_remaining: float = 0.0
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

	_detector = Area2D.new()
	_detector.name = "Detector"
	# Nothing needs to detect the detector, only monitor for bodies on the
	# world layer every terrain `StaticBody2D` in this game already defaults
	# to (`Player.LAYER_WORLD`, preloading Player.gd here would be a heavier
	# coupling than a repo-wide constant is worth).
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
	_detector.body_entered.connect(_on_body_entered)

## The colour the ledge is currently showing -- an observable seam a
## scenario can assert on without reaching past this script into a child
## node it does not own the name of.
func visual_color() -> Color:
	return _visual.color

func _on_body_entered(body: Node) -> void:
	if _state != _LedgeState.SOLID:
		return
	if not body.is_in_group("players"):
		return
	_state = _LedgeState.WARNING
	_timer_remaining = warn_sec
	_visual.color = WARNING_COLOR

func _physics_process(delta: float) -> void:
	if _state == _LedgeState.SOLID:
		return
	_timer_remaining -= delta
	if _timer_remaining > 0.0:
		return
	match _state:
		_LedgeState.WARNING:
			_state = _LedgeState.AWAY
			_timer_remaining = away_sec
			_visual.color = AWAY_COLOR
			# Toggling collision from inside a physics callback has to be
			# deferred -- doing it synchronously here crashes with "flushing
			# queries" mid-step. Deferred is correct either way, so it is
			# done unconditionally rather than only when strictly needed.
			_collision_shape.set_deferred("disabled", true)
		_LedgeState.AWAY:
			_state = _LedgeState.SOLID
			_visual.color = SOLID_COLOR
			_collision_shape.set_deferred("disabled", false)
