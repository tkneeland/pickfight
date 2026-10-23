extends CanvasLayer

## Edge arrows for fighters outside the camera view (#779). A big hit or a bounce pad can send a
## fighter above the top of the shared screen; this pins a small arrow in the fighter's colour to
## the screen edge, pointing at them, with the team letter beside it in Teams (the #752 badge).
##
## RoundManager builds this lazily beside its name tags and hands it the same player list, so the
## lobby how-to-play demos (their own SubViewports, their own players) never get one. Living,
## visible (not ghost, not KO'd) fighters only. Where a fighter is on screen comes from the
## viewport's canvas transform, so the per-stage large-stage camera zoom needs no special case.
## Each arrow fades in and out over `FADE_SEC`.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const TeamsScript := preload("res://scripts/Teams.gd")
const TeamBadgeScript := preload("res://scripts/TeamBadge.gd")
const HostSettingsScript := preload("res://scripts/HostSettings.gd")

const FADE_SEC: float = 0.15
## Gap between the screen edge and the arrow's tip.
const EDGE_MARGIN: float = 48.0
const ARROW_LENGTH: float = 30.0
const ARROW_HALF_WIDTH: float = 17.0
const BADGE_PX: float = 26.0
## Opacity at which a slot's arrow counts as shown.
const SHOWN_ALPHA: float = 0.01

var _players: Array = []
var _slot_color: Callable
var _canvas: Control
var _badges: Array[Control] = []
## Player numbers (#875): the seat number beside the arrow, after the team letter in Teams.
var _numbers: Array[Control] = []
var _alpha: Array[float] = []
## Per slot: [tip position, unit direction toward the fighter] while an arrow is wanted.
var _aim: Array = []
var _wanted: Array[bool] = []

func _init(players: Array = [], slot_color: Callable = Callable()) -> void:
	name = "OffscreenIndicators"
	layer = 6
	_players = players
	_slot_color = slot_color

func build() -> void:
	_canvas = Control.new()
	_canvas.name = "Arrows"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_arrows)
	add_child(_canvas)
	for slot in _players.size():
		var badge: Control = TeamBadgeScript.new(TeamsScript.NONE, BADGE_PX)
		badge.name = "TeamBadge%d" % slot
		_canvas.add_child(badge)
		_badges.append(badge)
		var num: Control = TeamBadgeScript.new(TeamsScript.NONE, BADGE_PX)
		num.name = "NumberBadge%d" % slot
		_canvas.add_child(num)
		_numbers.append(num)
		_alpha.append(0.0)
		_aim.append([Vector2.ZERO, Vector2.UP])
		_wanted.append(false)

## Whether a slot's arrow is showing (fading in counts, fully faded out does not).
func arrow_visible(slot: int) -> bool:
	return slot >= 0 and slot < _alpha.size() and _alpha[slot] > SHOWN_ALPHA

func arrow_alpha(slot: int) -> float:
	return _alpha[slot] if slot >= 0 and slot < _alpha.size() else 0.0

## Where a slot's arrow tip sits on screen, in viewport pixels.
func arrow_tip(slot: int) -> Vector2:
	return _aim[slot][0] if slot >= 0 and slot < _aim.size() else Vector2.ZERO

## The team letter beside a slot's arrow, "" in a free-for-all or with no arrow.
func arrow_letter(slot: int) -> String:
	if not arrow_visible(slot):
		return ""
	return _badges[slot].letter() if _badges[slot].visible else ""

## The seat number beside a slot's arrow (#875), 0 with the option off or no arrow.
func arrow_number(slot: int) -> int:
	if not arrow_visible(slot):
		return 0
	return _numbers[slot].number() if _numbers[slot].visible else 0

