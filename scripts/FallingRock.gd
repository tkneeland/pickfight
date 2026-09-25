extends Node2D

## Falling rock stage part (issue #53): a rock drops down this node's column
## on a timer, and a player it lands on is hurt and knocked aside.
##
## Placed where the rock starts -- at the top of its column, usually just
## above the camera's top edge or under a ceiling. It falls straight down
## from there.
##
## **Warning first, always.** Nothing lethal arrives unannounced: for
## `warning_sec` before every drop the rock hangs shaking at the top of its
## column and a flashing crosshair marks where it will land -- on the first
## solid ground under the column, found fresh at the start of each warning
## so a floor that has collapsed or a platform that has moved is accounted
## for. A player who is watching always has `warning_sec` to step out.
##
## **Damage goes down the game's one hit path.** A rock hit is scored the way
## `Player._land_strike` scores a weapon strike: `take_damage()` on the
## victim, then `strike_landed` reporting it. There is no attacker, so the
## report is emitted on the victim's own `strike_landed` -- the victim as its
## own attacker. That one choice is what makes every consumer behave as it
## does for a weapon hit without any of them being edited: `HitFeedback`
## draws the hitmarker and damage number (in the victim's colour, red if it
## was lethal), and `RoundManager` buzzes the victim `struck` (ADR-0013). It
## also buzzes the same phone `hit`, as the "attacker"; the controller page
## drops a weaker buzz arriving while a stronger one plays, so the phone
## feels only `struck`. A future listener that credits hits to attackers
## sees attacker == victim, which no weapon strike ever produces, and can
## tell a stage hit from a real one by that alone.
##
## `damage` is flat, not speed-scaled: the rock always falls the same way,
## and a flat number is one a stage author can reason about. It stays well
## under `Player.DEATH_DAMAGE`, so a rock only finishes off a player who was
## already hurt -- a ring-out is the stage's lethal threat, not this.
##
## The knock is a velocity change straight onto the body -- sideways away
## from the column, with a little lift so ground friction does not eat it --
## because a hit that only changed a number would read as nothing happening.
##
## **One rock, reused.** Never freed and re-instanced mid-round: a stage part
## must not churn nodes. The rock is a child built once in `_ready()` and
## re-armed at the top of the column for every drop; between drops it is
## hidden and touches nothing.
##
## **A landed rock does not linger as terrain.** It shatters on the first
## solid thing it meets and is gone. Rocks that stayed would pile up into
## geometry no stage author designed -- walling off spawns, burying pickups,
## building stairs out of a pit -- and a rock that is both a hazard and a new
## ledge sends two opposite messages. The stage stays the stage; the rock is
## a thing that happens to it.
##
## **Not a physics body.** The rock is moved by this script and asks the
## physics server what it overlaps each tick (world layer only, so weapon
## heads -- layer 2 -- neither block nor are hit by it). A `RigidBody2D` rock
## would bounce off heads, be batted about, come to rest on players' heads,
## and settle wherever the solver liked; none of that is the part's job.
## Its fall speed is capped at `MAX_FALL_SPEED`, a step well under the rock's
## own diameter plus the thinnest thing it can land on, so it cannot step
## through a 24 px platform or a player between two ticks.
##
## Time is counted in physics ticks from `_ready()`: a stage is instanced
## fresh every round (ADR-0012), so "since this part entered the round" is
## round time, without asking `RoundManager` for it.
##
## Exports, and only these: a stage author sets numbers and never edits the
## sub-resources `_ready()` builds from them.

## Seconds between drops: from the part entering the round to the first
## warning, and from each rock's landing to the next warning.
@export var interval_sec: float = 6.0
## Seconds the rock hangs shaking, and its landing spot flashes, before it
## falls.
@export var warning_sec: float = 1.5
## Damage a rock deals a player it lands on -- a flat hit through
## `Player.take_damage()`.
@export var damage: float = 25.0
## The rock's radius, in pixels. Its drawn outline and its hit test are both
## built from this.
@export var rock_radius: float = 28.0
## How fast the knock sends a struck player, in px/s: sideways away from the
## column, with a little lift.
@export var shove_speed: float = 650.0

