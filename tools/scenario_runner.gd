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
const StageType := preload("res://scripts/Stage.gd")
const RoundManagerType := preload("res://scripts/RoundManager.gd")

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
	"weapon_head_circles_within_art",
	"stage_rotates_each_round",
	"stage_spawns_are_safe",
	"waiting_expires_disconnected_claims",
	"abandoned_round_ends_without_winner",
	"round_winner_keeps_weapon",
	"weapon_reach_matches_roster",
	"weapon_damage_matches_roster",
	"weapon_responsiveness_matches_roster",
	"heavy_weapon_wins_clash",
	"roster_heads_do_not_tunnel_head",
	"roster_hafts_are_non_colliding",
	"every_stage_can_ring_out",
	"hazard_zone_kills_at_full_health",
	"moving_platform_carries_player",
	"head_plants_moving_platform",
	"crumbling_ledge_three_phases",
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
## How far a head reaches past its anchor, which is what the plant and clash
## checks below are measured against. A head is a cluster of circles fitted to
## drawn art now (ADR-0010) rather than one round nub, so this is no longer
## literally a radius: the pickaxe's crescent reaches 9 px along the haft and
## further across it. It stays written down as the nub's 8 px because that is
## the distance those checks were tuned at, and PLANT_CLEARANCE is the slack
## they allow -- a weapon whose head reached far enough past this to matter
## would be a different weapon, not the same one redrawn.
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
## Every weapon resource the game ships. All five of the roster are here now.
## Read by the art-containment check and by every roster scenario that has to
## be true of the whole roster rather than of whichever weapon `Player.tscn`
## happens to ship with, so a sixth weapon is covered by adding it here.
const WEAPON_RESOURCE_PATHS: PackedStringArray = [
	"res://resources/pickaxe.tres",
	"res://resources/staff.tres",
	"res://resources/sword.tres",
	"res://resources/axe.tres",
	"res://resources/dagger.tres",
]
## How far a head circle may stick out of its weapon's drawn art and still
## count as inside it: half a pixel.
##
## It is there for the two ways a hand-fitted head misses by less than anyone
## can see -- the flat sides of a polygon cutting the corner of a curve it
## traces, and coordinates written down to two decimals -- and it is far
## under the smallest gap that reads as art and hitbox disagreeing.
##
## **Three of the six heads this suite checks pass on the tolerance and not on
## their geometry.** Worst circle against its own outline, negative meaning
## inside: pickaxe -0.043, sword -0.043, dagger -0.046, staff **+0.003**, axe
## **+0.011**, and the default round head exactly **+0.000** -- tangent, by
## construction (`WeaponStats._circle_outline` draws a polygon that contains
## the circle, so the flats land on the radius). The staff and the axe are
## outside their art, by a hundredth of a pixel.
##
## So the margin this constant is really carrying is about **0.05 px, not
## 0.86**: hardening it toward zero -- or even to 0.01 -- turns the staff, the
## axe and every stub built on the default head red without a single head
## having changed. An earlier version of this comment claimed the pickaxe
## cleared its outline by 0.86 px and concluded the shipped weapons passed on
## geometry; that was true of the five-circle pickaxe and has not been true
## since it was refitted to seven. Tighten this only against a recomputed set
## of all six numbers.
const ART_CONTAINMENT_TOLERANCE: float = 0.5
## How far a head circle is shoved out of its art to check that the
## containment check can actually fail. Well clear of the default head, so
## the only way this passes is by the check not looking.
const MISFIT_CIRCLE_OFFSET: float = 24.0

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
		"weapon_head_circles_within_art":
			return await _scenario_weapon_head_circles_within_art()
		"stage_rotates_each_round":
			return await _scenario_stage_rotates_each_round()
		"stage_spawns_are_safe":
			return await _scenario_stage_spawns_are_safe()
		"waiting_expires_disconnected_claims":
			return await _scenario_waiting_expires_disconnected_claims()
		"abandoned_round_ends_without_winner":
			return await _scenario_abandoned_round_ends_without_winner()
		"round_winner_keeps_weapon":
			return await _scenario_round_winner_keeps_weapon()
		"weapon_reach_matches_roster":
			return await _scenario_weapon_reach_matches_roster()
		"weapon_damage_matches_roster":
			return await _scenario_weapon_damage_matches_roster()
		"weapon_responsiveness_matches_roster":
			return await _scenario_weapon_responsiveness_matches_roster()
		"heavy_weapon_wins_clash":
			return await _scenario_heavy_weapon_wins_clash()
		"roster_heads_do_not_tunnel_head":
			return await _scenario_roster_heads_do_not_tunnel_head()
		"roster_hafts_are_non_colliding":
			return await _scenario_roster_hafts_are_non_colliding()
		"every_stage_can_ring_out":
			return await _scenario_every_stage_can_ring_out()
		"hazard_zone_kills_at_full_health":
			return await _scenario_hazard_zone_kills_at_full_health()
		"moving_platform_carries_player":
			return await _scenario_moving_platform_carries_player()
		"head_plants_moving_platform":
			return await _scenario_head_plants_moving_platform()
		"crumbling_ledge_three_phases":
			return await _scenario_crumbling_ledge_three_phases()
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
			# DISCLOSURE: these two lines are a **repair of a pre-existing
			# scenario**, edited in place, in a file whose convention is that
			# new work is appended. They are not part of the weapon roster;
			# `heads_do_not_tunnel_head` had this hole before the roster
			# existed and the roster's own sweep would have inherited it.
			# Recorded here rather than left to be found because an in-place
			# edit to a shared append-only file is exactly the change a
			# reviewer of an appended diff would never look for.
			#
			# What was wrong. Each charge starts on a clean pair. A charge is
			# a fixture for the sweep, not a fight: two bodies driven into
			# each other at up to 1800 px/s each batter one another through
			# the weapons trapped between them, and the damage that left
			# behind used to carry into the next charge. Twelve charges of it
			# eliminated a player partway down the sweep -- an eliminated
			# player is frozen and its head leaves the collision layer -- and
			# every remaining charge then measured two heads that could no
			# longer meet, quietly voiding the rest of the sweep while it
			# still reported no breach. Nothing here is about damage; this
			# just stops one trial's wear deciding what the next one is
			# allowed to test.
			#
			# And what it costs. Writing `damage` straight onto the player
			# goes round the player's own damage path, so
			# `_update_damage_visual()` never re-runs and the body keeps the
			# fill colour it had reddened to. Nothing in this scenario looks
			# at the fill -- `damage_reddens_fill_identity_persists` is where
			# that is asserted, and it drives damage the proper way -- so the
			# shortcut is safe here and would not be anywhere the visual is
			# read.
			attacker.damage = 0.0
			blocker.damage = 0.0
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

## ADR-0010: a weapon head is a cluster of circles fitted to the weapon's
## drawn art, so what has to be true of every weapon is that **every head
## circle lies inside the art outline**, within ART_CONTAINMENT_TOLERANCE.
##
## This replaces `weapon_silhouette_matches_head_shape`, which checked the
## older and now impossible promise that the drawing *equals* the hitbox. The
## promise that survived the change is the one a player can feel: nothing hits
## them from outside what they can see. It does not run the other way -- a
## crescent's horns taper past where any circle fits, and that is the
## approximation ADR-0010 chose.
##
## Read off a built rig rather than out of the resource: the circles are the
## ones `Player` gave the head body and the outline is the polygon it gave the
## head's `Polygon2D`, both in head-local space, so this fails if the rig
## stops honouring either. Checking the resource against itself would pass
## whatever the rig did with it.
func _scenario_weapon_head_circles_within_art() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var player: RigidBody2D = _spawn_player(stage, PARK_POSITION)
	await _await_ticks(2)

	for path: String in WEAPON_RESOURCE_PATHS:
		var stats: Resource = load(path)
		if stats == null:
			failures.append("%s: could not be loaded" % path)
			continue
		player.set_weapon_stats(stats)
		await _await_ticks(2)
		failures.append_array(_art_containment_failures(path.get_file(), player))

	# The head a bare `WeaponStats.new()` carries, which is what every stub
	# in this suite is built from: it has to be a real weapon, drawn as what
	# it hits with, or the scenarios that swap one in are driving a head that
	# could not exist in a fight.
	player.set_weapon_stats(WeaponStatsType.new())
	await _await_ticks(2)
	failures.append_array(_art_containment_failures("the default head", player))

	# And the check has to be able to fail, or a head built with no circles
	# at all would sail through everything above. Same default art, one
	# circle moved well outside it.
	var misfit := WeaponStatsType.new()
	misfit.head_circle_offsets = PackedVector2Array([Vector2(MISFIT_CIRCLE_OFFSET, 0.0)])
	misfit.head_circle_radii = PackedFloat32Array([WeaponStatsType.DEFAULT_HEAD_RADIUS])
	player.set_weapon_stats(misfit)
	await _await_ticks(2)
	if _art_containment_failures("misfitted head", player).is_empty():
		failures.append("a head circle moved %.1f px clear of its art passed the containment check" % MISFIT_CIRCLE_OFFSET)

	await _teardown(stage)
	return failures

## Every way the head a player is currently holding fails ADR-0010's
## guarantee: no art of its own, no art worth the name, nothing to hit with,
## or a circle reaching outside what is drawn.
func _art_containment_failures(label: String, player: RigidBody2D) -> Array[String]:
	var failures: Array[String] = []
	var outline: PackedVector2Array = player.weapon_head_visual_polygon()
	var circles: Array[Dictionary] = player.weapon_head_circles()
	if player.weapon_head_visual_is_fallback():
		failures.append("%s: drawn as the fallback box, so it carries no art for its circles to sit inside" % label)
	if outline.size() < 3:
		failures.append("%s: the drawn art has %d points, which is not a polygon" % [label, outline.size()])
		return failures
	if circles.is_empty():
		failures.append("%s: the head was built with no collision circles, so it hits nothing" % label)
	var worst: float = -INF
	for circle: Dictionary in circles:
		var centre: Vector2 = circle["offset"]
		var radius: float = circle["radius"]
		var outside: float = _circle_outside_polygon(centre, radius, outline)
		worst = maxf(worst, outside)
		if outside > ART_CONTAINMENT_TOLERANCE:
			failures.append("%s: a head circle (centre %.2f,%.2f radius %.2f) reaches %.2f px outside the drawn art" % [
				label, centre.x, centre.y, radius, outside])
	if not circles.is_empty():
		print("      %s: %d circles against %d points of art, worst fit %+.2f px outside it (negative is inside, clear)" % [
			label, circles.size(), outline.size(), worst])
	return failures

## How far a circle reaches outside a polygon, in pixels: negative -- how much
## room it has to spare -- when it is inside with clearance.
##
## The polygon is the drawn art and is not necessarily convex (a crescent is
## not), so this is distance to the nearest edge rather than anything that
## assumes a side to be on, with the centre's own containment deciding the
## sign.
func _circle_outside_polygon(centre: Vector2, radius: float, polygon: PackedVector2Array) -> float:
	var nearest_edge: float = INF
	for i in polygon.size():
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		nearest_edge = minf(nearest_edge, centre.distance_to(Geometry2D.get_closest_point_to_segment(centre, a, b)))
	if not Geometry2D.is_point_in_polygon(centre, polygon):
		return nearest_edge + radius
	return radius - nearest_edge

# --- Stage rotation (ADR-0008) -----------------------------------------------

## Spawn points every real stage must declare: one per player slot in
## scenes/Main.tscn (ADR-0008). Grows with the roster (ADR-0007).
const STAGE_MIN_SPAWNS: int = 2

## A private test double for ControllerServer's roster seam
## (claimed_slots / expire_disconnected_claims), scoped to this file only so
## it can't collide with issue #6's separate tools/stub_roster.gd -- both
## land in the same PR window and this scenario has no need of anything else
## that stub exposes.
class _FakeRoster extends Node:
	var slots: Array[int] = []
	func claimed_slots() -> Array[int]:
		return slots
	func expire_disconnected_claims() -> void:
		pass

## Packs a bare Node2D + Stage.gd + Spawn* markers into a PackedScene at
## runtime, so the rotation scenario below doesn't need throwaway fixture
## .tscn files under scenes/stages/ alongside the three real stages.
func _make_stub_stage(stage_name: String, spawns: Array[Vector2]) -> PackedScene:
	var root := Node2D.new()
	root.name = stage_name
	root.set_script(StageType)
	for i in spawns.size():
		var marker := Marker2D.new()
		marker.name = "Spawn%d" % i
		marker.position = spawns[i]
		root.add_child(marker)
		marker.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.queue_free()
	return packed

