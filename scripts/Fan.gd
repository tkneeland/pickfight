extends Node2D

## Fan stage part (issue #281): a visible fan whose air column pushes along
## the way it faces, and which can travel along a path and/or turn so the
## column sweeps.
##
## The push is the wind zone's (issue #52): the fan owns a steady `WindZone`
## child, placed in front of the housing and turned with it, so strength,
## mass-independence, body-only pushing (ADR-0006), streaks and tint are all
## the existing code. This script only moves and turns the zone.
##
## Motion, all timed in physics ticks and all optional:
##   `spin_deg_per_sec` -- the column turns continuously.
##   `sweep_deg` -- the column swings +-`sweep_deg` about the facing, one
##                  full back-and-forth per `sweep_sec`.
##   `travel` -- the fan slides to `travel` px from where it was placed and
##               back, one round trip per `travel_sec`.
## `facing` is the column's direction at rest, in the node's local space.

const WindZoneScene: PackedScene = preload("res://scenes/parts/WindZone.tscn")
const PartKitScript: GDScript = preload("res://scripts/PartKit.gd")
## A fighter may be whooshed at again only after this long (issue #1084).
const WHOOSH_INTERVAL_SEC: float = 1.0

@export var facing: Vector2 = Vector2.RIGHT
## Length and width of the air column.
@export var column_length: float = 300.0
@export var column_width: float = 120.0
@export var strength: float = 1800.0
@export var spin_deg_per_sec: float = 0.0
@export var sweep_deg: float = 0.0
@export var sweep_sec: float = 4.0
@export var travel: Vector2 = Vector2.ZERO
@export var travel_sec: float = 6.0

## The housing's colour; `Stage` swaps in the mood's platform colour.
## Issue #976: what the Online client copies from the host to draw this part
## as the host does (NetSync.gd).
const NET_VARS: Array[String] = ["position", "rotation", "_elapsed"]
var _body_color: Color = Color(0.35, 0.35, 0.4, 1)
var _origin: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0
var _spin: float = 0.0
var _zone: Area2D = null
## Instance ids of the fighters in the column last tick, and seconds until
## each may be whooshed at again.
var _inside_last: Dictionary = {}
var _whoosh_wait: Dictionary = {}

func _ready() -> void:
	_origin = position
	_zone = WindZoneScene.instantiate() as Area2D
	_zone.name = "AirColumn"
	_zone.size = Vector2(column_length, column_width)
	_zone.strength = strength
	_zone.steady = true
	_zone.direction = Vector2.RIGHT
	# Local +x is the column's axis; the fan's own rotation aims it.
	_zone.position = Vector2(column_length / 2.0 + 18.0, 0)
	add_child(_zone)
	rotation = _heading()

func _heading() -> float:
	var sweep: float = 0.0
	if sweep_deg != 0.0 and sweep_sec > 0.0:
		sweep = deg_to_rad(sweep_deg) * sin(TAU * _elapsed / sweep_sec)
	return facing.angle() + _spin + sweep

## The air column's direction in world space, unit length. An observable seam.
func push_direction() -> Vector2:
	return _zone.world_direction() if _zone != null else Vector2.ZERO

## The wind zone the fan owns.
func air_column() -> Area2D:
	return _zone

func set_platform_color(color: Color) -> void:
	_body_color = color
	queue_redraw()

func _physics_process(delta: float) -> void:
	_elapsed += delta
	_spin += deg_to_rad(spin_deg_per_sec) * delta
	rotation = _heading()
	if travel != Vector2.ZERO and travel_sec > 0.0:
		var f: float = 0.5 - 0.5 * cos(TAU * _elapsed / travel_sec)
		position = _origin + travel * f
	_whoosh_on_entry(delta)
	queue_redraw()

## Plays `fan_whoosh` when a living, unprotected fighter first enters the
## column, at most once per fighter per second (issue #1084; the conveyor's
## `belt_step` rule, #1060). It goes through `PartKit.sfx`, so Online joiners
## hear it from the snapshot sound trailer like every other part cue.
func _whoosh_on_entry(delta: float) -> void:
	for id: int in _whoosh_wait.keys():
		var left: float = float(_whoosh_wait[id]) - delta
		if left <= 0.0:
			_whoosh_wait.erase(id)
		else:
			_whoosh_wait[id] = left
	var now: Dictionary = {}
	for body: Node2D in _zone.get_overlapping_bodies():
		if body is RigidBody2D and body.is_in_group("players") and bool(body.get("alive")) and not bool(body.get("spawn_protected")):
			var id: int = body.get_instance_id()
			now[id] = true
			if not _inside_last.has(id) and not _whoosh_wait.has(id):
				_whoosh_wait[id] = WHOOSH_INTERVAL_SEC
				PartKitScript.sfx(self, &"fan_whoosh", body.global_position)
	_inside_last = now

func _draw() -> void:
	# Housing, then blades that turn with time so it reads as running.
	draw_rect(Rect2(-14, -20, 22, 40), _body_color)
	var blade: Color = _body_color.lightened(0.35)
	var s: float = absf(sin(_elapsed * 14.0))
	draw_line(Vector2(10, -18.0 * s), Vector2(10, 18.0 * s), blade, 5.0)
	draw_line(Vector2(-14, -22), Vector2(8, -22), blade, 3.0)
	draw_line(Vector2(-14, 22), Vector2(8, 22), blade, 3.0)
