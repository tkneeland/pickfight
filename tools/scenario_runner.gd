extends SceneTree

## Headless assertion seam for combat scenarios (issue #2, AC-1/AC-2 and their
## share of DoD-1/DoD-2), extended in D2 to the weapon rig. Drives players through the same public interface the
## phone controller transport uses -- Player.set_input_vector() -- and asserts
## only on observable state (weapon world angle and reach, body rotation, position,
## velocity, and later damage/alive/weapon-held). Never asserts on the rig
## underneath -- not on joints, drive torque or gains: ADR-0006 names a
## fallback rig that would change all of those, and this suite has to survive
## it. See the "Testing Decisions" section of issue #2.
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

const SCENARIO_NAMES: PackedStringArray = [
	"aim_angle",
	"body_no_rotation",
	"extension_tracks_drag",
	"release_eases_to_rest",
	"head_plants_terrain",
	"head_plants_player",
	"non_finite_input_rejected",
	"weapon_stats_are_swappable",
	"haft_is_non_colliding",
	"rig_freed_with_player",
]

const ANGLE_TOLERANCE: float = 0.01
const ROTATION_TOLERANCE: float = 0.001
## Pixels the settled head may sit away from the reach the drag asked for.
## Small next to the 120px reach range, and small next to the 30px step
## between the magnitudes sampled, so "reach follows the drag" cannot pass by
## the weapon sitting somewhere in the middle of its range.
const REACH_TOLERANCE: float = 6.0
## Ticks a scenario gives the weapon to reach a newly commanded angle or
## reach before measuring it. The weapon is a driven physical body, so it
## arrives over several ticks rather than teleporting; this is the settling
## allowance, never a loosening of ANGLE_TOLERANCE, which is the property
## being measured.
const SETTLE_TICKS: int = 30
## The pickaxe's full reach, as an independently written-down number rather
## than one read back out of the weapon the player is holding: a test that
## asked the weapon what its reach was would pass whatever the weapon did.
const MAX_REACH: float = 140.0
## Clear air: high enough above the arena that a full-reach weapon in any
## direction touches nothing.
const PARK_POSITION: Vector2 = Vector2(0, -600)
## Clear air with room to keep falling for a few seconds without meeting the
## arena at all.
const DEEP_PARK_POSITION: Vector2 = Vector2(0, -2000)
## Long enough for a full-reach weapon to ease all the way back in, and then
## some, so "it kept going" and "it came back out again" are both visible.
const RELEASE_TICKS: int = 60
## Below this a release is a snap rather than an ease. The weapon covers its
## whole reach range at WeaponStats.rest_return_speed, which at 400 px/s over
## 120 px is about 18 ticks; this only insists it is not near-instant.
const MIN_RELEASE_TICKS: int = 8
## Arena geometry this suite stands on, written down here rather than read
## back out of the scene: the ground's top surface, and the radii of the two
## things that rest on it.
const GROUND_TOP: float = 300.0
const PLAYER_RADIUS: float = 24.0
const HEAD_RADIUS: float = 8.0
## Slack allowed when deciding what is resting on what.
const PLANT_CLEARANCE: float = 4.0
const SETTLED_SPEED: float = 40.0
## Ticks spent pushing against a plant, and the rise that has to produce
## before the plant counts as having moved the body. A player that simply
## fell would post a negative rise.
const PUSH_TICKS: int = 30
const MIN_PUSH_RISE: float = 40.0
## How far apart two players driven identically may end up before they are
## no longer behaving the same.
const TWIN_TOLERANCE: float = 1.0
## A stat set deliberately unlike the pickaxe's, so a swap that did nothing
## cannot pass by coincidence.
const STUB_MIN_REACH: float = 40.0
const STUB_MAX_REACH: float = 60.0
## The bystander the haft is swept through: close enough that a full-reach
## head passes beyond them, far enough that the two bodies never touch.
const BYSTANDER_OFFSET: float = 90.0
const HAFT_SHOVE_TOLERANCE: float = 3.0
## A bar slid into the gap between a player and its own head: it crosses the
## haft, and it is too close in to be met by a head swung round at full
## reach.
const BAR_OFFSET: float = 70.0
const BAR_SIZE: Vector2 = Vector2(80.0, 8.0)
const LANDING_TICKS: int = 90
const COLLISION_TICKS: int = 60
## Cap how many per-tick failures a single scenario records, so a totally
## broken lock doesn't spam hundreds of near-identical lines.
const MAX_FAILURES_PER_SCENARIO: int = 5

