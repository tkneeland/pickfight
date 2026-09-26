extends Node2D

## Code-drawn impact juice (issue #116): a dust puff where a body lands hard,
## a short fading trail behind a weapon head swung fast, and sparks where two
## heads clash. No assets, like `DeathBurst.gd`.
##
## Built the way `HitFeedback.gd` and `SfxHooks.gd` are: it watches the tree
## for the nodes that emit events and connects to their signals, so `Player`
## and `WeaponHead` never learn it exists. Nodes are recognised by the signals
## they carry, never by `class_name` (CLAUDE.md): `strike_landed` and
## `eliminated` is a player, `struck_world` and `clashed` is a weapon head.
##
## **No per-event allocation (issue #108).** Every effect lives in this one
## node's fixed pools, sized in `_ready`: a landing or a clash writes into
## ring-buffer slots, it never spawns a node or grows an array. When the
## particle pool is full the oldest particle is overwritten; a trail keeps at
## most `TRAIL_POINTS` points; at most `MAX_TRAILS` heads trail at once. A
## head that finds every slot taken waits in `_t_waiting` and claims the next
## slot to come free (issue #168), so a weapon swap or a crowded round never
## leaves a head trail-less for good. The node redraws only while something
## is on screen.
##
## Lives in world space, like `HitFeedback`. Animated per rendered frame, so
## physics interpolation is off for it; trails follow the head's *rendered*
## (interpolated) position, which it reconstructs from the last two ticks.

enum Kind { DUST, SPARK }

## --- Particles (dust and sparks share one pool) ---
const MAX_PARTICLES: int = 96

## Downward speed, px/s, a body has to arrive with for a dust puff. Well above
## `SfxHooks.LAND_MIN_SPEED` (350): every landing thuds, only a hard one puffs.
const DUST_MIN_SPEED: float = 600.0
## Speed at which the puff is at its biggest.
const DUST_FULL_SPEED: float = 1400.0
const DUST_PER_PUFF: int = 8
const DUST_LIFETIME: float = 0.45
const DUST_SPEED_MIN: float = 60.0
const DUST_SPEED_MAX: float = 190.0
const DUST_RADIUS_START: float = 5.0
const DUST_RADIUS_END: float = 14.0
## Horizontal drag on dust, per second, so the puff billows out and stops.
const DUST_DRAG: float = 5.0
const DUST_COLOR: Color = Color(0.86, 0.82, 0.74, 0.75)
## Where a landing puffs: the bottom of the body. Player's radius.
const BODY_RADIUS: float = 24.0
const LAND_COOLDOWN_FRAMES: int = 10

## Closing speed, px/s, below which two heads meeting throw no sparks (a
## settled clash leaning on itself), and the speed that throws the most.
const SPARK_MIN_SPEED: float = 300.0
const SPARK_FULL_SPEED: float = 2500.0
const SPARKS_MIN: int = 5
const SPARKS_MAX: int = 12
const SPARK_LIFETIME: float = 0.28
const SPARK_SPEED_MIN: float = 220.0
const SPARK_SPEED_MAX: float = 620.0
const SPARK_GRAVITY: float = 900.0
const SPARK_LENGTH: float = 10.0
const SPARK_HOT: Color = Color(1.0, 0.97, 0.75, 1.0)
const SPARK_COOL: Color = Color(1.0, 0.55, 0.12, 1.0)
const HEAD_COOLDOWN_FRAMES: int = 5

## --- Trails ---
const MAX_TRAILS: int = 8
const TRAIL_POINTS: int = 10
## Head speed, px/s, above which it leaves a trail. A committed swing runs
## 1500-3000; aiming and resting sit far below.
const TRAIL_MIN_SPEED: float = 1100.0
## How long a trail point stays visible.
const TRAIL_LIFETIME: float = 0.12
const TRAIL_WIDTH: float = 9.0
const TRAIL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.55)
## A head moving further than this in one tick was teleported (a respawn),
## not swung: its trail is cut rather than streaked across the stage.
const TRAIL_MAX_JUMP: float = 160.0

const META_WATCHED: StringName = &"_juice_watched"
const PRUNE_AT: int = 256
const PRUNE_AFTER_FRAMES: int = 600

## Particle pool, struct-of-arrays. `_p_life <= 0` is a free slot.
var _p_pos := PackedVector2Array()
var _p_vel := PackedVector2Array()
var _p_age := PackedFloat32Array()
var _p_life := PackedFloat32Array()
var _p_kind := PackedByteArray()
var _p_next: int = 0
var _p_active: int = 0

