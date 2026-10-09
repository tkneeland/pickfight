extends Node2D

## King of the Hill (issue #276): a zone on the stage; a player alone inside it
## banks hold time, and the first to `seconds_to_win` takes the round: it ends
## with a banner and everyone freezes, nobody is eliminated (#662). A knockout
## respawns after `RESPAWN_SEC` through `Respawn.gd`, keeping its hold time, so
## only the hill ends a round, never the last player standing. The clock runs
## `time_limit_sec`; at time-out the most hold time wins, a tie plays on until
## someone holds the hill alone. The mode keeps its own `hold_time`; it never
## touches `RoundManager._scores`, the match tally.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

## An announcer line for the mode (#370); the Announcer listens for it.
signal callout(sound: StringName)

const RespawnScript := preload("res://scripts/Respawn.gd")
const ScreenKitScript := preload("res://scripts/ScreenKit.gd")
const TeamsScript := preload("res://scripts/Teams.gd")

## Seconds a knocked-out player waits before coming back (#662).
const RESPAWN_SEC: float = 4.0
## The clock shows top centre for its last this-many seconds.
const CLOCK_SHOWN_SEC: float = 30.0

var round_manager: Node
## Where the hill is, in world space. Left at ZERO, `start_round()` puts it at
## the centre of the stage's spawn points.
var hill_position: Vector2 = Vector2.ZERO
## Radius, px, of the hill: a live player whose centre is within it is on it.
var hill_radius: float = 110.0
## How far below the spawn centre to look for floor, and how far above it a
## standing player's centre sits.
const GROUND_DROP: float = 1200.0
const STAND_HEIGHT: float = 50.0
## Seconds alone in the hill that win the round.
var seconds_to_win: float = 15.0
## slot -> seconds held alone this round.
var hold_time: Dictionary = {}
## The slot that reached `seconds_to_win`, or -1.
var winner_slot: int = -1
## Teams (issue #352): team -> seconds the team held the hill this round. Any
## number of teammates inside hold it together; a mix of colours contests it
## and freezes everyone's clock.
var team_hold: Dictionary = {}
## The team that reached `seconds_to_win`, or -1.
var winner_team: int = -1
## Moving hill (#377): on a stage with `hill_moves`, the hill hops to the next
## of the stage's hill spots every `hill_move_interval` seconds, and
## `hill_warning` is true for the last `hill_warn_sec` before it does, with a
## ring drawn on the spot it is heading for.
var hill_move_interval: float = 30.0
var hill_warn_sec: float = 3.0
var hill_warning: bool = false
var hill_spots: Array[Vector2] = []
var hill_moves: bool = false
var _spot_index: int = 0
var _since_move: float = 0.0
var _won: bool = false
## The round's time limit (0 for none) and what is left of it. At zero the most
## hold time wins; a tie sets `overtime` until someone holds the hill alone.
var time_limit_sec: float = 180.0
var time_left: float = 180.0
var overtime: bool = false
var respawn_sec: float = RESPAWN_SEC
var _respawner: RefCounted
var _watched: Dictionary = {}
var _handlers: Dictionary = {}
var _hud: CanvasLayer
var _clock_label: Label
var _holds_label: Label
var _slots: Array[int] = []
var _active: bool = false
## Last slot (or team in Teams) that held the hill alone, -1 for none: a
## different one taking it over is "Hill taken!" (#370).
var _last_holder: int = -1

func setup(manager: Node) -> void:
	round_manager = manager

func start_round(slots: Array[int]) -> void:
	_slots = slots.duplicate()
	hold_time.clear()
	winner_slot = -1
	winner_team = -1
	_won = false
	_last_holder = -1
	team_hold.clear()
	overtime = false
	time_left = time_limit_sec
	for slot: int in _slots:
		hold_time[slot] = 0.0
	_watch_players()
	_load_stage_hill()
	if hill_position == Vector2.ZERO and round_manager != null:
		var points: Array[Vector2] = round_manager._stage_spawn_points
		if not points.is_empty():
			var sum := Vector2.ZERO
			for p: Vector2 in points:
				sum += p
			hill_position = _on_the_ground(sum / float(points.size()))
	_active = true
	_build_hud()
	_update_hud()
	queue_redraw()
	callout.emit(&"announce_king_of_the_hill")

## Every player's knockout queues a respawn, coming back farthest from the hill.
func _watch_players() -> void:
	_unwatch_players()
	if round_manager == null:
		return
	_respawner = RespawnScript.new(round_manager, _watched, respawn_sec)
	_respawner.far_from = func() -> Vector2: return hill_position
	for slot: int in _slots:
		var player: Variant = _player(slot)
		if player == null or not player.has_signal("eliminated"):
			continue
		var handler: Callable = _on_eliminated.bind(slot)
		_watched[slot] = player
		_handlers[slot] = handler
		player.eliminated.connect(handler)

