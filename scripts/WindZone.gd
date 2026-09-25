extends Area2D

## Wind zone stage part (issue #52): a region that pushes players' bodies,
## in gusts with a readable tell by default, or steadily.
##
## An `Area2D` like `KillZone.gd` and `Hazard`, because wind is not terrain:
## nothing stands on it and nothing collides with it. Every physics tick it
## pushes the player bodies inside it with a force along `direction`. The push
## is an acceleration, `strength` px/s^2, applied as `strength * mass`, so the
## wind moves every body the same way whatever it weighs, the way a stage
## author reading the number expects.
##
## **The gust cycle (owner, issue #52).** CALM, then TELL, then GUST, then
## CALM again, forever, timed in physics ticks like `KillZone.gd`'s rise so it
## stays in step with the bodies it pushes:
##   CALM -- no push. Faint tint, streaks drifting slowly.
##   TELL -- still no push. The tint brightens and the streaks speed up across
##           the whole of it, so a player who sees it has `tell_sec` to plant
##           or get out. The wind-up is a warning, not a weaker gust.
##   GUST -- full push. Brightest tint, fastest streaks.
## With `steady` on there is no cycle: the zone pushes all the time at
## `strength` and shows the gust visual all the time. The visual cue is not
## optional in either mode, so a player can always see where wind is.
##
## **Heads are not pushed (ADR-0006).** The detector only looks at the world
## layer, where player bodies are; weapon heads are on their own layer and
## never enter it. The weapon is aimed by clamped drives chasing the input
## vector, so wind on the head would do nothing but pull the aim off where the
## thumb says, and pull it off further for a weaker weapon than a stronger
## one, which would make the wind an aiming penalty rather than a movement
## one. Wind on the body is honest movement: the body is what drifts, the arm
## follows through its joint, and a head planted on terrain outside the gust
## is how a player holds on against it.
##
## The visual is drawn by this node's own `_draw()` (as `KillZone.gd` draws
## its band), from `size` and `direction`, so a stage author never edits a
## sub-resource: place the scene, set the numbers.

enum Phase { CALM, TELL, GUST, STEADY }

## The zone's box, centred on the node.
@export var size: Vector2 = Vector2(400, 300)
## Which way the wind blows, in the node's local space. Normalised in code, so
## only the direction matters; a zero vector pushes nothing.
@export var direction: Vector2 = Vector2.RIGHT
## Push during a gust (or always, when `steady`), as an acceleration in
## px/s^2. Gravity on a player is 1470 px/s^2 for scale.
@export var strength: float = 1800.0
## Constant push with no cycle. The gust visual shows the whole time.
@export var steady: bool = false
@export var calm_sec: float = 2.5
@export var tell_sec: float = 1.0
@export var gust_sec: float = 1.5
## Where in the cycle the zone starts, in seconds from the start of CALM, so
## two zones on one stage need not gust in lockstep.
@export var cycle_offset_sec: float = 0.0

## Pale sky blue: air, not ground and not danger. Alpha carries the phase.
const WIND_COLOR: Color = Color(0.7, 0.85, 1.0, 1)
const CALM_ALPHA: float = 0.08
const GUST_ALPHA: float = 0.32
const STREAK_ALPHA_CALM: float = 0.25
const STREAK_ALPHA_GUST: float = 0.9
## How fast the streaks travel, px/s. CALM drifts; the TELL ramps from calm
## to gust speed, which is most of what makes it read as winding up.
const STREAK_SPEED_CALM: float = 40.0
const STREAK_SPEED_GUST: float = 900.0
## One streak per this many square pixels, and each streak's length.
const STREAK_AREA: float = 3000.0
const STREAK_LENGTH_CALM: float = 14.0
const STREAK_LENGTH_GUST: float = 60.0

var _elapsed: float = 0.0
## How far the streak field has scrolled along the wind, integrated from the
## current speed each tick so a speed change never makes the streaks jump.
var _scroll: float = 0.0
var _streak_seeds: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	# Pushes only; nothing detects the zone itself.
	collision_layer = 0
	# World layer only (`Player.LAYER_WORLD`): bodies, never heads.
	collision_mask = 1
	var rect := RectangleShape2D.new()
	rect.size = size
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	shape.shape = rect
	add_child(shape)

	_elapsed = maxf(cycle_offset_sec, 0.0)
	# Fixed per zone, so the field is stable frame to frame: each seed is a
	# lateral position and a phase along the wind, both in 0..1.
	var rng := RandomNumberGenerator.new()
	rng.seed = 52
	var count: int = maxi(6, int(size.x * size.y / STREAK_AREA))
	for i in count:
		_streak_seeds.append(Vector2(rng.randf(), rng.randf()))

