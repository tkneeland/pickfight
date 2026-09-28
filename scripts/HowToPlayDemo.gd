extends HBoxContainer

## One lesson of the lobby's how-to-play panel, shown rather than told
## (#219): a phone with the thumb that is dragging on it, a tiny stage where a
## real `Player` does what that drag makes it do, and a one-line caption.
##
## The stage is a puppet show, not a recording. It lives in its own
## `SubViewport` with its own `World2D`, so its bodies share no physics space
## with the match (or with each other's demos), and the players on it are
## real `scenes/Player.tscn` instances driven through `set_input_vector()` --
## the same seam a phone and the scenario suite use -- by a canned thumb. So
## the demos stay true to the game as weapons and physics change. Each one
## rebuilds its stage from scratch and plays again every few seconds.
##
## Nothing a demo player does may reach the match. Its bodies can only touch
## what is in its own world; the listeners that watch every node entering the
## tree for players, heads and bullets (SfxHooks, Juice, HitFeedback, the
## Announcer) skip anything under a demo viewport (`is_demo_node()`); and the
## round loop, name tags, kill feed, stats and rumble only ever know the
## players RoundManager owns. Each demo's world also sits far out from the
## match and from the other demos (`WORLD_SPACING`), because a weapon head
## looks for other heads by tree group and position, not by world. The lobby
## frees every demo the moment it hides (`LobbyScreen.show_panel`).

## Loaded when a demo is built rather than preloaded: the tree-wide
## listeners preload this script for `is_demo_node()`, and some of them load
## with the Sfx autoload, before the game's scenes are wanted.
const PLAYER_SCENE_PATH: String = "res://scenes/Player.tscn"
const PICKUP_SCENE_PATH: String = "res://scenes/Pickup.tscn"
## What the pickup demo hands over: a blade, so the swap reads at a glance.
const PICKUP_WEAPON_PATH: String = "res://resources/sword.tres"

## Set on each demo's SubViewport; `is_demo_node()` reads it.
const DEMO_VIEWPORT_META: StringName = &"howto_demo"

enum Kind { SWING, CLIMB, PICKUP, WIN }

## The stage window, in screen pixels, and how much of the world it shows.
const VIEW_SIZE: Vector2i = Vector2i(224, 126)
const VIEW_SCALE: float = 0.5
## Each demo's world is centred this far out along x per demo (and down by
## the same), well clear of any stage and of each other's heads.
const WORLD_SPACING: float = 20000.0
const CAPTION_WIDTH_PX: float = 156.0
const PHONE_SIZE: Vector2 = Vector2(44, 78)
## Thumb trail length, in physics ticks.
const TRAIL_TICKS: int = 14

const SKY_COLOR: Color = Color(0.13, 0.15, 0.22, 1.0)
const TERRAIN_COLOR: Color = Color(0.35, 0.37, 0.45, 1.0)
const LAVA_COLOR: Color = Color(0.9, 0.2, 0.05, 1.0)
const LAVA_EDGE_COLOR: Color = Color(1.0, 0.75, 0.2, 1.0)
const HERO_COLOR: Color = Color(1.0, 0.85, 0.2, 1.0)
const RIVAL_COLOR: Color = Color(0.35, 0.75, 1.0, 1.0)
const PHONE_COLOR: Color = Color(0.85, 0.87, 0.92, 1.0)
const THUMB_COLOR: Color = Color(1.0, 0.85, 0.2, 1.0)

const PLAYER_RADIUS: float = 24.0

## Seconds each demo runs before it resets.
const LOOP_SEC: Dictionary = {
	Kind.SWING: 4.2,
	Kind.CLIMB: 6.5,
	Kind.PICKUP: 4.5,
	Kind.WIN: 4.5,
}