func _unwatch_players() -> void:
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

func _on_eliminated(slot: int) -> void:
	if not _active or _won or _respawner == null:
		return
	_respawner.queue(slot)

## Whether `slot` is waiting to respawn: still standing for the round manager.
func is_pending(slot: int) -> bool:
	return _respawner != null and _respawner.is_pending(slot)

## A kicked player must not come back.
func cancel_respawn(slot: int) -> void:
	if _respawner != null:
		_respawner.cancel(slot)

## Spawns hang in the air above the floor, so their centre can sit a couple of
## hundred pixels over where anyone stands (#409): a hill there is out of reach
## of anyone on the ground, and a round on such a stage never ends. Drops the
## point onto the first floor below it, to body height.
func _on_the_ground(point: Vector2) -> Vector2:
	if round_manager == null or not is_instance_valid(round_manager) or not (round_manager as Node).is_inside_tree():
		return point
	var world: World2D = (round_manager as Node).get_viewport().find_world_2d()
	if world == null:
		return point
	var space: PhysicsDirectSpaceState2D = world.direct_space_state
	var query := PhysicsRayQueryParameters2D.create(point, point + Vector2(0.0, GROUND_DROP), 1)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return point
	return Vector2(point.x, (hit["position"] as Vector2).y - STAND_HEIGHT)

## Reads the stage's hill spots (#377): the hill starts on the first. A stage
## with none leaves `hill_position` to the spawn-centre fallback.
func _load_stage_hill() -> void:
	hill_spots.clear()
	hill_moves = false
	hill_warning = false
	_spot_index = 0
	_since_move = 0.0
	var stage: Variant = round_manager.get("_current_stage") if round_manager != null else null
	if stage == null or not is_instance_valid(stage) or not (stage as Object).has_method("get_hill_spots"):
		return
	hill_spots = stage.get_hill_spots()
	hill_moves = bool(stage.hill_moves) and hill_spots.size() > 1
	if hill_position == Vector2.ZERO and not hill_spots.is_empty():
		hill_position = hill_spots[0]

## The spot the hill hops to next, or `hill_position` if it does not move.
func next_hill_position() -> Vector2:
	if not hill_moves:
		return hill_position
	return hill_spots[(_spot_index + 1) % hill_spots.size()]

func _tick_moving_hill(delta: float) -> void:
	_since_move += delta
	if _since_move >= hill_move_interval:
		_spot_index = (_spot_index + 1) % hill_spots.size()
		hill_position = hill_spots[_spot_index]
		_since_move = 0.0
		hill_warning = false
		queue_redraw()
	elif _since_move >= hill_move_interval - hill_warn_sec:
		hill_warning = true
		queue_redraw()

func end_round() -> void:
	_active = false
	for slot: int in _slots:
		_send_hill(slot, -1)
	_unwatch_players()
	_slots.clear()
	if _hud != null and is_instance_valid(_hud):
		_hud.queue_free()
	_hud = null
	_clock_label = null
	_holds_label = null

## Hands this round's hold times to the match stats (issue #355). A Teams
## round banks `team_hold` instead, so no individual awards come of it.
func report_stats(stats: RefCounted) -> void:
	for slot: int in hold_time:
		stats.record_hill_hold(slot, float(hold_time[slot]))

func team_hold_of(team: int) -> float:
	return float(team_hold.get(team, 0.0))

## Whether the round being played is a Teams round.
func _teams_round() -> bool:
	return round_manager != null and round_manager.has_method("team_mode") and bool(round_manager.team_mode())

func hold_of(slot: int) -> float:
	return float(hold_time.get(slot, 0.0))

## The players alive and inside the hill right now.
func occupants() -> Array[int]:
	var inside: Array[int] = []
	if round_manager == null:
		return inside
	for slot: int in _slots:
		var player: Variant = _player(slot)
		if player != null and bool(player.alive) \
				and (player as Node2D).global_position.distance_to(hill_position) <= hill_radius:
			inside.append(slot)
	return inside

func _player(slot: int) -> Variant:
	if slot < 0 or slot >= round_manager._players.size():
		return null
	var player: Variant = round_manager._players[slot]
	return player if player != null and is_instance_valid(player) else null

