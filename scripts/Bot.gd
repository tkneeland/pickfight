extends Node

## One bot's brain (issue #152). It reads the stage the way a player reads the
## shared screen, and answers with the one thing a phone sends: a relative
## unit-disc input vector (ADR-0003). It never moves its `Player` itself.
## Every decision leaves through `output`, which `BotDirector` points at
## `ControllerServer.push_virtual_input()`, so a bot's input is smoothed and
## applied exactly the way a phone's is.
##
## There is one skill level, "decent":
##
## - **Moving** uses the vault every human learns first. The bot points the
##   weapon, short, at the nearest terrain on the side away from where it
##   wants to go, then shoves it out to full reach. The head plants and the
##   body is thrown the other way (ADR-0006): along the ground, or up onto a
##   ledge. That is how it climbs with the pickaxe.
## - **Fighting**: too close to someone to swing hard, it steps back first.
##   Within reach, it chops the head down through
##   them from above and swings it back up, over and over. Strike damage
##   scales with head speed, so the swing is fast.
## - **Targets**: a pickup while it still holds the pickaxe, or when one is
##   much nearer than anyone to hit; otherwise the nearest player.
## - **Staying alive**: it will not vault towards open air with no ground
##   under it, and once the lava comes close it heads up instead.
## - **Reading the stage** (issue #176): the ground ahead has to be ground it
##   can trust. Hazard zones (with a margin) and the column under a falling
##   rock's warning count as no ground at all, and so does a spinning
##   platform, a crumbling ledge or collapsing floor that is already giving
##   way, and a bounce pad (it throws the body somewhere else). Crumbling
##   ledges, collapsing floors and see-saws are "unstable": the bot does not
##   step onto one from solid ground, and standing on one it heads for the
##   nearest solid ground. It only steps over a gap narrow enough to step
##   over; a wider one it waits at, well back from the edge, so a moving
##   platform is boarded when it comes alongside. It does not swing with an
##   edge close behind it, nor back off towards one. Standing under a rock's
##   warning, in a hazard's margin or on ground that is giving way, it
##   flees. A bounce pad is used on purpose when the target is high above
##   and a pad on the bot's own floor is the way up.
##
## Preloaded by path (CLAUDE.md), never referenced by a `class_name`.

const KillZoneScript: GDScript = preload("res://scripts/KillZone.gd")
const CrumblingLedgeScript: GDScript = preload("res://scripts/CrumblingLedge.gd")
const CollapsingFloorScript: GDScript = preload("res://scripts/CollapsingFloor.gd")
const RotatingPlatformScript: GDScript = preload("res://scripts/RotatingPlatform.gd")
const BouncePadScript: GDScript = preload("res://scripts/BouncePad.gd")
const FallingRockScript: GDScript = preload("res://scripts/FallingRock.gd")
const MovingPlatformScript: GDScript = preload("res://scripts/MovingPlatform.gd")
const SpikesScript: GDScript = preload("res://scripts/Spikes.gd")
const SawScript: GDScript = preload("res://scripts/Saw.gd")
const GameModesScript: GDScript = preload("res://scripts/GameModes.gd")

## Player.LAYER_WORLD: terrain and bodies. Heads are on their own layer, so
## the rays below never see one.
const LAYER_WORLD: int = 1
## How often the target is picked again, in seconds. Between picks the bot
## keeps what it chose, so it does not dither between two targets.
const THINK_SEC: float = 0.25
## Vault timing: aim the head at the anchor, short, then push it out.
const AIM_SEC: float = 0.15
const PUSH_SEC: float = 0.22
## Swing timing: each half of the chop, up and down.
const SWING_SEC: float = 0.22
## The chop's arc, either side of the line to the target. The wind-up is on
## the upper side, so the chop comes down through the target and the head
## only meets the floor after it. The whole arc is under PI, because the
## angle drive always takes the short way round.
const SWING_ABOVE: float = 1.45
const SWING_BELOW: float = 0.6
## The gentler chop used with a drop close past the rival (issue #302).
const SWING_ABOVE_GENTLE: float = 0.7
const SWING_BELOW_GENTLE: float = 0.15
const SWING_SEC_GENTLE: float = 0.35
## Drop this close past the rival and the chop is gentle.
const GENTLE_EDGE_ROOM: float = 450.0
## Input length while aiming a vault, and while holding the head in the air.
const AIM_LENGTH: float = 0.15
const AIR_LENGTH: float = 0.3
## Input length of a vault's push with the pickaxe (#181). The vaults were
## tuned at its old 700 px/s, pushing to full reach; at 1000 px/s a full push
## threw the bot off Ferry's landing and Updraft's ledge from 7 of 14 starts
## within 45 px of the spawns. At 0.6 it survives all 14 again. Other
## weapons still push to full reach, as before.
const PICKAXE_PUSH_LENGTH: float = 0.6
## How far past full reach the anchor may be and still count as ground.
const ANCHOR_SLACK: float = 30.0
## A goal this far above counts as up, and the bot vaults for height.
const CLIMB_THRESHOLD: float = 50.0
## The goal has to be this close horizontally before the bot climbs for it.
const CLIMB_RANGE: float = 220.0
## Nearer than this share of its reach, the bot backs off before swinging,
## by about BACK_OFF_DISTANCE.
const CLOSE_FRACTION: float = 0.5
const BACK_OFF_DISTANCE: float = 160.0
## Horizontally this close to the goal, the bot stops heading sideways.
const ARRIVED_X: float = 30.0
## How far up the bot looks for a ceiling, and how far sideways (in steps)
## for a clear way round it.
const CEILING_PROBE: float = 220.0
const CEILING_SCAN_STEP: float = 40.0
const CEILING_SCAN_MAX: float = 480.0
## Player body radius: a head reaches a body this much past its own reach.
const BODY_RADIUS: float = 24.0
## How far below a point the bot looks for ground to land on.
const GROUND_PROBE: float = 1400.0
## How far ahead the bot checks for ground before vaulting sideways. (Issue
## #176 dropped the jump over any gap with ground 320 px beyond it: measured,
## the vault falls short of most of them.)
const EDGE_LOOKAHEAD: float = 150.0
## How close the lava may come below before the bot climbs instead.
const LAVA_WORRY: float = 280.0
## The bot starts worrying about the lava this long before its grace ends.
const LAVA_GRACE_HEADSTART: float = 2.0
## No real progress for this long and the bot vaults somewhere at random for
## WIGGLE_SEC, to get out of whatever it is stuck in.
const STUCK_SEC: float = 1.6
const STUCK_DISTANCE: float = 30.0
const WIGGLE_SEC: float = 0.8
## A pickup is worth the detour, for a bot already holding a picked-up weapon,
## when it is this fraction of the distance to the nearest player or less.
const PICKUP_DETOUR: float = 0.5
const PICKAXE_PATH: String = "res://resources/pickaxe.tres"

