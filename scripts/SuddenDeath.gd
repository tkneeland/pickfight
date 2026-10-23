extends Node

## Sudden Death (issue #277): one damaging hit eliminates its victim.
##
## `strike_landed` is emitted by the striker and carries the victim as its
## first argument; the victim is the one eliminated.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

## An announcer line for the mode (#370); the Announcer listens for it.
signal callout(sound: StringName)

const ModeKitScript := preload("res://scripts/ModeKit.gd")

var round_manager: Node
## Whether starting the round calls "Sudden Death!". Stock's overtime turns it
## off and calls "Overtime!" itself.
var announce_start: bool = true
## slot -> the Callable connected to that player's `strike_landed`.
var _handlers: Dictionary = {}
var _watched: Dictionary = {}

func setup(manager: Node) -> void:
	round_manager = manager

func start_round(slots: Array[int]) -> void:
	end_round()
	if round_manager == null:
		return
	if announce_start:
		callout.emit(&"announce_sudden_death")
	ModeKitScript.watch(round_manager, slots, &"strike_landed", func(_slot: int) -> Callable: return _on_strike,
			_watched, _handlers)
	for slot: int in _watched:
		_watched[slot].set_meta("one_hit_ko", true)

func end_round() -> void:
	for slot: int in _handlers.keys():
		var player: Variant = _watched.get(slot)
		if player != null and is_instance_valid(player):
			player.remove_meta("one_hit_ko")
	ModeKitScript.unwatch(_watched, _handlers, &"strike_landed", false)

func connected_count() -> int:
	return _handlers.size()

func _on_strike(victim: Node, amount: float, point: Vector2, _lethal: bool) -> void:
	if amount <= 0.0 or victim == null or not is_instance_valid(victim):
		return
	if not _watched.values().has(victim) or not bool(victim.get("alive")):
		return
	# A hit on the shield face or open canopy face is a block, not a kill (#569).
	if victim.has_method("hit_blocked") and victim.hit_blocked(point):
		return
	victim.eliminate()
