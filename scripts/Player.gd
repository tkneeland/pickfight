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
## strikes, blocks and plants. Both joints are passive constraints with no
## motor: on Godot 4.6.2 `PinJoint2D`'s motor has no force or torque cap and
## `GrooveJoint2D` has no actuation at all, so the drive is hand-written here
## and clamped at `WeaponStats.max_drive_force` -- the cap is what lets a
## weaker weapon lose a contest instead of deadlocking.
##
## Combat: colliding into another player fast enough knocks them back,
## approximating Stick Fight's scrappy melee. Damage is carried as a weapon
## stat but is not applied by anything yet.
##
## Per ADR-0003, the weapon is driven by a relative unit-disc input vector
## (Vector2.ZERO means "not touching") rather than an absolute cursor
## position. A bound controller supplies that vector over the network; the
## debug sources below (mouse, keyboard) exist only for host-side testing and
## are ignored entirely while a controller is bound. The mouse source only
## reports a vector while a mouse button is held, so like a phone it asserts
## nothing when nobody is touching it.

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

## Which weapon this player is holding. Swappable at runtime through
## `set_weapon_stats()`; the pickaxe is the only instance today.
@export var weapon_stats: WeaponStats
@export var rotate_speed: float = 3.0
@export var reach_speed: float = 220.0
@export var knockback_threshold: float = 300.0
@export var knockback_scale: float = 0.5
@export var debug_source: DebugSource = DebugSource.NONE
@export var mouse_drag_radius: float = 140.0

var input_vector: Vector2 = Vector2.ZERO
var has_controller: bool = false

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

var _stats: WeaponStats
var _rig: Node2D
var _haft: RigidBody2D
var _head: RigidBody2D
var _head_shape: CollisionShape2D
var _pin: PinJoint2D
var _groove: GrooveJoint2D
var _haft_inertia: float = 1.0

@onready var weapon_line: Line2D = $Weapon

func _ready() -> void:
	linear_damp = 1.5
	angular_damp = 3.0
	contact_monitor = true
	max_contacts_reported = 8
	collision_layer = LAYER_WORLD
	collision_mask = LAYER_WORLD
	add_to_group("players")
	body_entered.connect(_on_body_entered)
	set_weapon_stats(weapon_stats if weapon_stats != null else WeaponStats.new())

## The rig lives beside the player rather than under it, so it is not freed
## with the player the way a child would be. Left alone it outlives its owner
## as a headless weapon: joints pointing at a freed body, and a head still on
## the head layer, still able to hit people. Nothing frees a player yet, but
## death lands in the next deliverable and the round loop will free every
## player every round.
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
	_update_weapon_input(delta)
	if not _rig_is_live():
		return
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

## Swap the weapon. Rebuilds the rig from the new stats, so reach, weight,
## responsiveness, force ceiling and head shape all change together.
func set_weapon_stats(stats: WeaponStats) -> void:
	weapon_stats = stats
	_stats = stats
	weapon_min_length = stats.min_reach
	weapon_length = clampf(weapon_length, stats.min_reach, stats.max_reach)
	# Deferred because a player is usually given its weapon while its own
	# parent is still adding it to the tree, and the rig has to be added to
	# that same parent: the weapon's bodies cannot live under the player's,
	# since a RigidBody2D driven by another one's transform fights physics.
	# It also means a caller may set position and stats in either order and
	# still get a rig built where the player ended up.
	_build_rig.call_deferred()

## Move the player and its weapon together. The rig lives beside the player in
## the tree rather than under it (a RigidBody2D cannot drive another one
## through the scene transform), so anything that relocates a player -- the
## kill zone's respawn, a scenario's setup -- has to relocate the weapon too
## or the joints get torn across the arena.
func teleport_to(pos: Vector2) -> void:
	var offset: Vector2 = pos - global_position
	global_position = pos
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	for body: RigidBody2D in [_haft, _head]:
		if body == null:
			continue
		body.global_position += offset
		body.linear_velocity = Vector2.ZERO
		body.angular_velocity = 0.0

# --- Weapon rig -------------------------------------------------------------

func _build_rig() -> void:
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

	_head = RigidBody2D.new()
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
	# is exactly the shape that tunnels through a thin platform.
	_head.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	_head_shape = CollisionShape2D.new()
	_head_shape.shape = _stats.head_shape
	_head.add_child(_head_shape)
	var head_visual := Polygon2D.new()
	var r: float = _stats.head_draw_radius()
	head_visual.polygon = PackedVector2Array([
		Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r)])
	head_visual.color = _stats.head_color
	_head.add_child(head_visual)
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
	_rig.queue_free()
	_rig = null
	_haft = null
	_head = null
	_head_shape = null
	_pin = null
	_groove = null

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
	_head_shape.global_rotation = _haft.rotation

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

# --- Knockback --------------------------------------------------------------

func _on_body_entered(body: Node) -> void:
	if body == self or not body.is_in_group("players"):
		return
	var rel_vel: Vector2 = linear_velocity - body.linear_velocity
	if rel_vel.length() > knockback_threshold:
		var dir: Vector2 = (body.global_position - global_position).normalized()
		body.apply_central_impulse(dir * rel_vel.length() * knockback_scale)
