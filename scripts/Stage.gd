extends Node2D

## A rotating arena layout (ADR-0008). `RoundManager` instances one of these
## per round and reads spawn points off it rather than owning its own export.
## Preloaded by path everywhere it's used -- see CLAUDE.md's `class_name` rule.

const StageBackgroundType := preload("res://scripts/StageBackground.gd")

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

func _ready() -> void:
	if get_node_or_null(BACKGROUND_NODE_NAME) != null:
		return
	var background: Node2D = StageBackgroundType.new()
	background.name = BACKGROUND_NODE_NAME
	var seed_value: int = background_seed if background_seed != 0 else hash(String(name))
	background.configure(background_sky_top, background_sky_bottom, background_silhouette,
		background_layers, seed_value)
	add_child(background)
	# First in tree order as well as lowest in z, belt and braces.
	move_child(background, 0)

## The backdrop built in `_ready()`, or null outside the tree.
func get_background() -> Node2D:
	return get_node_or_null(BACKGROUND_NODE_NAME) as Node2D

## Spawn points declared as `Marker2D` children named `Spawn0`, `Spawn1`, ...
## Sorted by name so slot order matches player slot order regardless of the
## order children were added in the editor -- naturally, so `Spawn10` lands
## after `Spawn9` rather than after `Spawn1`.
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
