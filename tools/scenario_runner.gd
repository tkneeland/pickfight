extends SceneTree

## Headless assertion seam for combat scenarios (issue #2, AC-1/AC-2 and their
## share of DoD-1/DoD-2), extended in D2 to the weapon rig and in D3 to
## damage, death and clash. Drives players through the same public interface the
## phone controller transport uses -- Player.set_input_vector() -- and asserts
## only on observable state (weapon world angle and reach, body rotation, position,
## velocity, accumulated damage, deaths, which weapon is held). Never asserts on the rig
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
## Preloaded, not referenced by `class_name`: the global class cache lives in
## the gitignored `.godot/` and only an editor run builds it, so a fresh clone
## cannot resolve the name.
const WeaponStatsType := preload("res://scripts/WeaponStats.gd")

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
	"head_does_not_tunnel_thin_platform",
	"head_strike_damage_scales",
	"body_collision_knockback_no_damage",
	"damage_kills",
	"ringout_kills_at_full_health",
	"ringout_then_next_round_survives",
	"heads_do_not_interpenetrate",
	"clash_higher_drive_force_wins",
	"heads_do_not_tunnel_head",
	"damage_reddens_fill_identity_persists",
	"identity_colours_match_controller_page",
	"weapon_silhouette_matches_head_shape",
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
## The thinner of the arena's two slabs (PlatformRight), written down here
## rather than read back out of the scene: 240x24 centred at (320, 60), so its
## top surface is y=48 and its underside y=72. This is the geometry the
## operator's boost move put the head through, and 24 px is thin enough that a
## head moving at swing speed crosses the whole slab inside one 60 Hz tick.
const THIN_PLATFORM_CENTRE: Vector2 = Vector2(320.0, 60.0)
const THIN_PLATFORM_HALF_WIDTH: float = 120.0
const THIN_PLATFORM_HALF_HEIGHT: float = 12.0
## The boost move the defect was reported against, as a parameter sweep:
## start this far above the slab, hold the weapon wound in for this many
## ticks, then slam it to full reach straight down, either already falling or
## from rest. 8 x 3 x 2 = 48 trials.
const BOOST_START_HEIGHTS: PackedFloat32Array = [
	30.0, 50.0, 70.0, 90.0, 110.0, 130.0, 150.0, 170.0]
const BOOST_WINDUP_TICKS: PackedInt32Array = [1, 3, 5]
const BOOST_FALLING_FLAGS: PackedInt32Array = [1, 0]
const BOOST_FALL_SPEED: float = 450.0
## Long enough for the head to reach the slab and the boost to play out from
## the highest start height sampled.
const BOOST_TICKS: int = 60
## Ticks between trials, long enough for the freed player's weapon rig to
## leave the physics world before the next trial's is built.
const BOOST_RESET_TICKS: int = 4
## Cap how many per-tick failures a single scenario records, so a totally
## broken lock doesn't spam hundreds of near-identical lines.
const MAX_FAILURES_PER_SCENARIO: int = 5

## --- Damage, death and clash ------------------------------------------------

## The damage a player dies at, written down here rather than read off the
## player: a test that asked the player what its own threshold was would pass
## whatever the player decided.
const DEATH_DAMAGE: float = 100.0

## Half-sweeps for the swing spread. The attacker starts this far short of the
## victim and is commanded this far past them, so the head crosses the victim
## in the middle of its travel -- at speed, rather than decelerating onto
## them. A longer sweep is a faster head, which is the independent variable
## these trials turn. It stops at 1.3 because the swing saturates there --
## measured, a 1.8 rad half-sweep arrives at 2472 px/s against 1.3's 2476,
## so a longer wind-up buys no more speed and the pair would say nothing.
const SWING_HALF_ANGLES: PackedFloat32Array = [0.5, 0.9, 1.3]
## Two trials' head speeds have to differ by at least this much before the
## pair is allowed to say anything about damage scaling with speed.
const MIN_SPEED_STEP: float = 150.0
## The wind-up, in two parts. The weapon is first turned to the wind-up angle
## wound all the way in, where the head stays inside 26 px of its own player
## and so cannot touch anything, and only then pushed out to full reach. Done
## the other way round -- turning a fully extended weapon -- the head ploughs
## through wherever the victim is standing on its way to the wind-up pose,
## which both hits them before the trial starts and leaves the weapon jammed
## against them instead of wound up. Starting every wind-up from wound in
## also means every swing starts from the same pose, which is what makes a
## rehearsal worth replaying.
const RETRACT_TICKS: int = 20
const EXTEND_TICKS: int = 15
## Ticks a swing is watched for.
const SWING_TICKS: int = 40
## Ticks watched after a hit lands, enough to read the damage and stop.
const POST_HIT_TICKS: int = 2
## The slow-contact anchor: the attacker holds its weapon out and walks the
## head into the victim at this speed. Well under a swing, and the point of
## the trial is that it hurts nobody.
const CREEP_SPEED: float = 250.0
const CREEP_TICKS: int = 25
## Where the victim stands for the creep: a little beyond a fully extended
## head, and far enough out that the two bodies never meet inside
## CREEP_TICKS.
const CREEP_DISTANCE: float = 185.0
## How far inside the rehearsed arc a victim is planted. The replay of a
## swing is not identical to the rehearsal of it to the last pixel -- the
## weapon starts each one from wherever the last left it -- and a target
## sitting exactly on the rehearsed path can be missed by a few pixels.
## Planting it slightly inside the arc costs a little of the head's speed at
## contact and buys the trial back.
const ARC_INSET: float = 10.0
## How many swings a victim is given to die under. Three clean strikes should
## do it; this is the runaway guard, not the expectation.
const MAX_KILL_SWINGS: int = 8
## Ticks a ring-out is waited for: the fall from the respawn height to the
## kill zone, with room to spare.
const RINGOUT_TICKS: int = 240
## Off the end of the ground (which spans -600..600) but still over the kill
## zone (-700..700), and clear of both platforms.
const RINGOUT_START: Vector2 = Vector2(650, -200)
## Where a ring-out victim is brought back for the next round: standing on
## the middle of the ground, nowhere near an edge or the kill zone.
const NEXT_ROUND_SPAWN: Vector2 = Vector2(0, GROUND_TOP - PLAYER_RADIUS)
## How long a player brought back into a round is watched for. The reported
## re-elimination landed two ticks in; this is a full second of play.
const NEXT_ROUND_WATCH_TICKS: int = 60
## How far a player standing at NEXT_ROUND_SPAWN may have drifted by the end
## of the watch. Settling onto the ground moves it a few pixels; being put
## back where it died moves it hundreds.
const NEXT_ROUND_DRIFT: float = 40.0
## Ticks between a ring-out and the next round, standing in for
## RoundManager's round-end pause: long enough for the elimination's deferred
## freeze to land, as it always has by the time a real round starts.
const NEXT_ROUND_PAUSE_TICKS: int = 30
## Ring-out-then-next-round cycles run back to back: the live bug repeated
## every round, so one cycle passing is not enough.
const NEXT_ROUND_CYCLES: int = 3

## Body-collision knockback: one player run into the other this fast from
## 160 px away, which linear damping brings down to about 430 px/s by the
## time they meet -- still well over Player.knockback_threshold. The player
## who was standing still has to come out of it moving at least
## MIN_REBOUND_SPEED. A plain rigid collision has no bounce, so anything the
## standing player gains is the knockback and nothing else.
const BUMP_SPEED: float = 600.0
const MIN_REBOUND_SPEED: float = 100.0
## And has to be carried somewhere by it, not merely twitch.
const MIN_SHOVE_DISTANCE: float = 40.0
const BUMP_TICKS: int = 60

