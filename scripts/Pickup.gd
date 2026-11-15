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
const PickupCalloutScript := preload("res://scripts/PickupCallout.gd")
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
const BACKING_COLOR: Color = Color(1.0, 0.8, 0.18, 0.35)
## Playtest 2026-09-27: a pickup read as nothing at all on a full-screen
## host -- a 25 px grey disc on grey terrain -- and the owner reported "no
## weapons spawning" while they were there. So each pickup also wears a gold
## ring and a soft halo that breathes, drawn behind it and never collided
## with: the trigger and the art keep the sizes the stages were laid out for.
const RING_COLOR: Color = Color(1.0, 0.8, 0.18, 1.0)
const RING_WIDTH: float = 4.0
const HALO_COLOR: Color = Color(1.0, 0.85, 0.3, 0.3)
## How far past the disc the halo reaches at its widest, and how often it
## breathes.
const HALO_REACH: float = 2.0
const HALO_PERIOD_SEC: float = 1.2
const ART_COLOR: Color = Color(0.95, 0.92, 0.8, 1.0)
const BACKING_SEGMENTS: int = 24
## Health pack (#1267). Its `weapon_type` in the world snapshot: past every
## weapon index, so the Online client builds the same pack, not a weapon.
const HEALTH_PACK_TYPE: int = 0xFFFF
## The callout's own string (not a weapon name): "Healed!".
const HEALTH_CALLOUT_KEY: String = "PICKUP_HEALED"
## Art: a red cross on a white plate with a green ring and halo, so it reads as
## nothing like a gold weapon pickup.
const HEALTH_RADIUS: float = 22.0
const HEALTH_PLATE_COLOR: Color = Color(0.97, 0.97, 0.97, 0.95)
const HEALTH_RING_COLOR: Color = Color(0.25, 0.85, 0.4, 1.0)
const HEALTH_HALO_COLOR: Color = Color(0.4, 0.95, 0.5, 0.3)
const HEALTH_CROSS_COLOR: Color = Color(0.88, 0.12, 0.14, 1.0)
const HEALTH_CROSS_ARM: float = 14.0
const HEALTH_CROSS_THICK: float = 5.0
## Drawn for a weapon with no art of its own: a plain diamond, reported as the
## fallback so a missing outline is visible rather than silent.
const FALLBACK_ART: PackedVector2Array = [
	Vector2(10.0, 0.0), Vector2(0.0, -10.0), Vector2(-10.0, 0.0), Vector2(0.0, 10.0)]

## The weapon this pickup hands over. Set through `set_weapon()` before the
## pickup enters the tree; its visuals and trigger are built from it.
var weapon_stats: Resource
## Issue #1267: a health pack instead of a weapon. Touched by a living body it
## resets that fighter's damage to 0 and leaves; it never touches their
## weapon. Set through `set_health_pack()` before the pickup enters the tree.
var is_health_pack: bool = false
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

## Marks this pickup a health pack (#1267) instead of a weapon; call before it
## enters the tree. The Online client's puppet calls it too.
func set_health_pack() -> void:
	is_health_pack = true

## Issue #660: a KO'd player's ghost can pick a pickup up and put it down. While
## carried it is moved by its carrier (no physics fight); once dropped it falls
## under gravity until it meets terrain, like a thrown thing, and a live player
## can still collect it on the way.
const DROP_GRAVITY: float = 1400.0
const DROP_REST_CLEARANCE: float = 16.0
## A pickup that never finds ground is freed this far below where it was dropped.
const DROP_MAX_FALL: float = 4000.0
## A drop that starts inside terrain is lifted this far per probe, at most this
## many times, until its centre is in the open; it then falls onto that top.
const DROP_LIFT_STEP: float = 8.0
const DROP_LIFT_STEPS: int = 256
var carrier: Node = null
var _falling: bool = false
var _fall_speed: float = 0.0
var _fall_start_y: float = 0.0
## Issue #1103: set once a ghost has dropped this pickup (never for an authored
## spawn). While it rests it keeps checking for ground, so it falls again when
## the platform under it moves away or breaks.
var _dropped: bool = false
## Slack below DROP_REST_CLEARANCE before a resting dropped pickup counts as unsupported.
const DROP_REST_MARGIN: float = 3.0

