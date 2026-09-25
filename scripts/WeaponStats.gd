class_name WeaponStats
extends Resource

## Everything that makes one weapon different from another (ADR-0005: the
## weapon carries reach, weight, responsiveness, damage and the head's shape).
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
## Applied by `Player._strike_damage`, from both the sweep path and the
## solver path.
@export var damage: float = 34.0

# --- Firing: a weapon that shoots as well as swings (issue #55, ADR-0014) ----
#
# Every default here means "does not fire", so a weapon that sets none of them
# -- every weapon but the boomstick, and every stub a scenario builds -- is
# exactly the melee weapon it always was. `Player` reads `fire_interval` alone
# to decide whether a weapon fires at all.

## Seconds between shots, fired automatically straight down the barrel (the
## haft's direction). The countdown starts when the weapon is put in the
## player's hands -- a pickup, a round start -- so the first shot comes one
## whole interval later, never at once. 0 means the weapon never fires.
@export var fire_interval: float = 0.0
## Damage one bullet deals when it hits a player. Flat: a bullet's speed is
## fixed, so there is no strike speed to scale it by.
@export var projectile_damage: float = 0.0
## How fast a bullet flies, in px/s. Straight, with no gravity.
@export var projectile_speed: float = 0.0
## Impulse a bullet gives the player it hits, along its line of flight.
@export var projectile_knockback: float = 0.0
## The bullet's radius: what it is drawn as and what it is swept as.
@export var projectile_radius: float = 3.0
## Impulse each shot gives the shooter's body, back along the barrel.
@export var recoil_impulse: float = 0.0

# --- Sound (issue #75, ADR-0016) ---------------------------------------------

## Which of `Sfx`'s per-weapon sounds this weapon makes: its strikes play
## `hit_<sound_set>`, and if it fires, its shots play `fire_<sound_set>`. Every
## weapon in `resources/` names its own. The default is the pickaxe's, which
## is what a bare `WeaponStats.new()` stands in for.
@export var sound_set: StringName = &"pickaxe"

# --- The head: what it hits with, and what it is drawn as --------------------
#
# ADR-0010. A weapon head is a **cluster of circles fitted to the drawn art**,
# not one shape doing both jobs. Two things are stored, in the same head-local
# space, and `Player` builds one from each:
#
#   * `head_circle_offsets` / `head_circle_radii` -- the collision. One
#     `CollisionShape2D` per circle on the single head body.
#   * `art_outline` -- the visual. The polygon the head is drawn as.
#
# The guarantee between them is one-directional and is what
# `weapon_head_circles_within_art` in tools/scenario_runner.gd checks: every
# circle lies inside the outline, within a small tolerance. The art may reach
# a little past the circles -- a crescent's horns taper to nothing and no
# circle of any useful size fits in the tip -- because a player is never hit
# by something they cannot see, which is the promise that matters. It does
# not run the other way.
#
# Circles only, never traced polygons: ADR-0010 defers polygon collision, and
# `WeaponHead`'s interpenetration correction and tunnelling sweep are written
# per-circle.
#
# Head-local space has **+X pointing outward along the haft**, away from the
# player, with the origin at the groove anchor -- the point the haft holds the
# head by, and the point reach is measured to. `Player` turns the whole
# cluster and the outline together to face along the haft each tick, so both
# are authored once, facing +X.

## Centre of each collision circle, and its radius. Parallel arrays rather
## than a list of sub-resources: a weapon is authored by hand in a `.tres`,
## and two flat arrays are the form a traced cluster is legible in there.
## Pairs are read up to the shorter of the two, so a half-edited resource
## loses a circle rather than crashing the rig -- see `head_circle_count()`.
@export var head_circle_offsets: PackedVector2Array = PackedVector2Array()
@export var head_circle_radii: PackedFloat32Array = PackedFloat32Array()

## The head's drawn shape, traced by hand from the weapon's drawing
## (docs/art/weapons-whiteboard.jpg) and sized against the player body. This
## is what a player sees, so it is what the circles are fitted to.
@export var art_outline: PackedVector2Array = PackedVector2Array()

## Whether the head is one-sided and mirrors across the haft to follow the
## aim. Every head is authored facing +X with one side of it on +Y; a
## symmetric head leaves that alone, and one with `flips_with_aim` has
## `Player` flip every circle's and outline point's Y whenever the aim crosses
## the vertical, so the side it is drawn on stays the same side of the screen
## whichever way the player faces. The axe is the only one (#16).
@export var flips_with_aim: bool = false

## The head a bare `WeaponStats.new()` gets: the round nub the pickaxe used
## to be, drawn as itself. Scenarios build stub stats that way to vary reach
## or force without authoring a head, so the default has to be a working
## weapon rather than a head that collides with nothing.
const DEFAULT_HEAD_RADIUS: float = 8.0
const DEFAULT_OUTLINE_SEGMENTS: int = 16

func _init() -> void:
	if head_circle_offsets.is_empty() and head_circle_radii.is_empty():
		head_circle_offsets = PackedVector2Array([Vector2.ZERO])
		head_circle_radii = PackedFloat32Array([DEFAULT_HEAD_RADIUS])
	if art_outline.is_empty():
		art_outline = _circle_outline(DEFAULT_HEAD_RADIUS, DEFAULT_OUTLINE_SEGMENTS)

## How many collision circles this head actually has: the shorter of the two
## parallel arrays, which is the number of complete offset-and-radius pairs
## they describe between them.
func head_circle_count() -> int:
	return mini(head_circle_offsets.size(), head_circle_radii.size())

## A drawn circle of `radius`, as a polygon that **contains** it rather than
## one inscribed in it: the corners sit on a slightly larger circle so the
## flat sides fall exactly on `radius`. The difference is 0.16 px at the
## default head -- invisible -- and it is what keeps the default weapon's own
## circle inside its own art on the geometry rather than on the containment
## tolerance.
func _circle_outline(radius: float, segments: int) -> PackedVector2Array:
	var corner: float = radius / cos(PI / float(segments))
	var points := PackedVector2Array()
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		points.append(Vector2(cos(a), sin(a)) * corner)
	return points
