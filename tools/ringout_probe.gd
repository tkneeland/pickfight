extends SceneTree
## Ring-out rate probe (issue #137): the real game scene with only one stage
## in the rotation and perf_probe.gd's four random bots (same input model),
## counting eliminations before the rising lava's grace ends, per bot-minute
## alive. Random bots fall off a lot, which is the point: it is a measure of
## how easy a stage is to fall off by accident. Asserts nothing.
##
##   godot --headless --path . --fixed-fps 60 -s tools/ringout_probe.gd -- --stage=Flatlands --seconds=600 --seed=1
##
## Prints one RINGOUT line: rounds, pre-lava falls (eliminated below the view
## or off its sides), pre-lava hazard deaths, eliminations after the lava set
## off, bot-minutes alive pre-lava, falls per bot-minute, and the median time
## to a round's first elimination. The lobby is switched off, the round-end
## pause shortened and round modifiers disabled, as in perf_probe.gd.
const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const StubRosterScript := preload("res://tools/stub_roster.gd")
const RoundManagerType := preload("res://scripts/RoundManager.gd")
const PLAYER_COUNT: int = 4
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

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--stage="): _stage = arg.trim_prefix("--stage=")
		elif arg.begins_with("--seconds="): _seconds = arg.trim_prefix("--seconds=").to_float()
		elif arg.begins_with("--seed="): _seed = arg.trim_prefix("--seed=").to_int()
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
	for i in PLAYER_COUNT: slots.append(i)
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
		_rounds += 1
		_round_tick = Engine.get_physics_frames()
		_round_had_elim = false)
	for i in PLAYER_COUNT:
		var player: RigidBody2D = main.get_node("Player%d" % (i + 1)) as RigidBody2D
		player.bind_controller()
		player.eliminated.connect(_on_elim.bind(player))
		_players.append(player)
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
	if p.y > 420.0 or absf(p.x) > 800.0:
		_falls += 1
	else:
		_hazard += 1
	if not _round_had_elim:
		_round_had_elim = true
		_first_elim_ticks.append(t)

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
	print("RINGOUT stage=%s seed=%d rounds=%d prelava_falls=%d prelava_hazard=%d lava_elims=%d bot_min=%.1f falls_per_bot_min=%.3f median_first_elim_s=%.1f" % [
		_stage, _seed, _rounds, _falls, _hazard, _late, bot_min, _falls / maxf(bot_min, 0.001), med])
	var sfx: Node = get_root().get_node_or_null(^"Sfx")
	if sfx != null: await sfx.release()
	quit(0)