func is_carried() -> bool:
	return carrier != null and is_instance_valid(carrier)

func is_falling() -> bool:
	return _falling

func carry_by(who: Node) -> void:
	carrier = who
	_falling = false
	_dropped = false

func drop() -> void:
	carrier = null
	_falling = true
	_dropped = true
	_fall_speed = 0.0
	_fall_start_y = global_position.y

func _physics_process(delta: float) -> void:
	# #1267: a fighter already standing on the pack who then takes damage never
	# re-enters it, so an unclaimed pack re-checks who is on it every tick.
	if is_health_pack and not _claimed and not display_only:
		for body: Node2D in get_overlapping_bodies():
			_on_body_entered(body)
			if _claimed:
				return
	if not _falling and not _dropped:
		return
	# #1103: a resting dropped pickup re-checks its ground with the same ray.
	var resting: bool = not _falling
	if not resting:
		_fall_speed += DROP_GRAVITY * delta
	var from: Vector2 = global_position
	var to: Vector2 = from + Vector2(0.0, 0.0 if resting else _fall_speed * delta)
	# Bodies share the world layer; land on terrain only. Built up front:
	# `query.exclude` hands back a copy, so appending to it would be lost.
	var bodies: Array[RID] = []
	for body: Node in get_tree().get_nodes_in_group("players"):
		if body is CollisionObject2D:
			bodies.append((body as CollisionObject2D).get_rid())
	var query := PhysicsRayQueryParameters2D.create(from, to + Vector2(0.0, DROP_REST_CLEARANCE + (DROP_REST_MARGIN if resting else 0.0)), LAYER_WORLD, bodies)
	# Issue #1102: a ray that starts inside terrain reports a hit at its own
	# start with no normal, so a ghost's drop inside a ledge is lifted out first.
	query.hit_from_inside = true
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and (hit["normal"] as Vector2) == Vector2.ZERO:
		var point := PhysicsPointQueryParameters2D.new()
		point.collision_mask = LAYER_WORLD
		point.exclude = bodies
		point.position = from
		var lifted: int = 0
		while lifted < DROP_LIFT_STEPS and not get_world_2d().direct_space_state.intersect_point(point, 1).is_empty():
			point.position.y -= DROP_LIFT_STEP
			lifted += 1
		global_position = point.position
		return
	if resting:
		if hit.is_empty():
			_falling = true
			_fall_speed = 0.0
			_fall_start_y = from.y
		return
	if not hit.is_empty():
		global_position = (hit["position"] as Vector2) - Vector2(0.0, DROP_REST_CLEARANCE)
		_falling = false
		return
	global_position = to
	if to.y - _fall_start_y > DROP_MAX_FALL:
		queue_free()

## Issue #976: the Online client's copy, drawn exactly as this pickup but
## never picked up. Set before it enters the tree.
var display_only: bool = false

## The group the Online client's copies join instead of "pickups", which is
## the host's live pickups only (night lighting glows both).
const DISPLAY_GROUP: StringName = &"night_lit_pickups"

func _ready() -> void:
	collision_layer = 0
	collision_mask = LAYER_WORLD
	monitorable = false
	_build()
	if display_only:
		add_to_group(DISPLAY_GROUP)
		monitoring = false
		set_physics_process(false)
		return
	add_to_group("pickups")
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
	if is_health_pack:
		_build_health_pack()
		return
	var layout: Dictionary = art_layout(weapon_stats)
	_art_is_fallback = layout["fallback"]
	_art.polygon = layout["outline"]
	_art.color = ART_COLOR
	_art.scale = Vector2.ONE * float(layout["art_scale"])
	_art.position = layout["anchor"]
	_art.rotation = DRAW_AXIS.angle()

	var haft := Line2D.new()
	haft.name = "Haft"
	haft.points = PackedVector2Array([layout["butt"], layout["anchor"]])
	haft.width = HAFT_WIDTH
	haft.default_color = HAFT_COLOR
	haft.begin_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(haft)
	move_child(haft, _art.get_index())

	_build_plate(layout, BACKING_COLOR, RING_COLOR, HALO_COLOR)

