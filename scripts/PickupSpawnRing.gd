extends Node2D

## A one-shot gold ring that expands and fades from where a pickup spawned
## (#816), so a drop is easy to spot on a crowded shared screen. Motion only,
## no flash, so Reduce flashes does not apply. Frees itself when done.

## How long the ring lasts, in game seconds.
const LIFETIME_SEC: float = 0.5
## Radius at the start and the end of the expansion.
const START_RADIUS: float = 12.0
const END_RADIUS: float = 80.0
const RING_WIDTH: float = 4.0
const RING_COLOR: Color = Color(1.0, 0.85, 0.3, 1.0)

var _age: float = 0.0

func _init() -> void:
	name = "PickupSpawnRing"
	z_index = -1

func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME_SEC:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var t: float = clampf(_age / LIFETIME_SEC, 0.0, 1.0)
	var eased: float = 1.0 - (1.0 - t) * (1.0 - t)
	var color := RING_COLOR
	color.a = 1.0 - t
	draw_arc(Vector2.ZERO, lerpf(START_RADIUS, END_RADIUS, eased), 0.0, TAU, 48, color, RING_WIDTH, true)