## Clash: two players this far apart, each commanding full reach at the other.
## 220 px leaves each head 60 px short of where it is being told to go, so
## both drives stay pushing for the whole measurement instead of arriving.
## CLASH_TICKS is then long enough that holding is a state and not a moment
## passed through: two seconds of contact under full push.
const CLASH_SEPARATION: float = 220.0
const CLASH_TICKS: int = 120
## Ticks over which the two heads are walked into each other when a clash
## needs to be established rather than tested. Ramping the commanded reach
## rather than asking for all of it at once brings them together at a rate
## the contact can catch -- 13 px a tick at its quickest, measured, against
## the 16 px at which two heads touch -- instead of the 23 px a tick a
## straight command produces, which arrives faster than an ordinary contact
## catches and is left to `WeaponHead`'s pair correction to seat. Both are
## asserted in `heads_do_not_interpenetrate`; a contest is measured off the
## walked one so that what it reports is the drives contesting and not a
## correction settling.
const CLASH_APPROACH_TICKS: int = 90
## Ticks the same two heads are then sent at each other over, full reach
## commanded outright rather than ramped. Long enough for both weapons to
## cross the 180 px between them at rest and hold wherever they end up.
const SEND_TICKS: int = 60
## Solver penetration allowed between two touching heads before they count as
## having gone into each other rather than met.
const HEAD_OVERLAP_ALLOWANCE: float = 4.0
## How close the heads have to get before a clash trial counts as having
## happened at all, so a scenario cannot pass by the two never meeting.
const CLASH_CONTACT_SLACK: float = 8.0
## What a stronger weapon is given in the clash, and the ground it then has to
## win: the meeting point has to sit at least this far onto the weaker
## player's side of the midline between the two bodies. With equal weapons
## symmetry puts it on the midline, so this margin is the whole difference.
const STRONG_FORCE_MULTIPLIER: float = 4.0
const MIN_GROUND_WON: float = 20.0
## How far off the midline the meeting point of two identical weapons may sit
## before the clash is not symmetric after all.
const SYMMETRIC_CLASH_TOLERANCE: float = 8.0

## Head-versus-head tunnelling sweep: approach directions, and the speed each
## player is thrown at the other with. Both hold their heads out at each
## other, so closing speed is twice the charge speed -- up to 3600 px/s, or
## 60 px in a 60 Hz tick against a 16 px head.
const CHARGE_ANGLES: PackedFloat32Array = [0.0, 45.0, 90.0, 135.0]
const CHARGE_SPEEDS: PackedFloat32Array = [600.0, 1200.0, 1800.0]
## Far enough apart that both weapons settle fully extended without touching
## (2 x 140 px of reach inside 340 px), so every trial starts from a real
## block pose and the whole closing speed is spent on the contact.
const CHARGE_SEPARATION: float = 340.0
const CHARGE_TICKS: int = 45

## Damage display and identity (AC-16, AC-17, and the D4 scope change).
## Two arbitrary, clearly distinct identity colours -- not the real
## SLOT_COLORS pairing, which `identity_colours_match_controller_page` checks
## on its own terms by parsing both source files.
const IDENTITY_A_COLOR: Color = Color(0.15, 0.4, 1.0, 1.0)
const IDENTITY_B_COLOR: Color = Color(0.15, 0.8, 0.3, 1.0)
## Damage levels sampled: roughly 0%, 50% and 95% of DEATH_DAMAGE, as the
## deliverable asks for -- 95 rather than 100 so the victim does not die and
## get teleported to the respawn point mid-measurement.
const DAMAGE_SAMPLES: PackedFloat32Array = [0.0, 50.0, 95.0]
## How far apart (per RGB channel, root-sum-square) two colours must be to
## count as "distinguishable" for the identity check.
const DISTINCT_COLOR_MIN_DISTANCE: float = 0.2
## How far a colour that is supposed to be constant may drift and still count
## as unchanged.
const COLOR_MATCH_TOLERANCE: float = 0.001
const CONTROLLER_PAGE_PATH: String = "res://controller/index.html"
const MAIN_SCENE_PATH: String = "res://scenes/Main.tscn"
## Slack for comparing a colour parsed from a CSS hex triplet (8-bit channels)
## against one parsed from a Godot float literal -- a hair over 1/255.
const SLOT_COLOR_TOLERANCE: float = 0.01
## A rectangular head visibly different from a square in both dimensions, so
## a hardcoded square could not pass this by accident.
const RECT_HEAD_SIZE: Vector2 = Vector2(40.0, 12.0)
const HEAD_SHAPE_TOLERANCE: float = 0.5

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
		"head_does_not_tunnel_thin_platform":
			return await _scenario_head_does_not_tunnel_thin_platform()
		"head_strike_damage_scales":
			return await _scenario_head_strike_damage_scales()
		"body_collision_knockback_no_damage":
			return await _scenario_body_collision_knockback_no_damage()
		"damage_kills":
			return await _scenario_damage_kills()
		"ringout_kills_at_full_health":
			return await _scenario_ringout_kills_at_full_health()
		"ringout_then_next_round_survives":
			return await _scenario_ringout_then_next_round_survives()
		"heads_do_not_interpenetrate":
			return await _scenario_heads_do_not_interpenetrate()
		"clash_higher_drive_force_wins":
			return await _scenario_clash_higher_drive_force_wins()
		"heads_do_not_tunnel_head":
			return await _scenario_heads_do_not_tunnel_head()
		"damage_reddens_fill_identity_persists":
			return await _scenario_damage_reddens_fill_identity_persists()
		"identity_colours_match_controller_page":
			return await _scenario_identity_colours_match_controller_page()
		"weapon_silhouette_matches_head_shape":
			return await _scenario_weapon_silhouette_matches_head_shape()
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

## HG-2: the head does not tunnel through a thin platform.
##
## The operator hit this in real play doing the boost move -- swing the
## pickaxe hard straight down to fling the body upward -- over the arena's
## 24 px slabs: the head occasionally ended up under the platform instead of
## planted on it, which loses both the plant and the boost and drops the
## player off the stage.
##
## Swept rather than replayed. The breach rate is roughly 1 in 48, so a
## scenario that replayed only the one combination known to break would go
## green on a fix that merely moved the flake to a neighbouring start height.
## The sweep is the parameter space around the reported move: eight start
## heights, three wind-up lengths, falling and from rest.
##
## A breach is the head ending up entirely below the slab's underside while
## still horizontally inside it -- through the slab, not round its edge. The
## bar is zero: "shallower" is not a pass, because a head that has crossed
## the surface at all has lost the plant the player aimed for.
func _scenario_head_does_not_tunnel_thin_platform() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()

	var platform_top: float = THIN_PLATFORM_CENTRE.y - THIN_PLATFORM_HALF_HEIGHT
	var platform_bottom: float = THIN_PLATFORM_CENTRE.y + THIN_PLATFORM_HALF_HEIGHT
	var trials: int = 0
	var breaches: int = 0

	for height: float in BOOST_START_HEIGHTS:
		for windup: int in BOOST_WINDUP_TICKS:
			for falling_flag: int in BOOST_FALLING_FLAGS:
				var falling: bool = falling_flag == 1
				trials += 1

				# A player per trial, freed at the end of it. Every trial then
				# starts from the pose a player actually enters play in --
				# weapon wound in and sideways, everything at rest -- and no
				# trial can inherit momentum or a half-settled weapon from the
				# one before it. It also makes the wind-up below a real whip
				# from sideways to straight down, which is where the head
				# picks up the speed that does the damage here.
				var start := Vector2(THIN_PLATFORM_CENTRE.x, platform_top - height)
				var player: RigidBody2D = _spawn_player(stage, start)
				await physics_frame
				if falling:
					player.linear_velocity = Vector2(0.0, BOOST_FALL_SPEED)

				for _w in windup:
					player.set_input_vector(Vector2.DOWN * 0.05)
					await physics_frame

				player.set_input_vector(Vector2.DOWN)
				var deepest: float = -INF
				for _t in BOOST_TICKS:
					await physics_frame
					var head: Vector2 = player.weapon_head_position()
					# Only counted while the head is well inside the slab's
					# span: round the edge and down is legitimate travel, not
					# a breach.
					if absf(head.x - THIN_PLATFORM_CENTRE.x) > THIN_PLATFORM_HALF_WIDTH - HEAD_RADIUS:
						continue
					if head.y - HEAD_RADIUS > platform_bottom:
						deepest = maxf(deepest, head.y - platform_top)

				if deepest > -INF:
					breaches += 1
					if failures.size() < MAX_FAILURES_PER_SCENARIO:
						failures.append(
							"start %.0f px above the slab, %d-tick wind-up, %s: head ended %.1f px past the top of a 24 px platform" % [
								height, windup, "falling" if falling else "from rest", deepest])

				player.queue_free()
				await _await_ticks(BOOST_RESET_TICKS)

	if breaches > 0:
		failures.append("%d of %d boost trials put the head through the platform" % [breaches, trials])

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

	var stub := WeaponStatsType.new()
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