func _process(delta: float) -> void:
	if _canvas == null:
		return
	update_targets()
	var step: float = delta / FADE_SEC
	var redraw: bool = false
	for slot in _alpha.size():
		var was: float = _alpha[slot]
		_alpha[slot] = move_toward(_alpha[slot], 1.0 if _wanted[slot] else 0.0, step)
		_badges[slot].modulate.a = _alpha[slot]
		_numbers[slot].modulate.a = _alpha[slot]
		if _alpha[slot] > 0.0 or _alpha[slot] != was:
			redraw = true
	# With every arrow faded out (and none fading this frame) there is nothing to draw.
	if redraw:
		_canvas.queue_redraw()

## Works out who is off screen right now and where their arrow goes. Public so a scenario can
## read the result without waiting out a frame.
func update_targets() -> void:
	var viewport := get_viewport()
	var size: Vector2 = viewport.get_visible_rect().size
	var to_screen: Transform2D = viewport.get_canvas_transform()
	var screen := Rect2(Vector2.ZERO, size)
	var inner := Rect2(Vector2.ONE * EDGE_MARGIN, size - Vector2.ONE * EDGE_MARGIN * 2.0)
	var numbers_on: bool = HostSettingsScript.shared().player_numbers
	var arrows_on: bool = _settings_allow_arrows()
	for slot in _players.size():
		var player: Variant = _players[slot]
		_wanted[slot] = false
		var team: int = TeamsScript.NONE
		if arrows_on and player != null and is_instance_valid(player) and player.alive and player.visible:
			var at: Vector2 = to_screen * player.global_position
			if not screen.has_point(at):
				_wanted[slot] = true
				var centre: Vector2 = size * 0.5
				var dir: Vector2 = (at - centre).normalized()
				var tip: Vector2 = _clamp_to(inner, centre, at)
				_aim[slot] = [tip, dir]
				team = int(player.get("team")) if player.get("team") is int else TeamsScript.NONE
				_badges[slot].position = tip - dir * (ARROW_LENGTH + BADGE_PX * 0.5 + 6.0) - Vector2.ONE * BADGE_PX * 0.5
		_badges[slot].set_team(team if _wanted[slot] else TeamsScript.NONE)
		var num: Control = _numbers[slot]
		if _wanted[slot] and numbers_on:
			var dir2: Vector2 = _aim[slot][1]
			var step: float = ARROW_LENGTH + BADGE_PX * 0.5 + 6.0
			if team != TeamsScript.NONE:
				step += BADGE_PX + 4.0
			num.position = _aim[slot][0] - dir2 * step - Vector2.ONE * BADGE_PX * 0.5
			num.set_number(slot + 1, _slot_color.call(slot))
		else:
			num.set_number(0)

## Settings > "Edge arrows" (#940); on when there is no Sfx autoload.
func _settings_allow_arrows() -> bool:
	var sfx: Node = get_node_or_null("/root/Sfx")
	return sfx == null or bool(sfx.get("edge_arrows"))

## The point where the ray from `centre` toward `at` leaves `box`.
static func _clamp_to(box: Rect2, centre: Vector2, at: Vector2) -> Vector2:
	var d: Vector2 = at - centre
	var half: Vector2 = box.size * 0.5
	var sx: float = half.x / absf(d.x) if absf(d.x) > 0.001 else INF
	var sy: float = half.y / absf(d.y) if absf(d.y) > 0.001 else INF
	return centre + d * minf(sx, sy)

func _draw_arrows() -> void:
	for slot in _alpha.size():
		if _alpha[slot] <= SHOWN_ALPHA:
			continue
		var tip: Vector2 = _aim[slot][0]
		var dir: Vector2 = _aim[slot][1]
		var side: Vector2 = dir.orthogonal()
		var base: Vector2 = tip - dir * ARROW_LENGTH
		var colour: Color = _slot_color.call(slot)
		colour.a = _alpha[slot]
		var ink := Color(0.0, 0.0, 0.0, _alpha[slot])
		var pts := PackedVector2Array([tip, base + side * ARROW_HALF_WIDTH, base - side * ARROW_HALF_WIDTH])
		_canvas.draw_colored_polygon(pts, colour)
		_canvas.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), ink, 3.0)
