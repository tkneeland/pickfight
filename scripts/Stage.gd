extends Node2D

## A rotating arena layout (ADR-0008). `RoundManager` instances one of these
## per round and reads spawn points off it rather than owning its own export.
## Preloaded by path everywhere it's used -- see CLAUDE.md's `class_name` rule.

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
	var markers: Array[Marker2D] = []
	for child in get_children():
		if child is Marker2D and child.name.begins_with("Spawn"):
			markers.append(child)
	markers.sort_custom(func(a: Marker2D, b: Marker2D) -> bool:
		return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)

	var points: Array[Vector2] = []
	for marker in markers:
		points.append(marker.global_position if marker.is_inside_tree() else marker.position)
	return points

func get_pickup_spawn_points() -> Array[Vector2]:
	var none: Array[Vector2] = []
	return none
