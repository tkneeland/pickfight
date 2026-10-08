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
const CLASSIC_ID: String = "classic"
## The stages only Soccer and Capture the Flag play (#646, #647); every other
## mode uses the rest.
const SOCCER_STAGES: PackedStringArray = ["Pitch", "Dunes", "Cage"]
const CTF_STAGES: PackedStringArray = ["Bastion", "Stronghold"]
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
## Stage on/off is per game mode (#647): `{mode id: PackedStringArray of the
## stages switched off}`. Modes absent here use their default (everything on,
## except Stock, whose list is `stock_stages_on`). Ids are the `GameModes` ids,
## with "classic" for the no-mode rotation.
var disabled_stages_by_mode: Dictionary = {}
## Stock's stages are a whitelist (#375, #647): empty means the default, the
## competitive-flagged stages (every stage when none is flagged).
var stock_stages_on: PackedStringArray = []
## Stored in `stock_stages_on` when Stock's stages are all off: an empty list
## means the default, so "none" needs a mark that names no stage (#647).
const NONE_MARK: String = "-"
## Stage names flagged competitive, set by `StageRotation` next to `known_stages`.
var competitive_stages: PackedStringArray = []
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
## Match targets for the team modes (#544): goals to win a Soccer round
## and captures to win a Capture the Flag round (1-10 each).
const MIN_MODE_TARGET: int = 1
const MAX_MODE_TARGET: int = 10
var soccer_goals: int = 3
var ctf_captures: int = 2
## The host PC seat's saved look (#441): {"hat", "eyes", "color"} as
## `CosmeticsPicker.clean_pick` cleans it, put on whenever the seat is claimed.
var cosmetic_pick: Dictionary = {"hat": "none", "eyes": "round", "color": -1}
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
		if PickupWeaponsScript.RETIRED_PATHS.has(weapon_path):  # retired from rotation (#642)
			continue
		if DemoBuildScript.weapon_in_slice(name_of(weapon_path)):  # the demo's slice (#361)
			names.append(name_of(weapon_path))
	return names

## The classic list (#294's global switch, kept for old call sites).
func is_stage_enabled(stage_name: String) -> bool:
	return is_stage_enabled_for(CLASSIC_ID, stage_name)

static func mode_key(mode_id: String) -> String:
	return CLASSIC_ID if mode_id == "" else mode_id

## The ids the Stages & Rules screens (PC and phone) edit: Classic as "classic"
## (which `mode_key` also reads from the round's ""), plus the modes with lists.
const KNOWN_MODES: PackedStringArray = ["classic", "king_of_the_hill", "sudden_death", "stock", "soccer", "capture_the_flag"]

static func is_known_mode(mode_id: String) -> bool:
	return KNOWN_MODES.has(mode_key(mode_id))

## `GameModes`' own id for a settings key: Classic is "" there.
static func game_mode_id(mode_id: String) -> String:
	return "" if mode_id == CLASSIC_ID else mode_id

