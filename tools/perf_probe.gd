extends SceneTree

## Frame-time probe (issue #108): the real game scene, eight bot players (issue #138), timed
## per frame. Not a scenario -- it asserts nothing -- but the number a change
## to the game's per-frame cost is judged by.
##
##   godot --headless --path . --fixed-fps 60 -s tools/perf_probe.gd -- --frames=3600
##   godot --headless --path . --fixed-fps 120 -s tools/perf_probe.gd -- --demo --frames=7200
##
## `--fixed-fps` makes every iteration one fixed step of game time with no
## sleeping, so each frame's wall time is the CPU the frame cost. Pass the
## physics rate (60, or 120 under `--demo`, which RoundManager switches to)
## so each frame is exactly one physics step. Headless has no renderer, so
## this measures scripts, physics and audio mixing, not drawing.
##
## Arguments (after `--`):
##   --frames=<n>     frames to time after warm-up (default 3600)
##   --seed=<n>       bot and weapon RNG seed (default 108)
##   --demo           the game's own demo mode (random weapons, 120 Hz physics)
##   --random-weapons random weapons at 60 Hz
##
## Main.tscn is used as shipped except its ControllerServer, which is swapped
## for the scenario suite's roster stub so no sockets open and all eight slots
## are claimed from the first frame. Round modifiers are off so a run repeats.

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const StubRosterScript := preload("res://tools/stub_roster.gd")
const RoundManagerType := preload("res://scripts/RoundManager.gd")

const WARMUP_FRAMES: int = 120
const PLAYER_COUNT: int = 8

var _frames: int = 3600
var _seed: int = 108
var _players: Array[RigidBody2D] = []
var _bots: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _frame_usec: PackedInt64Array = PackedInt64Array()
var _physics_usec: PackedInt64Array = PackedInt64Array()
var _last_usec: int = -1
var _physics_start_usec: int = -1
## The slowest frames, as "frame:ms", to line spikes up with what happened.
var _spikes: Array[String] = []
var _frame_index: int = 0
var _rounds: int = 0
var _strikes: int = 0
var _eliminations: int = 0
## `--trace`: what happened on which frame, printed beside the spikes.
var _trace_on: bool = false
var _trace: Array[String] = []

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			_frames = arg.trim_prefix("--frames=").to_int()
		elif arg.begins_with("--seed="):
			_seed = arg.trim_prefix("--seed=").to_int()
		elif arg == "--trace":
			_trace_on = true
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
	for i in PLAYER_COUNT:
		slots.append(i)
	roster.slots = slots
	main.add_child(roster)
	var round_manager: Node = main.get_node("RoundManager")
	round_manager.rotation_seed = _seed
	# Straight into rounds: the lobby (#120) waits for phones to ready up, and
	# the stub roster never does.
	round_manager.lobby_enabled = false
	# The round-end pause is wall-clock, and a probe runs many times faster
	# than real time: shortened so the run is rounds, not scoreboards.
	round_manager.round_end_pause_sec = 0.05
	round_manager.round_started.connect(func() -> void:
		_rounds += 1
		_note("round"))
	for i in PLAYER_COUNT:
		var player: RigidBody2D = main.get_node("Player%d" % (i + 1)) as RigidBody2D
		player.bind_controller()
		player.strike_landed.connect(func(_v: Node, amount: float, _p: Vector2, _l: bool) -> void:
			if amount > 0.0:
				_strikes += 1
				_note("strike"))
		player.eliminated.connect(func() -> void:
			_eliminations += 1
			_note("elim"))
		_players.append(player)
		_bots.append({"mode": 0, "until": 0, "phase": _rng.randf() * TAU, "rate": _rng.randf_range(4.0, 9.0)})
	get_root().add_child(main)
	current_scene = main

	var clock := Node.new()
	clock.name = "PerfClock"
	clock.process_priority = -1000
	clock.process_physics_priority = -1000
	clock.set_script(_clock_script())
	clock.set_meta(&"probe", self)
	get_root().add_child(clock)

func _note(what: String) -> void:
	if _trace_on:
		_trace.append("%d:%s" % [_frame_index, what])

## The per-frame hooks, on a node rather than this SceneTree so they run in
## the tree's own process order: first of everything, every frame.
func _clock_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """extends Node
func _process(_delta: float) -> void:
	get_meta(&"probe").on_frame()
func _physics_process(_delta: float) -> void:
	get_meta(&"probe").on_physics()
"""
	script.reload()
	return script

