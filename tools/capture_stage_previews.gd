extends SceneTree
## Bakes the stage preview images (#647): every scene in scenes/stages/ under
## the camera Main.tscn gives it -- origin and 1600x900 for a normal stage,
## zoomed out to the stage's view_size for a large one -- with no players,
## spawn labels or pickup rings, downscaled to 480x270. Headless Godot can't
## render, so run it windowed, by hand (one window; it quits when done):
##
##   godot --path . -s tools/capture_stage_previews.gd -- [--out=res-or-abs/dir] [--stages=Flatlands,Bowl]
##
## Run at most 5 stages per process (--stages=): after about ten in one run the
## viewport stops updating and later PNGs repeat the last good frame.
## Writes <out>/<Stage>.png per stage (default art/stage_previews/). Afterwards
## run `godot --headless --path . --import` so the PNGs get .import files.
const PREVIEW_SIZE: Vector2i = Vector2i(480, 270)
var _out: String = ProjectSettings.globalize_path("res://art/stage_previews")
var _stages: PackedStringArray = []
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		elif arg.begins_with("--stages="): _stages = arg.trim_prefix("--stages=").split(",")
	if _stages.is_empty():
		for f in DirAccess.get_files_at("res://scenes/stages"):
			if f.ends_with(".tscn"): _stages.append(f.get_basename())
		_stages.sort()
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
		for _i in 10: await physics_frame
		for _i in 3: await process_frame
		var img: Image = get_root().get_texture().get_image()
		img.resize(PREVIEW_SIZE.x, PREVIEW_SIZE.y, Image.INTERPOLATE_LANCZOS)
		img.save_png("%s/%s.png" % [_out, n])
		holder.queue_free()
		for _i in 5: await physics_frame
	quit(0)
