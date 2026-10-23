extends RefCounted

## What every thrown or fired weapon -- the bullet (`Projectile`), the
## boomerang and the grapple or rod hook (`GrappleHook`) -- does the same way:
## a shield face turning the shot, the shooter's colour and the loaded art
## drawn in flight, and the swept cast that finds the first thing in the
## shot's path. Also the line-of-terrain test the player and the flail share.
##
## Static functions only. Preloaded by path, never named by `class_name`
## (CLAUDE.md).

const ShieldSparkScript := preload("res://scripts/ShieldSpark.gd")

## Issue #631, ADR-0024: the player, other than `shooter`, whose shield's
## face turns a shot flying `from` -> `to` with radius `r`, or null.
static func shield_holder(tree: SceneTree, shooter: Node, from: Vector2, to: Vector2, r: float) -> Node:
	for node: Node in tree.get_nodes_in_group("players"):
		if node != shooter and node.has_method("shield_face_blocks") \
				and node.shield_face_blocks(from, to, r):
			return node
	return null

## `art` moved so its bounding box is centred on the origin: the loaded art is
## authored where it sits on the head, and in flight it is drawn round the
## flying circle.
static func centred(art: PackedVector2Array) -> PackedVector2Array:
	if art.is_empty():
		return art
	var box := Rect2(art[0], Vector2.ZERO)
	for p: Vector2 in art:
		box = box.expand(p)
	var centre: Vector2 = box.get_center()
	var out := PackedVector2Array()
	for p: Vector2 in art:
		out.append(p - centre)
	return out

## Issue #969: feedback for a shot the shield of `holder` just stopped at
## `point`: one `shield_block` sound and a spark burst in the holder's colour
## (no burst with "Reduce flashes" on, #317; the sound stays). Call once per
## block. Damage and the shot's own turn-back are the caller's business.
static func shield_blocked(shot: Node, holder: Node, point: Vector2) -> void:
	var sfx: Node = shot.get_node_or_null(^"/root/Sfx")
	if sfx != null:
		sfx.play(&"shield_block", point, 1.0)
		if bool(sfx.get("reduce_flash")):
			return
	var spark: Node2D = ShieldSparkScript.new()
	spark.colour = shooter_colour(holder)
	var parent: Node = shot.get_parent()
	if parent == null:
		spark.free()
		return
	parent.add_child(spark)
	spark.global_position = point

## The shooter's identity colour, or white for a shooter without one.
static func shooter_colour(shooter: Node) -> Color:
	var identity: Variant = shooter.get("identity_color") if shooter != null else null
	return identity if identity is Color else Color.WHITE

## Casts `shape` from `from` along `motion` against bodies on `mask`, leaving
## out `exclude`, and reports the first contact: `unsafe` is the fraction of
## `motion` at which the shape first touches (1.0 for a clear path), and
## `collider` and `point` are what it touched there and where. The cast only
## says when, so what was touched is asked at the touching position; a graze
## can leave no rest info, and an overlap query then still finds the collider.
## `point` is Vector2.INF when the rest info had none: each caller has its own
## fallback.
static func cast_first(space: PhysicsDirectSpaceState2D, shape: Shape2D, from: Vector2, motion: Vector2,
		mask: int, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, from)
	query.motion = motion
	query.collision_mask = mask
	query.exclude = exclude
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var fractions: PackedFloat32Array = space.cast_motion(query)
	var unsafe: float = fractions[1] if fractions.size() >= 2 else 1.0
	if unsafe >= 1.0:
		return {"unsafe": 1.0, "collider": null, "point": Vector2.INF}
	query.transform = Transform2D(0.0, from + motion * unsafe)
	query.motion = Vector2.ZERO
	var collider: Object = null
	var point: Vector2 = Vector2.INF
	var rest: Dictionary = space.get_rest_info(query)
	if not rest.is_empty():
		collider = instance_from_id(rest["collider_id"])
		point = rest["point"]
	else:
		var overlaps: Array[Dictionary] = space.intersect_shape(query, 1)
		if not overlaps.is_empty():
			collider = overlaps[0]["collider"]
	return {"unsafe": unsafe, "collider": collider, "point": point}

## Whether terrain on `mask` lies on the straight line `from` -> `to`, leaving
## out `exclude`. Players' bodies share the terrain layer and are stepped past,
## up to `max_skips` of them.
static func terrain_between(space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2, mask: int,
		exclude: Array[RID], max_skips: int) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, mask, exclude)
	query.collide_with_areas = false
	for i in max_skips:
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider: Object = hit["collider"]
		if not (collider is Node and (collider as Node).is_in_group("players")):
			return true
		var skipped: Array[RID] = query.exclude
		skipped.append(hit["rid"])
		query.exclude = skipped
	return false
