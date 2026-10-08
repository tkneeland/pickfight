extends SceneTree
## UI screenshots for visual review (issue #565): renders each host-screen state
## to a PNG so an agent or reviewer can check the look against
## `docs/design/ui-overhaul/`. Not part of the scenario suite or CI -- headless
## Godot does not render, so run it windowed, by hand:
##
##   godot --path . -s tools/ui_screenshots.gd -- --out=/abs/dir [--size=1600x900|all]
##
## `--size` is WxH, or `all` for 1600x900, 1920x1080 and 1280x800 (the default
## is 1600x900). Writes `<out>/<WxH>/<state>.png` per state and exits 0 once
## every PNG is saved and non-blank; exits 1 and names the state otherwise.
##
## States: title; lobby in Couch, Online and Solo with 0, 3 and 8 seats (Couch
## with 3 has a gamepad seat, which carries the pad picker); how_to_play,
## your_look and stages_rules (the lobby with its How to play, Your look and Stages & Rules popups open); settings; esc_menu (settings open over a live Solo match); the
## PC join screen; the in-match HUD with 8 players; victory with 8 players.
## Online has no empty room (the host PC always holds a seat), so its "0" is
## the host alone. A 0/3/8 seat count is the bots the host's counter seats,
## which Solo and Online cap at the room's 8 seats.
##
## Like the scenario runner, a `-s` run never reads or writes the owner's
## settings (`user://audio.cfg`, #195): Sfx, Music and HostSettings see a
## script main loop and use a temp file with saving off. Online uses an
## in-process relay, never the real one. The screens are driven through
## their public methods (`press_title`, `show_panel`, `apply_host_command`),
## not their internals.
const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const CLIENT_SCENE: PackedScene = preload("res://scenes/RemoteClient.tscn")
const RelayScript := preload("res://relay/Relay.gd")
const PadMenuScript := preload("res://scripts/PadMenu.gd")
const SIZES: Array[Vector2i] = [Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1280, 800)]
const RELAY_PORT: int = 39601
const SETTLE_FRAMES: int = 8
const MATCH_TIMEOUT_MSEC: int = 40000

var _out: String = ""
var _sizes: Array[Vector2i] = [SIZES[0]]
var _failures: Array[String] = []
var _saved: int = 0
var _dir: String = ""
var _relay: Node = null

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg == "--size=all":
			_sizes = SIZES.duplicate()
		elif arg.begins_with("--size="):
			var parts: PackedStringArray = arg.trim_prefix("--size=").split("x")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
				_fail_args("bad --size '%s' (want WxH or all)" % arg)
				return
			_sizes = [Vector2i(int(parts[0]), int(parts[1]))]
		else:
			_fail_args("unknown argument '%s'" % arg)
			return
	if _out.is_empty():
		_fail_args("--out=<dir> is required")
		return
	_run()

func _fail_args(message: String) -> void:
	printerr("ui_screenshots: " + message)
	quit(2)

func _run() -> void:
	_relay = RelayScript.new()
	get_root().add_child(_relay)
	if _relay.start(RELAY_PORT) != OK:
		printerr("ui_screenshots: relay could not listen on %d" % RELAY_PORT)
		quit(1)
		return
	var old_relay_url: Variant = ProjectSettings.get_setting("pickfight/relay_url")
	ProjectSettings.set_setting("pickfight/relay_url", "ws://127.0.0.1:%d" % RELAY_PORT)
	for size: Vector2i in _sizes:
		_dir = "%s/%dx%d" % [_out, size.x, size.y]
		DirAccess.make_dir_recursive_absolute(_dir)
		_set_window(size)
		await _frames(SETTLE_FRAMES)
		await _title_and_couch()
		await _online()
		await _solo_and_match()
		await _join_screen()
	ProjectSettings.set_setting("pickfight/relay_url", old_relay_url)
	_relay.stop()
	print("ui_screenshots: %d PNGs under %s, %d problems" % [_saved, _out, _failures.size()])
	for message: String in _failures:
		printerr("  " + message)
	quit(1 if not _failures.is_empty() else 0)

# --- Window and capture ---------------------------------------------------------

