extends Node2D

## Stage-wide gust part (issue #281): a periodic gust across the whole stage,
## all one way, announced `warning_sec` ahead.
##
## Built on the wind zone (issue #52) rather than beside it: this node owns
## one very large `WindZone` on the world layer, so every player body inside
## it is pushed by the same code, by the same acceleration, the same way. The
## zone's tell is the warning: tint brightening, streaks speeding up across
## the whole stage, and the existing `wind_tell` sound when it starts, then
## `wind_gust` as the gust lands. Between gusts the zone is calm and pushes
## nothing.

const WindZoneScene: PackedScene = preload("res://scenes/parts/WindZone.tscn")
const WindZoneScript := preload("res://scripts/WindZone.gd")

@export var size: Vector2 = Vector2(2000, 1200)
@export var direction: Vector2 = Vector2.RIGHT
@export var strength: float = 1500.0
@export var calm_sec: float = 8.0
## How far ahead of the push the warning starts.
@export var warning_sec: float = 1.5
@export var gust_sec: float = 2.0
@export var cycle_offset_sec: float = 0.0

var _zone: Area2D = null

func _ready() -> void:
	_zone = WindZoneScene.instantiate() as Area2D
	_zone.name = "GustZone"
	_zone.size = size
	_zone.direction = direction
	_zone.strength = strength
	_zone.steady = false
	_zone.calm_sec = calm_sec
	_zone.tell_sec = warning_sec
	_zone.gust_sec = gust_sec
	_zone.cycle_offset_sec = cycle_offset_sec
	add_child(_zone)

## Whether the warning is showing (the push has not started).
func is_warning() -> bool:
	return _zone != null and _zone.phase() == WindZoneScript.Phase.TELL

## Whether the gust is pushing right now.
func is_gusting() -> bool:
	return _zone != null and _zone.is_pushing()

func push_direction() -> Vector2:
	return _zone.world_direction() if _zone != null else Vector2.ZERO

func gust_zone() -> Area2D:
	return _zone
