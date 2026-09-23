extends Node2D

## A rotating arena layout (ADR-0008). `RoundManager` instances one of these
## per round and reads spawn points off it rather than owning its own export.
## Preloaded by path everywhere it's used -- see CLAUDE.md's `class_name` rule.

## Spawn points declared as `Marker2D` children named `Spawn0`, `Spawn1`, ...
## Sorted by name so slot order matches player slot order regardless of the
## order children were added in the editor.
func get_spawn_points() -> Array[Vector2]:
	var markers: Array[Marker2D] = []
	for child in get_children():
		if child is Marker2D and child.name.begins_with("Spawn"):
			markers.append(child)
	markers.sort_custom(func(a: Marker2D, b: Marker2D) -> bool: return a.name < b.name)

	var points: Array[Vector2] = []
	for marker in markers:
		points.append(marker.position)
	return points
