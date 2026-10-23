extends Node2D

## Night variant of a stage (issue #332): a dimmed canvas lit by lamps and by
## a soft glow on every player, weapon head, pickup and hazard. Visual only --
## no collision, physics or rules change -- and applied by data: `Stage.night`
## adds one of these as a child, so no stage scene is duplicated.
##
## Lighting approach: the project renders with `gl_compatibility`, which
## supports `CanvasModulate` and `PointLight2D` (no shadows used, which keeps
## the cost low). The modulate is deliberately only mildly dark so players
## stay readable even before their glow is added.
##
## Reduce flashes (#317): lamps gently flicker, unless the saved setting is on,
## when they hold a steady light.

## Preloaded by path, never by `class_name` (CLAUDE.md).
const PartKitScript := preload("res://scripts/PartKit.gd")
const NIGHT_TINT: Color = Color(0.46, 0.5, 0.68)
const LAMP_COLOR: Color = Color(1.0, 0.85, 0.55)
const GLOW_COLOR: Color = Color(0.9, 0.93, 1.0)
const HAZARD_GLOW_COLOR: Color = Color(1.0, 0.5, 0.4)
const LAMP_SCALE: float = 2.4
const PLAYER_GLOW_SCALE: float = 0.9
const HEAD_GLOW_SCALE: float = 0.55
const PICKUP_GLOW_SCALE: float = 0.7
const HAZARD_GLOW_SCALE: float = 0.8
const LAMP_ENERGY: float = 1.0
const GLOW_ENERGY: float = 0.8
const LIGHT_TEXTURE_SIZE: int = 256
const GLOW_NAME: String = "NightGlow"

var modulate_node: CanvasModulate
var lamps: Array[PointLight2D] = []
## Weapon-head glows keyed by player instance id, owned by this node.
var head_glows: Dictionary = {}
## Glows hung on players and pickups, which can outlive the stage: taken off
## when it goes, or the next (day) stage's players would still glow.
var _attached_glows: Array[Node] = []
var _texture: GradientTexture2D
var _time: float = 0.0
## The players and pickups this node lights, found once when it enters the
## tree and then as each one is added, never by a per-frame group scan:
## instance ids, whether each is a player, and the glow hung on each (re-hung
## if another night stage's exit took it off).
var _lit_ids: PackedInt64Array = []
var _lit_is_player: Array[bool] = []
var _lit_glows: Array = []

## Builds the lights. `lamp_points` are world positions for stage lamps.
func setup(lamp_points: Array[Vector2]) -> void:
	name = "NightLighting"
	modulate_node = CanvasModulate.new()
	modulate_node.name = "NightModulate"
	modulate_node.color = NIGHT_TINT
	add_child(modulate_node)
	for point in lamp_points:
		var lamp: PointLight2D = _make_light(LAMP_COLOR, LAMP_SCALE, LAMP_ENERGY)
		lamp.name = "Lamp%d" % lamps.size()
		add_child(lamp)
		lamp.global_position = point
		lamps.append(lamp)
	get_parent().tree_exiting.connect(_on_stage_exiting)
	_glow_hazards(get_parent())

## Switches the modulate off while the tree still holds it: freeing a visible
## CanvasModulate with its stage makes Godot log an engine error.
func _on_stage_exiting() -> void:
	if is_instance_valid(modulate_node):
		modulate_node.get_parent().remove_child(modulate_node)
		modulate_node.queue_free()
	var stage: Node = get_parent()
	for glow: Node in _attached_glows:
		if not is_instance_valid(glow) or glow.is_queued_for_deletion():
			continue
		var holder: Node = glow.get_parent()
		if holder == null or (stage != null and (holder == stage or stage.is_ancestor_of(holder))):
			continue # goes with the stage
		holder.remove_child(glow)
		glow.queue_free()
	_attached_glows.clear()

func _ready() -> void:
	set_process(true)

## Lights every player and pickup already in the tree, then each one added.
func _enter_tree() -> void:
	var tree: SceneTree = get_tree()
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	for player: Node in tree.get_nodes_in_group("players"):
		_consider(player)
	for pickup: Node in tree.get_nodes_in_group("pickups"):
		_consider(pickup)

func _exit_tree() -> void:
	var tree: SceneTree = get_tree()
	if tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)

