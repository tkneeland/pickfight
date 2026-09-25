extends StaticBody2D

## Breakable wall (issue #53): solid terrain that weapon strikes wear down,
## and that breaks for the rest of the round once they have done enough.
##
## **Damage is a strike's real damage.** Each weapon hit takes off exactly
## what the same hit would take off a player: the head's speed into the wall,
## scored by `Player._strike_damage`'s rule against the striking weapon's own
## `WeaponStats.damage`. So a hard axe swing counts for far more than a sword
## poke, a flick counts for a little, and a contact too slow to be a swing
## counts for nothing -- a wall can be leaned on, planted on and climbed
## without wearing it. The rule is re-stated here from `Player`'s own
## constants rather than called, because it is private to `Player` and
## `Player` is not this part's to change; `breakable_wall_breaks_on_weapon_hits`
## checks the two agree, so they cannot drift apart unnoticed.
##
## **Only heads.** A player's body is terrain-layer mass like any other and
## never damages the wall, however hard it is thrown at it: damage comes from
## the swing (ADR-0005), and a wall that broke when shoved would be a wall a
## player could barge through without swinging at all.
##
## **How a hit is seen.** A `StaticBody2D` reports no contacts, and a fast
## strike never produces a solver contact worth the name anyway -- the head
## stops itself against the wall in its own sweep (see `WeaponHead.swept_into`)
## before the solver sees anything. So this reads the heads rather than
## waiting to be told:
##   - swept strikes: every live head (`WeaponHead.HEAD_GROUP`) is checked for
##     `swept_into == self`, which the head sets with the speed it arrived at.
##     `Player` clears that field in its own `_physics_process`, so this part
##     runs its tick first (`process_physics_priority`) to see it. It is read,
##     never cleared, so the owning player's own bookkeeping is untouched.
##   - slow strikes the solver did see: a head newly touching the wall, scored
##     on its velocity into the wall going into the step it touched on --
##     the same "arrived with" speed `Player._on_head_hit` scores.
## The striking weapon's stats come from the head's owner: the one player
## the head holds a collision exception for, which is how `Player` lets its
## own head pass through its own body.
##
## **Breaking.** HP starts at `hp` and never recovers. Cracks appear and the
## wall darkens as it drops, so a player can see how close it is. At zero it
## flashes white for `BREAK_FLASH_SEC` -- still solid, so the break reads
## before anything falls through -- then its collision goes off and it is
## gone for the round. Never freed and re-instanced mid-round: "broken" is
## this same node with its `CollisionShape2D` disabled and its visual hidden.
##
## Exports, and only these: a stage author sets numbers and never edits the
## sub-resources `_ready()` builds from them.
@export var size: Vector2 = Vector2(32, 200)
## Strike damage the wall absorbs before it breaks. 100 is three full-speed
## pickaxe strikes (34 each, `Player.FULL_STRIKE_SPEED`), two from an axe.
@export var hp: float = 100.0

const PlayerType := preload("res://scripts/Player.gd")
const WeaponHeadType := preload("res://scripts/WeaponHead.gd")

enum _WallState { STANDING, BREAKING, BROKEN }

## A warmer, lighter stone than the grey-blue permanent terrain, so a wall
## that can be broken never passes for one that cannot.
const INTACT_COLOR: Color = Color(0.62, 0.52, 0.42, 1)
## What the wall darkens toward as its HP runs out.
const WORN_COLOR: Color = Color(0.3, 0.22, 0.16, 1)
const CRACK_COLOR: Color = Color(0.12, 0.08, 0.05, 1)
const FLASH_COLOR: Color = Color(1, 1, 1, 1)
const BREAK_FLASH_SEC: float = 0.12
## Cracks appear at these fractions of HP lost, one each.
const CRACK_THRESHOLDS: PackedFloat32Array = [0.2, 0.45, 0.7]
## Runs before `Player` (priority 0), which clears `WeaponHead.swept_into`.
const _BEFORE_PLAYERS: int = -10

