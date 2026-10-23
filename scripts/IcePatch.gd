extends StaticBody2D

## Ice patch stage part (issue #860): a strip of solid ground with almost no
## grip. While a player's body rests on it, the body's ground friction drops
## to the value the Slippery floor round modifier uses, so running and
## swing-rolling go loose; stepping off, or the stage going away at round end,
## puts the body's own material back.
##
## A `StaticBody2D`, like `Conveyor`: ordinary terrain on the world layer. A
## thin `Area2D` band along the top face picks candidates, and the body's
## contact monitor decides who is really standing on it.
##
## **Friction, not force.** The strip pushes nobody. It swaps the body's
## `physics_material_override` for a low-friction copy (Godot combines two
## bodies' friction by taking the lower), so a player slides on until their
## own damping stops them.
##
## **Heads are untouched (ADR-0006, ADR-0010).** The detector masks only the
## world layer, which a weapon head is not on, and only the body's material is
## changed, so a head plants on the ice as on any ground.
##
## **Nothing leaks.** The saved materials are put back when a body leaves, and
## in `_exit_tree()` for any still on the strip when the stage is freed. If
## something else (the Slippery floor modifier) replaced the override while a
## body was on the ice, that newer material is left alone. Patches share the
## record, so a body on two overlapping patches gets its grip back only when it
## is off both.
##
## `_ready()` builds collision, visual and detector from the exports.

## Preloaded by path, never by `class_name` (CLAUDE.md), for the shared friction.
const RoundModifiersType := preload("res://scripts/RoundModifiers.gd")
const PartKitScript := preload("res://scripts/PartKit.gd")

## The strip's collision and visual box, centred on the node.
@export var size: Vector2 = Vector2(160, 8)

## The friction a body has on the ice: the Slippery floor modifier's own value.
const ICE_FRICTION: float = RoundModifiersType.SLIPPERY_FRICTION
## Pale blue, with white streaks.
const ICE_COLOR: Color = Color(0.7, 0.86, 0.96, 1)
const STREAK_COLOR: Color = Color(1, 1, 1, 0.85)
const _DETECTOR_ABOVE: float = 6.0
const _DETECTOR_BELOW: float = 2.0
const _STREAK_SPACING: float = 36.0

var _detector: Area2D
## The bodies this patch is holding on the ice: body -> true.
var _mine: Dictionary = {}

## Shared by every ice patch, so two that overlap or touch hand a body from one
## to the other without it getting its grip back in between: the one
## low-friction material (compared by identity on restore), and per body on
## any patch the material it had before the ice (may be null) and the patches
## holding it. The material goes back only when the last of them lets go.
static var _ice_material: PhysicsMaterial
## body -> {"before": PhysicsMaterial, "patches": Array of patch instance ids}.
static var _holds: Dictionary = {}

static func _shared_material() -> PhysicsMaterial:
	if _ice_material == null:
		_ice_material = PhysicsMaterial.new()
		_ice_material.friction = ICE_FRICTION
	return _ice_material

func _ready() -> void:
	_shared_material()

	var half: Vector2 = size / 2.0
	PartKitScript.add_rect_shape(self, size)

	var ice := Polygon2D.new()
	ice.name = "Ice"
	ice.color = ICE_COLOR
	ice.polygon = PartKitScript.rect_polygon(size)
	add_child(ice)

	var streaks := Node2D.new()
	streaks.name = "Streaks"
	add_child(streaks)
	var count: int = maxi(1, int(size.x / _STREAK_SPACING))
	for i in count:
		var streak := Line2D.new()
		streak.width = 1.5
		streak.default_color = STREAK_COLOR
		var x: float = -half.x + _STREAK_SPACING * (float(i) + 0.5)
		streak.points = PackedVector2Array([Vector2(x - 6.0, half.y * 0.5), Vector2(x + 6.0, -half.y * 0.5)])
		streaks.add_child(streak)

	# World layer only: player bodies, not heads.
	_detector = PartKitScript.add_top_detector(self, size, _DETECTOR_ABOVE, _DETECTOR_BELOW)

func _physics_process(_delta: float) -> void:
	var on_ice: Array[RigidBody2D] = []
	for body: Node2D in _detector.get_overlapping_bodies():
		if body is RigidBody2D and body.is_in_group("players") and PartKitScript.touching(self, body):
			on_ice.append(body as RigidBody2D)
			_grip_off(body as RigidBody2D)
	for body: Variant in _mine.keys():
		if not on_ice.has(body):
			_restore(body)

func _exit_tree() -> void:
	for body: Variant in _mine.keys():
		_restore(body)

## True while this patch holds `body` on the ice (its material on it).
func is_icing(body: RigidBody2D) -> bool:
	return _mine.has(body)

func _grip_off(body: RigidBody2D) -> void:
	if _mine.has(body):
		return
	var hold: Variant = _holds.get(body)
	if hold != null:
		# Already on the ice of another patch: hold it too, so leaving that
		# one keeps the grip off while this one is still underfoot.
		(hold["patches"] as Array).append(get_instance_id())
		_mine[body] = true
		return
	var before: PhysicsMaterial = body.physics_material_override
	if before != null and before.friction <= ICE_FRICTION:
		return  # already as slippery (the modifier); nothing to swap or restore
	_holds[body] = {"before": before, "patches": [get_instance_id()]}
	_mine[body] = true
	body.physics_material_override = _shared_material()

func _restore(body: Variant) -> void:
	_mine.erase(body)
	var hold: Variant = _holds.get(body)
	if hold == null:
		return
	var patches: Array = hold["patches"]
	patches.erase(get_instance_id())
	if not patches.is_empty():
		return  # another patch still has it on the ice
	_holds.erase(body)
	if not is_instance_valid(body):
		return
	if body.physics_material_override == _ice_material:
		body.physics_material_override = hold["before"]
