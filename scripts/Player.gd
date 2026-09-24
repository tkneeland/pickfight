extends RigidBody2D

## A player: a rotation-locked body, and the weapon it drives.
##
## The weapon is one real object used for movement, damage and blocking
## (ADR-0005), built as a rigid body joined to the body and driven by clamped
## forces (ADR-0006). The rig is:
##
##   body --PinJoint2D--> haft --GrooveJoint2D--> head
##
## The haft is invisible to physics and carries the assembly's rotational
## inertia; the head is the only part with a collision shape, so only the head
## strikes, blocks and plants. The head also checks its own work each tick and
## undoes any tunnelling through thin geometry, which is its own script's job
## to explain. Both joints are passive constraints with no
## motor: on Godot 4.6.2 `PinJoint2D`'s motor has no force or torque cap and
## `GrooveJoint2D` has no actuation at all, so the drive is hand-written here
## and clamped at `WeaponStats.max_drive_force` -- the cap is what lets a
## weaker weapon lose a contest instead of deadlocking.
##
## Combat is split in two, and the split is the point (ADR-0005). A head
## striking a player deals damage, scaled by how fast the head is moving:
## that is the swing, and it is the only thing that hurts anyone. Colliding
## body-to-body knocks players around and deals nothing: that is movement.
## Rewarding players for flailing their mass into opponents would undercut
## the one thing the game is about, which is that better swinging wins.
##
## Damage accumulates within a round and eliminates at DEATH_DAMAGE
## (ADR-0004). `eliminate()` is the one path both a ring-out and accumulated
## damage take; it freezes and hides the player where they were, carrying
## whatever damage they had, until `start_round()` brings them back with it
## reset. There is no mid-round respawn.
##
## Per ADR-0003, the weapon is driven by a relative unit-disc input vector
## (Vector2.ZERO means "not touching") rather than an absolute cursor
## position. A bound controller supplies that vector over the network; the
## debug sources below (mouse, keyboard) exist only for host-side testing and
## are ignored entirely while a controller is bound. The mouse source only
## reports a vector while a mouse button is held, so like a phone it asserts
## nothing when nobody is touching it.

## Preloaded rather than referenced by their `class_name`. A `class_name` is
## resolved through Godot's global script class cache, which lives in the
## gitignored `.godot/` directory and is only built by an editor run -- so on a
## fresh clone every one of these types is undeclared and this script fails to
## parse. `godot --headless --quit` still exits 0 in that state, so the failure
## is silent. A preload is resolved from the path and needs no cache.
const WeaponStatsType := preload("res://scripts/WeaponStats.gd")
const WeaponHeadType := preload("res://scripts/WeaponHead.gd")
## The weapon a player holds unless it won the previous round (ADR-0005): the
## one place game code names the pickaxe's path (the scenario runner spells it
## out independently, on purpose, to check against). `start_round()` resets to
## this whenever `keeps_weapon` is false; `_ready()` falls back to it too.
const DEFAULT_WEAPON_STATS := preload("res://resources/pickaxe.tres")

enum DebugSource { NONE, MOUSE, KEYBOARD }

const KEYBOARD_MIN_T: float = 0.001

## Physics layers. Terrain and player bodies share layer 1 as they always
## have, so the arena and the kill zone are untouched by this rework. Weapon
## heads get layer 2 so a head can be masked independently: it collides with
## terrain, with player bodies and with other heads, and is excluded from its
## own player's body by an explicit collision exception. The haft has no
## collision shape at all, which is the strongest available form of
## "collides with nothing".
const LAYER_WORLD: int = 1
const LAYER_HEAD: int = 2

## The haft's share of the weapon's mass. It exists to give the assembly
## honest rotational inertia and somewhere to apply torque; the head is where
## the weight that matters lives.
const HAFT_MASS_FRACTION: float = 0.2
const MIN_HAFT_MASS: float = 0.05

## How far past straight up or straight down the aim has to go before a
## one-sided head (`WeaponStats.flips_with_aim`) changes sides: ten degrees.
## Inside that band the head keeps the side it had, so holding the weapon
## vertical does not make it flicker. See `_update_head_mirror()`.
const HEAD_FLIP_DEADBAND: float = PI / 18.0

## Damage a player dies at. A scale, not a health bar -- there is no health
## bar, and how hurt a player is shows on their body -- but the number has to
## be something, and 100 is the one every per-hit figure below is read
## against.
const DEATH_DAMAGE: float = 100.0

## What counts as a strike, in head speed.
##
## Below MIN_STRIKE_SPEED a contact is not a swing and takes nothing off
## anyone. The floor is set by what the rig does when nobody is attacking:
## landing a plant on another player bounces the head at 240-660 px/s while
## it settles, and a body walking an extended head into someone moves it at
## whatever the body is doing. None of that is a strike, and if it were, a
## player could kill by leaning on someone.
##
## At FULL_STRIKE_SPEED a strike deals exactly `WeaponStats.damage`, and it
## scales linearly from the floor to there and on past it. 2200 px/s is a
## committed full-reach sweep; the fastest the moveset produces in clear air
## is about 2700, and a head carried by a flying body can beat that, so the
## scale is capped -- at MAX_STRIKE_SCALE the pickaxe deals 68.
##
## The scale cap alone does not keep a single strike from killing from full
## health once weapons differ: the axe's 55 would reach 110. MAX_STRIKE_DAMAGE
## is the rule itself, applied to every weapon -- however fast a strike
## arrives, it leaves a full-health victim standing.
const MIN_STRIKE_SPEED: float = 700.0
const FULL_STRIKE_SPEED: float = 2200.0
const MAX_STRIKE_SCALE: float = 2.0
const MAX_STRIKE_DAMAGE: float = 90.0

## Colour the body fill lerps toward as `damage` climbs to `DEATH_DAMAGE`.
## Identity does not live here any more (ADR-0005) -- see `identity_color` --
## so the fill is free to just tell the damage story, including converging
## with every other player's fill at high damage. That convergence is fine
## precisely because identity has already moved off this node.
const DAMAGE_FILL_COLOR: Color = Color(0.85, 0.1, 0.08, 1.0)