enum _RockState { IDLE, WARNING, FALLING, SHATTERED }

## Terrain-adjacent brown-grey: reads as a lump of the stage itself, not as
## a player, a pickup or lava.
const ROCK_COLOR: Color = Color(0.5, 0.42, 0.34, 1)
const ROCK_OUTLINE_COLOR: Color = Color(0.25, 0.2, 0.15, 1)
## The landing marker: the hazard red-orange of `scenes/parts/Hazard.tscn`,
## flashing, so it reads as "danger here" rather than as a decoration.
const MARKER_COLOR: Color = Color(0.95, 0.25, 0.05, 1)
const MARKER_PULSES_PER_SEC: float = 3.0
const MARKER_MIN_ALPHA: float = 0.25
## Shake amplitude of the hanging rock during the warning, and how fast.
const SHAKE_PX: float = 3.0
const SHAKE_HZ: float = 18.0
## Gravity the rock falls with, and the cap on its speed. At 1500 px/s the
## rock steps 25 px a tick at 60 Hz, less than the 2 x rock radius plus 24 px
## a thin platform needs it to step over.
const FALL_GRAVITY: float = 2400.0
const MAX_FALL_SPEED: float = 1500.0
## How far down the column the ground is looked for, and how far the rock
## falls with nothing under it before it is taken to have left the stage.
const MAX_FALL_DISTANCE: float = 4000.0
## How long the shattered rock takes to fade out where it landed.
const SHATTER_SEC: float = 0.25
## Where the lift of the knock comes from: the knock's direction is
## (away-from-column, -SHOVE_LIFT) normalised.
const SHOVE_LIFT: float = 0.35
## Mirrors `Player.LAYER_WORLD` -- terrain and player bodies. Preloading
## Player.gd for one integer would be a heavier coupling than it is worth,
## the same call `CrumblingLedge` makes.
const _WORLD_LAYER: int = 1
const _PLAYERS_GROUP: StringName = &"players"
const _ROCK_SIDES: int = 9

var _state: _RockState = _RockState.IDLE
var _timer_remaining: float = 0.0
var _fall_speed: float = 0.0
## Where the rock will land, in world space, found at the start of each
## warning. NAN.y when the column has nothing under it.
var _landing: Vector2 = Vector2(NAN, NAN)
var _warning_elapsed: float = 0.0
var _drops: int = 0
var _hits: int = 0

var _rock: Node2D
var _rock_visual: Polygon2D
var _marker: Node2D
var _query: PhysicsShapeQueryParameters2D

func _ready() -> void:
	_rock = Node2D.new()
	_rock.name = "Rock"
	_rock_visual = Polygon2D.new()
	_rock_visual.name = "RockVisual"
	_rock_visual.color = ROCK_COLOR
	_rock_visual.polygon = _rock_outline(rock_radius)
	_rock.add_child(_rock_visual)
	var outline := Line2D.new()
	outline.name = "RockOutline"
	outline.width = 3.0
	outline.default_color = ROCK_OUTLINE_COLOR
	outline.closed = true
	outline.points = _rock_visual.polygon
	_rock.add_child(outline)
	# Top-level so moving it down the column does not depend on where this
	# part sits in its parent, and so the part's own origin stays the column
	# top the author placed.
	_rock.top_level = true
	# Over the terrain it falls past and lands on, so neither the hanging
	# rock nor its landing marker can be hidden behind a platform.
	_rock.z_index = 5
	_rock.visible = false
	add_child(_rock)

	_marker = _build_marker()
	_marker.top_level = true
	_marker.z_index = 5
	_marker.visible = false
	add_child(_marker)

	var circle := CircleShape2D.new()
	circle.radius = rock_radius
	_query = PhysicsShapeQueryParameters2D.new()
	_query.shape = circle
	_query.collision_mask = _WORLD_LAYER
	_query.collide_with_areas = false
	_query.collide_with_bodies = true

	_state = _RockState.IDLE
	_timer_remaining = interval_sec

