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
##
## Preloaded by path (CLAUDE.md), never referenced by a `class_name`.

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
## Input length while aiming a vault, and while holding the head in the air.
const AIM_LENGTH: float = 0.15
const AIR_LENGTH: float = 0.3
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
## How far ahead the bot checks for ground before vaulting sideways.
const EDGE_LOOKAHEAD: float = 150.0
## A gap is jumped when there is ground this far ahead beyond it.
const GAP_LOOKAHEAD: float = 320.0
## How close the lava may come below before the bot climbs instead.
const LAVA_WORRY: float = 280.0
## How often the lava is looked up, in seconds.
const LAVA_LOOKUP_SEC: float = 0.5
## No real progress for this long and the bot vaults somewhere at random for
## WIGGLE_SEC, to get out of whatever it is stuck in.
const STUCK_SEC: float = 1.6
const STUCK_DISTANCE: float = 30.0
const WIGGLE_SEC: float = 0.8
## A pickup is worth the detour, for a bot already holding a picked-up weapon,
## when it is this fraction of the distance to the nearest player or less.
const PICKUP_DETOUR: float = 0.5
const PICKAXE_PATH: String = "res://resources/pickaxe.tres"

## The `Player` this bot drives, and where its input goes.
var player: Node2D
var output: Callable = Callable()
## Seeds the few random choices, so a scenario can replay a bot exactly.
var rng := RandomNumberGenerator.new()

## What the bot is doing, for the scenarios: "idle", "move", "attack" or
## "back" (stepping away from someone too close to swing at), and the point
## it is heading for.
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
var _lava: Area2D = null
var _lava_lookup_at: int = 0

func _ready() -> void:
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
		return Vector2.ZERO
	_think_left -= delta
	if _think_left <= 0.0 or (_target != null and not _alive(_target)):
		_think_left = THINK_SEC
		_choose_goal()
	_track_progress(delta)
	if mode == "attack" and _alive(_target):
		return _swing(delta)
	return _vault(delta)

# --- Choosing a goal -------------------------------------------------------------

func _choose_goal() -> void:
	var me: Vector2 = player.global_position
	var enemy: Node2D = _nearest_enemy()
	var enemy_distance: float = me.distance_to(enemy.global_position) if enemy != null else INF
	var pickup: Node2D = _nearest_pickup()
	var pickup_distance: float = me.distance_to(pickup.global_position) if pickup != null else INF
	var lava_close: bool = _lava_worry()
	if enemy != null and enemy_distance < _reach() * CLOSE_FRACTION and not lava_close:
		# Too close to swing fast: a short lever moves the head slowly, and
		# a slow head does no damage. Step back out to a swinging distance,
		# unless there is no ground that way.
		var away: float = _safe_side(signf(me.x - enemy.global_position.x) if me.x != enemy.global_position.x else 1.0)
		if away != 0.0:
			mode = "back"
			_target = enemy
			goal = Vector2(me.x + away * BACK_OFF_DISTANCE, me.y)
			return
	if enemy != null and enemy_distance <= _reach() + BODY_RADIUS and not lava_close:
		if mode != "attack":
			_phase = 0
			_phase_left = SWING_SEC
		mode = "attack"
		_target = enemy
		goal = enemy.global_position
		return
	mode = "move"
	_target = null
	if pickup != null and (_holds_pickaxe() or pickup_distance < enemy_distance * PICKUP_DETOUR):
		goal = pickup.global_position
	elif enemy != null:
		_target = enemy
		goal = enemy.global_position
	else:
		goal = me
	if lava_close:
		goal = Vector2(goal.x, minf(goal.y, me.y - 300.0))

func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_distance: float = INF
	for other: Node in player.get_tree().get_nodes_in_group("players"):
		if other == player or not _alive(other):
			continue
		var d: float = player.global_position.distance_to((other as Node2D).global_position)
		if d < best_distance:
			best_distance = d
			best = other
	return best

