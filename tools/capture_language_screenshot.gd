extends SceneTree
## One windowed screenshot of the host screen in a chosen language (issue #688),
## to check that CJK and Cyrillic glyphs render rather than tofu boxes. Not part
## of the scenario suite; run it windowed, by hand, one window at a time:
##
##   perl -e 'alarm 120; exec @ARGV' godot --path . -s tools/capture_language_screenshot.gd -- --lang=ja --out=/abs/ja.png
##
## `--lang` is a `Languages.OPTIONS` code. Shows the three-seat Couch lobby with
## the Settings panel open over it, waits 60 frames, saves the window to `--out`.
const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const SIZE := Vector2i(1600, 900)

var _lang: String = "en"
var _out: String = ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--lang="):
			_lang = arg.trim_prefix("--lang=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	if _out.is_empty():
		printerr("capture_language_screenshot: --out=<file.png> is required")
		quit(2)
		return
	_run()

func _frames(n: int) -> void:
	for _i in n:
		await process_frame

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(SIZE)
	get_root().size = SIZE
	var settings: CanvasLayer = get_root().get_node("Sfx").build_settings_ui()
	if not settings.host.set_language(_lang):
		printerr("capture_language_screenshot: '%s' is not a language on offer" % _lang)
		quit(2)
		return
	var main: Node = MAIN_SCENE.instantiate()
	var server: Node = main.get_node("ControllerServer")
	server.http_port = 0
	server.ws_port = 0
	get_root().add_child(main)
	await _frames(16)
	settings.host.telemetry_notice_seen = true
	settings.refresh()
	var screen: CanvasLayer = main.get_node("RoundManager").get_node("LobbyLayer")
	screen.show_title(true)
	screen.press_title("local")
	server.apply_host_command("bots", 3)
	await _frames(8)
	settings.toggle_panel()
	await _frames(60)
	var image: Image = get_root().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var saved: Error = image.save_png(_out)
	server.go_offline()
	print("capture_language_screenshot: %s -> %s (%s)" % [_lang, _out, error_string(saved)])
	quit(0 if saved == OK else 1)