## Which part of the cycle the zone is in. An observable seam for scenarios.
func phase() -> Phase:
	if steady:
		return Phase.STEADY
	var calm: float = maxf(calm_sec, 0.0)
	var tell: float = maxf(tell_sec, 0.0)
	var gust: float = maxf(gust_sec, 0.0)
	var cycle: float = calm + tell + gust
	if cycle <= 0.0:
		return Phase.CALM
	var t: float = fmod(_elapsed, cycle)
	if t < calm:
		return Phase.CALM
	if t < calm + tell:
		return Phase.TELL
	return Phase.GUST

## How far into the tell the zone is, 0 at its start to 1 at the gust; 0
## outside it. What the visual ramps on.
func tell_progress() -> float:
	if phase() != Phase.TELL or tell_sec <= 0.0:
		return 0.0
	var cycle: float = maxf(calm_sec, 0.0) + tell_sec + maxf(gust_sec, 0.0)
	return clampf((fmod(_elapsed, cycle) - maxf(calm_sec, 0.0)) / tell_sec, 0.0, 1.0)

## 0 for calm, 1 for a full gust, ramping through the tell. The one number the
## visual is drawn from. The ramp is front-loaded (a square root) so the tell
## reads as different from calm the moment it starts, not only near its end.
func _intensity() -> float:
	match phase():
		Phase.GUST, Phase.STEADY:
			return 1.0
		Phase.TELL:
			return sqrt(tell_progress())
		_:
			return 0.0

## Whether the zone is pushing right now.
func is_pushing() -> bool:
	var p: Phase = phase()
	return p == Phase.GUST or p == Phase.STEADY

## The zone's tint right now; brighter as the wind builds. An observable seam
## in the manner of `CrumblingLedge.visual_color()`.
func visual_color() -> Color:
	var c: Color = WIND_COLOR
	c.a = lerpf(CALM_ALPHA, GUST_ALPHA, _intensity())
	return c

## How fast the streaks are moving right now, px/s. Observable, so a scenario
## can check the tell visibly winds up.
func streak_speed() -> float:
	var i: float = _intensity()
	return lerpf(STREAK_SPEED_CALM, STREAK_SPEED_GUST, i * i)

## The wind direction in world space, unit length (or zero).
func world_direction() -> Vector2:
	return global_transform.basis_xform(direction).normalized()

func _physics_process(delta: float) -> void:
	_elapsed += delta
	_scroll += streak_speed() * delta
	if is_pushing():
		var push: Vector2 = world_direction() * strength
		for body: Node2D in get_overlapping_bodies():
			if body is RigidBody2D and body.is_in_group("players"):
				var rb := body as RigidBody2D
				rb.apply_central_force(push * rb.mass)
	queue_redraw()

func _draw() -> void:
	var half: Vector2 = size / 2.0
	draw_rect(Rect2(-half, size), visual_color())

	var dir: Vector2 = direction.normalized()
	if dir == Vector2.ZERO:
		return
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	# The box's extent along and across the wind, so the streak field covers
	# it whatever the direction; streaks landing outside the box are skipped.
	var along_extent: float = absf(dir.x) * size.x + absf(dir.y) * size.y
	var across_extent: float = absf(perp.x) * size.x + absf(perp.y) * size.y
	var i: float = _intensity()
	var length: float = lerpf(STREAK_LENGTH_CALM, STREAK_LENGTH_GUST, i)
	var streak_color: Color = WIND_COLOR
	streak_color.a = lerpf(STREAK_ALPHA_CALM, STREAK_ALPHA_GUST, i)
	var width: float = lerpf(1.5, 3.0, i)
	var box := Rect2(-half, size)
	for s: Vector2 in _streak_seeds:
		var along: float = fposmod(s.y * along_extent + _scroll, along_extent) - along_extent / 2.0
		var across: float = (s.x - 0.5) * across_extent
		var head: Vector2 = dir * along + perp * across
		var tail: Vector2 = head - dir * length
		if box.has_point(head) and box.has_point(tail):
			draw_line(tail, head, streak_color, width)
			# An arrow tip, so the wind's direction reads in a still frame
			# too, not only from the streaks' motion.
			var tip: float = length * 0.3
			draw_line(head, head - dir * tip + perp * tip * 0.6, streak_color, width)
			draw_line(head, head - dir * tip - perp * tip * 0.6, streak_color, width)
