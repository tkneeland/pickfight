extends Node

## Steam achievements (issue #689): the 18 unlocks, the lifetime progress some
## of them need, and the one place that hands them to Steam. An autoload beside
## `SteamPlatform`, reached by path, never by `class_name`.
##
## `RoundManager` reports plain events (a KO, a round won, a goal...) and this
## script decides what each one earns, so the rules live here and not scattered
## through the game. Who earns it: any HUMAN seat's event credits the host
## PC's achievements (phones, pads, the host seat, online remote seats); a bot
## never credits. In Solo everything counts except Untouchable and Last Life,
## which are wins against bots. When the credited seat is an Online PC client,
## the host also tells that client (`ControllerServer.send_achievement`), whose
## own copy of this autoload unlocks it locally.
##
## `unlock()` is idempotent; the first time it records the id, tells Steam
## (`SteamPlatform.set_achievement` + `store_stats`, both no-ops without
## Steam) and emits `unlocked`. Builds without the Steam overlay get a small
## toast on the host screen instead. State lives in `user://achievements.cfg`
## unless `persist` is off, which scenarios (a `-s` run) switch off.

signal unlocked(id: String)

const SAVE_PATH: String = "user://achievements.cfg"
const SECTION: String = "achievements"
## A KO counts for Boo! and Gone Fishing when the shove or reel was this recent.
const WINDOW_MSEC: int = 3000
const HAT_TRICK_KOS: int = 3
const TOOL_BELT_WEAPONS: int = 8
const PARTY_SIZE: int = 8
const TOAST_SEC: float = 4.0
const PICKAXE: String = "pickaxe"
const STOCK: String = "stock"

const PickupWeaponsScript := preload("res://scripts/PickupWeapons.gd")
const HostSettingsScript := preload("res://scripts/HostSettings.gd")

## The ids, in the order the docs list them. API name is "ACH_" + upper case.
const IDS: PackedStringArray = [
	"first_swing", "pick_your_fight", "rock_bottom", "lava_lamp", "tool_belt", "arsenal",
	"old_faithful", "hat_trick", "untouchable", "back_of_the_net", "flag_runner",
	"king_of_the_hill", "last_life", "overtime", "party_of_eight", "boo", "gone_fishing",
	"world_tour",
]
## Wins against bots do not count in Solo.
const SOLO_EXCLUDED: PackedStringArray = ["untouchable", "last_life"]

## Whether to save to `path`; a `-s` run switches it off.
var persist: bool = true
var path: String = SAVE_PATH
## Whether an unlock shows a toast (never when Steam's own overlay is up).
var toast_enabled: bool = true
## The roster the events came from: tells bots from people, Solo from the rest
## and carries `send_achievement`. `RoundManager` sets it before each event.
var cs: Object = null

var _unlocked: Dictionary = {}
var _weapons_held: Dictionary = {}
var _arsenal: Dictionary = {}
var _stages_played: Dictionary = {}
## Per round, never saved: slot -> KOs, and the slots that took damage.
var _round_kos: Dictionary = {}
var _hurt: Dictionary = {}

var _toast_layer: CanvasLayer = null
var _toast_label: Label = null
var _toast_timer: Timer = null
var _toast_queue: Array[String] = []

func _ready() -> void:
	if get_tree() != null and get_tree().get_script() != null:
		persist = false  # a `-s` run (scenarios) never touches the owner's file
	if persist:
		load_from_disk()

# --- Names -----------------------------------------------------------------------

static func api_name(id: String) -> String:
	return "ACH_" + id.to_upper()

func display_name(id: String) -> String:
	return tr("ACH_%s_NAME" % id.to_upper())

func description(id: String) -> String:
	return tr("ACH_%s_DESC" % id.to_upper())

# --- State -----------------------------------------------------------------------

func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)

func unlocked_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in IDS:
		if _unlocked.has(id):
			out.append(id)
	return out

## Lifetime progress, for scenarios and the docs: set sizes.
func progress() -> Dictionary:
	return {"weapons_held": _weapons_held.size(), "arsenal": _arsenal.size(), "stages_played": _stages_played.size()}

## Forget everything, in memory only: a scenario starts from a clean slate and
## nothing it does reaches disk.
func reset_for_test() -> void:
	persist = false
	toast_enabled = false
	cs = null
	_unlocked.clear()
	_weapons_held.clear()
	_arsenal.clear()
	_stages_played.clear()
	_round_kos.clear()
	_hurt.clear()
	_toast_queue.clear()