## Issue #176: what the ground under a point is. NONE is open air, a hazard,
## or ground about to go; UNSTABLE is ground that will not last (a crumbling
## ledge, a collapsing floor, a see-saw); PAD is a bounce pad.
const FOOT_NONE: int = 0
const FOOT_UNSTABLE: int = 1
const FOOT_SOLID: int = 2
const FOOT_PAD: int = 3
## Ground this far below the body's edge counts as under its feet.
const FOOT_SLACK: float = 20.0
## The step between the points checked for ground along the way ahead.
const SCAN_STEP: float = 25.0
## A gap this wide or narrower is stepped over; a wider one is waited at.
const GAP_STEP_MAX: float = 60.0
## Issue #409: two bots on either side of a wider gap each wait at their own
## edge for the other, and a round that needs them to meet (King of the Hill,
## Stock's last two lives) never ends. Held at an edge this long with a goal on
## the far side, the bot tries a gap up to this wide.
const EDGE_PATIENCE_SEC: float = 3.0
const GAP_STEP_DESPERATE: float = 150.0
## Issue #409: a pickup on a platform the bot cannot get onto drew two bots
## round and round beneath it for the whole round. After this long on the same
## pickup the bot drops it for PICKUP_IGNORE_SEC and goes back to fighting.
const PICKUP_GIVE_UP_SEC: float = 10.0
const PICKUP_IGNORE_SEC: float = 90.0
## Nearer than this to an edge, with nowhere to go that way, the bot steps
## back from it.
const EDGE_KEEP: float = 75.0
## The room the bot wants behind it before it swings: a swing throws the
## body back, away from the target.
const ATTACK_EDGE_ROOM: float = 200.0
## Hazard zones count as this much bigger than they are.
const HAZARD_MARGIN: float = 50.0
## Room either side of a falling rock's column, past the rock and a body.
const ROCK_MARGIN: float = 45.0
## How far either way the bot looks for solid ground to leave unstable
## ground for, and how much ground past a hazard or a rock's column it
## wants on the side it flees to.
const SOLID_SEARCH: float = 600.0
const FLEE_DISTANCE: float = 200.0
## A target this far above sends the bot to a bounce pad on its own floor,
## if there is one within PAD_SEARCH.
const PAD_CLIMB: float = 150.0
const PAD_SEARCH: float = 700.0
## A pad this close in height to the bot's own ground is on its floor.
const PAD_FLOOR_SLACK: float = 40.0
## A moving platform travelling further than this sideways counts as ground
## that will not last.
const SIDEWAYS_TRAVEL: float = 20.0
const LIFT_TRAVEL: float = 150.0
## Ground further than this below a point is too far to drop to on purpose:
## a step off an edge onto it is a fall.
const MAX_DROP: float = 240.0
## How far the bot's own speed carries it: the edge check looks this many
## seconds of its speed further ahead.
const MOMENTUM_SEC: float = 0.3
## Slower than this with nothing to push off, the bot is resting on an
## edge's corner; it flings its head this way (x towards the ground) to
## rock back onto it.
const PERCHED_SPEED: float = 40.0
const PERCH_FLING: Vector2 = Vector2(0.8, -0.6)
## Issue #302: a bot aiming its head down, at rest, with the head well above
## its body has the head hooked on top of a ledge and the body hanging below
## it. After HOOKED_SEC of that it sweeps the head out sideways, off the
## ledge, for UNHOOK_SEC.
## Issue #302: height above the bot beyond which a rival counts as that much
## farther away, once per pixel over it, times CLIMB_COST: a vault only lifts
## a bot so far, so a rival up on a high ledge is the last to be hunted.
const FREE_CLIMB: float = 100.0
const CLIMB_COST: float = 4.0
## A new rival takes over from the one being hunted only when this much closer.
const RETARGET_RATIO: float = 0.7
## Issue #302: faster than this sideways, with less than BRAKE_ROOM (plus what
## its speed carries) of ground ahead, an attacking bot brakes.
const BRAKE_SPEED: float = 250.0
const BRAKE_ROOM: float = 120.0
const AIM_SEC_AGGRESSIVE: float = 0.15
const PUSH_SEC_AGGRESSIVE: float = 0.22
const ENGAGE_AGGRESSIVE: float = 2.0
## Issue #302: the bot's pace with one rival left (see _aggression_now).
const FIELD_FULL: int = 4
const THINK_SEC_AGGRESSIVE: float = 0.1
const CLOSE_FRACTION_AGGRESSIVE: float = 0.0
const SWING_SEC_AGGRESSIVE: float = 0.17
const STRIKE_REACH_OFFSET: float = -25.0
## Ground the bot wants past a rival before it will close on one (issue #302).
const EDGE_BEYOND_ROOM: float = 160.0
## A head this much short of the reach it was sent to, and slower than
## BLOCKED_SPEED, is pinned (issue #302).
const BLOCKED_GAP: float = 25.0
const BLOCKED_SPEED: float = 150.0
## Further than this above the ground, the bot is in the air (issue #302).
const AIRBORNE_GAP: float = 45.0
const HOOKED_SEC: float = 0.5
const UNHOOK_SEC: float = 0.6
const HOOKED_HEAD_ABOVE: float = 40.0

## The `Player` this bot drives, and where its input goes.
var player: Node2D
var output: Callable = Callable()
## Seeds the few random choices, so a scenario can replay a bot exactly: a
## seed set before the bot enters the tree is kept (issue #165).
var rng := RandomNumberGenerator.new()

## What the bot is doing, for the scenarios: "idle", "move", "attack",
## "back" (stepping away from someone too close to swing at) or "flee"
## (getting out from under a hazard, issue #176), and the point it is
## heading for.
var mode: String = "idle"
var goal: Vector2 = Vector2.ZERO
## The last vector sent.
var last_input: Vector2 = Vector2.ZERO

var _think_left: float = 0.0
var _target: Node2D = null
var _phase: int = 0
var _phase_left: float = 0.0
var _anchor: Vector2 = Vector2.ZERO
var _anchor_length: float = 0.1
## True when the last anchor search found nothing to push off: the bot is in
## the air, and holds the head low and behind instead of pushing.
var _airborne: bool = true
var _progress_from: Vector2 = Vector2.ZERO
var _progress_left: float = STUCK_SEC
var _wiggle_left: float = 0.0
## True while the way to the goal is blocked by an edge or a hazard, and the
## bot waits there rather than going over.
var _held_at_edge: bool = false
## Seconds spent held at an edge this stretch (#409).
var _edge_wait: float = 0.0
## The bot's own clock, the pickup it is chasing and since when, and the ones
## it gave up on (instance id -> clock when it may look again) (#409).
var _clock: float = 0.0
var _chasing: Node2D = null
var _chase_since: float = 0.0
var _ignored_pickups: Dictionary = {}
## The side the bot is fleeing a danger to, kept while it flees so a bot
## right under a rock's middle does not dither from side to side.
var _flee_side: float = 0.0
var _lava: Area2D = null
## Whether this life has read the stage yet: its lava, hazard zones, falling
## rocks and bounce pads. The stage only changes between rounds, while the
## bot is out, so once a life is enough (#165).
var _lava_looked_up: bool = false
## How many times the tree has been searched for the lava (and, since #176,
## the rest of the stage's hazards with it), for the scenarios.
var lava_lookups: int = 0
## The stage's hazard zones (KillZone areas other than the lava), as world
## rectangles grown by HAZARD_MARGIN; its falling rocks and bounce pads.
var _hazard_rects: Array[Rect2] = []
var _rocks: Array[Node2D] = []
var _pads: Array[Node2D] = []
## Issue #313: saws (their zone moves, so it is rebuilt each tick from where
## the blade is now) and stage gusts (found by duck typing, so a gust part that
## lands later is handled without Bot knowing its script).
var _saws: Array[Node2D] = []
var _gusts: Array[Node2D] = []
## Off, the bot ignores spikes and saws; for scenarios that compare.
var avoid_damage_hazards: bool = true
## The hazard rectangles plus the columns under any rock now warning or
## falling: built once a physics tick.
var _danger: Array[Rect2] = []
var _danger_frame: int = -1
## True while the bot is heading for a bounce pad on purpose, so the pad
## counts as ground to walk onto.
var _pad_route: bool = false
var _hooked_for: float = 0.0
var _aggression: float = 0.0
var _last_head: Vector2 = Vector2.ZERO
var _unhook_left: float = 0.0
var _unhook_side: float = 1.0
## The players' bodies, which every ray ignores: gathered once a physics tick,
## not once a ray (issue #165).
var _rids: Array[RID] = []
var _rids_frame: int = -1

