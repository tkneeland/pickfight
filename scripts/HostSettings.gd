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
const DemoBuildScript := preload("res://scripts/DemoBuild.gd")

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
## Rules tab (#378): per game mode ("" is Classic), the round modifiers the host
## switched off, as `{mode id: PackedStringArray of modifier ids}`. Empty by
## default, so every modifier can roll. A mode's own bans in `GameModes.TABLE`
## always win over this.
var disabled_modifiers: Dictionary = {}
## The `GameModes` id the host last picked (issue #352); "" is Classic.
var game_mode: String = ""
## Anonymous match stats (issue #372): sent to the relay at match end unless
## switched off in Settings. `telemetry_notice_seen` is set once the first-launch
## notice has been dismissed or acted on.
var share_stats: bool = true
var telemetry_notice_seen: bool = false
## Stock mode (#354): lives per player (1-10) and the time limit in seconds
## (one of STOCK_TIME_LIMITS; 0 is no limit).
const STOCK_MIN_LIVES: int = 1
const STOCK_MAX_LIVES: int = 10
const STOCK_TIME_LIMITS: Array[int] = [120, 300, 480, 900, 0]
var stock_lives: int = 3
var stock_time_limit: int = 480
## The stage a Stock match is played on (#375): a stage's base name, or ""
## for Random.
var stock_stage: String = ""
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
		if DemoBuildScript.weapon_in_slice(name_of(weapon_path)):  # the demo's slice (#361)
			names.append(name_of(weapon_path))
	return names

func is_stage_enabled(stage_name: String) -> bool:
	return not disabled_stages.has(stage_name) and DemoBuildScript.stage_in_slice(stage_name)

func is_weapon_enabled(weapon_name: String) -> bool:
	return not disabled_weapons.has(weapon_name) and DemoBuildScript.weapon_in_slice(weapon_name)

## Returns false (changing nothing) when this would switch off the last
## enabled stage.
func set_stage_enabled(stage_name: String, enabled: bool) -> bool:
	if enabled and not DemoBuildScript.stage_in_slice(stage_name):
		return false  # outside the demo's slice (#361)
	return _set_enabled(disabled_stages, known_stages, stage_name, enabled)

## Returns false (changing nothing) when this would switch off the last
## enabled pickup weapon.
func set_weapon_enabled(weapon_name: String, enabled: bool) -> bool:
	if enabled and not DemoBuildScript.weapon_in_slice(weapon_name):
		return false  # outside the demo's slice (#361)
	return _set_enabled(disabled_weapons, known_weapons(), weapon_name, enabled)

## Whether `modifier_id` may roll in `mode_id`: the mode's table bans win,
## then the host's per-mode switches.
func is_modifier_enabled(mode_id: String, modifier_id: String) -> bool:
	if _game_modes().bans_modifier(mode_id, modifier_id):
		return false
	return not (disabled_modifiers.get(mode_id, PackedStringArray()) as PackedStringArray).has(modifier_id)

## Returns false (changing nothing) for a modifier the mode's table bans:
## those stay locked off. Switching every modifier off is allowed; then none
## rolls.
func set_modifier_enabled(mode_id: String, modifier_id: String, enabled: bool) -> bool:
	if _game_modes().bans_modifier(mode_id, modifier_id):
		return false
	var list := PackedStringArray(disabled_modifiers.get(mode_id, PackedStringArray()))
	var index: int = list.find(modifier_id)
	if enabled and index != -1:
		list.remove_at(index)
	elif not enabled and index == -1:
		list.append(modifier_id)
	if list.is_empty():
		disabled_modifiers.erase(mode_id)
	else:
		disabled_modifiers[mode_id] = list
	save_settings()
	return true

# Loaded on use: GameModes reaches back to the settings through its modes.
func _game_modes() -> GDScript:
	return load("res://scripts/GameModes.gd") as GDScript

func set_stock_lives(lives: int) -> void:
	stock_lives = clampi(lives, STOCK_MIN_LIVES, STOCK_MAX_LIVES)
	save_settings()

## Returns false (changing nothing) for a limit that is not on offer.
func set_stock_time_limit(seconds: int) -> bool:
	if not STOCK_TIME_LIMITS.has(seconds):
		return false
	stock_time_limit = seconds
	save_settings()
	return true

## Returns false (changing nothing) for a name that is neither "" (Random)
## nor a known stage.
func set_stock_stage(stage_name: String) -> bool:
	if stage_name != "" and not known_stages.has(stage_name):
		return false
	stock_stage = stage_name
	save_settings()
	return true

func set_resolution(size: Vector2i) -> void:
	resolution = size
	save_settings()

func set_share_stats(on: bool) -> void:
	share_stats = on
	save_settings()

func mark_telemetry_notice_seen() -> void:
	telemetry_notice_seen = true
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
		disabled_modifiers = {}
		var stored: Variant = config.get_value(SECTION, "disabled_modifiers", {})
		if stored is Dictionary:
			for mode_id: Variant in stored:
				var ids := PackedStringArray(stored[mode_id])
				if not ids.is_empty():
					disabled_modifiers[str(mode_id)] = ids
		share_stats = bool(config.get_value(SECTION, "share_stats", true))
		telemetry_notice_seen = bool(config.get_value(SECTION, "telemetry_notice_seen", false))
		var lives: Variant = config.get_value(SECTION, "stock_lives", 3)
		stock_lives = clampi(int(lives), STOCK_MIN_LIVES, STOCK_MAX_LIVES) if lives is int else 3
		var limit: Variant = config.get_value(SECTION, "stock_time_limit", 480)
		stock_time_limit = int(limit) if limit is int and STOCK_TIME_LIMITS.has(int(limit)) else 480
		stock_stage = str(config.get_value(SECTION, "stock_stage", ""))
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
	config.set_value(SECTION, "disabled_modifiers", disabled_modifiers)
	config.set_value(SECTION, "share_stats", share_stats)
	config.set_value(SECTION, "telemetry_notice_seen", telemetry_notice_seen)
	config.set_value(SECTION, "stock_lives", stock_lives)
	config.set_value(SECTION, "stock_time_limit", stock_time_limit)
	config.set_value(SECTION, "stock_stage", stock_stage)
	err = config.save(path)
	if err != OK:
		push_warning("HostSettings: could not save to %s (%s)" % [path, error_string(err)])