## Set by `_teardown()`, which every scenario ends with. A GDScript runtime
## error inside a scenario abandons it and still resumes the caller with an
## empty failure list, which would otherwise be indistinguishable from a
## pass -- the one failure mode a test suite must never have.
var _scenario_completed: bool = false
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
		_scenario_completed = false
		var failures: Array[String] = await _run_scenario(name)
		if not _scenario_completed:
			failures.append("scenario did not run to completion -- look for a SCRIPT ERROR above")
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
		"extension_tracks_drag":
			return await _scenario_extension_tracks_drag()
		"release_eases_to_rest":
			return await _scenario_release_eases_to_rest()
		"head_plants_terrain":
			return await _scenario_head_plants_terrain()
		"head_plants_player":
			return await _scenario_head_plants_player()
		"non_finite_input_rejected":
			return await _scenario_non_finite_input_rejected()
		"weapon_stats_are_swappable":
			return await _scenario_weapon_stats_are_swappable()
		"haft_is_non_colliding":
			return await _scenario_haft_is_non_colliding()
		"rig_freed_with_player":
			return await _scenario_rig_freed_with_player()
		_:
			return ["unknown scenario '%s'" % name]

## AC-1: for a spread of input vectors, the weapon's world angle equals the
## input vector's angle within a small tolerance. The player is parked well
## above the arena geometry so the head never plants -- the check is purely
## about aim, not about plant behaviour.
func _scenario_aim_angle() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var player: RigidBody2D = _spawn_player(stage, PARK_POSITION)

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
		# Re-parked each sample: settling a driven weapon takes long enough
		# that an unattended player falls out of clear air onto the arena,
		# and a head jammed into the ground is a plant, not an aim test.
		# Parking leaves the body falling, so this still runs against a body
		# that is actually moving.
		player.teleport_to(PARK_POSITION)
		var angle_rad: float = deg_to_rad(sample["deg"])
		var v: Vector2 = Vector2.RIGHT.rotated(angle_rad) * sample["mag"]
		player.set_input_vector(v)
		await _await_ticks(SETTLE_TICKS)

		# Measured from the weapon's live world geometry -- where the head
		# physically is this tick -- rather than from any commanded setpoint,
		# which is what the player actually sees and which stays true whatever
		# the rig underneath turns out to be. Taking it live removes the need
		# to freeze the body, so this check runs against a body that is
		# actually moving.
		#
		# What this scenario does NOT prove: that body rotation cannot corrupt
		# the input frame. A player falling free of contact gets no torque, so
		# this passes with or without the rotation lock -- verified. AC-2
		# (body_no_rotation) is what guards the lock, by producing real contact.
		var observed: float = (player.weapon_head_position() - player.global_position).angle()
		var expected: float = v.angle()
		var diff: float = absf(wrapf(observed - expected, -PI, PI))
		if diff > ANGLE_TOLERANCE:
			failures.append(
				"input angle %.1f deg (mag %.2f): expected world angle %.4f rad, observed %.4f rad (diff %.4f rad)" % [
					sample["deg"], sample["mag"], expected, observed, diff])

	await _teardown(stage)
	return failures

## AC-3: reach follows drag magnitude across the whole range. Sampled at
## several magnitudes rather than just the ends, and checked for being
## ordered, so a weapon that only knew "in" and "out" would fail. The player
## is parked clear of geometry so nothing is obstructing the head; reach is
## measured from the head's live world position, which is what a player
## judges reach by.
func _scenario_extension_tracks_drag() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var player: RigidBody2D = _spawn_player(stage, PARK_POSITION)

	var magnitudes: PackedFloat32Array = PackedFloat32Array([0.05, 0.25, 0.5, 0.75, 1.0])
	var previous_reach: float = -1.0

	for mag: float in magnitudes:
		# Re-parked each sample for the same reason as aim_angle: the head
		# must be measured in clear air, not planted on the arena floor.
		player.teleport_to(PARK_POSITION)
		player.set_input_vector(Vector2.RIGHT * mag)
		await _await_ticks(SETTLE_TICKS)

		var reach: float = (player.weapon_head_position() - player.global_position).length()
		var expected: float = lerpf(player.weapon_min_length, MAX_REACH, mag)
		if absf(reach - expected) > REACH_TOLERANCE:
			failures.append("drag magnitude %.2f: expected reach %.1f px, observed %.1f px" % [
				mag, expected, reach])
		if reach <= previous_reach:
			failures.append("drag magnitude %.2f: reach %.1f px did not increase on the previous sample (%.1f px)" % [
				mag, reach, previous_reach])
		previous_reach = reach

	await _teardown(stage)
	return failures

