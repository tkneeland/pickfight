extends Node

## Soccer (issue #402): a Teams-only mode. One physics ball sits at the centre
## of a pitch with a goal at each end, one per team; players bat it with their
## weapon heads and bodies. The first team to `goals_to_win` goals takes the
## round. After a goal there is a short pause with a "GOAL!" callout, then the
## ball and the players go back to their kick-off places.
##
## Team 0 (Red) defends `Goal0`, team 1 (Blue) defends `Goal1`: a ball in a
## team's goal is a point for the other team. A knocked-out player comes back
## after about 1.5 s through the same respawn Stock uses (`Respawn.gd`), so
## nobody sits out; they still count as standing (`is_pending`) so the round
## goes on.
##
## Like every mode it never touches `RoundManager._scores`: the round ends by
## eliminating the losing team, and the normal last-team-standing rule scores
## it. Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const RespawnScript := preload("res://scripts/Respawn.gd")
const HostSettingsScript := preload("res://scripts/HostSettings.gd")

## An announcer line for the mode (#370); the Announcer listens for it.
signal callout(sound: StringName)
## A goal was scored by `team`; `scorer` is the player slot credited, or -1.
signal goal_scored(team: int, scorer: int)

const BALL_RADIUS: float = 28.0
## How close a player's body or weapon head must be to the ball to count as
## the last one to touch it.
const TOUCH_RADIUS: float = 80.0
const BALL_MAX_SPEED: float = 1800.0
## How far outside the stage's view the ball may be before it is put back.
const OUT_OF_PLAY_MARGIN: float = 200.0
const SCORE_SPACING: Vector2 = Vector2(48.0, -24.0)

var goals_to_win: int = 3
## Seconds between a goal and the kick-off.
var goal_pause_sec: float = 1.5
var respawn_sec: float = 1.5

var round_manager: Node
## team -> goals this round.
var scores: Dictionary = {0: 0, 1: 0}
## slot -> goals that player scored this round.
var scorers: Dictionary = {}
## The ball, a RigidBody2D built per round.
var ball: RigidBody2D
var _watched: Dictionary = {}
var _handlers: Dictionary = {}
var _respawner: RefCounted
var _active: bool = false
var _finished: bool = false
var _pause_left: float = 0.0
var _last_touch: int = -1
var _hud: CanvasLayer
var _score_label: Label
var _goal_label: Label

func setup(manager: Node) -> void:
	round_manager = manager

func start_round(slots: Array[int]) -> void:
	end_round()
	if round_manager == null:
		return
	goals_to_win = int(HostSettingsScript.shared().soccer_goals)
	scores = {0: 0, 1: 0}
	scorers.clear()
	_finished = false
	_pause_left = 0.0
	_last_touch = -1
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
	_build_ball()
	_build_hud()
	_active = true
	_place_ball()
	_place_players()
	_update_hud()
	callout.emit(&"announce_soccer")

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
	if _respawner != null:
		_respawner.clear()
	if ball != null and is_instance_valid(ball):
		ball.queue_free()
	ball = null
	if _hud != null and is_instance_valid(_hud):
		_hud.queue_free()
	_hud = null
	_score_label = null
	_goal_label = null

## Hands this round's goals to the match stats (issue #355).
func report_stats(stats: RefCounted) -> void:
	for slot: int in scorers:
		stats.record_goals(slot, int(scorers[slot]))

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

## Where `team` scores: the centre of the goal the other team defends, or the
## stage's far end. Used by the bots.
func attack_point(team: int) -> Vector2:
	var rect: Rect2 = _goal_rect(1 - team)
	return rect.get_center() if rect.size != Vector2.ZERO else Vector2.ZERO

## The centre of the goal `team` defends.
func defend_point(team: int) -> Vector2:
	var rect: Rect2 = _goal_rect(team)
	return rect.get_center() if rect.size != Vector2.ZERO else Vector2.ZERO

func _stage() -> Node:
	return round_manager._current_stage if round_manager != null else null

func _goal_rect(team: int) -> Rect2:
	var stage: Node = _stage()
	if stage != null and stage.has_method("get_goal_rect"):
		return stage.get_goal_rect(team)
	return Rect2()

func _ball_spawn() -> Vector2:
	var stage: Node = _stage()
	if stage != null and stage.has_method("get_ball_spawn"):
		return stage.get_ball_spawn()
	return Vector2.ZERO

# --- The ball ------------------------------------------------------------------

func _build_ball() -> void:
	ball = RigidBody2D.new()
	ball.name = "SoccerBall"
	ball.add_to_group("soccer_ball")
	# On the world and head layers, so bodies and weapon heads both strike it.
	ball.collision_layer = 3
	ball.collision_mask = 3
	ball.continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	ball.mass = 1.0
	ball.linear_damp = 0.1
	ball.angular_damp = 0.6
	var material := PhysicsMaterial.new()
	material.bounce = 0.6
	material.friction = 0.5
	ball.physics_material_override = material
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = BALL_RADIUS
	shape.shape = circle
	ball.add_child(shape)
	var disc := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 24:
		points.append(Vector2.RIGHT.rotated(TAU * float(i) / 24.0) * BALL_RADIUS)
	disc.polygon = points
	disc.color = Color(0.96, 0.96, 0.92)
	ball.add_child(disc)
	var seam := Polygon2D.new()
	seam.polygon = PackedVector2Array([Vector2(-10, -4), Vector2(10, -4), Vector2(14, 8), Vector2(0, 16), Vector2(-14, 8)])
	seam.color = Color(0.15, 0.15, 0.18)
	ball.add_child(seam)
	ball.z_index = 5
	add_child(ball)

