extends Node

## Music on the shared screen (issue #118, ADR-0017). An autoload beside
## `Sfx`, and built the same way (ADR-0016): the one thing that plays music,
## reached by path, never by `class_name`.
##
## What it owns:
##
## - **The tracks.** `TRACKS` names each loop. There is one chill track for
##   the lobby and menus, and a rotation of upbeat fight tracks. Every file is
##   CC0 and is credited in CREDITS.md.
## - **What plays.** `play_lobby()` and `play_fight()` are the whole API that
##   the lobby/match flow (#120) needs. Switching crossfades over
##   `CROSSFADE_SEC`. Asking for what is already playing does nothing, so a
##   caller may repeat the call every round.
## - **Following the rounds by default.** It watches the tree for a
##   RoundManager (recognised by its `round_started` and `round_won` signals).
##   A round start switches to fight music, and a round win ducks the music
##   under the round-win sound for a moment. Once the game's own scene is up,
##   the lobby track plays until the first round.
## - **Its own volume**, on a `Music` bus that sends to Master. So the master
##   slider and mute (`Sfx`) still sit on top of it. The volume is saved in the
##   same `user://audio.cfg` as `Sfx`'s settings, in a `music` section.
##
## **Headless.** It runs on the dummy audio driver, like `Sfx`. Tracks are read
## straight off disk when the raw file is there, so a fresh clone plays and
## boots clean. The scenario runner awaits `release()` before it quits, so no
## playback is left for the audio server to free after exit.

const BUS_NAME: StringName = &"Music"
const SETTINGS_PATH: String = "user://audio.cfg"
const SECTION: String = "music"
const DIR: String = "res://assets/music/"

## Every track, by name. `kind` is `lobby` or `fight`, and `db` is its base
## level. The fight rotation is every `fight` track, in this order.
## Optional `loop_start` / `tail_trim` (seconds) cut silence off the seam of a
## file that was not cut to loop (issue #140): playback starts, and every loop
## comes back, at `loop_start`, and it jumps back `tail_trim` before the end.
const TRACKS: Dictionary = {
	"lobby": {"file": "lobby_snowfall_looped.ogg", "kind": "lobby", "db": -8.0},
	"fight_fast": {"file": "fight_fast_fight_looped.ogg", "kind": "fight", "db": -8.0},
	"fight_mars": {"file": "fight_nes_shooter_mars.ogg", "kind": "fight", "db": -9.0,
		"loop_start": 0.08, "tail_trim": 0.075},
}

const CROSSFADE_SEC: float = 1.0
## The duck under the round-win sound. That sound lasts about 0.54 s, so the
## music dips fast, holds a little past it, then comes back.
const DUCK_DB: float = -14.0
const DUCK_ATTACK_SEC: float = 0.05
const DUCK_HOLD_SEC: float = 0.6
const DUCK_RELEASE_SEC: float = 0.5
## How long `release()` waits for the audio server to free stopped playbacks.
const RELEASE_SEC: float = 1.0
## How long closing the game window waits for the same. The server frees a
## stopped playback within a few frames.
const QUIT_RELEASE_SEC: float = 0.25
## How many frames after the game's scene is up the lobby track starts. A
## boot that quits on its first frame (the boot check's `--quit`) then never
## starts a track, so it leaves none for the audio server to free after exit.
## This counts frames, not seconds, because the first frame's delta includes
## the whole load time.
const LOBBY_START_DELAY_FRAMES: int = 10
## The level a fading voice is stopped at, and the floor for dB maths.
const SILENT: float = 0.0001
const META_WATCHED: StringName = &"_music_watched"

## 0..1, applied to the Music bus. Set it through `set_volume()` so that it
## reaches the bus and is saved.
var volume: float = 1.0
## Whether `set_volume()` saves. The scenario suite switches this off, and
## points `settings_path` at a temp file when it tests saving.
var persist_settings: bool = true
var settings_path: String = SETTINGS_PATH
## Whether a RoundManager's `round_started` switches to fight music. The
## lobby flow can switch this off if it wants to drive the music itself.
var follow_rounds: bool = true

## The track playing, or fading in: a key of `TRACKS`, or "" for silence.
var _current: String = ""
var _fight_turn: int = 0
var _streams: Dictionary = {}
var _warned: Dictionary = {}
## Two voices, so a switch can crossfade. `_levels` holds each voice's fade
## position (linear 0..1), and `_targets` is where each one is heading.
var _voices: Array[AudioStreamPlayer] = []
var _levels: Array[float] = [0.0, 0.0]
var _targets: Array[float] = [0.0, 0.0]
var _track_db: Array[float] = [0.0, 0.0]
var _active: int = 0
var _duck_db: float = 0.0
var _duck_hold_left: float = 0.0
var _switches: PackedStringArray = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus()
	load_settings()
	for i in 2:
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%d" % i
		voice.bus = BUS_NAME
		add_child(voice)
		_voices.append(voice)
	get_tree().node_added.connect(_on_node_added)
	_watch_subtree(get_tree().root)
	# The game's own scene is only current once all the autoloads are ready.
	# The scenario runner never has one, so it starts in silence.
	_start_if_in_game.call_deferred()

