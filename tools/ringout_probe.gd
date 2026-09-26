extends SceneTree
## Ring-out rate probe (issue #137): the real game scene with only one stage
## in the rotation and perf_probe.gd's random bots (same input model; four by
## default, up to eight with --players, which a large stage needs -- #144),
## counting eliminations before the rising lava's grace ends, per bot-minute
## alive. Random bots fall off a lot, which is the point: it is a measure of
## how easy a stage is to fall off by accident. Asserts nothing.
##
##   godot --headless --path . --fixed-fps 60 -s tools/ringout_probe.gd -- --stage=Flatlands --seconds=600 --seed=1 [--players=4]
##
## Prints one RINGOUT line: rounds, pre-lava falls (eliminated below the view
## or off its sides -- the stage's own view, zoomed out on a large one), pre-lava hazard deaths, eliminations after the lava set
## off, bot-minutes alive pre-lava, falls per bot-minute, and the median time
## to a round's first elimination. The lobby is switched off, the round-end
## pause shortened and round modifiers disabled, as in perf_probe.gd.
##
## `--brain=bot` (issue #176) drives every player with the real `Bot.gd`
## instead, seeded from --seed, its input through the same smoothing a
## phone's takes. The line then also reports stage deaths: eliminations with
## no strike from another player in the STRUCK_SEC before, so a bot knocked
## off by a rival is not counted against the stage. `first_stage_death_s` is
## the mean, over rounds, of the time to the round's first stage death, with a
## round that had none counted at the lava's grace (a lower bound).
const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const StubRosterScript := preload("res://tools/stub_roster.gd")
const RoundManagerType := preload("res://scripts/RoundManager.gd")
const BotType := preload("res://scripts/Bot.gd")
const ControllerServerType := preload("res://scripts/ControllerServer.gd")
## An elimination this soon after a strike from another player is the
## striker's, not the stage's.
const STRUCK_SEC: float = 2.0
var _brain: String = "random"
## --verbose: one ELIM line per elimination, for tuning the bots.
var _verbose: bool = false
## Each bot's mode and position every 10 ticks, the last few, for --verbose.
var _mode_log: Array = []
var _brains: Array[Node] = []
var _smoothers: Array = []
var _last_struck: Dictionary = {}
var _stage_deaths: int = 0
var _round_stage_death: bool = false
var _first_stage_ticks: Array[int] = []
const MAX_PLAYERS: int = 8
var _player_count: int = 4
var _stage: String = "Flatlands"
var _seconds: float = 600.0
var _seed: int = 1
var _players: Array[RigidBody2D] = []
var _bots: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _rm: Node
var _round_tick: int = -1
var _rounds: int = 0
var _falls: int = 0
var _hazard: int = 0
var _late: int = 0
var _exposure_ticks: int = 0
var _first_elim_ticks: Array[int] = []
var _round_had_elim: bool = false
var _start_tick: int = -1
var _grace_ticks: int = 0
## The live stage's view, refreshed each round start.
var _view: Rect2 = Rect2(-800, -450, 1600, 900)
## How far above the view's bottom an elimination still counts as a fall.
const PLAYER_MARGIN: float = 30.0

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--stage="): _stage = arg.trim_prefix("--stage=")
		elif arg.begins_with("--seconds="): _seconds = arg.trim_prefix("--seconds=").to_float()
		elif arg.begins_with("--seed="): _seed = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--players="): _player_count = clampi(arg.trim_prefix("--players=").to_int(), 2, MAX_PLAYERS)
		elif arg.begins_with("--brain="): _brain = arg.trim_prefix("--brain=")
		elif arg == "--verbose": _verbose = true
	seed(_seed)
	_rng.seed = _seed
	RoundManagerType.modifier_rolls_enabled = false
	var main: Node = MAIN_SCENE.instantiate()
	var real_server: Node = main.get_node("ControllerServer")
	main.remove_child(real_server)
	real_server.free()
	var roster: Node = StubRosterScript.new()
	roster.name = "ControllerServer"
	var slots: Array[int] = []
	for i in _player_count: slots.append(i)
	roster.slots = slots
	main.add_child(roster)
	_rm = main.get_node("RoundManager")
	_rm.rotation_seed = _seed
	_rm.round_end_pause_sec = 0.05
	_rm.lobby_enabled = false
	var scenes: Array[PackedScene] = [load("res://scenes/stages/%s.tscn" % _stage)]
	_rm.stage_scenes = scenes
	_grace_ticks = int(_rm.kill_zone_grace_sec * 60.0)
	_rm.round_started.connect(func() -> void:
		_close_round()
		_rounds += 1
		_round_stage_death = false
		_last_struck.clear()
		_round_tick = Engine.get_physics_frames()
		_round_had_elim = false
		var stage: Node2D = _rm.get("_current_stage")
		if stage != null: _view = stage.get_view_rect())
	for i in _player_count:
		var player: RigidBody2D = main.get_node("Player%d" % (i + 1)) as RigidBody2D
		player.bind_controller()
		player.eliminated.connect(_on_elim.bind(player))
		player.strike_landed.connect(func(victim: Node, _amount: float, _point: Vector2, _lethal: bool) -> void:
			_last_struck[victim] = Engine.get_physics_frames())
		_players.append(player)
		if _brain == "bot":
			var bot: Node = BotType.new()
			bot.name = "ProbeBot%d" % i
			bot.rng.seed = _seed * 100 + i
			bot.player = player
			var smoother: RefCounted = ControllerServerType.InputSmoother.new()
			_smoothers.append(smoother)
			bot.output = func(v: Vector2) -> void: smoother.push(v)
			_brains.append(bot)
			main.add_child(bot)
		_bots.append({"mode": 0, "until": 0, "phase": _rng.randf() * TAU, "rate": _rng.randf_range(4.0, 9.0)})
	get_root().add_child(main)
	current_scene = main
	var clock := Node.new()
	clock.process_physics_priority = -1000
	var script := GDScript.new()
	script.source_code = "extends Node\nfunc _physics_process(_d: float) -> void:\n\tget_meta(&\"probe\").on_physics()\n"
	script.reload()
	clock.set_script(script)
	clock.set_meta(&"probe", self)
	get_root().add_child(clock)