func _place_ball() -> void:
	if ball == null:
		return
	ball.freeze = false
	ball.global_position = _ball_spawn()
	PhysicsServer2D.body_set_state(ball.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, ball.global_transform)
	ball.linear_velocity = Vector2.ZERO
	ball.angular_velocity = 0.0
	ball.rotation = 0.0
	ball.reset_physics_interpolation()
	_last_touch = -1

## Everyone back to their own half. A player who is down stays down: their
## respawn is already counting.
func _place_players() -> void:
	var centre_x: float = _ball_spawn().x
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
				spot = mine[index % mine.size()] + SCORE_SPACING * float(lap)
			player.start_round(spot, true)
			index += 1

# --- Play ----------------------------------------------------------------------

func _on_eliminated(slot: int) -> void:
	if not _active or _finished:
		return
	_respawner.queue(slot)

func _physics_process(delta: float) -> void:
	if not _active:
		return
	_respawner.tick(delta)
	if _finished or ball == null:
		return
	if _pause_left > 0.0:
		_pause_left -= delta
		if _pause_left <= 0.0:
			_kick_off()
		return
	if ball.linear_velocity.length() > BALL_MAX_SPEED:
		ball.linear_velocity = ball.linear_velocity.normalized() * BALL_MAX_SPEED
	_track_touch()
	_check_goals()
	_check_out_of_play()

func _track_touch() -> void:
	for slot: int in _watched.keys():
		var player: Node2D = _watched[slot]
		if not is_instance_valid(player) or not bool(player.alive):
			continue
		var near: float = ball.global_position.distance_to(player.global_position)
		if player.has_method("weapon_head_position"):
			near = minf(near, ball.global_position.distance_to(player.weapon_head_position()))
		if near <= TOUCH_RADIUS:
			_last_touch = slot

func _check_goals() -> void:
	for defender: int in [0, 1]:
		var rect: Rect2 = _goal_rect(defender)
		if rect.size != Vector2.ZERO and rect.has_point(ball.global_position):
			score_goal(1 - defender)
			return

## The ball strayed out of the pitch (a stage without a closed roof): back to
## the centre rather than lost.
func _check_out_of_play() -> void:
	var stage: Node = _stage()
	if stage == null or not stage.has_method("get_view_rect"):
		return
	if not stage.get_view_rect().grow(OUT_OF_PLAY_MARGIN).has_point(ball.global_position):
		_place_ball()

## `team` scores. The player credited is the last of that team to have touched
## the ball (none for an own goal). Public so a scenario can drive it.
func score_goal(team: int) -> void:
	if not _active or _finished or _pause_left > 0.0:
		return
	scores[team] = int(scores[team]) + 1
	var scorer: int = _last_touch if _last_touch != -1 and team_of(_last_touch) == team else -1
	if scorer != -1:
		scorers[scorer] = int(scorers.get(scorer, 0)) + 1
	goal_scored.emit(team, scorer)
	callout.emit(&"announce_goal")
	ball.freeze = true
	_update_hud()
	if int(scores[team]) >= goals_to_win:
		_win(team)
		return
	_pause_left = goal_pause_sec
	_show_goal(true)

func _kick_off() -> void:
	_show_goal(false)
	_place_ball()
	_place_players()

## `team` has the goals: everyone on the other team is out, so the round
## manager's last-team-standing rule scores it.
func _win(team: int) -> void:
	_finished = true
	_show_goal(true)
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

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "SoccerHud"
	_score_label = Label.new()
	_score_label.name = "SoccerScore"
	_score_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	_score_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 44)
	_score_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_score_label.add_theme_constant_override("outline_size", 8)
	_hud.add_child(_score_label)
	_goal_label = Label.new()
	_goal_label.name = "SoccerGoal"
	_goal_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 0)
	_goal_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_goal_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goal_label.add_theme_font_size_override("font_size", 120)
	_goal_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_goal_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_goal_label.add_theme_constant_override("outline_size", 14)
	_goal_label.text = tr("SOCCER_GOAL")
	_goal_label.visible = false
	_hud.add_child(_goal_label)
	add_child(_hud)

## "2 - 1": Red's goals, then Blue's.
func score_text() -> String:
	return "%d - %d" % [int(scores[0]), int(scores[1])]

func _update_hud() -> void:
	if _score_label != null:
		_score_label.text = score_text()

func _show_goal(on: bool) -> void:
	if _goal_label != null:
		_goal_label.visible = on
