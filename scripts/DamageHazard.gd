extends Area2D

## Shared contact rule for the damage stage parts, Spikes and Saw (issue #282,
## ADR-0008). Not the lava of `KillZone.gd`, which eliminates on touch: a
## touch here is a big chunk of damage plus a shove away from the hazard, so
## it is survivable and recoverable, and a player who has taken damage is
## nearer the edge of dying to the next thing that hits them.
##
## The damage goes through `Player.take_damage()`, the one damage path, so
## elimination, deaths and scoring behave exactly as for a weapon KO. The hit
## is also reported on the victim's `strike_landed` so the damage number and
## hit marker appear. Each player has their own short cooldown, so one touch
## (a body lingering in the blades, or a shove that leaves it overlapping on
## the next tick) is counted once.
##
## Only player bodies are hurt: the detector masks the world layer, where
## bodies live and weapon heads do not (ADR-0010), so a weapon head poking
## into a hazard is not a touch. Subclasses build their shape and visual and
## may override `knockback_direction()`. Never referenced by `class_name`
## (CLAUDE.md): subclasses extend this script by path.

## Damage dealt per touch. `Player.DEATH_DAMAGE` is 100, so 40 is a big chunk.
@export var damage: float = 40.0
## Speed, in px/s, the player is thrown away from the hazard at.
@export var knockback_speed: float = 900.0
## Seconds before the same player can be hurt by this hazard again.
@export var hit_cooldown_sec: float = 0.8

## Fallback hazard colour; `Stage.gd` recolours with the mood's kill colour.
const DEFAULT_COLOR: Color = Color(0.85, 0.15, 0.05, 1)
const WeaponHeadType := preload("res://scripts/WeaponHead.gd")

var _cooldowns: Dictionary = {}
var _hits: int = 0

func _init() -> void:
	collision_layer = 0
	collision_mask = 1

## How many touches have landed. Observable, for scenarios.
func hit_count() -> int:
	return _hits

## Recolours the hazard; `Stage.gd` passes the mood's kill colour.
func set_hazard_color(_colour: Color) -> void:
	pass

## The unit direction the player is thrown. Default: straight away from the
## hazard's centre.
func knockback_direction(body: Node2D) -> Vector2:
	var away: Vector2 = body.global_position - global_position
	return away.normalized() if away.length() > 0.001 else Vector2.UP

func _physics_process(delta: float) -> void:
	for id: int in _cooldowns.keys():
		_cooldowns[id] = float(_cooldowns[id]) - delta
		if _cooldowns[id] <= 0.0:
			_cooldowns.erase(id)
	for body: Node2D in get_overlapping_bodies():
		if body is RigidBody2D and body.is_in_group("players") and body.get("alive") == true:
			if not _cooldowns.has(body.get_instance_id()):
				_hurt(body as RigidBody2D)

func _hurt(body: RigidBody2D) -> void:
	_cooldowns[body.get_instance_id()] = hit_cooldown_sec
	if body.get("spawn_protected") == true:
		return
	_hits += 1
	var dir: Vector2 = knockback_direction(body)
	var change: Vector2 = dir * knockback_speed - body.linear_velocity
	body.linear_velocity += change
	for part: RigidBody2D in _weapon_bodies_of(body):
		part.linear_velocity += change
	body.take_damage(damage)
	if body.has_signal("strike_landed"):
		body.strike_landed.emit(body, damage, body.global_position, not body.alive)

## The body's weapon rigid bodies, so the shove carries the whole player and
## the joint drive has no reach error to haul back (see `BouncePad.gd`).
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
