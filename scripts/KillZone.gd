extends Area2D

## Ring-out: falling off the stage eliminates, whatever damage the player had
## taken. Stage geometry is meant to be the sharpest threat in the game, so it
## does not care how healthy anyone is.
##
## The elimination itself belongs to the player -- `Player.eliminate()` is
## the one path both routes out of a round take, the other being accumulated
## damage -- so this only decides that one happened.
##
## Issue #18 asked for a separate "hazard zone" placed inside the playable
## area rather than beneath it. Built out, it turned out identical to this
## script -- same body_entered check, same eliminate() call, same disregard
## for health -- so it is not a second script. `scenes/parts/Hazard.tscn`
## instances this same script with a hazard's visual and shape; do not add a
## `HazardZone.gd` that would just duplicate this file.

##
## Issue #22 (ADR-0012) lets a stage's floor kill zone rise over a round, to
## put a deadline on it. The rise is opt-in: nothing here starts it, and
## `RoundManager` turns it on only for the node named `KillZone` directly
## under the active stage. Hazards share this script and must never rise, so
## they simply never have `start_rising()` called on them -- which is why it
## is a call rather than an export defaulting to on.

## Seconds before the rise sets off during which its surface pulses, so
## nobody is caught out by a floor that starts climbing without warning.
@export var rise_warning_sec: float = 4.0
## Depth of the rising surface drawn beneath the zone's top edge: enough to
## read as a solid body of lava filling the stage from below, not a strip.
@export var surface_depth: float = 2000.0

## The surface's colour once it is moving: the hazard red-orange of
## `scenes/parts/Hazard.tscn`, translucent so the stage stays readable
## through it. Playtest 1 (#45) found 0.45 too easy to miss, so it is now
## mostly opaque and topped with a bright molten edge.
const SURFACE_COLOR: Color = Color(0.9, 0.2, 0.05, 0.7)
## The bright line along the surface's top, so its height reads at a glance
## even where the lava is behind stage geometry.
const EDGE_COLOR: Color = Color(1.0, 0.75, 0.2, 1.0)
const EDGE_WIDTH: float = 10.0
## Brightest the surface flashes to during the warning, and how fast.
const WARNING_ALPHA: float = 1.0
const WARNING_PULSES_PER_SEC: float = 2.0
## Used when the zone has no rectangle shape to size the surface from.
const FALLBACK_SIZE: Vector2 = Vector2(8000.0, 40.0)

## Sound hooks (issue #75, ADR-0016); nothing in the game reads them.
## `rise_countdown` fires once for each of the last COUNTDOWN_FROM whole
## seconds of the grace period (3, 2, 1), and `rise_began` the tick the floor
## sets off.
signal rise_countdown(seconds_left: int)
signal rise_began
const COUNTDOWN_FROM: int = 3

var _rising: bool = false
var _grace_left: float = 0.0
var _speed: float = 0.0
var _surface: Polygon2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Idle until start_rising(): hazards, and every stage outside a round
	# (the ring-out and spawn scenarios included), never pay for a tick.
	set_physics_process(false)

## Hold still for `grace_sec`, then climb at `speed` px/s until the round
## ends. Draws the rising surface on first call. Physics ticks rather than
## wall-clock, so the rise moves in step with the bodies it is rising into.
func start_rising(grace_sec: float, speed: float) -> void:
	_grace_left = maxf(grace_sec, 0.0)
	_speed = speed
	_rising = true
	_ensure_surface()
	set_physics_process(true)
	if _grace_left <= 0.0:
		rise_began.emit()

## Freeze wherever the zone is now: the round is over, and a surface still
## climbing over the scoreboard or the waiting text would look like a bug.
func stop_rising() -> void:
	_rising = false
	set_physics_process(false)
	if _surface != null:
		_surface.color = SURFACE_COLOR

func is_rising() -> bool:
	return _rising

## The global y of the zone's top edge, where the lava's surface is drawn:
## anything at or below it is in the zone (issue #200). Its node's own y
## without a rectangle shape to take the edge from.
func surface_y() -> float:
	for child in get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			var shape: CollisionShape2D = child
			return shape.global_position.y - shape.shape.size.y * 0.5 * absf(shape.global_scale.y)
	return global_position.y

func _physics_process(delta: float) -> void:
	if not _rising:
		return
	if _grace_left > 0.0:
		var whole_before: int = ceili(_grace_left)
		_grace_left -= delta
		_update_warning()
		if _grace_left > 0.0:
			var whole_after: int = ceili(_grace_left)
			if whole_after < whole_before and whole_after <= COUNTDOWN_FROM:
				rise_countdown.emit(whole_after)
			return
		rise_began.emit()
		_surface.color = SURFACE_COLOR
		# Carry the leftover of the tick grace ended on into the rise, so the
		# deadline does not slip by up to a tick.
		delta = -_grace_left
		_grace_left = 0.0
	# Moving the node, not the shape: the physics server re-tests overlaps
	# on the next step, so `body_entered` fires for a body the zone rises
	# into exactly as it does for one that falls in.
	position.y -= _speed * delta

func _update_warning() -> void:
	if _grace_left > rise_warning_sec:
		_surface.color = SURFACE_COLOR
		return
	var pulse: float = absf(sin(_grace_left * PI * WARNING_PULSES_PER_SEC))
	_surface.color = Color(SURFACE_COLOR, lerpf(SURFACE_COLOR.a, WARNING_ALPHA, pulse))

## A translucent band from the zone's top edge down `surface_depth`, as wide
## as its shape, drawn by this script so no stage scene needs editing.
func _ensure_surface() -> void:
	if _surface != null:
		return
	var size: Vector2 = FALLBACK_SIZE
	var offset: Vector2 = Vector2.ZERO
	for child in get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			size = child.shape.size
			offset = child.position
			break
	var top: float = offset.y - size.y * 0.5
	var left: float = offset.x - size.x * 0.5
	var right: float = offset.x + size.x * 0.5
	_surface = Polygon2D.new()
	_surface.name = "RisingSurface"
	_surface.color = SURFACE_COLOR
	_surface.polygon = PackedVector2Array([
		Vector2(left, top), Vector2(right, top),
		Vector2(right, top + surface_depth), Vector2(left, top + surface_depth)])
	add_child(_surface)
	# A child of the surface, so it rides up with it.
	var edge := Line2D.new()
	edge.name = "SurfaceEdge"
	edge.width = EDGE_WIDTH
	edge.default_color = EDGE_COLOR
	edge.points = PackedVector2Array([Vector2(left, top), Vector2(right, top)])
	_surface.add_child(edge)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("players"):
		body.eliminate()
