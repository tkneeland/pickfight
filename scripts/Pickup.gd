extends Area2D

## A weapon lying on the stage during a round (issue #14, ADR-0009). Touching
## it with a player's body swaps that player's weapon for this one; the old
## weapon is gone, not dropped, and the pickup leaves the stage the moment it
## is claimed.
##
## Static and unaffected by gravity: an Area2D is never simulated, so a pickup
## stays exactly where it spawned and a player can plan a route to it (user
## story 11).
##
## Only a player's **body** collects (user story 7). Bodies share the world
## layer with terrain; weapon heads are on their own layer (Player.LAYER_HEAD),
## which this area does not watch, so a head resting on a pickup does nothing
## and a pickup cannot be sniped from a weapon's length away. Terrain on the
## world layer does enter, and is ignored by the `players` group check.

## Player.LAYER_WORLD, repeated rather than read off Player so this script
## does not have to preload it.
const LAYER_WORLD: int = 1
## Drawn size of the weapon's head art relative to the head it actually is.
## Visual only: what the player then holds is the weapon at its real size.
const ART_SCALE: float = 1.0
## The drawn haft is the weapon's reach scaled down by this, clamped, so a
## long weapon still reads as long without the pickup outgrowing its spot.
const HAFT_DRAW_SCALE: float = 0.2
const HAFT_MIN_LENGTH: float = 12.0
const HAFT_MAX_LENGTH: float = 40.0
const HAFT_WIDTH: float = 4.0
## Player.HAFT_COLOR, so a pickup's haft reads as the same material.
const HAFT_COLOR: Color = Color(0.42, 0.3, 0.2, 1.0)
## Weapons lie on a diagonal, head up and to the right.
const DRAW_AXIS: Vector2 = Vector2(0.70710678, -0.70710678)
## The furthest a drawn weapon may reach from the pickup's centre. A weapon
## whose art at full size would go further -- since #45 the sword's blade is
## 97 px long and the axe's head is 1.75x -- is drawn smaller as a whole,
## haft and head together, so a pickup never outgrows the spots stages were
## laid out for. 25 px is what the largest pickup measured before #45 (the
## staff, 24.5 px), which every stage's pickup spots already clear.
const MAX_ART_RADIUS: float = 25.0
## The trigger reaches at least this far from the pickup's centre however
## small the weapon's art is, so every pickup is equally easy to touch.
const MIN_TRIGGER_RADIUS: float = 20.0
## Space between the art and the edge of the backing disc.
const BACKING_MARGIN: float = 6.0
const BACKING_COLOR: Color = Color(1.0, 1.0, 1.0, 0.18)
const ART_COLOR: Color = Color(0.95, 0.92, 0.8, 1.0)
const BACKING_SEGMENTS: int = 24
## Drawn for a weapon with no art of its own: a plain diamond, reported as the
## fallback so a missing outline is visible rather than silent.
const FALLBACK_ART: PackedVector2Array = [
	Vector2(10.0, 0.0), Vector2(0.0, -10.0), Vector2(-10.0, 0.0), Vector2(0.0, 10.0)]

## The weapon this pickup hands over. Set through `set_weapon()` before the
## pickup enters the tree; its visuals and trigger are built from it.
var weapon_stats: Resource
## Set the instant someone claims this pickup, so a second body arriving on
## the same tick (or before the free lands) gets nothing (user story 12).
var _claimed: bool = false
var _art_is_fallback: bool = false
var _trigger_radius: float = 0.0

@onready var _backing: Polygon2D = $Backing
@onready var _art: Polygon2D = $Art
@onready var _shape: CollisionShape2D = $Shape

func set_weapon(stats: Resource) -> void:
	weapon_stats = stats

func _ready() -> void:
	add_to_group("pickups")
	collision_layer = 0
	collision_mask = LAYER_WORLD
	monitorable = false
	_build()
	body_entered.connect(_on_body_entered)

## The outline drawn for this pickup, in the art's own coordinates: exactly
## the weapon's `pickup_art` when it has one, else its `art_outline`.
func art_polygon() -> PackedVector2Array:
	return _art.polygon if _art != null else PackedVector2Array()

