extends Node2D

## A one-shot ring, or a staggered set of rings, that expands and fades from
## where it is placed, then frees itself. Motion only, no flash, so Reduce
## flashes does not apply. `PickupSpawnRing.gd` (#816) and `RoundWinRing.gd`
## (#909) extend it by path and set the look in `_init`.

## How long the effect lasts, in game seconds.
var lifetime_sec: float = 0.5
## Radius at the start and the end of each ring's expansion.
var start_radius: float = 12.0
var end_radius: float = 80.0
var ring_width: float = 4.0
var color: Color = Color.WHITE
## How many rings, each trailing the one before by `ring_delay` (a share of
## the lifetime).
var ring_count: int = 1
var ring_delay: float = 0.0
var segments: int = 48

var _age: float = 0.0

func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime_sec:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var span: float = lifetime_sec * (1.0 - ring_delay * float(ring_count - 1))
	for i in ring_count:
		var t: float = clampf((_age - float(i) * ring_delay * lifetime_sec) / span, 0.0, 1.0)
		# A trailing ring has not started yet; a finished one is gone.
		if (i > 0 and t <= 0.0) or t >= 1.0:
			continue
		var eased: float = 1.0 - (1.0 - t) * (1.0 - t)
		var c := color
		c.a = 1.0 - t
		draw_arc(Vector2.ZERO, lerpf(start_radius, end_radius, eased), 0.0, TAU, segments, c, ring_width, true)
