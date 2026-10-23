extends RefCounted

## Shared building blocks of the stage parts and hazards: the collision box,
## the rectangle drawing, the "standing on top" detector band, finding a
## player's weapon bodies, and asking the `Sfx` autoload for a sound or the
## "Reduce flashes" setting. Static helpers only; each part keeps its own
## state and node names. Preloaded by path, never referenced by `class_name`
## (CLAUDE.md).

## For `HEAD_GROUP` only: see `weapon_bodies_of()`.
const WeaponHeadType := preload("res://scripts/WeaponHead.gd")

## The rigid bodies of `body`'s weapon (its head and haft), so a push given to
## a player's body can carry the whole player and not the body alone: the
## weapon is jointed to the body and held at its reach by a clamped drive
## (ADR-0006), which would otherwise haul the two back together (see the
## header of `BouncePad.gd` for the measurement).
##
## Found through what the head already makes public: every live head is in
## `WeaponHead.HEAD_GROUP`, and its `sweep_exclude` names the one body it
## belongs to. The haft is the head's sibling under the rig. A flail's ball is
## a second head in the same rig (issue #150), so a rig already gathered is
## not walked again. Empty when nothing is found.
static func weapon_bodies_of(tree: SceneTree, body: RigidBody2D) -> Array[RigidBody2D]:
	var parts: Array[RigidBody2D] = []
	var rid: RID = body.get_rid()
	var rigs: Array[Node] = []
	for head: Node in tree.get_nodes_in_group(WeaponHeadType.HEAD_GROUP):
		if head.is_queued_for_deletion() or not (head is RigidBody2D) or not rid in head.sweep_exclude:
			continue
		var rig: Node = head.get_parent()
		if rigs.has(rig):
			continue
		rigs.append(rig)
		for child: Node in rig.get_children():
			if child is RigidBody2D and child != body and not parts.has(child):
				parts.append(child as RigidBody2D)
	return parts

## Adds a `CollisionShape2D` named `shape_name` holding a `size` rectangle,
## centred on `owner`, and returns it.
static func add_rect_shape(owner: Node, size: Vector2, shape_name: String = "CollisionShape2D") -> CollisionShape2D:
	var rect := RectangleShape2D.new()
	rect.size = size
	var collision_shape := CollisionShape2D.new()
	collision_shape.name = shape_name
	collision_shape.shape = rect
	owner.add_child(collision_shape)
	return collision_shape

## The four corners of a `size` rectangle centred on the origin, clockwise
## from the top left: a `Polygon2D` matching `add_rect_shape()`.
static func rect_polygon(size: Vector2) -> PackedVector2Array:
	var half: Vector2 = size / 2.0
	return PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])

## Adds the thin "standing on top" band of a `size` part: an `Area2D` named
## `Detector` (shape `DetectorShape`) along the top face, from `above` px
## over it to `below` px into it. It masks only the world layer
## (`Player.LAYER_WORLD`), where player bodies live and weapon heads do not
## (ADR-0010), and nothing detects it.
static func add_top_detector(owner: Node, size: Vector2, above: float, below: float) -> Area2D:
	var detector := Area2D.new()
	detector.name = "Detector"
	detector.collision_layer = 0
	detector.collision_mask = 1
	detector.position = Vector2(0, -size.y / 2.0 - above / 2.0 + below / 2.0)
	var detector_rect := RectangleShape2D.new()
	detector_rect.size = Vector2(size.x, above + below)
	var detector_shape := CollisionShape2D.new()
	detector_shape.name = "DetectorShape"
	detector_shape.shape = detector_rect
	detector.add_child(detector_shape)
	owner.add_child(detector)
	return detector

## Whether `body` is really resting on `part`, not only inside its band.
## `get_colliding_bodies()` needs the body's contact monitor, which a player
## always has on (it scores knockback with it).
static func touching(part: PhysicsBody2D, body: RigidBody2D) -> bool:
	return body.contact_monitor and body.get_colliding_bodies().has(part)

## Asks the Sfx autoload for `sound` (issue #76), from `from`'s tree. Looked
## up by path, never by name, so a part still works without the autoload.
static func sfx(from: Node, sound: StringName, at: Vector2, strength: float = 1.0) -> void:
	var player: Node = from.get_node_or_null(^"/root/Sfx")
	if player != null:
		player.play(sound, at, strength)

## Comfort option (#317): the saved "Reduce flashes" setting, off when there is
## no `Sfx` autoload to ask.
static func reduce_flash(from: Node) -> bool:
	var player: Node = from.get_node_or_null(^"/root/Sfx")
	return player != null and bool(player.get("reduce_flash"))

## A hazard (a falling rock, a meteor) strikes `victim` for `amount` at
## `point`, down the same path a weapon strike takes: the hazard is marked as
## `kind` for the achievements (#689), the damage goes through `take_damage()`,
## and what it actually took off goes out on the victim's own `strike_landed`
## (issue #162: a spawn-protected player takes nothing, and nothing dealt is
## nothing reported). A victim still standing and not spawn-protected is then shoved at `speed` along
## (`side`, -`lift`) normalised. Returns the damage dealt.
static func hazard_strike(victim: Node, amount: float, point: Vector2, kind: String, side: float, lift: float,
		speed: float) -> float:
	var before: Variant = victim.get("damage")
	if victim.has_method("mark_hazard"):
		victim.mark_hazard(kind)
	victim.take_damage(amount, point)
	var after: Variant = victim.get("damage")
	var dealt: float = amount
	if before != null and after != null:
		dealt = float(after) - float(before)
	if dealt > 0.0 and victim.has_signal("strike_landed"):
		victim.emit_signal("strike_landed", victim, dealt, point, not victim.alive)
	if not victim.alive or victim.get("spawn_protected") == true:
		return dealt  # a protected fighter is not shoved either (#991)
	var body := victim as RigidBody2D
	if body != null:
		body.apply_central_impulse(Vector2(side, -lift).normalized() * speed * body.mass)
	return dealt
