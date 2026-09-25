extends Node

## Sound effects on the shared screen (issue #75, ADR-0016). An autoload, so
## the one entry point -- `play(name, position, strength)` -- is there for
## every scene and every scenario without anything having to be wired to it.
##
## What it owns, and nothing else:
##
## - **The sound table.** `SOUNDS` names every sound the game can make and the
##   pool of variant files it picks from, so repeated hits do not all sound
##   the same. Adding a sound is one entry here plus one `play()` call (or one
##   line in `SfxHooks.gd`).
## - **Strength.** 0..1: how hard the thing that made the sound was. It scales
##   volume (`MIN_GAIN` at 0, full at 1) and pitch (a harder hit sits a little
##   lower, which reads as weight).
## - **Placement.** A sound with a position plays through an
##   `AudioStreamPlayer2D`, so it pans left or right with where it happened
##   on screen. UI sounds (`"positional": false`) play flat.
## - **Mixing.** Everything plays on the `SFX` bus, created here if the
##   project has no bus layout, and no one sound has more than its
##   `overlap` copies playing at once: past the cap the oldest copy is cut
##   and reused, so a flurry stays a flurry and not a wall of noise.
## - **Master volume and mute**, applied to the Master bus and remembered in
##   `user://audio.cfg`. `SfxSettings.gd` is the on-screen control for them.
##
## Which game events make which sound is not here: `SfxHooks.gd` listens to
## the signals the game already emits and calls `play()`. Nothing in the game
## calls this autoload by name, so a scene or script never breaks for want of
## it, and the phones never hear anything (ADR-0013 keeps them to the buzz).
##
## **Headless.** Godot's dummy audio driver takes the same calls, so the
## scenario suite runs this for real. Sound files are read straight off disk
## when the raw file is present, so a fresh clone that has never been
## imported still plays (and still boots clean); an exported build, which
## carries only the imported copy, loads that instead.

const HooksScript := preload("res://scripts/SfxHooks.gd")
const SettingsScript := preload("res://scripts/SfxSettings.gd")

const BUS_NAME: StringName = &"SFX"
const SETTINGS_PATH: String = "user://audio.cfg"
const DIR: String = "res://assets/sfx/"