func _physics_process(delta: float) -> void:
	if not _active or round_manager == null or _won:
		return
	if _respawner != null:
		_respawner.tick(delta)
	if hill_moves:
		_tick_moving_hill(delta)
	var inside: Array[int] = occupants()
	var teams: bool = _teams_round()
	var holder: int = _solo_holder(inside, teams)
	if holder != -1:
		_note_holder(holder)
		if teams:
			team_hold[holder] = team_hold_of(holder) + delta
		else:
			hold_time[holder] = hold_of(holder) + delta
		var held: float = team_hold_of(holder) if teams else hold_of(holder)
		if held >= seconds_to_win or overtime:
			_win(holder, teams)
	if not _won and time_limit_sec > 0.0 and not overtime:
		time_left = maxf(time_left - delta, 0.0)
		if time_left <= 0.0:
			_timeout(teams)
	_update_hud()
	_tell_phones(teams)
	queue_redraw()

## The slot (or, in Teams, team) alone on the hill, or -1.
func _solo_holder(inside: Array[int], teams: bool) -> int:
	if not teams:
		return inside[0] if inside.size() == 1 else -1
	var team: int = -2
	for slot: int in inside:
		var t: int = int(round_manager.team_of(slot))
		if team == -2:
			team = t
		elif t != team:
			return -1
	return team if team >= 0 else -1

## Whether the hill has been won, so the round that follows has no KOs (#521).
func is_won() -> bool:
	return _won

func _note_holder(holder: int) -> void:
	if _last_holder != -1 and holder != _last_holder:
		callout.emit(&"announce_hill_taken")
	_last_holder = holder

## `unit` (a slot, or a team in Teams) takes the round: the banner, no
## eliminations; the round manager freezes everyone else.
func _win(unit: int, teams: bool) -> void:
	_won = true
	if teams:
		winner_team = unit
	else:
		winner_slot = unit
	if _respawner != null:
		_respawner.clear()
	var who: String = TeamsScript.team_name(unit) if teams else str(round_manager._slot_name(unit))
	var colour: Color = TeamsScript.team_color(unit) if teams else (round_manager._slot_color(unit) as Color)
	var feed: Control = round_manager.kill_feed()
	if feed != null:
		feed.show_banner(tr("BANNER_HOLDS_THE_HILL") % who, "", colour)
	round_manager.declare_mode_win(unit if not teams else -1, unit if teams else -1)
	_update_hud()

## The clock ran out: the most hold time wins (a team's total in Teams); level
## on top, it is overtime until someone holds the hill alone.
func _timeout(teams: bool) -> void:
	var best: float = -1.0
	var leaders: Array[int] = []
	var units: Array = []
	if teams:
		units = [0, 1]
	else:
		units = _slots.duplicate()
	for unit: int in units:
		var held: float = team_hold_of(unit) if teams else hold_of(unit)
		if held > best + 0.0001:
			best = held
			leaders = [unit]
		elif absf(held - best) <= 0.0001:
			leaders.append(unit)
	if leaders.size() == 1:
		_win(leaders[0], teams)
		return
	overtime = true
	callout.emit(&"announce_overtime")

# --- Hill state and display ----------------------------------------------------

## &"empty" (nobody inside), &"held" (one player, or one team, alone) or
## &"contested" (rivals inside together).
func hill_state() -> StringName:
	var inside: Array[int] = occupants()
	if inside.is_empty():
		return &"empty"
	return &"held" if _solo_holder(inside, _teams_round()) != -1 else &"contested"

## Who holds the hill alone right now (a slot, or a team in Teams), or -1.
func holder_unit() -> int:
	return _solo_holder(occupants(), _teams_round())

func holder_colour() -> Color:
	var unit: int = holder_unit()
	if unit == -1:
		return Color(1.0, 0.85, 0.2)
	if _teams_round():
		return TeamsScript.team_color(unit)
	return round_manager._slot_color(unit) as Color

## How full the holder's ring is: their hold time over the target, 0-1.
func fill_fraction() -> float:
	var unit: int = holder_unit()
	if unit == -1 or seconds_to_win <= 0.0:
		return 0.0
	var held: float = team_hold_of(unit) if _teams_round() else hold_of(unit)
	return clampf(held / seconds_to_win, 0.0, 1.0)

