extends Node

## Stock (issue #354): every player has a few lives per round, Smash-style.
##
## Losing a life respawns the player after `respawn_sec` at the stage spawn
## farthest from everyone still standing, with spawn protection (#114), the
## pickaxe and no damage (which resets the phone's damage bar, #331). A player
## with no life left is out for the round, and `RoundManager` gives them the
## KO ghost (#324). A player waiting to respawn still counts as standing
## (`is_pending`), so the round goes on.
##
## Teams: lives are per player; a team loses when all its players are out. An
## eliminated player whose team-mate has 2+ lives may `steal_life()`.
##
## The time limit (`HostSettings.stock_time_limit`, 0 for none) ends in the
## player or team with the most lives winning; a tie plays a one-hit overtime
## among the tied, reusing `SuddenDeath.gd`.
##
## Like every mode it never touches `RoundManager._scores`. There is no rise
## (the rising lava, ADR-0012): `RoundManager` does not start it in Stock.
##
## Preloaded by path, never referenced by `class_name` (CLAUDE.md).

const HostSettingsScript := preload("res://scripts/HostSettings.gd")
const SuddenDeathScript := preload("res://scripts/SuddenDeath.gd")
const GameClockScript := preload("res://scripts/GameClock.gd")

## Seconds from losing a life to coming back.
var respawn_sec: float = 1.5
## Seconds left on the clock; meaningful only when `time_limit_sec` > 0.
var time_left: float = 0.0
var time_limit_sec: float = 0.0
## slot -> lives left (0 once out). Only slots playing the round.
var lives: Dictionary = {}
var overtime: bool = false
var round_manager: Node

## slot -> seconds until it respawns.
var _pending: Dictionary = {}
## slot -> GameClock msec its spawn protection ends.
var _protected: Dictionary = {}
var _watched: Dictionary = {}
var _handlers: Dictionary = {}
var _active: bool = false
var _overtime_mode: Node = null
var _hud: CanvasLayer
var _clock_label: Label

func setup(manager: Node) -> void:
	round_manager = manager

func start_round(slots: Array[int]) -> void:
	end_round()
	if round_manager == null:
		return
	var settings: RefCounted = HostSettingsScript.shared()
	var start_lives: int = int(settings.stock_lives)
	time_limit_sec = float(settings.stock_time_limit)
	time_left = time_limit_sec
	overtime = false
	for slot: int in slots:
		if slot < 0 or slot >= round_manager._players.size():
			continue
		var player: Variant = round_manager._players[slot]
		if player == null or not is_instance_valid(player) or not player.has_signal("eliminated"):
			continue
		var handler: Callable = _on_eliminated.bind(slot)
		_watched[slot] = player
		_handlers[slot] = handler
		lives[slot] = start_lives
		player.eliminated.connect(handler)
	_active = true
	_build_hud()
	_update_clock()

func end_round() -> void:
	_active = false
	for slot: int in _handlers.keys():
		var player: Variant = _watched.get(slot)
		var handler: Callable = _handlers[slot]
		if player != null and is_instance_valid(player) and player.eliminated.is_connected(handler):
			player.eliminated.disconnect(handler)
		if player != null and is_instance_valid(player):
			player.spawn_protected = false
			player.modulate.a = 1.0
		_send_lives(slot, -1, false)
	_handlers.clear()
	_watched.clear()
	_pending.clear()
	_protected.clear()
	lives.clear()
	overtime = false
	if _overtime_mode != null and is_instance_valid(_overtime_mode):
		_overtime_mode.end_round()
		_overtime_mode.queue_free()
	_overtime_mode = null
	if _hud != null and is_instance_valid(_hud):
		_hud.queue_free()
	_hud = null
	_clock_label = null

func connected_count() -> int:
	return _handlers.size()

## Whether `slot` has lost a life and is waiting to come back.
func is_pending(slot: int) -> bool:
	return _pending.has(slot)

func lives_of(slot: int) -> int:
	return int(lives.get(slot, -1))

## Whether `slot` is out of lives (and so a ghost).
func is_out(slot: int) -> bool:
	return lives.has(slot) and int(lives[slot]) <= 0 and not _pending.has(slot) \
		and not bool(_watched[slot].alive)

func _on_eliminated(slot: int) -> void:
	if not _active:
		return
	lives[slot] = 0 if overtime else maxi(int(lives.get(slot, 0)) - 1, 0)
	if int(lives[slot]) > 0:
		_pending[slot] = respawn_sec
	# Counted here, after the lives are, so a player about to come back is
	# never taken for the last one down.
	round_manager._record_survivor(slot)

func _physics_process(delta: float) -> void:
	if not _active:
		return
	for slot: int in _pending.keys():
		_pending[slot] = float(_pending[slot]) - delta
		if float(_pending[slot]) <= 0.0:
			_respawn(slot)
	_tick_protection()
	if time_limit_sec > 0.0 and not overtime:
		time_left = maxf(time_left - delta, 0.0)
		if time_left <= 0.0:
			_timeout()
	_update_clock()
	for slot: int in lives.keys():
		_send_lives(slot, int(lives[slot]), can_steal(slot))

## Back in at the spawn farthest from the others, a pickaxe in hand.
func _respawn(slot: int) -> void:
	_pending.erase(slot)
	var player: Node2D = _watched[slot]
	if not is_instance_valid(player):
		return
	player.start_round(_farthest_spawn(slot), false)
	if float(round_manager.spawn_protection_sec) > 0.0:
		player.spawn_protected = true
		_protected[slot] = _now_msec() + int(float(round_manager.spawn_protection_sec) * 1000.0)

