extends Node

## Test double for `ControllerServer`'s roster seam (issue #6). `RoundManager`
## reaches its `controller_server_path` only through `claimed_slots()` and
## `expire_disconnected_claims()` -- duck-typed, never by `class_name` -- and
## this implements exactly those two, so a scenario can drive the roster
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
