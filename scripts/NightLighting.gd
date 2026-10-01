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
var _texture: GradientTexture2D
var _time: float = 0.0

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

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	_time += delta
	var steady: bool = _reduce_flash()
	for i in lamps.size():
		var flicker: float = 0.0 if steady else 0.08 * sin(_time * 5.0 + i * 1.7)
		lamps[i].energy = LAMP_ENERGY + flicker
	for player in get_tree().get_nodes_in_group("players"):
		_light_player(player as Node2D)
	for pickup in get_tree().get_nodes_in_group("pickups"):
		if pickup.get_node_or_null(GLOW_NAME) == null:
			var glow: PointLight2D = _make_light(GLOW_COLOR, PICKUP_GLOW_SCALE, GLOW_ENERGY)
			glow.name = GLOW_NAME
			pickup.add_child(glow)
	for id in head_glows.keys():
		if not is_instance_valid(instance_from_id(id)):
			(head_glows[id] as Node).queue_free()
			head_glows.erase(id)

func _light_player(player: Node2D) -> void:
	if player == null:
		return
	if player.get_node_or_null(GLOW_NAME) == null:
		var glow: PointLight2D = _make_light(GLOW_COLOR, PLAYER_GLOW_SCALE, GLOW_ENERGY)
		glow.name = GLOW_NAME
		player.add_child(glow)
	var id: int = player.get_instance_id()
	if not head_glows.has(id):
		var head: PointLight2D = _make_light(GLOW_COLOR, HEAD_GLOW_SCALE, GLOW_ENERGY)
		head.name = "HeadGlow%d" % id
		add_child(head)
		head_glows[id] = head
	if player.has_method("weapon_head_position"):
		(head_glows[id] as PointLight2D).global_position = player.weapon_head_position()
	else:
		(head_glows[id] as PointLight2D).global_position = player.global_position

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

func _reduce_flash() -> bool:
	var sfx: Node = get_node_or_null("/root/Sfx")
	return sfx != null and bool(sfx.get("reduce_flash"))