## Canned thumbs, as `Vector3(time_sec, angle_rad, length)` keyframes: the
## drag's angle and length are eased from one keyframe to the next, and a
## length of 0 is a lifted thumb (`Vector2.ZERO`) until the next keyframe.
## Angles are screen angles: 0 right, PI/2 down, -PI/2 up.
const SWING_KEYS: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0),
	Vector3(0.5, PI * 1.1, 0.3),
	# A slow drag round overhead: the pick follows the thumb.
	Vector3(1.9, PI * 1.85, 0.8),
	Vector3(2.3, PI * 1.5, 1.0),
	# The flick: a quick drag from straight up to down-right, into the rival.
	Vector3(2.48, PI * 2.15, 1.0),
	Vector3(2.78, PI * 2.15, 1.0),
	Vector3(2.88, 0.0, 0.0),
]
const PICKUP_KEYS: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0),
	Vector3(0.3, PI * 0.72, 0.02),
	Vector3(0.7, PI * 0.72, 0.02),
	# Planted down and behind, then pushed out: the body vaults forward.
	Vector3(0.85, PI * 0.72, 1.0),
	Vector3(1.3, PI * 0.72, 1.0),
	Vector3(1.4, 0.0, 0.0),
	# Showing off the new weapon.
	Vector3(2.6, -PI * 0.5, 0.2),
	Vector3(3.4, -PI * 0.05, 1.0),
	Vector3(3.8, -PI * 0.05, 1.0),
	Vector3(3.9, 0.0, 0.0),
]
## The win demo swings as the swing demo does, from the same distance, at a
## rival near the edge, then digs the pick in behind so the hero stops short
## of the edge itself.
const WIN_KEYS: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0),
	Vector3(0.5, PI * 1.1, 0.3),
	Vector3(1.9, PI * 1.85, 0.8),
	Vector3(2.3, PI * 1.5, 1.0),
	Vector3(2.48, PI * 2.05, 1.0),
	Vector3(2.7, PI * 2.05, 1.0),
	Vector3(2.9, PI * 2.75, 0.3),
	Vector3(4.0, PI * 2.75, 0.3),
	Vector3(4.1, 0.0, 0.0),
]

## The win demo's rival is sent flying this fast when the hero's strike lands
## on it. A real strike deals damage but barely moves a body (a KO takes
## several, or a ram, and a ram is too chaotic to land the same way at every
## physics rate), so the puppet show plays the knock-off up to read in one loop.
const WIN_KNOCK_VELOCITY: Vector2 = Vector2(360.0, -300.0)

var kind: int = Kind.SWING
var caption: String = ""
## Which demo this is on the panel, for its world offset.
var index: int = 0

var _viewport: SubViewport
var _phone: Control
var _stage: Node2D
var _hero: RigidBody2D
var _rival: RigidBody2D
var _pickup: Node
var _lava_y: float = INF
var _clock: float = 0.0
var _loops: int = 0
var _input: Vector2 = Vector2.ZERO
var _trail: Array[Vector2] = []
var _origin: Vector2 = Vector2.ZERO
var _climb: Dictionary = {}
## The canned thumb and where the two players start, per demo; variables
## rather than constants only so a tuning probe can try others.
var keys: Array[Vector3] = []
var hero_at: Vector2 = Vector2.ZERO
var rival_at: Vector2 = Vector2.ZERO
## The right-hand edge of the win demo's platform, over the lava.
var edge_x: float = 110.0
var _rival_hurt: float = 0.0
var _knocked: bool = false

## Whether `node` lives under a demo's stage: the tree-wide listeners use this
## to leave demo players, heads and bullets alone.
static func is_demo_node(node: Node) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	var viewport: Viewport = node.get_viewport()
	return viewport != null and viewport.has_meta(DEMO_VIEWPORT_META)

func _init(demo_kind: int = Kind.SWING, text: String = "", demo_index: int = 0) -> void:
	kind = demo_kind
	caption = text
	index = demo_index
	name = "HowToPlayDemo%d" % demo_index
	add_theme_constant_override("separation", 10)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	_origin = Vector2(WORLD_SPACING * float(demo_index + 1), WORLD_SPACING)
	match kind:
		Kind.SWING:
			keys = SWING_KEYS
			hero_at = Vector2(-50.0, -PLAYER_RADIUS)
			rival_at = Vector2(100.0, -PLAYER_RADIUS)
		Kind.CLIMB:
			hero_at = Vector2(CLIMB_EDGE - PLAYER_RADIUS
				- float(CLIMB_GAP_BY_HZ.get(Engine.physics_ticks_per_second, CLIMB_GAP)), -PLAYER_RADIUS)
		Kind.PICKUP:
			keys = PICKUP_KEYS
			hero_at = Vector2(-120.0, -PLAYER_RADIUS)
		Kind.WIN:
			keys = WIN_KEYS
			hero_at = Vector2(-80.0, -PLAYER_RADIUS)
			rival_at = Vector2(70.0, -PLAYER_RADIUS)