## AC-4: letting go eases the weapon back to rest instead of snapping to it
## or drifting afterwards, and the angle the player last pointed at is held
## while that happens. All four of those are checked, because "eased to rest"
## is not one observation: a snap, a drift and a slow bounce past rest all
## end up at rest too.
func _scenario_release_eases_to_rest() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var player: RigidBody2D = _spawn_player(stage, PARK_POSITION)
	var rest: float = 0.0

	player.teleport_to(PARK_POSITION)
	var held_angle: float = deg_to_rad(-40.0)
	player.set_input_vector(Vector2.RIGHT.rotated(held_angle))
	await _await_ticks(SETTLE_TICKS)
	rest = player.weapon_min_length

	# Let go.
	player.set_input_vector(Vector2.ZERO)
	var previous: float = _reach_of(player)
	var ticks_to_rest: int = -1
	for i in RELEASE_TICKS:
		await physics_frame
		var reach: float = _reach_of(player)
		if reach > previous + REACH_TOLERANCE and failures.size() < MAX_FAILURES_PER_SCENARIO:
			failures.append("tick %d: reach went back out from %.1f px to %.1f px on the way to rest" % [
				i, previous, reach])
		if reach < rest - REACH_TOLERANCE and failures.size() < MAX_FAILURES_PER_SCENARIO:
			failures.append("tick %d: reach %.1f px undershot rest (%.1f px)" % [i, reach, rest])
		var angle_drift: float = absf(wrapf((player.weapon_head_position() - player.global_position).angle() - held_angle, -PI, PI))
		if angle_drift > ANGLE_TOLERANCE and failures.size() < MAX_FAILURES_PER_SCENARIO:
			failures.append("tick %d: angle drifted %.4f rad from the angle last pointed at" % [i, angle_drift])
		if ticks_to_rest < 0 and absf(reach - rest) <= REACH_TOLERANCE:
			ticks_to_rest = i
		previous = reach

	if ticks_to_rest < 0:
		failures.append("never reached rest (%.1f px) within %d ticks; ended at %.1f px" % [
			rest, RELEASE_TICKS, _reach_of(player)])
	elif ticks_to_rest < MIN_RELEASE_TICKS:
		failures.append("snapped to rest in %d ticks; a release should ease over at least %d" % [
			ticks_to_rest, MIN_RELEASE_TICKS])

	# And it stays there: released is a resting state, not a pass through one.
	await _await_ticks(SETTLE_TICKS)
	var settled: float = _reach_of(player)
	if absf(settled - rest) > REACH_TOLERANCE:
		failures.append("drifted off rest after settling: %.1f px, expected %.1f px" % [settled, rest])

	await _teardown(stage)
	return failures

## AC-5: the head plants on arena geometry and the body moves because of it.
##
## The player is dropped onto the arena floor holding the weapon short and
## pointed down, so it comes to rest standing on its pickaxe with its body
## clear of the ground -- that gap is the evidence that the head, and not the
## body, is what the arena is holding up. Then the drag goes to full reach:
## the only thing that can move the player from there is the weapon pushing
## against what it is planted on.
func _scenario_head_plants_terrain() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var player: RigidBody2D = _spawn_player(stage, Vector2(0, 100))

	# Short weapon, straight down: land on the head.
	player.set_input_vector(Vector2.DOWN * 0.05)
	await _await_ticks(LANDING_TICKS)

	var planted_y: float = player.global_position.y
	var head_y: float = player.weapon_head_position().y
	if absf(player.linear_velocity.y) > SETTLED_SPEED:
		failures.append("player never settled on its head: vertical speed %.1f px/s" % player.linear_velocity.y)
	if planted_y + PLAYER_RADIUS > GROUND_TOP - PLANT_CLEARANCE:
		failures.append("player body reached the floor (y %.1f); it should be standing on the head, not on itself" % planted_y)
	if head_y + HEAD_RADIUS > GROUND_TOP + PLANT_CLEARANCE:
		failures.append("head sank %.1f px into the floor; it should be planted on top of it" % (
			head_y + HEAD_RADIUS - GROUND_TOP))

	# Full reach against the plant: push off.
	player.set_input_vector(Vector2.DOWN)
	var highest: float = planted_y
	for _i in PUSH_TICKS:
		await physics_frame
		highest = minf(highest, player.global_position.y)

	var risen: float = planted_y - highest
	if risen < MIN_PUSH_RISE:
		failures.append("pushing against the plant raised the body %.1f px, expected more than %.1f px" % [
			risen, MIN_PUSH_RISE])

	await _teardown(stage)
	return failures

