extends Node2D

## A rotating arena layout (ADR-0008). `RoundManager` instances one of these
## per round and reads spawn points off it rather than owning its own export.
## Preloaded by path everywhere it's used -- see CLAUDE.md's `class_name` rule.

const StageBackgroundType := preload("res://scripts/StageBackground.gd")
const PaletteScript := preload("res://scripts/Palette.gd")

## This stage's index in the rotation, set by RoundManager before the stage
## enters the tree; it picks the palette mood (#255). -1 means Daylight.
var stage_index: int = -1
## The palette mood applied in `_ready()`.
var mood: Dictionary = {}

## The stage's backdrop (issue #117): a gradient sky and parallax
## silhouettes, built by `StageBackground.gd` when the stage enters the tree
## and drawn behind everything. Kept dark and muted -- below the grey of stage
## geometry -- so players, heads and platforms stay the brightest things on
## screen. The defaults are a dim dusk; each stage sets its own.
@export_group("Background")
@export var background_sky_top: Color = Color(0.1, 0.12, 0.2)
@export var background_sky_bottom: Color = Color(0.2, 0.22, 0.28)
## What the nearest silhouette layer is tinted towards; further layers sit
## closer to the sky.
@export var background_silhouette: Color = Color(0.12, 0.13, 0.18)
## Layer kinds, far to near: "clouds", "mountains", "hills", "rocks", "city".
@export var background_layers: PackedStringArray = ["clouds", "mountains", "hills"]
## Seeds the silhouettes' shapes; 0 derives one from the stage's name, so
## each stage's skyline is its own but the same every round.
@export var background_seed: int = 0
@export_group("")

const BACKGROUND_NODE_NAME: String = "Background"

## What the Main camera shows of a normal stage (issue #144): the project's
## 1600x900 viewport at zoom 1, centred on the stage's origin.
const DEFAULT_VIEW_SIZE: Vector2 = Vector2(1600.0, 900.0)

## How much of the world the camera must show for this stage, centred on its
## origin (issue #144). The default is the normal view; a large stage built
## for five to eight players declares a bigger one, and RoundManager zooms the
## Main camera out until all of it fits. Keep it 16:9 like the screen, or the
## camera shows extra on the other axis (see `get_view_rect()`). A stage whose
## view is bigger than the default on either axis is a large stage, which the
## rotation only offers to rounds of `RoundManager.large_stage_min_players`
## or more.
@export var view_size: Vector2 = DEFAULT_VIEW_SIZE

func _ready() -> void:
	if get_node_or_null(BACKGROUND_NODE_NAME) != null:
		return
	var background: Node2D = StageBackgroundType.new()
	background.name = BACKGROUND_NODE_NAME
	var seed_value: int = background_seed if background_seed != 0 else hash(String(name))
	mood = PaletteScript.mood_for_stage(stage_index)
	background.configure(mood["sky_top"], mood["sky_bottom"], background_silhouette,
		background_layers, seed_value, get_view_rect().size)
	background.far_hill = mood["far"]
	background.mid_hill = mood["mid"]
	background.use_hill_colours = true
	background.configure_dressing(mood, stage_index)
	add_child(background)
	# First in tree order as well as lowest in z, belt and braces.
	move_child(background, 0)
	_tint_bodies(self)
	var kill_zone: Node = get_node_or_null("KillZone")
	if kill_zone != null and kill_zone.has_method("set_kill_color"):
		kill_zone.set_kill_color(mood["kill"])

## Recolours every static platform or stage-body visual: the Polygon2Ds under
## a plain StaticBody2D (no script, so breakables, ledges and pads keep their
## own colours) take the mood's platform colour.
func _tint_bodies(node: Node) -> void:
	for child in node.get_children():
		if child.has_method("set_platform_color"):
			child.set_platform_color(mood["platform"])
		if child.has_method("set_hazard_color"):
			child.set_hazard_color(mood["kill"])
		if child is Polygon2D and node.get_class() == "StaticBody2D" and node.get_script() == null:
			(child as Polygon2D).color = mood["platform"]
		_tint_bodies(child)

## The camera zoom that fits `view` inside the default view: 1 for a normal
## stage, under 1 for a large one. Uniform, so nothing is stretched.
static func zoom_for_view(view: Vector2) -> float:
	if view.x <= 0.0 or view.y <= 0.0:
		return 1.0
	return minf(DEFAULT_VIEW_SIZE.x / view.x, DEFAULT_VIEW_SIZE.y / view.y)

## What the Main camera actually shows of this stage, in world coordinates:
## `view_size` centred on the stage's origin, widened on one axis to the
## screen's 16:9 when the declared size is another shape. The spawn, terrain
## and background checks all measure against this.
func get_view_rect() -> Rect2:
	var shown: Vector2 = DEFAULT_VIEW_SIZE / zoom_for_view(view_size)
	var origin: Vector2 = global_position if is_inside_tree() else position
	return Rect2(origin - shown * 0.5, shown)

## Whether this stage is bigger than the normal view (issue #144).
func is_large() -> bool:
	return is_large_view(view_size)

static func is_large_view(view: Vector2) -> bool:
	return view.x > DEFAULT_VIEW_SIZE.x or view.y > DEFAULT_VIEW_SIZE.y

## A stage scene's `view_size`, read off its packed root without instancing
## it, so the rotation can skip a large stage it is not going to play. A
## scene that never sets it (every normal stage) has the default.
static func view_size_of(scene: PackedScene) -> Vector2:
	if scene == null:
		return DEFAULT_VIEW_SIZE
	var state: SceneState = scene.get_state()
	if state.get_node_count() == 0:
		return DEFAULT_VIEW_SIZE
	for p in state.get_node_property_count(0):
		if state.get_node_property_name(0, p) == &"view_size":
			return state.get_node_property_value(0, p)
	return DEFAULT_VIEW_SIZE

## The backdrop built in `_ready()`, or null outside the tree.
func get_background() -> Node2D:
	return get_node_or_null(BACKGROUND_NODE_NAME) as Node2D

## Spawn points declared as `Marker2D` children named `Spawn0`, `Spawn1`, ...
## Sorted by name, regardless of the order children were added in the editor
## -- naturally, so `Spawn10` lands after `Spawn9` rather than after `Spawn1`.
## RoundManager hands them out in roster order (#163): the round's first
## player gets `Spawn0`, its second `Spawn1`, whatever their slot numbers, so
## a stage that pairs its spawns left/right splits any two players.
##
## World positions, so a stage root placed anywhere other than the origin
## still spawns players on its own geometry. `RoundManager` reads these after
## adding the stage to the tree; outside the tree each marker's local
## position is the best answer there is.
func get_spawn_points() -> Array[Vector2]:
	return _marker_points("Spawn")

## Where pickups may appear (issue #14, ADR-0009): `Marker2D` children named
## `PickupSpawn0`, `PickupSpawn1`, ..., collected the same way as player
## spawns. A stage may declare none; `RoundManager` then falls back to a point
## above the stage's centre, so a stage author is never forced to add them.
func get_pickup_spawn_points() -> Array[Vector2]:
	return _marker_points("PickupSpawn")

func _marker_points(prefix: String) -> Array[Vector2]:
	var markers: Array[Marker2D] = []
	for child in get_children():
		if child is Marker2D and child.name.begins_with(prefix):
			markers.append(child)
	markers.sort_custom(func(a: Marker2D, b: Marker2D) -> bool:
		return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)

	var points: Array[Vector2] = []
	for marker in markers:
		points.append(marker.global_position if marker.is_inside_tree() else marker.position)
	return points
