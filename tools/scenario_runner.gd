extends SceneTree

## Headless assertion seam for combat scenarios (issue #2, AC-1/AC-2 and their
## share of DoD-1/DoD-2). Drives players through the same public interface the
## phone controller transport uses -- Player.set_input_vector() -- and asserts
## only on observable state (arm world angle, body rotation, position,
## velocity, and later damage/alive/weapon-held). Never asserts on the rig
## underneath (raycast today, joints in D2): see the "Testing Decisions"
## section of issue #2 for why.
##
##   godot --headless --path . -s tools/scenario_runner.gd -- --all
##   godot --headless --path . -s tools/scenario_runner.gd -- --scenario=aim_angle
##
## Arguments (after `--`):
##   --all                run every registered scenario
##   --scenario=<name>    run exactly one scenario by name; unknown name fails
##                        loudly rather than passing silently on a typo
##
## To add a scenario: append its name to SCENARIO_NAMES, add a matching case
## in `_run_scenario()`, and write a `_scenario_<name>() -> Array[String]`
## coroutine that builds its own stage (via `_new_stage()`), drives players
## through `set_input_vector()` (via `_spawn_player()`, which also calls the
## public `bind_controller()` so input actually takes effect), steps physics
## with `await physics_frame`, and returns a list of failure messages (an
## empty array is a pass).

const ArenaScene: PackedScene = preload("res://scenes/Arena.tscn")
const PlayerScene: PackedScene = preload("res://scenes/Player.tscn")

const SCENARIO_NAMES: PackedStringArray = ["aim_angle", "body_no_rotation"]

const ANGLE_TOLERANCE: float = 0.01
const ROTATION_TOLERANCE: float = 0.001
const LANDING_TICKS: int = 90
const COLLISION_TICKS: int = 60
## Cap how many per-tick failures a single scenario records, so a totally
## broken lock doesn't spam hundreds of near-identical lines.
const MAX_FAILURES_PER_SCENARIO: int = 5

var _scenario_filter: String = ""
var _run_all_flag: bool = false

func _initialize() -> void:
	_parse_args()

	if _scenario_filter == "" and not _run_all_flag:
		printerr("SCENARIO: pass --all or --scenario=<name> (known: %s)" % ", ".join(SCENARIO_NAMES))
		quit(2)
		return

	if _scenario_filter != "" and not SCENARIO_NAMES.has(_scenario_filter):
		printerr("SCENARIO: unknown scenario '%s' (known: %s)" % [_scenario_filter, ", ".join(SCENARIO_NAMES)])
		quit(2)
		return

	# Not awaited: this kicks off the coroutine and returns control to the
	# engine, which then drives it forward one physics tick at a time via the
	# `physics_frame` signal awaited inside the scenarios.
	_run_all()

func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--all":
			_run_all_flag = true
		elif arg.begins_with("--scenario="):
			_scenario_filter = arg.trim_prefix("--scenario=")
		else:
			printerr("SCENARIO: unrecognized argument '%s'" % arg)

func _run_all() -> void:
	var to_run: PackedStringArray = SCENARIO_NAMES if _run_all_flag else PackedStringArray([_scenario_filter])
	var pass_count: int = 0
	var fail_count: int = 0

	for name: String in to_run:
		var failures: Array[String] = await _run_scenario(name)
		if failures.is_empty():
			print("PASS  %s" % name)
			pass_count += 1
		else:
			print("FAIL  %s" % name)
			for f: String in failures:
				print("      - %s" % f)
			fail_count += 1

	print("---")
	print("%d passed, %d failed, %d total" % [pass_count, fail_count, to_run.size()])
	quit(1 if fail_count > 0 else 0)

func _run_scenario(name: String) -> Array[String]:
	match name:
		"aim_angle":
			return await _scenario_aim_angle()
		"body_no_rotation":
			return await _scenario_body_no_rotation()
		_:
			return ["unknown scenario '%s'" % name]