func _ready() -> void:
	_phone = Control.new()
	_phone.name = "Phone"
	_phone.custom_minimum_size = PHONE_SIZE
	_phone.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_phone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phone.draw.connect(_draw_phone)
	add_child(_phone)

	var frame := SubViewportContainer.new()
	frame.name = "Stage"
	frame.custom_minimum_size = Vector2(VIEW_SIZE)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	_viewport = SubViewport.new()
	_viewport.name = "DemoViewport"
	_viewport.size = VIEW_SIZE
	_viewport.set_meta(DEMO_VIEWPORT_META, true)
	_viewport.world_2d = World2D.new()
	_viewport.audio_listener_enable_2d = false
	_viewport.gui_disable_input = true
	_viewport.physics_object_picking = false
	frame.add_child(_viewport)
	# Set once it is in the tree: the canvas it moves only exists from then.
	_viewport.canvas_transform = Transform2D(0.0, Vector2(VIEW_SCALE, VIEW_SCALE), 0.0,
		Vector2(VIEW_SIZE) * 0.5 - (_origin + _view_centre()) * VIEW_SCALE)

	var label := Label.new()
	label.name = "Caption"
	label.text = caption
	label.custom_minimum_size.x = CAPTION_WIDTH_PX
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)

	_build_stage()

## The demo's stage viewport (for the scenario suite).
func viewport() -> SubViewport:
	return _viewport

## The player the thumb drives, and the one it plays against (null in the
## demos that have none). Both change every loop.
func hero() -> RigidBody2D:
	return _hero

func rival() -> RigidBody2D:
	return _rival

## Every player on this demo's stage now.
func demo_players() -> Array[RigidBody2D]:
	var out: Array[RigidBody2D] = []
	for p: RigidBody2D in [_hero, _rival]:
		if p != null and is_instance_valid(p):
			out.append(p)
	return out

## Times the demo has started over.
func loops() -> int:
	return _loops

## What the thumb is sending now.
func thumb() -> Vector2:
	return _input

func _physics_process(delta: float) -> void:
	if _stage == null:
		return
	_clock += delta
	if _clock >= float(LOOP_SEC[kind]) or _demo_done():
		_build_stage()
		_loops += 1
		return
	_input = _thumb_now()
	if _hero != null and is_instance_valid(_hero) and _hero.alive:
		_hero.set_input_vector(_input)
	if kind == Kind.WIN and not _knocked and _rival != null and is_instance_valid(_rival) and _rival.alive 			and float(_rival.damage) > _rival_hurt:
		_knocked = true
		_rival.linear_velocity = WIN_KNOCK_VELOCITY
	if _rival != null and is_instance_valid(_rival) and _rival.alive and _rival.global_position.y - _origin.y > _lava_y:
		_rival.eliminate()
	if _hero != null and is_instance_valid(_hero) and _hero.alive and _hero.global_position.y - _origin.y > _lava_y:
		_hero.eliminate()
	_trail.append(_input)
	if _trail.size() > TRAIL_TICKS:
		_trail.pop_front()
	_phone.queue_redraw()

## A demo that has plainly gone wrong (a body out of the window) starts over
## early rather than showing an empty stage.
func _demo_done() -> bool:
	for p: RigidBody2D in demo_players():
		if p.alive and (p.global_position - _origin).length() > 900.0:
			return true
	# The climb takes as long as it takes: once up, a moment on top, again.
	if kind == Kind.CLIMB and int(_climb.get("phase", -1)) == CLIMB_UP:
		_climb["up_sec"] = float(_climb.get("up_sec", 0.0)) + get_physics_process_delta_time()
		return float(_climb["up_sec"]) >= CLIMB_SHOW_SEC
	return false

func _thumb_now() -> Vector2:
	if kind == Kind.CLIMB:
		return _climb_thumb()
	return _keyed(keys, _clock)

static func _keyed(keys: Array[Vector3], t: float) -> Vector2:
	var last: Vector3 = keys[keys.size() - 1]
	if t >= last.x:
		return Vector2.ZERO if last.z <= 0.0 else Vector2.RIGHT.rotated(last.y) * last.z
	for i in range(keys.size() - 1):
		var a: Vector3 = keys[i]
		var b: Vector3 = keys[i + 1]
		if t < a.x or t >= b.x:
			continue
		if a.z <= 0.0:
			return Vector2.ZERO
		if b.z <= 0.0:
			return Vector2.RIGHT.rotated(a.y) * a.z
		var f: float = smoothstep(0.0, 1.0, (t - a.x) / maxf(b.x - a.x, 0.0001))
		return Vector2.RIGHT.rotated(lerpf(a.y, b.y, f)) * lerpf(a.z, b.z, f)
	return Vector2.ZERO