func _init() -> void:
	rng.randomize()

func _physics_process(delta: float) -> void:
	var v: Vector2 = think(delta)
	last_input = v
	if output.is_valid():
		output.call(v)

## One tick of decisions: the input vector this bot sends now.
func think(delta: float) -> Vector2:
	if not _alive(player):
		mode = "idle"
		_target = null
		_lava = null
		_lava_looked_up = false
		_hazard_rects.clear()
		_rocks.clear()
		_pads.clear()
		_saws.clear()
		_gusts.clear()
		_danger_frame = -1
		_pad_route = false
		_edge_wait = 0.0
		_held_at_edge = false
		return Vector2.ZERO
	_clock += delta
	_think_left -= delta
	if _think_left <= 0.0 or (_target != null and not _alive(_target)):
		_aggression = _aggression_now()
		_think_left = lerpf(THINK_SEC, THINK_SEC_AGGRESSIVE, _aggression)
		_choose_goal()
	_track_progress(delta)
	if mode == "attack" and _alive(_target):
		_hooked_for = 0.0
		var brake: Vector2 = _brake()
		if brake != Vector2.ZERO:
			return brake
		var air: Vector2 = _hold_in_air()
		if air != Vector2.ZERO:
			return air
		return _swing(delta)
	var unhook: Vector2 = _unhook(delta)
	if unhook != Vector2.ZERO:
		return unhook
	return _vault(delta)

# --- Mode objectives (issue #353) -------------------------------------------------

## Hot Potato: how far from "it" a bot that is not "it" tries to stay.
const KEEP_AWAY_FROM_IT: float = 700.0
## King of the Hill: inside this fraction of the hill's radius counts as holding it.
const HILL_HOLD_FRACTION: float = 0.6

## The hill (King of the Hill) this tick, or null; and the Hot Potato "it" this
## bot keeps away from, or null. Sudden Death, Stock, Classic and any mode this
## does not know leave both null: the bot plays the existing hunt.
var _hill_node: Node = null
var _hill_rival_inside: bool = false
var _keep_away_from: Node2D = null
## Soccer (#402): the mode node this tick, or null.
var _soccer_node: Node = null

## Capture the Flag (#403): the mode node this tick, or null.
var _ctf_node: Node = null

## Soccer: how far behind the ball (away from the goal it attacks) a bot lines
## up, and how far past it the bot drives.
const SOCCER_BEHIND: float = 90.0
const SOCCER_DRIVE: float = 160.0

func _read_mode() -> void:
	_soccer_node = null
	_ctf_node = null
	_hill_node = null
	_hill_rival_inside = false
	_keep_away_from = null
	var rm: Node = player.get_tree().get_first_node_in_group("round_manager")
	if rm == null or not rm.has_method("active_game_mode_id"):
		return
	var node: Node = rm.game_mode_node()
	if node == null or not is_instance_valid(node):
		return
	match rm.active_game_mode_id():
		GameModesScript.KING_OF_THE_HILL:
			_hill_node = node
			for other: Node in player.get_tree().get_nodes_in_group("players"):
				if other != player and _alive(other) and _in_hill(other as Node2D) \
						and not (player.has_method("is_teammate") and player.is_teammate(other)):
					_hill_rival_inside = true
		GameModesScript.SOCCER:
			_soccer_node = node
		GameModesScript.CAPTURE_THE_FLAG:
			_ctf_node = node
		GameModesScript.HOT_POTATO:
			var it_slot: int = int(node.it_slot)
			var me_slot: int = rm._players.find(player)
			if it_slot >= 0 and it_slot != me_slot and it_slot < rm._players.size():
				var it: Variant = rm._players[it_slot]
				if _alive(it):
					_keep_away_from = it as Node2D

func _in_hill(who: Node2D, fraction: float = 1.0) -> bool:
	return who.global_position.distance_to(_hill_node.hill_position) <= float(_hill_node.hill_radius) * fraction

## Soccer: get behind the ball on the side away from the goal this bot attacks,
## then drive through it towards that goal.
func _soccer_goal() -> Vector2:
	var rm: Node = player.get_tree().get_first_node_in_group("round_manager")
	var team: int = _soccer_node.team_of(rm._players.find(player))
	var ball_at: Vector2 = _soccer_node.ball.global_position
	var aim: Vector2 = _soccer_node.attack_point(team)
	var dir: float = signf(aim.x - ball_at.x) if aim.x != ball_at.x else 1.0
	var me: Vector2 = player.global_position
	var behind: bool = (me.x - ball_at.x) * dir < -BODY_RADIUS
	if behind:
		return Vector2(ball_at.x + dir * SOCCER_DRIVE, ball_at.y)
	return Vector2(ball_at.x - dir * SOCCER_BEHIND, ball_at.y)

## Capture the Flag: where this bot heads (#403).
## - Carrying the enemy flag: home to its own base.
## - An enemy carries ours: everyone on the team chases the carrier.
## - Our flag lies dropped: everyone not carrying runs to return it.
## - Otherwise the team's lowest slot defends (waits at its own flag) when it
##   has company, and the rest go for the enemy flag (or, if a teammate already
##   carries it, escort that teammate home).
func _ctf_goal() -> Vector2:
	var rm: Node = player.get_tree().get_first_node_in_group("round_manager")
	var slot: int = rm._players.find(player)
	var team: int = _ctf_node.team_of(slot)
	var enemy: int = 1 - team
	var me: Vector2 = player.global_position
	if _ctf_node.carried_flag_of(slot) != -1:
		return _ctf_node.base_rect(team).get_center()
	var chased: int = int(_ctf_node.carrier[team])
	if chased != -1 and chased < rm._players.size() and _alive(rm._players[chased]):
		_target = rm._players[chased] as Node2D
		return (rm._players[chased] as Node2D).global_position
	if int(_ctf_node.state[team]) == _ctf_node.DROPPED:
		return _ctf_node.flag_position[team]
	var mates: Array[int] = []
	for o in rm._players.size():
		if _ctf_node.team_of(o) == team and rm._players[o] != null and _alive(rm._players[o]):
			mates.append(o)
	mates.sort()
	if mates.size() > 1 and mates[0] == slot:
		return _ctf_node.home_position(team)
	var ours: int = int(_ctf_node.carrier[enemy])
	if ours != -1 and ours != slot and ours < rm._players.size() and _alive(rm._players[ours]):
		return _ctf_node.base_rect(team).get_center()
	return _ctf_node.flag_position[enemy]