## Players and pickups join their group in their own `_ready`, after the tree
## reports them added: a node not yet ready is looked at once it is.
func _on_node_added(node: Node) -> void:
	if not node is Node2D or node is PointLight2D:
		return
	if node.is_node_ready():
		_consider(node)
	else:
		node.ready.connect(_consider.bind(node), CONNECT_ONE_SHOT)

func _consider(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	var is_player: bool = node.is_in_group("players")
	if not is_player and not node.is_in_group("pickups"):
		return
	if is_player and not node is Node2D:
		return
	var id: int = node.get_instance_id()
	if _lit_ids.has(id):
		return
	_lit_ids.append(id)
	_lit_is_player.append(is_player)
	_lit_glows.append(_hang_glow(node, is_player))
	if is_player:
		var head: PointLight2D = _make_light(GLOW_COLOR, HEAD_GLOW_SCALE, GLOW_ENERGY)
		head.name = "HeadGlow%d" % id
		add_child(head)
		head_glows[id] = head
		_place_head_glow(node as Node2D, head)

## The glow `holder` carries: its own if it has one already, else a new one.
func _hang_glow(holder: Node, is_player: bool) -> Node:
	var existing: Node = holder.get_node_or_null(GLOW_NAME)
	if existing != null and not existing.is_queued_for_deletion():
		return existing
	var glow: PointLight2D = _make_light(GLOW_COLOR, PLAYER_GLOW_SCALE if is_player else PICKUP_GLOW_SCALE, GLOW_ENERGY)
	glow.name = GLOW_NAME
	holder.add_child(glow)
	_attached_glows.append(glow)
	return glow

func _process(delta: float) -> void:
	_time += delta
	var steady: bool = PartKitScript.reduce_flash(self)
	for i in lamps.size():
		var flicker: float = 0.0 if steady else 0.08 * sin(_time * 5.0 + i * 1.7)
		lamps[i].energy = LAMP_ENERGY + flicker
	var k: int = _lit_ids.size() - 1
	while k >= 0:
		var id: int = _lit_ids[k]
		var holder: Node = instance_from_id(id) as Node
		if holder == null:
			# Freed: drop it, and its head glow, which is this node's own.
			if head_glows.has(id):
				(head_glows[id] as Node).queue_free()
				head_glows.erase(id)
			_lit_ids.remove_at(k)
			_lit_is_player.remove_at(k)
			_lit_glows.remove_at(k)
		elif holder.is_inside_tree() and holder.is_in_group("players" if _lit_is_player[k] else "pickups"):
			var glow: Variant = _lit_glows[k]
			if not is_instance_valid(glow) or (glow as Node).get_parent() != holder:
				_lit_glows[k] = _hang_glow(holder, _lit_is_player[k])
			if _lit_is_player[k]:
				_place_head_glow(holder as Node2D, head_glows[id])
		k -= 1

## The head glow is not the player's child: it follows the weapon head, and
## hides with the player.
func _place_head_glow(player: Node2D, head: PointLight2D) -> void:
	var lit: bool = player.visible and player.get("alive") != false
	head.visible = lit
	if not lit:
		return
	if player.has_method("weapon_head_position"):
		head.global_position = player.weapon_head_position()
	else:
		head.global_position = player.global_position

func _glow_hazards(node: Node) -> void:
	for child in node.get_children():
		if child.has_method("set_hazard_color") and child is Node2D:
			var glow: PointLight2D = _make_light(HAZARD_GLOW_COLOR, HAZARD_GLOW_SCALE, GLOW_ENERGY)
			glow.name = GLOW_NAME
			child.add_child(glow)
		_glow_hazards(child)

func _make_light(color: Color, light_scale: float, energy: float) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = _light_texture()
	light.color = color
	light.energy = energy
	light.texture_scale = light_scale
	light.shadow_enabled = false
	return light

func _light_texture() -> GradientTexture2D:
	if _texture == null:
		_texture = GradientTexture2D.new()
		_texture.width = LIGHT_TEXTURE_SIZE
		_texture.height = LIGHT_TEXTURE_SIZE
		_texture.fill = GradientTexture2D.FILL_RADIAL
		_texture.fill_from = Vector2(0.5, 0.5)
		_texture.fill_to = Vector2(1.0, 0.5)
		var gradient := Gradient.new()
		gradient.set_color(0, Color.WHITE)
		gradient.set_color(1, Color(1, 1, 1, 0))
		_texture.gradient = gradient
	return _texture
