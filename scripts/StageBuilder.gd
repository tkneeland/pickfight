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
##
## #1049: every built stage carries its definition, in its JSON shape
## (`StageDef.to_json_data()`), as the `DEF_META` metadata, which `pack()` keeps.
## The host sends it to each Online joiner, who rebuilds the same stage with this
## same builder after checking it with the same limits.

const StageDefScript := preload("res://scripts/StageDef.gd")
const StageScript := preload("res://scripts/Stage.gd")
const PlatformScene := preload("res://scenes/parts/Platform.tscn")
const KillFloorScene := preload("res://scenes/parts/KillFloor.tscn")

## The rotation weight a mode tag gives a stage in that mode, and in any other,
## the same as the built-in mode stages (Bastion, Mesa, Pitch).
const TAGGED_MODE_WEIGHT: float = 4.0
const OTHER_MODE_WEIGHT: float = 0.3
## The metadata key a built stage keeps its definition under (#1049).
const DEF_META: StringName = &"stage_def"

## Builds a stage from JSON text. {"ok", "reason", "stage"}: the stage is null
## when the definition is rejected, and "reason" says why.
static func build_text(text: String) -> Dictionary:
	return _wrap(StageDefScript.validate_text(text))

## Builds a stage from a parsed definition (validated here; an invalid one is
## never built). Same result shape as `build_text()`.
static func build(data: Variant) -> Dictionary:
	return _wrap(StageDefScript.validate(data))

## The definition a stage was built from, in its JSON shape, or {} for a
## built-in stage (#1049).
static func def_of(stage: Node) -> Dictionary:
	if stage == null or not stage.has_meta(DEF_META):
		return {}
	var def: Variant = stage.get_meta(DEF_META)
	return def if def is Dictionary else {}

## A built stage (not yet in the tree) as a PackedScene the rotation can hold
## like a built-in one; its definition rides along as metadata (#1049). Null
## (and an error) if packing fails.
static func pack(stage: Node2D) -> PackedScene:
	for child in stage.get_children():
		child.owner = stage
	var scene := PackedScene.new()
	var err: Error = scene.pack(stage)
	if err != OK:
		push_error("StageBuilder: packing '%s' failed (%s)" % [stage.name, error_string(err)])
		return null
	return scene

## Builds from a definition `StageDef.validate()` already accepted (its "def",
## vectors and all), without checking it a second time (#1049: the Online
## client validates once on receipt).
static func build_valid(def: Dictionary) -> Node2D:
	return _build_valid(def)

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
	stage.set_meta(DEF_META, StageDefScript.to_json_data(def))
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