## Not "it" in Hot Potato: step away from "it" along the ground the bot can
## trust. `goal` is where the vault heads.
func _keep_away_goal() -> Vector2:
	var me: Vector2 = player.global_position
	var it_at: Vector2 = _keep_away_from.global_position
	if me.distance_to(it_at) >= KEEP_AWAY_FROM_IT:
		return me
	var side: float = signf(me.x - it_at.x) if me.x != it_at.x else 1.0
	var away: float = _safe_side(side)
	if away == 0.0:
		away = _safe_side(-side)
		# Ground only towards "it": hold the place rather than run into it.
		if away != 0.0 and signf(away) != side:
			return me
	return Vector2(me.x + away * FLEE_DISTANCE, me.y) if away != 0.0 else me

# --- Choosing a goal -------------------------------------------------------------

func _choose_goal() -> void:
	_read_mode()
	var me: Vector2 = player.global_position
	var enemy: Node2D = _nearest_enemy()
	var enemy_distance: float = me.distance_to(enemy.global_position) if enemy != null else INF
	var pickup: Node2D = _nearest_pickup()
	var pickup_distance: float = me.distance_to(pickup.global_position) if pickup != null else INF
	var lava_close: bool = _lava_worry()
	_pad_route = false
	# Out from under a rock, out of a hazard's margin, off ground giving way
	# or ground that will not last: before anything else (issue #176).
	var escape: Vector2 = _escape_goal()
	if escape != Vector2.INF and not lava_close:
		mode = "flee"
		_target = null
		goal = escape
		return
	if _keep_away_from != null and not lava_close:
		mode = "move"
		_target = null
		goal = _keep_away_goal()
		return
	if enemy != null and enemy_distance < _reach() * lerpf(CLOSE_FRACTION, CLOSE_FRACTION_AGGRESSIVE, _aggression) and not lava_close:
		# Too close to swing fast: a short lever moves the head slowly, and
		# a slow head does no damage. Step back out to a swinging distance,
		# unless there is no ground that way, or not enough of it.
		var away: float = _safe_side(signf(me.x - enemy.global_position.x) if me.x != enemy.global_position.x else 1.0)
		if away != 0.0 and _edge_room(away, BACK_OFF_DISTANCE + EDGE_KEEP) >= BACK_OFF_DISTANCE + EDGE_KEEP:
			mode = "back"
			_target = enemy
			goal = Vector2(me.x + away * BACK_OFF_DISTANCE, me.y)
			return
	# A swing throws the body back, away from the target: with an edge close
	# behind, the bot presses in towards the target instead (issue #176).
	var behind: float = -signf(enemy.global_position.x - me.x) if enemy != null and enemy.global_position.x != me.x else 0.0
	var room_behind: bool = behind == 0.0 or _edge_room(behind, ATTACK_EDGE_ROOM) >= ATTACK_EDGE_ROOM
	# Issue #302: nor does it close on a rival with a drop right past it: the
	# swing's throw carries the bot over the rival and off the stage. It holds
	# off until the rival comes away from the edge.
	var drop_beyond: bool = enemy != null and enemy.global_position.x != me.x \
			and _edge_room(signf(enemy.global_position.x - me.x), absf(enemy.global_position.x - me.x) + EDGE_BEYOND_ROOM) \
			< absf(enemy.global_position.x - me.x) + EDGE_BEYOND_ROOM
	if enemy != null and enemy_distance <= _reach() + BODY_RADIUS * 3.0 and drop_beyond and not lava_close and room_behind:
		mode = "move"
		_target = enemy
		goal = me
		return
	if enemy != null and enemy_distance <= _reach() + BODY_RADIUS * lerpf(1.0, ENGAGE_AGGRESSIVE, _aggression) and not lava_close and room_behind:
		if mode != "attack":
			_phase = 0
			_phase_left = SWING_SEC
		mode = "attack"
		_target = enemy
		goal = enemy.global_position
		return
	mode = "move"
	_target = null
	if _soccer_node != null and _soccer_node.ball != null and is_instance_valid(_soccer_node.ball):
		goal = _soccer_goal()
	elif _ctf_node != null:
		goal = _ctf_goal()
	elif _hill_node != null:
		if not _in_hill(player, HILL_HOLD_FRACTION):
			goal = _hill_node.hill_position
		elif enemy != null and _hill_rival_inside:
			_target = enemy
			goal = enemy.global_position
		else:
			goal = me
	elif pickup != null and (_holds_pickaxe() or pickup_distance < enemy_distance * PICKUP_DETOUR):
		goal = pickup.global_position
		if pickup != _chasing:
			_chasing = pickup
			_chase_since = _clock
		elif _clock - _chase_since > PICKUP_GIVE_UP_SEC:
			_ignored_pickups[pickup.get_instance_id()] = _clock + PICKUP_IGNORE_SEC
			_chasing = null
	elif enemy != null:
		_chasing = null
		_target = enemy
		goal = enemy.global_position
	else:
		goal = me
	if lava_close:
		goal = Vector2(goal.x, minf(goal.y, me.y - 300.0))
	elif goal.y < me.y - PAD_CLIMB:
		var pad: Vector2 = _pad_towards(goal)
		if pad != Vector2.INF:
			_pad_route = true
			goal = pad

## Issue #302: 0 with FIELD_FULL or more rivals alive, 1 with one left, and
## in between as they dwindle: the fewer rivals, the less the bot hesitates,
## the closer it fights and the faster it chops.
func _aggression_now() -> float:
	var rivals: int = 0
	for other: Node in player.get_tree().get_nodes_in_group("players"):
		if other == player or not _alive(other):
			continue
		if player.has_method("is_teammate") and player.is_teammate(other):
			continue
		rivals += 1
	if rivals == 0:
		return 0.0
	return clampf(float(FIELD_FULL - rivals) / float(FIELD_FULL - 1), 0.0, 1.0)

## The nearest player the bot can walk to (issue #176), or failing that the
## nearest at all: it waits at the edge for that one.
func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_cost: float = INF
	var walkable: Node2D = null
	var walkable_cost: float = INF
	var current: Node2D = null
	var current_cost: float = INF
	var current_walkable: bool = false
	for other: Node in player.get_tree().get_nodes_in_group("players"):
		if other == player or not _alive(other):
			continue
		# Issue #236: never a teammate in a Teams match.
		if player.has_method("is_teammate") and player.is_teammate(other):
			continue
		# King of the Hill: fight whoever is in the hill before anyone else.
		if _hill_rival_inside and not _in_hill(other as Node2D):
			continue
		var at: Vector2 = (other as Node2D).global_position
		var cost: float = _hunt_cost(at)
		var reachable: bool = _walkable_to(at.x)
		if other == _target:
			current = other as Node2D
			current_cost = cost
			current_walkable = reachable
		if cost < best_cost:
			best_cost = cost
			best = other as Node2D
		if cost < walkable_cost and reachable:
			walkable_cost = cost
			walkable = other as Node2D
	var pick: Node2D = walkable if walkable != null else best
	var pick_cost: float = walkable_cost if walkable != null else best_cost
	# Stick with the rival being hunted unless another is clearly better
	# (issue #302): swapping on every think tick is dithering.
	if current != null and current != pick and (current_walkable or walkable == null) \
			and pick_cost > current_cost * RETARGET_RATIO:
		return current
	return pick

## How costly a rival at `at` is to hunt (issue #302): the distance, plus
## extra for every pixel it is up above what a vault can reach.
func _hunt_cost(at: Vector2) -> float:
	var above: float = maxf(player.global_position.y - at.y - FREE_CLIMB, 0.0)
	return player.global_position.distance_to(at) + above * CLIMB_COST

