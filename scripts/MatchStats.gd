extends RefCounted

## Per-match numbers behind the kill feed and the match awards (issue #148).
## Pure bookkeeping: no nodes, no clock of its own. `RoundManager` feeds it
## hits and eliminations with the time they happened (game time from
## `GameClock.gd` in the game, #182; any number a scenario likes), and asks
## it who gets a KO and, at match end, who gets which award. Nothing is
## persisted: `begin_match()` wipes the lot, `forget_slot()` one slot's share.
## `shift()` moves the running clocks past a pause for a caller whose clock
## keeps running through one; the game's clock stops, so it never needs it.
##
## KO credit: whoever last hit the victim within `KO_CREDIT_WINDOW_MSEC` of the
## elimination gets the KO; with no such hit it is a self-KO (a ring-out, the
## lava, a falling rock). A hit counts whether or not it did damage -- a 0-damage
## swing still shoves, and a shove off the edge is a KO. A victim's own report
## (a falling rock reports on the victim's own `strike_landed`) is not a hit.

## How recent the last hit must be for its attacker to get the KO.
const KO_CREDIT_WINDOW_MSEC: int = 3000
## The balance log rotates to `<name>.1` past this size (#609).
const LOG_MAX_BYTES: int = 1000000
## A second KO by the same player within this of their last is a multi-KO.
const MULTI_KO_WINDOW_MSEC: int = 3000

## Award categories, one award each at most.
const COMBAT: String = "COMBAT"
const CLUMSY: String = "CLUMSY"
const SURVIVOR: String = "SURVIVOR"
const AIRBORNE: String = "AIRBORNE"

## The shortest airtime that earns the award (issue #337).
const AIRTIME_MIN_MSEC: int = 1000
const COLLECTOR: String = "COLLECTOR"
## Mode-specific award categories (issue #355), each given only in its mode.
const HILL: String = "HILL"
const TAGGER: String = "TAGGER"
const LIVES: String = "LIVES"
const SCORER: String = "SCORER"
const CAPTURER: String = "CAPTURER"
## The shortest hill hold (seconds) that earns Longest Hold.
const HILL_MIN_SEC: float = 0.5
const GameModesScript := preload("res://scripts/GameModes.gd")

## slot -> number, created on first use so any roster size works.
var kos: Dictionary = {}
var self_kos: Dictionary = {}
var deaths: Dictionary = {}
var damage_dealt: Dictionary = {}
var damage_taken: Dictionary = {}
## Balance log (issue #316): weapon id -> damage / landed hits by REAL players
## this match. Bots and self-hits are left out. Written once per match by
## `RoundManager` to `user://balance_stats.jsonl`; local only, tuning only.
var weapon_damage: Dictionary = {}
var weapon_hits: Dictionary = {}
## Telemetry (issue #372): weapon id -> KOs credited with that weapon's last
## hit, and slot -> weapon id -> landed hits, to name the winner's weapon. Real
## players only, like the tallies above; the slot keys never leave the host.
var weapon_kos: Dictionary = {}
var slot_weapon_hits: Dictionary = {}
## Total msec each slot spent alive in rounds this match.
var survival_msec: Dictionary = {}
## Longest continuous stretch (msec) each slot went with no body contact this
## match (issue #337).
var longest_air_msec: Dictionary = {}
## Weapon pickups grabbed this match (issue #325), and per slot which weapon
## (name -> count) -- the favourite is the one grabbed most, first grabbed on a tie.
var pickups: Dictionary = {}
var weapon_grabs: Dictionary = {}
## Mode stats (issue #355), summed over the match's rounds and reported by the
## mode node at the end of each round (`report_stats()` on the mode).
## slot -> seconds held alone in the King of the Hill zone.
var hill_hold_sec: Dictionary = {}
## slot -> Hot Potato tags passed on (damaging hits made while "it").
var tags_passed: Dictionary = {}
## slot -> Stock lives left at the end of each round, summed.
var lives_left: Dictionary = {}
## slot -> Soccer goals scored this match (#402).
var goals: Dictionary = {}
## slot -> Capture the Flag captures this match (#403).
var captures: Dictionary = {}
## Credited KOs this match, for "first blood".
var total_kos: int = 0