## Issue #8: the active stage advances by one every round and wraps back to
## the first after the last. Drives a real RoundManager (script preloaded by
## path, no class_name) through several rounds against three in-memory stub
## stages -- no ground is needed, since only the active stage's identity is
## asserted here, not spawn safety (see stage_spawns_are_safe for that) --
## and the private _FakeRoster above standing in for ControllerServer.
func _scenario_stage_rotates_each_round() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = Node2D.new()
	get_root().add_child(stage)

	# Named explicitly and referenced via literal relative NodePaths below,
	# rather than each node's own get_path(): this scenario can be the very
	# first thing run (e.g. `--scenario=stage_rotates_each_round` on its own),
	# before the root has completed its first tick, and get_path() fails with
	# "not in a scene tree" that early even though add_child() itself is fine.
	var container := Node2D.new()
	container.name = "Container"
	stage.add_child(container)

	var stage_names: PackedStringArray = ["Stub0", "Stub1", "Stub2"]
	var stub_scenes: Array[PackedScene] = []
	for stage_name: String in stage_names:
		stub_scenes.append(_make_stub_stage(stage_name, [Vector2.ZERO, Vector2(50, 0)]))

	var p1: RigidBody2D = PlayerScene.instantiate() as RigidBody2D
	p1.name = "P1"
	stage.add_child(p1)
	p1.global_position = DEEP_PARK_POSITION
	p1.bind_controller()
	var p2: RigidBody2D = PlayerScene.instantiate() as RigidBody2D
	p2.name = "P2"
	stage.add_child(p2)
	p2.global_position = DEEP_PARK_POSITION + Vector2(300, 0)
	p2.bind_controller()

	var roster := _FakeRoster.new()
	roster.name = "Roster"
	roster.slots = [0, 1]
	stage.add_child(roster)

	var paths: Array[NodePath] = [NodePath("../P1"), NodePath("../P2")]
	var round_manager := Node.new()
	round_manager.set_script(RoundManagerType)
	round_manager.player_paths = paths
	round_manager.stage_scenes = stub_scenes
	round_manager.arena_container_path = NodePath("../Container")
	round_manager.controller_server_path = NodePath("../Roster")
	round_manager.min_players_to_start = 2
	round_manager.round_end_pause_sec = 0.0
	stage.add_child(round_manager)

	# Enough rounds to wrap the 3-stage roster around twice, so "wraps back
	# to the first stage" is actually exercised rather than merely "advances".
	var rounds: int = stage_names.size() * 2 + 1
	for round_index in rounds:
		var active_name: String = ""
		for _i in 120:
			await physics_frame
			if p1.alive and p2.alive and container.get_child_count() > 0:
				active_name = container.get_child(container.get_child_count() - 1).name
				break
		if active_name.is_empty():
			failures.append("round %d: never saw a live round with a stage instanced" % round_index)
			break
		var expected: String = stage_names[round_index % stage_names.size()]
		if active_name != expected:
			failures.append("round %d: active stage was %s, expected %s" % [round_index, active_name, expected])

		# End this round (alternating who is eliminated, so scoring exercises
		# both slots) so the next one gets a chance to start.
		if round_index % 2 == 0:
			p1.eliminate()
		else:
			p2.eliminate()
		await _await_ticks(4)

	await _teardown(stage)
	return failures

## Issue #8 outcome: each real stage's declared spawn points land on solid
## ground and the player idles there safely for 60 ticks -- not falling
## through a gap, not clipped into geometry, not still falling.
##
## Also holds each stage to ADR-0008's contract of one spawn per player slot
## (STAGE_MIN_SPAWNS), so a stage missing a marker fails here instead of
## spawning someone at the origin in live play.
##
## STAGE_PATHS is the rotation itself, listed in the order scenes/Main.tscn
## rotates through it. Keeping the list here rather than inline means a stage
## added to the rotation is swept by this scenario the moment the one list is
## updated.
const STAGE_PATHS: PackedStringArray = [
	"res://scenes/stages/Flatlands.tscn",
	"res://scenes/stages/Pillars.tscn",
	"res://scenes/stages/Highrise.tscn",
	"res://scenes/stages/Islands.tscn",
	"res://scenes/stages/Gauntlet.tscn",
	"res://scenes/stages/Slant.tscn",
	"res://scenes/stages/Bowl.tscn",
	"res://scenes/stages/Furnace.tscn",
]

func _scenario_stage_spawns_are_safe() -> Array[String]:
	var failures: Array[String] = []
	var stage_paths: PackedStringArray = STAGE_PATHS

	for path: String in stage_paths:
		# Each stage's _teardown() marks the scenario complete, so reset it
		# here: a script error on a later stage must not inherit the earlier
		# stage's "completed" and pass silently.
		_scenario_completed = false
		var stage: Node2D = Node2D.new()
		get_root().add_child(stage)
		var stage_scene: PackedScene = load(path)
		var instance: Node2D = stage_scene.instantiate()
		stage.add_child(instance)
		var spawns: Array[Vector2] = instance.get_spawn_points()

		if spawns.size() < STAGE_MIN_SPAWNS:
			failures.append("%s: declared %d spawn point(s), needs at least %d" % [
				path, spawns.size(), STAGE_MIN_SPAWNS])

		for i in spawns.size():
			var player: RigidBody2D = _spawn_player(stage, spawns[i])
			await _await_ticks(60)
			if not player.alive:
				failures.append("%s spawn %d: player died within 60 idle ticks" % [path, i])
			elif absf(player.linear_velocity.y) > SETTLED_SPEED:
				failures.append("%s spawn %d: never settled, vertical speed %.1f px/s" % [
					path, i, player.linear_velocity.y])
			player.queue_free()
			await _await_ticks(BOOST_RESET_TICKS)

		await _teardown(stage)

	return failures

# --- Roster and round loop (issue #12) --------------------------------------

## Grace period the abandoned-round scenario runs RoundManager with: short
## enough to wait out, long enough that the reconnect inside it is clearly
## inside it.
const ABANDON_GRACE_SEC: float = 0.5
## How long a round-loop scenario waits for something that should happen
## within a few frames before calling it a failure.
const ROUND_LOOP_TIMEOUT_MSEC: int = 3000

## A test double for ControllerServer's roster seam that models liveness:
## `slots` are claimed, `live` are the ones with a connected controller, and
## `expire_disconnected_claims()` behaves like the real one -- it drops every
## claimed slot that is not live.
class _LiveRoster extends Node:
	var slots: Array[int] = []
	var live: Array[int] = []
	func claimed_slots() -> Array[int]:
		return slots
	func slot_has_controller(slot: int) -> bool:
		return live.has(slot)
	func expire_disconnected_claims() -> void:
		var kept: Array[int] = []
		for slot in slots:
			if live.has(slot):
				kept.append(slot)
		slots = kept

## A real RoundManager (preloaded by path) driving two round-owned players
## against a _LiveRoster, on a stub stage with spawns and no geometry at all:
## players spawn far above everything and simply fall, alive, for as long as
## a scenario needs. Referenced through literal relative NodePaths rather than
## get_path(), which fails before the root's first tick when a scenario runs
## on its own.
func _new_round_loop(grace_sec: float) -> Dictionary:
	var stage := Node2D.new()
	get_root().add_child(stage)
	var container := Node2D.new()
	container.name = "Container"
	stage.add_child(container)
	var players: Array[RigidBody2D] = []
	for i in 2:
		var player: RigidBody2D = PlayerScene.instantiate() as RigidBody2D
		player.name = "P%d" % i
		player.start_in_round = false
		stage.add_child(player)
		players.append(player)
	var roster := _LiveRoster.new()
	roster.name = "Roster"
	stage.add_child(roster)
	var round_manager := Node.new()
	round_manager.set_script(RoundManagerType)
	var paths: Array[NodePath] = [NodePath("../P0"), NodePath("../P1")]
	round_manager.player_paths = paths
	var stub_stages: Array[PackedScene] = [
		_make_stub_stage("Sky", [DEEP_PARK_POSITION, DEEP_PARK_POSITION + Vector2(300, 0)])]
	round_manager.stage_scenes = stub_stages
	round_manager.arena_container_path = NodePath("../Container")
	round_manager.controller_server_path = NodePath("../Roster")
	round_manager.min_players_to_start = 2
	round_manager.round_end_pause_sec = 0.0
	round_manager.abandoned_round_grace_sec = grace_sec
	stage.add_child(round_manager)
	return {"stage": stage, "players": players, "roster": roster, "round_manager": round_manager}