## AC-6: another player's body is terrain too. Same shape as
## head_plants_terrain, with an opponent standing in for the floor: one
## player settles standing on its head on top of another, its own body clear
## of them, and then pushes off.
func _scenario_head_plants_player() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()

	var under: RigidBody2D = _spawn_player(stage, Vector2(0, 200))
	await _await_ticks(LANDING_TICKS)

	var over: RigidBody2D = _spawn_player(stage, Vector2(0, -100))
	over.set_input_vector(Vector2.DOWN * 0.25)
	await _await_ticks(LANDING_TICKS)

	var planted_y: float = over.global_position.y
	var gap: float = under.global_position.y - planted_y
	if absf(over.linear_velocity.y) > SETTLED_SPEED:
		failures.append("player never settled on its head: vertical speed %.1f px/s" % over.linear_velocity.y)
	if gap < 2.0 * PLAYER_RADIUS + PLANT_CLEARANCE:
		failures.append("bodies %.1f px apart: the two players are touching, so this is body contact, not a plant" % gap)
	var head_gap: float = (under.global_position.y - PLAYER_RADIUS) - (over.weapon_head_position().y + HEAD_RADIUS)
	if absf(head_gap) > PLANT_CLEARANCE:
		failures.append("head is %.1f px from the other player's surface; it should be resting on it" % head_gap)

	var highest: float = planted_y
	over.set_input_vector(Vector2.DOWN)
	for _i in PUSH_TICKS:
		await physics_frame
		highest = minf(highest, over.global_position.y)

	var risen: float = planted_y - highest
	if risen < MIN_PUSH_RISE:
		failures.append("pushing off the other player raised the body %.1f px, expected more than %.1f px" % [
			risen, MIN_PUSH_RISE])

	await _teardown(stage)
	return failures

## AC-13: a NaN or infinity in the input vector produces no motion and no
## corruption. Measured against a twin driven identically up to the point of
## corruption and then told "not touching", because that is exactly what a
## rejected vector has to look like: same weapon, same body, same place. A
## NaN that reached a force call would not merely move the wrong way, it
## would put the body somewhere that is not a number for the rest of the
## session, so finiteness is checked every tick as well.
func _scenario_non_finite_input_rejected() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()

	# Parked far higher than PARK_POSITION: this scenario runs long enough
	# for a falling player to reach the arena, and the twins sit either side
	# of the stage where the platforms are not symmetric -- landing on
	# different geometry would separate them for reasons that have nothing to
	# do with the input.
	var spoiled_spawn: Vector2 = DEEP_PARK_POSITION + Vector2(-200, 0)
	var control_spawn: Vector2 = DEEP_PARK_POSITION + Vector2(200, 0)
	var spoiled: RigidBody2D = _spawn_player(stage, spoiled_spawn)
	var control: RigidBody2D = _spawn_player(stage, control_spawn)

	var held: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(-60.0)) * 0.8
	spoiled.set_input_vector(held)
	control.set_input_vector(held)
	await _await_ticks(SETTLE_TICKS)

	var poison: Array[Vector2] = [
		Vector2(NAN, 0.0),
		Vector2(0.0, NAN),
		Vector2(NAN, NAN),
		Vector2(INF, 0.0),
		Vector2(0.0, -INF),
		Vector2(INF, NAN),
	]

	for i in RELEASE_TICKS:
		spoiled.set_input_vector(poison[i % poison.size()])
		control.set_input_vector(Vector2.ZERO)
		await physics_frame
		if failures.size() >= MAX_FAILURES_PER_SCENARIO:
			continue
		var head: Vector2 = spoiled.weapon_head_position()
		if not _is_finite_vector(spoiled.global_position) or not _is_finite_vector(spoiled.linear_velocity) or not _is_finite_vector(head):
			failures.append("tick %d: non-finite state reached the body (pos %s, vel %s, head %s)" % [
				i, spoiled.global_position, spoiled.linear_velocity, head])
			continue
		var drift: float = (
			(spoiled.global_position - spoiled_spawn) - (control.global_position - control_spawn)).length()
		if drift > TWIN_TOLERANCE:
			failures.append("tick %d: body moved %.2f px differently from the twin that was told nothing" % [i, drift])
		var reach_drift: float = absf(_reach_of(spoiled) - _reach_of(control))
		if reach_drift > TWIN_TOLERANCE:
			failures.append("tick %d: reach differs from the twin by %.2f px" % [i, reach_drift])

	await _teardown(stage)
	return failures