## The nearest pickup with solid ground under it and either side of it: one
## over open air, a hazard, a pad or ground that will not last is bait.
func _nearest_pickup() -> Node2D:
	var best: Node2D = null
	var best_distance: float = INF
	for pickup: Node in player.get_tree().get_nodes_in_group("pickups"):
		if not is_instance_valid(pickup) or pickup.is_queued_for_deletion() or not pickup.is_inside_tree():
			continue
		if float(_ignored_pickups.get(pickup.get_instance_id(), -1.0)) > _clock:
			continue
		var at: Vector2 = (pickup as Node2D).global_position
		var d: float = player.global_position.distance_to(at)
		if d < best_distance and _footing(at) == FOOT_SOLID and _footing(at + Vector2(EDGE_KEEP, 0.0)) == FOOT_SOLID \
				and _footing(at - Vector2(EDGE_KEEP, 0.0)) == FOOT_SOLID and _walkable_to(at.x):
			best_distance = d
			best = pickup
	return best

func _alive(node: Variant) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var n: Node = node as Node
	return n.is_inside_tree() and bool(n.get("alive"))

func _holds_pickaxe() -> bool:
	var stats: Variant = player.get("weapon_stats")
	return not (stats is Resource) or (stats as Resource).resource_path == PICKAXE_PATH

func _stat(key: String, fallback: float) -> float:
	var stats: Variant = player.get("weapon_stats")
	if stats is Resource:
		var value: Variant = (stats as Resource).get(key)
		if value != null:
			return float(value)
	return fallback

func _reach() -> float:
	return _stat("max_reach", 150.0)

func _min_reach() -> float:
	return _stat("min_reach", 20.0)

## The input length that asks for `reach` pixels (Player maps 0..1 onto
## min_reach..max_reach).
func _length_for(reach: float) -> float:
	var span: float = maxf(_reach() - _min_reach(), 1.0)
	return clampf((reach - _min_reach()) / span, 0.05, 1.0)

# --- Fighting ------------------------------------------------------------------

## Chop down through the target from above, swing back up, repeat. The
## wind-up side is whichever side of the line to the target is up.
func _swing(delta: float) -> Vector2:
	var to_target: Vector2 = _target.global_position - player.global_position
	var base: float = to_target.angle()
	# Screen y points down, so "up" is towards negative angles on the right
	# and towards positive ones on the left.
	var up_side: float = -1.0 if to_target.x >= 0.0 else 1.0
	# Issue #302: with a drop just past the rival, a hard chop that plants the
	# head throws the bot over it and off the stage: a short, gentle one.
	var gentle: bool = to_target.x != 0.0 \
			and _edge_room(signf(to_target.x), absf(to_target.x) + GENTLE_EDGE_ROOM) < absf(to_target.x) + GENTLE_EDGE_ROOM
	var above: float = SWING_ABOVE_GENTLE if gentle else SWING_ABOVE
	var below: float = SWING_BELOW_GENTLE if gentle else SWING_BELOW
	_phase_left -= delta
	if _phase_left <= 0.0:
		_phase = 1 - _phase
		_phase_left = SWING_SEC_GENTLE if gentle else lerpf(SWING_SEC, SWING_SEC_AGGRESSIVE, _aggression)
	var angle: float = base + up_side * above if _phase == 0 else base - up_side * below
	var wanted: float = to_target.length() + STRIKE_REACH_OFFSET
	# Issue #302: a head pinned against the rival or the floor and pushed on
	# vaults the body over it. Once it is held short of where it was sent
	# (not just lagging in a swing), ease off to where it is.
	if player.has_method("weapon_head_position") and delta > 0.0:
		var head: Vector2 = player.weapon_head_position()
		var speed: float = head.distance_to(_last_head) / delta
		_last_head = head
		var actual: float = player.global_position.distance_to(head)
		if actual < wanted - BLOCKED_GAP and speed < BLOCKED_SPEED:
			wanted = maxf(actual, _min_reach())
	var length: float = _length_for(wanted)
	return Vector2.RIGHT.rotated(angle) * length

## Issue #302: a swing's head-plant can throw the bot over its rival and on
## towards an edge. Carried towards one faster than it can stop, it plants the
## head ahead of itself, down and forward, and pushes: the throw goes back.
func _brake() -> Vector2:
	var body := player as RigidBody2D
	if body == null:
		return Vector2.ZERO
	var side: float = signf(body.linear_velocity.x)
	if side == 0.0 or absf(body.linear_velocity.x) < BRAKE_SPEED:
		return Vector2.ZERO
	var ahead: float = BRAKE_ROOM + absf(body.linear_velocity.x) * MOMENTUM_SEC
	# Carried over the rival's head is as bad as carried over an edge.
	var to_rival: float = (_target.global_position.x - player.global_position.x) * side
	var overshooting: bool = to_rival > -BODY_RADIUS and to_rival < absf(body.linear_velocity.x) * MOMENTUM_SEC \
			and absf(body.linear_velocity.x) > BRAKE_SPEED
	if not overshooting and _edge_room(side, ahead) >= ahead:
		return Vector2.ZERO
	var dir := Vector2(side * 0.5, 0.87).normalized()
	if not _floor_hit(player.global_position, player.global_position + dir * (_reach() + ANCHOR_SLACK)):
		return dir * AIR_LENGTH
	return dir * (PICKAXE_PUSH_LENGTH if _holds_pickaxe() else 1.0)

## Issue #302: a bot thrown off the ground mid-fight, by its own swing or a
## vault over the rival's head, stops swinging: every push it makes in the air
## only speeds it on its way over the rival. It holds the head short and low
## behind, ready to plant on landing.
func _hold_in_air() -> Vector2:
	var me: Vector2 = player.global_position
	if _ray_hits(me, me + Vector2(0.0, BODY_RADIUS + AIRBORNE_GAP)):
		return Vector2.ZERO
	var side: float = signf(_target.global_position.x - me.x)
	return Vector2(-side * 0.5, 1.0).normalized() * AIR_LENGTH

# --- Moving --------------------------------------------------------------------

## Issue #302: the head hooked over a ledge's top with the body dangling
## beneath it holds the bot there for good, because every anchor it plants
## is downwards, into the ledge the head is already resting on. Sweep the
## head out sideways, towards the goal, to slide it off.
func _unhook(delta: float) -> Vector2:
	if _unhook_left > 0.0:
		_unhook_left -= delta
		return Vector2(_unhook_side, 0.0)
	var body := player as RigidBody2D
	if body == null or not player.has_method("weapon_head_position"):
		return Vector2.ZERO
	var head: Vector2 = player.weapon_head_position()
	var hooked: bool = body.linear_velocity.length() < PERCHED_SPEED and last_input.y > 0.0 \
			and head.y < player.global_position.y - HOOKED_HEAD_ABOVE
	if not hooked:
		_hooked_for = 0.0
		return Vector2.ZERO
	_hooked_for += delta
	if _hooked_for < HOOKED_SEC:
		return Vector2.ZERO
	_hooked_for = 0.0
	_unhook_left = UNHOOK_SEC
	var side: float = signf(goal.x - player.global_position.x)
	_unhook_side = side if side != 0.0 else (-1.0 if rng.randf() < 0.5 else 1.0)
	return Vector2(_unhook_side, 0.0)