# --- Damage, death and clash ------------------------------------------------

## AC-7: a head striking a player damages them, and the faster the head is
## moving the more it takes off.
##
## Each trial is one swing at a fresh victim, so every strike is measured
## against a player who has taken nothing yet and no trial inherits the one
## before it. Speed is the independent variable and is turned by sweeping the
## head through a longer arc, not by asking the weapon to go faster: the
## attacker winds up short of the victim and is told to finish past them, so
## the head crosses them mid-sweep. Both sides of the claim are then measured
## from outside the player -- damage off the victim's own accumulated total,
## speed off how far the head visibly moved in the tick before it landed --
## so nothing here recomputes what the strike rule computes.
##
## The anchors at each end are what make it a scaling law rather than a list:
## walking an extended head into someone at CREEP_SPEED has to take nothing
## off them at all, and the hardest swing in the spread has to sit inside the
## pacing the design asks for -- more than one strike to kill, no more than
## three.
func _scenario_head_strike_damage_scales() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var centre: Vector2 = DEEP_PARK_POSITION
	var attacker: RigidBody2D = _spawn_player(stage, centre)
	await physics_frame
	_brace(attacker)

	var results: Array[Dictionary] = []
	for half_angle: float in SWING_HALF_ANGLES:
		var aim: Dictionary = await _rehearse_swing(attacker, centre, half_angle)
		var victim: RigidBody2D = _spawn_player(stage, aim["point"])
		await physics_frame
		_brace(victim)
		var hit: Dictionary = await _swing_at(attacker, victim, centre, half_angle, aim["point"])
		results.append(hit)
		print("      swing %.2f rad: head %.0f px/s, damage %.1f, closest %.1f px" % [
			half_angle, hit["speed"], hit["damage"], hit["closest"]])
		if not hit["landed"]:
			failures.append("a %.2f rad swing never reached the victim at all" % half_angle)
		elif hit["damage"] <= 0.0:
			failures.append("a %.2f rad swing landed at %.0f px/s and took nothing off the victim" % [
				half_angle, hit["speed"]])
		victim.queue_free()
		await _await_ticks(BOOST_RESET_TICKS)

	for i in range(1, results.size()):
		var slower: Dictionary = results[i - 1]
		var faster: Dictionary = results[i]
		if faster["speed"] < slower["speed"] + MIN_SPEED_STEP:
			failures.append("the sweep did not produce a faster head: %.0f px/s after %.0f px/s" % [
				faster["speed"], slower["speed"]])
		elif faster["damage"] <= slower["damage"]:
			failures.append("a head at %.0f px/s dealt %.1f, no more than the %.1f dealt at %.0f px/s" % [
				faster["speed"], faster["damage"], slower["damage"], slower["speed"]])

	# The slow anchor: an extended head walked into someone is not a strike.
	# Its own attacker, because the creep is the body carrying the head in
	# and the swinger above is braced.
	var walker: RigidBody2D = _spawn_player(stage, centre + Vector2.DOWN * CREEP_DISTANCE)
	var bystander: RigidBody2D = _spawn_player(stage, centre + Vector2.DOWN * CREEP_DISTANCE + Vector2.RIGHT * CREEP_DISTANCE)
	await physics_frame
	var creep: Dictionary = await _creep_into(walker, bystander, centre + Vector2.DOWN * CREEP_DISTANCE)
	print("      creep: head %.0f px/s, damage %.1f, closest %.1f px" % [
		creep["speed"], creep["damage"], creep["closest"]])
	if not creep["landed"]:
		failures.append("the creep never reached the bystander, so it proves nothing")
	elif creep["damage"] > 0.0:
		failures.append("walking a head into someone at %.0f px/s took %.1f off them; only a swing should hurt" % [
			creep["speed"], creep["damage"]])
	if results.size() > 0 and creep["speed"] >= float(results[0]["speed"]):
		failures.append("the creep moved the head at %.0f px/s, no slower than the gentlest swing (%.0f px/s)" % [
			creep["speed"], results[0]["speed"]])

	# The pacing the design asks for: a strike is a commitment, not a
	# one-shot, and an exchange is over in a handful of them.
	if results.size() > 0:
		var hardest: float = float(results[results.size() - 1]["damage"])
		if hardest >= DEATH_DAMAGE:
			failures.append("the hardest strike deals %.1f and kills outright from full health (%.1f)" % [
				hardest, DEATH_DAMAGE])
		if hardest * 3.0 < DEATH_DAMAGE:
			failures.append("the hardest strike deals %.1f, so killing takes more than 3 of them (%.1f to kill)" % [
				hardest, DEATH_DAMAGE])

	await _teardown(stage)
	return failures

## AC-8: bumping into someone shoves them and takes nothing off them.
##
## The load-bearing half of ADR-0005's split. Two players are driven into each
## other well above Player.knockback_threshold with their weapons pointed
## straight up and out of the way, so body contact is the only thing that
## happens. The shove is asserted as well as the absence of damage, because
## "no damage" on its own also describes a collision that never happened --
## and nothing here bounces on its own: rigid bodies default to no
## restitution, so a rebound is the knockback and nothing else.
func _scenario_body_collision_knockback_no_damage() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()

	# In clear air, not on the floor: ground friction stops a shove inside
	# 35 px, which is less than it takes to cross the gap, so two players
	# slid at each other along the ground never actually meet. Both fall
	# equally while this runs, so the closing is the horizontal drive alone.
	#
	# One player charges and the other stands still, rather than both
	# charging: head-on and symmetric, each shoves the other by exactly half
	# the closing speed and the two cancel to a dead stop, which is a real
	# outcome but shows nothing. Someone standing still who ends up moving
	# has unambiguously been shoved.
	var charger: RigidBody2D = _spawn_player(stage, DEEP_PARK_POSITION - Vector2(80, 0))
	var bumped: RigidBody2D = _spawn_player(stage, DEEP_PARK_POSITION + Vector2(80, 0))
	# Weapons wound in and pointed up, so neither head can touch the other
	# player and body contact is the only thing under test.
	charger.set_input_vector(Vector2.UP * 0.05)
	bumped.set_input_vector(Vector2.UP * 0.05)
	await _await_ticks(SETTLE_TICKS)

	var started_at: float = bumped.global_position.x
	charger.linear_velocity = Vector2(BUMP_SPEED, charger.linear_velocity.y)

	var closest: float = INF
	var shoved_speed: float = 0.0
	for _i in BUMP_TICKS:
		await physics_frame
		closest = minf(closest, (bumped.global_position - charger.global_position).length())
		shoved_speed = maxf(shoved_speed, bumped.linear_velocity.x)

	var shoved_by: float = bumped.global_position.x - started_at
	if closest > 2.0 * PLAYER_RADIUS + PLANT_CLEARANCE:
		failures.append("the two bodies never touched (closest %.1f px), so nothing was tested" % closest)
	if shoved_speed < MIN_REBOUND_SPEED:
		failures.append("the bump shoved nobody: the standing player reached %.0f px/s" % shoved_speed)
	if shoved_by < MIN_SHOVE_DISTANCE:
		failures.append("the standing player was moved %.1f px by being run into" % shoved_by)
	if charger.damage > 0.0 or bumped.damage > 0.0:
		failures.append("body contact dealt damage (%.1f and %.1f); only a head strike may" % [
			charger.damage, bumped.damage])
	if charger.deaths > 0 or bumped.deaths > 0:
		failures.append("body contact killed someone (%d and %d deaths)" % [
			charger.deaths, bumped.deaths])

	await _teardown(stage)
	return failures