## Steps physics until `condition` holds or `timeout_msec` of wall-clock time
## passes; returns whether it held. Wall-clock rather than ticks because
## RoundManager's grace and pause timers are wall-clock.
func _await_condition(condition: Callable, timeout_msec: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if condition.call():
			return true
	return false

func _await_msec(msec: int) -> void:
	var deadline: int = Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < deadline:
		await physics_frame

## Issue #12: a claim whose controller dropped while no round was running is
## released right away, not held until a round that has not started yet ends.
## Before the fix it was held forever, counted towards min_players_to_start,
## and the next phone to join started a round against a controller-less body.
func _scenario_waiting_expires_disconnected_claims() -> Array[String]:
	var failures: Array[String] = []
	var loop: Dictionary = _new_round_loop(ABANDON_GRACE_SEC)
	var roster: _LiveRoster = loop["roster"]
	var players: Array[RigidBody2D] = loop["players"]

	# Slot 0 was claimed, then its phone dropped, all before any round.
	roster.slots = [0]
	roster.live = []
	var released: bool = await _await_condition(func() -> bool: return roster.slots.is_empty(), ROUND_LOOP_TIMEOUT_MSEC)
	if not released:
		failures.append("a claim that disconnected while waiting was still held: %s" % [roster.slots])

	# A second phone joins. Only one controller is actually connected, so no
	# round may start.
	roster.slots.append(1)
	roster.live = [1]
	await _await_ticks(SETTLE_TICKS)
	for i in players.size():
		if players[i].alive:
			failures.append("P%d was brought into a round that only one connected player could have started" % i)

	await _teardown(loop["stage"])
	return failures

## Issue #12 / ADR-0007 amendment: a round in which no surviving player has a
## connected controller ends with no winner once the grace period passes, and
## a controller reconnecting inside the grace period keeps the round going.
## Before the fix such a round could never end, so its claims never expired
## and every new phone was refused.
func _scenario_abandoned_round_ends_without_winner() -> Array[String]:
	var failures: Array[String] = []
	var loop: Dictionary = _new_round_loop(ABANDON_GRACE_SEC)
	var roster: _LiveRoster = loop["roster"]
	var round_manager: Variant = loop["round_manager"]
	var players: Array[RigidBody2D] = loop["players"]
	var grace_msec: int = int(ABANDON_GRACE_SEC * 1000.0)

	roster.slots = [0, 1]
	roster.live = [0, 1]
	var started: bool = await _await_condition(
		func() -> bool: return players[0].alive and players[1].alive, ROUND_LOOP_TIMEOUT_MSEC)
	if not started:
		failures.append("round never started with two connected players")
		await _teardown(loop["stage"])
		return failures

	# Everyone drops, but one controller is back well inside the grace period:
	# the round carries on, and keeps carrying on well past the grace period.
	roster.live = []
	await _await_msec(grace_msec / 3)
	roster.live = [0]
	await _await_msec(grace_msec * 2)
	if not (players[0].alive and players[1].alive):
		failures.append("round ended although a controller reconnected inside the grace period")

	# Everyone drops for good: the round ends with nobody scoring or dying.
	roster.live = []
	var ended: bool = await _await_condition(
		func() -> bool: return not players[0].alive and not players[1].alive,
		grace_msec + ROUND_LOOP_TIMEOUT_MSEC)
	if not ended:
		failures.append("round with no connected controller never ended")
	for i in players.size():
		if round_manager._scores[i] != 0:
			failures.append("P%d scored %d from an abandoned round" % [i, round_manager._scores[i]])
		if players[i].deaths != 0:
			failures.append("P%d was counted as dying (%d) in an abandoned round" % [i, players[i].deaths])

	# And the round boundary releases the claims, so new phones can join.
	var released: bool = await _await_condition(func() -> bool: return roster.slots.is_empty(), ROUND_LOOP_TIMEOUT_MSEC)
	if not released:
		failures.append("abandoned round ended but its claims were still held: %s" % [roster.slots])

	await _teardown(loop["stage"])
	return failures
## --- Round winner keeps their weapon (issue #6) -----------------------------

## Preloaded by path, never referenced by `class_name` (CLAUDE.md): the
## global class cache lives in the gitignored `.godot/` and only an editor
## run builds it, so a fresh clone would fail to resolve the name.
const RoundManagerScript := preload("res://scripts/RoundManager.gd")
const StubRosterScript := preload("res://tools/stub_roster.gd")

## Clear air above the arena, well apart, so a full-reach weapon never
## touches terrain or the other player while this scenario runs.
const ROUND_WINNER_SPAWN_A: Vector2 = Vector2(-100.0, -600.0)
const ROUND_WINNER_SPAWN_B: Vector2 = Vector2(100.0, -600.0)
## `round_end_pause_sec` is 0 for this scenario, so a round transition is a
## couple of `_process` ticks away rather than a real-time pause; bounded so
## a broken loop fails the scenario instead of hanging it.
const ROUND_TRANSITION_TICKS: int = 20
## Ticks given for RoundManager's ROUND_END -> WAITING transition to run
## after the stub roster is edited to simulate a claim dropping, before
## asserting the round is stuck waiting on it.
const CLAIM_DROP_SETTLE_TICKS: int = 5

## D1-D3 (issue #6): at round start, the previous round's winner keeps
## whatever `weapon_stats` it held; every other rostered player (and, in a
## no-survivors round, everyone) resets to the default (the pickaxe). A
## winner claim that later expires does not pass the weapon to whoever
## claims the freed slot (D3). Drives the real `RoundManager` and
## `Player.tscn` end to end; only `ControllerServer`'s roster seam is
## stubbed (`tools/stub_roster.gd`), since the real one opens LAN sockets
## and this runner is headless.
func _scenario_round_winner_keeps_weapon() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()

	# Since #8 a round's spawn points come from the active stage, not from an
	# export on RoundManager, so this scenario hands it a one-stage rotation
	# holding the two clear-air spawns it needs rather than setting them
	# directly. Named explicitly, since the NodePaths below are literal.
	var container := Node2D.new()
	container.name = "RoundWinnerContainer"
	stage.add_child(container)

	var p1: RigidBody2D = _spawn_player(stage, ROUND_WINNER_SPAWN_A)
	p1.name = "RoundWinnerP1"
	var p2: RigidBody2D = _spawn_player(stage, ROUND_WINNER_SPAWN_B)
	p2.name = "RoundWinnerP2"

	var roster := StubRosterScript.new()
	roster.name = "RoundWinnerRoster"
	roster.slots = [0, 1]
	stage.add_child(roster)

	var round_manager := RoundManagerScript.new()
	round_manager.name = "RoundWinnerRoundManager"
	round_manager.player_paths = [NodePath("../RoundWinnerP1"), NodePath("../RoundWinnerP2")]
	round_manager.stage_scenes = [
		_make_stub_stage("RoundWinnerStage", [ROUND_WINNER_SPAWN_A, ROUND_WINNER_SPAWN_B])]
	round_manager.arena_container_path = NodePath("../RoundWinnerContainer")
	round_manager.controller_server_path = NodePath("../RoundWinnerRoster")
	round_manager.round_end_pause_sec = 0.0
	round_manager.min_players_to_start = 2
	stage.add_child(round_manager)

	# Round 1 starts on its own -- both slots are already claimed. Only once
	# it is running do we hand out the test weapons: doing it earlier would
	# be undone by round 1's own reset.
	await _await_ticks(ROUND_TRANSITION_TICKS)

	var stub_p1 := WeaponStatsType.new()
	stub_p1.min_reach = STUB_MIN_REACH
	stub_p1.max_reach = STUB_MAX_REACH
	p1.set_weapon_stats(stub_p1)

	var stub_p2 := WeaponStatsType.new()
	stub_p2.min_reach = STUB_MIN_REACH
	stub_p2.max_reach = STUB_MAX_REACH
	p2.set_weapon_stats(stub_p2)
	await _await_ticks(2)

	# --- Phase A: the winner keeps the weapon, the loser resets ------------
	p2.eliminate()
	var phase_a_restarted: bool = false
	for i in ROUND_TRANSITION_TICKS:
		await physics_frame
		if p1.alive and p2.alive:
			phase_a_restarted = true
			break
	if not phase_a_restarted:
		failures.append("phase A: round did not restart after p2 was eliminated")
		await _teardown(stage)
		return failures

	p1.set_input_vector(Vector2.RIGHT)
	p2.set_input_vector(Vector2.RIGHT)
	await _await_ticks(SETTLE_TICKS)

	if p1.weapon_stats != stub_p1:
		failures.append("phase A: winner p1 did not keep its weapon_stats instance")
	if p2.weapon_stats == null or p2.weapon_stats.resource_path != "res://resources/pickaxe.tres":
		failures.append("phase A: loser p2 did not reset to the pickaxe")
	var p1_reach: float = _reach_of(p1)
	if absf(p1_reach - STUB_MAX_REACH) > REACH_TOLERANCE:
		failures.append("phase A: winner p1 reached %.1f px at full drag, expected the stub's %.1f px" % [
			p1_reach, STUB_MAX_REACH])
	var p2_reach: float = _reach_of(p2)
	if absf(p2_reach - MAX_REACH) > REACH_TOLERANCE:
		failures.append("phase A: loser p2 reached %.1f px at full drag, expected the pickaxe's %.1f px" % [
			p2_reach, MAX_REACH])

	# --- Phase B: no survivors, so everyone resets --------------------------
	p1.eliminate()
	p2.eliminate()
	var phase_b_restarted: bool = false
	for i in ROUND_TRANSITION_TICKS:
		await physics_frame
		if p1.alive and p2.alive:
			phase_b_restarted = true
			break
	if not phase_b_restarted:
		failures.append("phase B: round did not restart after a no-survivors round")
		await _teardown(stage)
		return failures

	if p1.weapon_stats == null or p1.weapon_stats.resource_path != "res://resources/pickaxe.tres":
		failures.append("phase B: p1 did not reset to the pickaxe after a no-survivors round")
	if p2.weapon_stats == null or p2.weapon_stats.resource_path != "res://resources/pickaxe.tres":
		failures.append("phase B: p2 did not reset to the pickaxe after a no-survivors round")

	# --- Phase C: an expired winner claim does not pass the weapon on (D3) -
	var stub_p1c := WeaponStatsType.new()
	stub_p1c.min_reach = STUB_MIN_REACH
	stub_p1c.max_reach = STUB_MAX_REACH
	p1.set_weapon_stats(stub_p1c)
	await _await_ticks(2)

	p2.eliminate()
	# Simulate the claim dropping before the (zero-length) pause expires: the
	# freed slot 0 can no longer be found in claimed_slots() by the time
	# RoundManager reaches the ROUND_END -> WAITING transition.
	roster.slots = [1]
	await _await_ticks(CLAIM_DROP_SETTLE_TICKS)

	if p1.alive:
		failures.append("phase C: round restarted with only one claimed slot, expected it to wait")

	# A newcomer claims the freed slot 0.
	roster.slots = [0, 1]
	var phase_c_restarted: bool = false
	for i in ROUND_TRANSITION_TICKS:
		await physics_frame
		if p1.alive and p2.alive:
			phase_c_restarted = true
			break
	if not phase_c_restarted:
		failures.append("phase C: round did not restart once slot 0 was reclaimed")
		await _teardown(stage)
		return failures

	if p1.weapon_stats == null or p1.weapon_stats.resource_path != "res://resources/pickaxe.tres":
		failures.append("phase C: the expired winner's claim passed the weapon on to the newcomer in its slot")

	await _teardown(stage)
	return failures

# --- The weapon roster (issue #13) -------------------------------------------
#
# Five weapons that differ in weight, reach and damage (CONTEXT.md, ADR-0005),
# so that picking one is a commitment rather than a skin. The scenarios below
# hand a real player each real resource and assert on what a player would see
# happen: how far the head got, what a strike took off, how quickly the weapon
# answered a new drag, and who gave way when two heads met.
#
# Each weapon's own numbers are read off the resource it is holding, because
# the starting table is explicitly a baseline to be tuned by playtesting
# (issue #13) and a suite that wrote those numbers down a second time would
# have to be edited every time somebody turned a dial. What keeps that from
# passing whatever the resources happen to say is the **tier ordering**, which
# is the design claim rather than a number: the roster is only worth having if
# L really does out-reach M and M really does out-reach S, and those orderings
# are asserted on what was measured, never on what was declared.

## Which tier each weapon sits in for each quantity, per issue #13's
## starting-numbers table. Keyed by the resource file's basename.
##
## Reach:  S 90 / M 140 / L 200 px.
## Damage: S 20 / M 34 / L 55 per full-speed hit.
## Answer: how many ticks the weapon takes to come out onto a newly commanded
##         reach, so S is the light, quick end of the roster and L the heavy,
##         slow one -- the tiers still read smallest-to-largest in the
##         measured quantity, which is what `_roster_tier_failures()` checks.
const ROSTER_REACH_TIERS: Dictionary = {
	"staff": "L",
	"pickaxe": "M",
	"axe": "M",
	"sword": "S",
	"dagger": "S",
}
const ROSTER_DAMAGE_TIERS: Dictionary = {
	"axe": "L",
	"pickaxe": "M",
	"sword": "M",
	"dagger": "M",
	"staff": "S",
}
const ROSTER_ANSWER_TIERS: Dictionary = {
	"staff": "S",
	"dagger": "S",
	"pickaxe": "M",
	"sword": "M",
	"axe": "L",
}
## Smallest measured quantity first, which is the order the tiers have to come
## out in.
const ROSTER_TIER_ORDER: PackedStringArray = ["S", "M", "L"]

## Ticks given to a `set_weapon_stats()` swap before the new rig is driven.
## The rebuild is deferred (see `Player.set_weapon_stats`), so the rig a
## scenario measures is not the one it asked for until a frame has passed.
const ROSTER_SWAP_TICKS: int = 4
## Ticks a weapon is given to arrive at a commanded reach. Longer than
## SETTLE_TICKS because the roster's slowest weapon extends at 470 px/s
## against the pickaxe's 700, and its 120 px of travel alone is 15 ticks.
const ROSTER_SETTLE_TICKS: int = 45
## How much further an L weapon has to reach than every M one, and M than
## every S, before the roster's reach ordering counts as real. The table's own
## steps are 60 px and 50 px, so this is a wide margin over measurement noise
## and a long way under a step.
const ROSTER_REACH_TIER_MARGIN: float = 20.0

## The head speed a strike deals exactly the weapon's own `damage` at,
## written down here rather than read off `Player`: a test that asked the
## player what full speed meant would pass whatever the player decided. It is
## ADR-0005's committed full-reach sweep, and `Player`'s documented scaling
## puts the weapon's whole `damage` on a hit landing at it.
const FULL_STRIKE_HEAD_SPEED: float = 2200.0
## What the charging body is actually commanded, which is not the same thing.
## A `RigidBody2D` carries linear damping, so a body told to run at a speed
## settles a little under it; this is the command that lands the **head** on
## FULL_STRIKE_HEAD_SPEED, and the trial measures the head to check that it
## did rather than assuming it.
const FULL_STRIKE_COMMAND: float = 2280.0
## How far off full speed the head may actually have been going when it
## landed. The strike rule is linear in speed, so a band this wide moves the
## axe's 55 by under 2 -- which is what ROSTER_DAMAGE_TOLERANCE has to cover,
## and it sits a long way under the 14 and 21 the roster's damage tiers are
## apart.
const FULL_STRIKE_SPEED_BAND: float = 50.0
const ROSTER_DAMAGE_TOLERANCE: float = 3.0
## Room for two weapons that should deal the same damage to disagree, and the
## margin by which a higher tier has to beat a lower one. The table's steps
## are 21 and 14, so both sit clear of the tolerance above and well under a
## step.
const ROSTER_DAMAGE_SPREAD: float = 6.0
const ROSTER_DAMAGE_TIER_MARGIN: float = 6.0
## How far the victim is planted from where the charge starts, and how long
## the charge is watched for. The run-up has to be long enough that the head
## has stopped ringing on the end of its own haft and is being carried along
## at the body's speed: a body yanked to full speed from rest swings its head
## out past that speed and back for about 15 ticks, and at 36 px a tick this
## leaves twice that before anything is in the way.
const FULL_STRIKE_RUN_UP: float = 1600.0
const FULL_STRIKE_TICKS: int = 80

## The reach the responsiveness trial drags every weapon out to, and how close
## the head has to get to it to count as having answered. 90 px is the
## shortest full reach on the roster, so every weapon can be asked for it, and
## every weapon rests at the same 20 px -- which makes the five comparable:
## the same 70 px of travel, commanded the same way, timed the same way.
const ROSTER_ANSWER_REACH: float = 90.0
const ROSTER_ANSWER_TOLERANCE: float = 2.0
const ROSTER_ANSWER_TICKS: int = 120
## Ticks two weapons of the same tier may disagree by, and ticks a slower tier
## has to lag a quicker one by. Deliberately asserted as an ordering in ticks
## rather than against any absolute count: the drive speeds are a starting
## table to be tuned, and tuning them must not turn this red.
const ROSTER_ANSWER_SPREAD: float = 3.0
const ROSTER_ANSWER_TIER_MARGIN: float = 1.0

## Two players this far apart for the roster clash. Close enough that two
## daggers (90 px of reach each) still meet with both drives pushing at their
## force ceiling rather than arriving and stopping, which is what makes the
## like-for-like control a contest and not two weapons resting on each other.
const ROSTER_CLASH_SEPARATION: float = 150.0
## Ticks the two heads are held against each other before the contest is read.
const ROSTER_CLASH_HOLD_TICKS: int = 60
## How much more of its own commanded reach the lighter weapon has to have
## surrendered. "Gave way" is the observation the clash is really about, and
## unlike where the heads met it owes nothing to either weapon's reach: it is
## each weapon measured against the reach it was itself asking for.
const MIN_GIVE_MARGIN: float = 20.0
## How far apart two identical weapons' surrenders may be before the control
## is not symmetric after all.
const SYMMETRIC_GIVE_TOLERANCE: float = 8.0
const AXE_PATH: String = "res://resources/axe.tres"
const DAGGER_PATH: String = "res://resources/dagger.tres"

## US-4/7/12/14/20: a full drag puts each weapon's head at that weapon's own
## full reach, and the five weapons come out in the tiers the roster asked
## for.
##
## Two claims, and the second is the one that makes the first worth asserting.
## Per weapon, the head has to settle where that resource says it reaches --
## the weapon delivering its own data. Across weapons, the measured reaches
## have to sort into S below M below L by a clear margin, which is the roster
## being a roster: five weapons that all reached 140 px would satisfy every
## per-weapon check above and would still be one weapon five times.
func _scenario_weapon_reach_matches_roster() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var player: RigidBody2D = _spawn_player(stage, PARK_POSITION)
	await _await_ticks(ROSTER_SWAP_TICKS)

	var observed: Dictionary = {}
	for path: String in WEAPON_RESOURCE_PATHS:
		var weapon: String = path.get_file().get_basename()
		var stats: WeaponStatsType = load(path)
		if stats == null:
			failures.append("%s: could not be loaded" % path)
			continue
		player.set_weapon_stats(stats)
		await _await_ticks(ROSTER_SWAP_TICKS)
		# Re-parked for each weapon for the same reason `extension_tracks_drag`
		# re-parks between samples: the head has to be measured in clear air,
		# not planted on the arena.
		player.teleport_to(PARK_POSITION)
		player.set_input_vector(Vector2.RIGHT)
		await _await_ticks(ROSTER_SETTLE_TICKS)

		var reach: float = _reach_of(player)
		observed[weapon] = reach
		print("      %s: full drag settled at %.1f px, its own max reach is %.1f px" % [
			weapon, reach, stats.max_reach])
		if absf(reach - stats.max_reach) > REACH_TOLERANCE:
			failures.append("%s: full drag settled at %.1f px, not at the %.1f px of reach it carries" % [
				weapon, reach, stats.max_reach])

	failures.append_array(_roster_tier_failures(
		"reach", "px", observed, ROSTER_REACH_TIERS, REACH_TOLERANCE, ROSTER_REACH_TIER_MARGIN))

	await _teardown(stage)
	return failures

## US-9/16/20: a full-speed strike with each weapon takes that weapon's own
## damage off, and the five sort into the roster's damage tiers.
##
## Speed is the thing that has to be controlled here, because the strike rule
## scales damage by it (ADR-0005) and the five weapons swing at wildly
## different rates -- comparing a staff's swing against an axe's would measure
## the drive speeds, not the damage. So the head is not swung at all: the
## attacker holds it out and is carried into the victim at a commanded speed,
## which is the same speed whatever weapon it is holding. The speed the head
## was actually seen moving at is then measured from its own positions and
## checked to be full speed, so the trial says what it claims to say rather
## than assuming the body dragged the head along perfectly.
##
## Two things the charge has to get right, both learned the hard way from a
## version of this that did neither. It has to be **long**, because a head
## yanked to speed from rest rings in and out on its haft for a dozen ticks
## and arrives at anything from half speed to a third over it. And it has to
## be **level**: only the part of the head's motion heading into the victim is
## scored (`Player._on_head_hit`), so a head that has sagged even 20 px by the
## time it arrives is scored well under the speed it is travelling at, by a
## different amount for every weapon.
func _scenario_weapon_damage_matches_roster() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var centre: Vector2 = DEEP_PARK_POSITION
	var attacker: RigidBody2D = _spawn_player(stage, centre)
	await _await_ticks(ROSTER_SWAP_TICKS)

	var observed: Dictionary = {}
	for path: String in WEAPON_RESOURCE_PATHS:
		var weapon: String = path.get_file().get_basename()
		var stats: WeaponStatsType = load(path)
		if stats == null:
			failures.append("%s: could not be loaded" % path)
			continue
		attacker.set_weapon_stats(stats)
		await _await_ticks(ROSTER_SWAP_TICKS)
		# A fresh victim per weapon, so every strike lands on somebody who has
		# taken nothing yet.
		var victim: RigidBody2D = _spawn_player(stage, centre + Vector2.RIGHT * FULL_STRIKE_RUN_UP)
		await physics_frame
		_brace(victim)

		var hit: Dictionary = await _charge_strike(attacker, victim)
		print("      %s: head arrived at %.0f px/s and took %.1f off, its own damage is %.1f (closest %.1f px)" % [
			weapon, hit["speed"], hit["damage"], stats.damage, hit["closest"]])
		if not hit["landed"]:
			failures.append("%s: the charge never reached the victim, so it proves nothing" % weapon)
		elif absf(float(hit["speed"]) - FULL_STRIKE_HEAD_SPEED) > FULL_STRIKE_SPEED_BAND:
			failures.append("%s: the head landed at %.0f px/s, not the %.0f px/s a full-speed strike is measured at" % [
				weapon, hit["speed"], FULL_STRIKE_HEAD_SPEED])
		else:
			observed[weapon] = hit["damage"]
			if absf(float(hit["damage"]) - stats.damage) > ROSTER_DAMAGE_TOLERANCE:
				failures.append("%s: a full-speed strike took %.1f off, not the %.1f of damage it carries" % [
					weapon, hit["damage"], stats.damage])

		victim.queue_free()
		await _await_ticks(BOOST_RESET_TICKS)

	failures.append_array(_roster_tier_failures(
		"damage", "", observed, ROSTER_DAMAGE_TIERS, ROSTER_DAMAGE_SPREAD, ROSTER_DAMAGE_TIER_MARGIN))

	await _teardown(stage)
	return failures

## US-10/11/17: a light weapon answers a newly commanded drag quicker than a
## medium one, which answers quicker than the heavy one.
##
## Asserted as an ordering in ticks and never against a tick count, because
## the drive speeds are a starting table the design expects to be tuned
## (issue #13) and tuning them must not turn this red. What it does pin down
## is the one thing tuning must not break: the axe's power costs it time, the
## dagger and staff buy their speed with damage or nothing to hit with, and if
## all five answered alike the roster would not feel like five weapons.
##
## The drag measured is a **reach** drag: every weapon is let go to the 20 px
## of rest reach they all share, then asked for 90 px, the shortest full reach
## on the roster. Same travel, same command, same clock for all five, and what
## separates them is the one thing meant to -- how fast the weapon is allowed
## to answer.
##
## Not measured as a turn, which is the other half of a drag: a turn is made
## against the weapon's own lever arm and the head's inertia out on the end of
## it, so what a turn times is mostly the weapon's length and its force
## ceiling. Timed that way the staff -- the lightest, quickest-slewing weapon
## on the roster -- comes out the most sluggish of the five, purely for being
## long, which is reach being measured and called responsiveness.
func _scenario_weapon_responsiveness_matches_roster() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var player: RigidBody2D = _spawn_player(stage, PARK_POSITION)
	await _await_ticks(ROSTER_SWAP_TICKS)
	_brace(player)

	var observed: Dictionary = {}
	for path: String in WEAPON_RESOURCE_PATHS:
		var weapon: String = path.get_file().get_basename()
		var stats: WeaponStatsType = load(path)
		if stats == null:
			failures.append("%s: could not be loaded" % path)
			continue
		player.set_weapon_stats(stats)
		await _await_ticks(ROSTER_SWAP_TICKS)
		player.set_input_vector(Vector2.ZERO)
		await _await_ticks(ROSTER_SETTLE_TICKS)

		var rest: float = _reach_of(player)
		var magnitude: float = (ROSTER_ANSWER_REACH - stats.min_reach) / (stats.max_reach - stats.min_reach)
		player.set_input_vector(Vector2.RIGHT * magnitude)
		var answered: int = -1
		for i in ROSTER_ANSWER_TICKS:
			await physics_frame
			if absf(_reach_of(player) - ROSTER_ANSWER_REACH) <= ROSTER_ANSWER_TOLERANCE:
				answered = i + 1
				break
		print("      %s: answered a drag from %.1f px out to %.1f px in %d ticks" % [
			weapon, rest, ROSTER_ANSWER_REACH, answered])
		if answered < 0:
			failures.append("%s: never came out to %.1f px within %d ticks of being asked for it" % [
				weapon, ROSTER_ANSWER_REACH, ROSTER_ANSWER_TICKS])
		else:
			observed[weapon] = float(answered)

	failures.append_array(_roster_tier_failures(
		"ticks to answer a new drag", "ticks", observed, ROSTER_ANSWER_TIERS,
		ROSTER_ANSWER_SPREAD, ROSTER_ANSWER_TIER_MARGIN))

	await _teardown(stage)
	return failures

## US-8/15: the heavy weapon wins the clash. An axe head and a dagger head are
## driven into each other and the axe gives way less.
##
## `clash_higher_drive_force_wins` already says a bigger force ceiling wins
## ground, using a stub weapon built in this file. This says the roster's own
## weight tiers are that difference: nothing here is synthesised, both sides
## are the shipped resources, and the axe's advantage is the 0.45 kg and
## 9000 N it actually carries against the dagger's 0.15 and 4000.
##
## Two measurements, because where the heads met is not the whole story. How
## far off the midline they met is the ground won, which is what a player
## sees. How much of its own commanded reach each weapon surrendered is who
## gave way, and that one owes nothing at all to either weapon's reach -- each
## side is measured against the reach it was itself asking for -- so it
## survives the axe being the longer weapon of the two.
##
## Both are read against a like-for-like control first: two daggers, where the
## situation is symmetric and so anything but a dead heat would be a bias in
## the rig rather than a property of the weapons. And the axe is then run from
## both sides, because an advantage that lives on the left-hand side of the
## arena is not an advantage the axe has.
func _scenario_heavy_weapon_wins_clash() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var centre: Vector2 = DEEP_PARK_POSITION
	var half: Vector2 = Vector2.RIGHT * ROSTER_CLASH_SEPARATION * 0.5
	var left: RigidBody2D = _spawn_player(stage, centre - half)
	var right: RigidBody2D = _spawn_player(stage, centre + half)
	await physics_frame

	var axe: WeaponStatsType = load(AXE_PATH)
	var dagger: WeaponStatsType = load(DAGGER_PATH)
	if axe == null or dagger == null:
		failures.append("the axe or the dagger could not be loaded, so there is no clash to run")
		await _teardown(stage)
		return failures

	# Braced, for the same reason `clash_higher_drive_force_wins` braces: each
	# weapon's push comes back through its own body, so two free players shove
	# themselves apart and their heads never stay in contact.
	_brace(left)
	_brace(right)

	var even: Dictionary = await _roster_clash(left, right, centre, dagger, dagger)
	print("      dagger against dagger: met %.1f px off the midline, %.1f px apart; gave way %.1f px and %.1f px" % [
		even["offset"], even["gap"], even["left_give"], even["right_give"]])
	failures.append_array(_clash_met_failures("dagger against dagger", even))
	if absf(float(even["offset"])) > SYMMETRIC_CLASH_TOLERANCE:
		failures.append("two daggers met %.1f px off the midline between them" % even["offset"])
	if absf(float(even["left_give"]) - float(even["right_give"])) > SYMMETRIC_GIVE_TOLERANCE:
		failures.append("two daggers gave way by %.1f px and %.1f px; neither should out-push the other" % [
			even["left_give"], even["right_give"]])

	var axe_left: Dictionary = await _roster_clash(left, right, centre, axe, dagger)
	print("      axe on the left: met %.1f px off the midline, %.1f px apart; axe gave way %.1f px, dagger %.1f px" % [
		axe_left["offset"], axe_left["gap"], axe_left["left_give"], axe_left["right_give"]])
	failures.append_array(_clash_met_failures("the axe on the left", axe_left))
	failures.append_array(_heavy_won_failures(
		"the axe on the left", axe_left["left_give"], axe_left["right_give"],
		float(axe_left["offset"]) - float(even["offset"])))

	var axe_right: Dictionary = await _roster_clash(left, right, centre, dagger, axe)
	print("      axe on the right: met %.1f px off the midline, %.1f px apart; dagger gave way %.1f px, axe %.1f px" % [
		axe_right["offset"], axe_right["gap"], axe_right["left_give"], axe_right["right_give"]])
	failures.append_array(_clash_met_failures("the axe on the right", axe_right))
	failures.append_array(_heavy_won_failures(
		"the axe on the right", axe_right["right_give"], axe_right["left_give"],
		float(even["offset"]) - float(axe_right["offset"])))

	await _teardown(stage)
	return failures

## Every way a set of per-weapon measurements fails the roster's own ordering:
## a weapon that was never measured at all, two weapons of one tier that came
## out unlike each other, or a tier that failed to beat the one below it.
##
## The tiers are the design claim (issue #13's starting-numbers table) and the
## values are what the run measured, so nothing here is the resources marking
## their own homework.
func _roster_tier_failures(quantity: String, unit: String, observed: Dictionary, tiers: Dictionary, spread: float, margin: float) -> Array[String]:
	var failures: Array[String] = []
	var buckets: Dictionary = {}
	for tier: String in ROSTER_TIER_ORDER:
		buckets[tier] = []

	for weapon: String in tiers:
		if not observed.has(weapon):
			failures.append("%s: %s was never measured, so the roster's ordering is untested" % [
				quantity, weapon])
			continue
		var bucket: Array = buckets[tiers[weapon]]
		bucket.append(float(observed[weapon]))

	for tier: String in ROSTER_TIER_ORDER:
		var values: Array = buckets[tier]
		if values.size() < 2:
			continue
		var low: float = float(values.min())
		var high: float = float(values.max())
		if high - low > spread:
			failures.append("%s: the %s tier came out spread over %.1f %s, from %.1f to %.1f -- one tier is meant to be one number" % [
				quantity, tier, high - low, unit, low, high])

	for i in range(1, ROSTER_TIER_ORDER.size()):
		var lower: Array = buckets[ROSTER_TIER_ORDER[i - 1]]
		var upper: Array = buckets[ROSTER_TIER_ORDER[i]]
		if lower.is_empty() or upper.is_empty():
			continue
		var step: float = float(upper.min()) - float(lower.max())
		if step < margin:
			failures.append("%s: the %s tier beat the %s tier by %.1f %s, which is not the roster's ordering (wanted %.1f)" % [
				quantity, ROSTER_TIER_ORDER[i], ROSTER_TIER_ORDER[i - 1], step, unit, margin])

	return failures

## One clash between two named weapons, from a standing start.
##
## Modelled on `_clash`, which it cannot reuse: that one is written around
## CLASH_SEPARATION, which is set for two pickaxes and leaves two daggers
## 40 px short of ever touching. Walked together rather than sent, for the
## reason `_clash` gives -- a contest can only be measured once there is a
## contact, and two heads sent at each other arrive faster than the contact
## catches and are seated by `WeaponHead`'s pair correction instead.
##
## Reports where the two heads met relative to the midline between the bodies,
## how far apart they ended up, and how much of its own commanded reach each
## side surrendered.
func _roster_clash(left: RigidBody2D, right: RigidBody2D, centre: Vector2, left_stats: WeaponStatsType, right_stats: WeaponStatsType) -> Dictionary:
	left.set_weapon_stats(left_stats)
	right.set_weapon_stats(right_stats)
	await _await_ticks(ROSTER_SWAP_TICKS)

	var half: Vector2 = Vector2.RIGHT * ROSTER_CLASH_SEPARATION * 0.5
	left.teleport_to(centre - half)
	right.teleport_to(centre + half)
	await _close_heads(left, right, CLASH_APPROACH_TICKS)
	await _await_ticks(ROSTER_CLASH_HOLD_TICKS)

	var left_head: Vector2 = left.weapon_head_position()
	var right_head: Vector2 = right.weapon_head_position()
	var meeting: float = (left_head.x + right_head.x) * 0.5
	var midline: float = (left.global_position.x + right.global_position.x) * 0.5
	return {
		"offset": meeting - midline,
		"gap": (right_head - left_head).length(),
		# How close these two particular heads can get before they are
		# touching: a head is a cluster of circles fitted to drawn art
		# (ADR-0010), so this is each head's own furthest circle rather than
		# one radius shared by every weapon.
		"contact": _head_extent(left) + _head_extent(right),
		"left_give": left_stats.max_reach - _reach_of(left),
		"right_give": right_stats.max_reach - _reach_of(right),
	}

## Did these two heads actually meet? A clash nobody turned up to would
## otherwise report a dead heat and pass.
func _clash_met_failures(label: String, clash: Dictionary) -> Array[String]:
	var reachable: float = float(clash["contact"]) + CLASH_CONTACT_SLACK
	if float(clash["gap"]) > reachable:
		return ["%s: the heads never met, ending %.1f px apart when they touch at %.1f px" % [
			label, clash["gap"], reachable]]
	return []

## The heavy weapon's side of a roster clash: it surrendered less of its own
## commanded reach than the light one did, and the meeting point moved onto
## the light weapon's side of the midline by comparison with the like-for-like
## control.
func _heavy_won_failures(label: String, heavy_give: float, light_give: float, ground_won: float) -> Array[String]:
	var failures: Array[String] = []
	if light_give - heavy_give < MIN_GIVE_MARGIN:
		failures.append("%s: the heavy weapon gave up %.1f px of its own reach against the light one's %.1f px, so nothing gave way (wanted %.1f px between them)" % [
			label, heavy_give, light_give, MIN_GIVE_MARGIN])
	if ground_won < MIN_GROUND_WON:
		failures.append("%s: the clash moved only %.1f px onto the light weapon's side of the midline (wanted %.1f px)" % [
			label, ground_won, MIN_GROUND_WON])
	return failures

## How far the head a player is holding reaches past the point it is held by,
## **in any direction**: its furthest circle, measured as offset-plus-radius
## without regard to which way the offset points. Read off the built rig
## rather than the resource, so it is the head that is really there.
##
## This is a **loose upper bound on forward reach, and both of its callers use
## it as one.** They want how far the head gets along the haft, away from the
## player -- the direction a head meets another head in, and the direction a
## head overtakes a body in -- and on the roster's blades, which lie back
## across their anchor rather than out in front of it, the two are nothing
## like each other. Omnidirectional against true forward reach: pickaxe 12.32
## vs 9.00, sword **22.95 vs 9.00**, axe **16.37 vs 11.00**, dagger 6.00 vs
## 6.00, staff 5.00 vs 5.00.
##
## Kept omnidirectional deliberately, because both callers are loose in the
## safe direction and tightening them would move measured physics in a
## scenario with very little room. What that costs, written down so nobody has
## to rediscover it:
##
##   * `_roster_clash()`'s `"contact"`, which feeds `_clash_met_failures()`.
##     The axe against the dagger is allowed 16.37 + 6.00 = 22.4 px between
##     head anchors (30.4 px once CLASH_CONTACT_SLACK is added) when the two
##     heads physically touch at 11.00 + 6.00 = 17.0 px. The "did the heads
##     actually turn up?" guard is some 13 px looser than it reads. It only
##     ever passes a clash it should have failed -- never the reverse -- and
##     the clash's real assertions are about who gave way, which this does not
##     touch.
##   * `_charge_strike()`'s `contact`, which is
##     PLAYER_RADIUS + this + PLANT_CLEARANCE: 50.95 px for the sword against
##     roughly 33 px of real contact. The `touched` latch therefore fires
##     early, and the anti-sag levelling behind `if gap > contact * 3.0` stops
##     about 54 px early for the sword and the axe. Those are the measured
##     arrival speeds in `weapon_damage_matches_roster`, and the axe already
##     lands at 2190 px/s inside a 2200 +/- 50 band -- 10 px/s of margin. A
##     tighter extent here moves that number, so anyone who swaps this for
##     `_head_forward_extent()` has to re-measure that scenario's speeds and
##     re-tune FULL_STRIKE_COMMAND, not just watch the suite go green once.
##
## `_head_forward_extent()` and `_head_rear_extent()`, at the end of this
## file, are the directional answers. New work should prefer them.
func _head_extent(player: RigidBody2D) -> float:
	var extent: float = 0.0
	for circle: Dictionary in player.weapon_head_circles():
		var offset: Vector2 = circle["offset"]
		extent = maxf(extent, offset.length() + float(circle["radius"]))
	return extent

## A head held out and carried into a victim at a commanded speed, and what it
## did on arrival.
##
## The strike the roster's damage numbers are defined at is a full-speed one,
## and a swing cannot be asked for a speed -- it arrives at whatever its own
## weapon produces, which differs across the roster by more than the damage
## does. So the weapon is held still and the body brings it in, which is the
## same commanded speed whatever is being held.
##
## Both ends are then read from outside the player: damage off the victim's
## own accumulated total, and speed off how far the head visibly moved in the
## last whole tick before anything stopped it.
func _charge_strike(attacker: RigidBody2D, victim: RigidBody2D) -> Dictionary:
	var centre: Vector2 = DEEP_PARK_POSITION
	await _wind_up(attacker, centre, 0.0)
	await _await_ticks(ROSTER_SETTLE_TICKS)
	# Put back where the run-up is measured from: the wind-up leaves the
	# attacker wherever gravity took it, and the victim is braced and so is
	# not falling with it.
	attacker.teleport_to(centre)
	victim.teleport_to(centre + Vector2.RIGHT * FULL_STRIKE_RUN_UP)

	var before_damage: float = victim.damage
	var before_deaths: int = victim.deaths
	var previous_head: Vector2 = attacker.weapon_head_position()
	var last_speed: float = 0.0
	var speed_at_hit: float = 0.0
	var dealt: float = 0.0
	var landed: bool = false
	var closest: float = INF

	var contact: float = PLAYER_RADIUS + _head_extent(attacker) + PLANT_CLEARANCE
	var touched: bool = false
	for _t in FULL_STRIKE_TICKS:
		# Commanded flat, so the charge arrives at the height it started at
		# rather than on the way down.
		attacker.linear_velocity = Vector2.RIGHT * FULL_STRIKE_COMMAND
		await physics_frame
		var head: Vector2 = attacker.weapon_head_position()
		var speed: float = (head - previous_head).length() / _tick_seconds()
		previous_head = head
		var gap: float = (head - victim.global_position).length()
		closest = minf(closest, gap)
		if gap <= contact:
			touched = true
		elif not touched:
			last_speed = speed
			# Kept level with the head while the charge is still well out.
			# The charge falls a little as it runs -- gravity is integrated
			# inside each step, after the tick's velocity is commanded -- and
			# a head arriving even 20 px high strikes off-centre, where only
			# the part of its motion heading into the victim counts
			# (`Player._on_head_hit`). That would score the same swing
			# differently for every weapon, which would be the rig deciding
			# the answer rather than the weapon.
			if gap > contact * 3.0:
				victim.teleport_to(Vector2(victim.global_position.x, head.y))
		if victim.damage != before_damage or victim.deaths != before_deaths:
			# The tick the damage shows up on is a tick the head has already
			# been stopped part-way through, so the speed it arrived with is
			# the last whole step it took while still clear of the victim.
			speed_at_hit = last_speed
			dealt = victim.damage - before_damage if victim.deaths == before_deaths \
				else DEATH_DAMAGE - before_damage
			landed = true
			break

	return {
		"damage": dealt,
		"speed": speed_at_hit,
		"landed": landed,
		"closest": closest,
	}

# --- The roster's heads, driven through the head-physics guarantees ---------
#
# Every scenario above that guards head behaviour -- `head_plants_terrain`,
# `head_plants_player`, `haft_is_non_colliding`, `heads_do_not_tunnel_head` --
# drives whatever weapon `Player.tscn` ships with, which is the pickaxe. Four
# of the roster's five heads had never been put through a plant, a haft
# pass-through or a tunnelling charge at all.
#
# The gap has a measured floor under it, recorded in `resources/pickaxe.tres`:
# a cut of the crescent refilled with 1.0-2.3 px circles broke exactly three of
# those scenarios -- the head would not come to rest on a body, it sank 5.4 px
# through the bar its own haft passes through, and 1 charge in 12 drove a head
# clean through another -- because circles that small cross a contact inside a
# single physics step. The pickaxe was redrawn back above that floor. The
# dagger (smallest circle 1.44 px) and the sword (tip circle 1.93 px) were then
# authored into it and never run against it.
#
# The two scenarios below run **every** weapon in WEAPON_RESOURCE_PATHS through
# the guarantees that floor is defined by, so a head fitted under it goes red
# on its own account rather than on the pickaxe's. Neither names a weapon:
# both read the head's geometry off the live rig and size their own fixture
# from it, so a weapon refitted tomorrow is measured as it is tomorrow.

## Clearance kept on each side when a fixture -- a bystander, a bar -- is put
## into the stretch of a weapon that is bare haft, and so also the narrowest
## such stretch worth using. A band under twice this is not somewhere a
## fixture can be placed without where it was placed deciding the answer.
const HAFT_BAND_MARGIN: float = 3.0
## The sweep across a bystander, taken in steps instead of in one command.
## A hard sweep drags the head in along its own haft (see `_rehearse_swing`),
## and on the roster's short weapons the bare-haft band is only a few pixels
## wider than the bystander -- a head dragged inward would touch them, and the
## shove it left would be read as the haft's. Stepped, the weapon is at full
## reach the whole way round and the only thing crossing the bystander is haft.
const HAFT_SWEEP_STEPS: int = 6
const HAFT_SWEEP_STEP_TICKS: int = 12
## Clear air left between two heads at the start of a charge, on top of the
## two full reaches. CHARGE_SEPARATION cannot be reused across the roster: it
## is sized for the pickaxe and says so ("2 x 140 px of reach inside 340 px"),
## and the staff reaches 200, so two of them would start the trial already
## touching -- which is a clash being measured, not a charge. Each weapon gets
## its two reaches plus this instead.
const ROSTER_CHARGE_CLEARANCE: float = 60.0
## How far out a weapon is left while it turns, as a fraction of its own reach
## range. `_wind_up()`'s 0.05, written down here because the haft sweep needs
## the same trick and does not want `_wind_up()`'s teleport with it.
const WOUND_IN_MAGNITUDE: float = 0.05

## US-4/7/12/14/20, the head half: **no weapon on the roster puts its head
## through another head.**
##
## `heads_do_not_tunnel_head` above makes this claim for the pickaxe and has
## always been read as making it for the game. It is not: it runs the default
## `Player.tscn` weapon, and the four heads added since are between a third
## and a fifth of the pickaxe's smallest circle. This runs the same twelve
## charges -- four approach directions so gravity cannot hide it, three closing
## speeds up to 3600 px/s between them -- once per weapon, both players holding
## the same weapon, sixty charges in all.
##
## Three things it does that the original cannot, all of them forced by heads
## that are no longer one round nub.
##
## Contact is measured **surface to surface between the two clusters** rather
## than as a fixed 2 x HEAD_RADIUS around the anchor. A single radius is
## isotropic and a fitted cluster is not: two staffs whose anchors pass 6 px
## apart have missed each other entirely, two axes whose anchors pass 20 px
## apart across the crescents have not, and the same 16 px is wrong for both.
## A breach is then the plain thing the scenario is named for -- the blocker's
## head ended up behind the attacker's, down the line they charged, having
## never been in contact with it -- rather than a distance test tuned per
## weapon.
##
## The charge starts from each weapon's own separation, because
## CHARGE_SEPARATION is sized for the pickaxe's 140 px and the staff reaches
## 200. And each weapon gets a fresh pair of players, so an elimination under
## one weapon cannot freeze a body and quietly void the four sweeps after it.
func _scenario_roster_heads_do_not_tunnel_head() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var centre: Vector2 = DEEP_PARK_POSITION

	for path: String in WEAPON_RESOURCE_PATHS:
		var weapon: String = path.get_file().get_basename()
		var stats: WeaponStatsType = load(path)
		if stats == null:
			failures.append("%s: could not be loaded" % path)
			continue

		# A fresh pair per weapon. Damage is cleared per charge below, but an
		# elimination inside a single charge still freezes a body for good,
		# and a frozen body would carry into every weapon after this one.
		var attacker: RigidBody2D = _spawn_player(stage, centre)
		var blocker: RigidBody2D = _spawn_player(stage, centre)
		attacker.set_weapon_stats(stats)
		blocker.set_weapon_stats(stats)
		await _await_ticks(ROSTER_SWAP_TICKS)

		var separation: float = maxf(CHARGE_SEPARATION,
			2.0 * stats.max_reach + ROSTER_CHARGE_CLEARANCE)
		failures.append_array(await _charge_sweep(weapon, attacker, blocker, centre, separation))

		attacker.queue_free()
		blocker.queue_free()
		await _await_ticks(2)

	await _teardown(stage)
	return failures

## One weapon's worth of `heads_do_not_tunnel_head`: both players hold it,
## hold their heads out at each other from a distance neither can reach
## across, and are thrown together over four directions and three speeds.
##
## Written against the pair passed in rather than against the scene, so the
## caller owns how long a pair lives and what weapon is on it.
func _charge_sweep(label: String, attacker: RigidBody2D, blocker: RigidBody2D, centre: Vector2, separation: float) -> Array[String]:
	var failures: Array[String] = []
	var trials: int = 0
	var met: int = 0
	var breaches: int = 0
	## Charges cut short by an elimination. Such a charge measured two heads
	## for part of a step and then a frozen body with its head off the
	## collision layer, so it is void rather than passing -- counted, reported,
	## and kept out of `met` and `breaches` entirely.
	var voided: int = 0

	for degrees: float in CHARGE_ANGLES:
		for speed: float in CHARGE_SPEEDS:
			trials += 1
			var axis: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(degrees))
			var half: Vector2 = axis * separation * 0.5
			attacker.teleport_to(centre - half)
			blocker.teleport_to(centre + half)
			attacker.set_input_vector(axis)
			blocker.set_input_vector(-axis)
			# Cleared for the reason the disclosure on
			# `_scenario_heads_do_not_tunnel_head` gives: one charge's wear
			# must not decide what the next one is allowed to test. Same
			# shortcut and the same caveat -- this goes round the player's own
			# damage path, so `_update_damage_visual()` does not re-run and
			# the body keeps whatever fill it had reddened to. Nothing here
			# reads the fill.
			attacker.damage = 0.0
			blocker.damage = 0.0
			await _await_ticks(SETTLE_TICKS)

			var deaths: int = attacker.deaths + blocker.deaths
			var previous_a: Array[Dictionary] = _head_circles_world(attacker)
			var previous_b: Array[Dictionary] = _head_circles_world(blocker)
			var previous_rel: Vector2 = blocker.weapon_head_position() - attacker.weapon_head_position()
			# Surface to surface between the two clusters: zero is touching,
			# negative is overlapping. Not a distance between anchors, which
			# is a different number for every weapon and none of them the one
			# that decides whether two heads met.
			var closest: float = _head_surface_gap(previous_a, previous_b)
			var previous_along: float = previous_rel.dot(axis)
			var touched: bool = closest <= 0.0
			var went_through: bool = false
			## Set when the along-axis ordering comes back after a crossing,
			## which is the head-crossing correction having done its job.
			var restored: bool = false
			## Surface gap on the step a crossing happened. A crossing on its
			## own is not a breach: two heads can cross the line they charged
			## down while comfortably clear of each other, having simply
			## missed -- which is what four approach directions are for. The
			## breach is a crossing where the two clusters were *overlapping*
			## on the step that crossed -- surfaces interpenetrating, so the
			## step should have resolved as a collision and instead resolved
			## as one head being on the far side.
			##
			## Nothing looser works. CLASH_CONTACT_SLACK (8 px) was tried and
			## is the wrong instrument: it is the slack for "did these two
			## meet", and two heads crossing 8 px apart have plainly not met.
			## The head-crossing correction agrees -- it rejects such a pair
			## outright, because the sum of the two clusters' radii is less
			## than their anchors' closest approach, which is not a bug but
			## the geometry saying no circle could have touched. A breach has
			## to be a crossing the physics owed us and did not deliver, and
			## only overlap says that without argument.
			var crossed_gap: float = INF
			var cut_short: bool = false
			var crossed_from: Vector2 = Vector2.ZERO
			var crossed_to: Vector2 = Vector2.ZERO
			for _t in CHARGE_TICKS:
				attacker.linear_velocity = axis * speed
				blocker.linear_velocity = -axis * speed
				await physics_frame
				# An elimination freezes a player and drops its head's
				# collision layer, so from that tick on nothing measured here
				# means "two heads closing" any more.
				if attacker.deaths + blocker.deaths != deaths:
					cut_short = true
					break
				var current_a: Array[Dictionary] = _head_circles_world(attacker)
				var current_b: Array[Dictionary] = _head_circles_world(blocker)
				var relative: Vector2 = blocker.weapon_head_position() - attacker.weapon_head_position()
				var gap: float = _head_surface_gap(current_a, current_b)
				closest = minf(closest, gap)
				# A breach is the blocker's head ending up **behind** the
				# attacker's, along the line they charged down, when no tick
				# up to that moment ever saw the two of them so much as
				# touch. Read in that order, and with `touched` carrying
				# ticks that have already happened: the tick after a head has
				# gone through shows the two clusters overlapping, so folding
				# this tick's contact in first would let every real breach
				# hide behind the overlap it had just created.
				#
				# Deliberately not asked per circle pair. Two clusters leant
				# against each other have plenty of pairs that are not
				# touching, and any one of them jittering past its own contact
				# reads as a crossing -- that version called two pickaxes
				# "through" on a 1 px step while the heads were solidly in
				# contact, which is the pre-existing scenario's own weapon
				# passing its own charge. Whether the heads met at all is a
				# question about the heads, not about a pair of circles.
				var along: float = relative.dot(axis)
				if not went_through and not touched and along < 0.0 and previous_along > 0.0:
					went_through = true
					crossed_gap = minf(gap, _head_surface_gap(previous_a, previous_b))
					crossed_from = previous_rel
					crossed_to = relative
				# `_undo_any_head_crossing` corrects a crossing on the step
				# *after* the one that made it -- it works from the motion
				# that actually happened, which it can only read once the
				# step is over. So a head found on the far side is not yet a
				# breach: it is either a breach or a crossing about to be
				# undone, and the two are told apart by whether the ordering
				# comes back.
				if went_through and along > 0.0:
					restored = true
				if gap <= 0.0:
					touched = true
				previous_a = current_a
				previous_b = current_b
				previous_rel = relative
				previous_along = along

			if cut_short:
				voided += 1
				print("      %s %3.0f deg at %.0f px/s each: VOID, an elimination cut the charge short" % [
					label, degrees, speed])
				# Revived rather than replaced. `start_round` is the one path
				# back into play (see `leave_round`), and with `keeps_weapon`
				# it restores `alive`, the collision layers and the transform
				# while leaving the weapon this sweep is measuring on the
				# body. Spawning a fresh pair instead would mean re-running
				# the weapon swap and its settle, sixty times over, for a
				# state this already reaches in two ticks.
				attacker.start_round(centre, true)
				blocker.start_round(centre, true)
				await _await_ticks(SETTLE_TICKS)
				continue

			if went_through and restored:
				print("      %s %3.0f deg at %.0f px/s each: crossed, then the correction put it back" % [
					label, degrees, speed])
				went_through = false
			if went_through and crossed_gap >= 0.0:
				print("      %s %3.0f deg at %.0f px/s each: crossed %.1f px apart -- a miss, not a breach" % [
					label, degrees, speed, crossed_gap])
				went_through = false

			if closest <= CLASH_CONTACT_SLACK:
				met += 1
			print("      %s %3.0f deg at %.0f px/s each: heads closed to %6.1f px of each other%s" % [
				label, degrees, speed, closest, "  THROUGH" if went_through else ""])
			if went_through:
				breaches += 1
				if failures.size() < MAX_FAILURES_PER_SCENARIO:
					failures.append(
						"%s, %.0f deg approach at %.0f px/s each: one step took the heads from %s apart to %s apart -- through each other and out the far side -- without the two of them ever once being in contact" % [
							label, degrees, speed, crossed_from, crossed_to])

	var measured: int = trials - voided
	if voided > 0:
		print("      %s: %d of %d charges were void (elimination mid-charge); %d measured" % [
			label, voided, trials, measured])
	# A sweep that voided most of its charges has not made the claim this
	# scenario is named for, whatever the surviving charges said.
	if measured < trials / 2:
		failures.append("%s: only %d of %d charges ran to completion; the rest were cut short by an elimination, so this weapon was not really swept" % [
			label, measured, trials])
	elif met < measured / 2:
		failures.append("%s: only %d of %d completed charges brought the heads together at all" % [
			label, met, measured])
	if breaches > 0:
		failures.append("%s: %d of %d completed charges put a head through another head" % [
			label, breaches, measured])

	return failures