# --- Observable seams for scenarios -----------------------------------------

## "idle", "warning", "falling" or "shattered" -- the phase the rock is in.
func state_name() -> String:
	return ["idle", "warning", "falling", "shattered"][_state]

## Whether the warning is showing right now: the hanging rock and the
## landing marker are both visible.
func is_warning() -> bool:
	return _state == _RockState.WARNING and _marker.visible and _rock.visible

## Where the landing marker sits (world space), valid while warning. NAN.y
## when the column has no ground under it.
func landing_point() -> Vector2:
	return _landing

## The rock's world position -- the column top while idle or warning.
func rock_position() -> Vector2:
	return _rock.global_position

## Drops started and players hit since the part entered the round.
func drop_count() -> int:
	return _drops

func hit_count() -> int:
	return _hits

# --- Cycle ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	match _state:
		_RockState.IDLE:
			_timer_remaining -= delta
			if _timer_remaining <= 0.0:
				_begin_warning()
		_RockState.WARNING:
			_timer_remaining -= delta
			_warning_elapsed += delta
			_animate_warning()
			if _timer_remaining <= 0.0:
				_begin_fall()
		_RockState.FALLING:
			_fall(delta)
		_RockState.SHATTERED:
			_timer_remaining -= delta
			_rock_visual.modulate.a = clampf(_timer_remaining / SHATTER_SEC, 0.0, 1.0)
			if _timer_remaining <= 0.0:
				_rest()

func _begin_warning() -> void:
	_state = _RockState.WARNING
	_timer_remaining = warning_sec
	_warning_elapsed = 0.0
	_landing = _find_landing()
	_rock.global_position = global_position
	_rock_visual.modulate.a = 1.0
	_rock.visible = true
	# Over a pit there is no ground to mark, so the marker sits at the column
	# top under the shaking rock instead: the warning is never skipped.
	_marker.global_position = global_position if is_nan(_landing.y) else _landing
	_marker.visible = true
	_animate_warning()

func _animate_warning() -> void:
	var shake: float = sin(_warning_elapsed * TAU * SHAKE_HZ) * SHAKE_PX
	_rock.global_position = global_position + Vector2(shake, 0.0)
	var pulse: float = absf(cos(_warning_elapsed * PI * MARKER_PULSES_PER_SEC))
	_marker.modulate.a = lerpf(MARKER_MIN_ALPHA, 1.0, pulse)

func _begin_fall() -> void:
	_state = _RockState.FALLING
	_fall_speed = 0.0
	_drops += 1
	_rock.global_position = global_position
	_marker.visible = false

func _fall(delta: float) -> void:
	_fall_speed = minf(_fall_speed + FALL_GRAVITY * delta, MAX_FALL_SPEED)
	_rock.global_position += Vector2(0.0, _fall_speed * delta)

	_query.transform = Transform2D(0.0, _rock.global_position)
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var hits: Array[Dictionary] = space.intersect_shape(_query, 8)
	var struck_player: Node = null
	var struck_ground: bool = false
	for hit: Dictionary in hits:
		var body: Object = hit.get("collider")
		if body == null:
			continue
		if body is Node and (body as Node).is_in_group(_PLAYERS_GROUP):
			if struck_player == null and body.get("alive") == true:
				struck_player = body
		else:
			struck_ground = true
	if struck_player != null:
		_strike(struck_player)
		_shatter()
	elif struck_ground:
		_shatter()
	elif _rock.global_position.y - global_position.y > MAX_FALL_DISTANCE:
		# Fell clean out of the stage: nothing to shatter against.
		_rest()

