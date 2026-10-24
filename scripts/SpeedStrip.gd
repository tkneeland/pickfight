extends StaticBody2D

## Speed strip stage part (issue #891): the mirror of `MudPatch`. A strip of
## solid ground that speeds a player up: while a player's body rests on it,
## the drag on its horizontal speed (along the strip's own X) is partly
## cancelled, so running tops out at about 1.5x its flat-floor pace and gets
## there faster. Leaving the strip stops the boost at once.
##
## A `StaticBody2D`, like `Conveyor`, `IcePatch` and `MudPatch`: ordinary
## terrain on the world layer. A thin `Area2D` band along the top face picks
## candidates, and the body's contact monitor decides who is really standing
## on it, so a player in the air above the strip is unaffected.
##
## **X only, nothing written.** Only the component along the strip's X is
## scaled, so jumping and falling are not boosted, and no body property is
## changed, so nothing needs restoring. The body's weapon (head and haft) gets
## the same factor, as `Conveyor` moves them together.
##
## **Heads are untouched (ADR-0006, ADR-0010).** The detector masks only the
## world layer, which a weapon head is not on, and a head is only sped up as
## part of its own player's weapon while that player stands on the strip.
##
## `_ready()` builds collision, visual and detector from the exports.

## Preloaded by path, never by `class_name` (CLAUDE.md).
const PartKitScript := preload("res://scripts/PartKit.gd")

## The strip's collision and visual box, centred on the node.
@export var size: Vector2 = Vector2(160, 8)

## Drag cancelled per second along the strip's X. A body's own linear damping
## is 1.5, and top speed goes as the inverse of the drag, so 1.5 -> 1.0 is 1.5x.
const BOOST_RATE: float = 0.5
## Dark teal base with pale chevrons pointing right.
const STRIP_COLOR: Color = Color(0.1, 0.4, 0.45, 1)
const CHEVRON_COLOR: Color = Color(0.7, 1.0, 0.95, 0.95)
const _DETECTOR_ABOVE: float = 6.0
const _DETECTOR_BELOW: float = 2.0
const _CHEVRON_SPACING: float = 24.0

## Issue #1058: a whoosh when a living fighter first steps onto the strip, at
## most once per fighter per second (the `MudPatch` squelch pattern). Played on
## the host only; online clients hear it through the generic Sfx snapshot
## trailer, so nothing here is replicated.
const WHOOSH_INTERVAL_SEC: float = 1.0

var _detector: Area2D
## Instance ids of the fighters boosting last tick.
var _boosting_last: Dictionary = {}
## Instance id -> seconds until that fighter may whoosh again.
var _whoosh_wait: Dictionary = {}

func _ready() -> void:
	var half: Vector2 = size / 2.0
	PartKitScript.add_rect_shape(self, size)

	var strip := Polygon2D.new()
	strip.name = "Strip"
	strip.color = STRIP_COLOR
	strip.polygon = PartKitScript.rect_polygon(size)
	add_child(strip)

	var chevrons := Node2D.new()
	chevrons.name = "Chevrons"
	add_child(chevrons)
	var count: int = maxi(1, int(size.x / _CHEVRON_SPACING))
	for i in count:
		var chevron := Line2D.new()
		chevron.width = 1.5
		chevron.default_color = CHEVRON_COLOR
		var x: float = -half.x + _CHEVRON_SPACING * (float(i) + 0.5)
		chevron.points = PackedVector2Array([
			Vector2(x - 3.0, -half.y * 0.7), Vector2(x + 3.0, 0.0), Vector2(x - 3.0, half.y * 0.7),
		])
		chevrons.add_child(chevron)

	# World layer only: player bodies, not heads.
	_detector = PartKitScript.add_top_detector(self, size, _DETECTOR_ABOVE, _DETECTOR_BELOW)

func _physics_process(delta: float) -> void:
	for id: int in _whoosh_wait.keys():
		var left: float = float(_whoosh_wait[id]) - delta
		if left <= 0.0:
			_whoosh_wait.erase(id)
		else:
			_whoosh_wait[id] = left
	var now: Dictionary = {}
	for body: Node2D in _detector.get_overlapping_bodies():
		if body is RigidBody2D and body.is_in_group("players") and PartKitScript.touching(self, body):
			_boost(body as RigidBody2D, delta)
			if bool(body.get("alive")):
				var id: int = body.get_instance_id()
				now[id] = true
				if not _boosting_last.has(id) and not _whoosh_wait.has(id):
					_whoosh_wait[id] = WHOOSH_INTERVAL_SEC
					PartKitScript.sfx(self, &"strip_boost", body.global_position)
	_boosting_last = now

## True while `body` is standing on the strip.
func is_boosting(body: RigidBody2D) -> bool:
	return _detector != null and _detector.get_overlapping_bodies().has(body) and PartKitScript.touching(self, body)

## The body and its weapon (head and haft) get the same factor; see `Conveyor`.
func _boost(body: RigidBody2D, delta: float) -> void:
	var axis: Vector2 = global_transform.x.normalized()
	var gain: float = exp(BOOST_RATE * delta)
	for part: RigidBody2D in [body] + PartKitScript.weapon_bodies_of(get_tree(), body):
		var along: float = part.linear_velocity.dot(axis)
		part.linear_velocity += axis * along * (gain - 1.0)