## US-4/7/12/14/20, the haft half: **every weapon's haft passes through what
## its own head is stopped by.**
##
## `haft_is_non_colliding` above makes this claim for the pickaxe only, and it
## is the claim that keeps anybody from shoving a player off a ledge by slowly
## extending a weapon sideways -- so it has to hold for all five. Per weapon,
## the two halves the original uses, both sized from that weapon's own head
## rather than from the pickaxe's:
##
##   * A bystander standing in the weapon's **bare-haft band**: far enough out
##     that the two bodies never touch, near enough in that the head passes
##     well beyond them. The weapon sweeps over them at full reach and they
##     are not moved.
##   * A bar slid into the same band, crossing the haft and touching nothing
##     else. The weapon holds full reach straight through it, and on release
##     the head cannot come back down past it.
##
## The bar half runs for every weapon. The bystander half runs only where the
## weapon's own geometry leaves room for a whole player body between the two
## bodies, and says so out loud where it does not -- see `_roster_haft_trial`.
func _scenario_roster_hafts_are_non_colliding() -> Array[String]:
	var failures: Array[String] = []
	var bystander_halves: int = 0

	for path: String in WEAPON_RESOURCE_PATHS:
		var weapon: String = path.get_file().get_basename()
		var stats: WeaponStatsType = load(path)
		if stats == null:
			failures.append("%s: could not be loaded" % path)
			continue
		var trial: Dictionary = await _roster_haft_trial(weapon, stats)
		failures.append_array(trial["failures"])
		if bool(trial["bystander"]):
			bystander_halves += 1

	# The bystander half is the half that says "through a **player**", and a
	# roster where no weapon could run it would have passed everything above
	# on bars alone.
	if bystander_halves == 0:
		failures.append("not one weapon on the roster left room for a bystander in its own bare-haft band, so nothing here was tested against a player at all")

	return failures