## Vault towards `goal`: aim short at an anchor, then push out through it.
func _vault(delta: float) -> Vector2:
	_phase_left -= delta
	if _phase_left <= 0.0:
		_phase = 1 - _phase
		if _phase == 0:
			_phase_left = lerpf(AIM_SEC, AIM_SEC_AGGRESSIVE, _aggression)
			_pick_anchor()
		else:
			_phase_left = lerpf(PUSH_SEC, PUSH_SEC_AGGRESSIVE, _aggression)
	if _phase == 0 or _airborne:
		return _anchor * _anchor_length
	return _anchor * PICKAXE_PUSH_LENGTH if _holds_pickaxe() else _anchor

## Where the head plants for the next vault. Pushing the head out through
## the anchor throws the body the opposite way, so the anchor is below and
## behind the way the bot wants to go: shallow for travel along the ground,
## steep for height, straight down for a pogo. Measured on Flatlands with the
## pickaxe, the shallow vault covers ground fastest and the steep one lifts
## the body highest while still drifting forward.
func _pick_anchor() -> void:
	var me: Vector2 = player.global_position
	var side: float = _travel_side()
	# Height only once near the goal: from far off, cover the ground first.
	var rising: bool = (goal.y < me.y - CLIMB_THRESHOLD and absf(goal.x - me.x) < CLIMB_RANGE) or _lava_worry()
	if _wiggle_left > 0.0:
		side = _safe_side(-1.0 if rng.randf() < 0.5 else 1.0)
		rising = rng.randf() < 0.5
	var candidates: Array[Vector2] = []
	if side == 0.0:
		if rising:
			candidates.append(Vector2.DOWN)
	elif rising:
		candidates.append(Vector2(-side * 0.38, 0.92))
		candidates.append(Vector2.DOWN)
	else:
		# Shallow only: from any higher, the bot falls back to the ground
		# first, rather than vaulting steeply and staying up in the air.
		candidates.append(Vector2(-side * 0.92, 0.38))
		# Standing at an edge and heading away from it, the shallow anchor
		# is over the drop: plant steeply instead, just behind the feet
		# (issue #176). So too when the bot rests up on its own head, too
		# high for the shallow one to reach the ground.
		var body := player as RigidBody2D
		var resting: bool = body != null and body.linear_velocity.length() < PERCHED_SPEED
		if resting or _ray_hits(me, me + Vector2(0.0, BODY_RADIUS + FOOT_SLACK)):
			candidates.append(Vector2(-side * 0.38, 0.92))
			# Right at the edge even that is over the drop: all but
			# straight down, a hop that drifts the bot back from it.
			candidates.append(Vector2(-side * 0.15, 0.99).normalized())
	# The first one with ground to plant on. Where none has, the bot is in
	# the air: it holds the head short and low, ready to plant on landing,
	# without pogoing on it.
	_airborne = true
	for dir: Vector2 in candidates:
		if _floor_hit(me, me + dir * (_reach() + ANCHOR_SLACK)):
			_anchor = dir
			_anchor_length = AIM_LENGTH
			_airborne = false
			return
	# Perched on an edge's corner, the body's middle over the drop and no
	# ground behind to push off: fling the head up and in over the ground,
	# and the swing of it rocks the body back onto it (issue #176).
	var body := player as RigidBody2D
	if side != 0.0 and body != null and body.linear_velocity.length() < PERCHED_SPEED and _standing_on() == FOOT_NONE:
		var foot: Vector2 = me + Vector2(side * BODY_RADIUS, 0.0)
		if _ray_hits(foot, foot + Vector2(0.0, BODY_RADIUS + FOOT_SLACK)):
			_anchor = PERCH_FLING * Vector2(side, 1.0)
			_anchor_length = AIM_LENGTH
			_airborne = false
			return
	_anchor = Vector2(-side * 0.5, 1.0).normalized()
	_anchor_length = AIR_LENGTH

## Which way along x the bot heads: towards the goal, unless that is open air
## with nothing to land on, or the goal is up on something directly overhead,
## in which case it heads for the nearer way round it.
func _travel_side() -> float:
	var me: Vector2 = player.global_position
	var to_goal: Vector2 = goal - me
	var side: float = 0.0
	if absf(to_goal.x) > ARRIVED_X:
		side = signf(to_goal.x)
	if to_goal.y < -CLIMB_THRESHOLD and _ray_hits(me, me + Vector2(0.0, -CEILING_PROBE)):
		side = _way_round_ceiling(side)
	# Getting off ground that is going, or over none: straight for the
	# solid ground, the way there checked already (issue #176).
	# Out from under a danger over solid ground, the ground's own edges
	# still hold: a flee's throw is no reason to run off the far side.
	if mode == "flee" and _standing_on() != FOOT_SOLID:
		if side != 0.0 and _footing(me, true) == FOOT_SOLID:
			var ahead: float = EDGE_LOOKAHEAD + _momentum(side)
			if _edge_room(side, ahead, true) < ahead:
				return 0.0
		return side
	# Upwind of a gust that is warning or blowing (issue #313).
	var gust: float = _gust_side()
	if gust != 0.0:
		side = gust
	var safe: float = _safe_side(side)
	_held_at_edge = side != 0.0 and safe == 0.0
	if safe == 0.0:
		# Stopped by an edge or a hazard (issue #176): not right at it,
		# where a knock or its own swing puts the bot over.
		safe = _step_back_from_edges()
	return safe

## `side`, or 0 where the way ahead is no ground the bot can trust: open
## air, a hazard, a pad, or ground that will not last when the bot is on
## solid ground (issue #176). A gap of up to GAP_STEP_MAX is stepped over.
func _safe_side(side: float) -> float:
	if side == 0.0:
		return 0.0
	var ahead: float = EDGE_LOOKAHEAD + _momentum(side)
	return side if _edge_room(side, ahead) >= ahead else 0.0

## How far the body's speed along `side` carries it on its own.
func _momentum(side: float) -> float:
	var body := player as RigidBody2D
	if body == null:
		return 0.0
	return maxf(body.linear_velocity.x * side, 0.0) * MOMENTUM_SEC

## The side away from an edge nearer than EDGE_KEEP, or 0 where neither is.
func _step_back_from_edges() -> float:
	var keep_right: float = EDGE_KEEP + _momentum(1.0)
	var keep_left: float = EDGE_KEEP + _momentum(-1.0)
	var right: float = _edge_room(1.0, keep_right)
	var left: float = _edge_room(-1.0, keep_left)
	if right < keep_right and left >= EDGE_KEEP:
		return -1.0
	if left < keep_left and right >= EDGE_KEEP:
		return 1.0
	return 0.0

## How far the bot can go along `side` on ground it trusts, up to `limit`,
## stepping over any gap of up to GAP_STEP_MAX.
func _edge_room(side: float, limit: float, past_danger: bool = false) -> float:
	var me: Vector2 = player.global_position
	var from: int = _standing_on()
	var d: float = SCAN_STEP
	while d <= limit:
		if not _can_step(_footing(me + Vector2(side * d, 0.0), past_danger), from):
			var gap_end: float = d + SCAN_STEP
			var crossed: bool = false
			while gap_end <= d + _gap_limit():
				if _can_step(_footing(me + Vector2(side * gap_end, 0.0), past_danger), from):
					crossed = true
					break
				gap_end += SCAN_STEP
			if not crossed:
				return d - SCAN_STEP
			d = gap_end
		d += SCAN_STEP
	return limit

