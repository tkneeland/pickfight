extends SceneTree
## Windowed stage screenshots (issue #137): each stage under the camera
## Main.tscn gives it -- origin and 1600x900 for a normal stage, zoomed out
## to fit the stage's view_size for a large one (issue #144) -- a real player body
## dropped on each spawn point (up to 8) and left 90 ticks to settle, spawn
## indices labelled and pickup spots drawn as yellow rings. Not part of the
## suite -- headless Godot does not render, so run it windowed, by hand:
##
##   godot --path . -s tools/capture_stage_screenshots.gd -- --out=/abs/dir [--stages=Flatlands,Bowl]
##
## Writes <out>/<Stage>.png per stage and quits. A body that died or slid off
## its spawn in those 90 ticks shows up as missing or out of place.
const PlayerScene: PackedScene = preload("res://scenes/Player.tscn")
const COLOURS: Array[Color] = [Color(0.9,0.2,0.2), Color(0.2,0.45,1), Color(0.2,0.85,0.3), Color(1,0.85,0.1), Color(0.8,0.3,0.9), Color(1,0.55,0.1), Color(0.2,0.9,0.9), Color(1,1,1)]
var _out: String = ""
## Default: the rotation, in STAGE_PATHS order.
var _stages: PackedStringArray = ["Flatlands","Pillars","Ferry","Highrise","Erosion","Islands","Furnace","Gauntlet","Cascade","Slant","Bowl","Springboard","Gale","Carousel","Rockfall","Sinkhole","Bulwark","Pistons","Overpass","Ziggurat"]
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		elif arg.begins_with("--stages="): _stages = arg.trim_prefix("--stages=").split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	_run()
func _run() -> void:
	var cam := Camera2D.new()
	get_root().add_child(cam)
	await process_frame
	cam.make_current()
	for n in _stages:
		var holder := Node2D.new()
		get_root().add_child(holder)
		var inst: Node2D = (load("res://scenes/stages/%s.tscn" % n) as PackedScene).instantiate()
		holder.add_child(inst)
		var view: Rect2 = inst.get_view_rect()
		cam.zoom = Vector2.ONE * inst.zoom_for_view(view.size)
		cam.global_position = view.get_center()
		cam.reset_smoothing()
		var spawns: Array[Vector2] = inst.get_spawn_points()
		for i in mini(spawns.size(), 8):
			var p: RigidBody2D = PlayerScene.instantiate()
			p.identity_color = COLOURS[i]
			holder.add_child(p)
			p.global_position = spawns[i]
			var l := Label.new()
			l.text = "S%d" % i
			l.position = spawns[i] + Vector2(-10, -70)
			l.z_index = 100
			holder.add_child(l)
		for q: Vector2 in inst.get_pickup_spawn_points():
			var ring := Line2D.new()
			var pts := PackedVector2Array()
			for k in 17: pts.append(q + Vector2.RIGHT.rotated(k * TAU / 16) * 14)
			ring.points = pts
			ring.width = 3
			ring.default_color = Color(1, 0.9, 0.2)
			ring.z_index = 100
			holder.add_child(ring)
		var title := Label.new()
		title.text = "%s  (%d spawns, %d pickup spots)" % [n, spawns.size(), inst.get_pickup_spawn_points().size()]
		title.scale = Vector2.ONE / cam.zoom
		title.position = view.position + Vector2(20, 10) / cam.zoom
		title.z_index = 100
		title.add_theme_font_size_override("font_size", 28)
		holder.add_child(title)
		for _i in 90: await physics_frame
		for _i in 3: await process_frame
		get_root().get_texture().get_image().save_png("%s/%s.png" % [_out, n])
		holder.queue_free()
		for _i in 5: await physics_frame
	quit(0)