# --- Stages ---------------------------------------------------------------------

## Where the window looks, relative to the demo's origin.
func _view_centre() -> Vector2:
	match kind:
		Kind.CLIMB:
			return Vector2(20.0, -70.0)
		Kind.WIN:
			return Vector2(20.0, 10.0)
	return Vector2(0.0, -60.0)

func _build_stage() -> void:
	if _stage != null:
		# Out of the world at once, so the old bodies never meet the new ones.
		_viewport.remove_child(_stage)
		_stage.queue_free()
	_stage = Node2D.new()
	_stage.name = "DemoStage"
	_stage.position = _origin
	_hero = null
	_rival = null
	_pickup = null
	_lava_y = INF
	_knocked = false
	_clock = 0.0
	_input = Vector2.ZERO
	_trail.clear()
	_climb = {"phase": CLIMB_HOOK, "ticks": 0, "lost": 0, "pushing": false}
	var sky := Polygon2D.new()
	var half: Vector2 = Vector2(VIEW_SIZE) / VIEW_SCALE
	var c: Vector2 = _view_centre()
	sky.polygon = PackedVector2Array([c - half, c + Vector2(half.x, -half.y), c + half, c + Vector2(-half.x, half.y)])
	sky.color = SKY_COLOR
	_stage.add_child(sky)
	match kind:
		Kind.SWING:
			_add_block(Vector2(0.0, 20.0), Vector2(1200.0, 40.0))
			_hero = _add_player(hero_at, HERO_COLOR)
			_rival = _add_player(rival_at, RIVAL_COLOR)
		Kind.CLIMB:
			_add_block(Vector2(0.0, 20.0), Vector2(1200.0, 40.0))
			_add_block(Vector2(CLIMB_EDGE + 300.0, -CLIMB_LEDGE_HEIGHT * 0.5), Vector2(600.0, CLIMB_LEDGE_HEIGHT))
			_hero = _add_player(hero_at, HERO_COLOR)
		Kind.PICKUP:
			_add_block(Vector2(0.0, 20.0), Vector2(1200.0, 40.0))
			_hero = _add_player(hero_at, HERO_COLOR)
			_pickup = (load(PICKUP_SCENE_PATH) as PackedScene).instantiate()
			_pickup.set_weapon(load(PICKUP_WEAPON_PATH))
			_pickup.position = PICKUP_AT
			_stage.add_child(_pickup)
		Kind.WIN:
			_lava_y = 90.0
			var lava := Polygon2D.new()
			lava.polygon = PackedVector2Array([Vector2(-600, _lava_y), Vector2(600, _lava_y), Vector2(600, 600), Vector2(-600, 600)])
			lava.color = LAVA_COLOR
			_stage.add_child(lava)
			var edge := Line2D.new()
			edge.points = PackedVector2Array([Vector2(-600, _lava_y), Vector2(600, _lava_y)])
			edge.width = 6.0
			edge.default_color = LAVA_EDGE_COLOR
			_stage.add_child(edge)
			_add_block(Vector2((edge_x - 400.0) * 0.5, 20.0), Vector2(edge_x + 400.0, 40.0))
			_hero = _add_player(hero_at, HERO_COLOR)
			_rival = _add_player(rival_at, RIVAL_COLOR)
	_viewport.add_child(_stage)
	_rival_hurt = float(_rival.damage) if _rival != null else 0.0

## Where the pickup demo's pickup floats: on the hero's vault.
const PICKUP_AT: Vector2 = Vector2(20.0, -80.0)