## The widest gap the bot steps over now: wider once it has waited at an edge
## for the way across (#409).
func _gap_limit() -> float:
	return GAP_STEP_DESPERATE if _edge_wait >= EDGE_PATIENCE_SEC else GAP_STEP_MAX

## Whether the bot could walk to `x` on ground it trusts, at its own
## height, stepping over narrow gaps only (issue #176). Checked coarsely:
## this is for choosing what to go for, not for placing a foot.
func _walkable_to(x: float) -> bool:
	var me: Vector2 = player.global_position
	var span: float = absf(x - me.x)
	var side: float = signf(x - me.x)
	if span <= SCAN_STEP * 2.0:
		return true
	var from: int = _standing_on()
	var step: float = GAP_STEP_MAX * 0.5
	var d: float = step
	var bad_run: float = 0.0
	while d < span:
		if _can_step(_footing(me + Vector2(side * d, 0.0)), from):
			bad_run = 0.0
		else:
			bad_run += step
			if bad_run > _gap_limit():
				return false
		d += step
	return true

## Whether ground of kind `kind` is somewhere to step, for a bot now on
## ground of kind `from`.
func _can_step(kind: int, from: int) -> bool:
	match kind:
		FOOT_SOLID:
			return true
		FOOT_UNSTABLE:
			return from != FOOT_SOLID
		FOOT_PAD:
			return _pad_route
	return false

## What the bot is standing on, or over, now.
func _standing_on() -> int:
	return _footing(player.global_position)

## What the ground under `point` is (FOOT_*): the first terrain straight
## below it, above the lava, with no hazard (or falling rock's column) in
## between. A point inside terrain counts as that terrain.
func _footing(point: Vector2, past_danger: bool = false) -> int:
	var bottom: float = minf(point.y + GROUND_PROBE, _lava_top())
	if bottom <= point.y:
		return FOOT_NONE
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(point, Vector2(point.x, bottom), LAYER_WORLD, _player_rids())
	query.hit_from_inside = true
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return FOOT_NONE
	var ground_y: float = (hit["position"] as Vector2).y
	if ground_y - point.y > MAX_DROP:
		return FOOT_NONE
	for rect: Rect2 in ([] as Array[Rect2]) if past_danger else _danger_rects():
		if point.x >= rect.position.x and point.x <= rect.end.x \
				and rect.position.y <= ground_y + BODY_RADIUS and rect.end.y >= point.y:
			return FOOT_NONE
	return _ground_kind(hit["collider"])

## FOOT_* for a piece of terrain.
func _ground_kind(collider: Object) -> int:
	if collider == null:
		return FOOT_NONE
	var script: Script = collider.get_script()
	if script == CrumblingLedgeScript:
		return FOOT_UNSTABLE if collider.call("is_solid") else FOOT_NONE
	if script == CollapsingFloorScript:
		return FOOT_UNSTABLE if collider.call("state_name") == "solid" else FOOT_NONE
	if script == RotatingPlatformScript:
		return FOOT_UNSTABLE if int(collider.get("mode")) == RotatingPlatformScript.Mode.SEESAW else FOOT_NONE
	if script == BouncePadScript:
		return FOOT_PAD
	# A platform moving sideways (a ferry's barge) is gone from under a
	# step a moment later, and a lift a long way up or down is soon far from
	# where it was stepped on; a piston's short stroke is ground enough.
	if script == MovingPlatformScript:
		var travel: Vector2 = collider.get("travel")
		if absf(travel.x) > SIDEWAYS_TRAVEL or absf(travel.y) > LIFT_TRAVEL:
			return FOOT_UNSTABLE
	return FOOT_SOLID

## The side of the nearest clear column above the bot, preferring `side` on
## a tie; `side` itself if the whole scan is covered.
func _way_round_ceiling(side: float) -> float:
	var me: Vector2 = player.global_position
	var first: float = side if side != 0.0 else 1.0
	var step: float = CEILING_SCAN_STEP
	while step <= CEILING_SCAN_MAX:
		for s: float in [first, -first]:
			var x: Vector2 = me + Vector2(s * step, 0.0)
			if not _ray_hits(x, x + Vector2(0.0, -CEILING_PROBE)) and _footing(x) != FOOT_NONE:
				return s
		step += CEILING_SCAN_STEP
	return side

## Whether the ray from `from` to `to` meets ground facing up, to plant a
## head on (issue #176): the side of a ledge below its edge is no anchor,
## and a push into it throws the bot out over the drop.
func _floor_hit(from: Vector2, to: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, LAYER_WORLD, _player_rids())
	var hit: Dictionary = space.intersect_ray(query)
	return not hit.is_empty() and (hit["normal"] as Vector2).y < -0.5

func _ray_hits(from: Vector2, to: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, LAYER_WORLD, _player_rids())
	return not space.intersect_ray(query).is_empty()

## Whether the lava is rising and close below. Not during the grace before
## it sets off: `is_rising()` is true from the round's start, and a bot on a
## low stage that worried all through the grace climbed instead of getting
## off ground giving way under it (issue #176).
func _lava_worry() -> bool:
	var top: float = _lava_top()
	if _lava == null or not bool(_lava.call("is_rising")):
		return false
	if float(_lava.get("_grace_left")) > LAVA_GRACE_HEADSTART:
		return false
	return top - player.global_position.y < LAVA_WORRY

func _player_rids() -> Array[RID]:
	var frame: int = Engine.get_physics_frames()
	if frame != _rids_frame:
		_rids_frame = frame
		_rids.clear()
		for other: Node in player.get_tree().get_nodes_in_group("players"):
			if other is CollisionObject2D:
				_rids.append((other as CollisionObject2D).get_rid())
	return _rids

## The hazard rectangles, plus the column under every falling rock that is
## warning or falling (issue #176). Built once a physics tick.
func _danger_rects() -> Array[Rect2]:
	var frame: int = Engine.get_physics_frames()
	if frame == _danger_frame:
		return _danger
	_danger_frame = frame
	_lava_top()
	_danger.clear()
	_danger.append_array(_hazard_rects)
	for saw: Node2D in _saws:
		if is_instance_valid(saw) and saw.is_inside_tree():
			var reach: float = float(saw.get("radius")) + BODY_RADIUS + HAZARD_MARGIN
			_danger.append(Rect2(saw.global_position.x - reach, saw.global_position.y - reach, reach * 2.0, reach * 2.0))
	for rock: Node2D in _rocks:
		if not is_instance_valid(rock) or not rock.is_inside_tree():
			continue
		var state: String = rock.call("state_name")
		if state != "warning" and state != "falling":
			continue
		var half: float = float(rock.get("rock_radius")) + BODY_RADIUS + ROCK_MARGIN
		var top: float = (rock.call("rock_position") as Vector2).y
		var landing: Vector2 = rock.call("landing_point")
		var bottom: float = landing.y + BODY_RADIUS * 2.0 if not is_nan(landing.y) else top + GROUND_PROBE * 3.0
		_danger.append(Rect2(rock.global_position.x - half, top, half * 2.0, maxf(bottom - top, 1.0)))
	return _danger

