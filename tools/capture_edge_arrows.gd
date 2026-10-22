extends SceneTree

## Windowed evidence capture for #779 (edge arrows). Run by hand, not part of the suite:
##
##   godot --resolution 1920x1080 --path . -s tools/capture_edge_arrows.gd -- --out=issue-779/1920x1080
##
## A real arena with a camera, one fighter on the floor and one knocked above the view (Teams on,
## so the arrow carries its team letter); saves one PNG under res://test-results/ and quits.

const PlayerScene: PackedScene = preload("res://scenes/Player.tscn")
const ArenaScene: PackedScene = preload("res://scenes/Arena.tscn")
const IndicatorsScript := preload("res://scripts/OffscreenIndicators.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var out: String = "issue-779"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var arena: Node = ArenaScene.instantiate()
	root.add_child(arena)
	var camera := Camera2D.new()
	camera.position = Vector2(0.0, 100.0)
	root.add_child(camera)
	camera.make_current()
	var players: Array = []
	var colours: Array[Color] = [Color(0.15, 0.4, 1.0), Color(0.95, 0.35, 0.2)]
	for i in 2:
		var p: RigidBody2D = PlayerScene.instantiate() as RigidBody2D
		p.set("team", i)
		root.add_child(p)
		players.append(p)
	players[0].teleport_to(Vector2(-150.0, 100.0))
	players[1].teleport_to(Vector2(250.0, -1500.0))
	var layer: CanvasLayer = IndicatorsScript.new(players, func(slot: int) -> Color: return colours[slot])
	root.add_child(layer)
	layer.build()
	for i in 40:
		players[0].teleport_to(Vector2(-150.0, 100.0))
		players[1].teleport_to(Vector2(250.0, -1500.0))
		await process_frame
	var dir: String = "res://test-results/%s" % out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	root.get_texture().get_image().save_png("%s/edge-arrow.png" % dir)
	quit()