## AC-15: the weapon's properties are data, not constants baked into the
## player. Swapping the stat set for a shorter one changes what the same drag
## produces -- reach at full drag, and where "rest" is -- which is what makes
## the indirection real rather than decorative.
func _scenario_weapon_stats_are_swappable() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var player: RigidBody2D = _spawn_player(stage, PARK_POSITION)

	player.teleport_to(PARK_POSITION)
	player.set_input_vector(Vector2.RIGHT)
	await _await_ticks(SETTLE_TICKS)
	var pickaxe_reach: float = _reach_of(player)
	if absf(pickaxe_reach - MAX_REACH) > REACH_TOLERANCE:
		failures.append("before the swap, full drag reached %.1f px, expected %.1f px" % [
			pickaxe_reach, MAX_REACH])

	var stub := WeaponStats.new()
	stub.min_reach = STUB_MIN_REACH
	stub.max_reach = STUB_MAX_REACH
	player.set_weapon_stats(stub)
	await _await_ticks(SETTLE_TICKS)

	player.teleport_to(PARK_POSITION)
	player.set_input_vector(Vector2.RIGHT)
	await _await_ticks(SETTLE_TICKS)
	var stub_reach: float = _reach_of(player)
	if absf(stub_reach - STUB_MAX_REACH) > REACH_TOLERANCE:
		failures.append("after the swap, full drag reached %.1f px, expected %.1f px" % [
			stub_reach, STUB_MAX_REACH])

	player.set_input_vector(Vector2.ZERO)
	await _await_ticks(SETTLE_TICKS)
	var stub_rest: float = _reach_of(player)
	if absf(stub_rest - STUB_MIN_REACH) > REACH_TOLERANCE:
		failures.append("after the swap, rest sat at %.1f px, expected %.1f px" % [
			stub_rest, STUB_MIN_REACH])

	await _teardown(stage)
	return failures

