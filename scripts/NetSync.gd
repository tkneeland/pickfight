extends RefCounted
## Issue #976: how the Online client draws every in-world object that moves or
## changes on the host but is not a player, projectile or pickup, exactly as
## the host draws it. Two kinds:
##
## * **Stage parts** -- nodes in the stage scene the client loads too (saws,
##   moving platforms, crumbling ledges, fans, wind, rising lava, ...). Each
##   part script lists, in `NET_VARS`, the properties its look follows. The
##   host sends their values; the client stops its own copy of the part from
##   running (it has no players to react to) and sets them, so the client's
##   part is drawn by the part's own script, from the host's state. A part
##   whose look is a pure clock (lava waves, the parallax sky) lists the
##   clock in `NET_CLOCKS` instead and keeps running, re-set from the host's
##   value only when it drifts off. A part is named by its node path in the
##   stage, which both sides share.
## * **Props** -- things the host adds at runtime (the soccer ball, the CTF
##   flags, the King of the Hill hill, a tiebreaker rock, the Gale modifier's
##   gust). The host marks each with `mark_prop()`; the client builds the same
##   node from the same builder (`build_prop()`) and moves it.
##
## No `class_name`: consumers preload this by path.

const FallingRockScene: PackedScene = preload("res://scenes/parts/FallingRock.tscn")
const StageGustScript := preload("res://scripts/StageGust.gd")
# The mode scripts preload this one to mark their props, so this one loads
# them by path when it needs them rather than preloading them back.
const SOCCER_PATH: String = "res://scripts/Soccer.gd"
const CTF_PATH: String = "res://scripts/CaptureTheFlag.gd"
const KOTH_PATH: String = "res://scripts/KingOfTheHill.gd"

const PROPS_GROUP: StringName = &"net_props"
const PROP_META: StringName = &"net_prop"

const PROP_ROCK: int = 1
const PROP_GALE: int = 2
const PROP_SOCCER_BALL: int = 3
const PROP_CTF_FLAG: int = 4
const PROP_HILL: int = 5

## How far (in the clock's own units) a client clock may drift from the host's
## before it is re-set. A part may override it with `NET_CLOCK_TOLERANCE`.
const CLOCK_TOLERANCE: float = 0.25

const _HILL_STATES: Array[StringName] = [&"empty", &"held", &"contested"]

# --- Stage parts ------------------------------------------------------------

## A constant `key` declared by `node`'s script or any script it extends, or
## `fallback` when none does.
static func script_const(node: Object, key: String, fallback: Variant = null) -> Variant:
	var script: Script = node.get_script() as Script
	while script != null:
		var consts: Dictionary = script.get_script_constant_map()
		if consts.has(key):
			return consts[key]
		script = script.get_base_script()
	return fallback

## Per script: [NET_VARS, NET_CLOCKS], so the per-frame walk of the stage
## does not copy every script's constant map each time.
static var _decl_cache: Dictionary = {}

static func _decl(node: Object) -> Array:
	var script: Script = node.get_script() as Script
	if script == null:
		return [[], []]
	if not _decl_cache.has(script):
		_decl_cache[script] = [script_const(node, "NET_VARS", []), script_const(node, "NET_CLOCKS", [])]
	return _decl_cache[script]

static func vars_of(node: Object) -> Array:
	return _decl(node)[0]

static func clocks_of(node: Object) -> Array:
	return _decl(node)[1]

## Every part under `stage` (itself included) whose look the host sends, in
## tree order. Props, and anything under one, are not parts.
static func parts_of(stage: Node) -> Array[Node]:
	var out: Array[Node] = []
	if stage != null:
		_collect_parts(stage, out)
	return out

static func _collect_parts(node: Node, out: Array[Node]) -> void:
	if node.has_meta(PROP_META):
		return
	if not vars_of(node).is_empty() or not clocks_of(node).is_empty():
		out.append(node)
	for child: Node in node.get_children():
		_collect_parts(child, out)

## The id both sides give `node`: a hash of its path under `stage`.
static func part_id(stage: Node, node: Node) -> int:
	return hash(str(stage.get_path_to(node))) & 0xFFFFFFFF

## The values of `paths` on `node`. A path is a property name, or names
## joined with ":" through object properties (`"_visual:color"`).
static func read(node: Object, paths: Array) -> Array:
	var out: Array = []
	for path: String in paths:
		out.append(_get_path(node, path))
	return out

