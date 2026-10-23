extends RefCounted

## Shared plumbing of the round modes: watching the round's players, putting
## teams on their own side, ending a team round and the HUD's score pill.
## Static helpers only; the modes keep their own state and pass it in.
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const ScreenKitScript := preload("res://scripts/ScreenKit.gd")

## Where a placed player goes when their side has no spawn points, and the step
## between players sharing a spawn point.
const SIDE_OFFSET: float = 300.0
const LAP_SPACING: Vector2 = Vector2(48.0, -24.0)

## Connects `signal_name` of every live player in `slots` to
## `handler_for.call(slot)`, recording the player in `watched` and the
## handler in `handlers` (both keyed by slot). Slots out of range, gone or
## without the signal are skipped.
static func watch(manager: Node, slots: Array[int], signal_name: StringName, handler_for: Callable,
		watched: Dictionary, handlers: Dictionary) -> void:
	for slot: int in slots:
		if slot < 0 or slot >= manager._players.size():
			continue
		var player: Variant = manager._players[slot]
		if player == null or not is_instance_valid(player) or not (player as Object).has_signal(signal_name):
			continue
		var handler: Callable = handler_for.call(slot)
		watched[slot] = player
		handlers[slot] = handler
		(player as Object).connect(signal_name, handler)

## Undoes `watch()`. With `release`, each player also loses any respawn
## protection and its fade (a respawning mode's end of round).
static func unwatch(watched: Dictionary, handlers: Dictionary, signal_name: StringName, release: bool = true) -> void:
	for slot: int in handlers.keys():
		var player: Variant = watched.get(slot)
		var handler: Callable = handlers[slot]
		if player != null and is_instance_valid(player):
			if (player as Object).is_connected(signal_name, handler):
				(player as Object).disconnect(signal_name, handler)
			if release:
				player.spawn_protected = false
				player.modulate.a = 1.0
	handlers.clear()
	watched.clear()

## Whether `slot` waits on `respawner` to come back.
static func is_pending(respawner: RefCounted, slot: int) -> bool:
	return respawner != null and respawner.is_pending(slot)

## Drops `slot`'s pending respawn, if any.
static func cancel_respawn(respawner: RefCounted, slot: int) -> void:
	if respawner != null:
		respawner.cancel(slot)

## `slot`'s team: its Teams team, or by slot parity outside a Teams match (a
## scenario seam).
static func team_of(manager: Node, slot: int) -> int:
	var team: int = int(manager.team_of(slot)) if manager != null and manager.team_mode() else -1
	return team if team >= 0 else slot % 2

## The stage being played, or null.
static func stage(manager: Node) -> Node:
	return manager._current_stage if manager != null else null

## A fingerprint of `stage` for a mode that caches its geometry (goal and base
## rectangles) instead of reading it every tick: another stage (a mid-round
## change, #646), the stage entering the tree, or it being moved or resized
## changes the key, and the cache is read afresh. Empty for no stage.
static func stage_key(stage_node: Node) -> Array:
	if stage_node == null:
		return []
	return [stage_node.get_instance_id(), stage_node.is_inside_tree(), stage_node.get("position"), stage_node.get("view_size")]

## Everyone in `watched` to their own side of `centre_x`: team 0 on the left,
## team 1 on the right, nearest the stage's own spawn points on that side. A
## spawn point for which `skip.call(point)` is true is left out. A player who is
## down stays down: their respawn is already counting.
static func place_teams(manager: Node, watched: Dictionary, team_of_slot: Callable, centre_x: float,
		skip: Callable = Callable()) -> void:
	var by_team: Dictionary = {0: [], 1: []}
	var slots: Array = watched.keys()
	slots.sort()
	for slot: int in slots:
		by_team[team_of_slot.call(slot)].append(slot)
	var points: Array[Vector2] = manager._stage_spawn_points
	for team: int in by_team.keys():
		var mine: Array[Vector2] = []
		for point: Vector2 in points:
			if (point.x < centre_x) == (team == 0) and not (skip.is_valid() and bool(skip.call(point))):
				mine.append(point)
		mine.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return a.x < b.x if team == 0 else a.x > b.x)
		var index: int = 0
		for slot: int in by_team[team]:
			var player: Node2D = watched[slot]
			if not is_instance_valid(player) or not bool(player.alive):
				index += 1
				continue
			var spot: Vector2 = Vector2(centre_x + (-SIDE_OFFSET if team == 0 else SIDE_OFFSET), 0.0)
			if not mine.is_empty():
				var lap: int = index / mine.size()
				spot = mine[index % mine.size()] + LAP_SPACING * float(lap)
			player.start_round(spot, true)
			index += 1

## `team` won: everyone in `watched` on another team is out for good, so the
## round manager's last-team-standing rule scores it.
static func eliminate_other_team(manager: Node, watched: Dictionary, respawner: RefCounted,
		team_of_slot: Callable, team: int) -> void:
	var slots: Array = watched.keys()
	slots.sort()
	for slot: int in slots:
		if int(team_of_slot.call(slot)) == team:
			continue
		respawner.cancel(slot)
		var player: Node2D = watched[slot]
		if is_instance_valid(player) and bool(player.alive):
			player.eliminate()
		manager._record_survivor(slot)

## A HUD pill label named `label_name`, centred at the top `top` px down.
static func hud_pill(label_name: String, top: int, font_size: int = 44) -> Label:
	var label := Label.new()
	label.name = label_name
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, top)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ScreenKitScript.style_hud_pill(label, font_size)
	return label

## "2 - 1": team 0's score, then team 1's.
static func score_text(scores: Dictionary) -> String:
	return "%d - %d" % [int(scores[0]), int(scores[1])]