## Closing the game window: stop the music (and any sound effect) and give
## the audio server a moment to free the playbacks, then quit. Quitting at
## once would report them as "ObjectDB instances leaked at exit". This only
## applies in the game (`_start_if_in_game`); scripts quit as they like.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not get_tree().auto_accept_quit:
		_quit_cleanly()

func _quit_cleanly() -> void:
	var sfx: Node = get_node_or_null(^"/root/Sfx")
	if sfx != null:
		sfx.stop_all()
	await release(QUIT_RELEASE_SEC)
	get_tree().quit()

func _process(delta: float) -> void:
	_step_duck(delta)
	var rate: float = delta / CROSSFADE_SEC
	for i in _voices.size():
		_levels[i] = move_toward(_levels[i], _targets[i], rate)
		var voice: AudioStreamPlayer = _voices[i]
		voice.volume_db = _track_db[i] + linear_to_db(maxf(_levels[i], SILENT)) + _duck_db
		if _targets[i] == 0.0 and _levels[i] <= 0.0 and voice.playing:
			voice.stop()
	_wrap_trimmed_loop()

# --- The API the lobby/match flow calls -------------------------------------

## Play the lobby/menu track.
func play_lobby() -> void:
	_switch_to("lobby")

## Play fight music. If fight music is already playing, it carries on. From
## anything else, the next track in the fight rotation starts.
func play_fight() -> void:
	if current_kind() == "fight":
		return
	var fights: PackedStringArray = fight_tracks()
	if fights.is_empty():
		return
	var track: String = fights[_fight_turn % fights.size()]
	_fight_turn += 1
	_switch_to(track)

## Fade out to silence.
func stop() -> void:
	_current = ""
	_targets[0] = 0.0
	_targets[1] = 0.0

## Dip the music under a sound that must be heard. The round win calls it.
func duck() -> void:
	_duck_hold_left = DUCK_HOLD_SEC

# --- State, for the settings menu and the scenarios -------------------------

## The playing track's key, or "" for silence.
func current_track() -> String:
	return _current

## "lobby", "fight", or "" for silence.
func current_kind() -> String:
	if _current == "":
		return ""
	return String(TRACKS[_current]["kind"])

## Whether the track is really playing on a voice, and not only asked for.
func is_playing() -> bool:
	return _current != "" and _voices[_active].playing

## How far the music is ducked right now, in dB (0 means not ducked).
func duck_db() -> float:
	return _duck_db

## Every track asked for since startup, in order. A repeated ask that changed
## nothing is not listed.
func switches() -> PackedStringArray:
	return _switches.duplicate()

func fight_tracks() -> PackedStringArray:
	var names := PackedStringArray()
	for key: String in TRACKS:
		if TRACKS[key]["kind"] == "fight":
			names.append(key)
	return names

## Every file `TRACKS` refers to, as res:// paths.
func all_track_files() -> PackedStringArray:
	var paths := PackedStringArray()
	for key: String in TRACKS:
		paths.append(DIR + String(TRACKS[key]["file"]))
	return paths

## Stop everything and wait for the audio server to let go of it, as
## `Sfx.release()` does. The scenario runner awaits this before it quits.
func release(wait_sec: float = RELEASE_SEC) -> void:
	_current = ""
	for i in _voices.size():
		_voices[i].stop()
		_voices[i].stream = null
		_levels[i] = 0.0
		_targets[i] = 0.0
	_streams.clear()
	# Out of the tree there is no SceneTree to wait on (issue #167).
	if not is_inside_tree():
		return
	await get_tree().create_timer(wait_sec, true, false, true).timeout

# --- Volume -------------------------------------------------------------------

## `save` false applies the volume without writing the settings file; the
## settings menu saves once a slider drag ends (issue #167).
func set_volume(value: float, save: bool = true) -> void:
	volume = clampf(value, 0.0, 1.0) if is_finite(value) else 1.0
	_apply_volume()
	if save:
		_save_settings()

## Write the volume to `settings_path` (when `persist_settings`).
func save_settings() -> void:
	_save_settings()

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		volume = clampf(float(config.get_value(SECTION, "volume", 1.0)), 0.0, 1.0)
	_apply_volume()

func _apply_volume() -> void:
	var index: int = AudioServer.get_bus_index(BUS_NAME)
	if index != -1:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, SILENT)))

## Load, change and save, so `Sfx`'s sections in the same file are kept.
func _save_settings() -> void:
	if not persist_settings:
		return
	var config := ConfigFile.new()
	config.load(settings_path)
	config.set_value(SECTION, "volume", volume)
	config.save(settings_path)

# --- Following the rounds -----------------------------------------------------

