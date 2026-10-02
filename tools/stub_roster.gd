extends Node

## Test double for `ControllerServer`'s roster seam (issue #6). `RoundManager`
## reaches its `controller_server_path` only through `claimed_slots()`,
## `expire_disconnected_claims()` and `send_buzz()` -- duck-typed, never by
## `class_name` -- and this implements exactly those, so a scenario can drive the roster
## (who is claimed, and when a claim drops) without opening the real
## `ControllerServer`'s LAN sockets in a headless run.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md): the
## global class cache lives in the gitignored `.godot/` and only an editor
## run builds it, so a fresh clone would fail to resolve the name.

## The slots a scenario currently considers claimed. A scenario mutates this
## directly to simulate a phone connecting or dropping.
var slots: Array[int] = []

func claimed_slots() -> Array[int]:
	return slots

## The real `ControllerServer` drops a slot here between rounds when its
## phone has disconnected. This stub never disconnects anyone on its own --
## a scenario simulates that by editing `slots` directly -- so this is a
## no-op that exists only to satisfy the interface `RoundManager` calls.
func expire_disconnected_claims() -> void:
	pass

## Every `send_buzz()` call, in order, as `[slot, kind]` (issue #34), so a
## scenario can assert which phone was buzzed with what without a socket.
var buzzes: Array = []

func send_buzz(slot: int, kind: String) -> void:
	buzzes.append([slot, kind])

## Every `send_lives()` call as `[slot, lives, can_steal]` (Stock, #354), and
## `send_damage()` as `[slot, fraction]`, for the scenarios.
var lives_sent: Array = []
var damage_sent: Array = []

func send_lives(slot: int, lives: int, can_steal: bool) -> void:
	lives_sent.append([slot, lives, can_steal])

func send_damage(slot: int, fraction: float) -> void:
	for i in range(damage_sent.size() - 1, -1, -1):
		if damage_sent[i][0] == slot:
			if is_equal_approx(float(damage_sent[i][1]), fraction):
				return
			break
	damage_sent.append([slot, fraction])
