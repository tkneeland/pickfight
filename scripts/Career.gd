extends RefCounted

## Lifetime ("career") stats kept on the player's own device (#503). The host
## never stores them: at each round end and at the victory screen it sends the
## seat its own deltas, `{"t":"career","d":{...}}`, and the device adds them to
## its totals. Phones keep theirs in localStorage; the Online PC client keeps
## them in `user://career.cfg` through this script. Gamepad seats, the host's
## own seat and bots get nothing.
##
## Delta / totals shape: {"matches", "match_wins", "round_wins", "kos",
## "self_kos"} (ints) and "weapons" (weapon name -> rounds held).

const FIELDS: PackedStringArray = ["matches", "match_wins", "round_wins", "kos", "self_kos"]
const SECTION: String = "career"
const DEFAULT_PATH: String = "user://career.cfg"
## One message never carries more than this per number, and a stored total is
## capped, so a junk frame cannot wreck the line.
const MAX_DELTA: int = 1000
const MAX_TOTAL: int = 999999
const MAX_WEAPONS: int = 40
const MAX_WEAPON_NAME: int = 24

## A clean copy of a received delta: known fields only, whole non-negative
## numbers, capped. Anything that is not a Dictionary reads as empty.
static func clean(raw: Variant, cap: int = MAX_DELTA) -> Dictionary:
	var out: Dictionary = {}
	if not raw is Dictionary:
		return out
	for field: String in FIELDS:
		var n: int = _count(raw.get(field), cap)
		if n > 0:
			out[field] = n
	var weapons: Dictionary = {}
	var given: Variant = raw.get("weapons")
	if given is Dictionary:
		for key: Variant in given.keys():
			if weapons.size() >= MAX_WEAPONS:
				break
			if not key is String or (key as String).is_empty() or (key as String).length() > MAX_WEAPON_NAME:
				continue
			var rounds: int = _count(given[key], cap)
			if rounds > 0:
				weapons[key] = rounds
	if not weapons.is_empty():
		out["weapons"] = weapons
	return out

static func _count(value: Variant, cap: int) -> int:
	if not (value is int or value is float) or not is_finite(float(value)):
		return 0
	return clampi(int(value), 0, cap)

## `totals` plus the cleaned `delta`.
static func add(totals: Dictionary, delta: Variant, cap: int = MAX_DELTA) -> Dictionary:
	var d: Dictionary = clean(delta, cap)
	var out: Dictionary = {}
	for field: String in FIELDS:
		out[field] = mini(int(totals.get(field, 0)) + int(d.get(field, 0)), MAX_TOTAL)
	var weapons: Dictionary = (totals.get("weapons", {}) as Dictionary).duplicate()
	var more: Dictionary = d.get("weapons", {})
	for key: String in more.keys():
		if weapons.has(key) or weapons.size() < MAX_WEAPONS:
			weapons[key] = mini(int(weapons.get(key, 0)) + int(more[key]), MAX_TOTAL)
	out["weapons"] = weapons
	return out

## The weapon held for the most rounds, "" for none (first listed on a tie).
static func favourite(totals: Dictionary) -> String:
	var best: String = ""
	var weapons: Dictionary = totals.get("weapons", {})
	for key: String in weapons.keys():
		if best == "" or int(weapons[key]) > int(weapons[best]):
			best = key
	return best

static func load_totals(path: String) -> Dictionary:
	var out: Dictionary = {}
	if path.is_empty():
		return add(out, {})
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return add(out, {})
	var stored: Dictionary = {}
	for field: String in FIELDS:
		stored[field] = config.get_value(SECTION, field, 0)
	stored["weapons"] = config.get_value(SECTION, "weapons", {})
	return add({}, stored, MAX_TOTAL)

static func save_totals(path: String, totals: Dictionary) -> void:
	if path.is_empty():
		return
	var config := ConfigFile.new()
	config.load(path) # keep any other section
	for field: String in FIELDS:
		config.set_value(SECTION, field, int(totals.get(field, 0)))
	config.set_value(SECTION, "weapons", totals.get("weapons", {}))
	config.save(path)