## Trail slots. `_t_head[i]` null is a free slot. Per slot: the head's last
## two tick positions, and a ring of `TRAIL_POINTS` points with their birth
## time, flattened into slot * TRAIL_POINTS + j.
## Untyped on purpose: a freed head must be readable back out to be noticed.
var _t_head: Array = []
var _t_prev := PackedVector2Array()
var _t_curr := PackedVector2Array()
var _t_fast := PackedByteArray()
var _t_pts := PackedVector2Array()
var _t_born := PackedFloat32Array()
var _t_count := PackedInt32Array()
var _t_next := PackedInt32Array()
## Heads that found every slot taken, oldest first; each claims the next slot
## that comes free. Untyped for the same reason as `_t_head`. Grows only when
## a head is added to the tree, never per tick or per strike.
var _t_waiting: Array = []

var _players: Array[Node] = []
## instance id -> linear velocity at the start of this physics step.
var _velocity_before: Dictionary = {}
## instance id -> physics frame the source last made an effect on.
var _last_frame: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## Seconds since start, for trail point ages.
var _clock: float = 0.0
## Redraw once more after the last effect ends, to clear it.
var _drew_last_frame: bool = false

func _ready() -> void:
	z_index = 95
	# Animated per rendered frame; nothing here for interpolation to blend,
	# and it would only draw every effect a tick late (issue #108).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Before every game node, so a body's velocity is read before the step
	# that may land it, and heads' positions right after the last step.
	process_physics_priority = -100
	_rng.randomize()
	_p_pos.resize(MAX_PARTICLES)
	_p_vel.resize(MAX_PARTICLES)
	_p_age.resize(MAX_PARTICLES)
	_p_life.resize(MAX_PARTICLES)
	_p_kind.resize(MAX_PARTICLES)
	_p_life.fill(0.0)
	_t_head.resize(MAX_TRAILS)
	_t_prev.resize(MAX_TRAILS)
	_t_curr.resize(MAX_TRAILS)
	_t_fast.resize(MAX_TRAILS)
	_t_count.resize(MAX_TRAILS)
	_t_next.resize(MAX_TRAILS)
	_t_pts.resize(MAX_TRAILS * TRAIL_POINTS)
	_t_born.resize(MAX_TRAILS * TRAIL_POINTS)
	get_tree().node_added.connect(_on_node_added)
	_watch_subtree(get_tree().root)

# --- Read-only hooks for the scenario suite -----------------------------------

func active_particle_count(kind: int = -1) -> int:
	var n: int = 0
	for i in MAX_PARTICLES:
		if _p_life[i] > 0.0 and (kind < 0 or _p_kind[i] == kind):
			n += 1
	return n

## Visible points in `head`'s trail, 0 if it has none.
func trail_point_count(head: Node) -> int:
	var slot: int = _t_head.find(head)
	return 0 if slot < 0 else _live_points(slot)

## Heads holding a trail slot.
func trail_count() -> int:
	var n: int = 0
	for s in MAX_TRAILS:
		if _slot_held(s):
			n += 1
	return n

## Whether `head` holds a trail slot right now.
func holds_trail(head: Node) -> bool:
	var slot: int = _t_head.find(head)
	return slot >= 0 and _slot_held(slot)

# --- Watching -----------------------------------------------------------------