## The project stretches 1600x900 canvas items to the window, so a window of
## `size` shows the screen at that size.
func _set_window(size: Vector2i) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	get_root().size = size

func _frames(n: int) -> void:
	for _i in n:
		await process_frame

## Saves the window as `<state>.png` (or the `crop` of it) and checks it is not
## a flat colour.
func _shot(state: String, crop: Rect2 = Rect2()) -> void:
	await _frames(SETTLE_FRAMES)
	var image: Image = get_root().get_texture().get_image()
	var want: Vector2i = _sizes_dir_size()
	if image.get_size() != want:
		image.resize(want.x, want.y)
	if crop.has_area():
		var scale: float = float(want.x) / 1600.0 # the canvas is 1600 wide, stretched to the window
		var pad := 12.0
		var region := Rect2(crop.position * scale, crop.size * scale).grow(pad * scale)
		region = region.intersection(Rect2(Vector2.ZERO, Vector2(want)))
		image = image.get_region(Rect2i(region))
	if not _has_content(image):
		_failures.append("%s/%s is blank" % [_dir, state])
	if image.save_png("%s/%s.png" % [_dir, state]) != OK:
		_failures.append("could not save %s/%s.png" % [_dir, state])
		return
	_saved += 1
	print("ui_screenshots: %s/%s.png" % [_dir, state])

func _sizes_dir_size() -> Vector2i:
	var parts: PackedStringArray = _dir.get_file().split("x")
	return Vector2i(int(parts[0]), int(parts[1]))

## True when the image has more than one colour among a coarse grid of samples.
func _has_content(image: Image) -> bool:
	var first: Color = image.get_pixel(0, 0)
	for gy in 12:
		for gx in 12:
			var px: Color = image.get_pixel(gx * (image.get_width() - 1) / 11, gy * (image.get_height() - 1) / 11)
			if not px.is_equal_approx(first):
				return true
	return false

# --- Rigs -----------------------------------------------------------------------

## A fresh Main on the title screen: {"main","server","rm","screen"}.
func _new_main() -> Dictionary:
	PadMenuScript.reset()
	var main: Node = MAIN_SCENE.instantiate()
	var server: Node = main.get_node("ControllerServer")
	server.http_port = 0 # no fixed port: the OS picks, so a running game is never collided with
	server.ws_port = 0
	get_root().add_child(main)
	await _frames(SETTLE_FRAMES * 2)
	var rm: Node = main.get_node("RoundManager")
	return {"main": main, "server": server, "rm": rm, "screen": rm.get_node("LobbyLayer")}

func _free_main(rig: Dictionary) -> void:
	var settings: CanvasLayer = get_root().get_node("Sfx").build_settings_ui()
	if settings.is_open():
		settings.toggle_panel()
	rig["server"].go_offline()
	PadMenuScript.reset()
	rig["main"].queue_free()
	await _frames(4)

func _seats(rig: Dictionary, count: int) -> void:
	var server: Node = rig["server"]
	var host_seats: int = server.claimed_slots().size() - server.bot_director.bot_count()
	server.apply_host_command("bots", maxi(0, count - host_seats))
	await _frames(SETTLE_FRAMES)