static func _get_path(node: Object, path: String) -> Variant:
	var names: PackedStringArray = path.split(":")
	var target: Variant = node
	for i in names.size():
		if not (target is Object) or not is_instance_valid(target):
			return null
		target = (target as Object).get(names[i])
	return target

static func _set_path(node: Object, path: String, value: Variant) -> void:
	var names: PackedStringArray = path.split(":")
	var target: Variant = node
	for i in names.size() - 1:
		if not (target is Object) or not is_instance_valid(target):
			return
		target = (target as Object).get(names[i])
	if target is Object and is_instance_valid(target) and value != null:
		(target as Object).set(names[names.size() - 1], value)

## What the host sends for `node`: its `NET_VARS` values, then its clocks.
static func part_state(node: Object) -> Array:
	return read(node, vars_of(node)) + read(node, clocks_of(node))

## Stops the client's copy of a part from running its own logic, when the
## host's state drives its look. Clock-only parts keep running.
static func freeze_part(node: Node) -> void:
	if vars_of(node).is_empty():
		return
	node.set_process(false)
	node.set_physics_process(false)
	# A moving platform syncs to physics: a position set outside its own
	# physics step is put back until the next tick. The copy just shows the
	# host's place, at once.
	if node is AnimatableBody2D:
		(node as AnimatableBody2D).sync_to_physics = false

## Sets a part's look from the host's `state` (as `part_state()` sends it).
## Its clocks are re-set only when `sync_clocks`, and only when they drifted.
static func apply_part(node: Node, state: Array, sync_clocks: bool) -> void:
	var vars: Array = vars_of(node)
	var clocks: Array = clocks_of(node)
	for i in mini(vars.size(), state.size()):
		_set_path(node, vars[i], state[i])
	if sync_clocks:
		var tolerance: float = float(script_const(node, "NET_CLOCK_TOLERANCE", CLOCK_TOLERANCE))
		for j in clocks.size():
			var k: int = vars.size() + j
			if k >= state.size():
				break
			var mine: Variant = _get_path(node, clocks[j])
			var theirs: Variant = state[k]
			if (theirs is float or theirs is int) and (mine is float or mine is int):
				if absf(float(mine) - float(theirs)) > tolerance:
					_set_path(node, clocks[j], float(theirs))
	if not vars.is_empty():
		if node.has_method("_net_refresh"):
			node.call("_net_refresh")
		if node is CanvasItem:
			(node as CanvasItem).queue_redraw()

## A state between `a` and `b` (`t` in 0..1): numbers, vectors and colours
## are blended (an angle the short way round), anything else is `b`'s.
static func lerp_state(paths: Array, a: Array, b: Array, t: float) -> Array:
	if a.size() != b.size():
		return b
	var out: Array = []
	for i in b.size():
		var path: String = paths[i] if i < paths.size() else ""
		out.append(_lerp_value(path, a[i], b[i], t))
	return out

static func _lerp_value(path: String, a: Variant, b: Variant, t: float) -> Variant:
	if a is float and b is float:
		return lerp_angle(a, b, t) if path.ends_with("rotation") else lerpf(a, b, t)
	if a is Vector2 and b is Vector2:
		return (a as Vector2).lerp(b, t)
	if a is Color and b is Color:
		return (a as Color).lerp(b, t)
	return b

# --- Props --------------------------------------------------------------------

## Marks a node the host adds at runtime so it is sent to Online clients.
static func mark_prop(node: Node, kind: int) -> void:
	node.set_meta(PROP_META, kind)
	node.add_to_group(PROPS_GROUP)

static func prop_kind(node: Node) -> int:
	return int(node.get_meta(PROP_META, 0))

## What the host sends for prop `node`.
static func prop_state(node: Node) -> Array:
	match prop_kind(node):
		PROP_ROCK:
			return [(node as Node2D).global_position] + part_state(node)
		PROP_GALE:
			var zone: Node = node.call("gust_zone")
			return [(node as Node2D).global_position, node.size, node.direction, node.strength, node.calm_sec,
				node.warning_sec, node.gust_sec, node.cycle_offset_sec] + (part_state(zone) if zone != null else [])
		PROP_SOCCER_BALL:
			return [(node as Node2D).global_position, (node as Node2D).global_rotation]
		PROP_CTF_FLAG:
			return [int(node.get_meta(&"team", 0)), (node as Node2D).global_position, (node as Node2D).scale.x,
				(node as CanvasItem).is_visible_in_tree()]
		PROP_HILL:
			return node.call("net_state")
	return []