## Marks a weapon head drawn without art of its own -- a stats resource whose
## `art_outline` is not a polygon. Deliberately not a plausible weapon colour:
## a fallback that quietly looked like a normal head would hide the exact bug
## this closes -- the drawn head and the real hitbox parting ways again -- so
## it is wrong in a way a player would notice instead of a way they would
## trust.
const FALLBACK_HEAD_COLOR: Color = Color(1.0, 0.0, 1.0, 1.0)

## The haft's line width near the body and near the head. Tapered rather than
## constant so it reads as a haft -- a handle with a working end -- instead of
## a bar of uniform thickness. Purely presentational: the haft has no
## collision shape of its own to derive a width from (CONTEXT.md: it collides
## with nothing).
const HAFT_BASE_WIDTH: float = 10.0
const HAFT_TIP_WIDTH: float = 4.0
const HAFT_COLOR: Color = Color(0.42, 0.3, 0.2, 1.0)

## Which weapon this player is holding. Swappable at runtime through
## `set_weapon_stats()`; the pickaxe is the only instance today.
@export var weapon_stats: WeaponStatsType
@export var rotate_speed: float = 3.0
@export var reach_speed: float = 220.0
@export var knockback_threshold: float = 300.0
@export var knockback_scale: float = 0.5
## Impulse scales with closing speed with no natural ceiling; a hard fall or a
## full-power swing can produce a relative velocity far past anything the
## knockback feel was tuned around, launching the other player at an
## explosive, uncontrollable speed. Clamped here so the shove stays punchy
## without ever becoming a teleport.
@export var max_knockback_speed: float = 1600.0
@export var debug_source: DebugSource = DebugSource.NONE
@export var mouse_drag_radius: float = 140.0
## Whether this player starts active on its own, the way every scenario in
## `tools/scenario_runner.gd` expects. A round loop that owns this player
## sets this false in the scene and drives entry through `start_round()`
## instead -- see `_ready()`.
@export var start_in_round: bool = true

## The colour that identifies this player: a persistent outline traced around
## the body, and the fill of the weapon's head. Both stay constant at any
## damage level (ADR-0005) -- unlike the body fill, which reddens with
## `damage` and so cannot carry identity once someone is hurt. Paired with
## `SLOT_COLORS` in controller/index.html the same way the body fill used to
## be; see scenes/Main.tscn for the pairing and its comment.
@export var identity_color: Color = Color(0.9, 0.9, 0.95, 1.0)

var input_vector: Vector2 = Vector2.ZERO
var has_controller: bool = false

## Damage taken so far this round, and how many times this player has been
## eliminated. Both are observable state a scenario or a display can read;
## nothing else about being hurt is stored.
var damage: float = 0.0
var deaths: int = 0

## A strike this player's head landed on `victim` (issue #33), for whatever
## shows it -- `HitFeedback` draws the hitmarker and damage number. `amount`
## is what `victim` took, and 0 for a real swing (head faster than
## `knockback_threshold`) too slow to count; slower contacts report nothing.
## `point` is the head's leading edge; `lethal` is whether it eliminated.
signal strike_landed(victim: Node, amount: float, point: Vector2, lethal: bool)

## This player was just eliminated, by either route (issue #34) -- for
## whatever tells the player so; `RoundManager` buzzes their phone. Not
## emitted by `leave_round()`: finishing a round alive is not an elimination.
signal eliminated

## Whether this player is in play. False from elimination (damage or a
## ring-out) until `start_round()` brings them back for the next round --
## there is no mid-round respawn (ADR-0004): a round is over the same body
## every player entered it with.
var alive: bool = true

## The weapon setpoints the input vector asks for: a world angle in radians
## and a reach in pixels. These are what the host commands, not what the
## physics delivered -- for where the weapon actually is, read
## `weapon_head_position()`, which is what a player sees.
var weapon_angle: float = 0.0
var weapon_length: float = 20.0
var weapon_min_length: float = 20.0

var _keyboard_angle: float = 0.0
var _keyboard_t: float = 0.5
# NAN means "no button held"; set on press, the drag is measured from here.
var _mouse_anchor: Vector2 = Vector2(NAN, NAN)

var _stats: WeaponStatsType
var _rig: Node2D
var _haft: RigidBody2D
var _head: WeaponHeadType
## One CollisionShape2D per circle in `WeaponStats.head_circle_offsets`, all
## on the single head body (ADR-0010), and the offsets they were built from.
##
## The offsets are copied rather than read back off `_stats` each tick,
## because the two are not in step: `set_weapon_stats()` swaps the stats and
## defers the rebuild, so there are ticks that run the old rig under the new
## weapon's numbers. Copying also keeps the per-tick facing turn applied to
## the authored offset rather than to the last turn's output, which is what
## stops it accumulating drift.
var _head_shapes: Array[CollisionShape2D] = []
var _head_circle_offsets: PackedVector2Array = PackedVector2Array()
## A one-sided head (`WeaponStats.flips_with_aim`) and which side of the haft
## it is on right now: mirrored is every offset's and outline point's Y
## negated. The flag is copied at build for the same reason the offsets are.
var _head_flips_with_aim: bool = false
var _head_mirrored: bool = false
var _pin: PinJoint2D
var _groove: GrooveJoint2D
var _haft_inertia: float = 1.0
## The head's velocity going into this tick's physics step, kept because the
## strike is scored on the speed the head arrived with. By the time a contact
## is reported the step has already been solved and the head has given most
## of that up to the body it hit, so reading the velocity there would score
## every strike as a tap.
var _head_velocity: Vector2 = Vector2.ZERO

## The weapon head's drawn art, and whether it is the bounding-box fallback
## rather than the weapon's own `art_outline`. Rebuilt whenever the rig is
## (`_build_head_visual`), which is also the only place either is written.
var _head_visual: Polygon2D
var _head_visual_is_fallback: bool = false