## The trigger, backing disc, ring and halo every pickup wears, from `layout`
## in the given colours. Shared by weapon pickups and the health pack.
func _build_plate(layout: Dictionary, backing_color: Color, ring_color: Color, halo_color: Color) -> void:
	_trigger_radius = layout["trigger_radius"]
	var circle := CircleShape2D.new()
	circle.radius = _trigger_radius
	_shape.shape = circle

	var disc: PackedVector2Array = layout["disc"]
	_backing.polygon = disc
	_backing.color = backing_color

	var ring := Line2D.new()
	ring.name = "Ring"
	ring.points = disc
	ring.closed = true
	ring.width = RING_WIDTH
	ring.default_color = ring_color
	add_child(ring)
	move_child(ring, _backing.get_index() + 1)

	_halo = Polygon2D.new()
	_halo.name = "Halo"
	_halo.polygon = disc
	_halo.color = halo_color
	add_child(_halo)
	move_child(_halo, 0)

## The health pack (#1267): the plate above with a cross on it. Shared with the
## Online client's puppet, which builds this same scene display-only.
func _build_health_pack() -> void:
	var layout: Dictionary = health_layout()
	_art_is_fallback = false
	_art.polygon = layout["outline"]
	_art.color = HEALTH_CROSS_COLOR
	_build_plate(layout, HEALTH_PLATE_COLOR, HEALTH_RING_COLOR, HEALTH_HALO_COLOR)

## The health pack's geometry, in `art_layout`'s shape ("outline", "fallback",
## "art_scale", "butt", "anchor", "trigger_radius", "disc"). Pure.
static func health_layout() -> Dictionary:
	var a: float = HEALTH_CROSS_ARM
	var t: float = HEALTH_CROSS_THICK
	var outline: PackedVector2Array = [
		Vector2(-t, -a), Vector2(t, -a), Vector2(t, -t), Vector2(a, -t), Vector2(a, t), Vector2(t, t),
		Vector2(t, a), Vector2(-t, a), Vector2(-t, t), Vector2(-a, t), Vector2(-a, -t), Vector2(-t, -t)]
	return {"outline": outline, "fallback": false, "art_scale": 1.0, "butt": Vector2.ZERO,
		"anchor": Vector2.ZERO, "trigger_radius": maxf(MIN_TRIGGER_RADIUS, HEALTH_RADIUS),
		"disc": _disc(HEALTH_RADIUS)}

## A backing circle of `radius` around the pickup's centre.
static func _disc(radius: float) -> PackedVector2Array:
	var disc := PackedVector2Array()
	for i in BACKING_SEGMENTS:
		var a: float = TAU * float(i) / float(BACKING_SEGMENTS)
		disc.append(Vector2(cos(a), sin(a)) * radius)
	return disc

## The geometry of a pickup for `stats`, shared with the Online client's puppet
## (issue #930) so both draw the same thing: "outline" (head-local art),
## "fallback", "art_scale", "butt" and "anchor" (haft ends), "trigger_radius",
## and "disc" (the backing circle). Pure: touches no node.
static func art_layout(stats: Resource) -> Dictionary:
	var outline: PackedVector2Array = PackedVector2Array()
	if stats != null and "art_outline" in stats:
		outline = stats.art_outline
	# A weapon whose head alone does not show what it is -- the grapple's
	# launcher without its hook, the flail's knob without its ball (issue
	# #150) -- carries a fuller drawing for its pickup.
	if stats != null and "pickup_art" in stats and stats.pickup_art.size() >= 3:
		outline = stats.pickup_art
	var is_fallback: bool = outline.size() < 3
	if is_fallback:
		outline = FALLBACK_ART
	var art_scale: float = ART_SCALE

	var reach: float = stats.max_reach if stats != null and "max_reach" in stats else 0.0
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
	var rot: float = DRAW_AXIS.angle()

	# The drawn weapon's furthest point from the centre, butt or head.
	var art_radius: float = butt.length() + HAFT_WIDTH * 0.5
	for point: Vector2 in outline:
		art_radius = maxf(art_radius, (anchor + (point * ART_SCALE).rotated(rot)).length())

	if art_radius > MAX_ART_RADIUS:
		var fit: float = MAX_ART_RADIUS / art_radius
		butt *= fit
		anchor *= fit
		art_scale = ART_SCALE * fit
		art_radius = MAX_ART_RADIUS

	var trigger: float = maxf(MIN_TRIGGER_RADIUS, art_radius)
	var disc_radius: float = maxf(trigger, art_radius + BACKING_MARGIN)
	return {"outline": outline, "fallback": is_fallback, "art_scale": art_scale,
		"butt": butt, "anchor": anchor, "trigger_radius": trigger, "disc": _disc(disc_radius)}

