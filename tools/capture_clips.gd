extends SceneTree
## Gameplay clips for the trailer and social posts (issue #743): full-resolution
## 60 fps footage of the real game, recorded with Godot's Movie Maker. Not part
## of the scenario suite or CI -- headless Godot does not render, so run it
## windowed, by hand, ONE clip and ONE window at a time (Movie Maker writes one
## file per run; tools/capture_clips.sh loops over the clips):
##
##   perl -e 'alarm 180; exec @ARGV' godot --path . --write-movie $OUT/brawl.avi --fixed-fps 60 --resolution 1920x1080 -s tools/capture_clips.gd -- --only=brawl
##
## Flags after `--`: `--only=<clip>` (required; one of CLIPS), `--seconds=<n>`
## (override the clip length, for quick checks), `--frame-png=<sec>[,<sec>]`
## (also save viewport PNGs at those seconds into the clip's `--out` dir) and
## `--out=<dir>` (where the PNGs go; default: next to the movie file's cwd).
## The script quits itself when the clip ends (exit 1 if a match never started).
## Bots (Hard) fill all eight seats on a fixed stage and mode, with the HUD as in
## game. The recording starts with the process, so the first seconds are the
## stage card and countdown; `seconds` counts from the first frame of play.
## Scripts are preloaded by path, never by class_name (see capture_store_screenshots.gd).
const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const PadMenuScript := preload("res://scripts/PadMenu.gd")
const FPS: int = 60
const SIZE: Vector2i = Vector2i(1920, 1080)
const SETTLE_FRAMES: int = 8
const MATCH_TIMEOUT_FRAMES: int = 20 * FPS

## clip -> stage, game mode ("" = Classic), teams, seconds of play, weapons, podium.
const CLIPS: Dictionary = {
	"brawl": {"stage": "Bowl", "mode": "", "teams": false, "seconds": 12.0},
	"lava": {"stage": "Furnace", "mode": "", "teams": false, "seconds": 10.0},
	"soccer": {"stage": "Pitch", "mode": "soccer", "teams": true, "seconds": 12.0},
	"ctf": {"stage": "Stronghold", "mode": "capture_the_flag", "teams": true, "seconds": 12.0},
	"weapons": {"stage": "Colosseum", "mode": "", "teams": false, "seconds": 10.0, "weapons": true},
	"podium": {"stage": "Flatlands", "mode": "", "teams": false, "seconds": 8.0, "podium": true},
}

var _only: String = ""
var _seconds: float = -1.0
var _png_at: Array[float] = []
var _out: String = ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
		elif arg.begins_with("--seconds="):
			_seconds = float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--frame-png="):
			for s: String in arg.trim_prefix("--frame-png=").split(","):
				_png_at.append(float(s))
	if not CLIPS.has(_only):
		printerr("capture_clips: --only=<clip> is required, one of: %s" % ", ".join(CLIPS.keys()))
		quit(2)
		return
	if not _png_at.is_empty():
		if _out.is_empty():
			_out = OS.get_environment("PWD")
		DirAccess.make_dir_recursive_absolute(_out)
	# Hard stop whatever happens (a script error would otherwise leave the window open).
	var seconds: float = _seconds if _seconds >= 0.0 else float(CLIPS[_only]["seconds"])
	create_timer(seconds + 25.0).timeout.connect(func() -> void:
		printerr("capture_clips: hard timeout, quitting")
		quit(1))
	_run()

func _frames(n: int) -> void:
	for _i in n:
		await process_frame

func _wait_until(cond: Callable, max_frames: int) -> bool:
	for _i in max_frames:
		if cond.call():
			return true
		await process_frame
	return false

func _run() -> void:
	var clip: Dictionary = CLIPS[_only]
	PadMenuScript.reset()
	var main: Node = MAIN_SCENE.instantiate()
	var server: Node = main.get_node("ControllerServer")
	server.http_port = 0 # the OS picks a port, so a running game is never collided with
	server.ws_port = 0
	get_root().add_child(main)
	await _frames(SETTLE_FRAMES * 2)
	var rm: Node = main.get_node("RoundManager")
	var screen: CanvasLayer = rm.get_node("LobbyLayer")
	var settings: CanvasLayer = get_root().get_node("Sfx").build_settings_ui()
	settings.host.telemetry_notice_seen = true # no first-launch notice over the footage
	settings.refresh()
	rm.forced_night = 0 # daylight and no round modifiers: a clear picture, no banner
	rm.modifier_rolls_enabled = false
	var only: Array[PackedScene] = [load("res://scenes/stages/%s.tscn" % clip["stage"]) as PackedScene]
	rm.stage_scenes = only
	screen.press_title("solo")
	server.apply_host_command("bot_difficulty", "hard")
	var host_seats: int = server.claimed_slots().size() - server.bot_director.bot_count()
	server.apply_host_command("bots", maxi(0, 8 - host_seats))
	await _frames(SETTLE_FRAMES)
	server.apply_host_command("mode", "teams" if clip["teams"] else "ffa")
	server.apply_host_command("gamemode", "")
	if clip["mode"] != "" and not server.apply_host_command("gamemode", clip["mode"]):
		printerr("capture_clips: mode '%s' was refused" % clip["mode"])
		quit(1)
		return
	server.apply_host_command("target", 1)
	server.apply_host_command("start")
	if not await _wait_until(func() -> bool: return rm.lobby_phase() == "playing", MATCH_TIMEOUT_FRAMES):
		printerr("capture_clips: the match never reached a round (phase '%s')" % rm.lobby_phase())
		quit(1)
		return
	if clip.get("weapons", false):
		var paths: PackedStringArray = rm.playtest_weapon_paths()
		var i: int = 0
		for slot: int in server.claimed_slots():
			var body: Node = server.player_in_slot(slot)
			if body != null:
				body.set_weapon_stats(load(paths[(i * 2) % paths.size()]))
				i += 1
	if clip.get("podium", false):
		await _frames(2 * FPS) # a short fight first
		for bot: int in server.virtual_slots(): # the host's seat is left to win
			var body: Node = server.player_in_slot(bot)
			if body != null:
				body.eliminate()
		if not await _wait_until(func() -> bool: return rm.lobby_phase() == "victory", MATCH_TIMEOUT_FRAMES):
			printerr("capture_clips: never reached victory (phase '%s')" % rm.lobby_phase())
			quit(1)
			return
	var total: int = int((_seconds if _seconds >= 0.0 else float(clip["seconds"])) * FPS)
	for frame in total:
		for sec: float in _png_at:
			if frame == int(sec * FPS):
				_save_png(sec)
		await process_frame
	print("capture_clips: %s done, %d frames (%.1f s) of play" % [_only, total, float(total) / FPS])
	server.go_offline()
	quit(0)

func _save_png(sec: float) -> void:
	var image: Image = get_root().get_texture().get_image()
	if image.get_size() != SIZE:
		image.resize(SIZE.x, SIZE.y)
	var path: String = "%s/%s-%ss.png" % [_out, _only, str(sec)]
	if image.save_png(path) == OK:
		print("capture_clips: frame saved %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	else:
		printerr("capture_clips: could not save %s" % path)
