extends Node2D

## What a strike looks like on the shared screen (issue #33): a hitmarker at
## the point of impact, and -- as a tuning aid -- the damage it dealt.
##
## Listens to every player's `strike_landed` rather than being told by
## `Player`, so drawing stays out of the fighter. Players come and go (the
## roster, scenarios), so it watches the tree for new ones instead of wiring
## a fixed list. Lives in world space: markers sit where the hit happened.
##
## - A strike that dealt damage gets a hitmarker in the attacker's
##   `identity_color`, sized by damage; a lethal one a bigger red one.
## - With damage numbers on, every reported strike also gets its damage as a
##   floating number -- including `0` for a contact that was a real swing but
##   too slow to count, which gets no hitmarker. Those `0`s are rate-limited
##   per attacker/victim pair so a head dragged along someone doesn't spray.
##
## **No per-strike allocation (issue #168).** Markers and numbers are pooled:
## a finished one is taken out of the tree and parked, and the next strike
## re-uses it, so a hit only allocates when more are on screen at once than
## ever before. Damage numbers share one `LabelSettings` per font size. A
## re-used node is added back as the last child, as a new one would be, so
## `child_entered_tree` still announces every marker and number.

## Lobby how-to-play demo nodes (#219) are left alone: `is_demo_node()`.
const HowToPlayDemoScript := preload("res://scripts/HowToPlayDemo.gd")
const UiThemeScript := preload("res://scripts/UiTheme.gd")

## The debug switch. Damage numbers are a testing aid, not part of the game;
## flip this to hide them. Hitmarkers are always on.
const SHOW_DAMAGE_NUMBERS: bool = true

const MARKER_LIFETIME: float = 0.25
const NUMBER_LIFETIME: float = 0.8
## How far a number drifts up over its lifetime, in pixels.
const NUMBER_RISE: float = 40.0
## Hitmarker arm length at the smallest and largest damage, and the lethal
## multiplier on top.
const MARKER_MIN_ARM: float = 7.0
const MARKER_MAX_ARM: float = 18.0
const LETHAL_MARKER_SCALE: float = 1.6
const LETHAL_COLOR: Color = Color(0.95, 0.1, 0.08, 1.0)
const NUMBER_MIN_FONT: int = 16
const NUMBER_MAX_FONT: int = 36
const ZERO_NUMBER_COLOR: Color = Color(0.7, 0.7, 0.7, 1.0)
## Damage that draws the biggest marker and number. Player.MAX_STRIKE_DAMAGE,
## repeated rather than read so this script needn't preload the player.
const FULL_SCALE_DAMAGE: float = 90.0
## A `0` is shown at most once per attacker/victim pair in this many physics
## frames (0.2 s at 60 Hz). Counted in frames so scenarios are deterministic.
const ZERO_COOLDOWN_FRAMES: int = 12

## Starts from the constant; a variable so a scenario can prove the switch
## without editing the file.
var show_damage_numbers: bool = SHOW_DAMAGE_NUMBERS

## "attacker_id:victim_id" -> the physics frame its last `0` was shown on.
var _last_zero_frame: Dictionary = {}

## Finished markers and numbers, out of the tree, waiting to be re-used.
var _free_markers: Array[HitMarker] = []
var _free_numbers: Array[DamageNumber] = []
## font size -> the LabelSettings every damage number at that size shares;
## `ZERO_SETTINGS_KEY` for the grey `0`.
var _label_settings: Dictionary = {}
const ZERO_SETTINGS_KEY: int = -1

func _ready() -> void:
	z_index = 100
	# Markers and numbers animate per rendered frame in `_process`, not per
	# physics tick, so physics interpolation (issue #108) has nothing to blend
	# for them and would only draw them a tick late. Off here, off for every
	# marker and number under it.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_warm_number_sizes()
	get_tree().node_added.connect(_on_node_added)
	for player in get_tree().get_nodes_in_group("players"):
		_watch(player)

