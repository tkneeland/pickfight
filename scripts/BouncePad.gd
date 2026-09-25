extends StaticBody2D

## Bounce pad stage part (issue #52): a block of solid ground that launches a
## player's body the moment it lands on it.
##
## A `StaticBody2D`, like `CrumblingLedge`: the pad itself never moves, so it
## needs no sweep of its own, and its collision is ordinary terrain on the
## world layer. The launch is not a physics material bounce (restitution).
## Restitution returns a fraction of the speed a body arrived with, so a
## gentle landing would barely bounce and a hard one would go wild; a pad a
## player can plan around has to launch to the same height every time. So
## the pad sets the body's speed along the pad's own up to `launch_speed`,
## whatever it arrived with, and keeps whatever it had across the pad. A
## rotated pad therefore launches diagonally, along its own local up, and a
## player running across a flat pad keeps their run.
##
## **Who gets launched.** Only a player's body: something in the `players`
## group (the `KillZone.gd` and `CrumblingLedge` check) resting on the pad's
## top face. Detection is a thin child `Area2D` along that face, and a body
## in it only counts once it is really touching the pad, which a player's
## body reports through its own contact monitor. The band alone would not
## do: a player standing on their own pickaxe on the pad holds their body a
## few pixels above it, close enough to overlap any band thick enough to
## catch a landing reliably.
##
## **Heads are not launched (ADR-0006, ADR-0010).** A weapon head sits on
## its own layer (`Player.LAYER_HEAD`), and the detector masks only the world
## layer, so a head never enters it. For a head the pad is plain ground: it
## plants on it and pushes off it exactly as it does on the floor. Launching
## the head instead would yank the whole rig through the joints and throw the
## player along the weapon's angle, adding a fixed launch on top of the
## push-off the player already put into the plant. That is the "absurd
## fling" to avoid, and it would reward jabbing the pad rather than landing
## on it. When the body is launched its weapon gets the same change of
## velocity, so the player flies as one piece; see `_weapon_bodies_of()`.
##
## A body is launched once per landing. Once it is already leaving along the
## pad's up at a good share of `launch_speed` it is left alone, so a body
## still inside the band on the tick after its launch is not launched again.
##
## `_ready()` builds the collision, the visual and the detector from the
## exports below, so a stage author places this scene, rotates it if they want
## a diagonal launch, and never opens a sub-resource.

## Preloaded by path, never referenced by `class_name` (CLAUDE.md), for
## `HEAD_GROUP` only: see `_weapon_bodies_of()`.
const WeaponHeadType := preload("res://scripts/WeaponHead.gd")

## The pad's collision and visual box, centred on the node. The launch goes
## along the node's local up (-Y), so this is the top face's length by the
## pad's thickness.
@export var size: Vector2 = Vector2(120, 16)
## The speed, in px/s, a landing body leaves along the pad's up. Against a
## player's gravity and linear damping, 2000 carries a body roughly 500 px
## straight up.
@export var launch_speed: float = 2000.0

## Spring green: nothing else on a stage is green, so a pad reads as "this
## throws you" at a glance, against the grey-blue terrain, the blue moving
## platforms and the red-orange hazards.
const PAD_COLOR: Color = Color(0.25, 0.85, 0.35, 1)
## The chevrons drawn on the pad, pointing along its launch direction.
const CHEVRON_COLOR: Color = Color(0.1, 0.4, 0.15, 1)
## The pad flashes toward this on a launch and fades back over `_FLASH_SEC`.
const FLASH_COLOR: Color = Color(0.9, 1.0, 0.9, 1)
const _FLASH_SEC: float = 0.25
## How far the visual squashes toward the pad's base on a launch, as a
## fraction of its height: the pad reads as a spring that just fired.
const _SQUASH_SCALE: float = 0.45

## The detector band along the top face. Thin on purpose: see the header on
## why the band only picks candidates and the contact decides.
const _DETECTOR_ABOVE: float = 6.0
const _DETECTOR_BELOW: float = 2.0
## A body already leaving along the pad's up faster than this share of
## `launch_speed` has been launched, and is not launched again.
const _RELAUNCH_SHARE: float = 0.5

var _visual: Node2D
var _body_poly: Polygon2D
var _detector: Area2D
var _flash_remaining: float = 0.0
var _launches: int = 0

