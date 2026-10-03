extends Node

## Capture the Flag (issue #403): a Teams-only mode. Each team has a base with
## a flag on a symmetric stage (`Flag0` / `Flag1` markers, `Base0` / `Base1`
## areas). Touching the enemy flag picks it up; the carrier keeps their weapon
## and can fight, but any hit makes them drop it. A dropped flag goes home by
## itself after `return_sec`, or at once when a player of its own team touches
## it. Bringing the enemy flag into your own base is a capture; the first team
## to `captures_to_win` captures takes the round.
##
## Team 0 (Red) owns flag 0 and defends base 0, team 1 (Blue) likewise. A
## knocked-out player comes back after about 1.5 s through the same respawn
## Stock and Soccer use (`Respawn.gd`); they still count as standing
## (`is_pending`), so the round goes on.
##
## Like every mode it never touches `RoundManager._scores`: the round ends by
## eliminating the losing team, and the normal last-team-standing rule scores
## it. No random numbers are drawn here (#187). Preloaded by path, never
## referenced by `class_name` (CLAUDE.md).

const RespawnScript := preload("res://scripts/Respawn.gd")
const HostSettingsScript := preload("res://scripts/HostSettings.gd")

## An announcer line for the mode (#370); the Announcer listens for it.
signal callout(sound: StringName)
## `team` captured the enemy flag; `scorer` is the carrier's slot.
signal flag_captured(team: int, scorer: int)
## `slot` picked up `team`'s flag.
signal flag_taken(team: int, slot: int)
## `team`'s flag was dropped by `slot` (after a hit or a KO).
signal flag_dropped(team: int, slot: int)
## `team`'s flag is back at its base.
signal flag_returned(team: int)

const HOME: int = 0
const CARRIED: int = 1
const DROPPED: int = 2

## How close a player's body must be to a flag to touch it.
const TOUCH_RADIUS: float = 55.0
## How long a player who just dropped the flag cannot pick it up again.
const REGRAB_LOCKOUT_SEC: float = 1.5
## How far below a drop to look for ground before giving up and sending the flag home.
const DROP_PROBE: float = 900.0
## A dropped flag further than this outside the stage's view goes home.
const OUT_OF_PLAY_MARGIN: float = 200.0
const FLAG_COLOURS: Array[Color] = [Color(1.0, 0.3, 0.3), Color(0.35, 0.55, 1.0)]

var captures_to_win: int = 2
## Seconds a dropped flag lies before it returns by itself.
var return_sec: float = 10.0
var respawn_sec: float = 1.5

var round_manager: Node
## team -> captures this round.
var scores: Dictionary = {0: 0, 1: 0}
## slot -> captures that player made this round.
var capturers: Dictionary = {}
## team -> HOME / CARRIED / DROPPED, for that team's flag.
var state: Dictionary = {0: HOME, 1: HOME}
## team -> slot carrying that team's flag, or -1.
var carrier: Dictionary = {0: -1, 1: -1}
## team -> where that team's flag is now.
var flag_position: Dictionary = {0: Vector2.ZERO, 1: Vector2.ZERO}
## team -> seconds left before a dropped flag goes home.
var return_left: Dictionary = {0: 0.0, 1: 0.0}

var _watched: Dictionary = {}
var _handlers: Dictionary = {}
var _respawner: RefCounted
var _active: bool = false
var _finished: bool = false
## slot -> the carrier's `damage` when last looked at; any rise is a hit.
var _damage_seen: Dictionary = {}
## slot -> seconds before that player may pick a flag up again.
var _lockout: Dictionary = {}
var _root: Node2D
var _flag_nodes: Dictionary = {}
var _hud: CanvasLayer
var _score_label: Label

func setup(manager: Node) -> void:
	round_manager = manager