## Lays out the digits at every size a damage number can be, once, up front
## (issue #108). The first number at a size the font has not been used at
## costs the font that size's glyphs: measured at 3.2 ms against 0.1 ms once
## warm, inside the physics tick the strike landed in -- a hitch on the very
## hits the game is about, a different one for every new damage band. All
## twenty-one sizes together are about 70 ms, paid here at scene load. The
## font is Godot's fallback, which is what a Label with no theme uses.
func _warm_number_sizes() -> void:
	if not show_damage_numbers:
		return
	var font: Font = _number_font_face()
	if font == null:
		return
	for size in range(NUMBER_MIN_FONT, NUMBER_MAX_FONT + 1):
		font.get_string_size("0123456789", HORIZONTAL_ALIGNMENT_LEFT, -1, size)

func _on_node_added(node: Node) -> void:
	_watch(node)

func _watch(node: Node) -> void:
	if not node.has_signal("strike_landed") or HowToPlayDemoScript.is_demo_node(node):
		return
	var handler: Callable = _on_strike_landed.bind(node)
	if not node.is_connected("strike_landed", handler):
		node.connect("strike_landed", handler)

## `attacker` comes last because that is where the signal's bind puts it.
func _on_strike_landed(victim: Node, amount: float, point: Vector2, lethal: bool, attacker: Node) -> void:
	var world_scale: float = _world_scale()
	if amount > 0.0:
		var colour: Color = LETHAL_COLOR if lethal else _identity_colour(attacker)
		var marker: HitMarker = _free_markers.pop_back() if not _free_markers.is_empty() else HitMarker.new()
		marker.done = _retire
		marker.setup(point, colour, _marker_arm(amount, lethal), lethal, amount, world_scale)
		add_child(marker)
	elif not _zero_allowed(attacker, victim):
		return
	if show_damage_numbers:
		var font_size: int = _number_font(amount)
		var number: DamageNumber = _free_numbers.pop_back() if not _free_numbers.is_empty() else DamageNumber.new()
		number.done = _retire
		number.setup(point, amount, font_size, world_scale, _settings_for(amount, font_size))
		add_child(number)

## A marker or number has finished: out of the tree and back in the pool.
## Called deferred, never from inside the node's own `_process`.
func _retire(node: Variant) -> void:
	if not is_instance_valid(node) or (node as Node).get_parent() != self:
		return
	remove_child(node)
	if node is HitMarker:
		_free_markers.append(node)
	else:
		_free_numbers.append(node)

## The damage numbers' font (#548): Lilita One, the theme's heading face. The
## font Godot falls back to when the file is missing.
static func _number_font_face() -> Font:
	var font: Font = load(UiThemeScript.HEADING_FONT_PATH) as Font
	return font if font != null else ThemeDB.fallback_font

## One shared LabelSettings per font size (and one for the grey `0`).
func _settings_for(amount: float, font_size: int) -> LabelSettings:
	var key: int = font_size if amount > 0.0 else ZERO_SETTINGS_KEY
	var settings: LabelSettings = _label_settings.get(key)
	if settings == null:
		settings = LabelSettings.new()
		settings.font_size = font_size
		settings.font_color = Color.WHITE if amount > 0.0 else ZERO_NUMBER_COLOR
		settings.outline_size = maxi(4, font_size / 5)
		settings.outline_color = UiThemeScript.INK
		settings.font = _number_font_face()
		_label_settings[key] = settings
	return settings

## Parked nodes are out of the tree, so nothing else frees them.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for node: Node in _free_markers:
			if is_instance_valid(node):
				node.free()
		for node: Node in _free_numbers:
			if is_instance_valid(node):
				node.free()
		_free_markers.clear()
		_free_numbers.clear()

## How much to scale a marker or number up so it reads the same size on
## screen however far the camera is zoomed out (#163): 1 on a normal stage,
## 1 / zoom on a large one (issue #144), like RoundManager's name tags.
func _world_scale() -> float:
	var camera: Camera2D = get_viewport().get_camera_2d() if is_inside_tree() else null
	if camera != null and camera.zoom.x > 0.0:
		return 1.0 / camera.zoom.x
	return 1.0

func _zero_allowed(attacker: Node, victim: Node) -> bool:
	var key: String = "%d:%d" % [attacker.get_instance_id(), victim.get_instance_id()]
	var now: int = Engine.get_physics_frames()
	if _last_zero_frame.has(key) and now - int(_last_zero_frame[key]) < ZERO_COOLDOWN_FRAMES:
		return false
	_last_zero_frame[key] = now
	return true

