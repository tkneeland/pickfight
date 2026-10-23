extends Node2D
## One thing the PC client draws from a snapshot (issue #241): a player, a
## projectile or a pickup. A puppet has no physics; RemoteClient moves it every
## frame. Issue #930: a player is drawn as the host draws it (square body,
## haft, weapon head art, `Hat.gd` and `PlayerFace.gd` children) and a pickup
## with `Pickup.art_layout`'s geometry. No `class_name`: consumers preload this
## by path.

const PlayerScript: GDScript = preload("res://scripts/Player.gd")
const HatScript: GDScript = preload("res://scripts/Hat.gd")
const PlayerFaceScript: GDScript = preload("res://scripts/PlayerFace.gd")
const PickupScript: GDScript = preload("res://scripts/Pickup.gd")
const PickupWeaponsScript: GDScript = preload("res://scripts/PickupWeapons.gd")

enum Kind { PLAYER, PROJECTILE, PICKUP }

const BODY_RADIUS: float = 24.0
const HEAD_RADIUS: float = 9.0
const HEAD_INK: Color = Color(0.07, 0.07, 0.09, 1.0)

var kind: int = Kind.PLAYER
var color: Color = Color.WHITE
var label: String = ""
## Player: world offset from the body to the weapon head.
var head_offset: Vector2 = Vector2.ZERO
var body_rotation: float = 0.0
var damage: int = 0
## 0 dead, 1 alive, 2 spawn-protected (SnapshotCapture's STATE_ constants).
var phase: int = 1
## Player: world rotation of the weapon head, and which weapon it is (the
## snapshot's `head_shape_index`; 0 is the pickaxe). Pickup: `weapon_type`.
var head_rotation: float = 0.0
var weapon_index: int = 0
var _hat: Node2D
var _face: Node2D
var _stats_cache: Dictionary = {}

func set_pose(position_in: Vector2, rotation_in: float, head_position: Vector2, head_rotation_in: float = 0.0) -> void:
	position = position_in
	body_rotation = rotation_in
	head_offset = head_position - position_in
	head_rotation = head_rotation_in
	queue_redraw()

## Hat and eyes from the host's `looks` frame (ids as `Hat.IDS` and
## `PlayerFace.EYE_IDS`); `tint` is the hat's identity colour.
func set_look(hat_id: String, eyes_id: String, tint: Color) -> void:
	if _hat == null:
		_hat = HatScript.new()
		_hat.position = Vector2(0.0, -BODY_RADIUS)
		add_child(_hat)
		_face = PlayerFaceScript.new()
		_face.name = "Face"
		add_child(_face)
	_hat.set_hat(hat_id)
	_hat.set_tint(tint)
	_face.set_eyes(eyes_id)

func hat_id() -> String:
	return _hat.hat_id if _hat != null else HatScript.NONE

func eyes_id() -> String:
	return _face.eyes_style if _face != null else "round"

## The weapon resource for a snapshot weapon index (0 is the pickaxe), or null.
func _stats_for(index: int) -> Resource:
	if not _stats_cache.has(index):
		var path: String = PickupWeaponsScript.PICKAXE_PATH
		if index > 0:
			path = PickupWeaponsScript.WEAPON_PATHS[index - 1] if index <= PickupWeaponsScript.WEAPON_PATHS.size() else ""
		_stats_cache[index] = load(path) if not path.is_empty() else null
	return _stats_cache[index]

## The head-local art a player's weapon head is drawn with (empty: none known).
func head_art() -> PackedVector2Array:
	var stats: Resource = _stats_for(weapon_index)
	if stats != null and "art_outline" in stats and stats.art_outline.size() >= 3:
		return stats.art_outline
	return PackedVector2Array()

## What a pickup puppet draws, from `Pickup.art_layout`; "fallback" is true
## when its weapon has no art (the diamond).
func pickup_layout() -> Dictionary:
	return PickupScript.art_layout(_stats_for(weapon_index))

func _draw() -> void:
	match kind:
		Kind.PLAYER:
			_draw_player()
		Kind.PROJECTILE:
			draw_circle(Vector2.ZERO, 6.0, color)
		Kind.PICKUP:
			_draw_pickup()

func _draw_pickup() -> void:
	var layout: Dictionary = pickup_layout()
	var disc: PackedVector2Array = layout["disc"]
	draw_colored_polygon(disc, PickupScript.BACKING_COLOR)
	var ring: PackedVector2Array = disc.duplicate()
	ring.append(disc[0])
	draw_polyline(ring, PickupScript.RING_COLOR, PickupScript.RING_WIDTH)
	draw_line(layout["butt"], layout["anchor"], PickupScript.HAFT_COLOR, PickupScript.HAFT_WIDTH)
	var xf := Transform2D(PickupScript.DRAW_AXIS.angle(), layout["anchor"]).scaled_local(Vector2.ONE * float(layout["art_scale"]))
	var outline: PackedVector2Array = xf * (layout["outline"] as PackedVector2Array)
	draw_colored_polygon(outline, PickupScript.ART_COLOR)

func _draw_player() -> void:
	var fade: float = 0.25 if phase == 0 else (0.6 if phase == 2 else 1.0)
	modulate.a = fade
	var hurt: float = clampf(float(damage) / PlayerScript.DEATH_DAMAGE, 0.0, 1.0)
	var fill: Color = color.lerp(PlayerScript.DAMAGE_FILL_COLOR, hurt)
	var half := Vector2(BODY_RADIUS, BODY_RADIUS)
	if head_offset.length() > 1.0:
		_draw_haft()
		_draw_head()
	draw_rect(Rect2(-half, half * 2.0), fill)
	draw_rect(Rect2(-half + Vector2(2, 2), half * 2.0 - Vector2(4, 4)), color, false, 4.0)
	if phase == 0:
		draw_line(Vector2(-10, -10), Vector2(10, 10), Color.BLACK, 3.0)
		draw_line(Vector2(-10, 10), Vector2(10, -10), Color.BLACK, 3.0)
	_draw_label(Vector2(0, -BODY_RADIUS - 8 - HatScript.height_of(hat_id())))

## The haft, tapering from the body to the head like the host's Line2D.
func _draw_haft() -> void:
	var dir: Vector2 = head_offset.normalized()
	var side: Vector2 = dir.orthogonal()
	var base: float = PlayerScript.HAFT_BASE_WIDTH * 0.5
	var tip: float = PlayerScript.HAFT_TIP_WIDTH * 0.5
	draw_colored_polygon(PackedVector2Array([side * base, head_offset + side * tip,
		head_offset - side * tip, -side * base]), PlayerScript.HAFT_COLOR)

func _draw_head() -> void:
	var art: PackedVector2Array = head_art()
	if art.size() < 3:
		draw_circle(head_offset, HEAD_RADIUS, color)
		return
	var xf := Transform2D(head_rotation, head_offset)
	var poly: PackedVector2Array = xf * art
	draw_colored_polygon(poly, color)
	var closed: PackedVector2Array = poly.duplicate()
	closed.append(poly[0])
	draw_polyline(closed, HEAD_INK, 2.0, true)

func _draw_label(at: Vector2) -> void:
	if label.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(font, at + Vector2(-size.x * 0.5, 0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