## AC-14: the haft passes through what the head is stopped by.
##
## Both halves are checked against the same obstacle, because "it went
## through" only means something next to "and the head could not". A player
## sweeps its weapon at full reach over an opponent standing well inside that
## reach: the head arrives past them, the haft lies straight through their
## body, and they are not shoved -- which is the point, since a solid haft
## would let anyone push people off a ledge by slowly extending sideways.
## Then a bar is slid into the gap between the player and its own head, where
## it crosses the haft and touches nothing else: the weapon holds full reach
## through it, and on release the head cannot come back past it.
func _scenario_haft_is_non_colliding() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()

	var player: RigidBody2D = _spawn_player(stage, Vector2(0, 200))
	var bystander: RigidBody2D = _spawn_player(stage, Vector2(BYSTANDER_OFFSET, 200))
	await _await_ticks(LANDING_TICKS)
	var bystander_start: Vector2 = bystander.global_position

	# Up to full reach in clear air, then sweep across the bystander. The head
	# travels round at full reach, so it never passes through them: only the
	# haft does.
	player.set_input_vector(Vector2.UP)
	await _await_ticks(SETTLE_TICKS)
	player.set_input_vector(Vector2.RIGHT)
	await _await_ticks(SETTLE_TICKS * 2)

	var swept_reach: float = _reach_of(player)
	if absf(swept_reach - MAX_REACH) > REACH_TOLERANCE:
		failures.append("swinging across the bystander left the weapon at %.1f px instead of full reach %.1f px" % [
			swept_reach, MAX_REACH])
	var body_gap: float = (bystander.global_position - player.global_position).length()
	if body_gap < 2.0 * PLAYER_RADIUS + PLANT_CLEARANCE:
		failures.append("the two bodies closed to %.1f px, so anything the bystander did was body contact, not the haft" % body_gap)
	var shoved: float = (bystander.global_position - bystander_start).length()
	if shoved > HAFT_SHOVE_TOLERANCE:
		failures.append("the haft shoved the bystander %.1f px; it should pass straight through them" % shoved)

	# Back to vertical, then slide a bar into the gap between the player and
	# its own head: it crosses the haft and nothing else.
	player.set_input_vector(Vector2.UP)
	await _await_ticks(SETTLE_TICKS * 2)
	var bar_centre: Vector2 = player.global_position - Vector2(0, BAR_OFFSET)
	_add_bar(stage, bar_centre, BAR_SIZE)
	await _await_ticks(SETTLE_TICKS * 2)

	var through_reach: float = _reach_of(player)
	if absf(through_reach - MAX_REACH) > REACH_TOLERANCE:
		failures.append("the bar disturbed the haft: reach %.1f px instead of full reach %.1f px" % [
			through_reach, MAX_REACH])

	# Release: the head has to come back down through the same bar, and
	# cannot. What closes instead is the player, hauled up its own weapon to
	# the underside of the bar -- so the head is measured where it ends up in
	# the world, not by how far it is from a body that moved.
	var bar_top: float = bar_centre.y - BAR_SIZE.y * 0.5
	player.set_input_vector(Vector2.ZERO)
	await _await_ticks(SETTLE_TICKS * 2)
	var head_end: Vector2 = player.weapon_head_position()
	var sunk: float = (head_end.y + HEAD_RADIUS) - bar_top
	if sunk > PLANT_CLEARANCE:
		failures.append("the head came back %.1f px down through the bar its own haft passes through" % sunk)
	if _reach_of(player) <= player.weapon_min_length + REACH_TOLERANCE:
		failures.append("the weapon returned the whole way to rest, so the bar stopped nothing")

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

func _is_finite_vector(v: Vector2) -> bool:
	return is_finite(v.x) and is_finite(v.y)

func _reach_of(player: RigidBody2D) -> float:
	return (player.weapon_head_position() - player.global_position).length()

func _check_rotation(player: RigidBody2D, when: String, failures: Array[String]) -> void:
	if absf(player.rotation) > ROTATION_TOLERANCE and failures.size() < MAX_FAILURES_PER_SCENARIO:
		failures.append("%s: body rotation = %.6f rad, expected ~0 (%s)" % [when, player.rotation, player.name])

## A length of static terrain, placed where a scenario needs one.
func _add_bar(stage: Node2D, centre: Vector2, size: Vector2) -> StaticBody2D:
	var bar := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	collision.shape = rect
	bar.add_child(collision)
	stage.add_child(bar)
	bar.global_position = centre
	return bar

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
	_scenario_completed = true
	stage.queue_free()
	await physics_frame

func _await_ticks(n: int) -> void:
	for i in n:
		await physics_frame

## The weapon rig is built beside the player, not under it, so freeing a
## player does not free its weapon. Left orphaned it keeps simulating with a
## live head on the head layer -- able to hit people on behalf of someone who
## is gone. Nothing frees a player yet; death and the round loop both will.
func _scenario_rig_freed_with_player() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var player: RigidBody2D = _spawn_player(stage, Vector2(0, -200))
	await _await_ticks(5)

	if _count_rigs(stage) != 1:
		failures.append("expected exactly 1 weapon rig after spawn, found %d" % _count_rigs(stage))

	player.queue_free()
	await _await_ticks(5)

	var left: int = _count_rigs(stage)
	if left != 0:
		failures.append("player freed but %d weapon rig(s) still in the tree" % left)

	await _teardown(stage)
	return failures

func _count_rigs(node: Node) -> int:
	var count: int = 0
	for child: Node in node.get_children():
		if "WeaponRig" in child.name:
			count += 1
		count += _count_rigs(child)
	return count