## AC-9: enough accumulated damage eliminates. Elimination freezes and hides
## the player exactly where they were, still carrying the damage that
## eliminated them -- there is no mid-round respawn, and nothing resets that
## damage until `start_round()` brings them into the next round.
##
## Struck repeatedly with the hardest swing in the spread until the victim
## is eliminated. That it survives at least one of them is asserted too:
## damage that accumulates is the claim, and a one-shot kill would satisfy
## "it died" without it.
func _scenario_damage_kills() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var centre: Vector2 = DEEP_PARK_POSITION
	var attacker: RigidBody2D = _spawn_player(stage, centre)
	await physics_frame
	_brace(attacker)

	var half_angle: float = SWING_HALF_ANGLES[SWING_HALF_ANGLES.size() - 1]
	var aim: Dictionary = await _rehearse_swing(attacker, centre, half_angle)
	var victim: RigidBody2D = _spawn_player(stage, aim["point"])
	await physics_frame
	_brace(victim)

	var swings: int = 0
	var survived_a_strike: bool = false
	var hurt_before_death: float = 0.0
	while swings < MAX_KILL_SWINGS and victim.deaths == 0:
		var before: float = victim.damage
		await _swing_at(attacker, victim, centre, half_angle, aim["point"])
		swings += 1
		if victim.deaths == 0:
			if victim.damage > before:
				survived_a_strike = true
			hurt_before_death = victim.damage

	if victim.deaths != 1:
		failures.append("%d strikes left the victim on %.1f damage without eliminating them (%.1f kills)" % [
			swings, victim.damage, DEATH_DAMAGE])
	else:
		if not survived_a_strike:
			failures.append("the victim died on the first strike; damage is supposed to accumulate")
		if hurt_before_death >= DEATH_DAMAGE:
			failures.append("the victim was carrying %.1f damage and had not died yet (%.1f kills)" % [
				hurt_before_death, DEATH_DAMAGE])
		if victim.damage < DEATH_DAMAGE:
			failures.append("eliminated but only carrying %.1f damage; elimination should not reset it" % victim.damage)
		if victim.alive:
			failures.append("eliminated but still marked alive")

	await _teardown(stage)
	return failures

## AC-10: a ring-out eliminates a player who has taken no damage at all.
##
## Dropped off the end of the ground and past the kill zone with full health,
## which is the point: stage geometry is the sharpest threat and does not
## care how healthy anyone is. Elimination freezes the player in place --
## there is no respawn to land at -- carrying whatever damage they had,
## which here is none.
func _scenario_ringout_kills_at_full_health() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var player: RigidBody2D = _spawn_player(stage, RINGOUT_START)
	await physics_frame

	if player.damage > 0.0:
		failures.append("the player started on %.1f damage, so this is not a full-health ring-out" % player.damage)

	var fell: bool = false
	for _i in RINGOUT_TICKS:
		await physics_frame
		if player.deaths > 0:
			fell = true
			break

	if not fell:
		failures.append("fell for %d ticks to %s without dying" % [RINGOUT_TICKS, player.global_position])
	else:
		if player.deaths != 1:
			failures.append("one ring-out counted as %d deaths" % player.deaths)
		if player.damage > 0.0:
			failures.append("a ring-out at full health left %.1f damage behind" % player.damage)
		if player.alive:
			failures.append("eliminated but still marked alive")

	await _teardown(stage)
	return failures

## Issue #5: a player eliminated by ring-out is brought into the next round
## by `start_round()` and stays in it.
##
## In live play the respawned player died again the instant the next round
## began, every round. The cause was the spawn never reaching the physics
## server: the kill zone froze the body with its node transform freshly
## written by the physics sync, and assigning `global_position` over that
## does not queue the transform notification that pushes a body's position
## to the server. Unfrozen, the body was simulated where it died, dragged
## back there on the next sync, and eliminated again by the kill zone.
##
## That makes the watch below sensitive to reading the player's position:
## reading it between the ring-out and `start_round()` refreshes the node's
## transform and hides the bug, the same way nothing reads it in play. So
## nothing here touches the player's position until the respawn has been
## given its ticks.
##
## Each cycle also re-proves the ring-out itself -- the previously fixed
## "falling offscreen doesn't kill" case -- on a player who has already been
## through a respawn, which is where it has to keep working.
func _scenario_ringout_then_next_round_survives() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var player: RigidBody2D = _spawn_player(stage, RINGOUT_START)
	await physics_frame

	for cycle in NEXT_ROUND_CYCLES:
		if cycle > 0:
			# The round loop's own sequence: the survivor leaves the round
			# it won, and after the pause everyone re-enters through
			# start_round() -- here, straight into the next ring-out.
			player.leave_round()
			await _await_ticks(NEXT_ROUND_PAUSE_TICKS)
			player.start_round(RINGOUT_START)
		var fell: bool = false
		for _i in RINGOUT_TICKS:
			await physics_frame
			if player.deaths > cycle:
				fell = true
				break
		if not fell:
			failures.append("cycle %d: sent off the edge from %s and fell for %d ticks to %s without a ring-out" % [
				cycle, RINGOUT_START, RINGOUT_TICKS, player.global_position.round()])
			break
		if player.deaths != cycle + 1:
			failures.append("cycle %d: one ring-out counted as %d deaths" % [cycle, player.deaths - cycle])

		await _await_ticks(NEXT_ROUND_PAUSE_TICKS)
		player.start_round(NEXT_ROUND_SPAWN)
		var died_on_tick: int = -1
		for tick in NEXT_ROUND_WATCH_TICKS:
			await physics_frame
			if not player.alive or player.deaths != cycle + 1:
				died_on_tick = tick + 1
				break
		if died_on_tick >= 0:
			failures.append("cycle %d: eliminated again %d tick(s) into the next round, at %s (spawned at %s)" % [
				cycle, died_on_tick, player.global_position.round(), NEXT_ROUND_SPAWN])
			break
		var drift: float = player.global_position.distance_to(NEXT_ROUND_SPAWN)
		if drift > NEXT_ROUND_DRIFT:
			failures.append("cycle %d: brought back at %s but %d ticks later was at %s" % [
				cycle, NEXT_ROUND_SPAWN, NEXT_ROUND_WATCH_TICKS, player.global_position.round()])
			break

	await _teardown(stage)
	return failures

