extends Node2D

## Sudden Death mode: first player to take damage is eliminated (issue #277).
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

var round_manager: Node
var _watch_players: Dictionary = {}

func setup(manager: Node) -> void:
	round_manager = manager

func start_round() -> void:
	_watch_players.clear()
	if round_manager == null or round_manager._players == null:
		return
	for slot: int in range(8):
		var player: Node = round_manager._players[slot]
		if player != null and is_instance_valid(player):
			_watch_players[slot] = player
			if player.has_signal("strike_landed"):
				player.strike_landed.connect(func(_v, _a, _p, _l): _on_player_hit(slot))

func end_round() -> void:
	for slot: int in _watch_players.keys():
		var player: Node = _watch_players[slot]
		if player != null and is_instance_valid(player) and player.has_signal("strike_landed"):
			player.strike_landed.disconnect(func(_v, _a, _p, _l): _on_player_hit(slot))
	_watch_players.clear()

func _on_player_hit(slot: int) -> void:
	var player: Node = _watch_players.get(slot)
	if player != null and is_instance_valid(player):
		player.eliminate()