## The stages `mode_id` can use (#647): Soccer's pitches, Capture the Flag's
## halls, or for every other mode the general rotation (known stages minus
## those five).
func stages_for_mode(mode_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var key: String = mode_key(mode_id)
	for stage_name: String in known_stages:
		var own: bool = SOCCER_STAGES.has(stage_name) or CTF_STAGES.has(stage_name)
		var fits: bool = not own
		if key == "soccer":
			fits = SOCCER_STAGES.has(stage_name)
		elif key == "capture_the_flag":
			fits = CTF_STAGES.has(stage_name)
		if fits:
			out.append(stage_name)
	return out

func _stock_on_list() -> PackedStringArray:
	var pool := stages_for_mode("stock")
	var on := PackedStringArray()
	for stage_name: String in stock_stages_on:
		if pool.has(stage_name):
			on.append(stage_name)
	if not on.is_empty() or stock_stages_on == PackedStringArray([NONE_MARK]):
		return on  # a list holding only NONE_MARK is "all off" (#647)
	for stage_name: String in pool:
		if competitive_stages.has(stage_name):
			on.append(stage_name)
	return on if not on.is_empty() else pool

func is_stage_enabled_for(mode_id: String, stage_name: String) -> bool:
	if not DemoBuildScript.stage_in_slice(stage_name) or not stages_for_mode(mode_id).has(stage_name):
		return false
	var key: String = mode_key(mode_id)
	if key == "stock":
		return _stock_on_list().has(stage_name)
	return not (disabled_stages_by_mode.get(key, PackedStringArray()) as PackedStringArray).has(stage_name)

## The stages `mode_id` plays, in rotation order. Never empty while the mode has
## a stage: with all of them off, every stage of that mode.
func enabled_stages_for(mode_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for stage_name: String in stages_for_mode(mode_id):
		if is_stage_enabled_for(mode_id, stage_name):
			out.append(stage_name)
	return out if not out.is_empty() else stages_for_mode(mode_id)

## The stages `mode_id` has switched on, with no fallback: empty when the host
## switched them all off (#647). The rotation draws from `enabled_stages_for`.
func on_stages_for(mode_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for stage_name: String in stages_for_mode(mode_id):
		if is_stage_enabled_for(mode_id, stage_name):
			out.append(stage_name)
	return out

## Returns false (changing nothing) for a stage the mode cannot use, a stage
## outside the demo's slice switched on, or when this would switch off the
## mode's last enabled stage.
func set_stage_enabled_for(mode_id: String, stage_name: String, on: bool) -> bool:
	var pool := stages_for_mode(mode_id)
	if not pool.has(stage_name) or (on and not DemoBuildScript.stage_in_slice(stage_name)):
		return false
	var key: String = mode_key(mode_id)
	if key == "stock":
		var list := _stock_on_list()
		var index: int = list.find(stage_name)
		if on and index == -1:
			list.append(stage_name)
		elif not on and index != -1:
			if list.size() == 1:
				return false
			list.remove_at(index)
		stock_stages_on = list
		save_settings()
		return true
	var disabled := PackedStringArray(disabled_stages_by_mode.get(key, PackedStringArray()))
	if not _set_enabled(disabled, pool, stage_name, on):
		return false
	_store_disabled(key, disabled)
	return true

## Switches every stage of the mode on or off. Off leaves none on (#647: the
## phone then blocks Done); `enabled_stages_for` still falls back to all of
## them, so a round never lacks a stage.
func set_all_stages_for(mode_id: String, on: bool) -> void:
	var pool := stages_for_mode(mode_id)
	var key: String = mode_key(mode_id)
	if key == "stock":
		var list := PackedStringArray()
		for stage_name: String in pool:
			if on and DemoBuildScript.stage_in_slice(stage_name):
				list.append(stage_name)
		if not on:
			list.append(NONE_MARK)
		stock_stages_on = list
		save_settings()
		return
	var disabled := PackedStringArray()
	if not on:
		disabled = pool.duplicate()
	_store_disabled(key, disabled)

func _store_disabled(key: String, disabled: PackedStringArray) -> void:
	disabled_stages_by_mode[key] = disabled
	save_settings()

func is_weapon_enabled(weapon_name: String) -> bool:
	return not disabled_weapons.has(weapon_name) and DemoBuildScript.weapon_in_slice(weapon_name)

## The classic list; false (changing nothing) when this would switch off the
## last enabled stage.
func set_stage_enabled(stage_name: String, enabled: bool) -> bool:
	return set_stage_enabled_for(CLASSIC_ID, stage_name, enabled)

## Returns false (changing nothing) when this would switch off the last
## enabled pickup weapon.
func set_weapon_enabled(weapon_name: String, enabled: bool) -> bool:
	if enabled and not DemoBuildScript.weapon_in_slice(weapon_name):
		return false  # outside the demo's slice (#361)
	return _set_enabled(disabled_weapons, known_weapons(), weapon_name, enabled)

## Whether `modifier_id` may roll in `mode_id`: the mode's table bans win,
## then the host's per-mode switches.
func is_modifier_enabled(mode_id: String, modifier_id: String) -> bool:
	if _game_modes().bans_modifier(game_mode_id(mode_id), modifier_id):
		return false
	return not (disabled_modifiers.get(mode_key(mode_id), PackedStringArray()) as PackedStringArray).has(modifier_id)

## Returns false (changing nothing) for a modifier the mode's table bans:
## those stay locked off. Switching every modifier off is allowed; then none
## rolls.
func set_modifier_enabled(mode_id: String, modifier_id: String, enabled: bool) -> bool:
	if _game_modes().bans_modifier(game_mode_id(mode_id), modifier_id):
		return false
	mode_id = mode_key(mode_id)
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

func set_soccer_goals(goals: int) -> void:
	soccer_goals = clampi(goals, MIN_MODE_TARGET, MAX_MODE_TARGET)
	save_settings()

func set_ctf_captures(captures: int) -> void:
	ctf_captures = clampi(captures, MIN_MODE_TARGET, MAX_MODE_TARGET)
	save_settings()

## Returns false (changing nothing) for a limit that is not on offer.
func set_stock_time_limit(seconds: int) -> bool:
	if not STOCK_TIME_LIMITS.has(seconds):
		return false
	stock_time_limit = seconds
	save_settings()
	return true

## The old single Stock pick (#375): that stage only, or "" for the defaults.
## Returns false (changing nothing) for a name that is neither "" nor a Stock stage.
func set_stock_stage(stage_name: String) -> bool:
	if stage_name != "" and not stages_for_mode("stock").has(stage_name):
		return false
	stock_stages_on = PackedStringArray([stage_name]) if stage_name != "" else PackedStringArray()
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

## Saves the host PC seat's pick (#441), cleaned.
func set_cosmetic_pick(pick: Dictionary) -> void:
	cosmetic_pick = (load("res://scripts/CosmeticsPicker.gd") as GDScript).clean_pick(pick)
	save_settings()

## A stored string list, or empty when it is any other type (#609).
static func _strings(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if v is PackedStringArray:
		return v
	if v is Array:
		for item: Variant in v:
			if item is String:
				out.append(item)
	return out

## Per-mode stage lists (#647). A file from before them has one global
## `disabled_stages`, which seeds every general mode's list, and a `stock_stage`
## pick, which becomes "only that stage on" for Stock.
func _load_stage_lists(config: ConfigFile) -> void:
	disabled_stages_by_mode = {}
	stock_stages_on = PackedStringArray()
	var stored: Variant = config.get_value(SECTION, "stage_lists", "none")
	if stored is Dictionary:
		for mode_id: Variant in stored:
			disabled_stages_by_mode[mode_key(str(mode_id))] = _strings(stored[mode_id])
		stock_stages_on = _strings(config.get_value(SECTION, "stock_stages_on", PackedStringArray()))
		return
	var old := _strings(config.get_value(SECTION, "disabled_stages", PackedStringArray()))
	if not old.is_empty():
		for mode_id: String in [CLASSIC_ID, "king_of_the_hill", "sudden_death", "hot_potato"]:
			disabled_stages_by_mode[mode_id] = old.duplicate()
	var pick: String = str(config.get_value(SECTION, "stock_stage", ""))
	if pick != "":
		stock_stages_on = PackedStringArray([pick])

func load_settings() -> void:
	var config := ConfigFile.new()
	var err: Error = config.load(path)
	if err == OK:
		var size: Variant = config.get_value(SECTION, "resolution", Vector2i.ZERO)
		resolution = size if size is Vector2i and size.x > 0 and size.y > 0 else Vector2i.ZERO
		_load_stage_lists(config)
		disabled_weapons = _strings(config.get_value(SECTION, "disabled_weapons", PackedStringArray()))
		game_mode = str(config.get_value(SECTION, "game_mode", ""))
		if game_mode != "" and not _game_modes().selectable(game_mode):  # a retired mode (#645)
			game_mode = ""
		disabled_modifiers = {}
		var stored: Variant = config.get_value(SECTION, "disabled_modifiers", {})
		if stored is Dictionary:
			for mode_id: Variant in stored:
				var ids := _strings(stored[mode_id])
				if not ids.is_empty():
					disabled_modifiers[mode_key(str(mode_id))] = ids
		var share: Variant = config.get_value(SECTION, "share_stats", true)
		share_stats = share if share is bool else true
		telemetry_notice_seen = bool(config.get_value(SECTION, "telemetry_notice_seen", false))
		var lives: Variant = config.get_value(SECTION, "stock_lives", 3)
		stock_lives = clampi(int(lives), STOCK_MIN_LIVES, STOCK_MAX_LIVES) if lives is int else 3
		var goals: Variant = config.get_value(SECTION, "soccer_goals", 3)
		soccer_goals = clampi(int(goals), MIN_MODE_TARGET, MAX_MODE_TARGET) if goals is int else 3
		var captures: Variant = config.get_value(SECTION, "ctf_captures", 2)
		ctf_captures = clampi(int(captures), MIN_MODE_TARGET, MAX_MODE_TARGET) if captures is int else 2
		var limit: Variant = config.get_value(SECTION, "stock_time_limit", 480)
		stock_time_limit = int(limit) if limit is int and STOCK_TIME_LIMITS.has(int(limit)) else 480
		cosmetic_pick = (load("res://scripts/CosmeticsPicker.gd") as GDScript).read_pick(config, SECTION)
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
	config.set_value(SECTION, "stage_lists", disabled_stages_by_mode)
	config.set_value(SECTION, "stock_stages_on", stock_stages_on)
	config.set_value(SECTION, "disabled_weapons", disabled_weapons)
	config.set_value(SECTION, "game_mode", game_mode)
	config.set_value(SECTION, "disabled_modifiers", disabled_modifiers)
	config.set_value(SECTION, "share_stats", share_stats)
	config.set_value(SECTION, "telemetry_notice_seen", telemetry_notice_seen)
	config.set_value(SECTION, "stock_lives", stock_lives)
	config.set_value(SECTION, "soccer_goals", soccer_goals)
	config.set_value(SECTION, "ctf_captures", ctf_captures)
	config.set_value(SECTION, "stock_time_limit", stock_time_limit)
	(load("res://scripts/CosmeticsPicker.gd") as GDScript).write_pick(config, SECTION, cosmetic_pick)
	err = config.save(path)
	if err != OK:
		push_warning("HostSettings: could not save to %s (%s)" % [path, error_string(err)])
