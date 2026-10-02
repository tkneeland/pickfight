extends SceneTree

## One balance-sweep run (issue #404): the real game scene (Main, RoundManager,
## the stage rotation) with N bots on fixed weapons, played for R rounds,
## printing one `BALANCE {json}` line. `tools/balance_sweep.py` runs many of
## these and writes the report. Report only: it changes no weapon stats.
##
##   godot --headless --path . --fixed-fps 60 -s tools/balance_probe.gd -- \
##       --weapons=sword,axe --mode=classic --rounds=10 --seed=1
##
## Arguments (after `--`):
##   --weapons=a,b,..   weapon id (resources/<id>.tres) per slot; N = count
##   --mode=<id>        classic (default), king_of_the_hill, hot_potato, stock
##   --rounds=<n>       rounds to play (default 10)
##   --seed=<n>         match seed (stages, bots)
##   --stage=<Name>     play only this stage (scenes/stages/<Name>.tscn), every round
##   --lives=<n>        Stock lives per player (default: the saved setting)
##   --diag             every 20 game seconds print `DIAG` lines: each bot's place, mode and goal
##   --bots=<n>         accepted and ignored apart from telemetry's guard
##
## Numbers come from the game's own `MatchStats` (RoundManager's `_stats`):
## the stub roster has no `is_virtual()`, so every slot counts as a "real"
## player there and its per-slot damage, KOs and landed hits are tallied.
## Telemetry: this is a `-s` run, which `StatsSender.is_scripted` already
## refuses; the probe also asks `should_send` with `--bots` and without, and
## reports the answers in the output (`telemetry_send_allowed`, both false).
## Pickups are off (`pickup_scene = null`) so a slot keeps its weapon.

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const StubRosterScript := preload("res://tools/stub_roster.gd")
const RoundManagerType := preload("res://scripts/RoundManager.gd")
const BotScript: GDScript = preload("res://scripts/Bot.gd")
const BotDirectorScript: GDScript = preload("res://scripts/BotDirector.gd")
const StatsSenderScript := preload("res://scripts/StatsSender.gd")
const HostSettingsScript := preload("res://scripts/HostSettings.gd")
const GameClockScript := preload("res://scripts/GameClock.gd")

## Hard stop in game seconds for the whole run, whatever the rounds do.
const MAX_GAME_SEC: float = 3600.0
## A round still going after this many game seconds (King of the Hill with
## bots contesting the hill never ends: no lava) is closed as a timeout, a
## drawn round, and the run stops there. Reported as `"timeout": true`.
const ROUND_CAP_SEC: float = 300.0