## One weapon's worth of `haft_is_non_colliding`, on its own stage.
##
## Everything the fixture needs is measured off the built rig: how far the
## head reaches forward past its anchor, how far it reaches back down the haft
## toward the player, and so which stretch of the weapon is bare haft. That
## stretch is the **band**: from the far side of a bystander standing clear of
## the player's own body, out to where the head begins.
##
## For two of the roster that band will not take a whole player. The sword's
## blade lies 22.95 px back across its anchor on a 90 px weapon, so at full
## reach its head occupies everything from 67 px out to 99 px, and a body of
## radius 24 would have to stand with its centre inside 43 px -- closer than
## two players can stand. That is geometry, not a fixture that needs more
## thought: there is no reach at which the sword has both a bare haft and room
## for somebody on it. The bar, which is thin, fits every weapon's band, so
## the haft claim is still made for the sword -- against terrain rather than
## against a player -- and the shortfall is printed rather than skipped.
func _roster_haft_trial(weapon: String, stats: WeaponStatsType) -> Dictionary:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()
	var player: RigidBody2D = _spawn_player(stage, Vector2(0, 200))
	player.set_weapon_stats(stats)
	await _await_ticks(ROSTER_SWAP_TICKS)

	# The head's own reach, in both directions along the haft, off the live
	# rig. `extent` is the omnidirectional one and is what a bystander has to
	# be kept clear of, since the head turns past them side-on as well as
	# end-on.
	var forward: float = _head_forward_extent(player)
	var rear: float = _head_rear_extent(player)
	var extent: float = _head_extent(player)
	var band_inner: float = 2.0 * PLAYER_RADIUS + PLANT_CLEARANCE
	var band_outer: float = stats.max_reach - extent - PLAYER_RADIUS
	var ran_bystander: bool = band_outer - band_inner >= 2.0 * HAFT_BAND_MARGIN
	print("      %s: head reaches %.2f px forward and %.2f px back on %.0f px of weapon; bare haft runs %.1f to %.1f px" % [
		weapon, forward, rear, stats.max_reach, band_inner, band_outer])

	if ran_bystander:
		var offset: float = BYSTANDER_OFFSET
		if offset < band_inner + HAFT_BAND_MARGIN or offset > band_outer - HAFT_BAND_MARGIN:
			offset = (band_inner + band_outer) * 0.5
		failures.append_array(await _haft_bystander_half(weapon, stage, player, stats, offset, extent, band_inner))
	else:
		print("      %s: no bystander half -- its head leaves %.1f px of bare haft, and two players cannot stand closer than %.1f px" % [
			weapon, band_outer, band_inner])

	failures.append_array(await _haft_bar_half(weapon, stage, player, stats, rear))

	await _teardown(stage)
	return {"failures": failures, "bystander": ran_bystander}