## AC-11: two heads meeting stop each other.
##
## Two ways of meeting, because they are not the same event.
##
## **Walked together.** The commanded reach is ramped, so the heads arrive at
## a rate an ordinary contact catches. They meet, they hold at the 16 px at
## which they touch with 0.3 px of solver give, they never cross, and they
## stay there for as long as both drives keep pushing. No jitter, no creep.
##
## **Sent at each other**, which is what a player's thumb actually does: both
## commanding full reach at once, which the extension drive delivers at
## 700 px/s each, closing the heads at about 23 px a tick against the 16 px
## at which they touch. This used to be described here and not asserted --
## the pair resolved both ways from identical code depending only on where in
## the step the heads landed, blocking at 10.5 px one run and stepping clean
## through to the far side the next, and a coin flip is not something a suite
## can assert. `WeaponHead`'s pair correction is what made it deterministic:
## the encounter is now resolved once, by one of the two heads, on the step
## the pair crosses. So it is asserted here, on the same terms as the walked
## case.
##
## And in neither case does anybody get hurt. Two heads meeting is a block,
## not a strike -- CONTEXT.md's Clash -- so the one thing a clash must never
## produce is damage, whichever path stopped the heads.
func _scenario_heads_do_not_interpenetrate() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var centre: Vector2 = DEEP_PARK_POSITION
	var half: Vector2 = Vector2.RIGHT * CLASH_SEPARATION * 0.5
	var left: RigidBody2D = _spawn_player(stage, centre - half)
	var right: RigidBody2D = _spawn_player(stage, centre + half)
	await physics_frame
	# Braced, or there is nothing to watch: each weapon's push comes back
	# through its own body, so two free players shove themselves apart before
	# their heads settle against each other.
	_brace(left)
	_brace(right)

	var contact: float = 2.0 * HEAD_RADIUS
	var walked: Dictionary = await _close_heads(left, right, CLASH_APPROACH_TICKS)
	var held: Dictionary = await _watch_heads(left, right, CLASH_TICKS)
	print("      walked together at up to %.1f px a tick: met at %.1f px, still %.1f px apart under full push" % [
		walked["speed"], walked["closest"], held["closest"]])
	if walked["closest"] > contact + CLASH_CONTACT_SLACK:
		failures.append("walked together, the heads never met: closest %.1f px, touching is %.1f px" % [
			walked["closest"], contact])
	if held["closest"] < contact - HEAD_OVERLAP_ALLOWANCE:
		failures.append("the heads came to rest %.1f px inside each other" % (contact - held["closest"]))
	if walked["crossings"] + held["crossings"] > 0:
		failures.append("walked together, the left head still got to the right of the right head")
	if walked["tunnels"] + held["tunnels"] > 0:
		failures.append("walked together, a step still jumped the heads through each other")
	# Both drives are commanded 60 px past where they can get to, so this is
	# two weapons at full push, not two weapons that happen to be resting
	# against each other.
	if held["closest"] > contact + CLASH_CONTACT_SLACK:
		failures.append("the heads did not stay together: %.1f px apart while both are still pushing" % held["closest"])

	# Now the same block, sent rather than walked. Both weapons are eased all
	# the way back to rest first, so the send starts from a real distance and
	# reaches full closing speed before the heads meet.
	left.set_input_vector(Vector2.ZERO)
	right.set_input_vector(Vector2.ZERO)
	await _await_ticks(RELEASE_TICKS)
	var sent: Dictionary = await _send_heads(left, right, SEND_TICKS)
	print("      sent at each other at up to %.1f px a tick: met at %.1f px, still %.1f px apart at the end" % [
		sent["speed"], sent["closest"], (right.weapon_head_position() - left.weapon_head_position()).length()])
	if sent["closest"] > contact + CLASH_CONTACT_SLACK:
		failures.append("sent at each other, the heads never met: closest %.1f px, touching is %.1f px" % [
			sent["closest"], contact])
	if sent["closest"] < contact - HEAD_OVERLAP_ALLOWANCE:
		failures.append("sent at each other, the heads got %.1f px inside each other" % (contact - sent["closest"]))
	if sent["crossings"] > 0:
		failures.append("sent at each other, the left head got to the right of the right head on %d ticks" % sent["crossings"])
	if sent["tunnels"] > 0:
		failures.append("sent at each other, %d steps jumped the heads through each other" % sent["tunnels"])

	# A clash is a block. Neither of these two ever swung at a body -- each
	# one's head is 80 px short of the other's body at full reach -- so any
	# damage at all here would mean a head meeting a head was scored as a
	# strike.
	if left.damage > 0.0 or right.damage > 0.0:
		failures.append("a clash hurt somebody: left took %.1f, right took %.1f -- two heads meeting is a block, not a strike" % [
			left.damage, right.damage])

	await _teardown(stage)
	return failures

## AC-12: in a clash the head with the higher max drive force wins ground.
##
## Measured as where the two heads meet relative to the line midway between
## the two bodies. With identical weapons that meeting point has to sit on the
## midline -- the situation is symmetric, so anywhere else would be a bias in
## the rig rather than a property of the weapons. The right-hand player is
## then handed a weapon identical in every way but its force ceiling, and the
## meeting point has to move onto the weaker player's side. Nothing here
## reaches for the clamp itself; ADR-0006 says the outcome should fall out of
## it, and this is the observation that says whether it does.
func _scenario_clash_higher_drive_force_wins() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var centre: Vector2 = DEEP_PARK_POSITION
	var half: Vector2 = Vector2.RIGHT * CLASH_SEPARATION * 0.5
	var left: RigidBody2D = _spawn_player(stage, centre - half)
	var right: RigidBody2D = _spawn_player(stage, centre + half)
	await physics_frame
	# Braced, or there is no contest to measure: each weapon's push comes
	# back through its own body, so two free players shove themselves apart
	# and their heads never stay in contact. Bracing is a player planted
	# against the ground, which is the situation a clash actually happens in.
	_brace(left)
	_brace(right)

	var even: Dictionary = await _clash(left, right, centre)
	print("      equal weapons: meeting point %.1f px off the midline, heads %.1f px apart" % [
		even["offset"], even["gap"]])
	if even["gap"] > 2.0 * HEAD_RADIUS + CLASH_CONTACT_SLACK:
		failures.append("the heads never met with equal weapons: %.1f px apart" % even["gap"])
	if absf(even["offset"]) > SYMMETRIC_CLASH_TOLERANCE:
		failures.append("two identical weapons met %.1f px off the midline between them" % even["offset"])

	var strong := WeaponStatsType.new()
	strong.max_drive_force = strong.max_drive_force * STRONG_FORCE_MULTIPLIER
	right.set_weapon_stats(strong)
	await _await_ticks(SETTLE_TICKS)

	var uneven: Dictionary = await _clash(left, right, centre)
	print("      stronger right: meeting point %.1f px off the midline, heads %.1f px apart" % [
		uneven["offset"], uneven["gap"]])
	if uneven["gap"] > 2.0 * HEAD_RADIUS + CLASH_CONTACT_SLACK:
		failures.append("the heads never met with unequal weapons: %.1f px apart" % uneven["gap"])
	var ground_won: float = even["offset"] - uneven["offset"]
	if ground_won < MIN_GROUND_WON:
		failures.append("a %.0fx stronger weapon drove the clash only %.1f px onto the weaker player's side (wanted %.1f px)" % [
			STRONG_FORCE_MULTIPLIER, ground_won, MIN_GROUND_WON])
	if uneven["offset"] > -MIN_GROUND_WON:
		failures.append("the clash settled %.1f px off the midline; the stronger weapon should hold the middle and then some" % uneven["offset"])

	await _teardown(stage)
	return failures

## AC-11 at the speed a fight actually reaches: a head must not tunnel
## through another head.
##
## Blocking is one of the three jobs the weapon exists for (CONTEXT.md), and
## this used to breach: three of these twelve charges put a head clean through
## another head, both ends of the step outside the 16 px at which they touch
## and no contact ever generated. The head's world sweep cannot be pointed at
## it -- two heads each snapping the other out of a contact would fight rather
## than resolve, which is why `WeaponHead.sweep_mask` leaves the head layer
## out -- so `WeaponHead` corrects the pair instead, once, from the far side
## of the step.
##
## Both players hold their heads out at each other from a distance neither can
## reach across, and are then thrown at each other: closing speed is twice the
## charge speed, up to 3600 px/s, or 60 px in a tick against a 16 px head.
## Swept over four approach directions so that gravity, which helps a vertical
## charge and not a horizontal one, cannot hide it.
func _scenario_heads_do_not_tunnel_head() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var centre: Vector2 = DEEP_PARK_POSITION
	var attacker: RigidBody2D = _spawn_player(stage, centre)
	var blocker: RigidBody2D = _spawn_player(stage, centre)
	await physics_frame

	var contact: float = 2.0 * HEAD_RADIUS
	var trials: int = 0
	var met: int = 0
	var breaches: int = 0

	for degrees: float in CHARGE_ANGLES:
		for speed: float in CHARGE_SPEEDS:
			trials += 1
			var axis: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(degrees))
			var half: Vector2 = axis * CHARGE_SEPARATION * 0.5
			attacker.teleport_to(centre - half)
			blocker.teleport_to(centre + half)
			attacker.set_input_vector(axis)
			blocker.set_input_vector(-axis)
			await _await_ticks(SETTLE_TICKS)

			var deaths: int = attacker.deaths + blocker.deaths
			var previous: Vector2 = blocker.weapon_head_position() - attacker.weapon_head_position()
			var closest: float = previous.length()
			var went_through: bool = false
			var crossed_from: Vector2 = Vector2.ZERO
			var crossed_to: Vector2 = Vector2.ZERO
			for _t in CHARGE_TICKS:
				attacker.linear_velocity = axis * speed
				blocker.linear_velocity = -axis * speed
				await physics_frame
				var relative: Vector2 = blocker.weapon_head_position() - attacker.weapon_head_position()
				var still_alive: bool = attacker.deaths + blocker.deaths == deaths
				# An elimination freezes a player and its weapon in place rather
				# than moving them, but it also drops the head's collision layer,
				# so the relative position stops meaning "two heads closing" the
				# instant one side is eliminated; the trial stops being
				# meaningful there.
				if not still_alive:
					break
				closest = minf(closest, relative.length())
				if not went_through and _stepped_through(previous, relative):
					went_through = true
					crossed_from = previous
					crossed_to = relative
				previous = relative

			if closest <= contact + CLASH_CONTACT_SLACK:
				met += 1
			print("      %3.0f deg at %.0f px/s each: closest %6.1f px%s" % [
				degrees, speed, closest, "  THROUGH" if went_through else ""])
			if went_through:
				breaches += 1
				if failures.size() < MAX_FAILURES_PER_SCENARIO:
					failures.append(
						"%.0f deg approach at %.0f px/s each: one step took the heads from %s apart to %s apart, straight through the %.0f px at which they touch" % [
							degrees, speed, crossed_from, crossed_to, contact])

	if met < trials / 2:
		failures.append("only %d of %d charges brought the heads together at all" % [met, trials])
	if breaches > 0:
		failures.append("%d of %d charges put a head through another head" % [breaches, trials])

	await _teardown(stage)
	return failures