## A rock hit, down the same path a weapon strike takes -- see the header for
## why the report goes out on the victim's own `strike_landed`.
func _strike(victim: Node) -> void:
	_hits += 1
	var victim_body := victim as Node2D
	var to_victim: Vector2 = victim_body.global_position - _rock.global_position
	var point: Vector2 = _rock.global_position + to_victim.normalized() * rock_radius
	victim.take_damage(damage)
	if victim.has_signal("strike_landed"):
		victim.emit_signal("strike_landed", victim, damage, point, not victim.alive)
	if not victim.alive:
		return
	var side: float = signf(victim_body.global_position.x - global_position.x)
	if side == 0.0:
		side = 1.0
	var direction: Vector2 = Vector2(side, -SHOVE_LIFT).normalized()
	var body := victim as RigidBody2D
	if body != null:
		body.apply_central_impulse(direction * shove_speed * body.mass)

func _shatter() -> void:
	_state = _RockState.SHATTERED
	_timer_remaining = SHATTER_SEC

func _rest() -> void:
	_state = _RockState.IDLE
	_timer_remaining = interval_sec
	_rock.visible = false
	_marker.visible = false
	_rock.global_position = global_position

## The first solid thing under the column top that is not a player: where the
## rock will come to rest if nobody is in the way. Players are stepped past
## rather than masked out, since they share terrain's layer.
func _find_landing() -> Vector2:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var exclude: Array[RID] = []
	var from: Vector2 = global_position
	var to: Vector2 = global_position + Vector2(0.0, MAX_FALL_DISTANCE)
	for _attempt in 8:
		var params := PhysicsRayQueryParameters2D.create(from, to, _WORLD_LAYER, exclude)
		var hit: Dictionary = space.intersect_ray(params)
		if hit.is_empty():
			return Vector2(NAN, NAN)
		var body: Object = hit.get("collider")
		if body is Node and (body as Node).is_in_group(_PLAYERS_GROUP):
			exclude.append(hit["rid"])
			continue
		return hit["position"]
	return Vector2(NAN, NAN)

# --- Visuals ----------------------------------------------------------------

## A lumpy many-sided outline: a rock, not a ball. Fixed offsets rather than
## random ones so every rock of the same size looks the same in screenshots.
func _rock_outline(radius: float) -> PackedVector2Array:
	var lumps: PackedFloat32Array = [1.0, 0.86, 0.97, 0.9, 1.0, 0.84, 0.95, 0.88, 0.99]
	var points := PackedVector2Array()
	for i in _ROCK_SIDES:
		var angle: float = TAU * float(i) / float(_ROCK_SIDES)
		points.append(Vector2.RIGHT.rotated(angle) * radius * lumps[i % lumps.size()])
	return points

## A flattened shadow with a crosshair over it, drawn at the landing point so
## its base sits on the ground surface.
func _build_marker() -> Node2D:
	var marker := Node2D.new()
	marker.name = "LandingMarker"
	var shadow := Polygon2D.new()
	shadow.name = "Shadow"
	shadow.color = Color(MARKER_COLOR, 0.45)
	var ellipse := PackedVector2Array()
	for i in 16:
		var angle: float = TAU * float(i) / 16.0
		ellipse.append(Vector2(cos(angle) * rock_radius * 1.2, sin(angle) * rock_radius * 0.3 - rock_radius * 0.3))
	shadow.polygon = ellipse
	marker.add_child(shadow)
	var arm: float = rock_radius * 0.9
	var lift: float = -rock_radius * 0.3
	for segment: PackedVector2Array in [
			PackedVector2Array([Vector2(-arm, lift - arm * 0.5), Vector2(arm, lift + arm * 0.5)]),
			PackedVector2Array([Vector2(-arm, lift + arm * 0.5), Vector2(arm, lift - arm * 0.5)])]:
		var line := Line2D.new()
		line.width = 4.0
		line.default_color = MARKER_COLOR
		line.points = segment
		marker.add_child(line)
	return marker