## "Red 6/15 · Blue 3/15": every player (or team) with hold time, most first.
func holds_text() -> String:
	var rows: Array = []
	if _teams_round():
		for team: int in [0, 1]:
			if team_hold_of(team) > 0.0:
				rows.append([team_hold_of(team), "%s %d/%d" % [TeamsScript.team_name(team), floori(team_hold_of(team)), roundi(seconds_to_win)]])
	else:
		for slot: int in hold_time:
			if hold_of(slot) > 0.0:
				rows.append([hold_of(slot), "%s %d/%d" % [round_manager._slot_name(slot), floori(hold_of(slot)), roundi(seconds_to_win)]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var parts: PackedStringArray = PackedStringArray()
	for row: Array in rows:
		parts.append(str(row[1]))
	return " \u00b7 ".join(parts)

## The clock's text: "m:ss" in the last 30 s, "OVERTIME" in a tie-break, else "".
func clock_text() -> String:
	if overtime:
		return tr("OVERTIME")
	if time_limit_sec <= 0.0 or time_left > CLOCK_SHOWN_SEC:
		return ""
	var whole: int = ceili(time_left)
	return "%d:%02d" % [whole / 60, whole % 60]

func _build_hud() -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.queue_free()
	_hud = CanvasLayer.new()
	_hud.name = "HillHud"
	_holds_label = Label.new()
	_holds_label.name = "HillHolds"
	_holds_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	_holds_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_holds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ScreenKitScript.style_hud_pill(_holds_label, 32)
	_holds_label.visible = false
	_hud.add_child(_holds_label)
	_clock_label = Label.new()
	_clock_label.name = "HillClock"
	_clock_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 72)
	_clock_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ScreenKitScript.style_hud_pill(_clock_label)
	_clock_label.visible = false
	_hud.add_child(_clock_label)
	add_child(_hud)

func _update_hud() -> void:
	if _holds_label != null:
		var text: String = holds_text()
		_holds_label.text = text
		_holds_label.visible = text != ""
	if _clock_label != null:
		var clock: String = clock_text()
		_clock_label.text = clock
		_clock_label.visible = clock != ""

## Each phone sees its own hold (its team's, in Teams) out of the target.
func _tell_phones(teams: bool) -> void:
	for slot: int in _slots:
		var seconds: float = team_hold_of(int(round_manager.team_of(slot))) if teams else hold_of(slot)
		_send_hill(slot, floori(seconds))

func _send_hill(slot: int, seconds: int) -> void:
	var server: Variant = round_manager.get("_controller_server") if round_manager != null else null
	if server != null and is_instance_valid(server) and server.has_method("send_hill"):
		server.send_hill(slot, seconds, roundi(seconds_to_win))

func _draw() -> void:
	var gold := Color(1.0, 0.85, 0.2)
	var centre: Vector2 = to_local(hill_position)
	var state: StringName = hill_state() if _active and round_manager != null else &"empty"
	match state:
		&"held":
			var colour: Color = holder_colour()
			draw_circle(centre, hill_radius, Color(colour, 0.4))
			draw_arc(centre, hill_radius, 0.0, TAU, 48, Color(colour, 0.5), 3.0)
			var fraction: float = fill_fraction()
			if fraction > 0.0:
				draw_arc(centre, hill_radius - 7.0, -PI * 0.5, -PI * 0.5 + TAU * fraction, 64, colour, 12.0)
			_draw_crown(centre + Vector2(0.0, -hill_radius - 50.0 + 6.0 * sin(float(Time.get_ticks_msec()) * 0.005)), colour)
		&"contested":
			var flash: bool = int(float(Time.get_ticks_msec()) / 200.0) % 2 == 0
			var colour2: Color = Color(1.0, 0.2, 0.2) if flash else Color.WHITE
			draw_circle(centre, hill_radius, Color(colour2, 0.3))
			draw_arc(centre, hill_radius, 0.0, TAU, 48, colour2, 5.0)
			var font: Font = ThemeDB.fallback_font
			draw_string(font, centre + Vector2(-hill_radius, -hill_radius - 16.0), tr("HILL_CONTESTED"),
				HORIZONTAL_ALIGNMENT_CENTER, hill_radius * 2.0, 36, colour2)
		_:
			draw_circle(centre, hill_radius, Color(gold, 0.15))
			draw_arc(centre, hill_radius, 0.0, TAU, 48, Color(gold, 0.45), 3.0)
	if hill_warning:
		var pulse: float = 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
		var warn := Color(1.0, 0.35, 0.2)
		draw_arc(to_local(next_hill_position()), hill_radius, 0.0, TAU, 48, Color(warn, 0.4 + 0.5 * pulse), 4.0)

## A simple crown floating over the hill, in gold with the holder's outline.
func _draw_crown(at: Vector2, outline: Color) -> void:
	var pts := PackedVector2Array([Vector2(-32, 0), Vector2(-32, -32), Vector2(-16, -16), Vector2(0, -42),
		Vector2(16, -16), Vector2(32, -32), Vector2(32, 0)])
	for i in pts.size():
		pts[i] += at
	draw_colored_polygon(pts, Color(1.0, 0.85, 0.2))
	var loop: PackedVector2Array = pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, outline, 4.0)
