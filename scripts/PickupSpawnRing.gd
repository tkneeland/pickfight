extends "res://scripts/ExpandingRing.gd"

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

func _init() -> void:
	name = "PickupSpawnRing"
	z_index = -1
	lifetime_sec = LIFETIME_SEC
	start_radius = START_RADIUS
	end_radius = END_RADIUS
	ring_width = RING_WIDTH
	color = RING_COLOR
	segments = 48