func _ready() -> void:
	var half: Vector2 = size / 2.0

	var rect := RectangleShape2D.new()
	rect.size = size
	var collision_shape := CollisionShape2D.new()
	collision_shape.name = "CollisionShape2D"
	collision_shape.shape = rect
	add_child(collision_shape)

	# The visual is a pivot at the pad's base with the drawing hung above it,
	# so squashing its Y scale shrinks the pad down onto its base rather than
	# toward its middle.
	_visual = Node2D.new()
	_visual.name = "Visual"
	_visual.position = Vector2(0, half.y)
	add_child(_visual)

	_body_poly = Polygon2D.new()
	_body_poly.name = "Pad"
	_body_poly.color = PAD_COLOR
	_body_poly.polygon = PackedVector2Array([
		Vector2(-half.x, -size.y),
		Vector2(half.x, -size.y),
		Vector2(half.x, 0),
		Vector2(-half.x, 0),
	])
	_visual.add_child(_body_poly)

	# Up-pointing chevrons across the face. Spaced by the pad's height so a
	# short pad still gets at least one.
	var chevron_half_w: float = minf(size.y * 0.6, half.x * 0.8)
	var spacing: float = chevron_half_w * 2.6
	var count: int = maxi(1, int(size.x / spacing))
	for i in count:
		var cx: float = -half.x + size.x * (float(i) + 0.5) / float(count)
		var chevron := Line2D.new()
		chevron.name = "Chevron%d" % i
		chevron.width = maxf(2.0, size.y * 0.18)
		chevron.default_color = CHEVRON_COLOR
		chevron.points = PackedVector2Array([
			Vector2(cx - chevron_half_w, -size.y * 0.25),
			Vector2(cx, -size.y * 0.8),
			Vector2(cx + chevron_half_w, -size.y * 0.25),
		])
		_visual.add_child(chevron)

	_detector = Area2D.new()
	_detector.name = "Detector"
	# World layer only (`Player.LAYER_WORLD`): player bodies live there and
	# weapon heads do not, which is how heads are kept out -- see the header.
	_detector.collision_layer = 0
	_detector.collision_mask = 1
	_detector.position = Vector2(0, -half.y - _DETECTOR_ABOVE / 2.0 + _DETECTOR_BELOW / 2.0)
	var detector_rect := RectangleShape2D.new()
	detector_rect.size = Vector2(size.x, _DETECTOR_ABOVE + _DETECTOR_BELOW)
	var detector_shape := CollisionShape2D.new()
	detector_shape.name = "DetectorShape"
	detector_shape.shape = detector_rect
	_detector.add_child(detector_shape)
	add_child(_detector)

## The world direction this pad launches along: its local up.
func launch_direction() -> Vector2:
	return -global_transform.y.normalized()

## The colour the pad is showing right now -- `FLASH_COLOR` just after a
## launch, fading back to `PAD_COLOR`. An observable seam a scenario can
## assert on, in the manner of `CrumblingLedge.visual_color()`.
func visual_color() -> Color:
	return _body_poly.color

## How many bodies this pad has launched. Observable, for scenarios.
func launch_count() -> int:
	return _launches

func _physics_process(delta: float) -> void:
	for body: Node2D in _detector.get_overlapping_bodies():
		if body is RigidBody2D and body.is_in_group("players") and _touching(body):
			_try_launch(body as RigidBody2D)
	_update_flash(delta)

## Whether `body` is really resting on the pad, not only inside the band.
## `get_colliding_bodies()` needs the body's contact monitor, which a player
## always has on (it scores knockback with it).
func _touching(body: RigidBody2D) -> bool:
	return body.contact_monitor and body.get_colliding_bodies().has(self)

func _try_launch(body: RigidBody2D) -> void:
	var up: Vector2 = launch_direction()
	var along: float = body.linear_velocity.dot(up)
	if along >= launch_speed * _RELAUNCH_SHARE:
		return
	var change: Vector2 = up * (launch_speed - along)
	body.linear_velocity += change
	for part: RigidBody2D in _weapon_bodies_of(body):
		part.linear_velocity += change
	_launches += 1
	_flash_remaining = _FLASH_SEC

## The rigid bodies of `body`'s weapon (its head and haft), so a launch
## carries the whole player and not the body alone.
##
## Measured, launching the body alone does not work: the weapon is jointed to
## the body and held at its commanded reach by a clamped drive (ADR-0006), so
## a body suddenly moving at 1270 px/s while its weapon is not is, to the
## drive, a reach error to correct. The drive hauls the two back together at
## its full force, and the body lost 700 px/s of its launch in seven ticks --
## more for a heavier weapon, and differently for every aim. Giving the weapon
## the same change of velocity leaves nothing for the drive to correct, so the
## launch is the same whatever the player is holding and wherever they aim.
##
## Found without a hook in `Player.gd`, through what the head already makes
## public: every live head is in `WeaponHead.HEAD_GROUP`, and its
## `sweep_exclude` names the one body it belongs to (its own player, which it
## is allowed to pass through). The haft is the head's sibling under the rig.
## If none of that is found, the body is launched alone.
func _weapon_bodies_of(body: RigidBody2D) -> Array[RigidBody2D]:
	var parts: Array[RigidBody2D] = []
	var rid: RID = body.get_rid()
	for head: Node in get_tree().get_nodes_in_group(WeaponHeadType.HEAD_GROUP):
		if head.is_queued_for_deletion() or not (head is RigidBody2D) or not rid in head.sweep_exclude:
			continue
		var rig: Node = head.get_parent()
		for child: Node in rig.get_children():
			if child is RigidBody2D and child != body:
				parts.append(child as RigidBody2D)
	return parts

func _update_flash(delta: float) -> void:
	if _flash_remaining <= 0.0:
		return
	_flash_remaining = maxf(0.0, _flash_remaining - delta)
	var t: float = _flash_remaining / _FLASH_SEC
	_body_poly.color = PAD_COLOR.lerp(FLASH_COLOR, t)
	_visual.scale = Vector2(1.0, lerpf(1.0, _SQUASH_SCALE, t))