func _start_if_in_game() -> void:
	if get_tree().current_scene == null:
		return
	get_tree().auto_accept_quit = false
	for i in LOBBY_START_DELAY_FRAMES:
		await get_tree().process_frame
	if _current == "":
		play_lobby()

func _watch_subtree(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_watch_subtree(child)

func _on_node_added(node: Node) -> void:
	if node.has_meta(META_WATCHED):
		return
	if node.has_signal("round_started") and node.has_signal("round_won"):
		node.set_meta(META_WATCHED, true)
		node.connect("round_started", _on_round_started)
		node.connect("round_won", _on_round_won)

func _on_round_started() -> void:
	if follow_rounds:
		play_fight()

func _on_round_won(_slot: int) -> void:
	duck()

# --- Internals --------------------------------------------------------------

func _switch_to(track: String) -> void:
	if track == _current or not TRACKS.has(track):
		return
	var stream: AudioStream = _stream_for(track)
	_current = track
	_switches.append(track)
	if stream == null:
		stop()
		_current = track
		return
	# The voice that was playing fades out. The other one takes the new track.
	var previous: int = _active
	_active = 1 - _active
	_targets[previous] = 0.0
	var voice: AudioStreamPlayer = _voices[_active]
	voice.stop()
	voice.stream = stream
	_track_db[_active] = float(TRACKS[track].get("db", 0.0))
	_levels[_active] = 0.0
	_targets[_active] = 1.0
	voice.volume_db = _track_db[_active] + linear_to_db(SILENT) + _duck_db
	voice.play(loop_window(track).x)

## The part of `track` that loops, as (start, end) seconds into the file. The
## end is the file's length, less any `tail_trim`; 0 when it is not loaded.
func loop_window(track: String) -> Vector2:
	if not TRACKS.has(track):
		return Vector2.ZERO
	var info: Dictionary = TRACKS[track]
	var stream: AudioStream = _stream_for(track)
	var length: float = stream.get_length() if stream != null else 0.0
	var end: float = maxf(length - float(info.get("tail_trim", 0.0)), 0.0)
	return Vector2(float(info.get("loop_start", 0.0)), end)

# A trimmed track jumps back to its loop start before its silent tail, rather
# than letting the stream play the silence out and wrap on its own.
func _wrap_trimmed_loop() -> void:
	if _current == "" or not TRACKS.has(_current) or not TRACKS[_current].has("tail_trim"):
		return
	var voice: AudioStreamPlayer = _voices[_active]
	if not voice.playing:
		return
	var window: Vector2 = loop_window(_current)
	# The playback position only moves once per mix, so add the time since it.
	var position: float = voice.get_playback_position() + AudioServer.get_time_since_last_mix()
	if window.y > window.x and position >= window.y:
		voice.seek(window.x)

func _step_duck(delta: float) -> void:
	if _duck_hold_left > 0.0:
		_duck_hold_left = maxf(_duck_hold_left - delta, 0.0)
		_duck_db = move_toward(_duck_db, DUCK_DB, absf(DUCK_DB) * delta / DUCK_ATTACK_SEC)
	else:
		_duck_db = move_toward(_duck_db, 0.0, absf(DUCK_DB) * delta / DUCK_RELEASE_SEC)

func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) != -1:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS_NAME)
	AudioServer.set_bus_send(index, &"Master")

func _stream_for(track: String) -> AudioStream:
	if _streams.has(track):
		return _streams[track]
	var path: String = DIR + String(TRACKS[track]["file"])
	var stream: AudioStream = null
	if FileAccess.file_exists(path):
		# Straight off disk, which needs no import cache (as `Sfx` does).
		stream = AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
	else:
		stream = imported_stream(track)
	_apply_loop(stream, track)
	if stream == null and not _warned.has(path):
		_warned[path] = true
		push_warning("Music: missing track %s" % path)
	_streams[track] = stream
	return stream

## The imported copy of `track` (all an exported build ships), looping from
## its `loop_start` as the raw file does (issue #167); null when there is none.
## A copy, so the shared cached resource is left as imported.
func imported_stream(track: String) -> AudioStream:
	if not TRACKS.has(track):
		return null
	var path: String = DIR + String(TRACKS[track]["file"])
	if not ResourceLoader.exists(path):
		return null
	var loaded: AudioStream = load(path) as AudioStream
	if loaded == null:
		return null
	var stream: AudioStream = loaded.duplicate() as AudioStream
	_apply_loop(stream, track)
	return stream

## Loop `stream` back to `track`'s `loop_start` whenever it wraps by itself --
## after a hitch that let `_wrap_trimmed_loop` miss the window's end.
func _apply_loop(stream: AudioStream, track: String) -> void:
	if stream == null or not ("loop" in stream and "loop_offset" in stream):
		return
	stream.set("loop", true)
	stream.set("loop_offset", float(TRACKS[track].get("loop_start", 0.0)))