# --- Damage, death and clash helpers ----------------------------------------

## The same swing with nobody in the way, to find out where the head goes and
## how fast it is going when it gets there.
##
## Aiming a swing needs this. Where the head passes is not the circle the
## commanded reach describes: a hard sweep drags the head in along its own
## haft, so the faster the swing the tighter the arc, and a victim planted at
## nominal full reach is missed by a wider margin the harder the swing is --
## which would turn the whole spread upside down. Rehearsing puts the victim
## on the path the head actually takes, at the fastest point of it.
##
## Physics here is deterministic and the attacker is braced, so the swing
## measured is the swing that gets repeated: same start pose, same command,
## same arc, and the victim is not touching anything until the head arrives.
func _rehearse_swing(attacker: RigidBody2D, centre: Vector2, half_angle: float) -> Dictionary:
	await _wind_up(attacker, centre, -half_angle)

	var previous: Vector2 = attacker.weapon_head_position()
	var fastest: float = 0.0
	var point: Vector2 = previous
	attacker.set_input_vector(Vector2.RIGHT.rotated(half_angle))
	for _t in SWING_TICKS:
		await physics_frame
		var head: Vector2 = attacker.weapon_head_position()
		var speed: float = (head - previous).length() / _tick_seconds()
		if speed > fastest:
			fastest = speed
			point = head
		previous = head
	# Pulled a little inside the arc: see ARC_INSET. The attacker is braced,
	# so `centre` is exactly where it still is and the radius is honest.
	var arm: Vector2 = point - centre
	return {"point": centre + arm.normalized() * maxf(0.0, arm.length() - ARC_INSET), "speed": fastest}

## One swing at a victim standing on the head's path, and what it did.
##
## The attacker winds the weapon up `half_angle` short of the victim at full
## reach and is then told to finish `half_angle` past them, so the head
## crosses the victim in the middle of its sweep, moving, rather than
## arriving decelerating onto the angle it was pointed at. A longer
## half-sweep is a faster head at the moment of contact, which is how these
## trials turn speed without ever telling the weapon what speed to have.
##
## Both bodies are braced (`_brace`) for the duration. Unbraced, a full-reach
## sweep flings its own player -- that is the moveset working -- and the arc
## walks off the victim by up to 200 px, so the trials would measure whether
## the head arrived rather than what it did on arrival. Bracing is a fixture,
## not a claim: it is the engine's own `freeze`, it touches nothing in the
## rig, and what it produces is a player swinging from a firm stance.
##
## Speed is reported from the tick before the hit registered -- the last step
## the head took before anything stopped it -- and damage from the victim's
## own total, both of them things a player can watch happen.
func _swing_at(attacker: RigidBody2D, victim: RigidBody2D, centre: Vector2, half_angle: float, target: Vector2) -> Dictionary:
	victim.teleport_to(target)
	victim.set_input_vector(Vector2.ZERO)
	await _wind_up(attacker, centre, -half_angle)

	var before_damage: float = victim.damage
	var before_deaths: int = victim.deaths
	var previous_head: Vector2 = attacker.weapon_head_position()
	# The fastest the head was seen moving on its way in. The swing
	# accelerates into the target and is stopped dead by it, so the fastest
	# step before the hit is the speed it arrived with -- and the damage
	# lands a tick after the head has already been stopped, so the step it
	# lands on is no use for reading a speed off.
	var approach_speed: float = 0.0
	var dealt: float = 0.0
	var registered: bool = false
	var closest: float = INF
	var after_hit: int = 0

	attacker.set_input_vector(Vector2.RIGHT.rotated(half_angle))
	for _t in SWING_TICKS:
		await physics_frame
		var head: Vector2 = attacker.weapon_head_position()
		var speed: float = (head - previous_head).length() / _tick_seconds()
		previous_head = head
		closest = minf(closest, (head - victim.global_position).length())
		if not registered:
			approach_speed = maxf(approach_speed, speed)
			if victim.damage != before_damage or victim.deaths != before_deaths:
				registered = true
				dealt = victim.damage - before_damage if victim.deaths == before_deaths \
					else DEATH_DAMAGE - before_damage
		else:
			after_hit += 1
			if after_hit >= POST_HIT_TICKS:
				break

	# The head may have arrived and done nothing, which is a different
	# failure from never arriving -- so whether it got there is geometry,
	# measured at its closest approach, not whether damage appeared.
	return {
		"damage": dealt,
		"speed": approach_speed,
		"landed": closest <= PLAYER_RADIUS + HEAD_RADIUS + PLANT_CLEARANCE,
		"closest": closest,
	}

## The slow-contact anchor: the head held fully out while the body walks it
## into someone. Same measurements as `_swing_at`, so the two are comparable.
func _creep_into(attacker: RigidBody2D, victim: RigidBody2D, centre: Vector2) -> Dictionary:
	victim.teleport_to(centre + Vector2.RIGHT * CREEP_DISTANCE)
	victim.set_input_vector(Vector2.ZERO)
	await _wind_up(attacker, centre, 0.0)

	var before_damage: float = victim.damage
	var previous_head: Vector2 = attacker.weapon_head_position()
	var approach_speed: float = 0.0
	var speed_at_hit: float = 0.0
	var landed: bool = false
	var closest: float = INF

	for _t in CREEP_TICKS:
		attacker.linear_velocity = Vector2(CREEP_SPEED, attacker.linear_velocity.y)
		await physics_frame
		var head: Vector2 = attacker.weapon_head_position()
		var speed: float = (head - previous_head).length() / _tick_seconds()
		previous_head = head
		var reach: float = (head - victim.global_position).length()
		closest = minf(closest, reach)
		if not landed and reach <= PLAYER_RADIUS + HEAD_RADIUS + PLANT_CLEARANCE:
			landed = true
			speed_at_hit = approach_speed
		approach_speed = speed

	if not landed:
		speed_at_hit = approach_speed
	return {
		"damage": victim.damage - before_damage,
		"speed": speed_at_hit,
		"landed": landed,
		"closest": closest,
	}

## Drives two players' heads into each other and reports where they met: how
## far the midpoint between the two heads sits from the midpoint between the
## two bodies, positive being to the right. Both bodies are taken live,
## because the drive shoves them apart as it pushes -- the midline is not
## where they started.
func _clash(left: RigidBody2D, right: RigidBody2D, centre: Vector2) -> Dictionary:
	var half: Vector2 = Vector2.RIGHT * CLASH_SEPARATION * 0.5
	left.teleport_to(centre - half)
	right.teleport_to(centre + half)
	# Walked together rather than sent: a contest can only be measured once
	# there is a contact, and sent at each other these two arrive faster than
	# the contact catches and are seated by `WeaponHead`'s pair correction
	# instead (`heads_do_not_interpenetrate`), which is a correction settling
	# and not the two drives contesting. Once they are touching, the
	# drives are pushing at everything they have -- both are commanded 60 px
	# past where they can get to -- so what is measured afterwards is the
	# contest at full force and not a gentler version of it.
	await _close_heads(left, right, CLASH_APPROACH_TICKS)
	await _await_ticks(SETTLE_TICKS)

	var left_head: Vector2 = left.weapon_head_position()
	var right_head: Vector2 = right.weapon_head_position()
	var meeting: float = (left_head.x + right_head.x) * 0.5
	var midline: float = (left.global_position.x + right.global_position.x) * 0.5
	return {"offset": meeting - midline, "gap": (right_head - left_head).length()}