## Builds the client's copy of a prop of `kind` from its first `state`, with
## the host's own builder. Null for an unknown kind or a malformed state.
static func build_prop(kind: int, state: Array) -> Node2D:
	var node: Node2D = null
	match kind:
		PROP_ROCK:
			if state.is_empty() or not (state[0] is Vector2):
				return null
			node = FallingRockScene.instantiate() as Node2D
			node.set("auto_drop", false)
			node.position = state[0]
		PROP_GALE:
			if state.size() < 8:
				return null
			var gust: Node2D = StageGustScript.new()
			gust.name = "GaleGust" # RoundModifiers.GALE_NODE_NAME, as the host's
			for i in 8:
				if state[i] == null:
					return null
			gust.position = state[0]
			gust.size = state[1]
			gust.direction = state[2]
			gust.strength = state[3]
			gust.calm_sec = state[4]
			gust.warning_sec = state[5]
			gust.gust_sec = state[6]
			gust.cycle_offset_sec = state[7]
			node = gust
		PROP_SOCCER_BALL:
			node = Node2D.new()
			node.name = "SoccerBall"
			load(SOCCER_PATH).build_ball_visuals(node)
			node.z_index = 5
		PROP_CTF_FLAG:
			if state.is_empty() or not (state[0] is int):
				return null
			var flag: Node2D = load(CTF_PATH).build_flag(clampi(state[0], 0, 1))
			# The host's flags sit in a z 6 holder; the copy carries it itself.
			flag.z_index = 6
			node = flag
		PROP_HILL:
			node = HillView.new()
		_:
			return null
	# The meta only: the copy is not one of the host's props to capture.
	node.set_meta(PROP_META, kind)
	return node

## Called once the prop is in the tree: stops its own logic where the host's
## state drives it.
static func settle_prop(node: Node) -> void:
	match prop_kind(node):
		PROP_ROCK:
			freeze_part(node)
		PROP_GALE:
			var zone: Node = node.call("gust_zone")
			if zone != null:
				freeze_part(zone)

## Moves the client's copy of a prop to the host's `state`.
static func apply_prop(node: Node2D, state: Array) -> void:
	match prop_kind(node):
		PROP_ROCK:
			if state.size() >= 1 and state[0] is Vector2:
				node.global_position = state[0]
			apply_part(node, state.slice(1), false)
		PROP_GALE:
			if state.size() >= 1 and state[0] is Vector2:
				node.global_position = state[0]
			var zone: Node = node.call("gust_zone")
			if zone != null and state.size() > 8:
				apply_part(zone, state.slice(8), false)
		PROP_SOCCER_BALL:
			if state.size() >= 2 and state[0] is Vector2 and (state[1] is float or state[1] is int):
				node.global_position = state[0]
				node.global_rotation = float(state[1])
		PROP_CTF_FLAG:
			if state.size() >= 4 and state[1] is Vector2:
				node.global_position = state[1]
				node.scale = Vector2.ONE * float(state[2])
				node.visible = bool(state[3])
		PROP_HILL:
			(node as HillView).show_state(state)

## The paths `lerp_state` blends a prop's state with (rotations the short way).
static func prop_paths(kind: int) -> Array:
	match kind:
		PROP_SOCCER_BALL:
			return ["global_position", "global_rotation"]
	return []

## The King of the Hill hill as the Online client draws it: the host's own
## `KingOfTheHill.draw_hill()`, from the host's `net_state()`.
class HillView extends Node2D:
	var _state: Array = []

	func show_state(state: Array) -> void:
		_state = state
		queue_redraw()

	## The host's `KingOfTheHill.net_state()` this copy draws.
	func state() -> Array:
		return _state

	func _process(_delta: float) -> void:
		queue_redraw() # the crown bobs and the contested ring flashes on the clock

	func _draw() -> void:
		if _state.size() < 7 or not (_state[0] is Vector2) or not (_state[6] is Vector2):
			return
		var code: int = clampi(int(_state[2]), 0, _HILL_STATES.size() - 1)
		var colour: Color = _state[3] if _state[3] is Color else Color(1.0, 0.85, 0.2)
		load(KOTH_PATH).draw_hill(self, to_local(_state[0]), float(_state[1]), _HILL_STATES[code], colour,
			float(_state[4]), bool(_state[5]), to_local(_state[6]), Time.get_ticks_msec())