## The persistent ring drawn around the body in `identity_color`. Built once
## in `_ready()` and never touched again -- see `_build_identity_outline`.
var _identity_outline: Line2D

@onready var weapon_line: Line2D = $Haft
@onready var body_visual: Polygon2D = $Body

func _ready() -> void:
	linear_damp = 1.5
	contact_monitor = true
	max_contacts_reported = 8
	collision_layer = LAYER_WORLD
	collision_mask = LAYER_WORLD
	add_to_group("players")
	body_entered.connect(_on_body_entered)
	_style_haft()
	_build_identity_outline()
	if not start_in_round:
		# A round loop owns this player: stay out of play, inert and
		# unbuilt, until it calls start_round(). _build_rig() below checks
		# `alive` before it builds anything, so the deferred call
		# set_weapon_stats() schedules is a safe no-op until then.
		alive = false
		freeze = true
		visible = false
		collision_layer = 0
		collision_mask = 0
	_update_damage_visual()
	set_weapon_stats(weapon_stats if weapon_stats != null else DEFAULT_WEAPON_STATS)

## The rig lives beside the player rather than under it, so it is not freed
## with the player the way a child would be. Left alone it outlives its owner
## as a headless weapon: joints pointing at a freed body, and a head still on
## the head layer, still able to hit people. `eliminate()` is what frees it
## every round now; this is the same cleanup for the path where the player
## node itself goes away (a scenario tearing down its stage).
##
## Rebuilt on re-entry so this stays a cleanup path rather than a one-way
## teardown; `_build_rig` clears before it builds, so the duplicate call on a
## player's first entry is harmless.
func _exit_tree() -> void:
	_clear_rig()

func _enter_tree() -> void:
	if _stats != null:
		_build_rig.call_deferred()

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_update_weapon_input(delta)
	_update_damage_visual()
	if not _rig_is_live():
		return
	_score_swept_strike()
	_head_velocity = _head.linear_velocity
	_drive_angle(delta)
	_drive_extension(delta)
	_update_weapon_visual()

func _rig_is_live() -> bool:
	return _head != null and _head.is_inside_tree()

## Public interface the controller transport drives the weapon through.
##
## `v` is a relative input vector in the closed unit disc: its angle is the
## weapon's target angle and its length maps 0..1 onto the weapon's
## `min_reach`..`max_reach`. Longer vectors are clamped back onto the disc, so
## a caller may pass an unclamped drag without special-casing it.
## `Vector2.ZERO` means "not touching" -- the weapon holds its angle and eases
## back to rest.
##
## Non-finite components (NaN or infinity, reachable from a malformed or
## divide-by-zero packet) are rejected as `Vector2.ZERO`: `limit_length` lets
## NaN through, and one NaN reaching a force call destroys the RigidBody2D for
## the rest of the session.
func set_input_vector(v: Vector2) -> void:
	if not is_finite(v.x) or not is_finite(v.y):
		input_vector = Vector2.ZERO
		return
	input_vector = v.limit_length(1.0)

func bind_controller() -> void:
	has_controller = true

func unbind_controller() -> void:
	has_controller = false
	input_vector = Vector2.ZERO

## Where the weapon's head actually is this tick, in world space. This is the
## weapon's live geometry -- the observable a player judges aim and reach by,
## and the one thing about the rig that stays true whatever the rig is.
func weapon_head_position() -> Vector2:
	return _head.global_position if _head != null else global_position

## The non-deferred half of a weapon swap: just the bookkeeping, no rig
## rebuild. Split out so `start_round()` can reset `weapon_stats` and still
## only rebuild the rig once (in its own trailing deferred call), rather than
## once here and once more there.
func _assign_weapon_stats(stats: WeaponStatsType) -> void:
	weapon_stats = stats
	_stats = stats
	weapon_min_length = stats.min_reach
	weapon_length = clampf(weapon_length, stats.min_reach, stats.max_reach)

## Swap the weapon. Rebuilds the rig from the new stats, so reach, weight,
## responsiveness, force ceiling and head shape all change together.
func set_weapon_stats(stats: WeaponStatsType) -> void:
	_assign_weapon_stats(stats)
	# Deferred because a player is usually given its weapon while its own
	# parent is still adding it to the tree, and the rig has to be added to
	# that same parent: the weapon's bodies cannot live under the player's,
	# since a RigidBody2D driven by another one's transform fights physics.
	# It also means a caller may set position and stats in either order and
	# still get a rig built where the player ended up.
	_build_rig.call_deferred()

## Move the player and its weapon together. The rig lives beside the player in
## the tree rather than under it (a RigidBody2D cannot drive another one
## through the scene transform), so anything that relocates a live player --
## a scenario's setup, today -- has to relocate the weapon too or the joints
## get torn across the arena.
func teleport_to(pos: Vector2) -> void:
	var offset: Vector2 = pos - global_position
	global_position = pos
	linear_velocity = Vector2.ZERO
	for body: RigidBody2D in [_haft, _head]:
		if body == null:
			continue
		body.global_position += offset
		body.linear_velocity = Vector2.ZERO
		body.angular_velocity = 0.0
	# A teleport is not motion, so the head must not sweep along it: left to
	# it, the next sweep would find the arena in the way and put the head back
	# where it was moved away from.
	if _head != null:
		_head.forget_previous_position()

## Take a hit. Damage accumulates within a round; enough of it eliminates.
##
## Public because whoever landed the strike is the one who knows how hard it
## was -- the attacking player scores its own head's speed against its own
## weapon's damage and hands over the result. A no-op once eliminated: an
## eliminated player's head has no collision layer to be struck through, but
## nothing here should rely on that alone.
func take_damage(amount: float) -> void:
	if amount <= 0.0 or not alive:
		return
	damage += amount
	if damage >= DEATH_DAMAGE:
		eliminate()