## Walk two braced players' heads into each other, by ramping the reach they
## are asked for instead of asking for all of it at once. See
## CLASH_APPROACH_TICKS. Ends with both commanded to full reach, so whatever
## follows is watching two drives at full push.
func _close_heads(left: RigidBody2D, right: RigidBody2D, ticks: int) -> Dictionary:
	var watch: Dictionary = _new_head_watch(left, right)
	for i in ticks:
		var reach: float = float(i + 1) / float(ticks)
		left.set_input_vector(Vector2.RIGHT * reach)
		right.set_input_vector(Vector2.LEFT * reach)
		await physics_frame
		_watch_heads_tick(left, right, watch)
	return watch

## Send two braced players' heads at each other the way a player does it:
## full reach commanded outright, both at once, and then left alone. The
## drive delivers that at `WeaponStats.extend_speed` a side, which is what
## makes this the fast arrival the walked approach deliberately is not.
func _send_heads(left: RigidBody2D, right: RigidBody2D, ticks: int) -> Dictionary:
	var watch: Dictionary = _new_head_watch(left, right)
	left.set_input_vector(Vector2.RIGHT)
	right.set_input_vector(Vector2.LEFT)
	for _i in ticks:
		await physics_frame
		_watch_heads_tick(left, right, watch)
	return watch

## Watch two heads for a while without touching what either player is doing.
func _watch_heads(left: RigidBody2D, right: RigidBody2D, ticks: int) -> Dictionary:
	var watch: Dictionary = _new_head_watch(left, right)
	for _i in ticks:
		await physics_frame
		_watch_heads_tick(left, right, watch)
	return watch

## What a watch collects: how close the two heads got, how fast they were
## closing at the quickest (in pixels per tick, which is the unit that
## matters against a 16 px contact), how many ticks the left head spent on
## the wrong side of the right one, and how many single steps took them
## through each other without ever touching.
func _new_head_watch(left: RigidBody2D, right: RigidBody2D) -> Dictionary:
	var relative: Vector2 = right.weapon_head_position() - left.weapon_head_position()
	return {
		"closest": relative.length(),
		"crossings": 0,
		"tunnels": 0,
		"speed": 0.0,
		"previous": relative,
	}

func _watch_heads_tick(left: RigidBody2D, right: RigidBody2D, watch: Dictionary) -> void:
	var relative: Vector2 = right.weapon_head_position() - left.weapon_head_position()
	var previous: Vector2 = watch["previous"]
	watch["closest"] = minf(watch["closest"], relative.length())
	watch["speed"] = maxf(watch["speed"], previous.length() - relative.length())
	if relative.x <= 0.0:
		watch["crossings"] += 1
	if _stepped_through(previous, relative):
		watch["tunnels"] += 1
	watch["previous"] = relative

## Did these two heads swap places without ever being close enough to touch?
##
## Both arguments are the second head's position relative to the first, a tick
## apart. If the straight line between them passes inside the distance at
## which the two heads are touching, while both ends of it are outside that
## distance, then the pair went through each other between one tick and the
## next: there is no tick at which they were in contact, and yet they came out
## the other side. Ordinary contact does not look like this -- it leaves an
## endpoint inside -- and neither does a miss.
func _stepped_through(previous_relative: Vector2, current_relative: Vector2) -> bool:
	var contact: float = 2.0 * HEAD_RADIUS
	if previous_relative.length() <= contact or current_relative.length() <= contact:
		return false
	var step: Vector2 = current_relative - previous_relative
	var step_length_squared: float = step.length_squared()
	if step_length_squared == 0.0:
		return false
	var along: float = clampf(-previous_relative.dot(step) / step_length_squared, 0.0, 1.0)
	return (previous_relative + step * along).length() < contact

func _tick_seconds() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)

## Put an attacker at `centre` with its weapon wound up at `angle`: turned
## first while wound in, where the head can reach nobody, then pushed out to
## full reach. See RETRACT_TICKS.
func _wind_up(attacker: RigidBody2D, centre: Vector2, angle: float) -> void:
	attacker.teleport_to(centre)
	attacker.set_input_vector(Vector2.RIGHT.rotated(angle) * 0.05)
	await _await_ticks(RETRACT_TICKS)
	attacker.set_input_vector(Vector2.RIGHT.rotated(angle))
	await _await_ticks(EXTEND_TICKS)

## Hold a player still without touching its weapon: the engine's own freeze,
## which pins the body and leaves the rig hanging off it free to be driven.
## A strike trial needs the arc to arrive where it was aimed, and an unbraced
## swing throws its own player across the screen.
func _brace(player: RigidBody2D) -> void:
	player.linear_velocity = Vector2.ZERO
	player.freeze = true

# --- Damage display and identity (AC-16, AC-17, D4 scope change) -----------

func _color_distance(a: Color, b: Color) -> float:
	var dr: float = a.r - b.r
	var dg: float = a.g - b.g
	var db: float = a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)

func _color_close(a: Color, b: Color, tolerance: float) -> bool:
	return _color_distance(a, b) <= tolerance

## AC-16: the body fill reddens as `damage` climbs (0%, 50%, 95% of
## DEATH_DAMAGE), while the persistent identity outline and the weapon head's
## colour -- where ADR-0005 moves identity once the fill can no longer carry
## it -- stay exactly where they started, and stay distinguishable between
## two players throughout.
func _scenario_damage_reddens_fill_identity_persists() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()

	var a: RigidBody2D = PlayerScene.instantiate() as RigidBody2D
	a.identity_color = IDENTITY_A_COLOR
	stage.add_child(a)
	a.global_position = DEEP_PARK_POSITION
	a.bind_controller()

	var b: RigidBody2D = PlayerScene.instantiate() as RigidBody2D
	b.identity_color = IDENTITY_B_COLOR
	stage.add_child(b)
	b.global_position = DEEP_PARK_POSITION + Vector2(200.0, 0.0)
	b.bind_controller()

	await physics_frame
	_brace(a)
	_brace(b)

	var outline_a0: Color = a.identity_outline_color()
	var weapon_a0: Color = a.weapon_head_color()
	var outline_b0: Color = b.identity_outline_color()
	var weapon_b0: Color = b.weapon_head_color()

	if _color_distance(outline_a0, outline_b0) < DISTINCT_COLOR_MIN_DISTANCE:
		failures.append("player identity outlines are not distinguishable: %s vs %s" % [outline_a0, outline_b0])
	if _color_distance(weapon_a0, weapon_b0) < DISTINCT_COLOR_MIN_DISTANCE:
		failures.append("player weapon colours are not distinguishable: %s vs %s" % [weapon_a0, weapon_b0])

	var pure_red := Color(1.0, 0.0, 0.0, 1.0)
	var previous_fill_distance: float = _color_distance(a.body_fill_color(), pure_red)
	for sample: float in DAMAGE_SAMPLES:
		if sample > 0.0:
			a.take_damage(sample - a.damage)
			await physics_frame

		if absf(a.damage - sample) > 0.01:
			failures.append("could not drive damage to %.1f (sat at %.1f)" % [sample, a.damage])

		var fill: Color = a.body_fill_color()
		var fill_distance: float = _color_distance(fill, pure_red)
		if sample > 0.0 and fill_distance >= previous_fill_distance:
			failures.append("at %.0f%% of DEATH_DAMAGE the fill did not redden further (distance to red %.3f, was %.3f)" % [
				sample, fill_distance, previous_fill_distance])
		previous_fill_distance = fill_distance

		if not _color_close(a.identity_outline_color(), outline_a0, COLOR_MATCH_TOLERANCE):
			failures.append("at %.0f%% of DEATH_DAMAGE the identity outline changed: %s, expected %s" % [
				sample, a.identity_outline_color(), outline_a0])
		if not _color_close(a.weapon_head_color(), weapon_a0, COLOR_MATCH_TOLERANCE):
			failures.append("at %.0f%% of DEATH_DAMAGE the weapon colour changed: %s, expected %s" % [
				sample, a.weapon_head_color(), weapon_a0])

	if _color_close(a.body_fill_color(), outline_a0, COLOR_MATCH_TOLERANCE):
		failures.append("at 95%% of DEATH_DAMAGE the body fill still matches the identity colour; it should have reddened well past it")

	await _teardown(stage)
	return failures

