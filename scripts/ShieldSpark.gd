extends Node2D

## Issue #969: the small spark burst thrown where a shield face stops a shot,
## in the holder's identity colour. Frees itself when done. Skipped by the
## caller with "Reduce flashes" on (#317); see `ShotSweep.shield_blocked()`.

const DURATION: float = 0.25
const SPARK_COUNT: int = 7
const SPEED_MIN: float = 120.0
const SPEED_MAX: float = 260.0
const LENGTH: float = 8.0
## Observable for scenarios: every live burst is in this group.
const GROUP := &"shield_sparks"

var colour: Color = Color.WHITE
var _age: float = 0.0
var _sparks: Array[Vector2] = []

func _ready() -> void:
	add_to_group(GROUP)
	z_index = 90
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in SPARK_COUNT:
		var angle: float = TAU * float(i) / float(SPARK_COUNT) + rng.randf_range(-0.3, 0.3)
		_sparks.append(Vector2.RIGHT.rotated(angle) * rng.randf_range(SPEED_MIN, SPEED_MAX))

func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var t: float = clampf(_age / DURATION, 0.0, 1.0)
	var fade: Color = Color(colour, 1.0 - t)
	for velocity: Vector2 in _sparks:
		var tip: Vector2 = velocity * _age
		draw_line(tip, tip - velocity.normalized() * LENGTH * (1.0 - t), fade, 3.0, true)