func start_round(slots: Array[int]) -> void:
	end_round()
	if round_manager == null:
		return
	captures_to_win = int(HostSettingsScript.shared().ctf_captures)
	scores = {0: 0, 1: 0}
	capturers.clear()
	state = {0: HOME, 1: HOME}
	carrier = {0: -1, 1: -1}
	return_left = {0: 0.0, 1: 0.0}
	_damage_seen.clear()
	_lockout.clear()
	_finished = false
	_respawner = RespawnScript.new(round_manager, _watched, respawn_sec)
	for slot: int in slots:
		if slot < 0 or slot >= round_manager._players.size():
			continue
		var player: Variant = round_manager._players[slot]
		if player == null or not is_instance_valid(player) or not player.has_signal("eliminated"):
			continue
		var handler: Callable = _on_eliminated.bind(slot)
		_watched[slot] = player
		_handlers[slot] = handler
		player.eliminated.connect(handler)
	_build_flags()
	_build_hud()
	for team: int in [0, 1]:
		flag_position[team] = home_position(team)
	_place_players()
	_refresh_flags()
	_update_hud()
	_active = true
	callout.emit(&"announce_capture_the_flag")

func end_round() -> void:
	_active = false
	for slot: int in _handlers.keys():
		var player: Variant = _watched.get(slot)
		var handler: Callable = _handlers[slot]
		if player != null and is_instance_valid(player):
			if player.eliminated.is_connected(handler):
				player.eliminated.disconnect(handler)
			player.spawn_protected = false
			player.modulate.a = 1.0
	_handlers.clear()
	_watched.clear()
	_damage_seen.clear()
	_lockout.clear()
	if _respawner != null:
		_respawner.clear()
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_flag_nodes.clear()
	if _hud != null and is_instance_valid(_hud):
		_hud.queue_free()
	_hud = null
	_score_label = null

## Hands this round's captures to the match stats (issue #355).
func report_stats(stats: RefCounted) -> void:
	for slot: int in capturers:
		stats.record_captures(slot, int(capturers[slot]))

func connected_count() -> int:
	return _handlers.size()

## Whether `slot` was knocked out and is waiting to come back; the round
## manager counts such a player as still standing (as in Stock).
func is_pending(slot: int) -> bool:
	return _respawner != null and _respawner.is_pending(slot)

## `slot`'s team: its Teams team, or by slot parity outside a Teams match (a
## scenario seam).
func team_of(slot: int) -> int:
	var team: int = int(round_manager.team_of(slot)) if round_manager != null and round_manager.team_mode() else -1
	return team if team >= 0 else slot % 2

## The flag `slot` carries (the team whose flag it is), or -1.
func carried_flag_of(slot: int) -> int:
	for team: int in [0, 1]:
		if int(carrier[team]) == slot:
			return team
	return -1

## Where `team`'s flag sits when home: the centre of its base marker, or the
## stage's origin on a stage with none.
func home_position(team: int) -> Vector2:
	var stage: Node = _stage()
	if stage != null and stage.has_method("get_flag_home"):
		return stage.get_flag_home(team)
	return Vector2.ZERO

## The rectangle of `team`'s base, where a carrier of the enemy flag scores.
func base_rect(team: int) -> Rect2:
	var stage: Node = _stage()
	if stage != null and stage.has_method("get_base_rect"):
		return stage.get_base_rect(team)
	return Rect2()

func _stage() -> Node:
	return round_manager._current_stage if round_manager != null else null

# --- Play ----------------------------------------------------------------------

func _on_eliminated(slot: int) -> void:
	if not _active or _finished:
		return
	var held: int = carried_flag_of(slot)
	if held != -1:
		drop_flag(held)
	_respawner.queue(slot)

func _physics_process(delta: float) -> void:
	if not _active:
		return
	_respawner.tick(delta)
	if _finished:
		return
	for slot: int in _lockout.keys():
		_lockout[slot] = float(_lockout[slot]) - delta
		if float(_lockout[slot]) <= 0.0:
			_lockout.erase(slot)
	_check_carrier_hits()
	_check_touches()
	_check_captures()
	_tick_returns(delta)
	_refresh_flags()

## Any rise in a carrier's damage is a hit: the flag drops.
func _check_carrier_hits() -> void:
	for team: int in [0, 1]:
		var slot: int = int(carrier[team])
		if slot == -1:
			continue
		var player: Node2D = _watched.get(slot)
		if player == null or not is_instance_valid(player) or not bool(player.alive):
			drop_flag(team)
			continue
		if float(player.damage) > float(_damage_seen.get(slot, 0.0)) + 0.0001:
			drop_flag(team)
		_damage_seen[slot] = float(player.damage)