## Eliminate this player, by whatever route. Both routes there -- accumulated
## damage and the kill zone -- end here, so there is one description of what
## being eliminated does rather than two that can drift apart.
##
## A round is elimination-based (ADR-0004): this is not a respawn, so the
## body freezes and hides exactly where it was, carrying whatever damage it
## had. It stays out of the round until `start_round()` brings every
## surviving and newly-joined player back for the next one, which is also
## where damage resets -- at the round boundary, not here.
func eliminate() -> void:
	if not alive:
		return
	deaths += 1
	_go_inert()
	eliminated.emit()

## Take this player out of play without it counting as an elimination.
##
## The round loop's use: once a round is decided, every player who is still
## `alive` -- the winner included -- has to go back to the same inert state
## `eliminate()` leaves a loser in, so that `start_round()` is the one path
## everyone re-enters the next round through. Scoring reads `alive` and
## `deaths` before calling this, so it never sees the winner as having died.
func leave_round() -> void:
	if not alive:
		return
	_go_inert()

## The state an out-of-play player sits in: no rig, no collision, invisible,
## frozen in place. Shared by `eliminate()` (which also counts a death) and
## `leave_round()` (which does not) so there is exactly one description of
## what "out of the round" looks like.
func _go_inert() -> void:
	alive = false
	_clear_rig()
	# Deferred: eliminate() can run from KillZone's body_entered, which fires
	# mid-physics-step while the physics server is still flushing queries --
	# changing a RigidBody2D's mode synchronously from there is refused
	# ("Can't change this state while flushing queries"). Deferring is
	# harmless from leave_round()'s ordinary call sites too.
	set_deferred("freeze", true)
	linear_velocity = Vector2.ZERO
	visible = false
	collision_layer = 0
	collision_mask = 0

## Bring this player into a fresh round at `spawn_pos`: alive, full health,
## visible, collidable, and holding either the weapon it enters with
## (`keeps_weapon = true`, per ADR-0005 the previous round's winner only) or
## the default pickaxe (`keeps_weapon = false`, everyone else -- including a
## no-survivors round, and a roster entry only now being spawned in for the
## first time).
func start_round(spawn_pos: Vector2, keeps_weapon: bool = false) -> void:
	alive = true
	damage = 0.0
	if not keeps_weapon:
		_assign_weapon_stats(DEFAULT_WEAPON_STATS)
	freeze = false
	visible = true
	collision_layer = LAYER_WORLD
	collision_mask = LAYER_WORLD
	global_position = spawn_pos
	# Hand the spawn to the physics server directly; the assignment above
	# cannot be trusted to. A body's node transform reaches the server through
	# a queued transform notification, and assigning over a transform the
	# physics sync last wrote (which marks it stale without notifying) skips
	# queuing one. That is exactly the state a ring-out leaves the body in, so
	# without this the unfrozen body was simulated where it died -- inside the
	# kill zone -- and eliminated again two ticks into every round (issue #5).
	PhysicsServer2D.body_set_state(get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, global_transform)
	linear_velocity = Vector2.ZERO
	_build_rig.call_deferred()

# --- Weapon rig -------------------------------------------------------------

