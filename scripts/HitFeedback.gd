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

func _ready() -> void:
	z_index = 100
	get_tree().node_added.connect(_on_node_added)
	for player in get_tree().get_nodes_in_group("players"):
		_watch(player)

func _on_node_added(node: Node) -> void:
	_watch(node)

func _watch(node: Node) -> void:
	if not node.has_signal("strike_landed"):
		return
	var handler: Callable = _on_strike_landed.bind(node)
	if not node.is_connected("strike_landed", handler):
		node.connect("strike_landed", handler)

## `attacker` comes last because that is where the signal's bind puts it.
func _on_strike_landed(victim: Node, amount: float, point: Vector2, lethal: bool, attacker: Node) -> void:
	if amount > 0.0:
		var colour: Color = LETHAL_COLOR if lethal else _identity_colour(attacker)
		var marker := HitMarker.new()
		marker.setup(point, colour, _marker_arm(amount, lethal), lethal, amount)
		add_child(marker)
	elif not _zero_allowed(attacker, victim):
		return
	if show_damage_numbers:
		var number := DamageNumber.new()
		number.setup(point, amount, _number_font(amount))
		add_child(number)

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

	func setup(at: Vector2, c: Color, a: float, is_lethal: bool, dealt: float) -> void:
		position = at
		colour = c
		arm = a
		lethal = is_lethal
		amount = dealt

	func _process(delta: float) -> void:
		age += delta
		if age >= MARKER_LIFETIME:
			queue_free()
			return
		var t: float = age / MARKER_LIFETIME
		# Pops slightly past full size, then settles while fading.
		scale = Vector2.ONE * (1.0 + 0.3 * sin(minf(t * 3.0, 1.0) * PI))
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

	func setup(at: Vector2, dealt: float, font_size: int) -> void:
		amount = dealt
		text = str(roundi(dealt))
		var settings := LabelSettings.new()
		settings.font_size = font_size
		settings.font_color = Color.WHITE if dealt > 0.0 else ZERO_NUMBER_COLOR
		settings.outline_size = maxi(4, font_size / 5)
		settings.outline_color = Color(0, 0, 0, 0.9)
		label_settings = settings
		horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		size = Vector2(font_size * 3, font_size * 1.5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Centred on the hit, and a little above it so the marker stays visible.
		_start = at - size * 0.5 + Vector2(0, -font_size)
		position = _start

	func _process(delta: float) -> void:
		age += delta
		if age >= NUMBER_LIFETIME:
			queue_free()
			return
		var t: float = age / NUMBER_LIFETIME
		position = _start + Vector2(0, -NUMBER_RISE * t)
		modulate.a = 1.0 - t * t