func _identity_colour(attacker: Node) -> Color:
	var colour: Variant = attacker.get("identity_color")
	return colour if colour is Color else Color.WHITE

func _marker_arm(amount: float, lethal: bool) -> float:
	var arm: float = lerpf(MARKER_MIN_ARM, MARKER_MAX_ARM, clampf(amount / FULL_SCALE_DAMAGE, 0.0, 1.0))
	return arm * LETHAL_MARKER_SCALE if lethal else arm

func _number_font(amount: float) -> int:
	return roundi(lerpf(NUMBER_MIN_FONT, NUMBER_MAX_FONT, clampf(amount / FULL_SCALE_DAMAGE, 0.0, 1.0)))

## An X at the point of impact that pops in and fades.
class HitMarker extends Node2D:
	var colour: Color
	var arm: float
	var lethal: bool
	var amount: float
	var age: float = 0.0
	## The camera-zoom compensation the pop is applied on top of (#163).
	var base_scale: float = 1.0
	## Hands the finished marker back to the pool; freed instead without one.
	var done: Callable

	func setup(at: Vector2, c: Color, a: float, is_lethal: bool, dealt: float, world_scale: float = 1.0) -> void:
		position = at
		colour = c
		arm = a
		lethal = is_lethal
		amount = dealt
		age = 0.0
		base_scale = world_scale
		scale = Vector2.ONE * base_scale
		modulate.a = 1.0
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		age += delta
		if age >= MARKER_LIFETIME:
			set_process(false)
			if done.is_valid():
				done.call_deferred(self)
			else:
				queue_free()
			return
		var t: float = age / MARKER_LIFETIME
		# Pops slightly past full size, then settles while fading.
		scale = Vector2.ONE * base_scale * (1.0 + 0.3 * sin(minf(t * 3.0, 1.0) * PI))
		modulate.a = 1.0 - t
		queue_redraw()

	func _draw() -> void:
		var width: float = 4.0 if lethal else 3.0
		var outline: Color = Color(0, 0, 0, 0.8)
		for dir: Vector2 in [Vector2(1, 1), Vector2(1, -1)]:
			var d: Vector2 = dir.normalized() * arm
			draw_line(-d, d, outline, width + 2.0)
		for dir: Vector2 in [Vector2(1, 1), Vector2(1, -1)]:
			var d: Vector2 = dir.normalized() * arm
			draw_line(-d, d, colour, width)

## The damage a strike dealt, rising and fading from where it landed.
class DamageNumber extends Label:
	var amount: float
	var age: float = 0.0
	var _start: Vector2
	var _rise: float = NUMBER_RISE
	## Hands the finished number back to the pool; freed instead without one.
	var done: Callable

	## `settings` is shared between every number at this size; it is made
	## here only when the caller has none to share.
	func setup(at: Vector2, dealt: float, font_size: int, world_scale: float = 1.0, settings: LabelSettings = null) -> void:
		amount = dealt
		age = 0.0
		modulate.a = 1.0
		set_process(true)
		text = str(roundi(dealt))
		if settings == null:
			settings = LabelSettings.new()
			settings.font_size = font_size
			settings.font_color = Color.WHITE if dealt > 0.0 else ZERO_NUMBER_COLOR
			settings.outline_size = maxi(4, font_size / 5)
			settings.outline_color = UiThemeScript.INK
			settings.font = load(UiThemeScript.HEADING_FONT_PATH) as Font
		label_settings = settings
		horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		size = Vector2(font_size * 3, font_size * 1.5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Scaled from its top-left corner by the camera-zoom compensation (#163),
		# so the centring and the offset above the hit are scaled with it.
		scale = Vector2.ONE * world_scale
		_rise = NUMBER_RISE * world_scale
		# Centred on the hit, and a little above it so the marker stays visible.
		_start = at + (-size * 0.5 + Vector2(0, -font_size)) * world_scale
		position = _start

	func _process(delta: float) -> void:
		age += delta
		if age >= NUMBER_LIFETIME:
			set_process(false)
			if done.is_valid():
				done.call_deferred(self)
			else:
				queue_free()
			return
		var t: float = age / NUMBER_LIFETIME
		position = _start + Vector2(0, -_rise * t)
		modulate.a = 1.0 - t * t