var _weapons: Array[String] = []
var _mode: String = ""
var _mode_name: String = "classic"
var _rounds: int = 10
var _seed: int = 1
var _stage_only: String = ""
var _lives: int = 0
var _diag: bool = false
var _diag_at: float = 5.0
var _main: Node
var _rm: Node
var _players: Array[RigidBody2D] = []
var _round_open: bool = false
var _round_start_msec: int = 0
var _round_stage: String = ""
var _round_winner: int = -1
var _first_elim_msec: int = -1
var _round_log: Array[Dictionary] = []
var _timed_out: bool = false
var _finishing: bool = false
var _started_msec: int = 0

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--weapons="):
			for w: String in arg.trim_prefix("--weapons=").split(","):
				_weapons.append(w)
		elif arg.begins_with("--mode="):
			_mode_name = arg.trim_prefix("--mode=")
			_mode = "" if _mode_name == "classic" else _mode_name
		elif arg.begins_with("--rounds="):
			_rounds = arg.trim_prefix("--rounds=").to_int()
		elif arg.begins_with("--stage="):
			_stage_only = arg.trim_prefix("--stage=")
		elif arg == "--diag":
			_diag = true
		elif arg.begins_with("--lives="):
			_lives = arg.trim_prefix("--lives=").to_int()
		elif arg.begins_with("--seed="):
			_seed = arg.trim_prefix("--seed=").to_int()
	if _weapons.size() < 2 or _weapons.size() > 8:
		printerr("BALANCE: need --weapons with 2..8 ids")
		quit(2)
		return
	for w: String in _weapons:
		if not ResourceLoader.exists("res://resources/%s.tres" % w):
			printerr("BALANCE: no weapon %s" % w)
			quit(2)
			return
	seed(_seed)
	RoundManagerType.modifier_rolls_enabled = false

	_main = MAIN_SCENE.instantiate()
	var real_server: Node = _main.get_node("ControllerServer")
	_main.remove_child(real_server)
	real_server.free()
	var roster: Node = StubRosterScript.new()
	roster.name = "ControllerServer"
	var slots: Array[int] = []
	for i in _weapons.size():
		slots.append(i)
	roster.slots = slots
	_main.add_child(roster)
	_rm = _main.get_node("RoundManager")
	_rm.rotation_seed = _seed
	_rm.match_seed = _seed
	_rm.lobby_enabled = false
	_rm.round_end_pause_sec = 0.05
	_rm.stage_title_sec = 0.0
	_rm.pickup_scene = null
	_rm.game_mode = _mode
	if _stage_only != "":
		var only: Array[PackedScene] = [load("res://scenes/stages/%s.tscn" % _stage_only)]
		_rm.stage_scenes = only
	if _lives > 0:
		HostSettingsScript.shared().set_stock_lives(_lives)
	_rm.round_started.connect(_on_round_started)
	_rm.round_won.connect(func(slot: int) -> void: _round_winner = slot)
	for i in _weapons.size():
		var player: RigidBody2D = _main.get_node("Player%d" % (i + 1)) as RigidBody2D
		player.bind_controller()
		player.eliminated.connect(func() -> void:
			if _round_open and _first_elim_msec < 0:
				_first_elim_msec = GameClockScript.now_msec() - _round_start_msec)
		_players.append(player)
		var bot: Node = BotScript.new()
		bot.name = "Bot%d" % i
		bot.player = player
		bot.output = player.set_input_vector
		bot.rng.seed = BotDirectorScript.bot_seed(_seed, i)
		_main.add_child(bot)
	get_root().add_child(_main)
	current_scene = _main
	_started_msec = GameClockScript.now_msec()

func _on_round_started() -> void:
	_close_round()
	if _round_log.size() >= _rounds:
		_finish()
		return
	_round_open = true
	_round_start_msec = GameClockScript.now_msec()
	_round_stage = str(_rm._current_stage.name) if _rm._current_stage != null else ""
	_round_winner = -1
	_first_elim_msec = -1
	for i in _players.size():
		_players[i].set_weapon_stats.call_deferred(load("res://resources/%s.tres" % _weapons[i]))

func _close_round() -> void:
	if not _round_open:
		return
	_round_open = false
	_round_log.append({
		"stage": _round_stage,
		"winner": _round_winner,
		"sec": snappedf(float(GameClockScript.now_msec() - _round_start_msec) / 1000.0, 0.01),
		"first_elim_sec": snappedf(float(_first_elim_msec) / 1000.0, 0.01) if _first_elim_msec >= 0 else -1.0,
		"timeout": _timed_out,
	})