func art_is_fallback() -> bool:
	return _art_is_fallback

func trigger_radius() -> float:
	return _trigger_radius

## Draws the whole weapon, not just its head: a haft whose length follows the
## weapon's reach, with the head's own art on the end, laid on a diagonal and
## centred on the pickup. The head alone does not say which weapon it is --
## the staff's is a 5 px nub -- while a long haft with a nub, a short one with
## a blade, and a crescent on a mid-length one are each recognisable from
## across the room (user story 10).
func _build() -> void:
	var outline: PackedVector2Array = PackedVector2Array()
	if weapon_stats != null and "art_outline" in weapon_stats:
		outline = weapon_stats.art_outline
	# A weapon whose head alone does not show what it is -- the grapple's
	# launcher without its hook, the flail's knob without its ball (issue
	# #150) -- carries a fuller drawing for its pickup.
	if weapon_stats != null and "pickup_art" in weapon_stats and weapon_stats.pickup_art.size() >= 3:
		outline = weapon_stats.pickup_art
	_art_is_fallback = outline.size() < 3
	if _art_is_fallback:
		outline = FALLBACK_ART
	_art.polygon = outline
	_art.color = ART_COLOR
	_art.scale = Vector2.ONE * ART_SCALE

	var reach: float = weapon_stats.max_reach if weapon_stats != null and "max_reach" in weapon_stats else 0.0
	var haft_len: float = clampf(reach * HAFT_DRAW_SCALE, HAFT_MIN_LENGTH, HAFT_MAX_LENGTH)
	# The outline is head-local: +x points out along the haft from where the
	# haft holds the head. How far forward it reaches sets where the weapon's
	# midpoint falls.
	var head_len: float = 0.0
	for point: Vector2 in outline:
		head_len = maxf(head_len, point.x * ART_SCALE)
	var total: float = haft_len + head_len
	var butt: Vector2 = -DRAW_AXIS * total * 0.5
	var anchor: Vector2 = butt + DRAW_AXIS * haft_len
	_art.position = anchor
	_art.rotation = DRAW_AXIS.angle()

	# The drawn weapon's furthest point from the centre, butt or head.
	var art_radius: float = butt.length() + HAFT_WIDTH * 0.5
	for point: Vector2 in outline:
		art_radius = maxf(art_radius, (anchor + (point * ART_SCALE).rotated(_art.rotation)).length())

	if art_radius > MAX_ART_RADIUS:
		var fit: float = MAX_ART_RADIUS / art_radius
		butt *= fit
		anchor *= fit
		_art.position = anchor
		_art.scale = Vector2.ONE * ART_SCALE * fit
		art_radius = MAX_ART_RADIUS

	var haft := Line2D.new()
	haft.name = "Haft"
	haft.points = PackedVector2Array([butt, anchor])
	haft.width = HAFT_WIDTH
	haft.default_color = HAFT_COLOR
	haft.begin_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(haft)
	move_child(haft, _art.get_index())

	_trigger_radius = maxf(MIN_TRIGGER_RADIUS, art_radius)
	var circle := CircleShape2D.new()
	circle.radius = _trigger_radius
	_shape.shape = circle

	var disc := PackedVector2Array()
	var disc_radius: float = maxf(_trigger_radius, art_radius + BACKING_MARGIN)
	for i in BACKING_SEGMENTS:
		var a: float = TAU * float(i) / float(BACKING_SEGMENTS)
		disc.append(Vector2(cos(a), sin(a)) * disc_radius)
	_backing.polygon = disc
	_backing.color = BACKING_COLOR

## A live player's body touched the pickup: hand the weapon over and leave.
## Eliminated players have no collision layer to enter with, and are refused
## here too rather than relying on that alone (user story 19).
func _on_body_entered(body: Node) -> void:
	if _claimed or weapon_stats == null:
		return
	if not body.is_in_group("players") or not body.alive:
		return
	_claimed = true
	# Safe mid-flush: set_weapon_stats() only records the weapon and defers
	# the rig rebuild itself, which is the part the physics server would
	# refuse while it is still flushing the query that fired this signal.
	body.set_weapon_stats(weapon_stats)
	queue_free()