## victim slot -> {"attacker": slot, "msec": int} for the last hit taken.
var _last_hit: Dictionary = {}
## killer slot -> [msec of their last KO, run length].
var _streak: Dictionary = {}
## Slots still alive in the current round -> msec they entered it.
var _alive_since: Dictionary = {}
## Slot -> msec its current airborne stretch began.
var _air_since: Dictionary = {}

func begin_match() -> void:
	kos.clear()
	self_kos.clear()
	deaths.clear()
	damage_dealt.clear()
	damage_taken.clear()
	weapon_damage.clear()
	weapon_hits.clear()
	weapon_kos.clear()
	slot_weapon_hits.clear()
	survival_msec.clear()
	pickups.clear()
	weapon_grabs.clear()
	hill_hold_sec.clear()
	tags_passed.clear()
	lives_left.clear()
	goals.clear()
	captures.clear()
	total_kos = 0
	_last_hit.clear()
	_streak.clear()
	_alive_since.clear()
	_air_since.clear()
	longest_air_msec.clear()

func begin_round(slots: Array, now_msec: int) -> void:
	_air_since.clear()
	_last_hit.clear()
	_streak.clear()
	_alive_since.clear()
	for slot: int in slots:
		_alive_since[slot] = now_msec
		survival_msec[slot] = int(survival_msec.get(slot, 0))

## Everyone still standing stops the survival clock here.
func end_round(now_msec: int) -> void:
	_air_since.clear()
	for slot: int in _alive_since.keys():
		_add(survival_msec, slot, now_msec - int(_alive_since[slot]))
	_alive_since.clear()

## `slot` came back from a lost life (Stock, Soccer, Capture the Flag): its
## survival clock runs again from `now_msec` (#521).
func resume_round(slot: int, now_msec: int) -> void:
	_alive_since[slot] = now_msec

## A fresh player took `slot` mid-match (issue #161): nothing the slot's last
## occupant did is theirs, so every entry for it goes -- their numbers, the
## hit they last took or dealt, their streak and their round clock.
func forget_slot(slot: int) -> void:
	for table: Dictionary in [kos, self_kos, deaths, damage_dealt, damage_taken, survival_msec, longest_air_msec, pickups, weapon_grabs, hill_hold_sec, tags_passed, lives_left, goals, captures, _streak, _alive_since, _air_since]:
		table.erase(slot)
	_last_hit.erase(slot)
	slot_weapon_hits.erase(slot)
	for victim: int in _last_hit.keys():
		if int(_last_hit[victim]["attacker"]) == slot:
			_last_hit.erase(victim)

## The game was paused for `msec` (issue #161): every clock still running
## moves on by that much, so a pause neither runs out a KO credit window or a
## multi-KO run nor counts as time alive.
func shift(msec: int) -> void:
	if msec <= 0:
		return
	for victim: int in _last_hit.keys():
		_last_hit[victim]["msec"] = int(_last_hit[victim]["msec"]) + msec
	for killer: int in _streak.keys():
		_streak[killer][0] = int(_streak[killer][0]) + msec
	for slot: int in _alive_since.keys():
		_alive_since[slot] = int(_alive_since[slot]) + msec
	for slot: int in _air_since.keys():
		_air_since[slot] = int(_air_since[slot]) + msec

## One sample of whether `slot` is touching nothing (issue #337), taken each
## frame while it is alive in a round. Cheap: a start time per airborne slot and
## a best per slot. The stretch ends on the first grounded sample, the slot's
## elimination or the round's end.
func note_air(slot: int, airborne: bool, now_msec: int) -> void:
	if not airborne:
		_air_since.erase(slot)
		return
	if not _air_since.has(slot):
		_air_since[slot] = now_msec
	longest_air_msec[slot] = maxi(int(longest_air_msec.get(slot, 0)), now_msec - int(_air_since[slot]))

