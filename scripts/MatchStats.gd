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
## A second KO by the same player within this of their last is a multi-KO.
const MULTI_KO_WINDOW_MSEC: int = 3000

## Award categories, one award each at most.
const COMBAT: String = "COMBAT"
const CLUMSY: String = "CLUMSY"
const SURVIVOR: String = "SURVIVOR"
const COLLECTOR: String = "COLLECTOR"

## slot -> number, created on first use so any roster size works.
var kos: Dictionary = {}
var self_kos: Dictionary = {}
var deaths: Dictionary = {}
var damage_dealt: Dictionary = {}
var damage_taken: Dictionary = {}
## Total msec each slot spent alive in rounds this match.
var survival_msec: Dictionary = {}
## Weapon pickups grabbed this match (issue #325), and per slot which weapon
## (name -> count) -- the favourite is the one grabbed most, first grabbed on a tie.
var pickups: Dictionary = {}
var weapon_grabs: Dictionary = {}
## Credited KOs this match, for "first blood".
var total_kos: int = 0

## victim slot -> {"attacker": slot, "msec": int} for the last hit taken.
var _last_hit: Dictionary = {}
## killer slot -> [msec of their last KO, run length].
var _streak: Dictionary = {}
## Slots still alive in the current round -> msec they entered it.
var _alive_since: Dictionary = {}

func begin_match() -> void:
	kos.clear()
	self_kos.clear()
	deaths.clear()
	damage_dealt.clear()
	damage_taken.clear()
	survival_msec.clear()
	pickups.clear()
	weapon_grabs.clear()
	total_kos = 0
	_last_hit.clear()
	_streak.clear()
	_alive_since.clear()

func begin_round(slots: Array, now_msec: int) -> void:
	_last_hit.clear()
	_streak.clear()
	_alive_since.clear()
	for slot: int in slots:
		_alive_since[slot] = now_msec
		survival_msec[slot] = int(survival_msec.get(slot, 0))

## Everyone still standing stops the survival clock here.
func end_round(now_msec: int) -> void:
	for slot: int in _alive_since.keys():
		_add(survival_msec, slot, now_msec - int(_alive_since[slot]))
	_alive_since.clear()

## A fresh player took `slot` mid-match (issue #161): nothing the slot's last
## occupant did is theirs, so every entry for it goes -- their numbers, the
## hit they last took or dealt, their streak and their round clock.
func forget_slot(slot: int) -> void:
	for table: Dictionary in [kos, self_kos, deaths, damage_dealt, damage_taken, survival_msec, pickups, weapon_grabs, _streak, _alive_since]:
		table.erase(slot)
	_last_hit.erase(slot)
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

func record_hit(attacker: int, victim: int, amount: float, now_msec: int) -> void:
	if attacker < 0 or victim < 0 or attacker == victim:
		return
	_last_hit[victim] = {"attacker": attacker, "msec": now_msec}
	if amount > 0.0:
		_add(damage_dealt, attacker, amount)
		_add(damage_taken, victim, amount)

## Records `victim`'s elimination at `now_msec` and returns what happened:
## {"victim", "killer" (-1 for a self-KO), "streak" (the killer's KOs in a
## row, 1 for a lone KO), "first_blood" (the match's first credited KO)}.
func record_elimination(victim: int, now_msec: int) -> Dictionary:
	_add(deaths, victim, 1)
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

## Superlatives beyond `awards()` (issue #325): "Magpie" for the most weapon
## pickups. Kept apart so the three core awards stay as they were.
func extra_awards(slots: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var best: int = _leader(slots, pickups, kos, false)
	if best != -1:
		var n: int = int(pickups[best])
		out.append(_award(COLLECTOR, "Magpie", best, "%d pickup%s" % [n, "" if n == 1 else "s"]))
	return out

## Up to three awards, one per category, each
## {"category", "title", "slot", "detail"}. `slots` are the players eligible
## (the final roster); a category nobody scored in is left out.
func awards(slots: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var best: int = _leader(slots, kos, damage_dealt, false)
	if best != -1:
		var n: int = int(kos[best])
		out.append(_award(COMBAT, "Top Brawler", best, "%d KO%s" % [n, "" if n == 1 else "s"]))
	else:
		best = _leader(slots, damage_dealt, kos, false)
		if best != -1:
			out.append(_award(COMBAT, "Heavy Hitter", best, "%d damage" % roundi(float(damage_dealt[best]))))
	best = _leader(slots, self_kos, deaths, false)
	if best != -1:
		var n: int = int(self_kos[best])
		out.append(_award(CLUMSY, "Butterfingers", best, "%d self-KO%s" % [n, "" if n == 1 else "s"]))
	else:
		best = _leader(slots, damage_taken, deaths, false)
		if best != -1:
			out.append(_award(CLUMSY, "Punching Bag", best, "%d damage taken" % roundi(float(damage_taken[best]))))
	best = _leader(slots, survival_msec, deaths, true)
	if best != -1:
		out.append(_award(SURVIVOR, "Hard to Kill", best, "%s alive" % _clock(int(survival_msec[best]))))
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

func _add(table: Dictionary, slot: int, amount: Variant) -> void:
	table[slot] = table.get(slot, 0) + amount

static func _clock(msec: int) -> String:
	var sec: int = maxi(0, msec) / 1000
	return "%d:%02d" % [sec / 60, sec % 60]
