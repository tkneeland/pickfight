extends RigidBody2D

## Prototype movement: a single pole/arm that plants against the world and
## pushes or swings the body, approximating Getting Over It's hammer.
## Combat: colliding into another player fast enough knocks them back,
## approximating Stick Fight's scrappy melee.

@export var use_mouse: bool = true
@export var arm_min_length: float = 20.0
@export var arm_max_length: float = 140.0
@export var pole_stiffness: float = 6000.0
@export var reach_speed: float = 220.0
@export var rotate_speed: float = 3.0
@export var knockback_threshold: float = 300.0
@export var knockback_scale: float = 0.5

var arm_length: float = 80.0
var arm_angle: float = 0.0
var tip_planted: bool = false
var tip_global_pos: Vector2 = Vector2.ZERO

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

func _update_arm_input(delta: float) -> void:
	if use_mouse:
		var to_mouse: Vector2 = get_global_mouse_position() - global_position
		if to_mouse.length() > 1.0:
			arm_angle = to_mouse.angle()
		arm_length = clamp(to_mouse.length(), arm_min_length, arm_max_length)
	else:
		# Temporary keyboard fallback so a second local player can be tested
		# on the same machine. Real local multiplayer needs a per-player
		# analog input source (gamepad stick) instead of the shared mouse.
		var rotate_dir := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		var extend_dir := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
		arm_angle += rotate_dir * rotate_speed * delta
		arm_length = clamp(arm_length + extend_dir * reach_speed * delta, arm_min_length, arm_max_length)

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
