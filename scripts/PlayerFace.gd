extends Node2D
## The player square's face (issue #254): a crisp dark outline, two dot eyes
## that look toward the weapon head, blinks, a squint on a hit, X eyes once
## eliminated, and a squash and stretch on landings and big hits.
##
## Drawing only. Nothing here touches the player's physics body, collision
## shapes or gameplay; the squash is a visual scale on the visual nodes. Its
## randomness comes from its own RandomNumberGenerator, seeded per player, so
## it never advances the global (gameplay) generator.

const HALF: float = 24.0
const OUTLINE_WIDTH: float = 2.0
const OUTLINE_COLOR := Color(0.07, 0.07, 0.09)

## Outline and pupil ink; the stage mood's ink once a stage loads (#255).
var ink: Color = OUTLINE_COLOR

func set_ink(colour: Color) -> void:
	ink = colour
	queue_redraw()
const EYE_X: float = 9.0
const EYE_Y: float = -5.0
const EYE_RADIUS: float = 6.0
const PUPIL_RADIUS: float = 3.0
const LOOK_REACH: float = 2.5
const BLINK_MIN: float = 2.0
const BLINK_MAX: float = 5.0
const BLINK_LENGTH: float = 0.12
const SQUINT_LENGTH: float = 0.2
const MAX_SQUASH: float = 0.15
const SQUASH_RECOVERY: float = 0.15
## A landing squashes when the fall speed (px/s) at the previous tick was at
## least this and the body has since lost most of it.
const LANDING_SPEED: float = 350.0
const LANDING_FULL_SPEED: float = 900.0
## A hit of at least this much damage squashes as well as squints.
const BIG_HIT: float = 25.0

## Selectable eye styles (issue #297). "round" is the original and the default.
const EYE_ROUND := "round"
const EYE_IDS: Array[String] = ["round", "sleepy", "angry", "wide", "dot", "visor"]
const EYE_LABELS := {
	"round": "Round", "sleepy": "Sleepy", "angry": "Angry",
	"wide": "Wide", "dot": "Dot", "visor": "Visor",
}

var eyes_style: String = EYE_ROUND

func set_eyes(id: String) -> void:
	eyes_style = id if EYE_IDS.has(id) else EYE_ROUND
	queue_redraw()

## Where each pupil is drawn, in this node's frame (left eye first): the eye's
## centre pushed toward `look` by the style's reach. The draw uses this too.
func pupil_centers(look: Vector2) -> Array[Vector2]:
	var reach: float = LOOK_REACH
	match eyes_style:
		"wide":
			reach = 3.0
		"dot":
			reach = 2.0
		"visor":
			reach = 3.0
	return [Vector2(-EYE_X, EYE_Y) + look * reach, Vector2(EYE_X, EYE_Y) + look * reach]

var _player: RigidBody2D
var _squash_nodes: Array[Node2D] = []
var _hat: Node2D
var _rng := RandomNumberGenerator.new()
var _blink_in: float = 3.0
var _blink_left: float = 0.0
var _squint_left: float = 0.0
var _squash: float = 0.0
var _squash_left: float = 0.0
var _squash_dir: float = 1.0
var _prev_vy: float = 0.0

## `visuals` are the player's drawn nodes that squash with the face; `hat` is
## moved so it stays on the squashed head.
func setup(player: RigidBody2D, visuals: Array[Node2D], hat: Node2D) -> void:
	_player = player
	_squash_nodes = visuals
	_hat = hat
	# Seeded from the player's slot name, never from the global generator.
	_rng.seed = hash("eyes:%s" % player.name) ^ player.get_instance_id()
	_blink_in = _rng.randf_range(BLINK_MIN, BLINK_MAX)

func _physics_process(delta: float) -> void:
	if _player == null:
		return
	var vy: float = _player.linear_velocity.y
	if _player.alive:
		if _prev_vy >= LANDING_SPEED and vy < _prev_vy * 0.5:
			var strength: float = clampf(_prev_vy / LANDING_FULL_SPEED, 0.3, 1.0)
			start_squash(MAX_SQUASH * strength, 1.0)
	_prev_vy = vy
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_left = BLINK_LENGTH
		_blink_in = _rng.randf_range(BLINK_MIN, BLINK_MAX)
	_blink_left = maxf(0.0, _blink_left - delta)
	_squint_left = maxf(0.0, _squint_left - delta)
	if _squash_left > 0.0:
		_squash_left = maxf(0.0, _squash_left - delta)
	_apply_squash()
	queue_redraw()