## Pick-ups and defender returns: any standing player close to a flag that is
## not being carried.
func _check_touches() -> void:
	var slots: Array = _watched.keys()
	slots.sort()
	for team: int in [0, 1]:
		if int(state[team]) == CARRIED:
			continue
		for slot: int in slots:
			var player: Node2D = _watched[slot]
			if not is_instance_valid(player) or not bool(player.alive):
				continue
			if player.global_position.distance_to(flag_position[team]) > TOUCH_RADIUS:
				continue
			if team_of(slot) == team:
				if int(state[team]) == DROPPED:
					return_flag(team)
					break
				continue
			if _lockout.has(slot) or carried_flag_of(slot) != -1:
				continue
			take_flag(team, slot)
			break

func _check_captures() -> void:
	for team: int in [0, 1]:
		var enemy_flag: int = 1 - team
		var slot: int = int(carrier[enemy_flag])
		if slot == -1:
			continue
		var player: Node2D = _watched.get(slot)
		if player == null or not is_instance_valid(player):
			continue
		var rect: Rect2 = base_rect(team)
		if rect.size != Vector2.ZERO and rect.has_point(player.global_position):
			capture(team, slot)
			if _finished:
				return

func _tick_returns(delta: float) -> void:
	for team: int in [0, 1]:
		if int(state[team]) != DROPPED:
			continue
		return_left[team] = float(return_left[team]) - delta
		if float(return_left[team]) <= 0.0:
			return_flag(team)

## `slot` picks up `team`'s flag. Public so a scenario can drive it.
func take_flag(team: int, slot: int) -> void:
	if not _active or _finished or int(state[team]) == CARRIED:
		return
	var player: Node2D = _watched.get(slot)
	if player == null or not is_instance_valid(player):
		return
	state[team] = CARRIED
	carrier[team] = slot
	_damage_seen[slot] = float(player.damage)
	flag_position[team] = player.global_position
	flag_taken.emit(team, slot)
	callout.emit(&"announce_flag_taken")

## `team`'s flag is dropped where its carrier stands, falls to the ground
## below, and starts its countdown home. Public so a scenario can drive it.
func drop_flag(team: int) -> void:
	if int(state[team]) != CARRIED:
		return
	var slot: int = int(carrier[team])
	var player: Node2D = _watched.get(slot)
	carrier[team] = -1
	_lockout[slot] = REGRAB_LOCKOUT_SEC
	var at: Vector2 = flag_position[team]
	if player != null and is_instance_valid(player):
		at = player.global_position
	flag_dropped.emit(team, slot)
	var ground: Vector2 = _ground_below(at)
	if ground == Vector2.INF:
		return_flag(team)
		return
	flag_position[team] = ground
	state[team] = DROPPED
	return_left[team] = return_sec

## `team`'s flag goes back to its base, whatever it was doing.
func return_flag(team: int) -> void:
	state[team] = HOME
	carrier[team] = -1
	return_left[team] = 0.0
	flag_position[team] = home_position(team)
	flag_returned.emit(team)

## `team` captures with `slot` carrying the other flag, which goes home.
## Public so a scenario can drive it.
func capture(team: int, slot: int) -> void:
	if not _active or _finished:
		return
	var enemy_flag: int = 1 - team
	if int(carrier[enemy_flag]) != slot:
		return
	scores[team] = int(scores[team]) + 1
	capturers[slot] = int(capturers.get(slot, 0)) + 1
	carrier[enemy_flag] = -1
	return_flag(enemy_flag)
	flag_captured.emit(team, slot)
	callout.emit(&"announce_captured")
	_update_hud()
	if int(scores[team]) >= captures_to_win:
		_win(team)

## The nearest walkable surface below `from`, or Vector2.INF with none (a
## flag lost down a pit or off the stage).
func _ground_below(from: Vector2) -> Vector2:
	var stage: Node = _stage()
	if stage != null and stage.has_method("get_view_rect") \
			and not stage.get_view_rect().grow(OUT_OF_PLAY_MARGIN).has_point(from):
		return Vector2.INF
	if _root == null or not is_instance_valid(_root) or not _root.is_inside_tree():
		return from
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, DROP_PROBE), 1)
	var skip: Array[RID] = []
	for slot: int in _watched.keys():
		if is_instance_valid(_watched[slot]):
			skip.append((_watched[slot] as CollisionObject2D).get_rid())
	query.exclude = skip
	var hit: Dictionary = _root.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector2.INF
	return (hit["position"] as Vector2) + Vector2(0.0, -20.0)