func _on_elim(player: RigidBody2D) -> void:
	var t: int = Engine.get_physics_frames() - _round_tick
	if t > _grace_ticks:
		_late += 1
		return
	var p: Vector2 = player.global_position
	# Below or beside the stage's view (the camera's 1600x900 on a normal one).
	if p.y > _view.end.y - PLAYER_MARGIN or p.x < _view.position.x or p.x > _view.end.x:
		_falls += 1
	else:
		_hazard += 1
	if not _round_had_elim:
		_round_had_elim = true
		_first_elim_ticks.append(t)
	var struck: int = int(_last_struck.get(player, -100000))
	var by_stage: bool = Engine.get_physics_frames() - struck > int(STRUCK_SEC * 60.0)
	if _verbose:
		var modes: String = ""
		var i: int = _players.find(player)
		if _brain == "bot" and i >= 0 and i < _mode_log.size():
			modes = " modes=%s" % ",".join(_mode_log[i])
		print("ELIM round=%d t=%.1f %s at=(%.0f, %.0f) damage=%.0f %s%s" % [_rounds, t / 60.0, player.name,
			p.x, p.y, float(player.get("damage")), "stage" if by_stage else "struck", modes])
	if by_stage:
		_stage_deaths += 1
		if not _round_stage_death:
			_round_stage_death = true
			_first_stage_ticks.append(t)

## A round that ended (or the probe that stopped) with no stage death counts
## the whole grace as its time to one.
func _close_round() -> void:
	if _rounds > 0 and not _round_stage_death:
		_first_stage_ticks.append(mini(_grace_ticks, Engine.get_physics_frames() - _round_tick))
	_round_stage_death = true

func on_physics() -> void:
	var tick: int = Engine.get_physics_frames()
	if _start_tick < 0: _start_tick = tick
	if tick - _start_tick >= int(_seconds * 60.0):
		_report()
		return
	var alive: int = 0
	for p in _players:
		if p.alive: alive += 1
	if _round_tick >= 0 and alive >= 2 and tick - _round_tick <= _grace_ticks:
		_exposure_ticks += alive
	for i in _players.size():
		var player: RigidBody2D = _players[i]
		if not player.alive: continue
		if _brain == "bot":
			player.set_input_vector(_smoothers[i].step(1.0 / 60.0))
			if _verbose and tick % 10 == 0:
				while _mode_log.size() <= i: _mode_log.append([])
				_mode_log[i].append("%s@%.0f/%.0f" % [_brains[i].mode, player.global_position.x, player.global_position.y])
				if _mode_log[i].size() > 12: _mode_log[i].pop_front()
			continue
		var bot: Dictionary = _bots[i]
		if tick >= int(bot["until"]):
			bot["mode"] = _rng.randi() % 4
			bot["until"] = tick + _rng.randi_range(15, 60)
			bot["phase"] = _rng.randf() * TAU
		var target: Vector2 = _nearest_enemy(player)
		var to_enemy: float = (target - player.global_position).angle()
		var t: float = float(tick) / 60.0
		var v: Vector2 = Vector2.ZERO
		match int(bot["mode"]):
			0: v = Vector2.RIGHT.rotated(to_enemy + sin(t * float(bot["rate"]) + float(bot["phase"])) * 1.4)
			1: v = Vector2.RIGHT.rotated(PI * 0.5 + sin(t * 3.0 + float(bot["phase"])) * 0.6)
			2: v = Vector2.RIGHT.rotated(t * float(bot["rate"]) + float(bot["phase"])) * 0.9
			_: v = Vector2.ZERO
		player.set_input_vector(v)

func _nearest_enemy(player: RigidBody2D) -> Vector2:
	var best: Vector2 = player.global_position + Vector2.RIGHT
	var best_d: float = INF
	for other: RigidBody2D in _players:
		if other == player or not other.alive: continue
		var d: float = other.global_position.distance_squared_to(player.global_position)
		if d < best_d:
			best_d = d
			best = other.global_position
	return best

var _done: bool = false
func _report() -> void:
	if _done: return
	_done = true
	var bot_min: float = _exposure_ticks / 3600.0
	var med: float = -1.0
	if not _first_elim_ticks.is_empty():
		_first_elim_ticks.sort()
		med = _first_elim_ticks[_first_elim_ticks.size() / 2] / 60.0
	_close_round()
	var stage_mean: float = 0.0
	for ticks: int in _first_stage_ticks: stage_mean += ticks / 60.0
	stage_mean /= maxf(_first_stage_ticks.size(), 1.0)
	print("RINGOUT stage=%s seed=%d players=%d brain=%s rounds=%d prelava_falls=%d prelava_hazard=%d lava_elims=%d bot_min=%.1f falls_per_bot_min=%.3f median_first_elim_s=%.1f stage_deaths=%d stage_deaths_per_bot_min=%.3f first_stage_death_s=%.1f" % [
		_stage, _seed, _player_count, _brain, _rounds, _falls, _hazard, _late, bot_min, _falls / maxf(bot_min, 0.001), med,
		_stage_deaths, _stage_deaths / maxf(bot_min, 0.001), stage_mean])
	var sfx: Node = get_root().get_node_or_null(^"Sfx")
	if sfx != null: await sfx.release()
	quit(0)