func _build_rig() -> void:
	# Deferred callers (set_weapon_stats(), _enter_tree()) can land here
	# after the player has since gone inert -- a round ending, an
	# elimination landing in the same frame. Nothing should be built for a
	# player that is not in play; start_round() is what flips `alive` back
	# and asks again.
	if not alive:
		return
	_clear_rig()
	var host: Node = get_parent()
	if host == null:
		return

	var axis: Vector2 = Vector2.RIGHT.rotated(weapon_angle)

	_rig = Node2D.new()
	_rig.name = "%sWeaponRig" % name
	host.add_child(_rig)
	_rig.global_position = Vector2.ZERO

	var haft_mass: float = maxf(MIN_HAFT_MASS, _stats.mass * HAFT_MASS_FRACTION)
	_haft_inertia = haft_mass * _stats.max_reach * _stats.max_reach / 3.0
	_haft = RigidBody2D.new()
	_haft.name = "Haft"
	_haft.mass = haft_mass
	_haft.inertia = _haft_inertia
	_haft.gravity_scale = gravity_scale
	_haft.angular_damp = 0.0
	_haft.linear_damp = linear_damp
	# No collision shape, so nothing to place on a layer: the haft passes
	# through terrain, through players and through other weapons.
	_haft.collision_layer = 0
	_haft.collision_mask = 0
	_rig.add_child(_haft)
	_haft.global_position = global_position
	_haft.rotation = weapon_angle

	_head = WeaponHeadType.new()
	_head.name = "Head"
	_head.mass = _stats.mass
	_head.gravity_scale = gravity_scale
	_head.linear_damp = linear_damp
	# The head's own spin is not part of the moveset, and a free-spinning head
	# would grind against whatever it is planted on. Its shape is turned to
	# face along the haft each tick instead, so a non-circular head still
	# points where the weapon points.
	_head.lock_rotation = true
	_head.collision_layer = LAYER_HEAD
	_head.collision_mask = LAYER_WORLD | LAYER_HEAD
	# The head is small and can be swung fast; without continuous detection it
	# is exactly the shape that tunnels through a thin platform. Continuous
	# detection is necessary here but not sufficient -- it works from the
	# velocity the head has going into a step, and the joints add to that
	# during the solve -- so WeaponHead sweeps the motion that actually
	# happened afterwards as well. See WeaponHead for the measurements.
	_head.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	# The head is one body with a circle on it per circle the weapon was
	# fitted with (ADR-0010): a cluster is how a drawn head -- a crescent, a
	# blade -- gets a hitbox that follows the art without collision ever
	# becoming a traced polygon.
	_head_shapes.clear()
	_head_circle_offsets = _stats.head_circle_offsets.slice(0, _stats.head_circle_count())
	_head_flips_with_aim = _stats.flips_with_aim
	_head_mirrored = false
	for i in _stats.head_circle_count():
		var circle := CircleShape2D.new()
		circle.radius = _stats.head_circle_radii[i]
		var node := CollisionShape2D.new()
		node.name = "HeadCircle%d" % i
		node.shape = circle
		node.position = _head_circle_offsets[i]
		_head.add_child(node)
		_head_shapes.append(node)
	if _head_shapes.is_empty():
		push_warning("Player: weapon stats carry no head circles, so this head collides with nothing")
	# Copied, not handed over. GDScript Arrays are reference types, so
	# assigning `_head_shapes` itself would leave the head reading the very
	# array this player goes on mutating -- and the mutation is not
	# hypothetical: `set_weapon_stats()` defers the rebuild, `_clear_rig()`
	# clears `_head_shapes` and `_build_rig()` refills it with the *new*
	# head's circles, all while the old head is still inside the tree, still
	# not queued for deletion, and so still answering the group scan in
	# `WeaponHead._find_head_crossing` for the rest of the frame. Aliased,
	# that dying head would offer circles parented to a different body, and
	# another player's head could be corrected onto a position derived from a
	# cluster that is nowhere near it. The nodes are shared on purpose -- they
	# are the head's own children and the per-tick facing turn in
	# `_update_weapon_visual()` has to reach them -- it is the array itself
	# that each side must own.
	_head.sweep_shapes = _head_shapes.duplicate()
	# The sweep is against the world -- terrain and other players' bodies --
	# and never against this player's own body, which the head passes through.
	# Other heads are left out on purpose: a clash is two driven heads
	# contesting, and two heads each correcting themselves against the other
	# would fight rather than resolve. The head handles that pair itself, with
	# one correction between the two of them.
	_head.sweep_mask = LAYER_WORLD
	_head.sweep_exclude = [get_rid()]
	# Which of two heads does that one correction is settled by the same
	# number that settles the clash itself, so the two agree instead of
	# competing. The head does not drive with it.
	_head.drive_force = _stats.max_drive_force
	# The head has to report what it hits: a strike is head-to-player contact
	# and this is where it is noticed. Four is plenty for a nub that can only
	# be touching so many things at once.
	_head.contact_monitor = true
	_head.max_contacts_reported = 4
	_head.body_entered.connect(_on_head_hit)
	_head_visual = _build_head_visual(_stats)
	_head.add_child(_head_visual)
	_rig.add_child(_head)
	_head.global_position = global_position + axis * _stats.min_reach
	# Layers alone cannot express "every player's body except my own", so the
	# one exception is stated directly.
	_head.add_collision_exception_with(self)

	# Passive constraint only. The motor is left disabled deliberately: it has
	# no force cap on 4.6.2, so it would win every clash by definition.
	_pin = PinJoint2D.new()
	_pin.name = "BodyToHaft"
	_rig.add_child(_pin)
	_pin.global_position = global_position
	_pin.motor_enabled = false
	_pin.node_a = _pin.get_path_to(self)
	_pin.node_b = _pin.get_path_to(_haft)

	# The slider half of the rig. Its groove runs along the haft from
	# min_reach to max_reach, so reach is a physical limit on where the head
	# can be rather than a number the drive is trusted to respect.
	_groove = GrooveJoint2D.new()
	_groove.name = "HaftToHead"
	_rig.add_child(_groove)
	_groove.global_position = global_position + axis * _stats.min_reach
	# A GrooveJoint2D's groove runs along its own local +Y; this turns that
	# axis onto the haft's forward direction.
	_groove.global_rotation = weapon_angle - PI * 0.5
	_groove.length = maxf(1.0, _stats.max_reach - _stats.min_reach)
	_groove.initial_offset = 0.0
	_groove.node_a = _groove.get_path_to(_haft)
	_groove.node_b = _groove.get_path_to(_head)

func _clear_rig() -> void:
	if _rig == null:
		return
	# Joints first: a half-freed rig that still constrains the body would
	# drag the player around for the rest of the frame.
	if _pin != null:
		_pin.free()
	if _groove != null:
		_groove.free()
	# Not remove_child(): this runs from _exit_tree too, where the parent is
	# mid-removal and refuses it. queue_free() unparents on its own; the only
	# part that cannot wait for end of frame is the head continuing to collide,
	# so its layers are cleared now.
	if _head != null:
		_head.collision_layer = 0
		_head.collision_mask = 0
	# Renamed on the way out: a mid-round swap (a pickup, issue #14) builds the
	# new rig this same frame, and while this one waits for end-of-frame
	# deletion it would hold the "<name>WeaponRig" name, so Godot would
	# silently rename the live rig instead.
	_rig.name = "%sRetiredRig" % name
	_rig.queue_free()
	_rig = null
	_haft = null
	_head = null
	_head_shapes.clear()
	_head_circle_offsets = PackedVector2Array()
	_head_flips_with_aim = false
	_head_mirrored = false
	_pin = null
	_groove = null
	_head_visual = null
	_head_visual_is_fallback = false

func _head_distance() -> float:
	return (_head.global_position - global_position).length()

## Angle drive: clamped torque on the haft, per ADR-0006.
##
## Inside its limits this asks for exactly the angular velocity that lands on
## the commanded angle next tick, which is what keeps aim 1:1 with the drag
## instead of lagging behind it by a spring's worth of error. Two things bound
## that: the weapon's slew limit, and how fast it could still stop from here.
## The stopping bound is what a clamped drive needs and an uncapped engine
## motor does not -- ask for a speed the weapon cannot brake out of and it
## sails past the angle the player pointed at and rings around it.
##
## The torque that would take is then clamped to what the weapon can actually
## push with: `max_drive_force` through the lever arm to the head.
func _drive_angle(delta: float) -> void:
	var error: float = wrapf(weapon_angle - _haft.rotation, -PI, PI)
	var lever: float = maxf(_head_distance(), _stats.min_reach)
	var inertia: float = _haft_inertia + _stats.mass * lever * lever
	var max_torque: float = _stats.max_drive_force * lever
	var stop_limit: float = sqrt(2.0 * (max_torque / inertia) * absf(error))
	var limit: float = minf(_stats.drive_speed, stop_limit)
	var target_w: float = clampf(error / delta, -limit, limit)
	var torque: float = (target_w - _haft.angular_velocity) * inertia / delta
	_haft.apply_torque(clampf(torque, -max_torque, max_torque))

