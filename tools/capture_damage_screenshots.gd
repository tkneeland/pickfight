extends SceneTree

## Windowed evidence capture for AC-16 (damage display and identity).
##
## Headless Godot does not render, so the scenario runner -- which never
## opens a window -- cannot produce this. This script is the one non-headless
## tool in the project, run by hand, and it is not part of the automated
## verification suite:
##
##   godot --path . -s tools/capture_damage_screenshots.gd
##
## It builds a small stage (the real arena and one real player, frozen so it
## does not fall out of frame), drives Player.damage to roughly 0%, 50% and
## 95% of DEATH_DAMAGE, and saves one PNG per level to
## res://test-results/damage-display/ via
## `get_viewport().get_texture().get_image().save_png()`. Quits itself when
## done.

const PlayerScene: PackedScene = preload("res://scenes/Player.tscn")
const ArenaScene: PackedScene = preload("res://scenes/Arena.tscn")

const OUTPUT_DIR: String = "res://test-results/damage-display"
const IDENTITY_COLOR: Color = Color(0.15, 0.4, 1.0, 1.0)
const CAMERA_ZOOM: Vector2 = Vector2(3.5, 3.5)
const PLAYER_POSITION: Vector2 = Vector2(0.0, 100.0)
## Frames given to the renderer to actually draw the change before the
## capture -- one process frame is not reliably enough for the texture read
## to reflect it.
const SETTLE_FRAMES: int = 15

const SAMPLES: Array[Dictionary] = [
	{"damage": 0.0, "label": "00-zero-damage"},
	{"damage": 50.0, "label": "50-half-damage"},
	{"damage": 95.0, "label": "95-near-death"},
]

func _initialize() -> void:
	_run()

func _run() -> void:
	var root: Window = get_root()

	var stage := Node2D.new()
	root.add_child(stage)
	stage.add_child(ArenaScene.instantiate())

	var camera := Camera2D.new()
	stage.add_child(camera)
	camera.zoom = CAMERA_ZOOM
	camera.global_position = PLAYER_POSITION
	# A deferred call: made current immediately after add_child(), the
	# camera is not yet registered with the viewport and make_current()
	# errors (harmlessly -- the retry below still lands it as current).
	camera.make_current.call_deferred()

	var player: RigidBody2D = PlayerScene.instantiate() as RigidBody2D
	player.identity_color = IDENTITY_COLOR
	stage.add_child(player)
	player.global_position = PLAYER_POSITION
	# Frozen so the capture is not fighting gravity for a place in frame --
	# this script is about the body's fill and outline, not physics.
	player.freeze = true
	player.bind_controller()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	for _f in SETTLE_FRAMES:
		await process_frame

	for sample: Dictionary in SAMPLES:
		player.damage = sample["damage"]
		for _f in SETTLE_FRAMES:
			await process_frame
		var image: Image = root.get_texture().get_image()
		var path: String = "%s/%s.png" % [OUTPUT_DIR, sample["label"]]
		var err: int = image.save_png(path)
		if err != OK:
			printerr("CAPTURE: failed to save %s (error %d)" % [path, err])
		else:
			print("CAPTURE: saved %s" % path)

	quit(0)