func _print_diag(sec: float) -> void:
	var hill: Variant = _rm.game_mode_node().get("hill_position") if _rm.game_mode_node() != null else null
	var parts: PackedStringArray = []
	for i in _players.size():
		var bot: Node = _main.get_node("Bot%d" % i)
		var alive: bool = is_instance_valid(_players[i]) and _players[i].visible and _players[i].is_inside_tree()
		parts.append("p%d %s mode=%s goal=%s foot=%d des=%.0f wait=%.0f v=%s in=%s head=%s" % [i, Vector2i(_players[i].global_position), bot.mode, Vector2i(bot.goal), bot._standing_on(), bot._desperate_left, bot._wait_total, Vector2i(_players[i].linear_velocity), bot.last_input.snapped(Vector2(0.01,0.01)), Vector2i(_players[i].weapon_head_position())])
	for node: Node in _rm._current_stage.find_children("*", "", true, false):
		if node.has_method("hp_left"):
			parts.append("wall %s hp=%.0f hits=%d speed=%.0f" % [node.name, node.hp_left(), node.hit_count(), node.last_hit_speed()])
	print("DIAG t=%d stage=%s hill=%s | %s" % [int(sec), _round_stage, hill, " | ".join(parts)])

func _physics_process(_delta: float) -> bool:
	if _diag and _round_open:
		var sec: float = float(GameClockScript.now_msec() - _round_start_msec) / 1000.0
		if sec >= _diag_at:
			_diag_at += 20.0
			_print_diag(sec)
	if not _finishing:
		if _round_open and float(GameClockScript.now_msec() - _round_start_msec) / 1000.0 > ROUND_CAP_SEC:
			_timed_out = true
			_round_winner = -1
			_close_round()
			_finish()
		elif float(GameClockScript.now_msec() - _started_msec) / 1000.0 > MAX_GAME_SEC:
			_finish()
	return false

func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	_deferred_report.call_deferred()

func _deferred_report() -> void:
	# One more frame so the last deferred KO flush has reached MatchStats.
	await process_frame
	await process_frame
	var stats: RefCounted = _rm._stats
	var per_slot: Array[Dictionary] = []
	var total_sec: float = 0.0
	for r: Dictionary in _round_log:
		total_sec += float(r["sec"])
	for i in _weapons.size():
		var hits: int = 0
		for w: String in stats.slot_weapon_hits.get(i, {}):
			hits += int(stats.slot_weapon_hits[i][w])
		per_slot.append({
			"slot": i, "weapon": _weapons[i],
			"damage": snappedf(float(stats.damage_dealt.get(i, 0.0)), 0.1),
			"hits": hits,
			"kos": int(stats.kos.get(i, 0)),
			"self_kos": int(stats.self_kos.get(i, 0)),
			"deaths": int(stats.deaths.get(i, 0)),
			"wins": _round_log.filter(func(r: Dictionary) -> bool: return int(r["winner"]) == i).size(),
		})
	var host: RefCounted = HostSettingsScript.shared()
	var allowed_with_bots: bool = StatsSenderScript.should_send(host, StatsSenderScript.is_scripted(self, PackedStringArray()), PackedStringArray(["--bots=%d" % _weapons.size()]))
	var allowed_scripted_only: bool = StatsSenderScript.should_send(host, StatsSenderScript.is_scripted(self, PackedStringArray()), PackedStringArray())
	var sent: bool = _rm.send_telemetry()
	var senders: int = _rm.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n.get_script() == StatsSenderScript).size()
	var record: Dictionary = {
		"mode": _mode_name, "weapons": _weapons, "seed": _seed,
		"rounds": _round_log, "slots": per_slot, "round_seconds": snappedf(total_sec, 0.01),
		"share_stats_setting": host.share_stats,
		"telemetry_send_allowed": allowed_with_bots or allowed_scripted_only or sent,
		"telemetry_stats_sender_nodes": senders,
	}
	print("BALANCE " + JSON.stringify(record))
	paused = true
	_main.queue_free()
	await process_frame
	var music: Node = get_root().get_node_or_null(^"Music")
	if music != null:
		await music.release()
	var sfx: Node = get_root().get_node_or_null(^"Sfx")
	if sfx != null:
		var announcer: Node = sfx.get_node_or_null(^"Announcer")
		if announcer != null:
			announcer.set_process(false)
			if announcer.has_method("clear"):
				announcer.call("clear")
		await sfx.release()
	quit(0)