## The haft against a player: a bystander is stood in the weapon's bare-haft
## band and the weapon is swept over them at full reach, from straight up
## round to horizontal. The head travels round outside them the whole way, so
## the only thing that ever crosses them is haft, and they are not moved.
##
## Five things have to be true together, because "they were not shoved" on its
## own is what a weapon that never reached them would also report: the weapon
## really was at full reach, the haft really did lie across the bystander, the
## two bodies never touched, no circle of the head ever got inside the
## bystander's body, and they did not move.
##
## The swinging player is braced and the bystander is not, which is the whole
## point of bracing exactly one of them: the band between a bystander's body
## and the head sweeping past it is a few pixels wide on the short weapons,
## and an unbraced player is thrown far enough by its own swing to close it.
## Unbraced, the pickaxe ends the sweep 39 px from where it started and takes
## its head within half a pixel of the bystander -- which would make the head,
## not the haft, the thing that had been near them. The bystander stays free,
## because being free is what makes "it did not move" worth measuring.
func _haft_bystander_half(weapon: String, stage: Node2D, player: RigidBody2D, stats: WeaponStatsType, offset: float, extent: float, band_inner: float) -> Array[String]:
	var failures: Array[String] = []
	var bystander: RigidBody2D = _spawn_player(stage, Vector2(offset, 200))
	await _await_ticks(LANDING_TICKS)
	_brace(player)

	# Turned up wound in before it is let out, the way `_wind_up()` does it,
	# and for the same reason: a weapon commanded straight to full reach from
	# rest extends along the angle it has not finished leaving. Rest points
	# +X, which is at the bystander, and the two quickest weapons on the
	# roster extend faster than they turn -- the staff and the dagger both put
	# a head circle flat against the bystander's body on the way out, 24.0 px
	# from their centre, before the sweep being measured had begun. Wound in,
	# the head cannot reach anybody while it comes round.
	player.set_input_vector(Vector2.UP * WOUND_IN_MAGNITUDE)
	await _await_ticks(RETRACT_TICKS)
	player.set_input_vector(Vector2.UP)
	await _await_ticks(EXTEND_TICKS + SETTLE_TICKS)
	var bystander_start: Vector2 = bystander.global_position

	# Stepped from straight up round to horizontal, so the weapon is at full
	# reach throughout rather than being dragged in by its own swing.
	# Watched every tick, not just at the end. `head_clearance` is the gap
	# from the bystander's body to the nearest surface of the head -- circle
	# by circle, turned to face along the haft the way the rig turns it --
	# rather than to the anchor, because the anchor is not what collides. The
	# omnidirectional `extent` that sized the band is a loose bound on this
	# (see `_head_extent()`) and is fine for placing a fixture; it is far too
	# blunt to decide whether a head touched somebody.
	var head_clearance: float = INF
	for i in HAFT_SWEEP_STEPS + 1:
		var degrees: float = -90.0 + 90.0 * float(i) / float(HAFT_SWEEP_STEPS)
		player.set_input_vector(Vector2.RIGHT.rotated(deg_to_rad(degrees)))
		for _t in HAFT_SWEEP_STEP_TICKS:
			await physics_frame
			head_clearance = minf(head_clearance,
				_head_circle_clearance(player, bystander.global_position))
	await _await_ticks(SETTLE_TICKS)
	head_clearance = minf(head_clearance,
		_head_circle_clearance(player, bystander.global_position))

	var swept_reach: float = _reach_of(player)
	if absf(swept_reach - stats.max_reach) > REACH_TOLERANCE:
		failures.append("%s: sweeping across the bystander left the weapon at %.1f px instead of its own full reach %.1f px" % [
			weapon, swept_reach, stats.max_reach])
	var body_gap: float = (bystander.global_position - player.global_position).length()
	if body_gap < band_inner:
		failures.append("%s: the two bodies closed to %.1f px, so anything the bystander did was body contact, not the haft" % [
			weapon, body_gap])
	# The haft has to actually lie across them. A swing that finished short of
	# the bystander, or a player shoved so far back by its own swing that the
	# weapon no longer reaches, would report a perfectly still bystander and
	# mean nothing by it.
	var haft_depth: float = PLAYER_RADIUS - _point_segment_distance(
		bystander.global_position, player.global_position, player.weapon_head_position())
	if haft_depth <= 0.0:
		failures.append("%s: the haft ended %.1f px clear of the bystander's body, so it never passed through them at all" % [
			weapon, -haft_depth])
	# And the head has to have stayed outside them throughout -- otherwise a
	# shove would be the head's doing and the haft would be off the hook.
	if head_clearance < PLAYER_RADIUS:
		failures.append("%s: a head circle came within %.1f px of the bystander's centre, inside their own %.1f px body, so this sweep cannot tell the haft from the head" % [
			weapon, head_clearance, PLAYER_RADIUS])
	var shoved: float = (bystander.global_position - bystander_start).length()
	print("      %s: bystander at %.1f px, bodies %.1f px apart, haft through %.1f px of them, head surface no closer than %.1f px, shoved %.2f px" % [
		weapon, offset, body_gap, haft_depth, head_clearance, shoved])
	if shoved > HAFT_SHOVE_TOLERANCE:
		failures.append("%s: the haft shoved the bystander %.1f px; it should pass straight through them" % [
			weapon, shoved])

	# Handed back the way it was received. The bar half needs this player free:
	# what closes when the head is blocked is the player, hauled up its own
	# weapon to the underside of the bar.
	player.freeze = false
	bystander.queue_free()
	await _await_ticks(2)
	return failures

