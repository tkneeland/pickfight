extends StaticBody2D

## Mud patch stage part (issue #880): the mirror of `IcePatch`. A strip of
## solid ground that bogs a player down: while a player's body rests on it,
## its horizontal speed (along the strip's own X) is bled off by extra
## damping, so running tops out at roughly half its flat-floor pace.
##
## A `StaticBody2D`, like `Conveyor` and `IcePatch`: ordinary terrain on the
## world layer. A thin `Area2D` band along the top face picks candidates, and
## the body's contact monitor decides who is really standing on it, so a
## player in the air above the strip is unaffected.
##
## **X only.** Only the component along the strip's X is damped, so jumping,
## falling and climbing are not slowed. The body's weapon (head and haft) is
## damped by the same factor, as `Conveyor` moves them together, so the
## weapon's drive has no reach error to haul the body back with. Nothing is
## written to a body, so nothing needs restoring: leaving the strip simply
## stops the damping.
##
## **Heads are untouched (ADR-0006, ADR-0010).** The detector masks only the
## world layer, which a weapon head is not on, and a head is only ever damped
## as part of its own player's weapon while that player stands in the mud.
## A loose head, or one resting on the mud, is left alone.
##
## `_ready()` builds collision, visual and detector from the exports.

## Preloaded by path, never by `class_name` (CLAUDE.md).
const PartKitScript := preload("res://scripts/PartKit.gd")

## The strip's collision and visual box, centred on the node.
@export var size: Vector2 = Vector2(160, 10)

## Extra linear damping per second applied along the strip's X while a body
## stands in the mud. On top of the player's own damping of 1.5 this roughly
## halves the speed a steady run reaches.
const MUD_DAMP: float = 1.8
## Dark brown, with lighter and darker specks.
const MUD_COLOR: Color = Color(0.32, 0.21, 0.12, 1)
const SPECK_COLORS: Array[Color] = [Color(0.2, 0.12, 0.06, 1), Color(0.5, 0.36, 0.2, 1)]
const _DETECTOR_ABOVE: float = 6.0
const _DETECTOR_BELOW: float = 2.0
const _SPECK_SPACING: float = 14.0

## Issue #987: a squelch when a living fighter wades in, at most once per
## fighter per second. Played on the host only; online clients hear it through
## the generic Sfx snapshot trailer, so nothing here is replicated.
const SQUELCH_INTERVAL_SEC: float = 1.0

var _detector: Area2D
## Instance ids of the fighters bogging last tick.
var _bogging_last: Dictionary = {}
## Instance id -> seconds until that fighter may squelch again.
var _squelch_wait: Dictionary = {}

func _ready() -> void:
	var half: Vector2 = size / 2.0
	PartKitScript.add_rect_shape(self, size)

	var mud := Polygon2D.new()
	mud.name = "Mud"
	mud.color = MUD_COLOR
	mud.polygon = PartKitScript.rect_polygon(size)
	add_child(mud)

	var specks := Node2D.new()
	specks.name = "Specks"
	add_child(specks)
	var count: int = maxi(1, int(size.x / _SPECK_SPACING))
	for i in count:
		var speck := Polygon2D.new()
		speck.color = SPECK_COLORS[i % SPECK_COLORS.size()]
		var x: float = -half.x + _SPECK_SPACING * (float(i) + 0.5)
		var y: float = half.y * (0.5 if i % 2 == 0 else -0.3)
		speck.polygon = PackedVector2Array([
			Vector2(x - 2.0, y - 1.5), Vector2(x + 2.0, y - 1.5),
			Vector2(x + 2.0, y + 1.5), Vector2(x - 2.0, y + 1.5),
		])
		specks.add_child(speck)

	# World layer only: player bodies, not heads.
	_detector = PartKitScript.add_top_detector(self, size, _DETECTOR_ABOVE, _DETECTOR_BELOW)

func _physics_process(delta: float) -> void:
	for id: int in _squelch_wait.keys():
		var left: float = float(_squelch_wait[id]) - delta
		if left <= 0.0:
			_squelch_wait.erase(id)
		else:
			_squelch_wait[id] = left
	var now: Dictionary = {}
	for body: Node2D in _detector.get_overlapping_bodies():
		if body is RigidBody2D and body.is_in_group("players") and PartKitScript.touching(self, body):
			_bog(body as RigidBody2D, delta)
			if bool(body.get("alive")):
				var id: int = body.get_instance_id()
				now[id] = true
				if not _bogging_last.has(id) and not _squelch_wait.has(id):
					_squelch_wait[id] = SQUELCH_INTERVAL_SEC
					PartKitScript.sfx(self, &"mud_squelch", body.global_position)
	_bogging_last = now

## True while `body` is standing in the mud.
func is_bogging(body: RigidBody2D) -> bool:
	return _detector != null and _detector.get_overlapping_bodies().has(body) and PartKitScript.touching(self, body)

## The body and its weapon (head and haft) are damped together; see `Conveyor`.
func _bog(body: RigidBody2D, delta: float) -> void:
	var axis: Vector2 = global_transform.x.normalized()
	var keep: float = exp(-MUD_DAMP * delta)
	for part: RigidBody2D in [body] + PartKitScript.weapon_bodies_of(get_tree(), body):
		var along: float = part.linear_velocity.dot(axis)
		part.linear_velocity -= axis * along * (1.0 - keep)