## A hit: squint for SQUINT_LENGTH, and squash too when it is a big one.
func on_hit(amount: float) -> void:
	_squint_left = SQUINT_LENGTH
	if amount >= BIG_HIT:
		start_squash(MAX_SQUASH, -1.0)

## `amount` is clamped to MAX_SQUASH. `dir` 1 squashes (wide and short, a
## landing), -1 stretches (tall and thin, a hit).
func start_squash(amount: float, dir: float) -> void:
	_squash = minf(absf(amount), MAX_SQUASH)
	_squash_dir = dir
	_squash_left = SQUASH_RECOVERY

## The current visual scale factor, for the scenario: Vector2.ONE at rest.
func squash_scale() -> Vector2:
	var t: float = _squash_left / SQUASH_RECOVERY
	var a: float = _squash * t * t
	return Vector2(1.0 + a * _squash_dir, 1.0 - a * _squash_dir)

func _apply_squash() -> void:
	var s: Vector2 = squash_scale()
	# Scaled about the feet, so a landing stays planted on the floor.
	var pos := Vector2(0.0, HALF * (1.0 - s.y))
	for n: Node2D in _squash_nodes:
		n.scale = s
		n.position = pos
	scale = s
	position = pos
	if _hat != null:
		_hat.position.y = HALF - 2.0 * HALF * s.y

## "dead", "squint", "blink" or "open".
func eye_state() -> String:
	if _player != null and not _player.alive:
		return "dead"
	if _squint_left > 0.0:
		return "squint"
	if _blink_left > 0.0:
		return "blink"
	return "open"

## Unit vector from the player toward the weapon head (the weapon's aim when
## the head is not built).
func look_dir() -> Vector2:
	return _player.eye_look_dir() if _player != null else Vector2.RIGHT

func _draw() -> void:
	var inset: float = HALF - OUTLINE_WIDTH * 0.5
	draw_rect(Rect2(-inset, -inset, inset * 2.0, inset * 2.0), ink, false, OUTLINE_WIDTH)
	var state: String = eye_state()
	var look: Vector2 = look_dir()
	var pupils: Array[Vector2] = pupil_centers(look)
	var open_eyes: bool = state != "dead" and state != "squint" and state != "blink"
	var mark: Color = Color.WHITE if eyes_style == "visor" else ink
	if eyes_style == "visor":
		draw_rect(Rect2(-EYE_X - 9.0, EYE_Y - 5.5, EYE_X * 2.0 + 18.0, 11.0), ink)
	var idx: int = 0
	for sx: float in [-EYE_X, EYE_X]:
		var c := Vector2(sx, EYE_Y)
		var pc: Vector2 = pupils[idx]
		idx += 1
		if not open_eyes:
			if state == "dead":
				var r: float = EYE_RADIUS * 0.8
				draw_line(c + Vector2(-r, -r), c + Vector2(r, r), mark, 2.5)
				draw_line(c + Vector2(-r, r), c + Vector2(r, -r), mark, 2.5)
			else:
				draw_line(c + Vector2(-EYE_RADIUS, 0.0), c + Vector2(EYE_RADIUS, 0.0), mark, 2.5)
			continue
		match eyes_style:
			"dot":
				draw_circle(pc, 4.0, ink)
			"visor":
				draw_circle(pc, 2.5, Color.WHITE)
			"wide":
				draw_circle(c, 8.0, Color.WHITE)
				draw_arc(c, 8.0, 0.0, TAU, 20, ink, 1.5)
				draw_circle(pc, 2.5, ink)
			_:
				draw_circle(c, EYE_RADIUS, Color.WHITE)
				draw_circle(pc, PUPIL_RADIUS, ink)
				if eyes_style == "sleepy":
					var lid := PackedVector2Array()
					for k in 9:
						var a: float = PI + PI * float(k) / 8.0
						lid.append(c + Vector2(cos(a), sin(a)) * (EYE_RADIUS + 0.5))
					draw_colored_polygon(lid, ink)
				elif eyes_style == "angry":
					var dir: float = 1.0 if sx < 0.0 else -1.0
					draw_line(c + Vector2(-dir * 8.0, -9.0), c + Vector2(dir * 7.0, -4.0), ink, 3.0)
