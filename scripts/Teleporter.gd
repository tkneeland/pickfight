extends Area2D

## Teleporter stage part (issue #881): a portal that sends a fighter to its
## `twin`. A player body that enters appears at the twin's centre keeping its
## velocity, and both portals then ignore that body for `COOLDOWN_SEC` so
## nobody ping-pongs between them.
##
## **Who travels.** Only a living player's body (the `players` group, `alive`
## true). Ghosts and the dead are skipped. The detector masks only the world
## layer, which a weapon head is not on (ADR-0006, ADR-0010).
##
## **The weapon comes along.** The body's weapon (head and haft, found as
## `Conveyor` finds it) is moved by the same offset with the same velocity, so
## nothing is left behind or stretched across the map.
##
## Pair two portals by setting each one's `twin` to the other. `_ready()`
## builds the detector and ring visual from the exports; a portal with no
## resolvable twin does nothing.

## Preloaded by path, never by `class_name` (CLAUDE.md), for `HEAD_GROUP`.
const WeaponHeadType := preload("res://scripts/WeaponHead.gd")

## The other end of the pair.
@export var twin: NodePath
## Detector and ring radius.
@export var radius: float = 30.0
## Ring colour; give a pair the same one.
@export var ring_color: Color = Color(0.4, 0.8, 1.0, 1)

## Seconds both portals ignore a body after it travels.
const COOLDOWN_SEC: float = 1.0
const _PULSE_SEC: float = 0.3
const _PULSE_SCALE: float = 1.5

var _ring: Node2D
var _clock: float = 0.0
var _pulse_remaining: float = 0.0
## body -> `_clock` value at which this portal accepts it again.
var _ignored: Dictionary = {}

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1  # world layer only: player bodies, not heads
	monitoring = true
	var circle := CircleShape2D.new()
	circle.radius = radius
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	shape.shape = circle
	add_child(shape)

	_ring = Node2D.new()
	_ring.name = "Ring"
	add_child(_ring)
	for i in 2:
		var ring := Line2D.new()
		ring.width = 3.0 if i == 0 else 1.5
		ring.default_color = ring_color if i == 0 else ring_color.lightened(0.5)
		var r: float = radius * (1.0 if i == 0 else 0.65)
		var pts := PackedVector2Array()
		for step in 33:
			var a: float = TAU * float(step) / 32.0
			pts.append(Vector2(cos(a), sin(a)) * r)
		ring.points = pts
		_ring.add_child(ring)

## The twin portal, or null when unset or not a teleporter.
func get_twin() -> Node2D:
	var node: Node = get_node_or_null(twin)
	if node == null or node == self or not node.has_method("receive"):
		return null
	return node as Node2D

## True while this portal is ignoring `body`.
func is_ignoring(body: Node) -> bool:
	return _ignored.has(body) and float(_ignored[body]) > _clock

func _physics_process(delta: float) -> void:
	_clock += delta
	for body: Variant in _ignored.keys():
		if not is_instance_valid(body) or float(_ignored[body]) <= _clock:
			_ignored.erase(body)
	if _pulse_remaining > 0.0:
		_pulse_remaining = maxf(0.0, _pulse_remaining - delta)
		var t: float = _pulse_remaining / _PULSE_SEC
		_ring.scale = Vector2.ONE if _reduce_flash() else Vector2.ONE * lerpf(1.0, _PULSE_SCALE, t)
	var destination: Node2D = get_twin()
	if destination == null:
		return
	for body: Node2D in get_overlapping_bodies():
		if body is RigidBody2D and body.is_in_group("players") and _can_travel(body):
			_send(body as RigidBody2D, destination)

func _can_travel(body: Node2D) -> bool:
	if not bool(body.get("alive")) or is_ignoring(body):
		return false
	return true

func _send(body: RigidBody2D, destination: Node2D) -> void:
	var offset: Vector2 = destination.global_position - body.global_position
	var parts: Array[RigidBody2D] = _weapon_bodies_of(body)
	body.global_position += offset
	for part: RigidBody2D in parts:
		part.global_position += offset
	_ignored[body] = _clock + COOLDOWN_SEC
	_flash()
	_sfx(&"teleport", body.global_position - offset)
	destination.receive(body)

## Called by the portal a body arrived from: start ignoring it here too.
func receive(body: Node2D) -> void:
	_ignored[body] = _clock + COOLDOWN_SEC
	_flash()
	_sfx(&"teleport", global_position)

func _flash() -> void:
	_pulse_remaining = _PULSE_SEC

## The rigid bodies of `body`'s weapon (head and haft); see
## `Conveyor._weapon_bodies_of()`.
func _weapon_bodies_of(body: RigidBody2D) -> Array[RigidBody2D]:
	var parts: Array[RigidBody2D] = []
	var rid: RID = body.get_rid()
	for head: Node in get_tree().get_nodes_in_group(WeaponHeadType.HEAD_GROUP):
		if head.is_queued_for_deletion() or not (head is RigidBody2D) or not rid in head.sweep_exclude:
			continue
		for child: Node in head.get_parent().get_children():
			if child is RigidBody2D and child != body and not parts.has(child):
				parts.append(child as RigidBody2D)
	return parts

func _sfx(sound: StringName, at: Vector2) -> void:
	var sfx: Node = get_node_or_null(^"/root/Sfx")
	if sfx != null:
		sfx.play(sound, at, 1.0)

func _reduce_flash() -> bool:
	var sfx: Node = get_node_or_null(^"/root/Sfx")
	return sfx != null and bool(sfx.get("reduce_flash"))