func _watch_subtree(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_watch_subtree(child)

func _on_node_added(node: Node) -> void:
	if node.has_meta(META_WATCHED):
		return
	if node.has_signal("strike_landed") and node.has_signal("eliminated"):
		if node.has_signal("body_entered"):
			node.connect("body_entered", _on_player_touched.bind(node))
		_players.append(node)
	elif node.has_signal("struck_world") and node.has_signal("clashed"):
		# A head that left the tree and came back is re-watched, and is
		# already connected.
		var on_clash: Callable = _on_head_clashed.bind(node)
		if not node.is_connected("clashed", on_clash):
			node.connect("clashed", on_clash)
		if not _claim_trail(node as Node2D) and not _t_waiting.has(node):
			_t_waiting.append(node)
	else:
		return
	node.set_meta(META_WATCHED, true)

## Whether slot `s` belongs to a head still in play. A head queued for
## deletion is already gone: `Player._clear_rig()` retires the old head and
## builds the new one in the same frame, and the new one must be able to take
## the old one's slot then, not a frame later when nothing retries (#168).
func _slot_held(s: int) -> bool:
	var head: Variant = _t_head[s]
	return is_instance_valid(head) and not (head as Node).is_queued_for_deletion()

## Gives `head` the first free slot. False when every slot is held: the
## caller queues it in `_t_waiting` for the next slot to come free.
func _claim_trail(head: Node2D) -> bool:
	if head == null:
		return true
	for i in MAX_TRAILS:
		if not _slot_held(i):
			_t_head[i] = head
			_t_count[i] = 0
			_t_next[i] = 0
			_t_fast[i] = 0
			var at: Vector2 = head.global_position if head.is_inside_tree() else head.position
			_t_prev[i] = at
			_t_curr[i] = at
			return true
	return false

## Hands freed slots to waiting heads, oldest first. Heads freed while
## waiting are dropped; ones out of the tree or on their way out keep waiting
## until they are back or gone.
func _serve_waiting() -> void:
	var i: int = 0
	while i < _t_waiting.size():
		var head: Variant = _t_waiting[i]
		if not is_instance_valid(head) or (head as Node).is_queued_for_deletion():
			_t_waiting.remove_at(i)
			continue
		if (head as Node2D).is_inside_tree():
			if not _claim_trail(head as Node2D):
				return
			_t_waiting.remove_at(i)
			continue
		i += 1

# --- Per tick -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _velocity_before.size() > _players.size() * 4 + 16:
		_velocity_before.clear()
	var i: int = _players.size() - 1
	while i >= 0:
		var player: Node = _players[i]
		if is_instance_valid(player) and player.is_inside_tree():
			_velocity_before[player.get_instance_id()] = player.get("linear_velocity")
		elif not is_instance_valid(player):
			_players.remove_at(i)
		i -= 1
	var fast_sq: float = TRAIL_MIN_SPEED * TRAIL_MIN_SPEED
	var jump_sq: float = TRAIL_MAX_JUMP * TRAIL_MAX_JUMP
	for s in MAX_TRAILS:
		var head: Variant = _t_head[s]
		if head == null:
			continue
		if not _slot_held(s) or not (head as Node2D).is_inside_tree():
			# The head is gone (round over, weapon swapped): free the slot.
			# A head merely out of the tree may come back; it re-claims then.
			if _slot_held(s):
				(head as Node).remove_meta(META_WATCHED)
			_t_head[s] = null
			_t_count[s] = 0
			continue
		var now: Vector2 = (head as Node2D).global_position
		_t_prev[s] = _t_curr[s]
		_t_curr[s] = now
		if now.distance_squared_to(_t_prev[s]) > jump_sq:
			_t_prev[s] = now
			_t_count[s] = 0
			_t_fast[s] = 0
			continue
		var v: Vector2 = (now - _t_prev[s]) / maxf(delta, 0.0001)
		_t_fast[s] = 1 if v.length_squared() >= fast_sq else 0
	# After the loop above has let go of every slot whose head is gone.
	if not _t_waiting.is_empty():
		_serve_waiting()

# --- Per rendered frame -----------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	var busy: bool = _step_particles(delta)
	var frac: float = Engine.get_physics_interpolation_fraction() \
		if get_tree().physics_interpolation else 1.0
	for s in MAX_TRAILS:
		if _t_head[s] == null:
			continue
		if _t_fast[s] == 1:
			var at: Vector2 = _t_prev[s].lerp(_t_curr[s], frac)
			var k: int = s * TRAIL_POINTS + _t_next[s]
			_t_pts[k] = at
			_t_born[k] = _clock
			_t_next[s] = (_t_next[s] + 1) % TRAIL_POINTS
			_t_count[s] = mini(_t_count[s] + 1, TRAIL_POINTS)
		if _live_points(s) > 0:
			busy = true
		else:
			_t_count[s] = 0
	if busy or _drew_last_frame:
		queue_redraw()
	_drew_last_frame = busy

func _step_particles(delta: float) -> bool:
	if _p_active == 0:
		return false
	var active: int = 0
	for i in MAX_PARTICLES:
		if _p_life[i] <= 0.0:
			continue
		_p_age[i] += delta
		if _p_age[i] >= _p_life[i]:
			_p_life[i] = 0.0
			continue
		active += 1
		var v: Vector2 = _p_vel[i]
		if _p_kind[i] == Kind.SPARK:
			v.y += SPARK_GRAVITY * delta
		else:
			v *= maxf(0.0, 1.0 - DUST_DRAG * delta)
		_p_vel[i] = v
		_p_pos[i] += v * delta
	_p_active = active
	return true

func _live_points(slot: int) -> int:
	var n: int = 0
	var base: int = slot * TRAIL_POINTS
	for j in _t_count[slot]:
		if _clock - _t_born[base + j] < TRAIL_LIFETIME:
			n += 1
	return n

# --- Events ---------------------------------------------------------------------

## A body meeting anything that is not another player, moving down fast
## enough to be a hard landing. Judged on the velocity going into the step,
## as `SfxHooks` does: by the time contact is reported, it has stopped.
func _on_player_touched(other: Node, player: Node) -> void:
	if other.is_in_group("players") or not bool(player.get("alive")):
		return
	var before: Vector2 = _velocity_before.get(player.get_instance_id(), Vector2.ZERO)
	if before.y < DUST_MIN_SPEED or not _off_cooldown(player, LAND_COOLDOWN_FRAMES):
		return
	var strength: float = clampf((before.y - DUST_MIN_SPEED) / (DUST_FULL_SPEED - DUST_MIN_SPEED), 0.0, 1.0)
	var feet: Vector2 = (player as Node2D).global_position + Vector2(0.0, BODY_RADIUS)
	for i in DUST_PER_PUFF:
		# Half left, half right, low along the floor with a little lift.
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var angle: float = _rng.randf_range(0.0, 0.55)
		var speed: float = _rng.randf_range(DUST_SPEED_MIN, DUST_SPEED_MAX) * (0.6 + 0.6 * strength)
		var vel := Vector2(side * cos(angle), -sin(angle)) * speed
		_emit(Kind.DUST, feet + Vector2(side * _rng.randf_range(0.0, 10.0), -2.0), vel,
			DUST_LIFETIME * _rng.randf_range(0.8, 1.1))

## Two heads meeting at speed. `WeaponHead` reports a clash once, from the
## head that corrects the pair.
func _on_head_clashed(speed: float, point: Vector2, head: Node) -> void:
	if speed < SPARK_MIN_SPEED or not _off_cooldown(head, HEAD_COOLDOWN_FRAMES):
		return
	var strength: float = clampf((speed - SPARK_MIN_SPEED) / (SPARK_FULL_SPEED - SPARK_MIN_SPEED), 0.0, 1.0)
	var count: int = roundi(lerpf(SPARKS_MIN, SPARKS_MAX, strength))
	for i in count:
		var angle: float = TAU * float(i) / float(count) + _rng.randf_range(-0.35, 0.35)
		var vel := Vector2.RIGHT.rotated(angle) * _rng.randf_range(SPARK_SPEED_MIN, SPARK_SPEED_MAX) * (0.7 + 0.5 * strength)
		_emit(Kind.SPARK, point, vel, SPARK_LIFETIME * _rng.randf_range(0.7, 1.15))

## Writes one particle into the next pool slot, overwriting the oldest when
## the pool is full. Never allocates.
func _emit(kind: int, pos: Vector2, vel: Vector2, life: float) -> void:
	var i: int = _p_next
	_p_next = (_p_next + 1) % MAX_PARTICLES
	_p_pos[i] = pos
	_p_vel[i] = vel
	_p_age[i] = 0.0
	_p_life[i] = life
	_p_kind[i] = kind
	_p_active = mini(_p_active + 1, MAX_PARTICLES)

func _off_cooldown(source: Node, frames: int) -> bool:
	var id: int = source.get_instance_id()
	var now: int = Engine.get_physics_frames()
	if _last_frame.has(id) and now - int(_last_frame[id]) < frames:
		return false
	if _last_frame.size() > PRUNE_AT:
		for key: int in _last_frame.keys():
			if now - int(_last_frame[key]) > PRUNE_AFTER_FRAMES:
				_last_frame.erase(key)
	_last_frame[id] = now
	return true

# --- Drawing --------------------------------------------------------------------

func _draw() -> void:
	# World space: undo this node's own transform, in case it is ever moved.
	draw_set_transform_matrix(get_global_transform().affine_inverse())
	for s in MAX_TRAILS:
		if _t_head[s] == null or _t_count[s] < 2:
			continue
		_draw_trail(s)
	for i in MAX_PARTICLES:
		if _p_life[i] <= 0.0:
			continue
		var t: float = _p_age[i] / _p_life[i]
		if _p_kind[i] == Kind.SPARK:
			var c: Color = SPARK_HOT.lerp(SPARK_COOL, t)
			c.a = 1.0 - t * t
			var tail: Vector2 = _p_vel[i].normalized() * SPARK_LENGTH * (1.0 - 0.6 * t)
			draw_line(_p_pos[i] - tail, _p_pos[i], c, 2.5, true)
		else:
			var c: Color = DUST_COLOR
			c.a *= (1.0 - t) * (1.0 - t)
			draw_circle(_p_pos[i], lerpf(DUST_RADIUS_START, DUST_RADIUS_END, 1.0 - (1.0 - t) * (1.0 - t)), c)

## Newest to oldest, each segment thinner and fainter with age.
func _draw_trail(s: int) -> void:
	var base: int = s * TRAIL_POINTS
	var j: int = (_t_next[s] - 1 + TRAIL_POINTS) % TRAIL_POINTS
	for n in _t_count[s] - 1:
		var k: int = (j - 1 + TRAIL_POINTS) % TRAIL_POINTS
		var age: float = _clock - _t_born[base + k]
		if age >= TRAIL_LIFETIME:
			return
		var fade: float = 1.0 - age / TRAIL_LIFETIME
		var c: Color = TRAIL_COLOR
		c.a *= fade
		draw_line(_t_pts[base + j], _t_pts[base + k], c, maxf(1.0, TRAIL_WIDTH * fade), true)
		j = k
