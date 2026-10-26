extends "res://scripts/ExpandingRing.gd"

## A one-shot ring in the bounce pad's spring green that expands and fades from
## the pad's top face where a fighter was launched (#1089), so the "this throws
## you" moment reads from across the room. Drawn by ExpandingRing.gd, as
## RoundWinRing.gd is. Silent. The caller skips it with Reduce flashes on (the
## pad's own flash does too). Frees itself when done.

const LIFETIME_SEC: float = 0.4
const START_RADIUS: float = 10.0
const END_RADIUS: float = 50.0
const RING_WIDTH: float = 4.0
## The pad's spring green (BouncePad.PAD_COLOR), repeated here so the Online
## joiner's copy needs no pad in the tree.
const RING_COLOR: Color = Color(0.25, 0.85, 0.35, 1)

func _init() -> void:
	name = "BouncePadRing"
	lifetime_sec = LIFETIME_SEC
	start_radius = START_RADIUS
	end_radius = END_RADIUS
	ring_width = RING_WIDTH
	color = RING_COLOR

## The ring at `at` under `parent`. Shared by the host and the Online joiner
## (#976).
static func spawn_at(parent: Node, at: Vector2) -> Node2D:
	var ring: Node2D = (load("res://scripts/BouncePadRing.gd") as GDScript).new()
	parent.add_child(ring)
	ring.global_position = at
	return ring