var _state: _WallState = _WallState.STANDING
var _hp_left: float = 0.0
var _flash_remaining: float = 0.0
var _collision_shape: CollisionShape2D
var _visual: Polygon2D
var _cracks: Array[Line2D] = []
## Per head (instance id): its velocity going into this tick's step, and
## whether it was touching the wall (by contact or by sweep) last tick.
var _head_velocity: Dictionary = {}
var _head_touching: Dictionary = {}
var _hits: int = 0
var _last_hit_damage: float = 0.0
var _last_hit_speed: float = 0.0

## Damage that plays a wall hit at full strength (#76): a committed swing.
const WALL_HIT_FULL_DAMAGE: float = 60.0

func _ready() -> void:
	_hp_left = hp
	process_physics_priority = _BEFORE_PLAYERS
	var half: Vector2 = size / 2.0

	var rect := RectangleShape2D.new()
	rect.size = size
	_collision_shape = CollisionShape2D.new()
	_collision_shape.name = "CollisionShape2D"
	_collision_shape.shape = rect
	add_child(_collision_shape)

	_visual = Polygon2D.new()
	_visual.name = "Visual"
	_visual.color = INTACT_COLOR
	_visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	add_child(_visual)
	for i in CRACK_THRESHOLDS.size():
		var crack := Line2D.new()
		crack.name = "Crack%d" % i
		crack.width = 3.0
		crack.default_color = CRACK_COLOR
		crack.points = _crack_points(i, half)
		crack.visible = false
		_visual.add_child(crack)
		_cracks.append(crack)

# --- Observable seams for scenarios -----------------------------------------

## HP remaining; 0 once broken.
func hp_left() -> float:
	return _hp_left

## "standing", "breaking" (the flash) or "broken".
func state_name() -> String:
	return ["standing", "breaking", "broken"][_state]

func is_broken() -> bool:
	return _state == _WallState.BROKEN

## Whether the wall's collision is on, read off the shape itself.
func is_solid() -> bool:
	return not _collision_shape.disabled

func visual_color() -> Color:
	return _visual.color if _visual.visible else Color(0, 0, 0, 0)

func visible_crack_count() -> int:
	return _cracks.filter(func(c: Line2D) -> bool: return c.visible).size()

## Damaging and non-damaging head hits counted so far, and the last one's
## damage and scored speed.
func hit_count() -> int:
	return _hits

func last_hit_damage() -> float:
	return _last_hit_damage

func last_hit_speed() -> float:
	return _last_hit_speed

# --- Cycle ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	match _state:
		_WallState.STANDING:
			_read_heads()
		_WallState.BREAKING:
			_flash_remaining -= delta
			if _flash_remaining <= 0.0:
				_state = _WallState.BROKEN
				_visual.visible = false
				# Deferred, as in CrumblingLedge: collision toggles mid-step
				# are refused, and deferred is correct from anywhere.
				_collision_shape.set_deferred("disabled", true)
				set_physics_process(false)

func _read_heads() -> void:
	var seen: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group(WeaponHeadType.HEAD_GROUP):
		var head := node as RigidBody2D
		if head == null or head.collision_layer == 0:
			continue
		var id: int = head.get_instance_id()
		seen[id] = true
		# A hit is the tick contact *starts*, by either route, so one strike
		# is never scored twice -- and a swept field that somehow went
		# uncleared is not scored every tick.
		var swept: bool = head.get("swept_into") == self
		var touching: bool = swept or head.get_colliding_bodies().has(self)
		var was_touching: bool = _head_touching.get(id, false)
		_head_touching[id] = touching
		var arrived: Vector2 = _head_velocity.get(id, Vector2.ZERO)
		_head_velocity[id] = head.linear_velocity
		if touching and not was_touching:
			var speed: float = float(head.get("swept_speed")) if swept else _into_speed(head, arrived)
			_take_hit(head, speed)
			if _state != _WallState.STANDING:
				return
	# Forget heads that have gone: rigs are rebuilt on every weapon swap and
	# every round, so ids would otherwise pile up.
	for id: int in _head_velocity.keys():
		if not seen.has(id):
			_head_velocity.erase(id)
			_head_touching.erase(id)