## Unlock `id` once. True only the first time. Tells Steam, the toast and
## whoever listens to `unlocked`.
func unlock(id: String) -> bool:
	if not IDS.has(id) or _unlocked.has(id):
		return false
	_unlocked[id] = true
	_save()
	var steam: Node = get_node_or_null(^"/root/SteamPlatform")
	if steam != null:
		steam.set_achievement(api_name(id))
		steam.store_stats()
	unlocked.emit(id)
	_show_toast(id)
	return true

# --- Who earns it ----------------------------------------------------------------

func _is_bot(slot: int) -> bool:
	return is_instance_valid(cs) and cs.has_method("is_virtual") and cs.is_virtual(slot)

func _solo() -> bool:
	return is_instance_valid(cs) and cs.has_method("match_kind") and cs.match_kind() == "solo"

func _humans(slots: Array) -> Array[int]:
	var out: Array[int] = []
	for slot: int in slots:
		if slot >= 0 and not _is_bot(slot):
			out.append(slot)
	return out

## `slot`'s event earns `id`: the host PC unlocks it, and a PC client in that
## seat is told to unlock it too. A bot's event earns nothing, and Solo drops
## the wins against bots. True when this unlocked it on the host just now.
func credit(slot: int, id: String) -> bool:
	if slot < 0 or _is_bot(slot):
		return false
	if _solo() and SOLO_EXCLUDED.has(id):
		return false
	var fresh: bool = unlock(id)
	if is_instance_valid(cs) and cs.has_method("send_achievement"):
		cs.send_achievement(slot, id)
	return fresh

func credit_all(slots: Array, id: String) -> void:
	for slot: int in slots:
		credit(slot, id)

# --- Events from the round loop --------------------------------------------------

## A match began with `slots` seated.
func on_match_started(slots: Array) -> void:
	var humans: Array[int] = _humans(slots)
	if humans.size() >= PARTY_SIZE:
		credit_all(humans, "party_of_eight")

## A round began: `weapons` is slot -> weapon id each player enters with.
func on_round_started(in_round: Array, stage_name: String, weapons: Dictionary) -> void:
	_round_kos.clear()
	_hurt.clear()
	var humans: Array[int] = _humans(in_round)
	if humans.is_empty():
		return
	for slot: int in humans:
		on_weapon_held(slot, str(weapons.get(slot, "")))
	if stage_name == "":
		return
	_stages_played[stage_name] = true
	_save()
	var rotation: PackedStringArray = HostSettingsScript.shared().known_stages
	if rotation.is_empty():
		return
	for stage: String in rotation:
		if not _stages_played.has(stage):
			return
	credit_all(humans, "world_tour")

## `slot` is now holding `weapon_id` (a pickup, or the one it entered with).
func on_weapon_held(slot: int, weapon_id: String) -> void:
	if weapon_id == "" or _is_bot(slot):
		return
	if not _weapons_held.has(weapon_id):
		_weapons_held[weapon_id] = true
		_save()
	if _weapons_held.size() >= TOOL_BELT_WEAPONS:
		credit(slot, "tool_belt")

## `victim` took `amount` damage from anything, hazards included.
func on_damage(victim: int, amount: float) -> void:
	if amount > 0.0:
		_hurt[victim] = true

## `victim` was eliminated; `killer` is the credited slot or -1. `ctx`:
## hazard ("" or lava / damage / rock / meteor), reeler + reel_age_msec,
## booer + boo_age_msec.
func on_ko(victim: int, killer: int, ctx: Dictionary) -> void:
	var hazard: String = str(ctx.get("hazard", ""))
	if hazard != "":
		credit(victim, "rock_bottom")
		var reeler: int = int(ctx.get("reeler", -1))
		if reeler >= 0 and reeler != victim and int(ctx.get("reel_age_msec", WINDOW_MSEC + 1)) <= WINDOW_MSEC:
			credit(reeler, "gone_fishing")
		if hazard == "lava" and killer >= 0 and killer != victim:
			credit(killer, "lava_lamp")
	var booer: int = int(ctx.get("booer", -1))
	if booer >= 0 and booer != victim and int(ctx.get("boo_age_msec", WINDOW_MSEC + 1)) <= WINDOW_MSEC:
		credit(booer, "boo")
	if killer >= 0 and killer != victim:
		_round_kos[killer] = int(_round_kos.get(killer, 0)) + 1
		if int(_round_kos[killer]) >= HAT_TRICK_KOS:
			credit(killer, "hat_trick")