## Every sound the game makes. Per entry:
##   files       -- variant pool, one picked per play (never the same one
##                  twice running when there is a choice)
##   db          -- base volume, before strength
##   overlap     -- most copies playing at once (DEFAULT_OVERLAP if absent)
##   positional  -- false for UI sounds, which play flat (default true)
##   max_sec     -- fade out and stop after this long (for long files)
##
## The `hit_<set>` and `fire_<set>` names are per weapon: a weapon's
## `WeaponStats.sound_set` picks them. See CREDITS.md for every file's source.
const SOUNDS: Dictionary = {
	# --- Strikes, one set per weapon --------------------------------------
	"hit_pickaxe": {"files": [
		"kenney_impact/impactMining_000.ogg",
		"kenney_impact/impactMining_001.ogg",
		"kenney_impact/impactMining_002.ogg"], "db": 0.0},
	"hit_sword": {"files": [
		"kenney_rpg/knifeSlice.ogg",
		"kenney_rpg/knifeSlice2.ogg",
		"kenney_rpg/drawKnife1.ogg"], "db": 0.0},
	"hit_axe": {"files": [
		"kenney_rpg/chop.ogg",
		"kenney_impact/impactWood_heavy_000.ogg",
		"kenney_impact/impactWood_heavy_001.ogg"], "db": 2.0},
	"hit_staff": {"files": [
		"kenney_impact/impactPlank_medium_000.ogg",
		"kenney_impact/impactPlank_medium_001.ogg",
		"kenney_impact/impactPlank_medium_002.ogg"], "db": 0.0},
	"hit_dagger": {"files": [
		"kenney_impact/impactMetal_light_000.ogg",
		"kenney_impact/impactMetal_light_001.ogg",
		"kenney_impact/impactMetal_light_002.ogg"], "db": -2.0},
	"hit_boomstick": {"files": [
		"kenney_impact/impactPunch_heavy_000.ogg",
		"kenney_impact/impactPunch_heavy_001.ogg",
		"kenney_impact/impactPunch_heavy_002.ogg"], "db": 0.0},
	# --- Firing -------------------------------------------------------------
	"fire_boomstick": {"files": [
		"kenney_scifi/explosionCrunch_000.ogg",
		"kenney_scifi/explosionCrunch_001.ogg"], "db": -3.0, "overlap": 4},
	"bullet_impact": {"files": [
		"kenney_impact/impactTin_medium_000.ogg",
		"kenney_impact/impactTin_medium_001.ogg"], "db": -4.0},
	# --- Other combat and movement -----------------------------------------
	"clash": {"files": [
		"kenney_impact/impactMetal_medium_000.ogg",
		"kenney_impact/impactMetal_medium_001.ogg",
		"kenney_impact/impactMetal_medium_002.ogg"], "db": 0.0},
	"head_terrain": {"files": [
		"kenney_impact/footstep_concrete_000.ogg",
		"kenney_impact/footstep_concrete_001.ogg",
		"kenney_impact/footstep_concrete_002.ogg"], "db": -2.0, "overlap": 4},
	"land": {"files": [
		"kenney_impact/impactSoft_heavy_000.ogg",
		"kenney_impact/impactSoft_heavy_001.ogg",
		"kenney_impact/impactSoft_heavy_002.ogg"], "db": -3.0},
	"eliminated": {"files": [
		"kenney_scifi/lowFrequency_explosion_000.ogg"], "db": 0.0, "overlap": 2},
	# --- Lava ---------------------------------------------------------------
	"lava_sizzle": {"files": [
		"kenney_scifi/thrusterFire_000.ogg"], "db": -4.0, "overlap": 2, "max_sec": 1.2},
	"lava_rise": {"files": [
		"kenney_scifi/lowFrequency_explosion_001.ogg"], "db": 0.0, "overlap": 1, "positional": false},
	# --- Round and UI -------------------------------------------------------
	"countdown": {"files": [
		"kenney_interface/tick_001.ogg"], "db": 0.0, "overlap": 1, "positional": false},
	"round_start": {"files": [
		"kenney_interface/bong_001.ogg"], "db": 0.0, "overlap": 1, "positional": false},
	"modifier": {"files": [
		"kenney_interface/maximize_006.ogg"], "db": 0.0, "overlap": 1, "positional": false},
	"round_win": {"files": [
		"kenney_interface/confirmation_002.ogg"], "db": 0.0, "overlap": 1, "positional": false},
	"join": {"files": [
		"kenney_interface/pluck_001.ogg"], "db": 0.0, "overlap": 2, "positional": false},
}

const DEFAULT_OVERLAP: int = 3
## Linear gain at strength 0; strength 1 is full gain. About -9 dB, so the
## softest hit is clearly quieter without vanishing under the rest.
const MIN_GAIN: float = 0.35
## Pitch at strength 0 and at strength 1, before jitter.
const PITCH_AT_ZERO: float = 1.08
const PITCH_AT_FULL: float = 0.92
## Random pitch spread per play, as a fraction, so a pool of three does not
## sound like three recordings.
const PITCH_JITTER: float = 0.04
## Positional sounds are for panning, not for fading out with distance: every
## stage fits the screen, and a hit at the far edge must still be heard.
const MAX_DISTANCE: float = 6000.0
const ATTENUATION: float = 0.5
const FADE_SEC: float = 0.15

## The master volume, 0..1, and whether everything is muted. Set through
## `set_master_volume()` / `set_muted()` so they reach the bus.
var master_volume: float = 1.0
var muted: bool = false
## Whether volume and mute are saved to `SETTINGS_PATH` when changed. The
## scenario suite switches it off so a test run never rewrites the owner's
## settings.
var persist_settings: bool = true

## name -> Array[AudioStream], filled on first play.
var _streams: Dictionary = {}
## name -> Array of the player nodes that sound owns; never more than its cap.
var _voices: Dictionary = {}
## name -> index of the variant played last, to avoid an immediate repeat.
var _last_variant: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _recording: bool = false
var _requests: Array[Dictionary] = []
var _warned: Dictionary = {}
var _play_serial: int = 0
var _hooks: Node
var _settings_ui: CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ensure_bus()
	_load_settings()
	_hooks = HooksScript.new()
	_hooks.name = "Hooks"
	_hooks.sfx = self
	add_child(_hooks)
	# The game's own scene is only current once autoloads have all readied.
	# The scenario runner never has one, so it never builds the overlay.
	_build_settings_ui_if_in_game.call_deferred()

