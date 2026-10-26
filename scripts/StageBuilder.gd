extends RefCounted

## Runtime stage builder (#1046, ADR-0026, ADR-0008): turns a validated stage
## definition (`scripts/StageDef.gd`) into a stage node that behaves like a
## built-in stage. Preload by path; there is no class_name.
##
## The node is a `Node2D` running `scripts/Stage.gd`, so everything that reads a
## built-in stage reads this one: `Marker2D` children `Spawn0..` for
## `get_spawn_points()`, a `KillZone` (an instance of `scenes/parts/KillFloor.tscn`,
## the node name RoundManager rises), a `Platform.tscn` instance per Platform
## part (so the mood tint reaches it through `set_platform_color()`), and the
## stage's own backdrop and preview framing (`get_view_rect()`), built by
## Stage.gd when the node enters the tree. Nothing here runs code from the
## definition: parts come from a whitelist of scenes already in the project.
##
## Parts are named `Part0`, `Part1`, ... in definition order (a definition
## carries no part names). Not wired into the rotation or the host toggles yet;
## that waits for the editor (#1047).

const StageDefScript := preload("res://scripts/StageDef.gd")
const StageScript := preload("res://scripts/Stage.gd")
const PlatformScene := preload("res://scenes/parts/Platform.tscn")
const KillFloorScene := preload("res://scenes/parts/KillFloor.tscn")

## The rotation weight a mode tag gives a stage in that mode, and in any other,
## the same as the built-in mode stages (Bastion, Mesa, Pitch).
const TAGGED_MODE_WEIGHT: float = 4.0
const OTHER_MODE_WEIGHT: float = 0.3

## Builds a stage from JSON text. {"ok", "reason", "stage"}: the stage is null
## when the definition is rejected, and "reason" says why.
static func build_text(text: String) -> Dictionary:
	return _wrap(StageDefScript.validate_text(text))

## Builds a stage from a parsed definition (validated here; an invalid one is
## never built). Same result shape as `build_text()`.
static func build(data: Variant) -> Dictionary:
	return _wrap(StageDefScript.validate(data))

static func _wrap(checked: Dictionary) -> Dictionary:
	if not bool(checked["ok"]):
		return {"ok": false, "reason": checked["reason"], "stage": null}
	return {"ok": true, "reason": "", "stage": _build_valid(checked["def"])}

static func _build_valid(def: Dictionary) -> Node2D:
	var stage := Node2D.new()
	stage.set_script(StageScript)
	var node_name: String = String(def["name"]).validate_node_name()
	stage.name = node_name if node_name != "" else "CustomStage"
	stage.set_meta("custom_stage_name", def["name"])
	var modes: Array = def["modes"]
	if not modes.is_empty():
		var weights: Dictionary = {"_other": OTHER_MODE_WEIGHT}
		for mode: String in modes:
			weights[mode] = TAGGED_MODE_WEIGHT
		stage.mode_weights = weights
	var parts: Array = def["parts"]
	for i in parts.size():
		var part: Dictionary = parts[i]
		var node: Node2D
		if part["type"] == StageDefScript.KILL_FLOOR:
			node = KillFloorScene.instantiate() as Node2D
			node.name = "KillZone"
		else:
			node = PlatformScene.instantiate() as Node2D
			node.name = "Part%d" % i
			node.size = part["size"]
			node.one_way = bool((part["params"] as Dictionary).get("one_way", false))
		node.position = part["pos"]
		stage.add_child(node)
	var spawns: Array = def["spawns"]
	for i in spawns.size():
		var marker := Marker2D.new()
		marker.name = "Spawn%d" % i
		marker.position = spawns[i]
		stage.add_child(marker)
	return stage