## The haft against terrain, and the head against the same terrain: a bar is
## slid into the gap between the player and its own head, where it crosses the
## haft and touches nothing else. The weapon holds full reach through it, and
## on release the head cannot come back down past it.
##
## The bar goes at the middle of the weapon's bare haft, not at a fixed
## height: at the pickaxe's 70 px it would be buried inside the sword's blade.
## Where the head ends up is read in world coordinates against the bar's own
## top surface, because what closes on release is the player -- hauled up its
## own weapon to the underside of the bar -- rather than the head coming down.
func _haft_bar_half(weapon: String, stage: Node2D, player: RigidBody2D, stats: WeaponStatsType, rear: float) -> Array[String]:
	var failures: Array[String] = []
	player.set_input_vector(Vector2.UP)
	await _await_ticks(SETTLE_TICKS * 2)

	var bar_inner: float = PLAYER_RADIUS + BAR_SIZE.y * 0.5 + HAFT_BAND_MARGIN
	var bar_outer: float = stats.max_reach - rear - BAR_SIZE.y * 0.5 - HAFT_BAND_MARGIN
	if bar_outer <= bar_inner:
		failures.append("%s: its head leaves no stretch of bare haft a bar can be put across at all (%.1f px to %.1f px)" % [
			weapon, bar_inner, bar_outer])
		return failures
	var bar_offset: float = clampf(BAR_OFFSET, bar_inner, bar_outer)
	var bar_centre: Vector2 = player.global_position - Vector2(0, bar_offset)
	_add_bar(stage, bar_centre, BAR_SIZE)
	await _await_ticks(SETTLE_TICKS * 2)

	var through_reach: float = _reach_of(player)
	if absf(through_reach - stats.max_reach) > REACH_TOLERANCE:
		failures.append("%s: the bar disturbed the haft: reach %.1f px instead of its own full reach %.1f px" % [
			weapon, through_reach, stats.max_reach])

	var bar_top: float = bar_centre.y - BAR_SIZE.y * 0.5
	player.set_input_vector(Vector2.ZERO)
	await _await_ticks(SETTLE_TICKS * 2)
	# Measured at the anchor the haft holds the head by, not at the head's
	# outline: every weapon holds its head at a different place along it, and
	# the anchor is the one point all five have in common. Blocked, the head
	# sits on the bar and the anchor stays above its top surface; through, the
	# weapon is most of the way home and the anchor is far below it.
	var sunk: float = player.weapon_head_position().y - bar_top
	var rest_reach: float = _reach_of(player)
	print("      %s: bar at %.1f px, held %.1f px through it, ended %.1f px past its top surface at %.1f px of reach" % [
		weapon, bar_offset, through_reach, sunk, rest_reach])
	if sunk > PLANT_CLEARANCE:
		failures.append("%s: the head came back %.1f px down through the bar its own haft passes through" % [
			weapon, sunk])
	if rest_reach <= player.weapon_min_length + REACH_TOLERANCE:
		failures.append("%s: the weapon returned the whole way to rest, so the bar stopped nothing" % weapon)

	return failures

## How far a head reaches **forward along its own haft**, past the anchor the
## haft holds it by: the furthest any of its circles gets in head-local +X.
##
## This is the direction two heads meet in and the direction a head overtakes
## a body in, so it is what a contact distance is actually made of.
## `_head_extent()` answers a different question -- the furthest circle in any
## direction -- and on the roster's blades, which lie back across their anchor,
## it overstates this by up to 14 px. Read off the built rig, so it is the
## head that is really there.
func _head_forward_extent(player: RigidBody2D) -> float:
	var extent: float = 0.0
	for circle: Dictionary in player.weapon_head_circles():
		var offset: Vector2 = circle["offset"]
		extent = maxf(extent, offset.x + float(circle["radius"]))
	return extent

## How far a head reaches **back down its own haft**, toward the player. The
## roster's blades lie across their anchor rather than out in front of it --
## the sword's reaches 22.95 px back on a 90 px weapon -- so this is what
## decides how much of a weapon's length is bare haft and how much is solid
## head, and therefore where a fixture can be put without the head being what
## it meets.
func _head_rear_extent(player: RigidBody2D) -> float:
	var extent: float = 0.0
	for circle: Dictionary in player.weapon_head_circles():
		var offset: Vector2 = circle["offset"]
		extent = maxf(extent, float(circle["radius"]) - offset.x)
	return extent

## The gap between a world point and the nearest **surface** of the head a
## player is holding: negative once the point is inside one of its circles.
##
## Built from the two things a player will tell anyone -- where the head is
## and what circles it is made of -- plus the one rule the rig turns it by:
## head-local +X points outward along the haft. So the facing is read back out
## of the weapon's own geometry, from the player to the head, rather than off
## any node in the rig, and this stays true through the rig swap ADR-0006
## reserves the right to make.
func _head_circle_clearance(player: RigidBody2D, point: Vector2) -> float:
	var clearance: float = INF
	for circle: Dictionary in _head_circles_world(player):
		var centre: Vector2 = circle["centre"]
		clearance = minf(clearance, centre.distance_to(point) - float(circle["radius"]))
	return clearance

## The head a player is holding, circle by circle, **in world coordinates**.
##
## Built from the two things a player will tell anyone -- where its head is and
## what circles it is made of -- plus the one rule the rig turns the cluster
## by: head-local +X points outward along the haft. So the facing is recovered
## from the weapon's own geometry, player to head, rather than read off a node
## inside the rig, and this survives the rig swap ADR-0006 reserves the right
## to make.
func _head_circles_world(player: RigidBody2D) -> Array[Dictionary]:
	var anchor: Vector2 = player.weapon_head_position()
	var facing: float = (anchor - player.global_position).angle()
	var circles: Array[Dictionary] = []
	for circle: Dictionary in player.weapon_head_circles():
		var offset: Vector2 = circle["offset"]
		circles.append({
			"centre": anchor + offset.rotated(facing),
			"radius": float(circle["radius"]),
		})
	return circles

## The gap between two heads, surface to surface: the closest any circle of
## one gets to any circle of the other. Zero is touching and negative is
## overlapping, for any two heads on the roster, which is what makes "did
## these two meet?" one question rather than fifteen.
func _head_surface_gap(one: Array[Dictionary], other: Array[Dictionary]) -> float:
	var gap: float = INF
	for a: Dictionary in one:
		var a_centre: Vector2 = a["centre"]
		var a_radius: float = a["radius"]
		for b: Dictionary in other:
			var b_centre: Vector2 = b["centre"]
			gap = minf(gap, a_centre.distance_to(b_centre) - a_radius - float(b["radius"]))
	return gap


## Distance from a point to a line segment: how far a bystander's centre is
## from the haft, which is the segment from the player to its head.
func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var length_squared: float = ab.length_squared()
	if length_squared == 0.0:
		return point.distance_to(a)
	var along: float = clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * along)

# --- Stage rotation reachability (issue #17) --------------------------------

## Horizontal speed the probe is launched from a spawn point at. Far above
## anything a swing produces, deliberately: the question is whether the stage
## has an exit at all, not whether a particular hit is strong enough to use it.
const RINGOUT_SHOVE_SPEED: float = 1800.0
## Long enough for a shoved body to cross the widest stage and fall the height
## of the tallest one.
const RINGOUT_SHOVE_TICKS: int = 300

## A stage nobody can be knocked out of is a stage the round can only end on
## damage, and ADR-0008 rotates stages on the premise that the ring-out is the
## sharpest threat in the game. This shoves a body off each of a stage's own
## spawn points, left and right in turn, and requires at least one of those
## shoves to end in the kill zone.
##
## Starting from the declared spawn points rather than from a grid of
## positions is what makes the check mean something: air beside a stage that
## no player can be driven into proves nothing, and an early cut of this
## scenario passed every stage by dropping a body at x = -760, clear of all
## the geometry. Beginning where players actually begin, and moving the way a
## knockback moves them, asks the real question.
##
## It asserts existence, not a count: Bowl is meant to have exactly one narrow
## drain and Islands is meant to be almost all air, and demanding a particular
## amount of open floor would be a balance opinion rather than a correctness
## check. What it catches is the real mistake -- a stage whose walls, floor or
## kill zone were drawn or placed so that nobody can leave it.
func _scenario_every_stage_can_ring_out() -> Array[String]:
	var failures: Array[String] = []

	for path: String in STAGE_PATHS:
		# As in stage_spawns_are_safe: each stage's _teardown() sets the
		# completion flag, so clear it before the next stage runs.
		_scenario_completed = false
		var stage: Node2D = Node2D.new()
		get_root().add_child(stage)
		var instance: Node2D = (load(path) as PackedScene).instantiate()
		stage.add_child(instance)
		var spawns: Array[Vector2] = instance.get_spawn_points()

		var escape: String = ""
		for i in spawns.size():
			for direction: float in [-1.0, 1.0]:
				var player: RigidBody2D = _spawn_player(stage, spawns[i])
				await physics_frame
				player.linear_velocity = Vector2(direction * RINGOUT_SHOVE_SPEED, 0.0)
				var ticks: int = 0
				while ticks < RINGOUT_SHOVE_TICKS and player.alive:
					await physics_frame
					ticks += 1
				var died: bool = not player.alive
				player.queue_free()
				await _await_ticks(BOOST_RESET_TICKS)
				if died:
					escape = "spawn %d shoved %s, out after %d ticks" % [
						i, "left" if direction < 0.0 else "right", ticks]
					break
			if escape != "":
				break

		if escape == "":
			failures.append(
				"%s: no spawn point shoved at %.0f px/s in either direction reached the kill zone in %d ticks" % [
					path, RINGOUT_SHOVE_SPEED, RINGOUT_SHOVE_TICKS])
		else:
			print("      %s: %s" % [path, escape])

		await _teardown(stage)

	return failures

# --- Stage parts (issue #18) -------------------------------------------------

## Parked well clear of the Arena fixture other scenarios build, in clear air,
## so a hazard instance dropped here is never touching any other geometry.
const HAZARD_TEST_POSITION: Vector2 = Vector2(0, -800)
## A hazard kill should be near-instant, not something waited for -- this is
## generous next to the couple of physics ticks a body_entered contact and
## the elimination it triggers actually take.
const HAZARD_TICKS: int = 10