## The part of `velocity` heading into the wall at `head`'s position: along
## the direction from the head to the nearest point of the wall's rectangle.
func _into_speed(head: Node2D, velocity: Vector2) -> float:
	var local: Vector2 = to_local(head.global_position)
	var half: Vector2 = size / 2.0
	var nearest: Vector2 = Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
	var toward: Vector2 = to_global(nearest) - head.global_position
	if toward.length_squared() < 0.0001:
		# Already inside: fall back to straight at the centre.
		toward = global_position - head.global_position
	if toward.length_squared() < 0.0001:
		return 0.0
	return maxf(velocity.dot(toward.normalized()), 0.0)

func _take_hit(head: RigidBody2D, speed: float) -> void:
	var stats: Resource = _owner_stats(head)
	_absorb(strike_damage(stats, speed), speed)

## A boomstick bullet that meets the wall (owner decision on #53): it takes
## the bullet's flat damage, the same as a player would. Called by
## `Projectile._hit`; the bullet is spent either way.
func take_projectile_hit(amount: float) -> void:
	if not is_solid():
		return
	_absorb(amount, 0.0)

func _absorb(amount: float, speed: float) -> void:
	_hits += 1
	_last_hit_speed = speed
	_last_hit_damage = amount
	if amount <= 0.0:
		return
	_hp_left = maxf(_hp_left - amount, 0.0)
	_show_wear()
	if _hp_left > 0.0:
		_sfx(&"wall_hit", global_position, amount / WALL_HIT_FULL_DAMAGE)
	elif _state == _WallState.STANDING:
		_sfx(&"wall_break", global_position)
	if _hp_left <= 0.0:
		_state = _WallState.BREAKING
		_flash_remaining = BREAK_FLASH_SEC
		_visual.color = FLASH_COLOR
		for crack: Line2D in _cracks:
			crack.visible = false

## What a strike at `speed` from a weapon with `stats` deals: `Player`'s rule,
## restated from its constants (see the header).
static func strike_damage(stats: Resource, speed: float) -> float:
	if stats == null:
		return 0.0
	var over: float = speed - PlayerType.MIN_STRIKE_SPEED
	if over <= 0.0:
		return 0.0
	var strike_scale: float = minf(over / (PlayerType.FULL_STRIKE_SPEED - PlayerType.MIN_STRIKE_SPEED), PlayerType.MAX_STRIKE_SCALE)
	return minf(float(stats.get("damage")) * strike_scale, PlayerType.MAX_STRIKE_DAMAGE)

## The weapon stats of whoever holds `head`: the player it holds a collision
## exception for (see the header).
func _owner_stats(head: RigidBody2D) -> Resource:
	for body: PhysicsBody2D in head.get_collision_exceptions():
		if body.is_in_group(&"players"):
			return body.get("weapon_stats")
	return null

func _show_wear() -> void:
	var lost: float = 1.0 - _hp_left / maxf(hp, 0.001)
	_visual.color = INTACT_COLOR.lerp(WORN_COLOR, clampf(lost, 0.0, 1.0))
	for i in _cracks.size():
		_cracks[i].visible = lost >= CRACK_THRESHOLDS[i]

## A zig-zag crack across the wall. Fixed shapes, laid out along the wall's
## long axis so they spread over it whichever way it is authored.
func _crack_points(index: int, half: Vector2) -> PackedVector2Array:
	var along_y: bool = half.y >= half.x
	var long: float = half.y if along_y else half.x
	var short: float = half.x if along_y else half.y
	var centre: float = lerpf(-long * 0.6, long * 0.6, float(index) / maxf(CRACK_THRESHOLDS.size() - 1, 1))
	var offsets: PackedFloat32Array = [-1.0, -0.35, 0.3, 1.0]
	var zig: PackedFloat32Array = [0.0, 0.18, -0.14, 0.1]
	var points := PackedVector2Array()
	for j in offsets.size():
		var across: float = offsets[j] * short * 0.95
		var along: float = centre + zig[j] * long * (1.0 if index % 2 == 0 else -1.0)
		points.append(Vector2(across, along) if along_y else Vector2(along, across))
	return points

## Asks the Sfx autoload for `sound` (issue #76). Looked up by path, never by
## name, so this part still works in a tree without the autoload.
func _sfx(sound: StringName, at: Vector2, strength: float = 1.0) -> void:
	var sfx: Node = get_node_or_null(^"/root/Sfx")
	if sfx != null:
		sfx.play(sound, at, strength)