## AC-1: for a spread of input vectors, the arm's world angle equals the
## input vector's angle within a small tolerance. The player is parked well
## above the arena geometry so the arm's raycast tip never plants -- the
## check is purely about aim, not about plant/pole behaviour.
func _scenario_aim_angle() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var player: RigidBody2D = _spawn_player(stage, Vector2(0, -300))
	var arm: Line2D = player.get_node("Arm") as Line2D

	var spread: Array[Dictionary] = [
		{"deg": 0.0, "mag": 1.0},
		{"deg": 30.0, "mag": 0.7},
		{"deg": 90.0, "mag": 1.0},
		{"deg": 135.0, "mag": 0.5},
		{"deg": 179.0, "mag": 1.0},
		{"deg": -170.0, "mag": 0.6},
		{"deg": -90.0, "mag": 1.0},
		{"deg": -45.0, "mag": 0.3},
	]

	for sample: Dictionary in spread:
		var angle_rad: float = deg_to_rad(sample["deg"])
		var v: Vector2 = Vector2.RIGHT.rotated(angle_rad) * sample["mag"]
		player.set_input_vector(v)
		await _await_ticks(3)

		# Measured from the arm's live world geometry rather than the cached
		# tip_global_pos, which Player._update_tip() computes before the engine
		# integrates that tick's motion and so goes stale by the time it is read
		# back. Taking the arm's own point through the current transform is the
		# correct observable and removes the need to freeze the body, so this
		# check runs against a body that is actually moving.
		#
		# What this scenario does NOT prove: that body rotation cannot corrupt
		# the input frame. A player falling free of contact gets no torque, so
		# this passes with or without the rotation lock -- verified. AC-2
		# (body_no_rotation) is what guards the lock, by producing real contact.
		var observed: float = (arm.to_global(arm.points[1]) - player.global_position).angle()
		var expected: float = v.angle()
		var diff: float = absf(wrapf(observed - expected, -PI, PI))
		if diff > ANGLE_TOLERANCE:
			failures.append(
				"input angle %.1f deg (mag %.2f): expected world angle %.4f rad, observed %.4f rad (diff %.4f rad)" % [
					sample["deg"], sample["mag"], expected, observed, diff])

	await _teardown(stage)
	return failures

## AC-2: the body's rotation stays zero (within float tolerance) through a
## hard landing and through a collision with another player. Both players
## fall from height with converging horizontal velocity so the landing
## itself is hard, then get driven into each other above the knockback
## threshold so a real collision (not a quiescent body) is what's asserted
## against.
func _scenario_body_no_rotation() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()

	var player_a: RigidBody2D = _spawn_player(stage, Vector2(-150, -400))
	player_a.linear_velocity = Vector2(60, 0)
	var player_b: RigidBody2D = _spawn_player(stage, Vector2(150, -400))
	player_b.linear_velocity = Vector2(-60, 0)

	# Phase 1: hard landing under gravity.
	for i in LANDING_TICKS:
		await physics_frame
		_check_rotation(player_a, "landing tick %d" % i, failures)
		_check_rotation(player_b, "landing tick %d" % i, failures)

	# Phase 2: drive the two settled players into each other fast enough to
	# clear Player.knockback_threshold and trigger a real collision.
	player_a.linear_velocity = Vector2(320, player_a.linear_velocity.y)
	player_b.linear_velocity = Vector2(-320, player_b.linear_velocity.y)
	for i in COLLISION_TICKS:
		await physics_frame
		_check_rotation(player_a, "collision tick %d" % i, failures)
		_check_rotation(player_b, "collision tick %d" % i, failures)

	await _teardown(stage)
	return failures

func _check_rotation(player: RigidBody2D, when: String, failures: Array[String]) -> void:
	if absf(player.rotation) > ROTATION_TOLERANCE and failures.size() < MAX_FAILURES_PER_SCENARIO:
		failures.append("%s: body rotation = %.6f rad, expected ~0 (%s)" % [when, player.rotation, player.name])

func _new_stage() -> Node2D:
	var stage := Node2D.new()
	get_root().add_child(stage)
	stage.add_child(ArenaScene.instantiate())
	return stage

## Spawns a player at `pos` and binds it as a controller so that
## `set_input_vector()` -- the documented interface the phone transport
## drives the player through -- actually takes effect.
func _spawn_player(stage: Node2D, pos: Vector2) -> RigidBody2D:
	var player: RigidBody2D = PlayerScene.instantiate() as RigidBody2D
	stage.add_child(player)
	player.global_position = pos
	player.bind_controller()
	return player

func _teardown(stage: Node2D) -> void:
	stage.queue_free()
	await physics_frame

func _await_ticks(n: int) -> void:
	for i in n:
		await physics_frame