## Everyone to their own side at the start: Red on the left, Blue on the right,
## nearest the stage's own spawn points on that side. A player who is down
## stays down: their respawn is already counting.
func _place_players() -> void:
	var centre_x: float = (home_position(0).x + home_position(1).x) * 0.5
	var by_team: Dictionary = {0: [], 1: []}
	var slots: Array = _watched.keys()
	slots.sort()
	for slot: int in slots:
		by_team[team_of(slot)].append(slot)
	var points: Array[Vector2] = round_manager._stage_spawn_points
	for team: int in by_team.keys():
		var mine: Array[Vector2] = []
		for point: Vector2 in points:
			if (point.x < centre_x) == (team == 0):
				mine.append(point)
		mine.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return a.x < b.x if team == 0 else a.x > b.x)
		var index: int = 0
		for slot: int in by_team[team]:
			var player: Node2D = _watched[slot]
			if not is_instance_valid(player) or not bool(player.alive):
				index += 1
				continue
			var spot: Vector2 = Vector2(centre_x + (-300.0 if team == 0 else 300.0), 0.0)
			if not mine.is_empty():
				var lap: int = index / mine.size()
				spot = mine[index % mine.size()] + Vector2(48.0, -24.0) * float(lap)
			player.start_round(spot, true)
			index += 1

## `team` has the captures: everyone on the other team is out, so the round
## manager's last-team-standing rule scores it.
func _win(team: int) -> void:
	_finished = true
	var slots: Array = _watched.keys()
	slots.sort()
	for slot: int in slots:
		if team_of(slot) == team:
			continue
		_respawner.cancel(slot)
		var player: Node2D = _watched[slot]
		if is_instance_valid(player) and bool(player.alive):
			player.eliminate()
		round_manager._record_survivor(slot)

# --- Display -------------------------------------------------------------------

func _build_flags() -> void:
	_root = Node2D.new()
	_root.name = "CtfFlags"
	_root.z_index = 6
	add_child(_root)
	for team: int in [0, 1]:
		var flag := Node2D.new()
		flag.name = "Flag%d" % team
		var pole := Polygon2D.new()
		pole.polygon = PackedVector2Array([Vector2(-2, 0), Vector2(2, 0), Vector2(2, -70), Vector2(-2, -70)])
		pole.color = Color(0.85, 0.85, 0.88)
		flag.add_child(pole)
		var cloth := Polygon2D.new()
		cloth.polygon = PackedVector2Array([Vector2(2, -70), Vector2(40, -58), Vector2(2, -44)])
		cloth.color = FLAG_COLOURS[team]
		flag.add_child(cloth)
		_root.add_child(flag)
		_flag_nodes[team] = flag

## Draws each flag where it is: on its carrier's back, or on the ground.
func _refresh_flags() -> void:
	for team: int in [0, 1]:
		var flag: Node2D = _flag_nodes.get(team)
		if flag == null or not is_instance_valid(flag):
			continue
		var at: Vector2 = flag_position[team]
		if int(state[team]) == CARRIED:
			var player: Node2D = _watched.get(int(carrier[team]))
			if player != null and is_instance_valid(player):
				at = player.global_position + Vector2(0.0, 20.0)
				flag_position[team] = player.global_position
		flag.global_position = at
		flag.scale = Vector2(0.6, 0.6) if int(state[team]) == CARRIED else Vector2.ONE

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "CtfHud"
	_score_label = Label.new()
	_score_label.name = "CtfScore"
	_score_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	_score_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 44)
	_score_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_score_label.add_theme_constant_override("outline_size", 8)
	_hud.add_child(_score_label)
	add_child(_hud)

## "1 - 0": Red's captures, then Blue's.
func score_text() -> String:
	return "%d - %d" % [int(scores[0]), int(scores[1])]

func _update_hud() -> void:
	if _score_label != null:
		_score_label.text = score_text()
