extends SceneTree

## Windowed evidence capture for #360 (character polish). Headless Godot does
## not render, so the scenario runner cannot produce this; run by hand, not part
## of the suite:
##
##   godot --path . -s tools/capture_character_polish.gd
##
## Saves rest / hit-flash / take-off-stretch PNGs of one real player (frozen,
## zoomed) to res://test-results/character-polish/. Quits itself when done.

const PlayerScene: PackedScene = preload("res://scenes/Player.tscn")
const ArenaScene: PackedScene = preload("res://scenes/Arena.tscn")
const OUTPUT_DIR: String = "res://test-results/character-polish"
const POS: Vector2 = Vector2(0.0, 100.0)

func _initialize() -> void:
	_run()

func _run() -> void:
	var root: Window = get_root()
	var stage := Node2D.new()
	root.add_child(stage)
	stage.add_child(ArenaScene.instantiate())
	var camera := Camera2D.new()
	stage.add_child(camera)
	camera.zoom = Vector2(3.5, 3.5)
	camera.global_position = POS
	camera.make_current.call_deferred()
	var player: RigidBody2D = PlayerScene.instantiate() as RigidBody2D
	player.identity_color = Color(0.15, 0.4, 1.0, 1.0)
	stage.add_child(player)
	player.global_position = POS
	player.freeze = true
	player.bind_controller()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	for _f in 20:
		await process_frame
	var face: Node2D = player.face_node()
	await _shoot(root, "00-rest", null)
	await _shoot(root, "01-hit-flash", func() -> void: face.on_hit(10.0))
	await _shoot(root, "02-takeoff-stretch", func() -> void: face.start_squash(0.15, -1.0))
	quit(0)

## `poke` is re-applied each frame so the fading effect is at its peak when the
## frame is read back.
func _shoot(root: Window, label: String, poke: Variant) -> void:
	for _f in 3:
		if poke != null:
			(poke as Callable).call()
		await process_frame
	var path: String = "%s/%s.png" % [OUTPUT_DIR, label]
	var err: int = root.get_texture().get_image().save_png(path)
	print("CAPTURE: %s (%d)" % [path, err])
