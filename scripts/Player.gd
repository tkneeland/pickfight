extends RigidBody2D

## Prototype movement: a single pole/arm that plants against the world and
## pushes or swings the body, approximating Getting Over It's hammer.
## Combat: colliding into another player fast enough knocks them back,
## approximating Stick Fight's scrappy melee.
##
## Per ADR-0003, the arm is driven by a relative unit-disc input vector
## (Vector2.ZERO means "not touching") rather than an absolute cursor
## position. A bound controller supplies that vector over the network; the
## debug sources below (mouse, keyboard) exist only for host-side testing and
## are ignored entirely while a controller is bound.

enum DebugSource { NONE, MOUSE, KEYBOARD }

const KEYBOARD_MIN_T: float = 0.001

@export var arm_min_length: float = 20.0
@export var arm_max_length: float = 140.0
@export var pole_stiffness: float = 6000.0
@export var reach_speed: float = 220.0
@export var rotate_speed: float = 3.0
@export var knockback_threshold: float = 300.0
@export var knockback_scale: float = 0.5
@export var debug_source: DebugSource = DebugSource.NONE
@export var mouse_drag_radius: float = 140.0
@export var rest_return_speed: float = 400.0

var input_vector: Vector2 = Vector2.ZERO
var has_controller: bool = false

var arm_length: float = 80.0
var arm_angle: float = 0.0
var tip_planted: bool = false
var tip_global_pos: Vector2 = Vector2.ZERO

var _keyboard_angle: float = 0.0
var _keyboard_t: float = 0.5

@onready var arm: Line2D = $Arm
@onready var tip_ray: RayCast2D = $Arm/TipRay

func _ready() -> void:
	arm_length = clamp(80.0, arm_min_length, arm_max_length)
	linear_damp = 1.5
	angular_damp = 3.0
	contact_monitor = true
	max_contacts_reported = 8
	add_to_group("players")
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	_update_arm_input(delta)
	_update_tip()
	_apply_pole_force()

## Public interface for the controller transport (next deliverable).
func set_input_vector(v: Vector2) -> void:
	input_vector = v.limit_length(1.0)

func bind_controller() -> void:
	has_controller = true

func unbind_controller() -> void:
	has_controller = false
	input_vector = Vector2.ZERO

func _update_arm_input(delta: float) -> void:
	var effective_vector: Vector2 = _get_effective_vector(delta)
	if effective_vector != Vector2.ZERO:
		arm_angle = effective_vector.angle()
		arm_length = lerp(arm_min_length, arm_max_length, effective_vector.length())
	else:
		# Released: hold the last angle and ease the extension back to rest
		# over several physics frames rather than snapping or drifting.
		arm_length = move_toward(arm_length, arm_min_length, rest_return_speed * delta)

func _get_effective_vector(delta: float) -> Vector2:
	if has_controller:
		return input_vector
	match debug_source:
		DebugSource.MOUSE:
			var v: Vector2 = (get_global_mouse_position() - global_position) / mouse_drag_radius
			return v.limit_length(1.0)
		DebugSource.KEYBOARD:
			return _update_keyboard_vector(delta)
		_:
			return Vector2.ZERO

func _update_keyboard_vector(delta: float) -> Vector2:
	var rotate_dir := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	var extend_dir := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
	_keyboard_angle += rotate_dir * rotate_speed * delta
	var extend_range: float = arm_max_length - arm_min_length
	var t_speed: float = reach_speed / extend_range if extend_range > 0.0 else 0.0
	# Keep t just above zero so rotation keeps responding even when fully
	# retracted; a real zero vector is reserved for "not touching".
	_keyboard_t = clamp(_keyboard_t + extend_dir * t_speed * delta, KEYBOARD_MIN_T, 1.0)
	return Vector2.RIGHT.rotated(_keyboard_angle) * _keyboard_t

func _update_tip() -> void:
	var tip_local: Vector2 = Vector2.RIGHT.rotated(arm_angle) * arm_length
	var pts := arm.points
	pts[1] = tip_local
	arm.points = pts
	tip_ray.target_position = tip_local
	tip_ray.force_raycast_update()
	tip_planted = tip_ray.is_colliding()
	tip_global_pos = tip_ray.get_collision_point() if tip_planted else (global_position + tip_local)

func _apply_pole_force() -> void:
	if not tip_planted:
		return
	var to_body: Vector2 = global_position - tip_global_pos
	var current_dist: float = to_body.length()
	if current_dist < 1.0:
		return
	var dist_error: float = current_dist - arm_length
	apply_central_force(-to_body.normalized() * dist_error * pole_stiffness)

func _on_body_entered(body: Node) -> void:
	if body == self or not body.is_in_group("players"):
		return
	var rel_vel: Vector2 = linear_velocity - body.linear_velocity
	if rel_vel.length() > knockback_threshold:
		var dir: Vector2 = (body.global_position - global_position).normalized()
		body.apply_central_impulse(dir * rel_vel.length() * knockback_scale)
