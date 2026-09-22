class_name WeaponStats
extends Resource

## Everything that makes one weapon different from another (ADR-0005: the
## weapon carries reach, weight, responsiveness, damage and head shape).
##
## The pickaxe is the only instance today (`resources/pickaxe.tres`); the
## indirection exists now because retrofitting it later would mean reworking
## the player again. Player reads these values when it builds its weapon rig,
## so `Player.set_weapon_stats()` is what makes a weapon swappable at runtime.
##
## These are physical quantities, not feel fudges: mass is real mass, the
## drive caps are real caps. `max_drive_force` in particular is the single
## number a clash is resolved by -- the drive is hand-written precisely
## because Godot's joint motors have no force cap to lose a contest with
## (ADR-0006).

## Reach. `min_reach` is rest extension, `max_reach` is full drag. The head
## is physically confined between the two, so reach is a real limit rather
## than a number the drive politely respects.
@export var min_reach: float = 20.0
@export var max_reach: float = 140.0

## Mass of the head -- the part that actually hits things. The haft gets a
## small fraction of it (Player.HAFT_MASS_FRACTION) so the assembly has
## honest rotational inertia without the haft dominating.
@export var mass: float = 0.25

## Responsiveness: how fast the drive is allowed to slew the weapon. Angular
## in rad/s, extension in px/s. A heavy weapon lowers these and raises
## `max_drive_force`; a light one does the reverse.
@export var drive_speed: float = 24.0
@export var extend_speed: float = 700.0

## How fast the weapon eases back to `min_reach` when the player lets go.
## Separate from `extend_speed` because release should read as a deliberate
## action rather than a snap.
@export var rest_return_speed: float = 400.0

## The cap on every force the drive is allowed to apply, and (via the lever
## arm to the head) on every torque. This is the stat that decides who gives
## way when two heads meet.
@export var max_drive_force: float = 6000.0

## Damage a strike with this head deals, scaled at contact by head speed.
## Carried here from the start; nothing applies it yet.
@export var damage: float = 34.0

## The head's collision region -- per weapon, and not a point: a pickaxe's is
## a nub at the tip, a sword's would be most of the blade. `Player` draws the
## head's silhouette straight from this shape (see
## `Player._build_head_visual`) rather than from a parallel size number, so
## the drawing and the hitbox cannot drift apart.
@export var head_shape: Shape2D

func _init() -> void:
	if head_shape == null:
		var nub := CircleShape2D.new()
		nub.radius = 8.0
		head_shape = nub