var _halo: Polygon2D
var _halo_t: float = 0.0

## The halo breathes between the disc's own size and HALO_REACH times it,
## fading as it grows. Presentational only.
func _process(delta: float) -> void:
	if _halo == null:
		return
	_halo_t = fmod(_halo_t + delta / HALO_PERIOD_SEC, 1.0)
	_halo.scale = Vector2.ONE * lerpf(1.0, HALO_REACH, _halo_t)
	_halo.modulate.a = 1.0 - _halo_t

## Issue #976: where the halo is in its breath, 0..255, for the snapshot.
func halo_phase_byte() -> int:
	return clampi(int(_halo_t * 256.0), 0, 255)

## Issue #976: the Online client's copy breathes on its own clock, kept in
## step with the host's: re-set when it is more than a tenth of a breath off.
func set_halo_phase(byte: int) -> void:
	var theirs: float = float(clampi(byte, 0, 255)) / 256.0
	var off: float = absf(_halo_t - theirs)
	if minf(off, 1.0 - off) > 0.1:
		_halo_t = theirs

func halo_phase() -> float:
	return _halo_t

## A live player's body touched the pickup: hand the weapon over and leave.
## Eliminated players have no collision layer to enter with, and are refused
## here too rather than relying on that alone (user story 19).
func _on_body_entered(body: Node) -> void:
	if _claimed or (weapon_stats == null and not is_health_pack):
		return
	if not body.is_in_group("players") or not body.alive:
		return
	if is_health_pack:
		# A fighter with no damage gains nothing: leave the pack for a hurt one.
		if float(body.damage) > 0.0:
			_claim_health(body)
		return
	# #1006: a fighter already holding this weapon gains nothing; leave the
	# pickup for someone else (or for them once they switch).
	if body.weapon_stats != null and body.weapon_stats.resource_path == weapon_stats.resource_path:
		return
	_claimed = true
	# Safe mid-flush: set_weapon_stats() only records the weapon and defers
	# the rig rebuild itself, which is the part the physics server would
	# refuse while it is still flushing the query that fired this signal.
	body.set_weapon_stats(weapon_stats)
	if body.has_signal("weapon_picked_up"):
		body.weapon_picked_up.emit(weapon_stats.resource_path.get_file().get_basename().capitalize())
	PickupCalloutScript.show_for(body, weapon_stats.resource_path.get_file().get_basename(), get_parent()) # #818
	queue_free()

## #1267: the first hurt, living body to touch a health pack heals to full --
## damage back to 0, which the body fill and the snapshot follow on their own --
## and the pack is gone. Their weapon is untouched. A spawn-protected fighter
## claims it like a weapon pickup would. The grab sound plays off the `healed`
## signal (SfxHooks, so Online joiners hear it through the Sfx trailer) and the
## "Healed!" callout shows.
func _claim_health(body: Node) -> void:
	_claimed = true
	body.damage = 0.0
	if body.has_signal("healed"):
		body.healed.emit()
	PickupCalloutScript.show_for(body, "", get_parent(), HEALTH_CALLOUT_KEY)
	queue_free()
