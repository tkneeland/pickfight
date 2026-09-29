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