## The stage spawn point whose nearest standing player is farthest away.
func _farthest_spawn(slot: int) -> Vector2:
	var points: Array[Vector2] = round_manager._stage_spawn_points
	var here: Vector2 = _watched[slot].global_position
	if points.is_empty():
		return here
	var best: Vector2 = points[0]
	var best_gap: float = -1.0
	for point: Vector2 in points:
		var gap: float = INF
		for other: int in _watched.keys():
			if other != slot and bool(_watched[other].alive):
				gap = minf(gap, point.distance_to(_watched[other].global_position))
		if gap > best_gap:
			best_gap = gap
			best = point
	return best

func _tick_protection() -> void:
	var now: int = _now_msec()
	for slot: int in _protected.keys():
		var player: Node2D = _watched[slot]
		if not is_instance_valid(player):
			_protected.erase(slot)
		elif now >= int(_protected[slot]):
			player.spawn_protected = false
			player.modulate.a = 1.0
			_protected.erase(slot)
		else:
			var lit: bool = int(float(now) / 1000.0 * 16.0) % 2 == 0
			player.modulate.a = 1.0 if lit else 0.35

func _now_msec() -> int:
	return GameClockScript.now_msec()

# --- Teams: steal a life -------------------------------------------------------

func _team(slot: int) -> int:
	return int(round_manager.team_of(slot)) if round_manager.team_mode() else -1

## The team-mate with the most lives (2 or more), or -1.
func _donor_for(slot: int) -> int:
	var team: int = _team(slot)
	if team == -1:
		return -1
	var donor: int = -1
	var most: int = 1
	var keys: Array = lives.keys()
	keys.sort()
	for other: int in keys:
		if other != slot and _team(other) == team and int(lives[other]) > most:
			donor = other
			most = int(lives[other])
	return donor

## Whether `slot`, out of lives, may steal one from a team-mate.
func can_steal(slot: int) -> bool:
	return _active and not overtime and is_out(slot) and _donor_for(slot) != -1

## Takes one life from the team-mate with the most and brings `slot` back at
## once. Returns whether it happened.
func steal_life(slot: int) -> bool:
	if not can_steal(slot):
		return false
	var donor: int = _donor_for(slot)
	lives[donor] = int(lives[donor]) - 1
	lives[slot] = 1
	_respawn(slot)
	return true

# --- Time limit and overtime ---------------------------------------------------

## The clock ran out: most lives wins (a team's lives added up in Teams). The
## others are eliminated for good; if several are level the round goes on as a
## one-hit overtime between them.
func _timeout() -> void:
	var totals: Dictionary = {}
	for slot: int in lives.keys():
		if int(lives[slot]) <= 0:
			continue
		var unit: int = _team(slot) if _team(slot) != -1 else slot
		totals[unit] = int(totals.get(unit, 0)) + int(lives[slot])
	var best: int = 0
	for unit: int in totals.keys():
		best = maxi(best, int(totals[unit]))
	var tied: Array[int] = []
	for slot: int in lives.keys():
		var unit: int = _team(slot) if _team(slot) != -1 else slot
		if int(lives[slot]) > 0 and int(totals[unit]) == best:
			tied.append(slot)
	tied.sort()
	var losers: Array[int] = []
	for slot: int in lives.keys():
		if not tied.has(slot):
			losers.append(slot)
	for slot: int in losers:
		lives[slot] = 0
		_pending.erase(slot)
	overtime = true
	var tied_units: Dictionary = {}
	for slot: int in tied:
		tied_units[_team(slot) if _team(slot) != -1 else slot] = true
	if tied_units.size() > 1:
		_overtime_mode = SuddenDeathScript.new()
		add_child(_overtime_mode)
		_overtime_mode.setup(round_manager)
		_overtime_mode.start_round(tied)
	else:
		overtime = false
		time_limit_sec = 0.0
	for slot: int in losers:
		if bool(_watched[slot].alive):
			_watched[slot].eliminate()

# --- Display -------------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "StockHud"
	_clock_label = Label.new()
	_clock_label.name = "StockClock"
	_clock_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	_clock_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.add_theme_font_size_override("font_size", 44)
	_clock_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_clock_label.add_theme_constant_override("outline_size", 8)
	_clock_label.visible = false
	_hud.add_child(_clock_label)
	add_child(_hud)

## The countdown's text: "m:ss", "OVERTIME" in a tie-break, nothing with no limit.
func clock_text() -> String:
	if overtime:
		return "OVERTIME"
	if time_limit_sec <= 0.0:
		return ""
	var whole: int = ceili(time_left)
	return "%d:%02d" % [whole / 60, whole % 60]

## Whether the clock is in its last 10 seconds, pulsing.
func clock_pulsing() -> bool:
	return time_limit_sec > 0.0 and not overtime and time_left <= 10.0

func _update_clock() -> void:
	if _clock_label == null:
		return
	var text: String = clock_text()
	_clock_label.text = text
	_clock_label.visible = text != ""
	var tint: Color = Color.WHITE
	var pulse: float = 1.0
	if overtime:
		tint = Color(1.0, 0.35, 0.2)
	elif clock_pulsing():
		var beat: float = 0.5 + 0.5 * sin(time_left * TAU)
		pulse = 1.0 + 0.2 * beat
		tint = Color(1.0, 0.3, 0.3).lerp(Color.WHITE, 1.0 - beat)
	_clock_label.add_theme_color_override("font_color", tint)
	_clock_label.pivot_offset = _clock_label.size * 0.5
	_clock_label.scale = Vector2(pulse, pulse)

func _send_lives(slot: int, count: int, steal: bool) -> void:
	var server: Variant = round_manager._controller_server if round_manager != null else null
	if server != null and is_instance_valid(server) and server.has_method("send_lives"):
		server.send_lives(slot, count, steal)
