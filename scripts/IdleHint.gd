extends Node2D

## "Drag to swing" for a motionless first-round fighter (issue #826).
##
## In the first round of a match only, a human fighter (no bot, no ghost) whose
## `Player.input_vector` has stayed zero for `IDLE_SEC` after FIGHT gets an ink
## plate in their colour above their name tag, with a small animated arc arrow.
## The plate fades out the moment they provide any input, or when the round
## ends, and never comes back for that fighter in the same match. Gamepad seats
## read "Move the right stick".
##
## Self-contained: NameTags.gd builds this as a child and calls `tick()` from
## its own `tick()` with the round loop's state, so RoundManager, Player and
## ControllerServer are untouched. Timers read the game clock (GameClock.gd).

const IDLE_SEC: float = 6.0
const FADE_IN_SEC: float = 0.15
const FADE_OUT_SEC: float = 0.25
const FONT_SIZE: int = 22
const PAD_X: float = 12.0
const PAD_Y: float = 6.0
const ARROW_W: float = 30.0
const GAP_ABOVE_TAG: float = 8.0
const UiThemeScript := preload("res://scripts/UiTheme.gd")
const GameClockScript := preload("res://scripts/GameClock.gd")

## One plate over one fighter.
class Plate extends Node2D:
	var colour: Color = Color.WHITE
	var text: String = ""
	var font: Font
	var born_msec: int = 0
	var alpha: float = 0.0
	var leaving: bool = false
	var size: Vector2 = Vector2.ZERO

	func _draw() -> void:
		var rect := Rect2(Vector2(-size.x * 0.5, -size.y), size)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.0784, 0.0941, 0.1137, 0.92 * alpha) # UiTheme.INK
		box.border_color = Color(colour.r, colour.g, colour.b, alpha)
		box.set_border_width_all(3)
		box.set_corner_radius_all(10)
		draw_style_box(box, rect)
		var edge := Color(colour.r, colour.g, colour.b, alpha)
		var t: float = float(GameClockScript.now_msec() - born_msec) / 1000.0
		var centre := Vector2(rect.position.x + PAD_X + ARROW_W * 0.5, rect.position.y + size.y * 0.5)
		var sweep: float = 0.6 + 1.4 * (0.5 + 0.5 * sin(t * 4.0))
		var start: float = -PI * 0.5 - 0.8
		draw_arc(centre, 9.0, start, start + sweep, 16, edge, 3.0, true)
		var tip_angle: float = start + sweep
		var tip: Vector2 = centre + Vector2.from_angle(tip_angle) * 9.0
		var dir: Vector2 = Vector2.from_angle(tip_angle + PI * 0.5)
		var side: Vector2 = Vector2.from_angle(tip_angle)
		draw_colored_polygon(PackedVector2Array([tip + dir * 6.0, tip + side * 4.5, tip - side * 4.5]), edge)
		var text_x: float = rect.position.x + PAD_X + ARROW_W + 4.0
		var base_y: float = rect.position.y + size.y * 0.5 + (font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) * 0.5
		draw_string(font, Vector2(text_x, base_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, Color(1, 1, 1, alpha))

var _players: Array = []
var _slot_color: Callable
var _probe: Label
## slot -> idle seconds accumulated this round.
var _idle: Dictionary = {}
## slot -> Plate currently up.
var _plates: Dictionary = {}
## Fighters shown a hint (or who have moved) this match: never hinted again.
var _done: Dictionary = {}
var _rounds_seen: int = 0
var _last_round_id: int = -1
var _last_msec: int = -1

func _init(players: Array = [], slot_color: Callable = Callable()) -> void:
	name = "IdleHint"
	z_index = 20 # above the name tags
	_players = players
	_slot_color = slot_color

func _ready() -> void:
	_probe = Label.new()
	_probe.theme_type_variation = UiThemeScript.HUD_HEADING_LABEL
	_probe.visible = false
	add_child(_probe)

## True while a plate is up (not yet fading out) over `slot`.
func has_hint(slot: int) -> bool:
	var plate: Variant = _plates.get(slot)
	return plate != null and is_instance_valid(plate) and not (plate as Plate).leaving

## The plate's text over `slot`, or "".
func hint_text(slot: int) -> String:
	var plate: Variant = _plates.get(slot)
	return (plate as Plate).text if plate != null and is_instance_valid(plate) else ""

## One frame. `ctx`: `active` (a round is in play), `round_id` (changes every
## round), `reset` (back in the lobby: a new match is next), `is_bot` and
## `is_pad` (Callable slot -> bool), `anchor` (Callable slot -> Vector2, the
## top-centre of that slot's name tag in world space) and `scale`.
func tick(ctx: Dictionary) -> void:
	var now: int = GameClockScript.now_msec()
	var dt: float = float(now - _last_msec) / 1000.0 if _last_msec >= 0 else 0.0
	_last_msec = now
	if bool(ctx.get("reset", false)):
		_idle.clear()
		_done.clear()
		_rounds_seen = 0
		_last_round_id = -1
	var active: bool = bool(ctx.get("active", false))
	if active and int(ctx.get("round_id", 0)) != _last_round_id:
		_last_round_id = int(ctx.get("round_id", 0))
		_rounds_seen += 1
		_idle.clear()
	var watching: bool = active and _rounds_seen == 1
	var is_bot: Callable = ctx.get("is_bot", Callable())
	var is_pad: Callable = ctx.get("is_pad", Callable())
	var anchor: Callable = ctx.get("anchor", Callable())
	var scale_by: float = float(ctx.get("scale", 1.0))
	for slot in _players.size():
		var player: Variant = _players[slot]
		var eligible: bool = watching and player != null and is_instance_valid(player) and player.alive and player.visible \
			and (not _done.has(slot) or _plates.has(slot)) and not (is_bot.is_valid() and bool(is_bot.call(slot)))
		if not eligible:
			_idle.erase(slot)
			_dismiss(slot)
			continue
		if not (player.input_vector as Vector2).is_zero_approx():
			_idle.erase(slot)
			_done[slot] = true # moved: never hinted this match
			_dismiss(slot)
			continue
		if _plates.has(slot):
			continue # already shown: stays up until input or the round's end
		_idle[slot] = float(_idle.get(slot, 0.0)) + dt
		if float(_idle[slot]) >= IDLE_SEC:
			_done[slot] = true # at most one hint per fighter
			_spawn(slot, is_pad.is_valid() and bool(is_pad.call(slot)))
	for slot: int in _plates.keys():
		var plate: Plate = _plates[slot]
		plate.alpha = clampf(plate.alpha + (-dt / FADE_OUT_SEC if plate.leaving else dt / FADE_IN_SEC), 0.0, 1.0)
		if plate.leaving and plate.alpha <= 0.0:
			_plates.erase(slot)
			plate.queue_free()
			continue
		plate.scale = Vector2(scale_by, scale_by)
		if anchor.is_valid():
			plate.position = (anchor.call(slot) as Vector2) + Vector2(0.0, -GAP_ABOVE_TAG * scale_by)
		plate.queue_redraw()

func _dismiss(slot: int) -> void:
	var plate: Variant = _plates.get(slot)
	if plate != null and is_instance_valid(plate):
		(plate as Plate).leaving = true

func _spawn(slot: int, pad: bool) -> void:
	var plate := Plate.new()
	plate.name = "Plate%d" % slot
	plate.text = tr("HINT_RIGHT_STICK" if pad else "HINT_DRAG_TO_SWING")
	plate.font = _probe.get_theme_font("font")
	plate.colour = _slot_color.call(slot) if _slot_color.is_valid() else Color.WHITE
	plate.born_msec = GameClockScript.now_msec()
	var text_w: float = plate.font.get_string_size(plate.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE).x
	plate.size = Vector2(text_w + PAD_X * 2.0 + ARROW_W + 4.0, FONT_SIZE + PAD_Y * 2.0 + 4.0)
	add_child(plate)
	_plates[slot] = plate
