extends Node2D

## Hot Potato / Tag mode: one player is "it" and loses points each frame.
## Others can land a hit to tag them and become "it" (issue #278).
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

var round_manager: Node
var _it_slot: int = -1
var _players_connected: Array[int] = []
const PENALTY_PER_SECOND: float = 1.0

func setup(manager: Node) -> void:
	round_manager = manager

func start_round() -> void:
	_players_connected.clear()
	if round_manager == null or round_manager._players == null:
		return
	_it_slot = -1
	for slot: int in range(8):
		var player: Node = round_manager._players[slot]
		if player != null and is_instance_valid(player):
			_players_connected.append(slot)
			if player.has_signal("strike_landed"):
				player.strike_landed.connect(func(v, _a, _p, _l): _on_strike(slot, v))
	_assign_it()

func end_round() -> void:
	for slot: int in _players_connected:
		var player: Node = round_manager._players[slot] if round_manager != null else null
		if player != null and is_instance_valid(player) and player.has_signal("strike_landed"):
			player.strike_landed.disconnect(func(v, _a, _p, _l): _on_strike(slot, v))
	_players_connected.clear()
	_it_slot = -1

func _physics_process(delta: float) -> void:
	if _it_slot >= 0 and round_manager != null:
		var player: Node = round_manager._players[_it_slot]
		if player != null and is_instance_valid(player) and bool(player.get("alive")):
			round_manager._scores[_it_slot] -= int(PENALTY_PER_SECOND * delta)

func _on_strike(striker_slot: int, victim: Node) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	var victim_slot: int = -1
	if round_manager == null:
		return
	for slot: int in range(8):
		if round_manager._players[slot] == victim:
			victim_slot = slot
			break
	if victim_slot == _it_slot:
		_it_slot = striker_slot

func _assign_it() -> void:
	if _players_connected.size() > 0:
		_it_slot = _players_connected[randi() % _players_connected.size()]