## The nearest pickup with ground under it: one over open air is bait.
func _nearest_pickup() -> Node2D:
	var best: Node2D = null
	var best_distance: float = INF
	for pickup: Node in player.get_tree().get_nodes_in_group("pickups"):
		if not is_instance_valid(pickup) or pickup.is_queued_for_deletion() or not pickup.is_inside_tree():
			continue
		var at: Vector2 = (pickup as Node2D).global_position
		var d: float = player.global_position.distance_to(at)
		if d < best_distance and _over_ground(at):
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
	_phase_left -= delta
	if _phase_left <= 0.0:
		_phase = 1 - _phase
		_phase_left = SWING_SEC
	var angle: float = base + up_side * SWING_ABOVE if _phase == 0 else base - up_side * SWING_BELOW
	var length: float = _length_for(to_target.length() + BODY_RADIUS * 0.5)
	return Vector2.RIGHT.rotated(angle) * length

# --- Moving --------------------------------------------------------------------

## Vault towards `goal`: aim short at an anchor, then push out through it.
func _vault(delta: float) -> Vector2:
	_phase_left -= delta
	if _phase_left <= 0.0:
		_phase = 1 - _phase
		if _phase == 0:
			_phase_left = AIM_SEC
			_pick_anchor()
		else:
			_phase_left = PUSH_SEC
	if _phase == 0 or _airborne:
		return _anchor * _anchor_length
	return _anchor

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
	# The first one with ground to plant on. Where none has, the bot is in
	# the air: it holds the head short and low, ready to plant on landing,
	# without pogoing on it.
	_airborne = true
	for dir: Vector2 in candidates:
		if _ray_hits(me, me + dir * (_reach() + ANCHOR_SLACK)):
			_anchor = dir
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
	return _safe_side(side)

## `side`, or 0 where heading that way is open air with nothing to land on.
func _safe_side(side: float) -> float:
	var me: Vector2 = player.global_position
	if side != 0.0 and not _over_ground(me + Vector2(side * EDGE_LOOKAHEAD, 0.0)) \
			and not _over_ground(me + Vector2(side * GAP_LOOKAHEAD, 0.0)):
		return 0.0
	return side

## The side of the nearest clear column above the bot, preferring `side` on
## a tie; `side` itself if the whole scan is covered.
func _way_round_ceiling(side: float) -> float:
	var me: Vector2 = player.global_position
	var first: float = side if side != 0.0 else 1.0
	var step: float = CEILING_SCAN_STEP
	while step <= CEILING_SCAN_MAX:
		for s: float in [first, -first]:
			var x: Vector2 = me + Vector2(s * step, 0.0)
			if not _ray_hits(x, x + Vector2(0.0, -CEILING_PROBE)) and _over_ground(x):
				return s
		step += CEILING_SCAN_STEP
	return side

func _ray_hits(from: Vector2, to: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, LAYER_WORLD, _player_rids())
	return not space.intersect_ray(query).is_empty()

## Whether the lava is rising and close below.
func _lava_worry() -> bool:
	var top: float = _lava_top()
	if _lava == null or not bool(_lava.call("is_rising")):
		return false
	return top - player.global_position.y < LAVA_WORRY

func _player_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for other: Node in player.get_tree().get_nodes_in_group("players"):
		if other is CollisionObject2D:
			rids.append((other as CollisionObject2D).get_rid())
	return rids

## Whether there is ground under `point`, above the lava.
func _over_ground(point: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var bottom: float = minf(point.y + GROUND_PROBE, _lava_top())
	if bottom <= point.y:
		return false
	var query := PhysicsRayQueryParameters2D.create(point, Vector2(point.x, bottom), LAYER_WORLD, _player_rids())
	return not space.intersect_ray(query).is_empty()

## No real progress towards the goal for STUCK_SEC and the bot wiggles.
func _track_progress(delta: float) -> void:
	if _wiggle_left > 0.0:
		_wiggle_left -= delta
		return
	if mode != "move":
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
	var now: int = Time.get_ticks_msec()
	if _lava == null and now >= _lava_lookup_at:
		_lava_lookup_at = now + int(LAVA_LOOKUP_SEC * 1000.0)
		for node: Node in player.get_tree().root.find_children("KillZone", "Area2D", true, false):
			if node.has_method("is_rising"):
				_lava = node as Area2D
				break
	if _lava == null:
		return INF
	return _lava.global_position.y + _lava_top_offset()

## The zone's surface relative to its node, the way KillZone draws it.
func _lava_top_offset() -> float:
	for child: Node in _lava.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape is RectangleShape2D:
			var shape := child as CollisionShape2D
			return shape.position.y - (shape.shape as RectangleShape2D).size.y * 0.5
	return -20.0