## Issue #18 hazard zone, US-5/US-6: `scenes/parts/Hazard.tscn` reuses
## KillZone.gd verbatim (see that script's docstring for why it is not a
## second script), so this is deliberately the same assertion as
## `ringout_kills_at_full_health` run against the other placement -- a
## hazard sitting inside the playable area instead of beneath it. A player
## at full health who touches it is eliminated by the touch alone, which is
## the whole point of US-6: a player has to learn only one rule about stage
## death, not a different one for each placement.
func _scenario_hazard_zone_kills_at_full_health() -> Array[String]:
	var failures: Array[String] = []
	var hazard_scene: PackedScene = preload("res://scenes/parts/Hazard.tscn")
	var stage: Node2D = _new_stage()
	var hazard: Area2D = hazard_scene.instantiate()
	stage.add_child(hazard)
	hazard.global_position = HAZARD_TEST_POSITION

	var player: RigidBody2D = _spawn_player(stage, HAZARD_TEST_POSITION)
	await physics_frame

	if player.damage > 0.0:
		failures.append("the player started on %.1f damage, so this is not a full-health hazard test" % player.damage)

	var killed: bool = false
	for _i in HAZARD_TICKS:
		await physics_frame
		if player.deaths > 0:
			killed = true
			break

	if not killed:
		failures.append("sat in the hazard for %d ticks without dying" % HAZARD_TICKS)
	else:
		if player.deaths != 1:
			failures.append("one hazard contact counted as %d deaths" % player.deaths)
		if player.damage > 0.0:
			failures.append("a hazard kill at full health left %.1f damage behind" % player.damage)
		if player.alive:
			failures.append("eliminated but still marked alive")

	await _teardown(stage)
	return failures

## Preloaded by path, never referenced by `class_name` (CLAUDE.md): the
## global class cache lives in the gitignored `.godot/` and only an editor
## run builds it, so a fresh clone cannot resolve the name.
const MovingPlatformScene: PackedScene = preload("res://scenes/parts/MovingPlatform.tscn")

## Slack allowed between a player's horizontal displacement and the
## platform's over one patrol leg (moving_platform_carries_player). Loose
## next to a full leg's few-hundred-pixel travel, but far tighter than the
## gap a player left behind entirely would show.
const MOVING_PLATFORM_CARRY_TOLERANCE: float = 20.0

## US-2 / issue #18: a player resting on a moving platform is carried along
## with it, rather than sliding out from under it. Asserting only that the
## platform moved would pass even with the player left completely behind --
## nothing else here makes the player move on its own -- so this measures
## the player's own horizontal displacement across one full patrol leg and
## compares it directly against the platform's displacement over the same
## ticks.
##
## The platform is authored with `starts_moving = false` and only started
## with `start()` once the player has already landed and settled on it.
## Spawning a player onto a platform already mid-patrol would have it miss
## the moving target on the way down -- a hazard of dropping a player from
## above a moving target, not something this scenario is about.
func _scenario_moving_platform_carries_player() -> Array[String]:
	var failures: Array[String] = []
	var stage := Node2D.new()
	get_root().add_child(stage)

	var platform: AnimatableBody2D = MovingPlatformScene.instantiate() as AnimatableBody2D
	platform.starts_moving = false
	# Positioned before add_child(): _ready() reads global_position once, at
	# the moment the node enters the tree, to fix the patrol's near end.
	# Setting it any later would fix the patrol to wherever the node
	# happened to be instantiated (the origin) instead.
	platform.position = Vector2(0, 300)
	stage.add_child(platform)

	# Short weapon, straight down, same setup as head_plants_terrain: land
	# and plant on the platform's surface rather than drift toward its edge.
	var player: RigidBody2D = _spawn_player(stage, Vector2(0, 100))
	player.set_input_vector(Vector2.DOWN * 0.05)
	await _await_ticks(LANDING_TICKS)

	if absf(player.linear_velocity.y) > SETTLED_SPEED:
		failures.append("player never settled on the stationary platform: vertical speed %.1f px/s" % player.linear_velocity.y)

	platform.start()
	await physics_frame
	var player_x0: float = player.global_position.x
	var platform_x0: float = platform.global_position.x

	var leg_ticks: int = int(round(platform.one_way_sec * Engine.physics_ticks_per_second))
	await _await_ticks(leg_ticks)

	var player_dx: float = player.global_position.x - player_x0
	var platform_dx: float = platform.global_position.x - platform_x0
	print("      platform moved %.1f px, player moved %.1f px over one patrol leg" % [platform_dx, player_dx])
	if absf(player_dx - platform_dx) > MOVING_PLATFORM_CARRY_TOLERANCE:
		failures.append(
			"player displacement %.1f px did not track platform displacement %.1f px over one patrol leg (tolerance %.1f px)" % [
				player_dx, platform_dx, MOVING_PLATFORM_CARRY_TOLERANCE])

	await _teardown(stage)
	return failures

## US-7 / issue #18: a weapon head plants on a moving platform exactly as it
## does on static terrain -- `head_plants_terrain` is the prior art, and the
## assertion shape below is copied from it unchanged. The platform is
## genuinely translating throughout this scenario, not merely standing in
## for the arena floor with a different node type: `travel` and
## `one_way_sec` are tuned small enough that the platform's footprint stays
## under the player for the whole test, since carrying a player across a
## full patrol leg is already covered by moving_platform_carries_player.
##
## The platform's top surface is placed at GROUND_TOP, the same height
## head_plants_terrain stands its player on, so every constant in the copied
## assertions -- GROUND_TOP, PLAYER_RADIUS, HEAD_RADIUS, PLANT_CLEARANCE --
## reads exactly as it does there.
func _scenario_head_plants_moving_platform() -> Array[String]:
	var failures: Array[String] = []
	var stage := Node2D.new()
	get_root().add_child(stage)

	var platform: AnimatableBody2D = MovingPlatformScene.instantiate() as AnimatableBody2D
	platform.travel = Vector2(60, 0)
	platform.one_way_sec = 3.0
	platform.starts_moving = true
	# Positioned before add_child(), for the same reason as in
	# moving_platform_carries_player: _ready() fixes the patrol's near end
	# to global_position at the moment the node enters the tree.
	platform.position = Vector2(0, GROUND_TOP + platform.size.y / 2.0)
	stage.add_child(platform)

	var player: RigidBody2D = _spawn_player(stage, Vector2(0, 100))

	# Short weapon, straight down: land on the head.
	player.set_input_vector(Vector2.DOWN * 0.05)
	await _await_ticks(LANDING_TICKS)

	var planted_y: float = player.global_position.y
	var head_y: float = player.weapon_head_position().y
	if absf(player.linear_velocity.y) > SETTLED_SPEED:
		failures.append("player never settled on its head: vertical speed %.1f px/s" % player.linear_velocity.y)
	if planted_y + PLAYER_RADIUS > GROUND_TOP - PLANT_CLEARANCE:
		failures.append("player body reached the platform (y %.1f); it should be standing on the head, not on itself" % planted_y)
	if head_y + HEAD_RADIUS > GROUND_TOP + PLANT_CLEARANCE:
		failures.append("head sank %.1f px into the platform; it should be planted on top of it" % (
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

# --- Crumbling ledge (issue #18) --------------------------------------------

## Preloaded by path, not referenced by `class_name` -- see CLAUDE.md's
## `class_name` rule.
const CrumblingLedgeScene: PackedScene = preload("res://scenes/parts/CrumblingLedge.tscn")

## Independent literals matching the resolved defaults (issue #18), not read
## back off the instantiated ledge: reading them back would make this
## scenario pass even if the shipped defaults drifted from what the issue
## asked for.
const LEDGE_WARN_SEC: float = 0.8
const LEDGE_AWAY_SEC: float = 3.0
## Spawn the player already 1 px into the detector band rather than dropped
## from height: contact then happens on (about) the very first physics tick,
## so "ticks since spawn" and "ticks since contact" are close enough that the
## margins below cover the gap, without this scenario having to guess how
## many ticks a longer fall would take to land and settle.
const LEDGE_LANDING_OVERLAP: float = 1.0
## Ticks given to let the small landing overlap above resolve into a settled
## rest before phase 1 starts watching. Short next to LEDGE_WARN_SEC's tick
## count so most of the warning delay is still ahead of it.
const LEDGE_SETTLE_TICKS: int = 10
## Ticks of slack subtracted from the phase 1 watch window and added after
## the warning delay before phase 2 checks for a fall, on both sides of the
## contact-vs-settle tick estimate above.
const LEDGE_MARGIN_TICKS: int = 6
## Ticks given, once past the warning delay, for the ledge to actually fall
## away and gravity to carry the player clearly out of PLANT_CLEARANCE.
const LEDGE_FALL_CONFIRM_TICKS: int = 16

## US-3/US-4: a crumbling ledge holds a player through its full warning
## delay, stops holding once it falls away, and holds again once its away
## delay elapses. All three phases are asserted in one run on purpose --
## checking only the fall would also pass a ledge that never comes back,
## which is exactly the mistake this scenario exists to catch.
##
## The weapon is aimed straight up throughout and never touches the ledge:
## this scenario is about the ledge holding a player's own body (the
## `players`-group contact `CrumblingLedge` detects), not about the plant
## mechanic `head_plants_terrain` already covers. US-7 (a weapon head
## interacting with a crumbling ledge the same way it does with static
## ground) needs no extra code or scenario of its own here -- the ledge's
## `CollisionShape2D` sits on the same default world layer every terrain
## `StaticBody2D` in this game already uses, so a head plants on it exactly
## as it does on Flatlands' ground.
func _scenario_crumbling_ledge_three_phases() -> Array[String]:
	var failures: Array[String] = []
	var stage: Node2D = _new_stage()

	var ledge_position: Vector2 = Vector2(0, -300)
	var ledge_size: Vector2 = Vector2(200, 24)
	var ledge: StaticBody2D = CrumblingLedgeScene.instantiate() as StaticBody2D
	ledge.position = ledge_position
	stage.add_child(ledge)

	var ledge_top: float = ledge_position.y - ledge_size.y / 2.0
	var spawn_pos: Vector2 = Vector2(ledge_position.x, ledge_top - PLAYER_RADIUS + LEDGE_LANDING_OVERLAP)
	var player: RigidBody2D = _spawn_player(stage, spawn_pos)
	# Straight up: keeps the weapon head clear of the ledge for the whole
	# scenario, so only the player's own body is ever in contact with it.
	player.set_input_vector(Vector2.UP)

	var ticks_per_second: float = float(Engine.physics_ticks_per_second)
	var warn_ticks: int = int(round(LEDGE_WARN_SEC * ticks_per_second))
	var away_ticks: int = int(round(LEDGE_AWAY_SEC * ticks_per_second))
	var hold_check_ticks: int = warn_ticks - LEDGE_SETTLE_TICKS - LEDGE_MARGIN_TICKS

	await _await_ticks(LEDGE_SETTLE_TICKS)
	var settled_y: float = player.global_position.y
	if absf(player.linear_velocity.y) > SETTLED_SPEED:
		failures.append("player never settled on the ledge: vertical speed %.1f px/s" % player.linear_velocity.y)
	if settled_y + PLAYER_RADIUS > ledge_top + PLANT_CLEARANCE:
		failures.append("player settled at %.1f, expected resting on the ledge top at %.1f" % [
			settled_y, ledge_top])

	print("      phase 1: holding through the %.2fs warning delay" % LEDGE_WARN_SEC)
	for tick in hold_check_ticks:
		await physics_frame
		if player.global_position.y > settled_y + PLANT_CLEARANCE:
			failures.append(
				"ledge stopped holding %d ticks into its %.2fs warning delay -- gave way too soon" % [
					LEDGE_SETTLE_TICKS + tick, LEDGE_WARN_SEC])
			break

	print("      phase 2: falling away once the warning delay is over")
	var fell: bool = false
	for _i in LEDGE_FALL_CONFIRM_TICKS:
		await physics_frame
		if player.global_position.y > settled_y + PLANT_CLEARANCE:
			fell = true
	if not fell:
		failures.append(
			"ledge still held the player %d ticks after its %.2fs warning delay elapsed -- it never fell away" % [
				LEDGE_FALL_CONFIRM_TICKS, LEDGE_WARN_SEC])

	# Out of the fall cleanly rather than left to plunge toward the arena's
	# own ground and kill zone for the rest of the away delay -- none of
	# that belongs to this scenario, only the two edges either side of it.
	player.leave_round()
	var elapsed_since_contact: int = LEDGE_SETTLE_TICKS + hold_check_ticks + LEDGE_FALL_CONFIRM_TICKS
	# The ledge is not back to SOLID until warn_ticks (SOLID -> WARNING ->
	# AWAY) plus away_ticks (AWAY -> SOLID) have passed since contact, not
	# away_ticks alone -- the AWAY state itself only starts at warn_ticks.
	var remaining_away_ticks: int = warn_ticks + away_ticks - elapsed_since_contact + LEDGE_MARGIN_TICKS
	await _await_ticks(remaining_away_ticks)

	print("      phase 3: holding again after the %.2fs away delay" % LEDGE_AWAY_SEC)
	player.start_round(spawn_pos)
	player.set_input_vector(Vector2.UP)
	await _await_ticks(LEDGE_SETTLE_TICKS)

	var returned_y: float = player.global_position.y
	if absf(player.linear_velocity.y) > SETTLED_SPEED:
		failures.append("player never re-settled on the returned ledge: vertical speed %.1f px/s" % player.linear_velocity.y)
	if returned_y + PLAYER_RADIUS > ledge_top + PLANT_CLEARANCE:
		failures.append("ledge did not hold again after its away delay: player at %.1f, expected resting at %.1f" % [
			returned_y, ledge_top])

	await _teardown(stage)
	return failures