## Once a physics step, before any game node: pick each bot's input.
func on_physics() -> void:
	if _physics_start_usec < 0:
		_physics_start_usec = Time.get_ticks_usec()
	var tick: int = Engine.get_physics_frames()
	for i in _players.size():
		var player: RigidBody2D = _players[i]
		if not player.alive:
			continue
		var bot: Dictionary = _bots[i]
		if tick >= int(bot["until"]):
			bot["mode"] = _rng.randi() % 4
			bot["until"] = tick + _rng.randi_range(15, 60)
			bot["phase"] = _rng.randf() * TAU
		var target: Vector2 = _nearest_enemy(player)
		var to_enemy: float = (target - player.global_position).angle()
		var t: float = float(tick) / float(Engine.physics_ticks_per_second)
		var v: Vector2 = Vector2.ZERO
		match int(bot["mode"]):
			0:  # swing through the nearest opponent
				v = Vector2.RIGHT.rotated(to_enemy + sin(t * float(bot["rate"]) + float(bot["phase"])) * 1.4)
			1:  # plant down and push: the movement move
				v = Vector2.RIGHT.rotated(PI * 0.5 + sin(t * 3.0 + float(bot["phase"])) * 0.6)
			2:  # full circles
				v = Vector2.RIGHT.rotated(t * float(bot["rate"]) + float(bot["phase"])) * 0.9
			_:  # let go
				v = Vector2.ZERO
		player.set_input_vector(v)

func _nearest_enemy(player: RigidBody2D) -> Vector2:
	var best: Vector2 = player.global_position + Vector2.RIGHT
	var best_d: float = INF
	for other: RigidBody2D in _players:
		if other == player or not other.alive:
			continue
		var d: float = other.global_position.distance_squared_to(player.global_position)
		if d < best_d:
			best_d = d
			best = other.global_position
	return best

## Once a frame, before anything else in it: the wall time since the last.
func on_frame() -> void:
	var now: int = Time.get_ticks_usec()
	# Only frames of a round being fought are timed: between rounds nothing
	# runs, and those frames would pull every figure towards zero.
	if _last_usec >= 0 and _frame_index >= WARMUP_FRAMES and _alive_count() >= 2:
		var cost: int = now - _last_usec
		_frame_usec.append(cost)
		_physics_usec.append(now - _physics_start_usec if _physics_start_usec >= 0 else 0)
		if cost > 4000:
			_spikes.append("%d:%.1f(phys %.1f)" % [_frame_index, cost / 1000.0, _physics_usec[-1] / 1000.0])
	_last_usec = now
	_physics_start_usec = -1
	_frame_index += 1
	if _frame_usec.size() == _frames:
		_report()
		_finish()

func _finish() -> void:
	# As the scenario runner does: let the audio server let go of every sound
	# first, or quitting reports their playbacks as leaked.
	var sfx: Node = get_root().get_node_or_null(^"Sfx")
	if sfx != null:
		await sfx.release()
	quit(0)

func _alive_count() -> int:
	var n: int = 0
	for player: RigidBody2D in _players:
		if player.alive:
			n += 1
	return n

func _report() -> void:
	var hz: int = Engine.physics_ticks_per_second
	print("PERF physics_hz=%d frames=%d rounds=%d strikes=%d eliminations=%d" % [
		hz, _frame_usec.size(), _rounds, _strikes, _eliminations])
	print("PERF frame_ms   %s" % _summary(_frame_usec))
	print("PERF physics_ms %s" % _summary(_physics_usec))
	print("PERF spikes>4ms %s" % " ".join(_spikes))
	if _trace_on:
		print("PERF trace %s" % " ".join(_trace))
	print("PERF objects=%d nodes=%d" % [
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])

func _summary(samples: PackedInt64Array) -> String:
	var sorted: PackedInt64Array = samples.duplicate()
	sorted.sort()
	var total: int = 0
	for s: int in sorted:
		total += s
	var n: int = sorted.size()
	var budget_usec: int = int(1000000.0 / float(Engine.physics_ticks_per_second))
	var over: int = 0
	for s: int in sorted:
		if s > budget_usec:
			over += 1
	return "mean=%.3f p50=%.3f p95=%.3f p99=%.3f max=%.3f over_budget=%d" % [
		float(total) / n / 1000.0,
		sorted[n / 2] / 1000.0,
		sorted[int(n * 0.95)] / 1000.0,
		sorted[int(n * 0.99)] / 1000.0,
		sorted[n - 1] / 1000.0,
		over]