## Extension drive: clamped force along the haft, per ADR-0006.
##
## Applied as an actuator between the two ends of the weapon -- the head takes
## the force, the body takes the reaction -- rather than as a shove on the
## head alone. That pairing is what makes a planted head able to move anyone:
## push out against something solid and the body is thrown the other way,
## which is the whole moveset.
##
## Same shape as the angle drive: ask for the velocity that lands on the
## commanded reach, bounded by the weapon's extension speed and by what it
## could still stop from, then clamp the force to `max_drive_force`. Easing
## back to rest needs nothing special here, because the commanded reach is
## what eases (see `_update_weapon_input`).
func _drive_extension(delta: float) -> void:
	var axis: Vector2 = Vector2.RIGHT.rotated(_haft.rotation)
	var reach: float = (_head.global_position - global_position).dot(axis)
	var error: float = weapon_length - reach
	var max_force: float = _stats.max_drive_force
	# Both ends move, so the mass the drive is working against is the pair's
	# reduced mass, not the head's alone.
	var reduced_mass: float = 1.0 / (1.0 / _stats.mass + 1.0 / mass)
	var stop_limit: float = sqrt(2.0 * (max_force / reduced_mass) * absf(error))
	var limit: float = minf(_stats.extend_speed, stop_limit)
	var target_v: float = clampf(error / delta, -limit, limit)
	var relative_v: float = (_head.linear_velocity - linear_velocity).dot(axis)
	var force: float = clampf((target_v - relative_v) * reduced_mass / delta, -max_force, max_force)
	_head.apply_central_force(axis * force)
	apply_central_force(-axis * force)

func _update_weapon_visual() -> void:
	var pts := weapon_line.points
	pts[1] = to_local(_head.global_position)
	weapon_line.points = pts
	# The head body is rotation-locked, so the head's facing lives on what
	# hangs off it: every collision circle and the drawn art are turned to
	# point along the haft here. The circles are placed from the authored
	# offset each tick rather than turned from wherever they sat last tick --
	# a circle off the head's centre has to orbit the anchor, not spin in
	# place, and re-deriving it cannot accumulate drift.
	var facing: float = _haft.rotation - _head.rotation
	_update_head_mirror()
	var mirror := Vector2(1.0, -1.0) if _head_mirrored else Vector2.ONE
	for i in _head_shapes.size():
		var node: CollisionShape2D = _head_shapes[i]
		node.position = (_head_circle_offsets[i] * mirror).rotated(facing)
		node.rotation = facing
	_head_visual.rotation = facing

## Puts a one-sided head on the side of the haft that keeps it the same way up
## on screen: as authored while the aim points right, mirrored across the haft
## while it points left. Near straight up or down it holds whichever side it
## had until the aim is HEAD_FLIP_DEADBAND past the vertical, so a thumb
## wobbling on the vertical does not flip it every tick.
##
## The outline is rewritten point for point rather than the visual being
## scaled by -1: `weapon_head_visual_polygon()` and `weapon_head_circles()`
## both report head-local space with only the facing turn taken out, so the
## drawn polygon and the circles have to be mirrored the same way -- in the
## data -- or the art and the hitbox would part on one side only.
func _update_head_mirror() -> void:
	if not _head_flips_with_aim:
		return
	var across: float = cos(weapon_angle)
	var mirrored: bool = _head_mirrored
	if across < -sin(HEAD_FLIP_DEADBAND):
		mirrored = true
	elif across > sin(HEAD_FLIP_DEADBAND):
		mirrored = false
	if mirrored == _head_mirrored:
		return
	_head_mirrored = mirrored
	var outline: PackedVector2Array = _head_visual.polygon
	for i in outline.size():
		outline[i].y = -outline[i].y
	_head_visual.polygon = outline

# --- Presentation: identity and damage --------------------------------------
#
# AC-16/AC-17 and the D4 scope change. Three rules, all in this block:
#
#   * The body fill is the only thing damage is allowed to touch, and it is
#     free to converge toward DAMAGE_FILL_COLOR for every player alike --
#     that is what "how hurt someone is shows on their body" means.
#   * `identity_color` is what a player is found by. It never changes after
#     `_ready()`, and it is drawn in exactly two places: the outline traced
#     once around the body, and the weapon head's fill.
#   * The weapon head is drawn as `WeaponStats.art_outline` and collides as
#     the circles fitted inside it (ADR-0010), so a hit lands where the art
#     is. The two cannot drift the way they had (a circular hitbox drawn as a
#     square): `weapon_head_circles_within_art` in the scenario runner reads
#     both back off a built rig and checks every circle against the drawn
#     polygon.

## Traces the body's own polygon once, in `identity_color`, and never touches
## it again. This is what stays legible once the fill has reddened past the
## point of being recognisable as anyone in particular.
func _build_identity_outline() -> void:
	var outline := Line2D.new()
	outline.name = "IdentityOutline"
	var pts: PackedVector2Array = body_visual.polygon.duplicate()
	if pts.size() > 0:
		pts.append(pts[0])
	outline.points = pts
	outline.width = 4.0
	outline.default_color = identity_color
	outline.begin_cap_mode = Line2D.LINE_CAP_ROUND
	outline.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(outline)
	_identity_outline = outline

## Gives the haft a taper and a haft-like colour instead of a bar of uniform
## width and stock white, so it reads as a handle rather than a floating line.
## Purely presentational -- the haft has no collision shape to derive a width
## from (it collides with nothing, per CONTEXT.md).
func _style_haft() -> void:
	weapon_line.default_color = HAFT_COLOR
	weapon_line.width = HAFT_BASE_WIDTH
	weapon_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	weapon_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 1.0))
	taper.add_point(Vector2(1.0, HAFT_TIP_WIDTH / HAFT_BASE_WIDTH))
	weapon_line.width_curve = taper

