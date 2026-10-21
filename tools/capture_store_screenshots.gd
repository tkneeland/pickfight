extends SceneTree
## Steam store screenshots (issue #723): a curated set of 1920x1080 PNGs of the
## real game for the store page (docs/steam-readiness.md item 2.3). Not part of
## the scenario suite or CI -- headless Godot does not render, so run it
## windowed, by hand, one window at a time:
##
##   perl -e 'alarm 180; exec @ARGV' godot --path . -s tools/capture_store_screenshots.gd -- --out=$PWD/docs/launch/screenshots [--only=title,brawl]
##
## Writes `<out>/<NN>-<name>.png` and quits itself (exit 1 if a match never
## started or a shot is blank). Bots fill every seat so the fights are real;
## nothing is read from or written to the owner's settings (a `-s` run uses a
## temp settings file, see ui_screenshots.gd). Shots, by name:
##   title, lobby (QR and 8 seated cards), brawl (8 bots, Classic), teams,
##   soccer, ctf, hazard (lava stage), weapons (a different weapon in each
##   hand), podium (victory with 8 players).
## Screens are driven through their public methods and host commands, as
## ui_screenshots.gd does. Scripts are preloaded by path, never by class_name.
const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const PadMenuScript := preload("res://scripts/PadMenu.gd")
const PickupWeaponsScript := preload("res://scripts/PickupWeapons.gd")
const SIZE: Vector2i = Vector2i(1920, 1080)
const SETTLE_FRAMES: int = 8
const MATCH_TIMEOUT_MSEC: int = 40000

var _out: String = ""
var _only: PackedStringArray = []
var _failures: Array[String] = []
var _saved: int = 0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",")
	if _out.is_empty():
		printerr("capture_store_screenshots: --out=<dir> is required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_run()

func _wants(shot: String) -> bool:
	return _only.is_empty() or _only.has(shot)

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(SIZE)
	get_root().size = SIZE
	await _frames(SETTLE_FRAMES)
	if _wants("title") or _wants("lobby"):
		await _title_and_lobby()
	if _wants("brawl"):
		await _match("brawl", "02-brawl", "Bowl", "", false, 200)
	if _wants("teams"):
		await _match("teams", "04-teams", "Colosseum", "", true, 120)
	if _wants("soccer"):
		await _match("soccer", "05-soccer", "Pitch", "soccer", true, 150)
	if _wants("ctf"):
		await _match("ctf", "06-capture-the-flag", "Stronghold", "capture_the_flag", true, 150)
	if _wants("hazard"):
		await _match("hazard", "07-hazard-stage", "Furnace", "", false, 150)
	if _wants("weapons"):
		await _match("weapons", "08-weapons", "Colosseum", "", false, 100, true)
	if _wants("podium"):
		await _match("podium", "09-podium", "Flatlands", "", false, 150, false, true)
	print("capture_store_screenshots: %d PNGs under %s, %d problems" % [_saved, _out, _failures.size()])
	for message: String in _failures:
		printerr("  " + message)
	quit(1 if not _failures.is_empty() else 0)

func _frames(n: int) -> void:
	for _i in n:
		await process_frame

func _wait_until(cond: Callable, msec: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await process_frame
	return false

func _shot(file: String) -> void:
	await _frames(SETTLE_FRAMES)
	var image: Image = get_root().get_texture().get_image()
	if image.get_size() != SIZE:
		image.resize(SIZE.x, SIZE.y)
	if image.save_png("%s/%s.png" % [_out, file]) != OK:
		_failures.append("could not save %s" % file)
		return
	_saved += 1
	print("capture_store_screenshots: %s/%s.png" % [_out, file])

func _new_main() -> Dictionary:
	PadMenuScript.reset()
	var main: Node = MAIN_SCENE.instantiate()
	var server: Node = main.get_node("ControllerServer")
	server.http_port = 0 # the OS picks a port, so a running game is never collided with
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

func _notice_seen(seen: bool) -> void:
	var settings: CanvasLayer = get_root().get_node("Sfx").build_settings_ui()
	settings.host.telemetry_notice_seen = seen # no first-launch notice in a store shot
	settings.refresh()

func _title_and_lobby() -> void:
	var rig: Dictionary = await _new_main()
	var screen: CanvasLayer = rig["screen"]
	screen.show_title(true)
	_notice_seen(true)
	if _wants("title"):
		await _shot("01-title")
	if _wants("lobby"):
		screen.press_title("local")
		await _seats(rig, 8)
		await _frames(30)
		await _shot("03-lobby")
	await _free_main(rig)

## One match on `stage`, in `mode_id` ("" = Classic), then the shot. `fight`
## frames are let run so the bots are mid-brawl. `weapons` gives every player a
## different weapon first; `podium` knocks everyone out and shoots the victory
## screen instead.
func _match(shot: String, file: String, stage: String, mode_id: String, teams: bool, fight: int, weapons: bool = false, podium: bool = false) -> void:
	var rig: Dictionary = await _new_main()
	var screen: CanvasLayer = rig["screen"]
	var server: Node = rig["server"]
	var rm: Node = rig["rm"]
	_notice_seen(true)
	rm.forced_night = 0 # daylight and no round modifiers: a clear picture, no banner over the fight
	rm.modifier_rolls_enabled = false
	var only: Array[PackedScene] = [load("res://scenes/stages/%s.tscn" % stage) as PackedScene]
	rm.stage_scenes = only
	screen.press_title("solo")
	await _seats(rig, 8)
	# The host settings are shared across matches in this run: set the format and mode every time.
	server.apply_host_command("mode", "teams" if teams else "ffa")
	server.apply_host_command("gamemode", "")
	if mode_id != "":
		if not server.apply_host_command("gamemode", mode_id):
			_failures.append("%s: mode '%s' was refused" % [shot, mode_id])
	server.apply_host_command("target", 1)
	server.apply_host_command("start")
	if not await _wait_until(func() -> bool: return rm.lobby_phase() == "playing", MATCH_TIMEOUT_MSEC):
		_failures.append("%s: the match never reached a round (phase '%s')" % [shot, rm.lobby_phase()])
		await _free_main(rig)
		return
	if weapons:
		var paths: PackedStringArray = rm.playtest_weapon_paths()
		var i: int = 0
		for slot: int in server.claimed_slots():
			var body: Node = server.player_in_slot(slot)
			if body != null:
				body.set_weapon_stats(load(paths[(i * 2) % paths.size()]))
				i += 1
	await _frames(fight)
	if podium:
		for bot: int in server.virtual_slots(): # the host's seat is left to win
			var body: Node = server.player_in_slot(bot)
			if body != null:
				body.eliminate()
		if not await _wait_until(func() -> bool: return rm.lobby_phase() == "victory", MATCH_TIMEOUT_MSEC):
			_failures.append("%s: never reached victory (phase '%s')" % [shot, rm.lobby_phase()])
			await _free_main(rig)
			return
		await _frames(90)
	await _shot(file)
	await _free_main(rig)
