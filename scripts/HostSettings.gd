extends RefCounted

## The host's content and display choices (issue #294), next to the volume and
## fullscreen settings `Sfx` and `Music` keep: a windowed-mode resolution, and
## which stages and pickup weapons are switched off.
##
## A stage or weapon is named by its file's base name ("Flatlands",
## "sword"), which is stable and readable in the config file. Disabled ones
## are stored, not enabled ones, so a stage or weapon added later is on by
## default. At least one stage and one pickup weapon always stay on:
## `set_stage_enabled()` and `set_weapon_enabled()` refuse to switch off the
## last one and return false. The pickaxe is not listed; everyone starts
## with it (ADR-0009).
##
## Saved in the `[host]` section of the same `user://audio.cfg` the others
## use, loading the file first so their sections are kept. Preloaded by path,
## never by `class_name` (CLAUDE.md).
##
## A voice volume slider (#290, per-player voice grunts) is not built; when
## that lands its value belongs in `SfxSettings`' audio rows, saved by `Sfx`.

const SfxScript := preload("res://scripts/Sfx.gd")
const PickupWeaponsScript := preload("res://scripts/PickupWeapons.gd")

const SETTINGS_PATH: String = "user://audio.cfg"
const SECTION: String = "host"
## Windowed sizes offered. `Vector2i.ZERO` means the project's own window.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i.ZERO,
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

static var _shared: RefCounted

var path: String = SETTINGS_PATH
## Off for a `-s` run, so a scenario never writes the owner's file.
var persist: bool = true
var resolution: Vector2i = Vector2i.ZERO
var disabled_stages: PackedStringArray = []
var disabled_weapons: PackedStringArray = []
## The `GameModes` id the host last picked (issue #352); "" is Classic.
var game_mode: String = ""
## Every stage in the rotation, set by `StageRotation`. The last-one rule
## counts against it.
var known_stages: PackedStringArray = []

## The one store the game uses. A `-s` run (scenarios) gets defaults, saving
## off, as `Sfx` does (#195).
static func shared() -> RefCounted:
	if _shared == null:
		_shared = (load("res://scripts/HostSettings.gd") as GDScript).new()
		var tree := Engine.get_main_loop() as SceneTree
		if SfxScript.is_script_main_loop(tree):
			_shared.persist = false
			_shared.path = SfxScript.headless_settings_path()
		else:
			_shared.load_settings()
	return _shared

static func name_of(resource_path: String) -> String:
	return resource_path.get_file().get_basename()

static func known_weapons() -> PackedStringArray:
	var names := PackedStringArray()
	for weapon_path: String in PickupWeaponsScript.WEAPON_PATHS:
		names.append(name_of(weapon_path))
	return names

func is_stage_enabled(stage_name: String) -> bool:
	return not disabled_stages.has(stage_name)

func is_weapon_enabled(weapon_name: String) -> bool:
	return not disabled_weapons.has(weapon_name)

## Returns false (changing nothing) when this would switch off the last
## enabled stage.
func set_stage_enabled(stage_name: String, enabled: bool) -> bool:
	return _set_enabled(disabled_stages, known_stages, stage_name, enabled)

## Returns false (changing nothing) when this would switch off the last
## enabled pickup weapon.
func set_weapon_enabled(weapon_name: String, enabled: bool) -> bool:
	return _set_enabled(disabled_weapons, known_weapons(), weapon_name, enabled)

func set_resolution(size: Vector2i) -> void:
	resolution = size
	save_settings()

func set_game_mode(id: String) -> void:
	game_mode = id
	save_settings()

func _set_enabled(disabled: PackedStringArray, known: PackedStringArray, item: String, enabled: bool) -> bool:
	var index: int = disabled.find(item)
	if enabled:
		if index != -1:
			disabled.remove_at(index)
	elif index == -1:
		var remaining: int = 0
		for other: String in known:
			if other != item and not disabled.has(other):
				remaining += 1
		if remaining == 0:
			return false
		disabled.append(item)
	save_settings()
	return true

func load_settings() -> void:
	var config := ConfigFile.new()
	var err: Error = config.load(path)
	if err == OK:
		var size: Variant = config.get_value(SECTION, "resolution", Vector2i.ZERO)
		resolution = size if size is Vector2i else Vector2i.ZERO
		disabled_stages = PackedStringArray(config.get_value(SECTION, "disabled_stages", PackedStringArray()))
		disabled_weapons = PackedStringArray(config.get_value(SECTION, "disabled_weapons", PackedStringArray()))
		game_mode = str(config.get_value(SECTION, "game_mode", ""))
	elif err != ERR_FILE_NOT_FOUND:
		push_warning("HostSettings: could not read %s (%s); using the defaults" % [path, error_string(err)])

func save_settings() -> void:
	if not persist:
		return
	var config := ConfigFile.new()
	var err: Error = config.load(path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("HostSettings: not saving: %s would not load (%s)" % [path, error_string(err)])
		return
	config.set_value(SECTION, "resolution", resolution)
	config.set_value(SECTION, "disabled_stages", disabled_stages)
	config.set_value(SECTION, "disabled_weapons", disabled_weapons)
	config.set_value(SECTION, "game_mode", game_mode)
	err = config.save(path)
	if err != OK:
		push_warning("HostSettings: could not save to %s (%s)" % [path, error_string(err)])