## Repaints the body fill from `identity_color` (at zero damage) toward
## `DAMAGE_FILL_COLOR` (at `DEATH_DAMAGE`). Runs every physics tick rather
## than only from `take_damage()`, so the fill stays true to `damage` however
## it changed -- a strike, `start_round()`'s reset, or a scenario setting it
## directly, which is how this suite's own scenarios read and drive it.
func _update_damage_visual() -> void:
	var t: float = clampf(damage / DEATH_DAMAGE, 0.0, 1.0)
	body_visual.color = identity_color.lerp(DAMAGE_FILL_COLOR, t)

## Draws the weapon head as the art it was fitted to (ADR-0010): the weapon's
## own `art_outline`, in `identity_color`.
##
## A stats resource without a usable outline -- fewer than three points --
## falls back to the bounding box of its collision circles in
## `FALLBACK_HEAD_COLOR`, a colour that belongs to no player, so a weapon
## authored without art is visibly wrong rather than quietly guessed at. That
## is the same stance the shape-derived silhouette this replaces took, and
## for the same reason: the failure being guarded is the drawing and the
## hitbox parting ways. See `weapon_head_visual_is_fallback()`.
func _build_head_visual(stats: WeaponStatsType) -> Polygon2D:
	var visual := Polygon2D.new()
	visual.name = "HeadVisual"
	if stats.art_outline.size() >= 3:
		visual.polygon = stats.art_outline
		visual.color = identity_color
		_head_visual_is_fallback = false
	else:
		visual.polygon = _rect_from_bounds(_head_circle_bounds(stats))
		visual.color = FALLBACK_HEAD_COLOR
		_head_visual_is_fallback = true
		push_warning("Player: weapon stats carry no art outline (%d points); falling back to the head circles' bounding box" % stats.art_outline.size())
	return visual

## The box the head's collision circles occupy, in head-local space. Only the
## fallback needs it: a head with no art still has to be drawn as something,
## and the circles are the only statement of where the head is.
func _head_circle_bounds(stats: WeaponStatsType) -> Rect2:
	var bounds := Rect2()
	for i in stats.head_circle_count():
		var centre: Vector2 = stats.head_circle_offsets[i]
		var radius: float = stats.head_circle_radii[i]
		var circle := Rect2(centre - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
		bounds = circle if i == 0 else bounds.merge(circle)
	return bounds

func _rect_from_bounds(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)])

## The colour of the persistent identity outline as actually drawn, rather
## than the `identity_color` setting a caller trusts to have produced it.
func identity_outline_color() -> Color:
	return _identity_outline.default_color if _identity_outline != null else identity_color

## The colour the weapon's head is actually drawn in. Constant at any damage
## level (ADR-0005) for a known head shape; see `weapon_head_visual_is_fallback()`
## for the one case where it is deliberately not `identity_color`.
func weapon_head_color() -> Color:
	return _head_visual.color if _head_visual != null else identity_color

## The body's own fill colour -- the one visual here that `damage` is allowed
## to change.
func body_fill_color() -> Color:
	return body_visual.color

## The polygon the weapon's head is drawn as, in the head's local space.
## Exposed so a scenario can check the head's art against the head's hitbox
## without reaching into the rig's internals.
func weapon_head_visual_polygon() -> PackedVector2Array:
	return _head_visual.polygon if _head_visual != null else PackedVector2Array()

## The head's collision circles as the rig actually built them -- each an
## `offset` and a `radius` -- with the haft-facing turn taken back out, so
## they are in the same head-local space as `weapon_head_visual_polygon()`
## and the two can be compared directly. The pair is what ADR-0010's
## guarantee is about, and reading both off a live rig is how a scenario
## checks it without being told by the resource they both came from.
func weapon_head_circles() -> Array[Dictionary]:
	var circles: Array[Dictionary] = []
	if _head_visual == null:
		return circles
	var facing: float = _head_visual.rotation
	for node: CollisionShape2D in _head_shapes:
		var circle := node.shape as CircleShape2D
		if circle == null:
			continue
		circles.append({"offset": node.position.rotated(-facing), "radius": circle.radius})
	return circles

## Whether the head is drawn as the bounding box of its circles -- the
## fallback for a weapon with no art -- rather than as its own `art_outline`.
func weapon_head_visual_is_fallback() -> bool:
	return _head_visual_is_fallback

# --- Input ------------------------------------------------------------------

func _update_weapon_input(delta: float) -> void:
	var effective_vector: Vector2 = _get_effective_vector(delta)
	if effective_vector != Vector2.ZERO:
		weapon_angle = effective_vector.angle()
		weapon_length = lerp(_stats.min_reach, _stats.max_reach, effective_vector.length())
	else:
		# Released: hold the last angle and ease the extension back to rest
		# over several physics frames rather than snapping or drifting.
		weapon_length = move_toward(weapon_length, _stats.min_reach, _stats.rest_return_speed * delta)

func _get_effective_vector(delta: float) -> Vector2:
	if has_controller:
		return input_vector
	match debug_source:
		DebugSource.MOUSE:
			return _update_mouse_vector()
		DebugSource.KEYBOARD:
			return _update_keyboard_vector(delta)
		_:
			return Vector2.ZERO

## Mirrors the phone's `pointerdown` anchor semantics: the drag is relative to
## where the button went down, and while no button is held the source reports
## `Vector2.ZERO` -- "not touching" -- so the weapon eases to rest exactly as a
## released touch does. Without the button gate the mouse asserts a non-zero
## vector permanently, which both snaps the weapon the instant a controller
## unbinds and silently drives a player during headless runs.
func _update_mouse_vector() -> Vector2:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_mouse_anchor = Vector2(NAN, NAN)
		return Vector2.ZERO
	var mouse: Vector2 = get_global_mouse_position()
	if not is_finite(_mouse_anchor.x):
		_mouse_anchor = mouse
	var v: Vector2 = (mouse - _mouse_anchor) / mouse_drag_radius
	return v.limit_length(1.0)

