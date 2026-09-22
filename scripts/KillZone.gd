extends Area2D

## Temporary "ring out" handling: teleport a fallen player back to the
## arena instead of properly eliminating/scoring them.

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("players"):
		body.global_position = Vector2(0, -200)
		body.linear_velocity = Vector2.ZERO
		body.angular_velocity = 0.0
