extends Node2D

## One-shot elimination effect (hackathon playtest): a ring that blows
## outward and shards that fly off and fade, in the eliminated player's
## identity colour. Spawned beside the player, not under it, because the
## player hides the moment it is eliminated. Frees itself when done.

const DURATION: float = 0.7
const RING_START: float = 18.0
const RING_END: float = 110.0
const SHARD_COUNT: int = 14
const SHARD_SPEED_MIN: float = 260.0
const SHARD_SPEED_MAX: float = 520.0
const SHARD_LENGTH: float = 14.0

var colour: Color = Color.WHITE
var _age: float = 0.0
var _shards: Array[Vector2] = []

func _ready() -> void:
	z_index = 90
	# Animated per rendered frame, and placed after it enters the tree (the
	# player sets its position deferred): with physics interpolation on
	# (issue #108) it would be drawn flying in from the origin for a tick.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in SHARD_COUNT:
		var angle: float = TAU * float(i) / float(SHARD_COUNT) + rng.randf_range(-0.2, 0.2)
		_shards.append(Vector2.RIGHT.rotated(angle) * rng.randf_range(SHARD_SPEED_MIN, SHARD_SPEED_MAX))

func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var t: float = clampf(_age / DURATION, 0.0, 1.0)
	var ease_out: float = 1.0 - pow(1.0 - t, 3.0)
	var fade: Color = Color(colour, 1.0 - t)
	# Flash, then ring.
	if t < 0.25:
		draw_circle(Vector2.ZERO, RING_START * (1.0 + t * 4.0), Color(1, 1, 1, 0.8 * (1.0 - t * 4.0)))
	draw_arc(Vector2.ZERO, lerpf(RING_START, RING_END, ease_out), 0.0, TAU, 48, fade, lerpf(10.0, 1.5, t), true)
	for velocity: Vector2 in _shards:
		var tip: Vector2 = velocity * _age * (1.0 - 0.5 * t)
		draw_line(tip, tip - velocity.normalized() * SHARD_LENGTH * (1.0 - t), fade, 4.0, true)