## A gamepad press on device 4: it claims the next free seat.
func _pad_claim(device: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.device = device
		ev.button_index = JOY_BUTTON_A
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await process_frame

func _open_settings() -> CanvasLayer:
	var settings: CanvasLayer = get_root().get_node("Sfx").build_settings_ui()
	if not settings.is_open():
		settings.toggle_panel()
	return settings

func _wait_until(cond: Callable, msec: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await process_frame
	return false

# --- States ---------------------------------------------------------------------

func _title_and_couch() -> void:
	var rig: Dictionary = await _new_main()
	var screen: CanvasLayer = rig["screen"]
	screen.show_title(true)
	var settings: CanvasLayer = get_root().get_node("Sfx").build_settings_ui()
	settings.host.telemetry_notice_seen = true # the other shots are of a player who has seen it
	settings.refresh()
	await _shot("title")
	settings.host.telemetry_notice_seen = false # the one-time telemetry notice (#617), nothing saved
	settings.refresh()
	await _frames(3)
	await _shot("telemetry_notice")
	settings.host.telemetry_notice_seen = true
	settings.refresh()
	screen.press_title("local")
	await _seats(rig, 0)
	await _shot("lobby_couch_0")
	screen.set_popup("help") # the popup holds the four live demos (#547)
	await _frames(60) # the demos need a moment to play
	await _shot("how_to_play")
	screen.set_popup("")
	screen.set_popup("stages") # Stages & Rules (#647), Classic then Stock
	await _frames(10)
	await _shot("stages_rules")
	screen.stages_rules().select_tab("stock")
	await _shot("stages_rules_stock")
	var host: RefCounted = screen.stages_rules().settings()
	for off: String in ["Pillars", "Ferry", "Slant", "Bowl", "Mill"]:
		host.set_stage_enabled_for("", off, false)
	host.set_weapon_enabled("sword", false)
	host.set_modifier_enabled("", "gale", false)
	screen.stages_rules().select_tab("sudden_death")
	screen.stages_rules().select_tab("")
	await _shot("stages_rules_some_off")
	screen.stages_rules().select_tab("soccer")
	await _shot("stages_rules_soccer")
	screen.set_popup("")
	await _pad_claim(4) # a gamepad seat first: its card carries the pad picker
	await _seats(rig, 3)
	await _shot("lobby_couch_3_pad")
	await _seats(rig, 8)
	await _shot("lobby_couch_8")
	_open_settings()
	await _shot("settings")
	await _free_main(rig)

func _online() -> void:
	var rig: Dictionary = await _new_main()
	var screen: CanvasLayer = rig["screen"]
	var server: Node = rig["server"]
	screen.press_title("online")
	await _wait_until(func() -> bool: return server.is_online(), 8000)
	await _seats(rig, 1) # the host's own seat is always there
	await _shot("lobby_online_0")
	screen.set_popup("look")
	await _shot("your_look")
	screen.set_popup("")
	await _seats(rig, 3)
	await _shot("lobby_online_3")
	await _seats(rig, 8)
	await _shot("lobby_online_8")
	await _free_main(rig)

func _solo_and_match() -> void:
	var rig: Dictionary = await _new_main()
	var screen: CanvasLayer = rig["screen"]
	var server: Node = rig["server"]
	var rm: Node = rig["rm"]
	screen.press_title("solo")
	await _seats(rig, 1)
	await _shot("lobby_solo_0")
	await _seats(rig, 3)
	await _shot("lobby_solo_3")
	await _seats(rig, 8)
	await _shot("lobby_solo_8")
	server.apply_host_command("target", 1)
	server.apply_host_command("start")
	if not await _wait_until(func() -> bool: return rm.lobby_phase() == "playing", MATCH_TIMEOUT_MSEC):
		_failures.append("%s: the Solo match never reached a round (phase '%s')" % [_dir, rm.lobby_phase()])
		await _free_main(rig)
		return
	await _frames(90)
	await _shot("hud_8_players")
	_open_settings()
	await _shot("esc_menu")
	var settings: CanvasLayer = _open_settings()
	settings.toggle_panel()
	for bot: int in server.virtual_slots():
		var body: Node = server.player_in_slot(bot)
		if body != null:
			body.eliminate()
	if not await _wait_until(func() -> bool: return rm.lobby_phase() == "victory", MATCH_TIMEOUT_MSEC):
		_failures.append("%s: the Solo match never reached victory (phase '%s')" % [_dir, rm.lobby_phase()])
	else:
		await _frames(60)
		await _shot("victory_8_players")
	await _free_main(rig)

## The PC client's join screen (issue #241), the page Join online opens.
func _join_screen() -> void:
	var client: Node = CLIENT_SCENE.instantiate()
	client.settings_path = "" # never the owner's remote_client.cfg
	client.relay_url = "ws://127.0.0.1:%d" % RELAY_PORT
	get_root().add_child(client)
	await _frames(SETTLE_FRAMES)
	await _shot("pc_join_screen")
	client.queue_free()
	await _frames(4)