# --- Playing ----------------------------------------------------------------

## Play `sound` (a key of `SOUNDS`). `position` is a world position for a sound
## to pan by, or null to play it flat; `strength` 0..1 is how hard the thing
## that made it was. Unknown names warn once and do nothing.
func play(sound: StringName, position: Variant = null, strength: float = 1.0) -> void:
	var key: String = String(sound)
	if not SOUNDS.has(key):
		if not _warned.has(key):
			_warned[key] = true
			push_warning("Sfx: no sound named '%s'" % key)
		return
	var spec: Dictionary = SOUNDS[key]
	var s: float = clampf(strength, 0.0, 1.0) if is_finite(strength) else 1.0
	var volume_db: float = volume_db_for(key, s)
	var pitch: float = lerpf(PITCH_AT_ZERO, PITCH_AT_FULL, s) * (1.0 + _rng.randf_range(-PITCH_JITTER, PITCH_JITTER))
	var positional: bool = bool(spec.get("positional", true)) and position is Vector2
	if _recording:
		_requests.append({
			"name": key,
			"position": position,
			"strength": s,
			"volume_db": volume_db,
			"pitch": pitch,
		})
	# Not yet in the tree (a `-s` script's first frame): nothing can play.
	if not is_inside_tree():
		return
	var stream: AudioStream = _pick_stream(key)
	if stream == null:
		return
	var voice: Node = _claim_voice(key, positional)
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	if voice is AudioStreamPlayer2D:
		(voice as AudioStreamPlayer2D).global_position = position if position is Vector2 else _screen_centre()
	_play_serial += 1
	voice.set_meta(&"sfx_play", _play_serial)
	voice.play()
	if spec.has("max_sec"):
		_fade_out_later(voice, float(spec["max_sec"]))

## The volume a play of `sound` at `strength` gets. Public so the scenarios
## can check the curve without having to catch a play in the act.
func volume_db_for(sound: StringName, strength: float) -> float:
	var spec: Dictionary = SOUNDS.get(String(sound), {})
	var gain: float = lerpf(MIN_GAIN, 1.0, clampf(strength, 0.0, 1.0))
	return float(spec.get("db", 0.0)) + linear_to_db(gain)

func has_sound(sound: StringName) -> bool:
	return SOUNDS.has(String(sound))

## Every file `SOUNDS` refers to, as res:// paths.
func all_sound_files() -> PackedStringArray:
	var paths := PackedStringArray()
	for key: String in SOUNDS:
		for file: String in SOUNDS[key]["files"]:
			paths.append(DIR + file)
	return paths

## The most copies of `sound` that may play at once.
func overlap_cap(sound: StringName) -> int:
	return int(SOUNDS.get(String(sound), {}).get("overlap", DEFAULT_OVERLAP))

## How many copies of `sound` are playing right now.
func active_voices(sound: StringName) -> int:
	var count: int = 0
	for voice: Node in _voices.get(String(sound), []):
		if voice.playing:
			count += 1
	return count

## How many player nodes `sound` owns, playing or not. Never above its cap.
func voice_count(sound: StringName) -> int:
	return _voices.get(String(sound), []).size()

## Stop everything playing. The scenarios use it to start from silence.
func stop_all() -> void:
	for key: String in _voices:
		for voice: Node in _voices[key]:
			voice.stop()

# --- Test hook --------------------------------------------------------------
#
# The scenario suite spies on what was asked for rather than on what came out
# of the speakers, which headless cannot hear.

func start_recording() -> void:
	_requests.clear()
	_recording = true

func stop_recording() -> void:
	_recording = false

## Every `play()` since `start_recording()`: `{name, position, strength,
## volume_db, pitch}`, oldest first.
func recorded() -> Array[Dictionary]:
	return _requests.duplicate()

## The names alone, in order.
func recorded_names() -> PackedStringArray:
	var names := PackedStringArray()
	for r: Dictionary in _requests:
		names.append(r["name"])
	return names

# --- Volume and mute --------------------------------------------------------

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0) if is_finite(value) else 1.0
	_apply_master()
	_save_settings()

func set_muted(value: bool) -> void:
	muted = value
	_apply_master()
	_save_settings()

func toggle_muted() -> void:
	set_muted(not muted)

