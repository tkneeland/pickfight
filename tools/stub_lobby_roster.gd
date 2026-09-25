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
