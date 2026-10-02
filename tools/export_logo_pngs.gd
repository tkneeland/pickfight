extends SceneTree
## Rasterises art/logo/*.svg into PNGs (issue #359), headless, no window:
##
##   godot --headless --path . -s tools/export_logo_pngs.gd
##
## Writes art/logo/logo_1024.png (1024 px wide) and one PNG per capsule SVG in
## art/logo/capsules/, each at the size in its file name. Source SVGs come
## from tools/gen_logo_art.py.
func _initialize() -> void:
	var fails: int = 0
	fails += _export("res://art/logo/logo.svg", "res://art/logo/logo_1024.png", 1024.0 / 1600.0)
	var dir: DirAccess = DirAccess.open("res://art/logo/capsules")
	for file: String in dir.get_files():
		if file.ends_with(".svg"):
			fails += _export("res://art/logo/capsules/" + file, "res://art/logo/capsules/" + file.trim_suffix(".svg") + ".png", 1.0)
	quit(fails)

func _export(svg_path: String, png_path: String, scale: float) -> int:
	var img := Image.new()
	var err: int = img.load_svg_from_string(FileAccess.get_file_as_string(svg_path), scale)
	if err != OK:
		printerr("could not rasterise %s: %d" % [svg_path, err])
		return 1
	img.save_png(png_path)
	print("%s %dx%d" % [png_path, img.get_width(), img.get_height()])
	return 0