## A round finished (not abandoned, not a kick). `winners` are the slots that
## took it; `info`: weapons / damage / lives (slot -> value), mode, hill (the
## hill decided it), overtime (a Sudden Death decided it), stock_lives.
func on_round_finished(in_round: Array, winners: Array, info: Dictionary) -> void:
	credit_all(_humans(in_round), "first_swing")
	var weapons: Dictionary = info.get("weapons", {})
	var damage: Dictionary = info.get("damage", {})
	var lives: Dictionary = info.get("lives", {})
	for slot: int in _humans(winners):
		var weapon: String = str(weapons.get(slot, ""))
		if weapon == PICKAXE:
			credit(slot, "old_faithful")
		if _pickup_weapon_ids().has(weapon):
			_arsenal[weapon] = true
			_save()
			if _arsenal_complete():
				credit(slot, "arsenal")
		if not _hurt.has(slot) and float(damage.get(slot, 0.0)) <= 0.0:
			credit(slot, "untouchable")
		if bool(info.get("hill", false)):
			credit(slot, "king_of_the_hill")
		if bool(info.get("overtime", false)):
			credit(slot, "overtime")
		if str(info.get("mode", "")) == STOCK and int(info.get("stock_lives", 1)) > 1 and int(lives.get(slot, -1)) == 1:
			credit(slot, "last_life")

## The match was won by `winners` (a slot, or a whole team).
func on_match_won(winners: Array) -> void:
	credit_all(_humans(winners), "pick_your_fight")

func on_goal(scorer: int) -> void:
	credit(scorer, "back_of_the_net")

func on_capture(scorer: int) -> void:
	credit(scorer, "flag_runner")

func _pickup_weapon_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for weapon_path: String in PickupWeaponsScript.WEAPON_PATHS:
		if not PickupWeaponsScript.RETIRED_PATHS.has(weapon_path):
			out.append(weapon_path.get_file().get_basename())
	return out

func _arsenal_complete() -> bool:
	for id: String in _pickup_weapon_ids():
		if not _arsenal.has(id):
			return false
	return true

# --- Toast -----------------------------------------------------------------------

func _steam_running() -> bool:
	var steam: Node = get_node_or_null(^"/root/SteamPlatform")
	return steam != null and bool(steam.get("available"))

## The toast's current text, or "" when none is up.
func toast_text() -> String:
	return _toast_label.text if _toast_label != null and _toast_layer.visible else ""

func _show_toast(id: String) -> void:
	if not toast_enabled or _steam_running() or not is_inside_tree():
		return
	_toast_queue.append(id)
	if _toast_layer == null or not _toast_layer.visible:
		_next_toast()

func _next_toast() -> void:
	if _toast_queue.is_empty():
		if _toast_layer != null:
			_toast_layer.visible = false
		return
	_build_toast()
	_toast_label.text = tr("ACH_TOAST") % display_name(_toast_queue.pop_front())
	_toast_layer.visible = true
	_toast_timer.start(TOAST_SEC)

func _build_toast() -> void:
	if _toast_layer != null:
		return
	_toast_layer = CanvasLayer.new()
	_toast_layer.name = "AchievementToast"
	_toast_layer.layer = 90
	_toast_layer.visible = false
	add_child(_toast_layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 24)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(panel)
	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", 24)
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_toast_label)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(_next_toast)
	add_child(_toast_timer)

# --- Saving ----------------------------------------------------------------------

## Read `path` into memory (what `_ready` does when persistence is on).
func load_from_disk() -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	for id: String in PackedStringArray(config.get_value(SECTION, "unlocked", PackedStringArray())):
		if IDS.has(id):
			_unlocked[id] = true
	for weapon: String in PackedStringArray(config.get_value(SECTION, "weapons_held", PackedStringArray())):
		_weapons_held[weapon] = true
	for weapon: String in PackedStringArray(config.get_value(SECTION, "arsenal", PackedStringArray())):
		_arsenal[weapon] = true
	for stage: String in PackedStringArray(config.get_value(SECTION, "stages_played", PackedStringArray())):
		_stages_played[stage] = true

func _save() -> void:
	if not persist:
		return
	var config := ConfigFile.new()
	config.set_value(SECTION, "unlocked", PackedStringArray(_unlocked.keys()))
	config.set_value(SECTION, "weapons_held", PackedStringArray(_weapons_held.keys()))
	config.set_value(SECTION, "arsenal", PackedStringArray(_arsenal.keys()))
	config.set_value(SECTION, "stages_played", PackedStringArray(_stages_played.keys()))
	config.save(path)