## `weapon` names the attacker's weapon and `real` is false for a bot; only a
## real player's damaging hit with a named weapon joins the balance tallies.
func record_hit(attacker: int, victim: int, amount: float, now_msec: int, weapon: String = "", real: bool = true) -> void:
	if attacker < 0 or victim < 0 or attacker == victim:
		return
	_last_hit[victim] = {"attacker": attacker, "msec": now_msec, "weapon": weapon if real else ""}
	if amount > 0.0:
		if real and weapon != "":
			_add(weapon_damage, weapon, amount)
			_add(weapon_hits, weapon, 1)
			var by_weapon: Dictionary = slot_weapon_hits.get(attacker, {})
			by_weapon[weapon] = int(by_weapon.get(weapon, 0)) + 1
			slot_weapon_hits[attacker] = by_weapon
		_add(damage_dealt, attacker, amount)
		_add(damage_taken, victim, amount)

## Records `victim`'s elimination at `now_msec` and returns what happened:
## {"victim", "killer" (-1 for a self-KO), "streak" (the killer's KOs in a
## row, 1 for a lone KO), "first_blood" (the match's first credited KO)}.
func record_elimination(victim: int, now_msec: int) -> Dictionary:
	_add(deaths, victim, 1)
	_air_since.erase(victim)
	if _alive_since.has(victim):
		_add(survival_msec, victim, now_msec - int(_alive_since[victim]))
		_alive_since.erase(victim)
	var killer: int = -1
	var hit: Dictionary = _last_hit.get(victim, {})
	if not hit.is_empty() and now_msec - int(hit["msec"]) <= KO_CREDIT_WINDOW_MSEC:
		killer = int(hit["attacker"])
	_last_hit.erase(victim)
	var result: Dictionary = {"victim": victim, "killer": killer, "streak": 0, "first_blood": false}
	if killer == -1:
		_add(self_kos, victim, 1)
		return result
	_add(kos, killer, 1)
	if str(hit.get("weapon", "")) != "":
		_add(weapon_kos, str(hit["weapon"]), 1)
	total_kos += 1
	var run: Array = _streak.get(killer, [-MULTI_KO_WINDOW_MSEC - 1, 0])
	var streak: int = int(run[1]) + 1 if now_msec - int(run[0]) <= MULTI_KO_WINDOW_MSEC else 1
	_streak[killer] = [now_msec, streak]
	result["streak"] = streak
	result["first_blood"] = total_kos == 1
	return result

## `slot` picked up weapon `weapon` (a name such as "Hammer") off the stage.
func record_pickup(slot: int, weapon: String) -> void:
	if slot < 0:
		return
	_add(pickups, slot, 1)
	var grabs: Dictionary = weapon_grabs.get(slot, {})
	grabs[weapon] = int(grabs.get(weapon, 0)) + 1
	weapon_grabs[slot] = grabs

## The weapon `slot` grabbed most, "" when they grabbed none.
func favourite_weapon(slot: int) -> String:
	var grabs: Dictionary = weapon_grabs.get(slot, {})
	var best: String = ""
	for weapon: String in grabs.keys():
		if best == "" or int(grabs[weapon]) > int(grabs[best]):
			best = weapon
	return best