func _add_block(centre: Vector2, block_size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = centre
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = block_size
	shape.shape = rect
	body.add_child(shape)
	var fill := Polygon2D.new()
	var h: Vector2 = block_size * 0.5
	fill.polygon = PackedVector2Array([-h, Vector2(h.x, -h.y), h, Vector2(-h.x, h.y)])
	fill.color = TERRAIN_COLOR
	body.add_child(fill)
	_stage.add_child(body)

func _add_player(at: Vector2, colour: Color) -> RigidBody2D:
	var player: RigidBody2D = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as RigidBody2D
	player.position = at
	player.identity_color = colour
	player.bind_controller()
	_stage.add_child(player)
	return player

# --- The climb's thumb ------------------------------------------------------------
#
# A ledge climb depends on where a head happens to land, so a keyframed thumb
# would miss as often as not. This one watches the head the way a player
# does, the same thumb the scenario suite's traversal trial (#136) climbs
# with: hook the head over the top, swing the body up and over it, and vault
# off the floor first when the head cannot reach from there.

const CLIMB_EDGE: float = 60.0
const CLIMB_LEDGE_HEIGHT: float = 80.0
## How far from the ledge the hero starts. Where a head lands decides a
## climb, and where it lands at 60 Hz (normal play) and at 120 Hz (the game's
## --demo mode) are not the same: these starts climb at each.
const CLIMB_GAP: float = 10.0
const CLIMB_GAP_BY_HZ: Dictionary = {60: 10.0, 120: 60.0}
const CLIMB_TARGET_INSET: float = 40.0
const CLIMB_PRESS: float = 15.0
const CLIMB_CLEARANCE: float = 40.0
const CLIMB_OVER_MARGIN: float = 2.0
const CLIMB_PLANT_DEPTH: float = 16.0
const CLIMB_HOOK_SWING: float = 0.35
const CLIMB_HOOK_TIMEOUT: int = 40
const CLIMB_SWING_TIMEOUT: int = 90
const CLIMB_SWING_LOST_TICKS: int = 4
const CLIMB_SWING_STEP: float = 0.3
const CLIMB_SWING_END: float = PI * 0.75
const CLIMB_AIM_TIMEOUT: int = 20
const CLIMB_VAULT_CLEAR: float = 10.0
const CLIMB_REST_SPEED: float = 40.0
## Waits this long standing before the first reach, so the move reads, and
## this long on top before starting over.
const CLIMB_START_SEC: float = 0.5
const CLIMB_SHOW_SEC: float = 1.5
enum { CLIMB_VAULT, CLIMB_HOOK, CLIMB_SWING, CLIMB_UP }

## The thumb decides at 60 Hz, the rate its tick counts and swing step were
## tuned at, and holds between decisions when the game runs faster (demo
## mode's 120 Hz).
func _climb_thumb() -> Vector2:
	_climb["sub"] = float(_climb.get("sub", 0.0)) + 60.0 / float(Engine.physics_ticks_per_second)
	if float(_climb["sub"]) < 1.0 - 0.001:
		return _climb.get("held", Vector2.ZERO)
	_climb["sub"] = float(_climb["sub"]) - 1.0
	_climb["held"] = _climb_decide()
	return _climb["held"]

func _climb_decide() -> Vector2:
	if _hero == null or not is_instance_valid(_hero) or not _hero.alive or _clock < CLIMB_START_SEC:
		return Vector2.ZERO
	var stats: Resource = _hero.weapon_stats
	var min_reach: float = stats.min_reach
	var max_reach: float = stats.max_reach
	var top: float = -CLIMB_LEDGE_HEIGHT
	var floor_rest: float = -PLAYER_RADIUS
	var body: Vector2 = _hero.global_position - _origin
	var head_pos: Vector2 = _hero.weapon_head_position() - _origin
	var bearing: Vector2 = head_pos - body
	var forward: float = 0.0
	for circle: Dictionary in _hero.weapon_head_circles():
		forward = maxf(forward, (circle["offset"] as Vector2).x + float(circle["radius"]))
	var tip: Vector2 = head_pos + bearing.normalized() * forward
	var touching: bool = _head_touching_ledge()
	var over: bool = tip.x > CLIMB_EDGE + CLIMB_OVER_MARGIN
	var grounded: bool = body.y >= floor_rest - 2.0 and absf(_hero.linear_velocity.y) < CLIMB_REST_SPEED
	var reach: float = bearing.length()
	_climb["ticks"] += 1
	if body.x > CLIMB_EDGE and body.y + PLAYER_RADIUS <= top + 3.0:
		_climb["phase"] = CLIMB_UP
	match int(_climb["phase"]):
		CLIMB_UP:
			if body.y + PLAYER_RADIUS > top + 3.0:
				_climb_phase(CLIMB_HOOK)
			return Vector2.ZERO
		CLIMB_VAULT:
			var vault: Vector2 = Vector2.DOWN
			var aimed: bool = absf(wrapf(bearing.angle() - vault.angle(), -PI, PI)) <= 0.2
			# A head wedged against the floor may never quite point down:
			# push anyway after a moment.
			if not aimed and not _climb["pushing"] and _climb["ticks"] < CLIMB_AIM_TIMEOUT:
				return vault * 0.02
			if not _climb["pushing"]:
				_climb["pushing"] = true
				_climb["ticks"] = 0
			if body.y + PLAYER_RADIUS < top - CLIMB_VAULT_CLEAR or (_climb["ticks"] > 3 and (_hero.linear_velocity.y >= 0.0 or reach >= max_reach - 4.0)):
				_climb_phase(CLIMB_HOOK)
			return vault
		CLIMB_HOOK:
			if touching and over and absf(tip.y - top) < CLIMB_PLANT_DEPTH:
				_climb_phase(CLIMB_SWING)
			elif grounded and _climb["ticks"] > CLIMB_HOOK_TIMEOUT:
				_climb_phase(CLIMB_VAULT)
			var target: Vector2 = Vector2(CLIMB_EDGE + CLIMB_TARGET_INSET, top)
			var aim_at: Vector2 = target + (Vector2.DOWN * CLIMB_PRESS if over else Vector2.UP * CLIMB_CLEARANCE)
			var to: Vector2 = aim_at - body
			var want: float = clampf(to.length() - forward, min_reach, max_reach)
			var magnitude: float = clampf((want - min_reach) / (max_reach - min_reach), 0.02, 1.0)
			if absf(wrapf(bearing.angle() - to.angle(), -PI, PI)) > CLIMB_HOOK_SWING:
				magnitude = 0.02
			return to.normalized() * magnitude
		CLIMB_SWING:
			_climb["lost"] = 0 if touching else int(_climb["lost"]) + 1
			if _climb["ticks"] > CLIMB_SWING_TIMEOUT or _climb["lost"] > CLIMB_SWING_LOST_TICKS:
				_climb_phase(CLIMB_VAULT if grounded else CLIMB_HOOK)
			var angle: float = minf(bearing.angle() + CLIMB_SWING_STEP, CLIMB_SWING_END)
			var hold: float = clampf((reach - min_reach) / (max_reach - min_reach), 0.02, 1.0)
			return Vector2.RIGHT.rotated(angle) * hold
	return Vector2.ZERO

func _climb_phase(phase: int) -> void:
	_climb["phase"] = phase
	_climb["ticks"] = 0
	_climb["lost"] = 0
	_climb["pushing"] = false

## Whether the hero's head is resting on terrain (the ledge or the floor it
## is reaching from), read off the head's own contacts.
func _head_touching_ledge() -> bool:
	var head: Variant = _hero.get("_head")
	if head == null or not is_instance_valid(head) or not (head as Node).is_inside_tree():
		return false
	for other: Node in (head as RigidBody2D).get_colliding_bodies():
		if other is StaticBody2D:
			return true
	return false

# --- The phone ------------------------------------------------------------------

func _draw_phone() -> void:
	var s: Vector2 = _phone.size
	var body := Rect2(Vector2(2, 2), s - Vector2(4, 4))
	_phone.draw_rect(body, Color(0.08, 0.09, 0.12, 1.0), true)
	_phone.draw_rect(body, PHONE_COLOR, false, 2.0)
	var centre: Vector2 = body.get_center()
	var radius: float = minf(body.size.x, body.size.y) * 0.5 - 6.0
	_phone.draw_arc(centre, radius, 0.0, TAU, 24, Color(PHONE_COLOR, 0.25), 1.0)
	for i in _trail.size():
		var v: Vector2 = _trail[i]
		if v == Vector2.ZERO:
			continue
		var a: float = float(i + 1) / float(_trail.size() + 1)
		_phone.draw_circle(centre + v * radius, 2.0 + 2.0 * a, Color(THUMB_COLOR, 0.35 * a))
	if _input != Vector2.ZERO:
		_phone.draw_line(centre, centre + _input * radius, Color(THUMB_COLOR, 0.5), 1.5)
		_phone.draw_circle(centre + _input * radius, 6.0, THUMB_COLOR)
	else:
		_phone.draw_arc(centre, 5.0, 0.0, TAU, 12, Color(PHONE_COLOR, 0.5), 1.0)