func _apply_master() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(0, muted)

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		master_volume = clampf(float(config.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
		muted = bool(config.get_value("audio", "muted", false))
	_apply_master()

func _save_settings() -> void:
	if not persist_settings:
		return
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "muted", muted)
	config.save(SETTINGS_PATH)

## The on-screen volume control, built once the game's own scene is up. Also
## public so a scenario can build one and drive it.
func build_settings_ui() -> CanvasLayer:
	if _settings_ui == null:
		_settings_ui = SettingsScript.new()
		_settings_ui.name = "SfxSettings"
		_settings_ui.sfx = self
		add_child(_settings_ui)
	return _settings_ui

func _build_settings_ui_if_in_game() -> void:
	if get_tree().current_scene != null:
		build_settings_ui()

# --- Internals --------------------------------------------------------------

func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) != -1:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS_NAME)
	AudioServer.set_bus_send(index, &"Master")

func _pick_stream(key: String) -> AudioStream:
	if not _streams.has(key):
		var loaded: Array[AudioStream] = []
		for file: String in SOUNDS[key]["files"]:
			var stream: AudioStream = _load_stream(DIR + file)
			if stream != null:
				loaded.append(stream)
		_streams[key] = loaded
	var pool: Array = _streams[key]
	if pool.is_empty():
		return null
	var index: int = _rng.randi() % pool.size()
	if pool.size() > 1 and index == int(_last_variant.get(key, -1)):
		index = (index + 1) % pool.size()
	_last_variant[key] = index
	return pool[index]

## Straight off disk when the raw file is there (any checkout, imported or
## not), else the imported copy (an exported build ships only that).
func _load_stream(path: String) -> AudioStream:
	if FileAccess.file_exists(path):
		var absolute: String = ProjectSettings.globalize_path(path)
		match path.get_extension().to_lower():
			"ogg":
				return AudioStreamOggVorbis.load_from_file(absolute)
			"wav":
				return AudioStreamWAV.load_from_file(absolute)
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	if not _warned.has(path):
		_warned[path] = true
		push_warning("Sfx: missing sound file %s" % path)
	return null

## A free player node for `key`, making one while under the cap, or else the
## copy that has been playing longest, cut short and reused.
func _claim_voice(key: String, positional: bool) -> Node:
	var pool: Array = _voices.get(key, [])
	_voices[key] = pool
	for voice: Node in pool:
		if not voice.playing and (voice is AudioStreamPlayer2D) == positional:
			return voice
	if pool.size() < overlap_cap(key):
		var fresh: Node = _new_voice(positional)
		pool.append(fresh)
		return fresh
	var oldest: Node = pool[0]
	for voice: Node in pool:
		if voice.get_playback_position() > oldest.get_playback_position():
			oldest = voice
	oldest.stop()
	if (oldest is AudioStreamPlayer2D) != positional:
		# Same sound asked for flat and placed: swap the node's kind in place,
		# keeping the pool at its size.
		var index: int = pool.find(oldest)
		oldest.queue_free()
		pool[index] = _new_voice(positional)
		return pool[index]
	return oldest

func _new_voice(positional: bool) -> Node:
	var voice: Node
	if positional:
		var placed := AudioStreamPlayer2D.new()
		placed.max_distance = MAX_DISTANCE
		placed.attenuation = ATTENUATION
		voice = placed
	else:
		voice = AudioStreamPlayer.new()
	voice.bus = BUS_NAME
	add_child(voice)
	return voice

func _fade_out_later(voice: Node, after_sec: float) -> void:
	# Keyed to this play, so a node reused for a newer play is left alone.
	var serial: int = int(voice.get_meta(&"sfx_play", 0))
	var from_db: float = voice.volume_db
	var still_this_play := func() -> bool:
		return is_instance_valid(voice) and int(voice.get_meta(&"sfx_play", 0)) == serial
	var fade := func(t: float) -> void:
		if still_this_play.call():
			voice.volume_db = lerpf(from_db, -60.0, t)
	var finish := func() -> void:
		if still_this_play.call():
			voice.stop()
	var tween: Tween = create_tween()
	tween.tween_interval(after_sec)
	tween.tween_method(fade, 0.0, 1.0, FADE_SEC)
	tween.tween_callback(finish)

func _screen_centre() -> Vector2:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera != null:
		return camera.get_screen_center_position()
	return get_viewport().get_visible_rect().size * 0.5