## One row per slot in `slots`, in that order, for the victory screen's stats
## table: {"slot", "kos", "self_kos", "damage_dealt", "damage_taken",
## "pickups", "weapon"} (damage rounded, weapon "" for none).
func stat_rows(slots: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot: int in slots:
		out.append({
			"slot": slot,
			"kos": int(kos.get(slot, 0)),
			"self_kos": int(self_kos.get(slot, 0)),
			"damage_dealt": roundi(float(damage_dealt.get(slot, 0))),
			"damage_taken": roundi(float(damage_taken.get(slot, 0))),
			"pickups": int(pickups.get(slot, 0)),
			"weapon": favourite_weapon(slot),
		})
	return out

func record_hill_hold(slot: int, seconds: float) -> void:
	_add(hill_hold_sec, slot, seconds)

func record_tags_passed(slot: int, count: int) -> void:
	_add(tags_passed, slot, count)

func record_lives_left(slot: int, count: int) -> void:
	_add(lives_left, slot, count)

func record_goals(slot: int, count: int) -> void:
	_add(goals, slot, count)

func record_captures(slot: int, count: int) -> void:
	_add(captures, slot, count)

## The awards only `mode_id` gives (issue #355): Longest Hold (King of the
## Hill), Hot Hands (Hot Potato), Survivor (Stock). Classic and the other
## modes give none, whatever the tables hold.
func mode_awards(slots: Array, mode_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if mode_id == GameModesScript.KING_OF_THE_HILL:
		var held: Dictionary = {}
		for slot: Variant in hill_hold_sec:
			if float(hill_hold_sec[slot]) >= HILL_MIN_SEC:
				held[slot] = hill_hold_sec[slot]
		var best: int = _leader(slots, held, kos, false)
		if best != -1:
			out.append(_award(HILL, "Longest Hold", best, "%.1fs on the hill" % float(held[best])))
	elif mode_id == GameModesScript.HOT_POTATO:
		var best: int = _leader(slots, tags_passed, kos, false)
		if best != -1:
			var n: int = int(tags_passed[best])
			out.append(_award(TAGGER, "Hot Hands", best, "%d tag%s passed" % [n, "" if n == 1 else "s"]))
	elif mode_id == GameModesScript.STOCK:
		var best: int = _leader(slots, lives_left, kos, false)
		if best != -1:
			var n: int = int(lives_left[best])
			out.append(_award(LIVES, "Survivor", best, "%d li%s left" % [n, "fe" if n == 1 else "ves"]))
	elif mode_id == GameModesScript.SOCCER:
		var best: int = _leader(slots, goals, kos, false)
		if best != -1:
			var n: int = int(goals[best])
			out.append(_award(SCORER, "Top Scorer", best, "%d goal%s" % [n, "" if n == 1 else "s"]))
	elif mode_id == GameModesScript.CAPTURE_THE_FLAG:
		var best: int = _leader(slots, captures, kos, false)
		if best != -1:
			var n: int = int(captures[best])
			out.append(_award(CAPTURER, "Flag Runner", best, "%d capture%s" % [n, "" if n == 1 else "s"]))
	return out

## Superlatives beyond `awards()` (issue #325): "Magpie" for the most weapon
## pickups. Kept apart so the three core awards stay as they were.
func extra_awards(slots: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var best: int = _leader(slots, pickups, kos, false)
	if best != -1:
		var n: int = int(pickups[best])
		out.append(_award(COLLECTOR, TranslationServer.translate("AWARD_MAGPIE"), best, (TranslationServer.translate("DETAIL_PICKUP_ONE") if n == 1 else TranslationServer.translate("DETAIL_PICKUP_MANY")) % n))
	return out

## Up to three awards, one per category, each
## {"category", "title", "slot", "detail"}. `slots` are the players eligible
## (the final roster); a category nobody scored in is left out.
func awards(slots: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var best: int = _leader(slots, kos, damage_dealt, false)
	if best != -1:
		var n: int = int(kos[best])
		out.append(_award(COMBAT, TranslationServer.translate("AWARD_TOP_BRAWLER"), best, (TranslationServer.translate("DETAIL_KO_ONE") if n == 1 else TranslationServer.translate("DETAIL_KO_MANY")) % n))
	else:
		best = _leader(slots, damage_dealt, kos, false)
		if best != -1:
			out.append(_award(COMBAT, TranslationServer.translate("AWARD_HEAVY_HITTER"), best, TranslationServer.translate("DETAIL_DAMAGE") % roundi(float(damage_dealt[best]))))
	best = _leader(slots, self_kos, deaths, false)
	if best != -1:
		var n: int = int(self_kos[best])
		out.append(_award(CLUMSY, TranslationServer.translate("AWARD_BUTTERFINGERS"), best, (TranslationServer.translate("DETAIL_SELF_KO_ONE") if n == 1 else TranslationServer.translate("DETAIL_SELF_KO_MANY")) % n))
	else:
		best = _leader(slots, damage_taken, deaths, false)
		if best != -1:
			out.append(_award(CLUMSY, TranslationServer.translate("AWARD_PUNCHING_BAG"), best, TranslationServer.translate("DETAIL_DAMAGE_TAKEN") % roundi(float(damage_taken[best]))))
	best = _leader(slots, survival_msec, deaths, true)
	if best != -1:
		out.append(_award(SURVIVOR, TranslationServer.translate("AWARD_HARD_TO_KILL"), best, TranslationServer.translate("DETAIL_ALIVE") % _clock(int(survival_msec[best]))))
	best = _leader(slots, _air_scores(), kos, false)
	if best != -1:
		out.append(_award(AIRBORNE, TranslationServer.translate("AWARD_LONGEST_AIRTIME"), best, TranslationServer.translate("DETAIL_AIRBORNE") % (float(longest_air_msec[best]) / 1000.0)))
	return out

## `longest_air_msec`, without the stretches too short to earn the award.
func _air_scores() -> Dictionary:
	var out: Dictionary = {}
	for slot: int in longest_air_msec:
		if int(longest_air_msec[slot]) >= AIRTIME_MIN_MSEC:
			out[slot] = longest_air_msec[slot]
	return out

## The slot with the highest positive `primary`; ties go to the higher
## `secondary` (or the lower, with `secondary_low`), then the lower slot.
## -1 when nobody scored above zero.
func _leader(slots: Array, primary: Dictionary, secondary: Dictionary, secondary_low: bool) -> int:
	var best: int = -1
	var ordered: Array = slots.duplicate()
	ordered.sort()
	for slot: int in ordered:
		var value: float = float(primary.get(slot, 0))
		if value <= 0.0:
			continue
		if best == -1:
			best = slot
			continue
		var top: float = float(primary.get(best, 0))
		if value > top:
			best = slot
		elif value == top:
			var a: float = float(secondary.get(slot, 0))
			var b: float = float(secondary.get(best, 0))
			if (a < b) if secondary_low else (a > b):
				best = slot
	return best

func _award(category: String, title: String, slot: int, detail: String) -> Dictionary:
	return {"category": category, "title": title, "slot": slot, "detail": detail}

func _add(table: Dictionary, slot: Variant, amount: Variant) -> void:
	table[slot] = table.get(slot, 0) + amount

static func _clock(msec: int) -> String:
	var sec: int = maxi(0, msec) / 1000
	return "%d:%02d" % [sec / 60, sec % 60]

## One JSON line for the balance log: {"t": unix time, "weapons": {id: {"damage", "hits"}}}.
## Empty when no real player landed a damaging hit this match.
func balance_log_line(unix_time: int) -> String:
	if weapon_damage.is_empty():
		return ""
	var weapons: Dictionary = {}
	for id: String in weapon_damage:
		weapons[id] = {"damage": snappedf(float(weapon_damage[id]), 0.1), "hits": int(weapon_hits.get(id, 0))}
	return JSON.stringify({"t": unix_time, "weapons": weapons})

## The weapon landing the most hits among `slots` ("" when none landed one);
## the first reached wins a tie. Names the match winner's weapon for telemetry.
func best_weapon_of(slots: Array) -> String:
	var totals: Dictionary = {}
	for slot: int in slots:
		var by_weapon: Dictionary = slot_weapon_hits.get(slot, {})
		for weapon: String in by_weapon:
			totals[weapon] = int(totals.get(weapon, 0)) + int(by_weapon[weapon])
	var best: String = ""
	for weapon: String in totals:
		if best == "" or int(totals[weapon]) > int(totals[best]):
			best = weapon
	return best

## Appends `line` to `path`. False (never an error) when it cannot be written.
static func append_line(path: String, line: String) -> bool:
	if line == "":
		return false
	if FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path).size() > LOG_MAX_BYTES:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path) + ".1")  # rotate (#609)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null:
		return false
	file.seek_end()
	file.store_line(line)
	file.close()
	return true
