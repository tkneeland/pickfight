extends Node

## Sudden Death (issue #277): one damaging hit eliminates its victim.
##
## `strike_landed` is emitted by the striker and carries the victim as its
## first argument; the victim is the one eliminated.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

var round_manager: Node
## slot -> the Callable connected to that player's `strike_landed`.
var _handlers: Dictionary = {}
var _watched: Dictionary = {}

func setup(manager: Node) -> void:
	round_manager = manager

func start_round(slots: Array[int]) -> void:
	end_round()
	if round_manager == null:
		return
	for slot: int in slots:
		if slot < 0 or slot >= round_manager._players.size():
			continue
		var player: Variant = round_manager._players[slot]
		if player == null or not is_instance_valid(player) or not player.has_signal("strike_landed"):
			continue
		var handler: Callable = _on_strike
		_watched[slot] = player
		_handlers[slot] = handler
		player.strike_landed.connect(handler)

func end_round() -> void:
	for slot: int in _handlers.keys():
		var player: Variant = _watched.get(slot)
		var handler: Callable = _handlers[slot]
		if player != null and is_instance_valid(player) and player.strike_landed.is_connected(handler):
			player.strike_landed.disconnect(handler)
	_handlers.clear()
	_watched.clear()

func connected_count() -> int:
	return _handlers.size()

func _on_strike(victim: Node, amount: float, _point: Vector2, _lethal: bool) -> void:
	if amount <= 0.0 or victim == null or not is_instance_valid(victim):
		return
	if not _watched.values().has(victim) or not bool(victim.get("alive")):
		return
	victim.eliminate()
