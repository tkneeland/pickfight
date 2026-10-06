extends "res://tools/stub_roster.gd"

## `stub_roster.gd` plus the lobby seam `RoundManager` uses with
## `lobby_enabled` (issue #120): who is ready, who hosts, the host's "first to
## N", and every lobby state pushed to the phones. A scenario sets `ready_slots`,
## `host` and `target` directly, the way phones would over the socket.

var ready_slots: Dictionary = {}
var host: int = -1
var target: int = 5
var lobby_states: Array[Dictionary] = []

func slot_ready(slot: int) -> bool:
	return bool(ready_slots.get(slot, false))

func clear_ready() -> void:
	ready_slots.clear()

func host_slot() -> int:
	return host

func match_target() -> int:
	return target

func set_lobby_state(state: Dictionary) -> void:
	lobby_states.append(state.duplicate(true))

## The last state pushed, or {} before any.
func last_state() -> Dictionary:
	return lobby_states.back() if not lobby_states.is_empty() else {}

## Nicknames by slot (issue #121); a slot without one reads "".
var names: Dictionary = {}

func slot_name(slot: int) -> String:
	return str(names.get(slot, ""))

## Teams mode (issue #236): the host's mode, each slot's team pick (0 red,
## 1 blue; missing is "auto"), and which slots are bots.
var teams_on: bool = false
var team_picks: Dictionary = {}
var bot_slots: Array[int] = []

func team_mode() -> bool:
	return teams_on

func slot_team_pick(slot: int) -> int:
	return int(team_picks.get(slot, -1))

func is_virtual(slot: int) -> bool:
	return bot_slots.has(slot)

## Lifetime stats (#503): every `send_career()` the round loop made, as
## [slot, deltas] -- bots dropped, as the real server drops them -- and the
## host's "end match" command, emitted the way a phone's would arrive.
signal host_command(cmd: String, slot: int)
var career_log: Array = []

func send_career(slot: int, deltas: Dictionary) -> bool:
	if deltas.is_empty() or bot_slots.has(slot):
		return false
	career_log.append([slot, deltas.duplicate(true)])
	return true

## The sum of the deltas `slot` was sent, one dictionary (weapons summed too).
func career_total(slot: int) -> Dictionary:
	var out: Dictionary = {}
	for entry: Array in career_log:
		if entry[0] != slot:
			continue
		for key: String in entry[1].keys():
			if key == "weapons":
				var weapons: Dictionary = out.get("weapons", {})
				for weapon: String in entry[1]["weapons"].keys():
					weapons[weapon] = int(weapons.get(weapon, 0)) + int(entry[1]["weapons"][weapon])
				out["weapons"] = weapons
			else:
				out[key] = int(out.get(key, 0)) + int(entry[1][key])
	return out
