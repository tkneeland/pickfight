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
## body was on the ice, that newer material is left alone.
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
## body -> the material it had before the ice (may be null).
var _saved: Dictionary = {}
## The one low-friction material put on bodies; compared by identity on restore.
var _ice_material: PhysicsMaterial

func _ready() -> void:
	_ice_material = PhysicsMaterial.new()
	_ice_material.friction = ICE_FRICTION

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
	for body: Variant in _saved.keys():
		if not on_ice.has(body):
			_restore(body)

func _exit_tree() -> void:
	for body: Variant in _saved.keys():
		_restore(body)

## True while `body` has the ice's material on it.
func is_icing(body: RigidBody2D) -> bool:
	return _saved.has(body)

func _grip_off(body: RigidBody2D) -> void:
	if _saved.has(body):
		return
	var before: PhysicsMaterial = body.physics_material_override
	if before != null and before.friction <= ICE_FRICTION:
		return  # already as slippery (the modifier); nothing to swap or restore
	_saved[body] = before
	body.physics_material_override = _ice_material

func _restore(body: Variant) -> void:
	var before: PhysicsMaterial = _saved.get(body)
	_saved.erase(body)
	if not is_instance_valid(body):
		return
	if body.physics_material_override == _ice_material:
		body.physics_material_override = before