## AC-17: the controller page's SLOT_COLORS and the host's per-player
## identity_color values agree, slot for slot. Parses both source files
## rather than keeping a third copy of either list here -- a hardcoded copy
## would pass even if the two drifted apart, which is exactly the failure
## this scenario exists to catch.
func _scenario_identity_colours_match_controller_page() -> Array[String]:
	var failures: Array[String] = []
	var slot_colors: Array[Color] = _parse_slot_colors()
	var main_colors: Array[Color] = _parse_main_identity_colors()

	if slot_colors.size() < 2:
		failures.append("could not parse SLOT_COLORS from %s (found %d entries)" % [CONTROLLER_PAGE_PATH, slot_colors.size()])
	if main_colors.size() < 2:
		failures.append("could not parse identity_color for Player1/Player2 from %s (found %d entries)" % [MAIN_SCENE_PATH, main_colors.size()])

	if failures.is_empty():
		for i in 2:
			if not _color_close(slot_colors[i], main_colors[i], SLOT_COLOR_TOLERANCE):
				failures.append("slot %d: controller SLOT_COLORS has %s, Main.tscn identity_color has %s" % [
					i, slot_colors[i], main_colors[i]])

	# Nothing here builds a scene tree -- both sides of the check are files on
	# disk -- so there is no stage for `_teardown()` to free.
	_scenario_completed = true
	return failures

func _parse_slot_colors() -> Array[Color]:
	var colors: Array[Color] = []
	var text: String = FileAccess.get_file_as_string(CONTROLLER_PAGE_PATH)
	var list_re := RegEx.new()
	list_re.compile("SLOT_COLORS\\s*=\\s*\\[([^\\]]*)\\]")
	var list_match: RegExMatch = list_re.search(text)
	if list_match == null:
		return colors
	var hex_re := RegEx.new()
	hex_re.compile("#[0-9a-fA-F]{6}")
	for m: RegExMatch in hex_re.search_all(list_match.get_string(1)):
		colors.append(Color(m.get_string(0)))
	return colors

func _parse_main_identity_colors() -> Array[Color]:
	var colors: Array[Color] = []
	var text: String = FileAccess.get_file_as_string(MAIN_SCENE_PATH)
	for slot_name: String in ["Player1", "Player2"]:
		var node_re := RegEx.new()
		node_re.compile("\\[node name=\"%s\"[\\s\\S]*?(?=\\n\\[node|\\z)" % slot_name)
		var node_match: RegExMatch = node_re.search(text)
		if node_match == null:
			continue
		var color_re := RegEx.new()
		color_re.compile("identity_color\\s*=\\s*Color\\(([^)]*)\\)")
		var color_match: RegExMatch = color_re.search(node_match.get_string(0))
		if color_match == null:
			continue
		var comps: PackedStringArray = color_match.get_string(1).split(",")
		if comps.size() < 3:
			continue
		colors.append(Color(
			float(comps[0].strip_edges()),
			float(comps[1].strip_edges()),
			float(comps[2].strip_edges()),
			float(comps[3].strip_edges()) if comps.size() > 3 else 1.0))
	return colors

## D4 scope change: the drawn head derives from `WeaponStats.head_shape`
## rather than a parallel "draw radius" number, for every shape the roster
## understands (circle, rectangle, and the pickaxe's own convex-polygon
## spike), and visibly refuses to guess for a shape it does not.
func _scenario_weapon_silhouette_matches_head_shape() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var player: RigidBody2D = _spawn_player(stage, PARK_POSITION)
	await _await_ticks(2)

	# A synthetic circle stats object, not the default weapon stats: the
	# pickaxe's own head is a ConvexPolygonShape2D now (below), so the circle
	# case has to build its own the way the rectangle and capsule cases
	# already do.
	var circle_stats := WeaponStatsType.new()
	var circle_shape := CircleShape2D.new()
	circle_shape.radius = 8.0
	circle_stats.head_shape = circle_shape
	player.set_weapon_stats(circle_stats)
	await _await_ticks(2)

	var polygon: PackedVector2Array = player.weapon_head_visual_polygon()
	var max_reach_from_centre: float = 0.0
	for p: Vector2 in polygon:
		max_reach_from_centre = maxf(max_reach_from_centre, p.length())
	# The pre-fix drawing was a square of half-width equal to the
	# radius, whose corners reach radius * sqrt(2) from centre -- this
	# check fails against that shape and only that shape passes here.
	if absf(max_reach_from_centre - circle_shape.radius) > HEAD_SHAPE_TOLERANCE:
		failures.append("circle head: drawn silhouette reaches %.2f px from centre, collision shape radius is %.2f px" % [
			max_reach_from_centre, circle_shape.radius])
	if player.weapon_head_visual_is_fallback():
		failures.append("circle head: fell back, but CircleShape2D is understood directly")

	var rect_stats := WeaponStatsType.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = RECT_HEAD_SIZE
	rect_stats.head_shape = rect_shape
	player.set_weapon_stats(rect_stats)
	await _await_ticks(2)

	var rect_polygon: PackedVector2Array = player.weapon_head_visual_polygon()
	if rect_polygon.is_empty():
		failures.append("rectangle head: no silhouette was drawn")
	else:
		var min_pt: Vector2 = rect_polygon[0]
		var max_pt: Vector2 = rect_polygon[0]
		for p: Vector2 in rect_polygon:
			min_pt.x = minf(min_pt.x, p.x)
			min_pt.y = minf(min_pt.y, p.y)
			max_pt.x = maxf(max_pt.x, p.x)
			max_pt.y = maxf(max_pt.y, p.y)
		var drawn_size: Vector2 = max_pt - min_pt
		if (drawn_size - RECT_HEAD_SIZE).length() > HEAD_SHAPE_TOLERANCE:
			failures.append("rectangle head: drawn silhouette is %s, collision shape size is %s" % [
				drawn_size, RECT_HEAD_SIZE])
	if player.weapon_head_visual_is_fallback():
		failures.append("rectangle head: fell back, but RectangleShape2D is understood directly")

	var capsule_stats := WeaponStatsType.new()
	var capsule_shape := CapsuleShape2D.new()
	capsule_shape.radius = 6.0
	capsule_shape.height = 24.0
	capsule_stats.head_shape = capsule_shape
	player.set_weapon_stats(capsule_stats)
	await _await_ticks(2)

	if not player.weapon_head_visual_is_fallback():
		failures.append("capsule head: expected the bounding-box fallback, got a shape-specific silhouette")
	if _color_close(player.weapon_head_color(), player.identity_outline_color(), COLOR_MATCH_TOLERANCE):
		failures.append("capsule head: fallback silhouette is drawn in the identity colour, so it does not read as a fallback")

	# Not the shipped pickaxe (which still uses a CircleShape2D -- see the
	# comment in resources/pickaxe.tres for why a polygon head was tried and
	# reverted there): a synthetic shape, exactly like the rectangle and
	# capsule cases, to check the drawing path on its own.
	var polygon_stats := WeaponStatsType.new()
	var polygon_shape := ConvexPolygonShape2D.new()
	polygon_shape.points = PackedVector2Array([Vector2(8, 0), Vector2(0, -8), Vector2(-8, 0), Vector2(0, 8)])
	polygon_stats.head_shape = polygon_shape
	player.set_weapon_stats(polygon_stats)
	await _await_ticks(2)

	var drawn_polygon: PackedVector2Array = player.weapon_head_visual_polygon()
	if drawn_polygon != polygon_shape.points:
		failures.append("polygon head: drawn silhouette %s does not match collision shape points %s" % [
			drawn_polygon, polygon_shape.points])
	if player.weapon_head_visual_is_fallback():
		failures.append("polygon head: fell back, but ConvexPolygonShape2D is understood directly")

	await _teardown(stage)
	return failures