func _update_keyboard_vector(delta: float) -> Vector2:
	var rotate_dir := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	var extend_dir := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
	_keyboard_angle += rotate_dir * rotate_speed * delta
	var extend_range: float = _stats.max_reach - _stats.min_reach
	var t_speed: float = reach_speed / extend_range if extend_range > 0.0 else 0.0
	# Keep t just above zero so rotation keeps responding even when fully
	# retracted; a real zero vector is reserved for "not touching".
	_keyboard_t = clamp(_keyboard_t + extend_dir * t_speed * delta, KEYBOARD_MIN_T, 1.0)
	return Vector2.RIGHT.rotated(_keyboard_angle) * _keyboard_t

# --- Knockback and damage ---------------------------------------------------

## Body-to-body contact: a shove, and nothing else.
##
## Deliberately no damage here, and this is the load-bearing half of
## ADR-0005's split rather than an omission. Knockback is a movement effect:
## it moves people, and that is the whole of it. Damage comes from the swing,
## so that winning is about swinging well rather than about having momentum.
func _on_body_entered(body: Node) -> void:
	if body == self or not body.is_in_group("players"):
		return
	var rel_vel: Vector2 = linear_velocity - body.linear_velocity
	if rel_vel.length() > knockback_threshold:
		var dir: Vector2 = (body.global_position - global_position).normalized()
		var speed: float = minf(rel_vel.length(), max_knockback_speed)
		body.apply_central_impulse(dir * speed * knockback_scale)

## A strike the head's own sweep caught, which is where every hard one shows
## up.
##
## The head stops a fast strike itself, before the solver has generated a
## contact for it (see `WeaponHead.swept_into`), so `_on_head_hit` below only
## ever sees the aftermath: measured on a 2468 px/s swing, the contact the
## engine reported carried 18 px/s. Scoring strikes off that alone would call
## every committed swing a tap and leave only slow contacts hurting anyone,
## which is the design exactly backwards.
##
## The speed used is the one the sweep took out of the head -- the component
## heading into what it hit -- so a head skimming along a surface is not
## scored as having swung into it. Read here rather than in the head so that
## a death, which relocates two bodies, happens between physics steps rather
## than inside one.
func _score_swept_strike() -> void:
	var hit: Object = _head.swept_into
	var speed: float = _head.swept_speed
	_head.swept_into = null
	_head.swept_speed = 0.0
	var struck: Node = hit as Node
	if struck == null or struck == self or not struck.is_in_group("players"):
		return
	_land_strike(struck, speed)

## This weapon's head touched something slowly enough for the solver to be
## the one that noticed. If it was another player, that is a strike too --
## a gentle one, and usually worth nothing once scored.
##
## The head is on its own collision layer and holds an explicit exception for
## its own player, so what arrives here is terrain, other players' bodies and
## other players' heads. Only a player is a strike; a head meeting a head is
## a clash, which is `WeaponHead`'s pair correction and the solver's business
## between them, and nobody's damage.
func _on_head_hit(body: Node) -> void:
	if body == self or not body.is_in_group("players") or _head == null:
		return
	var to_body: Vector2 = body.global_position - _head.global_position
	if to_body.length_squared() == 0.0:
		return
	# Only the part of the head's motion heading into the player counts, so
	# that a head skimming past somebody at speed is not scored as if it had
	# swung into them.
	_land_strike(body, _head_velocity.dot(to_body.normalized()))

## Both strike paths end here: score the speed, hand the damage over, and
## report the strike for `strike_landed`. Nothing is reported for a victim
## already out of play, or a contact too slow to have been a swing at all.
func _land_strike(victim: Node, speed: float) -> void:
	if not victim.alive:
		return
	var amount: float = _strike_damage(speed)
	if amount <= 0.0 and speed <= knockback_threshold:
		return
	var point: Vector2 = _strike_point(victim)
	victim.take_damage(amount)
	strike_landed.emit(victim, amount, point, not victim.alive)

## Where the head met `victim`: the leading edge of whichever head circle is
## nearest them.
func _strike_point(victim: Node2D) -> Vector2:
	var best: Vector2 = _head.global_position
	var best_distance: float = INF
	var radius: float = 0.0
	for node: CollisionShape2D in _head_shapes:
		if node == null or not node.is_inside_tree() or not (node.shape is CircleShape2D):
			continue
		var distance: float = node.global_position.distance_squared_to(victim.global_position)
		if distance < best_distance:
			best_distance = distance
			best = node.global_position
			radius = (node.shape as CircleShape2D).radius
	return best + (victim.global_position - best).normalized() * radius

## What a strike at this head speed takes off, scaled per ADR-0005: the
## weapon's `damage` is what a full-speed committed swing does, a slow
## contact does nothing, and everything between is proportional.
##
## Tuned high on purpose. The swing is the only damage source in the game --
## there are no ranged weapons -- so a hit has to carry the pace of a whole
## exchange. Measured across the swing the moveset actually produces, the
## pickaxe's 34 comes out at 14 for a flick and 44 for a committed full-reach
## sweep: three clean strikes to kill, and two if the head is carried in by a
## body already moving. Stick Fight's punch weight would be ten or more and
## rounds would drag, which ADR-0005 warns about by name.
func _strike_damage(speed: float) -> float:
	var over: float = speed - MIN_STRIKE_SPEED
	if over <= 0.0:
		return 0.0
	var strike_scale: float = minf(over / (FULL_STRIKE_SPEED - MIN_STRIKE_SPEED), MAX_STRIKE_SCALE)
	return minf(_stats.damage * strike_scale, MAX_STRIKE_DAMAGE)