## Where to go to get out of trouble (issue #176), or Vector2.INF when the
## bot is in none: from under a falling rock's warning, out of a hazard's
## margin, off ground that is giving way (or over none), or off unstable
## ground to the nearest solid ground.
func _escape_goal() -> Vector2:
	var me: Vector2 = player.global_position
	for rect: Rect2 in _danger_rects():
		if rect.has_point(me) or (me.x >= rect.position.x and me.x <= rect.end.x and me.y <= rect.end.y and me.y >= rect.position.y - BODY_RADIUS):
			# Out the nearer side, unless the other has more ground past
			# the danger to stand on: fleeing a rock towards an edge is
			# fleeing off the stage.
			var away: float = signf(me.x - rect.get_center().x)
			if away == 0.0:
				away = 1.0
			if mode == "flee" and _flee_side != 0.0:
				away = _flee_side
			var out: float = rect.end.x - me.x if away > 0.0 else me.x - rect.position.x
			if not (mode == "flee" and _flee_side != 0.0):
				var out_other: float = rect.size.x - out
				var room: float = _edge_room(away, out + FLEE_DISTANCE, true) - out
				var room_other: float = _edge_room(-away, out_other + FLEE_DISTANCE, true) - out_other
				if room < FLEE_DISTANCE and room_other > room:
					away = -away
					out = out_other
			_flee_side = away
			return Vector2(me.x + away * (out + EDGE_KEEP), me.y)
	_flee_side = 0.0
	var kind: int = _standing_on()
	if kind == FOOT_SOLID:
		return Vector2.INF
	# Over nothing (or ground giving way), or on ground that will not last:
	# to the nearest solid ground either way, if there is any near enough.
	var best: float = INF
	for side: float in [1.0, -1.0]:
		var d: float = SCAN_STEP
		while d <= SOLID_SEARCH:
			if _footing(me + Vector2(side * d, 0.0)) == FOOT_SOLID:
				if d < absf(best):
					best = side * d
				break
			d += SCAN_STEP
	if best == INF:
		return Vector2.INF
	return Vector2(me.x + best + signf(best) * EDGE_KEEP, me.y)

## The nearest bounce pad on the bot's own floor that it can walk to, when
## the target is high above (issue #176): the pad is the way up. The bot
## runs onto it and the launch keeps its run. Vector2.INF when there is none.
func _pad_towards(high: Vector2) -> Vector2:
	if _pads.is_empty() or _standing_on() != FOOT_SOLID:
		return Vector2.INF
	var me: Vector2 = player.global_position
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(me, me + Vector2(0.0, GROUND_PROBE), LAYER_WORLD, _player_rids())
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return Vector2.INF
	var floor_y: float = (hit["position"] as Vector2).y
	var best: Vector2 = Vector2.INF
	for pad: Node2D in _pads:
		if not is_instance_valid(pad) or not pad.is_inside_tree():
			continue
		var at: Vector2 = pad.global_position
		if absf(at.y - floor_y) > PAD_FLOOR_SLACK or absf(at.x - me.x) > PAD_SEARCH:
			continue
		if absf(at.x - me.x) >= absf(best.x - me.x):
			continue
		_pad_route = true
		var reachable: bool = _walkable_to(at.x)
		_pad_route = false
		if reachable:
			best = at
	return best

## No real progress towards the goal for STUCK_SEC and the bot wiggles.
func _track_progress(delta: float) -> void:
	if _wiggle_left > 0.0:
		_wiggle_left -= delta
		return
	# Waiting at an edge on purpose is not being stuck: a wiggle there is
	# how a bot used to hop off it (issue #176).
	if mode == "move" and _held_at_edge:
		_edge_wait += delta
	else:
		_edge_wait = 0.0
	if (mode != "move" and mode != "flee") or _held_at_edge:
		_progress_from = player.global_position
		_progress_left = STUCK_SEC
		return
	_progress_left -= delta
	if player.global_position.distance_to(_progress_from) > STUCK_DISTANCE:
		_progress_from = player.global_position
		_progress_left = STUCK_SEC
	elif _progress_left <= 0.0:
		_wiggle_left = WIGGLE_SEC
		_progress_left = STUCK_SEC

## The top of the stage's floor kill zone, or INF where there is none.
func _lava_top() -> float:
	if _lava != null and (not is_instance_valid(_lava) or not _lava.is_inside_tree()):
		_lava = null
	if _lava == null and not _lava_looked_up:
		_lava_looked_up = true
		lava_lookups += 1
		for node: Node in player.get_tree().root.find_children("KillZone", "Area2D", true, false):
			if node.has_method("is_rising"):
				_lava = node as Area2D
				break
		_read_stage()
	if _lava == null:
		return INF
	return _lava.global_position.y + _lava_top_offset()

## The stage's other hazards, read with the lava once a life (issue #176):
## its hazard zones (KillZone areas other than the lava), falling rocks and
## bounce pads. The stage is the lava's parent; with no lava there is no
## stage to read.
func _read_stage() -> void:
	_hazard_rects.clear()
	_rocks.clear()
	_pads.clear()
	_saws.clear()
	_gusts.clear()
	_danger_frame = -1
	if _lava == null or _lava.get_parent() == null:
		return
	for node: Node in _lava.get_parent().find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script == KillZoneScript and node != _lava:
			var rect: Rect2 = _zone_rect(node as Area2D)
			if rect.has_area():
				_hazard_rects.append(rect.grow(HAZARD_MARGIN))
		elif script == FallingRockScript:
			_rocks.append(node as Node2D)
		elif script == BouncePadScript:
			_pads.append(node as Node2D)
		elif avoid_damage_hazards and script == SpikesScript:
			var spikes := node as Node2D
			var size: Vector2 = (spikes.get("size") as Vector2) * spikes.global_scale.abs()
			_hazard_rects.append(Rect2(spikes.global_position - size * 0.5, size).grow(HAZARD_MARGIN + BODY_RADIUS))
		elif avoid_damage_hazards and script == SawScript:
			_saws.append(node as Node2D)
		elif node is Node2D and node.has_method("is_warning") and node.has_method("gust_direction"):
			_gusts.append(node as Node2D)

## A zone's rectangle shape in world space (unrotated, as stages place them).
func _zone_rect(zone: Area2D) -> Rect2:
	for child: Node in zone.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape is RectangleShape2D:
			var shape := child as CollisionShape2D
			var size: Vector2 = (shape.shape as RectangleShape2D).size * zone.global_scale.abs()
			return Rect2(shape.global_position - size * 0.5, size)
	return Rect2()

## The zone's surface relative to its node, the way KillZone draws it.
func _lava_top_offset() -> float:
	for child: Node in _lava.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape is RectangleShape2D:
			var shape := child as CollisionShape2D
			return shape.position.y - (shape.shape as RectangleShape2D).size.y * 0.5
	return -20.0

## Issue #313: the side that is upwind of a stage gust now warning or blowing,
## or 0. A gust part is found by duck typing: `is_warning()` and
## `gust_direction()` (a Vector2 or a float along x), and, where it has one,
## `is_active()`. A bot already fleeing a danger keeps to that.
func _gust_side() -> float:
	for gust: Node2D in _gusts:
		if not is_instance_valid(gust) or not gust.is_inside_tree():
			continue
		var live: bool = bool(gust.call("is_warning"))
		if not live and gust.has_method("is_active"):
			live = bool(gust.call("is_active"))
		if not live:
			continue
		var dir: Variant = gust.call("gust_direction")
		var x: float = (dir as Vector2).x if dir is Vector2 else float(dir)
		if absf(x) > 0.01:
			return -signf(x)
	return 0.0
